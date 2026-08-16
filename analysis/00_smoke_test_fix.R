# =============================================================================
# 00_smoke_test_fix.R  —  RUN THIS FIRST, before 03_run_fix_arm.R.
# Compiles the covariate-p10 model and fits ONE dataset per regime, so a syntax
# error or a bad sampler geometry shows up in a couple of minutes rather than
# after the overnight run. Run from the compendium root.
# =============================================================================
library(cmdstanr); library(unmarked); library(posterior)
library(purrr); library(dplyr); library(tidyr)
source("R/fp_sim_pilot.R")   # simulate_fp()
source("R/fp_fix.R")         # fit_fix()

fpcov <- cmdstan_model("inst/stan/fp_occupancy_fpcov.stan")        # <- watch for compile errors
const <- cmdstan_model("inst/stan/fp_occupancy_re_toggle.stan")

# ---- (1) realistic structured confusion, conf_cor = 0.7, 30% verified -------
one07 <- simulate_fp(nsite = 300, K = 20, p10 = 0.20, verified_coverage = 0.30,
                     conf_effect = 1.5, conf_cor = 0.7, seed = 1)
row07 <- fit_fix(one07, fpcov_mod = fpcov, const_mod = const, also_constant = TRUE,
                 iter_warmup = 1000, iter_sampling = 1000, adapt_delta = 0.95,
                 parallel_chains = 4, verbose = TRUE)
cat("\n=== conf_cor = 0.7 ===\n"); print(t(row07))

# ---- (2) p10 tracks xs exactly, conf_cor = 1 -> expect FULL recovery --------
one1 <- simulate_fp(nsite = 300, K = 20, p10 = 0.20, verified_coverage = 0.30,
                    conf_effect = 1.5, conf_cor = 1.0, seed = 1)
row1 <- fit_fix(one1, fpcov_mod = fpcov, const_mod = const, also_constant = TRUE,
                iter_warmup = 1000, iter_sampling = 1000, adapt_delta = 0.95,
                parallel_chains = 4)
cat("\n=== conf_cor = 1.0 ===\n"); print(t(row1))

# WHAT TO CHECK (true b1 = -0.8):
#   fixstan_max_rhat <= 1.01 and fixstan_ndiv small (0-2).
#     If fixstan_ndiv is large, raise adapt_delta to 0.99 in 03_run_fix_arm.R.
#   const_b1_cov  == FALSE, const_b1_est near 0  (constant model still fails).
#   fixstan_b1_cov == TRUE, fixstan_b1_est near -0.8 (the fix recovers b1);
#     recovery is partial at cor = 0.7, essentially full at cor = 1.
#   fixstan_gamma_fp > 0 (p10 rises with the covariate; ~ conf_effect*conf_cor).
#   fixocc_b1_cov should track fixstan_b1_cov (the fix works in occuFP too),
#     unless fixocc_degenerate == TRUE.
