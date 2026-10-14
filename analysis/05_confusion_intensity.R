# =============================================================================
# 05_confusion_intensity.R
# Where does the constant-p10 correction stop protecting the occupancy slope?
#
# Clare et al. (2021) found the constant-FP correction nearly unbiased under
# covariate-dependent false positives; our confusion arm (conf_effect = 1.5,
# conf_cor = 0.7) found b1 attenuated or reversed, and the 10-90% verification
# sweep showed that verifying more does not rescue it. So the difference is not
# verification effort. This block varies the two INTENSITY knobs of the
# confusion, at fixed verification (30%) and a low base rate (p10 = 0.05):
#
#   conf_effect : slope of logit(p10) on the confusion gradient w
#                 (0.25 weak ... 1.5 = our main arm)
#   conf_cor    : correlation of w with the occupancy covariate
#                 (0.3 ... 1.0; at 1.0, w IS the occupancy covariate, i.e.
#                 false positives depend on the same covariate as the state)
#
# 4 x 3 = 12 cells, constant-p10 model + occuFP via run_pilot(), exactly as in
# 01_run_simulation.R. The cell (1.5, 0.7) duplicates a core cell of the main
# run on NEW datasets (different base_seed): its b1 coverage should match the
# original within Monte Carlo error, a reproducibility check for free.
#
# Note: raising conf_effect also raises the MARGINAL false-positive rate
# (mean over sites of plogis(logit(0.05) + conf_effect * w)); the summary
# reports it per cell so intensity and base rate are not confused in the text.
#
# Cost: 12 cells x 100 reps = 1,200 fits; ~171 s per fit on 16 workers,
# roughly 3.5 h. Run with the COMPENDIUM ROOT as the working directory.
# =============================================================================
library(cmdstanr); library(posterior); library(unmarked)
library(purrr); library(dplyr); library(tidyr); library(furrr); library(future)
library(ggplot2)

source("R/fp_sim_pilot.R")

stan_file <- normalizePath(file.path("inst", "stan", "fp_occupancy_re_toggle.stan"))
invisible(cmdstanr::cmdstan_model(stan_file))   # compile once before the workers (no-op if up to date)

design_int <- tidyr::expand_grid(conf_effect = c(0.25, 0.5, 1.0, 1.5),
                                 conf_cor    = c(0.3, 0.7, 1.0),
                                 p10 = 0.05, verified_coverage = 0.30,
                                 nsite = 300, K = 20, psi = 0.5, p11 = 0.6) |>
  dplyr::mutate(sigma_p10 = 0, p10_beta_conc = NA)

fit_args <- list(iter_warmup = 1000, iter_sampling = 1000,
                 adapt_delta = 0.95, parallel_chains = 1)
base_seed_int <- 9000             # disjoint from 1000 (main) and 5000 (confusion)

# --- (1) smoke test: 2 replicates per cell (24 fits) --------------------------
smoke <- run_pilot(design_int, reps = 2, stan_file = stan_file,
                   base_seed = base_seed_int, parallel = TRUE, workers = 12,
                   fit_args = fit_args)
smoke |>
  dplyr::select(true_conf_effect, true_conf_cor, true_p10_marginal,
                stan_b1_est, stan_b1_cov, stan_ndiv, stan_max_rhat, stan_runtime) |>
  tibble::as_tibble() |> print(n = Inf, width = Inf)
if (!any(smoke$stan_ok)) stop("Smoke test: no Stan fit succeeded; see the messages above.")

# --- (2) full run -------------------------------------------------------------
reps_int <- 100
res_int  <- run_pilot(design_int, reps = reps_int, stan_file = stan_file,
                      base_seed = base_seed_int, parallel = TRUE, workers = 16,
                      fit_args = fit_args)
saveRDS(res_int, file.path("data", "fp_intensity_results.rds"))

# --- (3) summary: the usual per-cell table + realized marginal FP rate --------
summ_int <- summarise_pilot(res_int) |>
  dplyr::left_join(
    res_int |>
      dplyr::group_by(conf_effect = true_conf_effect, conf_cor = true_conf_cor) |>
      dplyr::summarise(p10_marginal = mean(true_p10_marginal),
                       b1_cov_mcse  = sqrt(mean(stan_b1_cov, na.rm = TRUE) *
                                           (1 - mean(stan_b1_cov, na.rm = TRUE)) / dplyr::n()),
                       .groups = "drop"),
    by = c("conf_effect", "conf_cor"))
saveRDS(summ_int, file.path("data", "fp_intensity_summary.rds"))
summ_int |>
  dplyr::select(conf_effect, conf_cor, p10_marginal, stan_b1_coverage95, b1_cov_mcse,
                stan_b1_bias, stan_p10_coverage95, occufp_b1_coverage95, stan_conv_rate) |>
  print(width = Inf)

# --- (4) figure: b1 coverage and bias over the intensity grid ----------------
fig_int <- summ_int |>
  dplyr::select(conf_effect, conf_cor, Coverage = stan_b1_coverage95,
                Bias = stan_b1_bias) |>
  tidyr::pivot_longer(c(Coverage, Bias), names_to = "metric") |>
  ggplot(aes(conf_effect, value, colour = factor(conf_cor))) +
  geom_hline(data = data.frame(metric = c("Coverage", "Bias"), ref = c(0.95, 0)),
             aes(yintercept = ref), linetype = 2, colour = "grey60") +
  geom_line() + geom_point(size = 2.2) +
  facet_wrap(~ metric, scales = "free_y") +
  labs(x = "Confusion effect on logit(p10)", y = NULL,
       colour = "cor(w, occupancy covariate)") +
  theme_bw(base_size = 12) + theme(legend.position = "top")
ggsave(file.path("manuscript", "figures", "figF_confusion_intensity.pdf"),
       fig_int, width = 8, height = 4)
