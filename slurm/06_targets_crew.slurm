#!/bin/bash
#SBATCH --job-name=06_targets_crew
#SBATCH --output=06_targets_crew_%j.out
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=01:00:00
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

# Control batching and workers — derive from SLURM allocation
export N_BATCHES=20
export N_REPS_PER_BATCH=10
export N_WORKERS="${SLURM_CPUS_PER_TASK:-4}"

echo "Strategy: targets + crew (local controller)"
echo "Start: $(date)"

Rscript --no-save --no-restore -e "
t0 <- proc.time()
library(targets)
tar_make(script = 'R/06_targets_crew.R', store = '_targets_06', callr_function = NULL)
elapsed <- (proc.time() - t0)['elapsed']
cat('Elapsed seconds:', elapsed, '\n')
cat('End:', format(Sys.time()), '\n')
"
