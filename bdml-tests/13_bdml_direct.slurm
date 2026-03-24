#!/bin/bash
#SBATCH --job-name=13_bdml_dir
#SBATCH --output=13_bdml_direct_%j.out
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:30:00
#SBATCH --mem=4G

set -euo pipefail

module purge
module load R/4.4.2-gfbf-2024a
export R_LIBS=/data/econ-lead-public/econ0575/R_libs
export CMDSTAN=/data/econ-lead-public/econ0575/cmdstan/cmdstan-2.38.0
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

cd "$SLURM_SUBMIT_DIR"
mkdir -p results

echo "Strategy: bdml DGP + Stan model, direct (no callr), sequential"
echo "Start: $(date)"

Rscript --no-save --no-restore -e "
source('bdml-tests/sim_task_bdml_direct.R')

cat('Loading bdml model...\n')
get_bdml_model()  # warm up cache

N_REPS <- 8
cat('Reps:', N_REPS, '\n')
cat('Start:', format(Sys.time()), '\n')

t0 <- proc.time()
for (i in seq_len(N_REPS)) {
  t_rep <- proc.time()
  result <- sim_task_bdml_direct()
  elapsed_rep <- (proc.time() - t_rep)['elapsed']
  cat('Rep', i, ':', round(elapsed_rep, 1), 's  alpha_hat =',
      round(result\$alpha_hat, 3), '\n')
}
elapsed <- (proc.time() - t0)['elapsed']

cat('End:', format(Sys.time()), '\n')
cat('Total elapsed:', round(elapsed, 1), 's\n')
cat('Per rep:', round(elapsed / N_REPS, 1), 's\n')
"
