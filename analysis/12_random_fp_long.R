# =============================================================================
# 12_random_fp_long.R
# Item 3 of the revision with longer chains: the site random effect on the
# false-positive rate (random_fp) mixed poorly in 07_revision_checks.R with
# 1000 + 1000 iterations (R-hat > 1.01 in 29-60% of fits, median smallest bulk
# ESS 377). Refits random_fp with 2000 + 2000 iterations to the same 400
# datasets: the four unstructured cells of 01_run_simulation.R, first 100
# replicates, regenerated from their seeds and checked against the original
# run before fitting. The constant-rate fits of 07 on the same datasets serve
# as the comparison.
#
# Each task is saved in data/revision_rfp_long_jobs/ as soon as it ends and
# skipped on a rerun. The seeds do not depend on REPS (they come from the 100
# replicates of the original design), so a test with fewer replicates is safe.
# Run from the compendium root, without the renv library:
#   RENV_ACTIVATE_PROJECT=FALSE WORKERS=16 Rscript analysis/12_random_fp_long.R
# =============================================================================
library(crywolf)
source("R/fp_sim_pilot.R")
source("R/fp_revision.R")

reps <- as.integer(Sys.getenv("REPS", "100"))
workers <- as.integer(Sys.getenv("WORKERS", "16"))
iter <- 2000
job_dir <- file.path("data", "revision_rfp_long_jobs")
dir.create(job_dir, showWarnings = FALSE)

des <- revision_designs()
unstructured <- which(!is.na(des$main$p10_beta_conc))
tasks <- revision_tasks(des$main, 100, 1000, "main")
tasks <- tasks[tasks$cell %in% unstructured & tasks$rep <= reps, ]

ok <- check_regeneration(tasks, des, readRDS(file.path("data", "fp_sim_results.rds")))
if (!all(ok)) stop(sum(!ok), " regenerated datasets differ from the original run.")
message(nrow(tasks), " datasets regenerated and matched.")

crywolf::fp_compile()   # once, before the workers
run_one <- function(rep, cell, seed, run) {
  f <- file.path(job_dir, sprintf("%s-cell%02d-rep%03d.rds", run, cell, rep))
  if (file.exists(f)) return(readRDS(f))
  cfg <- des[[run]][cell, , drop = FALSE]
  sim <- regenerate(cfg, seed)
  out <- cbind(run = run, rep = rep, cell = cell, seed = seed,
               p10 = cfg$p10, verified_coverage = cfg$verified_coverage,
               regime = "unstructured",
               fit_revision(to_fp_data(sim), sim, "random_fp", seed, iter = iter))
  out$model <- "random_fp_long"
  saveRDS(out, f)
  out
}
future::plan(future::multisession, workers = workers)
t0 <- Sys.time()
res <- furrr::future_pmap(tasks, run_one,
                          .options = furrr::furrr_options(seed = TRUE, chunk_size = 1)) |>
  purrr::list_rbind()
attr(res, "hours") <- as.numeric(difftime(Sys.time(), t0, units = "hours"))
saveRDS(res, file.path("data", "fp_revision_rfp_long_results.rds"))
message("done: ", nrow(res), " fits in ", round(attr(res, "hours"), 1), " h")
