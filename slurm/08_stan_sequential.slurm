#!/bin/bash
#SBATCH --job-name=08_stan_seq
#SBATCH --output=08_stan_sequential_%j.out
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:30:00
#SBATCH --mem=4G

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

N_REPS=200

echo "Strategy: sequential Stan fits (1 chain, 1 core)"
echo "Start: $(date)"

Rscript --no-save --no-restore -e "
source('R/sim_task_stan.R')

N_REPS <- ${N_REPS}
cat('Reps:', N_REPS, '\n')
cat('Start:', format(Sys.time()), '\n')

t0 <- proc.time()
results <- lapply(seq_len(N_REPS), function(i) {
  cat('Rep', i, 'of', N_REPS, '\n')
  sim_task_stan(rep_id = i)
})
elapsed <- (proc.time() - t0)['elapsed']

df <- dplyr::bind_rows(results)
cat('End:', format(Sys.time()), '\n')
cat('Elapsed seconds:', elapsed, '\n')
cat('Reps completed:', nrow(df), '\n')
cat('Mean beta_mean:', mean(df\$beta_mean), '\n')
cat('Coverage:', mean(df\$beta_covers), '\n')
cat('Divergences:', sum(df\$n_divergent), '\n')

saveRDS(df, 'results/08_stan_sequential.rds')
cat('Results saved to results/08_stan_sequential.rds\n')
"
