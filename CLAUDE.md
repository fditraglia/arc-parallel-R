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

## Conventions

- Each strategy gets its own SLURM script in `slurm/`
- Common simulation task defined once in `R/sim_task.R`
- Results go to `results/` (gitignored)
- All SLURM scripts must be self-contained (full env setup)
- No CI/GitHub Actions (this is a testing repo)
