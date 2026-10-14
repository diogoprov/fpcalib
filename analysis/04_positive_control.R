# =============================================================================
# 04_positive_control.R
# Positive control for the structured-confusion arm: refit the SAME datasets
# that 01_run_simulation.R fitted with the constant-p10 model, now with the
# model in which p10 depends on the confusion gradient
# (inst/stan/fp_occupancy_fpcov.stan), with W = the true gradient
# (proxy_cor = 1) and with a noisy proxy of it (proxy_cor = 0.7).
#
# Expected if the attenuation of b1 is a misspecification artefact:
#   proxy_cor = 1   -> b1 coverage back near 0.95, bias near 0, at every
#                      verification level and both p10 levels;
#   proxy_cor = 0.7 -> partial recovery (a noisy proxy leaves part of the
#                      confusion unmodelled).
# One-dataset check before this script was written (p10 = 0.20, 30% verified):
# constant b1 = +0.12; fpcov(W = w) b1 = -0.71 [-1.03, -0.40]; fpcov(r = 0.7)
# b1 = -0.24 (true -0.8). Single replicate, indicative only.
#
# Run with the COMPENDIUM ROOT as the working directory, on the same machine /
# R version as 01_run_simulation.R (the pairing check in step 3 stops the
# script if the regenerated datasets differ from the original ones).
#
# Cost: 10 cells x reps x 2 proxy levels Stan fits. At reps = 100 that is
# 2,000 fits; at ~170 s per fit on 16 workers, roughly 6 h (the fpcov model
# may be somewhat slower; step 1 times it).
# =============================================================================
library(cmdstanr); library(posterior)
library(purrr); library(dplyr); library(tidyr); library(furrr); library(future)
library(ggplot2)

source("R/fp_sim_pilot.R")        # simulate_fp() (must return `w`)
source("R/fp_positive_control.R")

stan_file <- normalizePath(file.path("inst", "stan", "fp_occupancy_fpcov.stan"))
# Compile ONCE here, before the workers start. If the binary is missing, every
# furrr worker compiles it at the same time and they overwrite each other's
# executable (corrupted binary: "cannot execute binary file").
# force_recompile also replaces a corrupted binary left by an earlier attempt.
invisible(cmdstanr::cmdstan_model(stan_file, force_recompile = TRUE))

# --- design: the 10 confusion cells, in EXACTLY the order of design_conf in ---
#     01_run_simulation.R (core confusion cells, then the 50/70/90% sweep), so
#     that cell indices and seeds line up with the original run.
conf_core  <- tidyr::expand_grid(p10 = c(0.05, 0.20), verified_coverage = c(0.10, 0.30),
                                 nsite = 300, K = 20, psi = 0.5, p11 = 0.6)
conf_sweep <- tidyr::expand_grid(p10 = c(0.05, 0.20), verified_coverage = c(0.50, 0.70, 0.90),
                                 nsite = 300, K = 20, psi = 0.5, p11 = 0.6)
design_conf <- dplyr::bind_rows(conf_core, conf_sweep) |>
  dplyr::mutate(sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 1.5, conf_cor = 0.7)

base_seed_conf <- 5000            # base_seed of res_conf in 01_run_simulation.R
fit_args <- list(iter_warmup = 1000, iter_sampling = 1000,
                 adapt_delta = 0.95, parallel_chains = 1)
res_const <- readRDS(file.path("data", "fp_sim_results.rds"))

# NOTE: keep parallel = TRUE (the default), as in the original run. furrr with
# seed = TRUE switches the workers to the L'Ecuyer-CMRG generator, so a
# sequential run would probably draw different datasets from the same seeds.
# The pairing check in steps 1 and 3 stops the script if that happens.

# --- (1) smoke test: 1 replicate of every cell, both proxies (20 fits) --------
#     Checks that simulate_fp() returns w, that the datasets match the original
#     run (pair_with_constant() stops otherwise), and times one fpcov fit.
smoke <- run_positive_control(design_conf, reps = 1, stan_file = stan_file,
                              base_seed = base_seed_conf, workers = 10,
                              fit_args = fit_args)
smoke_p <- pair_with_constant(smoke, res_const)
smoke_p |>
  dplyr::select(cell, proxy_cor, true_p10, verified_coverage, const_b1_est,
                fpcov_b1_est, fpcov_b1_cov, fpcov_g1_est, fpcov_ndiv,
                fpcov_max_rhat, fpcov_runtime) |>
  tibble::as_tibble() |> print(n = Inf, width = Inf)
if (!any(smoke_p$fpcov_ok)) stop("Smoke test: no fpcov fit succeeded; see the messages above.")

# --- (2) full run -------------------------------------------------------------
#     100 replicates = the first 100 datasets of the original 300 per cell.
#     MC SE of a coverage near 0.95 at 100 reps ~ 0.022 (enough to tell 0.95
#     from the constant model's 0.00-0.20). Raise to 300 to match the
#     constant-model precision exactly.
reps_pc <- 100
res_pc  <- run_positive_control(design_conf, reps = reps_pc, stan_file = stan_file,
                                base_seed = base_seed_conf, workers = 16,
                                fit_args = fit_args)
saveRDS(res_pc, file.path("data", "fp_positive_control_results.rds"))

# --- (3) pair with the constant-p10 fits on the same datasets + summarise ----
paired  <- pair_with_constant(res_pc, res_const)
summ_pc <- summarise_positive_control(paired)
saveRDS(summ_pc, file.path("data", "fp_positive_control_summary.rds"))
print(summ_pc, width = Inf)

# --- (4) figure: b1 coverage vs verification, three models -------------------
fig_dat <- dplyr::bind_rows(
  summ_pc |> dplyr::filter(proxy_cor == 1) |>
    dplyr::transmute(p10, coverage, cov95 = const_b1_cov95,
                     model = "Constant p10"),
  summ_pc |> dplyr::transmute(p10, coverage, cov95 = fpcov_b1_cov95,
                              model = sprintf("p10 ~ W (proxy r = %.1f)", proxy_cor))
) |>
  dplyr::mutate(p10 = sprintf("p10 = %.2f", p10))

fig_pc <- ggplot(fig_dat, aes(coverage, cov95, colour = model)) +
  geom_hline(yintercept = 0.95, linetype = 2, colour = "grey60") +
  geom_line() + geom_point(size = 2.2) +
  facet_wrap(~ p10) +
  scale_x_continuous(labels = scales::percent) +
  coord_cartesian(ylim = c(0, 1)) +
  labs(x = "Sites verified", y = "Coverage of the 95% CrI for b1", colour = NULL) +
  theme_bw(base_size = 12) + theme(legend.position = "top")
ggsave(file.path("manuscript", "figures", "figE_positive_control_b1.pdf"),
       fig_pc, width = 8, height = 4)
