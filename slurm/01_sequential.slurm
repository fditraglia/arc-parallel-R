#!/bin/bash
#SBATCH --job-name=01_sequential
#SBATCH --output=01_sequential_%j.out
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

cd "$SLURM_SUBMIT_DIR"
mkdir -p results

N_REPS=50

Rscript --no-save --no-restore -e "
source('R/sim_task.R')

cat('Strategy: sequential for loop\n')
cat('Reps:', ${N_REPS}, '\n')
cat('Start:', format(Sys.time()), '\n')

t0 <- proc.time()
results <- vector('list', ${N_REPS})
for (i in seq_len(${N_REPS})) {
  results[[i]] <- sim_task(i)
}
elapsed <- (proc.time() - t0)['elapsed']

df <- combine_results(results)
cat('End:', format(Sys.time()), '\n')
cat('Elapsed seconds:', elapsed, '\n')
cat('Reps completed:', nrow(df), '\n')
cat('Mean beta1_hat:', mean(df\$beta1_hat), '\n')

saveRDS(df, 'results/01_sequential.rds')
cat('Results saved to results/01_sequential.rds\n')
"
