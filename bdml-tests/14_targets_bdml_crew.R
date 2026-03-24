# targets + crew + real bdml Stan model (BDML-LKJ-HP)
#
# Same grid as bdml "test" config: n=200, p={10,20}, rho={-0.8,0,0.8}
# 6 grid points × 200 batches × 1 rep = 1200 branches
#
# No callr wrapping, no capture.output — just the raw computation.
library(targets)
library(tarchetypes)
library(crew)

N_BATCHES <- as.integer(Sys.getenv("N_BATCHES", "200"))
N_REPS_PER_BATCH <- as.integer(Sys.getenv("N_REPS_PER_BATCH", "1"))
N_WORKERS <- as.integer(Sys.getenv("N_WORKERS",
                                    Sys.getenv("SLURM_CPUS_PER_TASK", "8")))

grid_df <- data.frame(
  n = 200,
  p = rep(c(10, 20), each = 3),
  R_Y2 = 0.5,
  R_D2 = 0.5,
  rho = rep(c(-0.8, 0, 0.8), times = 2),
  alpha = 0.25
)

cat("bdml+crew config: grid rows =", nrow(grid_df),
    ", batches =", N_BATCHES,
    ", reps_per_batch =", N_REPS_PER_BATCH,
    ", total branches =", nrow(grid_df) * N_BATCHES,
    ", workers =", N_WORKERS, "\n")

tar_option_set(
  packages = c("cmdstanr", "tibble", "bdml"),
  controller = crew_controller_local(
    workers = N_WORKERS,
    host = "127.0.0.1"
  )
)

source("bdml-tests/sim_task_bdml_direct.R")

list(
  tarchetypes::tar_map_rep(
    name = sim_result,
    command = sim_task_bdml_direct(n = n, p = p, R_Y2 = R_Y2, R_D2 = R_D2,
                                   rho = rho, alpha = alpha),
    values = grid_df,
    batches = N_BATCHES,
    reps = N_REPS_PER_BATCH
  )
)
