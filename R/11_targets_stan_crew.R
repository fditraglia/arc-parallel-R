# _targets.R for strategy 11: targets + tar_rep + crew + Stan.
#
# Control with environment variables:
#   N_BATCHES (default 8) x N_REPS_PER_BATCH (default 3) = 24 total reps
#   N_WORKERS (default: SLURM_CPUS_PER_TASK or 8)
library(targets)
library(tarchetypes)
library(crew)

N_BATCHES <- as.integer(Sys.getenv("N_BATCHES", "8"))
N_REPS_PER_BATCH <- as.integer(Sys.getenv("N_REPS_PER_BATCH", "3"))
N_WORKERS <- as.integer(Sys.getenv("N_WORKERS",
                                    Sys.getenv("SLURM_CPUS_PER_TASK", "8")))

cat("targets+crew+stan config: batches =", N_BATCHES,
    ", reps_per_batch =", N_REPS_PER_BATCH,
    ", workers =", N_WORKERS, "\n")

tar_option_set(
  packages = c("cmdstanr", "tibble"),
  controller = crew_controller_local(
    workers = N_WORKERS,
    host = "127.0.0.1"
  )
)

# Source outside the command body to avoid per-branch serialization.
# Each worker loads the compiled Stan binary itself via get_stan_model().
source("R/sim_task_stan.R")

list(
  tar_rep(
    sim_result,
    sim_task_stan(rep_id = NA),
    batches = N_BATCHES,
    reps = N_REPS_PER_BATCH
  )
)
