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

### Key finding: targets+crew works at 1200 branches

The upstream bdml pipeline hangs at 1,200+ dynamic branches via sbatch on ARC. We tested
targets+crew at exactly 1200 branches (`tar_rep` with 1200 batches × 1 rep) using a simple
Stan IV model — and **it completed successfully** in 617 seconds.

This means the bdml hang is **not** caused by:
- targets + crew at high branch counts (works here)
- Stan via sbatch (works here)
- ARC's SLURM environment (works here)

The hang must be caused by something specific to the bdml pipeline:
- Heavier function environment / package dependencies (tidyverse, bdml internals)
- `tar_map_rep()` vs `tar_rep()` (different dynamic branching mechanism)
- More complex Stan models via `instantiate`
- Interaction between `imports = "bdml"` and the targets dependency graph

### Open questions

- What specifically about bdml causes the 1200-branch hang?
- Does `tar_map_rep()` behave differently from `tar_rep()` at scale?
- Would restructuring bdml to use furrr or job arrays avoid the issue entirely?

## Key lessons learned

- **BLAS thread pinning is essential**: the `gfbf` R toolchain uses FlexiBLAS/OpenBLAS with threading. Multi-worker scripts must set `OMP_NUM_THREADS=1` and `OPENBLAS_NUM_THREADS=1` or workers oversubscribe cores.
- **`source()` inside `tar_rep()` hangs at scale**: targets serializes the function's environment per branch. Always `source()` at the top level of `_targets.R`.
- **`tar_make_future()` does not work on ARC**: superseded, poorly maintained, fails silently. Use `tar_make()` with crew instead.
- **`future::plan()` is invisible to `tar_make()`**: setting a future plan does nothing unless you use `tar_make_future()` (which itself doesn't work reliably).
- **crew needs `host = "127.0.0.1"` on ARC**: default hostname resolution fails silently on compute nodes.
- **SLURM does not source `~/.bashrc`**: set all environment variables explicitly in job scripts.
- **Start small on HPC**: test with few reps first to get per-rep timing before scaling up.
