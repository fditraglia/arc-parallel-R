#' Compile the Stan IV model. Call once, then pass to sim_task_stan().
#'
#' @return A CmdStanModel object
compile_stan_model <- function() {
  cmdstanr::cmdstan_model("stan/iv-simple.stan")
}

#' Run one simulation replicate: generate IV data, fit Bayesian IV via Stan.
#'
#' DGP (standardized):
#'   U ~ N(0,1) (unobserved confounder)
#'   Z ~ Uniform{1,2,3,4} (instrument: quarter of birth)
#'   X = U + Z + V,  V ~ N(0,1) (endogenous regressor: education)
#'   Y = U + beta_true * X + W,  W ~ N(0,1) (outcome: wages)
#'   All variables standardized before fitting.
#'   True causal effect beta_true = 0 (no effect of education on wages)
#'
#' @param rep_id Replicate ID (for tracking)
#' @param model A compiled CmdStanModel object (from compile_stan_model())
#' @param n Sample size (default 500)
#' @param chains Number of MCMC chains (default 4)
#' @param iter_sampling Iterations per chain after warmup (default 1000)
#' @return A one-row tibble with posterior summaries and coverage
sim_task_stan <- function(rep_id, model, n = 500, chains = 4,
                          iter_sampling = 1000) {
  beta_true <- 0  # true causal effect

  # Generate data
  U <- rnorm(n)
  Z <- sample(1:4, size = n, replace = TRUE)
  X <- rnorm(n, mean = U + Z)
  Y <- rnorm(n, mean = U + beta_true * X)

  # Standardize
  stan_data <- list(
    N = n,
    y = as.vector(scale(Y)),
    x = as.vector(scale(X)),
    z = as.vector(scale(Z))
  )

  # Fit model
  fit <- model$sample(
    data = stan_data,
    chains = chains,
    parallel_chains = 1,  # don't nest parallelism inside workers
    iter_sampling = iter_sampling,
    refresh = 0,          # suppress Stan progress output
    show_messages = FALSE,
    show_exceptions = FALSE
  )

  # Extract posterior summary for beta (the causal effect)
  summ <- fit$summary(variables = c("alpha", "beta", "gamma", "delta"))

  beta_row <- summ[summ$variable == "beta", ]
  delta_row <- summ[summ$variable == "delta", ]

  # 95% credible interval coverage
  beta_q5 <- beta_row$q5
  beta_q95 <- beta_row$q95
  covers <- (beta_true >= beta_q5) & (beta_true <= beta_q95)

  tibble::tibble(
    rep_id = rep_id,
    beta_mean = beta_row$mean,
    beta_median = beta_row$median,
    beta_sd = beta_row$sd,
    beta_q5 = beta_q5,
    beta_q95 = beta_q95,
    beta_rhat = beta_row$rhat,
    beta_covers = covers,
    delta_mean = delta_row$mean,
    delta_rhat = delta_row$rhat,
    n_divergent = sum(fit$diagnostic_summary(quiet = TRUE)$num_divergent)
  )
}
