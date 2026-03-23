# _targets.R for strategy 05: targets with tarchetypes::tar_rep, no crew.
# Uses dynamic branching via tar_rep. No parallel backend — sequential.
#
# Control branch count with environment variables:
#   N_BATCHES (default 20) x N_REPS_PER_BATCH (default 10) = 200 total reps
library(targets)
library(tarchetypes)

N_BATCHES <- as.integer(Sys.getenv("N_BATCHES", "20"))
N_REPS_PER_BATCH <- as.integer(Sys.getenv("N_REPS_PER_BATCH", "10"))

cat("targets config: batches =", N_BATCHES, ", reps_per_batch =", N_REPS_PER_BATCH, "\n")

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
