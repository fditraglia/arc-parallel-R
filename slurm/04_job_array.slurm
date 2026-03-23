#!/bin/bash
#SBATCH --job-name=04_job_array
#SBATCH --output=04_job_array_%A_%a.out
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:30:00
#SBATCH --mem=4G
#SBATCH --array=1-20

set -euo pipefail

# --- Environment setup (SLURM does NOT source ~/.bashrc) ---
module purge
module load R/4.4.2-gfbf-2024a
export R_LIBS=/data/econ-lead-public/econ0575/R_libs
export CMDSTAN=/data/econ-lead-public/econ0575/cmdstan/cmdstan-2.38.0

cd "$SLURM_SUBMIT_DIR"
mkdir -p results

# 200 total reps split across 20 array tasks = 10 reps per task
REPS_PER_TASK=10

Rscript --no-save --no-restore -e "
source('R/sim_task.R')

task_id <- as.integer(Sys.getenv('SLURM_ARRAY_TASK_ID'))
reps_per_task <- ${REPS_PER_TASK}

# Compute which rep IDs this task handles
start_rep <- (task_id - 1) * reps_per_task + 1
end_rep <- task_id * reps_per_task
my_reps <- start_rep:end_rep

cat('Strategy: SLURM job array\n')
cat('Task ID:', task_id, '\n')
cat('Reps:', start_rep, 'to', end_rep, '\n')
cat('Start:', format(Sys.time()), '\n')

t0 <- proc.time()
results <- lapply(my_reps, sim_task)
elapsed <- (proc.time() - t0)['elapsed']

df <- combine_results(results)
cat('End:', format(Sys.time()), '\n')
cat('Elapsed seconds:', elapsed, '\n')
cat('Reps completed:', nrow(df), '\n')

outfile <- sprintf('results/04_job_array_task_%03d.rds', task_id)
saveRDS(df, outfile)
cat('Results saved to', outfile, '\n')
"
