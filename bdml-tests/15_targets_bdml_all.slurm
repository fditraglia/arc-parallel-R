#!/bin/bash
#SBATCH --job-name=15_bdml_all
#SBATCH --output=15_bdml_all_%j.out
#SBATCH --error=15_bdml_all_%j.err
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=02:00:00
#SBATCH --mem=16G

set -euo pipefail

module purge
module load R/4.4.2-gfbf-2024a
export R_LIBS=/data/econ-lead-public/econ0575/R_libs
export CMDSTAN=/data/econ-lead-public/econ0575/cmdstan/cmdstan-2.38.0
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

cd "$SLURM_SUBMIT_DIR"

# 6 grid points x 10 batches x 20 reps = 60 branches, 200 reps per grid point
# Matches bdml test config exactly (simul_size=200, max_batches=10)
export N_BATCHES=10
export N_REPS_PER_BATCH=20
export N_WORKERS="${SLURM_CPUS_PER_TASK:-8}"

echo "Strategy: targets + crew + ALL 9 bdml estimators (no callr)"
echo "Start: $(date)"

Rscript --no-save --no-restore -e "
t0 <- proc.time()
library(targets)
tar_make(script = 'bdml-tests/15_targets_bdml_all.R', store = '_targets_15', callr_function = NULL)
elapsed <- (proc.time() - t0)['elapsed']
cat('Elapsed seconds:', elapsed, '\n')
cat('End:', format(Sys.time()), '\n')
"
