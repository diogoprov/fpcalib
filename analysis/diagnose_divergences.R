# =============================================================================
# diagnose_divergences.R
# Localize the divergence source, then test the fix on ONE cell before any
# 1200-fit re-run. Run from the fpcalib root. Needs cmdstanr, posterior,
# bayesplot. A few minutes total.
# =============================================================================
library(cmdstanr); library(posterior); library(bayesplot)
source("R/fp_sim_pilot.R")

one <- simulate_fp(nsite = 300, K = 20, p10 = 0.05, verified_coverage = 0.30, seed = 7)  # a baseline cell

# ---- (1) WHERE do the divergences live? Fit the CURRENT v2 model -------------
m_v2 <- cmdstanr::cmdstan_model("inst/stan/fp_occupancy_priors_v2.stan")
f_v2 <- m_v2$sample(data = one$stan_data, chains = 4,
                    iter_warmup = 1000, iter_sampling = 1000,
                    adapt_delta = 0.95, parallel_chains = 4, refresh = 0)
cat("v2 divergences:", sum(f_v2$diagnostic_summary(quiet = TRUE)$num_divergent), "\n")

np <- nuts_params(f_v2)
# If the red (divergent) draws pile up at the LOW end of sigma_u, it is the
# variance-component funnel (the estimate_re fix below removes it). If they pile
# up at the fp_gap boundary / low gamma0 instead, it is the p10 identifiability.
print(mcmc_parcoord(f_v2$draws(c("sigma_u", "u_raw[1]", "fp_gap", "gamma0", "beta[1]")), np = np))
print(mcmc_pairs(f_v2$draws(c("sigma_u", "fp_gap", "gamma0")), np = np,
                 off_diag_args = list(size = 0.8)))

# ---- (2) TEST the fix: same data, recorder RE toggled OFF --------------------
# The head-to-head cells generate sig_u = 0, so estimate_re should be 0 there.
sd_re <- one$stan_data
sd_re$estimate_re <- 0L                       # drop the RE from the likelihood
m_re <- cmdstanr::cmdstan_model("inst/stan/fp_occupancy_re_toggle.stan")
f_re <- m_re$sample(data = sd_re, chains = 4,
                    iter_warmup = 1000, iter_sampling = 1000,
                    adapt_delta = 0.95, parallel_chains = 4, refresh = 0)
cat("re-toggle (estimate_re=0) divergences:", sum(f_re$diagnostic_summary(quiet = TRUE)$num_divergent), "\n")

# Sanity: the estimand should be unchanged (true sig_u = 0), only the geometry.
cat("\np10  v2:", f_v2$summary("p10")$mean,   " | re:", f_re$summary("p10")$mean, "\n")
cat("b1   v2:", f_v2$summary("beta[2]")$mean, " | re:", f_re$summary("beta[2]")$mean, "\n")

# If (2) drops to ~0 divergences with matching estimates, adopt the toggle:
#   in simulate_fp(), add to stan_data:  estimate_re = as.integer(sig_u > 0)
#   and point run_pilot(stan_file = "inst/stan/fp_occupancy_re_toggle.stan").
# For the REAL manuscript data (which HAS recorders) keep estimate_re = 1L.
