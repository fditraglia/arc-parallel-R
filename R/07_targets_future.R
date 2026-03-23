# _targets.R for strategy 07: targets with tarchetypes::tar_rep + future backend.
# Same as 05 but uses tar_make_future() for parallel branch execution.
#
# Control with environment variables:
#   N_BATCHES (default 20) x N_REPS_PER_BATCH (default 10) = 200 total reps
#   N_WORKERS (default: SLURM_CPUS_PER_TASK or 4)
library(targets)
library(tarchetypes)

N_BATCHES <- as.integer(Sys.getenv("N_BATCHES", "20"))
N_REPS_PER_BATCH <- as.integer(Sys.getenv("N_REPS_PER_BATCH", "10"))

cat("targets+future config: batches =", N_BATCHES,
    ", reps_per_batch =", N_REPS_PER_BATCH, "\n")

tar_option_set(packages = character(0))

# Source outside the command body — sourcing inside causes per-branch
# serialization of the function's environment, which hangs at scale.
source("R/sim_task.R")

list(
  tar_rep(
    sim_result,
    sim_task(rep_id = NA),
    batches = N_BATCHES,
    reps = N_REPS_PER_BATCH
  )
)
