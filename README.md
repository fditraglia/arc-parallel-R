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

| Script | Strategy | Parallelism | Status |
|--------|----------|-------------|--------|
| `slurm/01_sequential.slurm` | For loop | None (baseline) | Works |
| `slurm/02_mclapply.slurm` | `parallel::mclapply` | Multi-core, single node | Works |
| `slurm/03_future.slurm` | `future::plan(multisession)` | Multi-core, single node | Works |
| `slurm/04_job_array.slurm` | SLURM job array | Multiple independent jobs | Works |
| `slurm/05_targets_basic.slurm` | `targets` + `tar_rep` | None (sequential targets) | Works |
| `slurm/06_targets_crew.slurm` | `targets` + `tar_rep` + `crew` | Multi-core via crew workers | Works (at 10 branches) |
| `slurm/07_targets_future.slurm` | `targets` + `tar_make_future` | Multi-core via future workers | **Broken on ARC** |

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
  "future", "future.apply",
  "targets", "tarchetypes",
  "crew"
), repos = "https://cloud.r-project.org")'
```

Verify:
```bash
Rscript -e 'for (p in c("targets", "tarchetypes", "crew", "future",
  "future.apply", "tibble", "dplyr")) cat(p, ":", requireNamespace(p, quietly=TRUE), "\n")'
```

### 3. Clone and run

```bash
cd $DATA
git clone git@github.com:fditraglia/arc-parallel-R.git
cd arc-parallel-R
sbatch slurm/01_sequential.slurm
```

## ARC results (50 reps, 2026-03-23)

| # | Strategy | Cores | Time | Speedup | Notes |
|---|----------|-------|------|---------|-------|
| 01 | Sequential | 1 | 455s | 1.0x | Baseline: ~9.1s/rep |
| 02 | mclapply | 8 | 66s | 6.9x | Near-linear scaling |
| 03 | future | 8 | 70s | 6.5x | Slightly more overhead than mclapply |
| 04 | Job array | 10x1 | 49s | — | Not directly comparable (10 cores, not 8) |
| 05 | targets basic | 1 | 448s | 1.0x | Negligible targets overhead at 10 branches |
| 06 | targets+crew | 8 | 103s | 4.4x | Works via sbatch at 10 branches |
| 07 | targets+future | 8 | 499s | 0.9x | **Did not parallelize** (see below) |

### Why targets+future fails on ARC

`tar_make_future()` ran sequentially on ARC (499s) despite parallelizing locally on a Mac (74s with 4 workers). The branches completed in 8m 12s — identical to sequential — indicating that future workers were never dispatched.

This is consistent with broader issues:

- **`tar_make_future()` is officially superseded** ([deprecated March 2025](https://docs.ropensci.org/targets/reference/tar_make_future.html)) in favor of `tar_make()` with crew.
- It was designed primarily for [`future.batchtools`](https://future.batchtools.futureverse.org/) (where each worker is a separate SLURM job), not `future::multisession` (local processes).
- There are [known issues](https://github.com/ropensci/targets/discussions/570) with `tar_make_future()` on SLURM clusters: file locking, expired jobs, orphaned processes.
- `future::plan(multisession)` works fine *outside* targets (script 03 achieved 6.5x speedup), so the problem is specific to how `tar_make_future()` spawns and manages workers in a SLURM batch environment.

**Bottom line**: `tar_make_future()` is a dead end. Use `tar_make()` with crew (script 06), which is the officially recommended approach and works correctly via sbatch.

### Open questions

- Does targets+crew break at higher branch counts (100, 500, 1200+)?
  The upstream bdml pipeline hangs at 1,200 branches. Our test used only 10.
- How much does BLAS thread pinning matter for absolute performance?
- What is the optimal batch size for `tar_rep()` on ARC?

## Key lessons learned

- **BLAS thread pinning is essential**: the `gfbf` R toolchain uses FlexiBLAS/OpenBLAS with threading. Multi-worker scripts must set `OMP_NUM_THREADS=1` and `OPENBLAS_NUM_THREADS=1` or workers oversubscribe cores.
- **`source()` inside `tar_rep()` hangs at scale**: targets serializes the function's environment per branch. Always `source()` at the top level of `_targets.R`.
- **`tar_make_future()` does not work on ARC**: superseded, poorly maintained, fails silently. Use `tar_make()` with crew instead.
- **`future::plan()` is invisible to `tar_make()`**: setting a future plan does nothing unless you use `tar_make_future()` (which itself doesn't work reliably).
- **crew needs `host = "127.0.0.1"` on ARC**: default hostname resolution fails silently on compute nodes.
- **SLURM does not source `~/.bashrc`**: set all environment variables explicitly in job scripts.
- **Start small on HPC**: test with few reps first to get per-rep timing before scaling up.
