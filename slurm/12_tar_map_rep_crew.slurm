#!/bin/bash
#SBATCH --job-name=12_map_rep
#SBATCH --output=12_tar_map_rep_crew_%j.out
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
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

cd "$SLURM_SUBMIT_DIR"

# 6 grid points x 200 batches x 1 rep = 1200 branches
# Same total as script 11 (tar_rep at 1200) for direct comparison
export N_BATCHES=200
export N_REPS_PER_BATCH=1
export N_WORKERS="${SLURM_CPUS_PER_TASK:-8}"

echo "Strategy: tar_map_rep + crew + Stan (1200 branches via grid)"
echo "Start: $(date)"

Rscript --no-save --no-restore -e "
t0 <- proc.time()
library(targets)
tar_make(script = 'R/12_targets_map_rep_crew.R', store = '_targets_12', callr_function = NULL)
elapsed <- (proc.time() - t0)['elapsed']
cat('Elapsed seconds:', elapsed, '\n')
cat('End:', format(Sys.time()), '\n')
"
