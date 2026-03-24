#!/bin/bash
#SBATCH --job-name=09_stan_furrr
#SBATCH --output=09_stan_furrr_%j.out
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=00:30:00
#SBATCH --mem=16G

set -euo pipefail

# --- Environment setup (SLURM does NOT source ~/.bashrc) ---
module purge
module load R/4.4.2-gfbf-2024a
export R_LIBS=/data/econ-lead-public/econ0575/R_libs
export CMDSTAN=/data/econ-lead-public/econ0575/cmdstan/cmdstan-2.38.0
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

cd "$SLURM_SUBMIT_DIR"
mkdir -p results

N_REPS=1200

echo "Strategy: furrr + multisession with Stan (8 workers, 1 chain each)"
echo "Start: $(date)"

Rscript --no-save --no-restore -e "
source('R/sim_task_stan.R')
library(furrr)

n_workers <- as.integer(Sys.getenv('SLURM_CPUS_PER_TASK', '8'))
plan(multisession, workers = n_workers)

N_REPS <- ${N_REPS}
cat('Reps:', N_REPS, '\n')
cat('Workers:', n_workers, '\n')
cat('Start:', format(Sys.time()), '\n')

t0 <- proc.time()
df <- future_map_dfr(
  seq_len(N_REPS),
  sim_task_stan,
  .options = furrr_options(seed = TRUE)
)
elapsed <- (proc.time() - t0)['elapsed']

cat('End:', format(Sys.time()), '\n')
cat('Elapsed seconds:', elapsed, '\n')
cat('Reps completed:', nrow(df), '\n')
cat('Mean beta_mean:', mean(df\$beta_mean), '\n')
cat('Coverage:', mean(df\$beta_covers), '\n')
cat('Divergences:', sum(df\$n_divergent), '\n')

saveRDS(df, 'results/09_stan_furrr.rds')
cat('Results saved to results/09_stan_furrr.rds\n')
"
