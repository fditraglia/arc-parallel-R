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

#' Run one rep with ALL 9 test-config estimators, no callr, no wrapping.
#'
#' Calls bdml package functions directly:
#' - Stan: bdml::get_model() + model$sample() (no callr subprocess)
#' - Non-Stan: bdml::sim_iter_nonstan() (no capture.output)
#'
#' @param n,p,R_Y2,R_D2,rho,alpha DGP parameters
#' @return Data frame with one row per estimator
sim_task_bdml_all <- function(n = 200, p = 10, R_Y2 = 0.5, R_D2 = 0.5,
                               rho = 0.8, alpha = 0.25) {
  data <- bdml::generate_data(n, p, R_Y2, R_D2, rho, alpha)
  seed_base <- sample.int(.Machine$integer.max, 1)

  model_type <- c(
    "BDML-LKJ-HP",
    "BDML-IW-JS-MAT",
    "Linero", "HCPH", "Naive",
    "FDML-Full", "FDML-XFit",
    "OLS", "Oracle"
  )

  results <- list()

  for (estimator in model_type) {
    tryCatch({
      if (bdml::is_stan_method(estimator)) {
        # Stan: fit directly, no callr
        result <- bdml::sim_iter_stan(estimator, data = data, seed = seed_base)
      } else {
        # Non-Stan: call directly, no capture.output
        result <- bdml::sim_iter_nonstan(estimator, data = data, seed = seed_base)
      }
      result$status <- "success"
      result$error_msg <- NA_character_
      results[[estimator]] <- result
    }, error = function(e) {
      results[[estimator]] <<- data.frame(
        alpha_hat = NA_real_, squared_error = NA_real_,
        LCL = NA_real_, UCL = NA_real_, catch = NA,
        interval_width = NA_real_, Method = estimator,
        status = "error", error_msg = conditionMessage(e),
        stringsAsFactors = FALSE
      )
    })
  }

  out <- do.call(rbind, results)
  # Drop grid columns — tar_map_rep appends them
  grid_cols <- c("n", "p", "R_Y2", "R_D2", "rho", "alpha", "x_cor")
  out[intersect(grid_cols, names(out))] <- NULL
  out
}
