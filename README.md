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

| Script | Strategy | Parallelism |
|--------|----------|-------------|
| `slurm/01_sequential.slurm` | For loop | None (baseline) |
| `slurm/02_mclapply.slurm` | `parallel::mclapply` | Multi-core, single node |
| `slurm/03_future.slurm` | `future::plan(multisession)` | Multi-core, single node |
| `slurm/04_job_array.slurm` | SLURM job array | Multiple independent jobs |
| `slurm/05_targets_basic.slurm` | `targets` + `tar_rep` | None (sequential targets) |
| `slurm/06_targets_crew.slurm` | `targets` + `tar_rep` + `crew` | Multi-core via crew workers |
| `slurm/07_targets_future.slurm` | `targets` + `tar_make_future` | Multi-core via future workers |

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

## Key lessons learned

- **BLAS thread pinning is essential**: the `gfbf` R toolchain uses FlexiBLAS/OpenBLAS with threading. Multi-worker scripts must set `OMP_NUM_THREADS=1` and `OPENBLAS_NUM_THREADS=1` or workers oversubscribe cores.
- **`source()` inside `tar_rep()` hangs at scale**: targets serializes the function's environment per branch. Always `source()` at the top level of `_targets.R`.
- **`future::plan()` is invisible to `tar_make()`**: use `tar_make_future()` for future-based parallelism, or `tar_make()` with a crew controller.
- **crew needs `host = "127.0.0.1"` on ARC**: default hostname resolution fails silently on compute nodes.
- **SLURM does not source `~/.bashrc`**: set all environment variables explicitly in job scripts.

## ARC results

| # | Strategy | Cores | Time (50 reps) | Speedup |
|---|----------|-------|----------------|---------|
| 01 | Sequential | 1 | 455s | 1.0x |
| 02 | mclapply | 8 | 66s | 6.9x |
| 03 | future | 8 | TBD | |
| 04 | Job array | 10x1 | TBD | |
| 05 | targets basic | 1 | TBD | |
| 06 | targets+crew | 8 | TBD | |
| 07 | targets+future | 8 | TBD | |
