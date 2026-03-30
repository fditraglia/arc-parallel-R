# CLAUDE.md

## Project Purpose

Find the best way to run fast, reliable, parallel simulations using the bdml R package (which fits Stan models) on Oxford's ARC HPC cluster. The parallelization strategy is an open question — targets+crew is one option but not the only one. This repo tests every common approach systematically.

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
9. **`set -euo pipefail` is good practice for SLURM setup sections** (module load, cd, exports) — but not necessarily appropriate for the entire script if it runs multiple independent tasks sequentially

## Key Findings from bdml Debugging

**Original problem:** bdml pipeline appeared to hang via sbatch on ARC.

**What actually happened:** The pipeline was never hung. Progress output goes to
stderr (`.err` file) not stdout (`.out` file) when using `callr_function = NULL`.
Checking only `.out` made it appear unresponsive.

**Earlier findings (still valid):**
- crew needs `host = "127.0.0.1"` on ARC compute nodes
- Sourced functions in `tar_map_rep()` cause per-branch environment serialization — use `pkg::function()`
- Both fixes were already applied to bdml before this repo was created

**What this repo proved:**
- targets + crew works at 1200 branches on ARC (both tar_rep and tar_map_rep)
- The real bdml Stan model (BDML-LKJ-HP) fits in ~2.3s/rep on ARC
- All 9 bdml estimators work via targets+crew on ARC
- The full bdml pipeline completes the test scenario in 33.7 min (8 workers)
- Calling bdml functions directly (bypassing outer callr + capture.output) takes 23.7 min
- Outer wrapping overhead: 42% on ARC vs 8.5% on Mac
- The 42% comes from removing callr (1,200 subprocess spawns) + outer capture.output
  (10,800 calls) together — not yet isolated, but callr is likely dominant (NFS pkg loading)
- Inner withr::with_tempdir() in BLR estimators is present in both tests — not part of
  the measured differential, but is a separate NFS concern
- After optimization (removing callr, outer capture.output, replacing withr with saveAt):
  24:05 wall clock, 90% CPU efficiency — matches direct-calls baseline exactly
- Baseline scenario (p=100, 5 rho, 2000 reps, 9 estimators, 40 workers): 2h 12m wall clock,
  86 core-hours, 81% efficiency. Rho has negligible effect on per-branch timing.

## Testing Strategy

Two dimensions, tested independently then combined:

**Phase 1 — Parallelism (simple OLS+bootstrap task, no Stan):** DONE
1. Sequential baseline ✓
2. parallel::mclapply ✓
3. future::plan(multisession) ✓
4. SLURM job arrays ✓
5. targets + tar_rep (sequential) ✓
6. targets + crew ✓
7. targets + tar_make_future ✓ (broken on ARC — superseded, do not use)

**Phase 2 — Add Stan:**
8. Single Stan fit via sbatch (does Stan work at all?)
9. Stan via mclapply (does fork() conflict with Stan's callr subprocess?)
10. Stan via job arrays (fully independent processes, no forking)
11. Stan via targets + crew
12. Scale testing: increase branch/rep counts across strategies that work

## HPC Workflow Discipline

- **Start small on ARC**: first submission of any strategy should use a small rep count (e.g. 20) to confirm it works and get per-rep timing, then scale up
- **Print progress**: long-running jobs must print interim output (e.g. every 10 reps) so you can distinguish "slow" from "hung"
- **Test at deployment config locally first**: don't test at 20 reps locally then deploy at 200 — run the exact same config on Mac to establish a baseline
- **Read the docs before writing code**: ARC user guide, software guide, package docs (tar_rep, crew, future) — not after

## Scientific Method — No Speculation Without Experiments

- **If you have a hypothesis, design a test.** This repo exists to run experiments. Don't theorize about what might cause a hang — write a script that isolates the variable and run it.
- **One variable at a time.** Each test should change exactly one thing from a known-working baseline.
- **Evidence over stories.** "tar_map_rep might behave differently" is a hypothesis. Running tar_map_rep at 1200 branches and observing what happens is evidence. Only evidence counts.
- **Don't accumulate untested hypotheses.** If you've listed 4 possible causes, you should be designing 4 experiments, not writing 4 paragraphs of speculation.
- **Do arithmetic carefully.** When comparing timings, check: same rep count? Same number of estimators? Wall clock vs aggregate worker time? Per-rep vs total? Don't claim "150x faster" when comparing 10 reps to 200 reps.
- **Know which repo/branch you're in.** Before committing, verify with `git remote -v` and `git branch`. This project spans two repos (arc-parallel-R and bdml). Don't push to the wrong branch.
- **Don't write down claims you can't support.** If you haven't measured something, say so. Don't round speculation into fact in documentation — it will mislead future readers (including yourself).

## Conventions

- Each strategy gets its own SLURM script in `slurm/`
- Common simulation task defined once in `R/sim_task.R`
- Results go to `results/` (gitignored)
- All SLURM scripts must be self-contained (full env setup)
- No CI/GitHub Actions (this is a testing repo)
