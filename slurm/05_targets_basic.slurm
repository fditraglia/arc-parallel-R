#!/bin/bash
#SBATCH --job-name=05_targets_basic
#SBATCH --output=05_targets_basic_%j.out
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=02:00:00
#SBATCH --mem=8G

# --- Environment setup (SLURM does NOT source ~/.bashrc) ---
module purge
module load R/4.4.2-gfbf-2024a
export R_LIBS=/data/econ-lead-public/econ0575/R_libs
export CMDSTAN=/data/econ-lead-public/econ0575/cmdstan/cmdstan-2.38.0

cd $SLURM_SUBMIT_DIR

# Control batching: 20 batches x 10 reps = 200 total
export N_BATCHES=20
export N_REPS_PER_BATCH=10

echo "Strategy: targets with tar_rep (sequential, no crew)"
echo "Start: $(date)"

Rscript --no-save --no-restore -e "
t0 <- proc.time()
library(targets)
tar_make(script = 'R/05_targets_basic.R', store = '_targets_05', callr_function = NULL)
elapsed <- (proc.time() - t0)['elapsed']
cat('Elapsed seconds:', elapsed, '\n')
cat('End:', format(Sys.time()), '\n')
"
