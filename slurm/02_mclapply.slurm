#!/bin/bash
#SBATCH --job-name=02_mclapply
#SBATCH --output=02_mclapply_%j.out
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

# Prevent BLAS/OpenMP thread oversubscription (gfbf toolchain uses FlexiBLAS/OpenBLAS)
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

cd "$SLURM_SUBMIT_DIR"
mkdir -p results

N_REPS=50

Rscript --no-save --no-restore -e "
source('R/sim_task.R')

n_cores <- as.integer(Sys.getenv('SLURM_CPUS_PER_TASK', '1'))
cat('Strategy: parallel::mclapply\n')
cat('Reps:', ${N_REPS}, '\n')
cat('Cores:', n_cores, '\n')
cat('Start:', format(Sys.time()), '\n')

t0 <- proc.time()
results <- parallel::mclapply(
  seq_len(${N_REPS}),
  sim_task,
  mc.cores = n_cores
)
elapsed <- (proc.time() - t0)['elapsed']

# Check for errors (mclapply wraps errors in try-error)
errors <- sapply(results, inherits, 'try-error')
if (any(errors)) {
  cat('WARNING:', sum(errors), 'replicates failed\n')
  results <- results[!errors]
}

df <- combine_results(results)
cat('End:', format(Sys.time()), '\n')
cat('Elapsed seconds:', elapsed, '\n')
cat('Reps completed:', nrow(df), '\n')
cat('Mean beta1_hat:', mean(df\$beta1_hat), '\n')

saveRDS(df, 'results/02_mclapply.rds')
cat('Results saved to results/02_mclapply.rds\n')
"
