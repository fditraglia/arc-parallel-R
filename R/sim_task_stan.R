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

#' Run one simulation replicate: generate IV data, fit Bayesian IV via Stan.
#'
#' DGP (standardized):
#'   U ~ N(0,1) (unobserved confounder)
#'   Z ~ Uniform{1,2,3,4} (instrument: quarter of birth)
#'   X = U + Z + V,  V ~ N(0,1) (endogenous regressor: education)
#'   Y = U + 0 * X + W,  W ~ N(0,1) (outcome: wages, true effect = 0)
#'   All variables standardized before fitting.
#'
#' Fits with 1 chain (parallelism is across reps, not within fits).
#'
#' @param rep_id Replicate ID (for tracking)
#' @return A one-row tibble
sim_task_stan <- function(rep_id) {
  n <- 500
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
    rep_id = rep_id,
    beta_mean = beta_row$mean,
    beta_q5 = beta_row$q5,
    beta_q95 = beta_row$q95,
    beta_covers = (beta_true >= beta_row$q5) & (beta_true <= beta_row$q95),
    n_divergent = sum(fit$diagnostic_summary(quiet = TRUE)$num_divergent)
  )
}
