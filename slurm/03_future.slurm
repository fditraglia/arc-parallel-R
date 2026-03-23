#!/bin/bash
#SBATCH --job-name=03_future
#SBATCH --output=03_future_%j.out
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

library(future)
library(future.apply)

n_cores <- as.integer(Sys.getenv('SLURM_CPUS_PER_TASK', '1'))
plan(multisession, workers = n_cores)

cat('Strategy: future::plan(multisession)\n')
cat('Reps:', ${N_REPS}, '\n')
cat('Workers:', n_cores, '\n')
cat('Start:', format(Sys.time()), '\n')

t0 <- proc.time()
results <- future_lapply(seq_len(${N_REPS}), sim_task, future.seed = TRUE)
elapsed <- (proc.time() - t0)['elapsed']

df <- combine_results(results)
cat('End:', format(Sys.time()), '\n')
cat('Elapsed seconds:', elapsed, '\n')
cat('Reps completed:', nrow(df), '\n')
cat('Mean beta1_hat:', mean(df\$beta1_hat), '\n')

saveRDS(df, 'results/03_future.rds')
cat('Results saved to results/03_future.rds\n')
"
