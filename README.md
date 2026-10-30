# fpcalib

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23379099.svg)](https://doi.org/10.5281/zenodo.23379099)

Research compendium for the manuscript

> Provete, D. B., Rhinehart, T., Piatti, L., & Sugai, L. S. M. *Verifying more
> is not enough when false positives track the environmental gradient in
> occupancy models* (working title), in preparation for *Methods in Ecology and
> Evolution*.

It holds the models, the simulation code, the scored outputs, and the scripts
that reproduce the results and figures. The question is practical: automated
acoustic classifiers return false positives, and the multiple-methods
false-positive occupancy model corrects for them with a subset of verified
detections, assuming a constant false-positive rate. Does that correction keep
the 95% intervals of the environmental effect honest when the false-positive
rate varies among sites, and in particular when it tracks the same gradient as
the species?

The reusable model, with a formula interface, simulation, and calibration
checks, is the R package **crywolf** (https://github.com/diogoprov/crywolf).
This compendium stays frozen at the code that produced the results of the
manuscript.

## The model

A Bayesian single-season occupancy model with false positives, following the
multiple-detection-method (site-confirmation) design of Miller et al. (2011),
written in Stan with the latent occupancy state marginalized. Classifier
detections may be false positives; verified clips are certain and anchor the
false-positive rate. A positive gap between the true- and false-positive
intercepts prevents label switching. The false-positive rate is either
constant or a function of site covariates. Each dataset is also fitted with the
frequentist `occuFP` estimator from **unmarked**.

## Repository layout

```
fpcalib/
├── DESCRIPTION, LICENSE.md, CITATION.cff, .Rprofile (renv stub)
├── AI_INTERACTION_LOG.md          record of the human-AI collaboration
├── inst/stan/
│   ├── fp_occupancy_re_toggle.stan   constant false-positive rate (main study)
│   ├── fp_occupancy_fpcov.stan       false-positive rate on site covariates (Kfp = 0 recovers the constant model)
│   ├── fp_occupancy_priors_v2.stan   model of the empirical nightjar analysis (JAV-03737), revised priors
│   └── fp_occupancy.stan             the same, original priors
├── R/
│   ├── fp_sim_pilot.R          simulate_fp(), fit_both(), run_pilot(), summarise_pilot()
│   ├── fp_fix.R                fit_fix(), run_fix(), summarise_fix(): false-positive rate on the occupancy covariate
│   ├── fp_positive_control.R   fit_fpcov(), run_positive_control(), pair_with_constant()
│   ├── fp_diagnostics.R        fp_calibration_check(), how_much_to_verify()
│   ├── fp_revision.R           refits of the revision checks with crywolf (07)
│   ├── fig_dag.R, fig_dag_v2.R model DAG
│   └── figs_didaticas_curiango.R
├── analysis/                   scripts, run in order from the compendium root
├── data/                       scored outputs (.rds), kept under version control
├── Dockerfile, aws/            long runs on an AWS EC2 spot instance (aws/README.md)
└── manuscript/
    ├── reproduce.qmd           Figures 3–7 and every number in the text, checked against data/
    ├── appendix-S1.qmd         Appendix S1 of the manuscript
    ├── figures/                manuscript figures and the scripts that draw them
    └── fpcalib_vs_simFPOcc.md  comparison with the simFPOcc framework
```

## The simulation design

Every dataset has 300 sites, 20 classifier occasions per site, occupancy
probability 0.5 at the mean of the covariate, true-detection probability 0.6,
and an environmental effect (occupancy slope) of −0.8. Three false-positive
regimes are crossed with two base false-positive rates (0.05 and 0.20) and the
fraction of sites verified:

1. **Homogeneous:** the same false-positive rate at every site, as the model
   assumes.
2. **Unstructured:** the rate varies at random among sites (Beta, concentration
   2), unrelated to the covariate.
3. **Structured confusion:** the logit of the rate rises along a latent gradient
   w (effect 1.5) correlated at 0.7 with the occupancy covariate, as when an
   acoustically similar species tracks the same gradient.

| Script | What it does | Output |
|---|---|---|
| `01_run_simulation.R` | main study: 23 cells (the 3 regimes × 2 rates × 10% and 30% verified, two near-boundary cells at a rate of 0.01, a verification sweep at 0%, 5%, and 50%, and structured confusion at 50%, 70%, and 90% verified); 100 replicates per cell, 300 for the structured-confusion cells; constant-rate Stan model and `occuFP` | `data/fp_sim_results.rds`, `data/fp_sim_summary.rds` |
| `02_make_figures.R` | superseded: coverage figures of the first run of 100 replicates | `analysis/figures/` |
| `03_run_fix_arm.R` | false-positive rate modelled on the occupancy covariate, in Stan and in `occuFP`, for the structured-confusion cells, plus two cells in which false positives depend on that covariate exactly; 100 replicates per cell | `data/fp_fix_*.rds` |
| `04_positive_control.R` | false-positive rate modelled on the confusing gradient w and on a noisy proxy of it (correlation 0.7), refitted to the first 100 datasets of every structured-confusion cell of `01` and paired with those fits | `data/fp_positive_control_*.rds` |
| `05_confusion_intensity.R` | strength (0.25, 0.5, 1.0, 1.5) × correlation (0.3, 0.7, 1.0) of the confusion, at a rate of 0.05 with 30% verified; constant-rate model in both frameworks; 100 replicates per cell | `data/fp_intensity_*.rds` |
| `06_manuscript_figures.R` | superseded by `14`: earlier drawing of the coverage of b1 against verification and of the intensity grid | `manuscript/figures/fig6_*`, `fig7_*` |
| `07_revision_checks.R` | revision checks refitted with crywolf: cost of the occupancy covariate in the false-positive process under homogeneous false positives, a site random effect on the false-positive rate under unstructured heterogeneity, and leave-one-site-out cross-validation and posterior predictive checks under structured confusion; 100 replicates per cell | `data/fp_revision_results.rds` |
| `08_observation_confirmation.R` | structured confusion (effect 1.5) under the observation-confirmation design, 5%, 10% or 30% of the automated occasions checked, plus two homogeneous cells; 100 replicates per cell | `data/fp_obsconfirm_results.rds` |
| `09_revision_summary.R` | summaries, tables and figures of 07, 08 and 10 | `data/fp_revision_summary.rds`, `analysis/tables/`, `analysis/figures/` |
| `10_obsconfirm_weak.R` | the design of 08 at the confusion effects 0.5 and 1.0 | `data/fp_obsconfirm_weak_results.rds` |
| `12_random_fp_long.R` | the site random effect on the false-positive rate of 07 refitted with 2,000 + 2,000 iterations to the same 400 unstructured datasets | `data/fp_revision_rfp_long_results.rds` |
| `11_obsconfirm_clare.R` | the design of 08 with false positives on the occupancy covariate itself (correlation 1.0), effects 0.5, 1.0 and 1.5, plus an occupancy model that ignores false positives | `data/fp_obsconfirm_clare_results.rds` |
| `13_fig4_caterpillars.R` | Figure 4: per-replicate intervals of four cells of `01` | `manuscript/figures/Fig4_*` |
| `14_figs_3_5_6.R` | Figures 3 (the three regimes), 5 (coverage of b1 against verification, four models) and 6 (the intensity grid), from the summaries only | `manuscript/figures/Fig3_*`, `Fig5_*`, `Fig6_*` |
| `15_nightjar.R` | the nightjar example: six fits of crywolf 1.9.0 to its curiango data, at four classifier thresholds | `data/nightjar_fits.rds` |
| `16_fig7_nightjar.R` | Figure 7: the nightjar example by threshold | `manuscript/figures/Fig7_*` |

All Stan fits used four chains of 1,000 warm-up and 1,000 sampling iterations,
with a target acceptance rate of 0.95, parallelized across fits with **furrr**.
Each replicate draws from a stored seed, so scripts 03 to 05 can regenerate the
datasets of the main run; `04` stops if they do not match.

## What the study shows

- With homogeneous false positives, both frameworks are calibrated.
- With unstructured heterogeneity, the false-positive rate is estimated poorly,
  but the environmental effect is largely spared.
- With structured confusion, the 95% interval of the environmental effect
  contains the truth in only 8–20% of replicates at a base rate of 0.05 and in
  none at 0.20, the effect is pulled towards zero, and verifying up to 90% of
  the sites does not fix it.
- Modelling the false-positive rate on the confusing gradient restores nominal
  coverage (0.90–0.97). Modelling it on the occupancy covariate, which a user
  always has, recovers part of it (0.48–0.66 and 0.08–0.48 at the two rates)
  and improves with verification; when false positives depend on that
  covariate exactly, the recovery is complete.
- Weak confusion (an effect of 0.5 or less on the logit scale) leaves the
  constant-rate correction calibrated at every correlation tested.
- Placing the occupancy covariate in the false-positive process costs almost
  nothing when false positives are homogeneous (interval widths within 2%).
- Leave-one-site-out cross-validation detects strong structured confusion; the
  posterior predictive check detects a false-positive rate that varies among
  sites, but not whether it tracks the covariate.
- Under observation confirmation, the constant-rate correction holds for weak
  confusion at the lower false-positive rate and improves as more occasions are
  checked; with the occupancy covariate in the false-positive process, coverage
  is 0.89–0.98 in every cell with 30% of occasions checked.
- When false positives depend on the occupancy covariate itself, the
  constant-rate correction removes 47–100% of the bias of a model that ignores
  false positives, yet where it removes 47–74% its intervals cover the truth in
  at most 4% of replicates; the covariate-dependent model covers it in 92–98%.

## Reproducing the study

Prerequisites, once:

```r
install.packages(c("purrr", "dplyr", "tidyr", "furrr", "future",
                   "posterior", "unmarked", "ggplot2", "patchwork"))
install.packages("cmdstanr",
                 repos = c("https://stan-dev.r-universe.dev", getOption("repos")))
cmdstanr::install_cmdstan()
```

The results were produced with CmdStan 2.39.0 and cmdstanr 0.9.0. Then, from
the compendium root, run the scripts in `analysis/` in numerical order. The
full set takes many hours on a multi-core machine; the scored `.rds` files in
`data/` let you regenerate the summaries and figures without rerunning the
simulations. Scripts 04 and 05 start with a short smoke test. Scripts 07, 08,
10 to 12 and 15 also need the R package crywolf (see `analysis/README.md`).

To check the manuscript against the stored results without rerunning
anything, render `manuscript/reproduce.qmd` from the compendium root:

```sh
quarto render manuscript/reproduce.qmd
```

It reads only `data/`, redraws Figures 3 to 7 and recomputes every number
reported in the Results and Discussion, and it stops with a list of the
numbers that disagree, if any (`-P strict:false` reports them in a table
instead). `manuscript/appendix-S1.qmd` renders Appendix S1 the same way.

The runs of scripts 07, 08 and 10 (and later ones built the same way) can go
to a single AWS EC2 spot instance instead of a local machine: `Dockerfile`
and `aws/` (see `aws/README.md`) run one script in a container, save its
job files to S3 so that an interrupted run resumes, and stop the instance at
the end.

## Citing

Please cite the archived version of this compendium,
doi:[10.5281/zenodo.23379099](https://doi.org/10.5281/zenodo.23379099), and the manuscript once published. The
full citation metadata are in `CITATION.cff`.

Miller, D. A., Nichols, J. D., McClintock, B. T., Grant, E. H. C., Bailey,
L. L., & Weir, L. A. (2011). Improving occupancy estimation when two types of
observational error occur: non-detection and species misidentification.
*Ecology*, 92, 1422–1428. https://doi.org/10.1890/10-1396.1

## License

GPL-3, because the code imports **unmarked** (GPL). See `LICENSE.md`.
