# Parallel R on ARC

Systematic comparison of parallel R strategies on Oxford's ARC HPC cluster.

## Why?

A [targets](https://docs.ropensci.org/targets/) + [crew](https://wlandau.github.io/crew/) pipeline that works perfectly on a laptop hangs via `sbatch` on ARC at scale.
Rather than continuing to guess, this repo builds understanding from the ground up by running the same simulation task through every common parallelization strategy.

## The simulation task

`R/sim_task.R` defines a single function `sim_task(rep_id)` that:

1. Generates correlated data (n=2000, p=50 covariates with AR(1) correlation)
2. Fits OLS
3. Runs 2000 bootstrap resamples for inference

Each rep takes ~9 seconds on ARC (Cascade Lake @ 2.90GHz), ~3 seconds on Apple Silicon.

## Strategies

### Phase 1: OLS + bootstrap (no Stan)

| Script | Strategy | Parallelism | Status |
|--------|----------|-------------|--------|
| `slurm/01_sequential.slurm` | For loop | None (baseline) | Works |
| `slurm/02_mclapply.slurm` | `parallel::mclapply` | Multi-core (fork) | Works |
| `slurm/03_future.slurm` | `future::plan(multisession)` | Multi-core (separate processes) | Works |
| `slurm/04_job_array.slurm` | SLURM job array | Independent jobs | Works |
| `slurm/05_targets_basic.slurm` | `targets` + `tar_rep` | None (sequential targets) | Works |
| `slurm/06_targets_crew.slurm` | `targets` + `tar_rep` + `crew` | Multi-core via crew | Works (at 10 branches) |
| `slurm/07_targets_future.slurm` | `targets` + `tar_make_future` | Multi-core via future | **Broken on ARC** |

### Phase 2: Stan (Bayesian IV)

| Script | Strategy | Parallelism | Status |
|--------|----------|-------------|--------|
| `slurm/08_stan_sequential.slurm` | Sequential Stan fits | 1 chain, 1 core | Works |
| `slurm/09_stan_furrr.slurm` | `furrr` + `multisession` | 8 workers × 1 chain | Works |
| `slurm/10_stan_job_array.slurm` | SLURM job array | 8 tasks × 1 chain | Works |
| `slurm/11_stan_crew.slurm` | `targets` + `crew` | 8 workers × 1 chain | Works |

**Not tested** (see [docs/stan-parallelism.md](docs/stan-parallelism.md)):
- `mclapply` + Stan: fork-based parallelism has [documented issues](https://github.com/stan-dev/cmdstanr/issues/326) with cmdstanr (file collisions, shared tempdir)
- `tar_make_future` + Stan: already confirmed broken on ARC in Phase 1

## Setup on ARC

### 1. Load R and set library path

From an interactive session (`srun -p interactive --pty /bin/bash`):

```bash
module purge
module load R/4.4.2-gfbf-2024a
export R_LIBS=/data/econ-lead-public/econ0575/R_libs
```

### 2. Install R packages

```bash
Rscript -e 'install.packages(c(
  "tibble", "dplyr",
  "future", "future.apply", "furrr",
  "targets", "tarchetypes",
  "crew", "cmdstanr"
), repos = c("https://mc-stan.org/r-packages/", "https://cloud.r-project.org"))'
```

Verify:
```bash
Rscript -e 'for (p in c("targets", "tarchetypes", "crew", "future",
  "future.apply", "furrr", "tibble", "dplyr", "cmdstanr")) cat(p, ":", requireNamespace(p, quietly=TRUE), "\n")'
```

### 3. Compile the Stan model

Still on an interactive node (compilation needs the same CPU architecture as compute nodes):

```bash
cd $DATA/arc-parallel-R
export CMDSTAN=/data/econ-lead-public/econ0575/cmdstan/cmdstan-2.38.0
Rscript -e 'cmdstanr::cmdstan_model("stan/iv-simple.stan")'
```

This compiles `stan/iv-simple.stan` to `stan/iv-simple` (a binary executable).
The binary is cached — subsequent calls to `cmdstan_model()` in SLURM jobs will
load it without recompiling.

### 4. Clone and run

```bash
cd $DATA
git clone git@github.com:fditraglia/arc-parallel-R.git
cd arc-parallel-R
sbatch slurm/01_sequential.slurm
```

## ARC results

### Phase 1: OLS + bootstrap (50 reps, ~9s/rep)

| # | Strategy | Cores | Time | Speedup | Notes |
|---|----------|-------|------|---------|-------|
| 01 | Sequential | 1 | 455s | 1.0x | Baseline: ~9.1s/rep |
| 02 | mclapply | 8 | 66s | 6.9x | Near-linear scaling |
| 03 | future | 8 | 70s | 6.5x | Slightly more overhead than mclapply |
| 04 | Job array | 10×1 | 49s | — | Not directly comparable (10 cores, not 8) |
| 05 | targets basic | 1 | 448s | 1.0x | Negligible targets overhead at 10 branches |
| 06 | targets+crew | 8 | 103s | 4.4x | Works via sbatch at 10 branches |
| 07 | targets+future | 8 | 499s | 0.9x | **Did not parallelize** (see below) |

### Phase 2: Stan Bayesian IV (1 chain per fit, ~4s/rep)

**200 reps:**

| # | Strategy | Cores | Time | Speedup | Coverage | Notes |
|---|----------|-------|------|---------|----------|-------|
| 08 | Sequential | 1 | 782s | 1.0x | 87.5% | Baseline: ~3.9s/rep |
| 09 | furrr | 8 | 104s | 7.5x | 85.5% | Near-linear scaling, minimal overhead |
| 10 | Job array | 8×1 | 103s | 7.6x | — | Fastest — zero coordination overhead |
| 11 | targets+crew | 8 | 117s | 6.7x | — | Slightly more overhead, but robust |

**1200 reps (stress test at bdml-scale branch count):**

| # | Strategy | Cores | Time | Coverage | Notes |
|---|----------|-------|------|----------|-------|
| 09 | furrr | 8 | 614s | 91.4% | Worked without issues |
| 10 | Job array | 8×1 | 638s | — | Worked without issues |
| 11 | targets+crew | 8 | 617s | — | **Worked** — 1200 branches dispatched successfully |

All strategies use 1 chain per Stan fit (parallelism across reps, not within fits).
Coverage rates are close to the expected 90% for the 90% credible interval.
`mclapply` was not tested with Stan due to [documented issues](docs/stan-parallelism.md) with fork-based parallelism and cmdstanr.

### Why targets+future fails on ARC

`tar_make_future()` ran sequentially on ARC (499s) despite parallelizing locally on a Mac (74s with 4 workers). The branches completed in 8m 12s — identical to sequential — indicating that future workers were never dispatched.

This is consistent with broader issues:

- **`tar_make_future()` is officially superseded** ([deprecated March 2025](https://docs.ropensci.org/targets/reference/tar_make_future.html)) in favor of `tar_make()` with crew.
- It was designed primarily for [`future.batchtools`](https://future.batchtools.futureverse.org/) (where each worker is a separate SLURM job), not `future::multisession` (local processes).
- There are [known issues](https://github.com/ropensci/targets/discussions/570) with `tar_make_future()` on SLURM clusters: file locking, expired jobs, orphaned processes.
- `future::plan(multisession)` works fine *outside* targets (script 03 achieved 6.5x speedup), so the problem is specific to how `tar_make_future()` spawns and manages workers in a SLURM batch environment.

**Bottom line**: `tar_make_future()` is a dead end. Use `tar_make()` with crew (script 06), which is the officially recommended approach and works correctly via sbatch.

### Key finding: targets+crew works at 1200 branches (both tar_rep and tar_map_rep)

The upstream bdml pipeline hangs at 1,200+ dynamic branches via sbatch on ARC. We tested
both branching mechanisms at 1200 branches with Stan + crew:

| Test | Branching | Branches | Time |
|------|-----------|----------|------|
| Script 11 | `tar_rep` (flat) | 1200 × 1 | 617s |
| Script 12 | `tar_map_rep` (grid) | 6 grid × 200 batches | 566s |

Both completed successfully. This rules out:
- targets + crew at high branch counts
- `tar_map_rep()` specifically (the branching mechanism bdml uses)
- Stan via sbatch
- ARC's SLURM environment generally

The bdml hang is **not** caused by any of the above. Remaining suspects:

1. **Missing BLAS thread pinning** — bdml's `run_simul.slurm` does not set
   `OMP_NUM_THREADS=1` or `OPENBLAS_NUM_THREADS=1`. With 24 crew workers each
   triggering multi-threaded BLAS calls (via Stan and `lm()`), this creates
   hundreds of threads competing for 48 cores.

2. **The bdml package environment itself** — heavy dependencies (`tidyverse`,
   `bdml`, `cmdstanr`), `library(tidyverse)` loaded into the global environment
   at pipeline definition time, or the complexity of `bdml::run_grid_point_rep()`.

3. **Stan model fallback compilation** — if `instantiate::stan_package_model()`
   fails on a worker, bdml falls back to dev-mode compilation in a shared
   directory.

4. **It may not actually hang anymore** — the bdml code has changed since the
   last ARC attempt (serialization fix applied, batching cap added). The
   original "hang" may have been premature termination of a slow setup phase,
   or may no longer reproduce with the current code.

### bdml direct tests: calling estimators without the outer wrapping

We called bdml's estimator functions (`bdml::sim_iter_stan()`,
`bdml::sim_iter_nonstan()`) directly through targets+crew, bypassing
`run_grid_point_rep()`'s outer wrapping layers:
- **`callr::r()`** — removed for the 1 Stan method (BDML-LKJ-HP)
- **outer `capture.output(type="message")`** — removed for all 9 methods

Note: the inner `withr::with_tempdir()` and inner `capture.output()` inside
individual BLR estimator functions (fit_naive, fit_hcph, fit_linero, fit_fdml)
were present in **both** the direct and wrapped tests. They are not part of
the measured overhead differential.

**Test 13** — Single Stan estimator (BDML-LKJ-HP) only, sequential, 8 reps:
- ARC: 2.3s/rep (one estimator, not the full simulation)
- Mac: 1.0s/rep

**Test 15** — All 9 estimators via targets+crew+tar_map_rep (the full simulation):

**Complete timing comparison** (6 grid × 200 reps × 9 estimators, 8 crew workers):

| Run | Mac | ARC | ARC/Mac |
|-----|-----|-----|---------|
| Test 15 (direct function calls) | 14.3 min (856s) | 23.7 min (1422s) | 1.66x |
| Full bdml pipeline (with wrapping) | 15.5 min (929s) | 33.7 min (2023s) | 2.18x |
| **Wrapping overhead** | **73s (8.5%)** | **10 min (42%)** | |

ARC `seff` details for both runs:

| Metric | Test 15 (direct) | Full bdml pipeline |
|--------|-----------------|-------------------|
| Wall clock | 23:46 | 33:43 |
| CPU utilized | 2h 53m | 3h 46m |
| CPU efficiency | 91% | 84% |
| Memory used | 2.7 GB | 4.3 GB |

The outer wrapping overhead is **negligible on Mac (8.5%)** but **large on
ARC (42%)**. The overhead comes from removing two outer layers together:
`callr::r()` (1,200 subprocess spawns for the Stan method) and the outer
`capture.output(type="message")` (10,800 calls across all 9 methods).
We have not isolated the contribution of each, but `callr` is almost certainly
dominant — each invocation spawns a new R process that loads packages from
ARC's NFS filesystem. The outer `capture.output` is a lightweight R-level
redirection and likely contributes much less.

Note: `withr::with_tempdir()` inside BLR estimator functions is another
NFS-sensitive operation, but it runs in both tests equally and is **not**
part of the 42% differential.

**What we learned about the bdml pipeline:**
- It was never actually hung — progress output goes to `.err` not `.out`
  (targets prints to stderr with `callr_function = NULL`), which made it
  appear unresponsive when checking `.out`
- BLAS thread pinning (`OMP_NUM_THREADS=1`) was missing from the SLURM script
  and has now been added
- The outer `callr::r()` + `capture.output()` wrapping adds ~42% overhead on
  ARC vs ~8.5% on Mac. `callr` subprocess package-loading on NFS is the
  likely dominant cause.

### After optimization (callr removed, withr replaced with saveAt)

| Metric | Before (wrapped) | Test 15 (direct) | After (optimized) |
|--------|-----------------|------------------|-------------------|
| Wall clock | 33:43 | 23:46 | 24:05 |
| CPU utilized | 3h 46m | 2h 53m | 2h 53m |
| CPU efficiency | 84% | 91% | 90% |
| Memory used | 4.3 GB | 2.7 GB | 3.2 GB |

The optimized pipeline matches the direct-calls result. The ~42% overhead
from callr/capture.output/withr is eliminated.

**What remains to be tested:**
- Scale to the full `main` scenario (135 grid points × 2000 reps)
- Determine optimal worker count and batch size for production runs

## Key lessons learned

- **BLAS thread pinning is essential**: the `gfbf` R toolchain uses FlexiBLAS/OpenBLAS with threading. Multi-worker scripts must set `OMP_NUM_THREADS=1` and `OPENBLAS_NUM_THREADS=1` or workers oversubscribe cores.
- **`source()` inside `tar_rep()` hangs at scale**: targets serializes the function's environment per branch. Always `source()` at the top level of `_targets.R`.
- **`tar_make_future()` does not work on ARC**: superseded, poorly maintained, fails silently. Use `tar_make()` with crew instead.
- **`future::plan()` is invisible to `tar_make()`**: setting a future plan does nothing unless you use `tar_make_future()` (which itself doesn't work reliably).
- **crew needs `host = "127.0.0.1"` on ARC**: default hostname resolution fails silently on compute nodes.
- **SLURM does not source `~/.bashrc`**: set all environment variables explicitly in job scripts.
- **Start small on HPC**: test with few reps first to get per-rep timing before scaling up.
