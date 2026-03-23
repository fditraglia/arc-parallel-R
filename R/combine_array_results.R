# Combine results from job array tasks into a single data.frame.
# Run after all array tasks complete:
#   Rscript R/combine_array_results.R

files <- sort(list.files("results", pattern = "^04_job_array_task_.*\\.rds$",
                         full.names = TRUE))
if (length(files) == 0) stop("No job array result files found in results/")

cat("Combining", length(files), "result files...\n")
results <- do.call(rbind, lapply(files, readRDS))
cat("Total reps:", nrow(results), "\n")
cat("Mean beta1_hat:", mean(results$beta1_hat), "\n")

saveRDS(results, "results/04_job_array.rds")
cat("Combined results saved to results/04_job_array.rds\n")
