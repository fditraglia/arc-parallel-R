# _targets.R for strategy 12: tar_map_rep + crew + Stan.
#
# Tests whether tar_map_rep (grid-based branching) behaves differently
# from tar_rep (flat branching) at scale. Script 11 used tar_rep at
# 1200 branches and completed in 617s. This uses tar_map_rep with a
# 6-point grid × 200 batches = 1200 branches.
#
# Control with environment variables:
#   N_BATCHES (default 200) x N_REPS_PER_BATCH (default 1) per grid point
#   N_WORKERS (default: SLURM_CPUS_PER_TASK or 8)
library(targets)
library(tarchetypes)
library(crew)

N_BATCHES <- as.integer(Sys.getenv("N_BATCHES", "200"))
N_REPS_PER_BATCH <- as.integer(Sys.getenv("N_REPS_PER_BATCH", "1"))
N_WORKERS <- as.integer(Sys.getenv("N_WORKERS",
                                    Sys.getenv("SLURM_CPUS_PER_TASK", "8")))

# Grid: 6 sample sizes
grid_df <- data.frame(n = c(200, 300, 400, 500, 600, 700))

cat("tar_map_rep+crew+stan config: grid rows =", nrow(grid_df),
    ", batches =", N_BATCHES,
    ", reps_per_batch =", N_REPS_PER_BATCH,
    ", total branches =", nrow(grid_df) * N_BATCHES,
    ", workers =", N_WORKERS, "\n")

tar_option_set(
  packages = c("cmdstanr", "tibble"),
  controller = crew_controller_local(
    workers = N_WORKERS,
    host = "127.0.0.1"
  )
)

source("R/sim_task_stan_grid.R")

list(
  tarchetypes::tar_map_rep(
    name = sim_result,
    command = sim_task_stan_grid(n = n),
    values = grid_df,
    batches = N_BATCHES,
    reps = N_REPS_PER_BATCH
  )
)
