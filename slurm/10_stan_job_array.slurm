#!/bin/bash
#SBATCH --job-name=10_stan_arr
#SBATCH --output=10_stan_job_array_%A_%a.out
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:30:00
#SBATCH --mem=4G
#SBATCH --array=1-8

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

# 1200 total reps across 8 tasks = 150 reps per task.
# Each task: 1 core, 1 chain per fit. Fully independent processes.
REPS_PER_TASK=150

Rscript --no-save --no-restore -e "
source('R/sim_task_stan.R')

task_id <- as.integer(Sys.getenv('SLURM_ARRAY_TASK_ID'))
reps_per_task <- ${REPS_PER_TASK}
start_rep <- (task_id - 1) * reps_per_task + 1
end_rep <- task_id * reps_per_task
my_reps <- start_rep:end_rep

cat('Strategy: SLURM job array + Stan\n')
cat('Task ID:', task_id, '\n')
cat('Reps:', start_rep, 'to', end_rep, '\n')
cat('Start:', format(Sys.time()), '\n')

t0 <- proc.time()
results <- lapply(my_reps, function(i) {
  cat('Rep', i, '\n')
  sim_task_stan(rep_id = i)
})
elapsed <- (proc.time() - t0)['elapsed']

df <- dplyr::bind_rows(results)
cat('End:', format(Sys.time()), '\n')
cat('Elapsed seconds:', elapsed, '\n')
cat('Reps completed:', nrow(df), '\n')

outfile <- sprintf('results/10_stan_job_array_task_%03d.rds', task_id)
saveRDS(df, outfile)
cat('Results saved to', outfile, '\n')
"
