# Stan and Parallel R: Known Issues

## The problem with fork-based parallelism (mclapply) and Stan

`parallel::mclapply` uses `fork()` to create child processes. After forking, children
share the parent's memory, file handles, and temp directory. This conflicts with
`cmdstanr`, which manages subprocesses and temp files assuming they are private to the
R process.

### Known failure modes

**1. Output file collisions (cmdstanr Issue [#326](https://github.com/stan-dev/cmdstanr/issues/326))**

When cmdstanr runs inside `mclapply`, forked processes generate Stan output CSV files
with identical names. Files overwrite each other, producing NAs in extracted draws.
This was patched in 2020 by incorporating `Sys.getpid()` into filenames, but other
shared-state issues may remain.

**2. Shared tempdir()**

After `fork()`, all child processes share the parent's `tempdir()`. R's `tempdir()` was
designed for a single process — [the R parallel docs](https://stat.ethz.ch/R-manual/R-devel/library/parallel/doc/parallel.pdf)
explicitly warn about this. cmdstanr writes output CSVs and diagnostics to temp
directories, so multiple forked workers writing simultaneously can cause race conditions.

**3. Shared file handles**

Forked processes inherit open file handles from the parent. cmdstanr manages handles
for Stan's stdout/stderr output. Multiple children interacting with the same handles
produces unpredictable results.

**4. HPC-specific issues**

People have reported cmdstanr not parallelizing on clusters despite working locally:
- [Stan Forums: running cmdstanr in parallel on computing cluster](https://discourse.mc-stan.org/t/running-cmdstanr-in-parallel-on-computing-cluster/29735):
  MKL threading conflicts and job scheduler interference
- [Stan Forums: parallel with cmdstanr](https://discourse.mc-stan.org/t/parallel-with-cmdstanr/11694):
  general discussion of parallel strategies

### Why this matters

`mclapply` is the simplest R parallelism tool and gives excellent speedups for pure R
code (we measured 6.9x on 8 cores with OLS+bootstrap). But it is **not safe for Stan
workloads** because Stan's execution model (compile → spawn executable → read output
files) requires process-private state that fork() does not provide.

## Safe alternatives for parallel Stan

### crew (recommended)

[crew](https://wlandau.github.io/crew/) spawns workers as **independent R processes**
(not forks). Each worker has its own memory, temp directory, and file handles. This
avoids all fork-related issues. Use via `targets` + `crew_controller_local()`.

On ARC, crew requires `host = "127.0.0.1"` because default hostname resolution fails
on compute nodes.

### SLURM job arrays

Each array task is a fully independent SLURM job with its own R process. Zero shared
state. The most robust option, at the cost of per-job R startup overhead and needing
to combine results afterward.

### future with multisession

`future::plan(multisession)` spawns separate R processes (like crew), not forks. This
is safe for Stan. Note: `future::plan(multicore)` **does** use forks and has the same
problems as `mclapply`.

### furrr (tidyverse-friendly)

[furrr](https://furrr.futureverse.org/) provides `future_map()` and friends — a
tidyverse-style interface to future. `furrr::future_map_dfr()` with
`plan(multisession)` gives tidy tibble output with parallel execution via separate
processes. Safe for Stan, minimal boilerplate.

### parallel::makePSOCKcluster

`parLapply` with a PSOCK cluster also spawns independent R processes. Safe for Stan,
but more manual setup than crew or future.

## Threading within Stan

Separate from R-level parallelism, Stan itself can use multiple threads per chain via
`threads_per_chain`. This uses OpenMP threading inside the Stan executable. On ARC:

- Set `OMP_NUM_THREADS=1` in SLURM scripts to prevent BLAS thread oversubscription
- If using `threads_per_chain > 1`, ensure the Stan model uses `reduce_sum()` or
  other parallel-aware functions
- Total threads = (R workers) × (chains per worker) × (threads per chain) — must not
  exceed allocated cores

## References

- [cmdstanr Issue #326: mclapply file collisions](https://github.com/stan-dev/cmdstanr/issues/326)
- [R parallel package documentation](https://stat.ethz.ch/R-manual/R-devel/library/parallel/doc/parallel.pdf)
- [Henrik Bengtsson on fork safety in R](https://github.com/HenrikBengtsson/Wishlist-for-R/issues/94)
- [Stan Forums: cmdstanr on computing clusters](https://discourse.mc-stan.org/t/running-cmdstanr-in-parallel-on-computing-cluster/29735)
- [crew package documentation](https://wlandau.github.io/crew/)
