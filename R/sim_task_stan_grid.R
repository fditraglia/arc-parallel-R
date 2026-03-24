#' Lazy-load the compiled Stan IV model. Compiles on first call if needed,
#' then caches the handle for the rest of the R session.
get_stan_model <- local({
  model <- NULL
  function() {
    if (is.null(model)) {
      model <<- cmdstanr::cmdstan_model("stan/iv-simple.stan")
    }
    model
  }
})

#' Run one simulation replicate with grid parameters.
#'
#' Same DGP as sim_task_stan() but accepts n as a parameter
#' (for use with tar_map_rep over a grid of sample sizes).
#'
#' @param n Sample size (passed from grid)
#' @return A one-row tibble
sim_task_stan_grid <- function(n) {
  beta_true <- 0

  U <- rnorm(n)
  Z <- sample(1:4, size = n, replace = TRUE)
  X <- rnorm(n, mean = U + Z)
  Y <- rnorm(n, mean = U + beta_true * X)

  stan_data <- list(
    N = n,
    y = as.vector(scale(Y)),
    x = as.vector(scale(X)),
    z = as.vector(scale(Z))
  )

  model <- get_stan_model()
  fit <- model$sample(
    data = stan_data,
    chains = 1,
    parallel_chains = 1,
    refresh = 0,
    show_messages = FALSE,
    show_exceptions = FALSE
  )

  summ <- fit$summary(variables = "beta")
  beta_row <- summ[summ$variable == "beta", ]

  tibble::tibble(
    beta_mean = beta_row$mean,
    beta_q5 = beta_row$q5,
    beta_q95 = beta_row$q95,
    beta_covers = (beta_true >= beta_row$q5) & (beta_true <= beta_row$q95),
    n_divergent = sum(fit$diagnostic_summary(quiet = TRUE)$num_divergent)
  )
}
