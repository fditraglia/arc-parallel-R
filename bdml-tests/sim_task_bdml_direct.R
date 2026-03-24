#' Lazy-load the BDML-LKJ-HP Stan model via bdml package.
get_bdml_model <- local({
  model <- NULL
  function() {
    if (is.null(model)) {
      model <<- bdml::get_model("BDML-LKJ-HP")
    }
    model
  }
})

#' Run one rep: bdml DGP + bdml Stan model, no callr, no wrapping.
#'
#' @param n,p,R_Y2,R_D2,rho,alpha DGP parameters
#' @return One-row tibble
sim_task_bdml_direct <- function(n = 200, p = 10, R_Y2 = 0.5, R_D2 = 0.5,
                                  rho = 0.8, alpha = 0.25) {
  data <- bdml::generate_data(n, p, R_Y2, R_D2, rho, alpha)

  model <- get_bdml_model()
  fit <- model$sample(
    data = list(
      p = as.integer(p),
      n = as.integer(n),
      X = data$X,
      Y = cbind(data$Y, data$D)
    ),
    chains = 1,
    parallel_chains = 1,
    refresh = 0,
    show_messages = FALSE,
    show_exceptions = FALSE
  )

  alpha_draws <- fit$draws("alpha", format = "matrix")
  alpha_hat <- mean(alpha_draws)
  alpha_q5 <- quantile(alpha_draws, 0.05)
  alpha_q95 <- quantile(alpha_draws, 0.95)

  tibble::tibble(
    alpha_hat = alpha_hat,
    alpha_q5 = unname(alpha_q5),
    alpha_q95 = unname(alpha_q95),
    alpha_covers = (alpha >= alpha_q5) & (alpha <= alpha_q95),
    n_divergent = sum(fit$diagnostic_summary(quiet = TRUE)$num_divergent)
  )
}
