# _targets.R for strategy 06: targets with tarchetypes::tar_rep + crew.
# Same as 05 but with crew for parallel worker dispatch.
#
# Control with environment variables:
#   N_BATCHES (default 20) x N_REPS_PER_BATCH (default 10) = 200 total reps
#   N_WORKERS (default: SLURM_CPUS_PER_TASK or 4)
library(targets)
library(tarchetypes)
library(crew)

N_BATCHES <- as.integer(Sys.getenv("N_BATCHES", "20"))
N_REPS_PER_BATCH <- as.integer(Sys.getenv("N_REPS_PER_BATCH", "10"))
N_WORKERS <- as.integer(Sys.getenv("N_WORKERS",
                                    Sys.getenv("SLURM_CPUS_PER_TASK", "4")))

cat("targets+crew config: batches =", N_BATCHES,
    ", reps_per_batch =", N_REPS_PER_BATCH,
    ", workers =", N_WORKERS, "\n")

tar_option_set(
  packages = character(0),
  controller = crew_controller_local(
    workers = N_WORKERS,
    host = "127.0.0.1"  # Required on ARC — default hostname resolution fails
  )
)

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
