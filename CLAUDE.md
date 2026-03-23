# CLAUDE.md

## Project Purpose

Systematic comparison of parallel R strategies on Oxford's ARC HPC cluster. Motivated by the bdml project where `targets` + `crew` hangs via `sbatch` despite working interactively.

## ARC Environment

- **$DATA**: `/data/econ-lead-public/econ0575`
- **R module**: `module load R/4.4.2-gfbf-2024a`
- **R library**: `$DATA/R_libs` (set via `export R_LIBS=$DATA/R_libs`)
- **CmdStan**: `$DATA/cmdstan/cmdstan-2.38.0` (set via `export CMDSTAN=...`)
- **Username**: `econ0575`
- **SSH**: `ssh arc` (configured in ~/.ssh/config with ProxyJump)
- **Clusters**: `arc` (large parallel jobs, 48-core nodes), `htc` (many small jobs)
- **Partitions**: `short` (max 12hr), `medium` (max 48hr), `long` (no limit), `interactive`, `devel`
- **SLURM jobs do NOT source ~/.bashrc or ~/.bash_profile** — set all env vars explicitly in scripts

## Critical ARC Facts (learned the hard way)

1. **crew needs `host = "127.0.0.1"`** — default hostname resolution fails on compute nodes
2. **Every SLURM script must include**: `module purge && module load R/4.4.2-gfbf-2024a`, `export R_LIBS=...`, `export CMDSTAN=...`
3. **targets progress goes to stderr** when using `callr_function = NULL`
4. **`source ~/.bash_profile` hangs** on compute/interactive nodes — always set env vars explicitly
5. **Output file location** depends on where you run `sbatch` from (relative paths in `#SBATCH --output`)
6. **`gfbf` toolchain = FlexiBLAS/OpenBLAS with threading** — multi-worker scripts must set `OMP_NUM_THREADS=1` and `OPENBLAS_NUM_THREADS=1` to prevent thread oversubscription
7. **`source()` inside `tar_rep()` command body** causes per-branch serialization of the function environment — always source at top level of `_targets.R`
8. **`tar_make_future()` is a dead end** — officially superseded (March 2025), fails silently on ARC (runs sequentially despite requesting workers). Use `tar_make()` with crew instead. `future::plan()` alone is invisible to `tar_make()`
9. **All SLURM scripts should use `set -euo pipefail`** — a failed `module load` or `cd` will otherwise silently continue

## Key Findings from bdml Debugging

- `targets` + `crew` dispatches branches fine **interactively** on ARC
- `targets` + `crew` **never dispatched a single branch via sbatch** — hangs after declaring branches
- `targets` without crew (`use_crew = FALSE`) **also hangs via sbatch** — so crew is not the sole problem
- The same pipeline works perfectly on a MacBook (even with 10,000+ branches)
- Trivial commands (`rnorm(1)`) dispatch fine at 1,200 branches interactively
- Package functions dispatch at 60 branches interactively; sourced functions hang at any count
- Root cause unknown — suspected main-process scheduler overhead on slower HPC hardware

## Testing Strategy

Build up from simple to complex, one variable at a time:
1. Basic R via sbatch (baseline)
2. parallel::mclapply via sbatch
3. future::plan(multisession) via sbatch
4. SLURM job arrays
5. targets without crew or branching
6. targets with dynamic branching
7. targets + crew
8. targets + future backend
9. Stan fits (added last — not suspected as root cause)

## HPC Workflow Discipline

- **Start small on ARC**: first submission of any strategy should use a small rep count (e.g. 20) to confirm it works and get per-rep timing, then scale up
- **Print progress**: long-running jobs must print interim output (e.g. every 10 reps) so you can distinguish "slow" from "hung"
- **Test at deployment config locally first**: don't test at 20 reps locally then deploy at 200 — run the exact same config on Mac to establish a baseline
- **Read the docs before writing code**: ARC user guide, software guide, package docs (tar_rep, crew, future) — not after

## Conventions

- Each strategy gets its own SLURM script in `slurm/`
- Common simulation task defined once in `R/sim_task.R`
- Results go to `results/` (gitignored)
- All SLURM scripts must be self-contained (full env setup)
- No CI/GitHub Actions (this is a testing repo)
