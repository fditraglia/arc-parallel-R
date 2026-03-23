#' Run one simulation replicate: generate data, fit OLS, get bootstrap CIs.
#'
#' DGP: y = beta1 * x1 + beta2 * x2 + ... + beta_p * xp + epsilon
#'   X ~ N(0, Sigma) with AR(1) correlation (rho = 0.5)
#'   epsilon ~ N(0, 1)
#'   beta = (2, -1, 0.5, 0, ..., 0) with p = 50 covariates
#'   n = 2000
#'
#' Each rep generates data, fits OLS, then runs B = 2000 bootstrap resamples
#' to get bootstrap SEs and 95% CIs for all coefficients.
#' Designed to take ~2-4 seconds per rep.
#'
#' @param rep_id Replicate ID (for tracking)
#' @return A one-row tibble with point estimates, bootstrap SEs, and coverage
sim_task <- function(rep_id) {
  n <- 2000
  p <- 50
  B <- 2000
  true_beta <- c(2, -1, 0.5, rep(0, p - 3))

  # AR(1) covariance: Sigma[i,j] = rho^|i-j|
  rho <- 0.5
  Sigma <- rho^abs(outer(1:p, 1:p, "-"))
  L <- chol(Sigma)

  # Generate data
  X <- matrix(rnorm(n * p), n, p) %*% L
  epsilon <- rnorm(n)
  y <- X %*% true_beta + epsilon

  # Point estimates
  fit <- lm(y ~ X - 1)
  beta_hat <- coef(fit)

  # Bootstrap
  boot_coefs <- matrix(NA, B, p)
  for (b in seq_len(B)) {
    idx <- sample.int(n, replace = TRUE)
    boot_fit <- lm(y[idx] ~ X[idx, ] - 1)
    boot_coefs[b, ] <- coef(boot_fit)
  }

  boot_se <- apply(boot_coefs, 2, sd)
  boot_lower <- apply(boot_coefs, 2, quantile, 0.025)
  boot_upper <- apply(boot_coefs, 2, quantile, 0.975)
  coverage <- (true_beta >= boot_lower) & (true_beta <= boot_upper)

  tibble::tibble(
    rep_id = rep_id,
    beta1_hat = unname(beta_hat[1]),
    beta2_hat = unname(beta_hat[2]),
    beta3_hat = unname(beta_hat[3]),
    boot_se1 = boot_se[1],
    boot_se2 = boot_se[2],
    boot_se3 = boot_se[3],
    coverage_rate = mean(coverage)
  )
}

#' Combine a list of sim_task results into a tibble
combine_results <- function(results) {
  dplyr::bind_rows(results)
}
