# =============================================================================
# 03_run_fix_arm.R
# "The fix": show that modelling the false-positive rate as a function of the
# covariate (logit(p10) ~ xs) recovers the occupancy slope b1 that the
# constant-p10 model loses under structured confusion, and that verifying more
# was never the lever.
#
# Two blocks:
#   (A) confusion sweep at conf_cor = 0.7 (the realistic case): the same 10
#       cells as the main run's confusion arm (2 p10 x 5 verification levels).
#       We fit ONLY the fix here; the constant-p10 baseline for these cells is
#       already in data/fp_sim_summary.rds (300 reps), so the recovery figure
#       overlays the two.
#   (B) conf_cor = 1 pair (p10 tracks xs EXACTLY): the clean upper bound. Here
#       we fit BOTH the constant model and the fix on the same data
#       (also_constant = TRUE), because the main run has no conf_cor = 1 cell.
#       Expectation: constant-p10 coverage ~ 0, fix coverage ~ nominal (full
#       recovery, because the modelled covariate IS the true driver).
#
# Run from the COMPENDIUM ROOT. On the 18-core M5 Pro: 16 workers, one chain
# each (workers x parallel_chains <= cores, leaving 2 cores for the OS).
# At reps = 100 this is ~1,400 Stan fits, roughly 4.5 h ideal (median ~180 s
# per fit). Set reps = 50 to halve it; the recovery is a large effect, so 50
# replicates already separate the lines cleanly.
# =============================================================================
library(cmdstanr); library(posterior); library(unmarked)
library(purrr); library(dplyr); library(tidyr); library(furrr); library(future)

source("R/fp_sim_pilot.R")   # simulate_fp()
source("R/fp_fix.R")         # fit_fix(), run_fix(), summarise_fix()

fpcov_file <- normalizePath(file.path("inst", "stan", "fp_occupancy_fpcov.stan"))
const_file <- normalizePath(file.path("inst", "stan", "fp_occupancy_re_toggle.stan"))

reps    <- 100                 # <- 50 halves the runtime; the effect is large
WORKERS <- 16                  # 18-core M5 Pro, one chain per worker, 2 cores spare
FIT <- list(iter_warmup = 1000, iter_sampling = 1000,
            adapt_delta = 0.95, parallel_chains = 1)
# If the fix model shows divergences in the smoke test (the FP slope can make
# the p11 > p10 geometry tighter), raise adapt_delta to 0.99 here.

# --- (A) conf_cor = 0.7 sweep: fix only (constant baseline already computed) --
design_07 <- tidyr::expand_grid(
  p10 = c(0.05, 0.20), verified_coverage = c(0.10, 0.30, 0.50, 0.70, 0.90),
  nsite = 300, K = 20, psi = 0.5, p11 = 0.6) |>
  dplyr::mutate(sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 1.5, conf_cor = 0.7)

# --- (B) conf_cor = 1 pair: p10 tracks xs exactly; fit BOTH models -----------
design_cor1 <- tidyr::expand_grid(
  p10 = c(0.05, 0.20), verified_coverage = 0.30,
  nsite = 300, K = 20, psi = 0.5, p11 = 0.6) |>
  dplyr::mutate(sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 1.5, conf_cor = 1.0)

res_07 <- run_fix(design_07, reps = reps, fpcov_file = fpcov_file, const_file = const_file,
                  base_seed = 9000, parallel = TRUE, workers = WORKERS,
                  also_constant = FALSE, fit_args = FIT)

res_cor1 <- run_fix(design_cor1, reps = reps, fpcov_file = fpcov_file, const_file = const_file,
                    base_seed = 12000, parallel = TRUE, workers = WORKERS,
                    also_constant = TRUE, fit_args = FIT)

res <- dplyr::bind_rows(res_07, res_cor1)

saveRDS(res,                 file.path("data", "fp_fix_results.rds"))

saveRDS(summarise_fix(res),  file.path("data", "fp_fix_summary.rds"))

print(summarise_fix(res), width = Inf)
