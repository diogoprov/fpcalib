# fpcalib

Calibration of a Bayesian false-positive occupancy model under detection heterogeneity.

This is a research compendium, not yet a full package: it holds the model, the
simulation code, and the scripts that reproduce every figure in the software
note that accompanies JAV-03737. The question it answers is narrow and
practical: when the false-positive rate of an automated acoustic classifier
varies across sites, do the model's 95% intervals still contain the truth 95% of
the time? The answer depends on how that variation is structured, and the
compendium quantifies it.

## What is inside

The Bayesian false-positive (misclassification) single-season occupancy model
follows the multiple-detection-method design of Miller et al. (2011), fit in
Stan and marginalized over the latent occupancy state. A subset of verified
recordings anchors the false-positive rate. The compendium simulates data from
this model under three false-positive regimes, fits both the Stan model and the
frequentist `occuFP` estimator from `unmarked` to each dataset, and scores 95%
interval coverage and bias for three quantities: the false-positive rate
(`p10`), nightly use (`psi`), and the occupancy slope (`b1`, the effect of the
environmental covariate).

## Repository layout

```
fpcalib/
├── DESCRIPTION            package-style metadata (name, deps, license)
├── README.md             this file
├── LICENSE.md            GPL-3
├── CITATION.cff          citation metadata (add the Zenodo DOI at archiving)
├── .Rprofile             renv activation stub
├── inst/stan/
│   ├── fp_occupancy_priors_v2.stan   the model used for the simulation
│   └── fp_occupancy.stan             the manuscript-priors version
├── R/
│   ├── fp_sim_pilot.R                simulate_fp(), fit_both(), run_pilot(), summarise_pilot()
│   └── figs_didaticas_curiango.R     coverage-caterpillar and flow-diagram helpers
├── analysis/
│   ├── 01_run_simulation.R           reproduce the 100-replicate study
│   └── 02_make_figures.R             regenerate the coverage figures
└── data/                             scored outputs (written by 01)
```

## Reproducing the study

Prerequisites, once:

```r
install.packages(c("purrr", "dplyr", "tidyr", "furrr", "future",
                   "posterior", "unmarked", "ggplot2", "patchwork"))
install.packages("cmdstanr",
                 repos = c("https://stan-dev.r-universe.dev", getOption("repos")))
cmdstanr::install_cmdstan()   # builds CmdStan; record the version in this README
```

Then, from the compendium root:

```r
source("analysis/01_run_simulation.R")   # runs the simulation, writes data/*.rds
source("analysis/02_make_figures.R")     # writes analysis/figures/*.pdf
```

Pinning the exact package versions with `renv::init()` is recommended before
archiving (see `.Rprofile`). CmdStan is installed separately, so note its
version here for the record: CmdStan __._._ .

## The simulation design

Twelve cells cross three false-positive regimes with two true `p10` levels
(0.05 and 0.20) and two verification-coverage levels (10% and 30% of site-visits
verified), 100 replicates each. Every cell fixes nightly use `psi` = 0.5, true
detection `p11` = 0.6, and the true environmental effect `b1` = −0.8. The three
regimes are:

(i) homogeneous, where every site shares the same false-positive rate (the
model's assumption); (ii) unstructured (Beta), where the rate varies at random
across sites with no relation to the covariate; and (iii) structured confusion,
where the rate is correlated with the environmental covariate itself, as when an
acoustically similar species tracks the same gradient.

An optional near-boundary arm (`p10` = 0.01, commented in
`01_run_simulation.R`) reproduces the degeneracy that `occuFP` shows on real
data, where the frequentist maximum-likelihood fit sits on the boundary and its
Hessian goes singular.

## What the study shows

The headline numbers live in `data/fp_sim_100reps_summary.rds`; the short
version is a three-step story. Under homogeneity both models are well-calibrated.
Under unstructured heterogeneity the false-positive rate is estimated poorly
(its interval coverage collapses) but the environmental effect is largely
spared. Under structured confusion both parameters fail and the environmental
effect is biased toward zero, so a real effect can be read as absent. Where
`occuFP` converges it is biased in the same direction as the Bayesian model; the
difference is that the Bayesian interval reveals the damage through its coverage,
whereas the frequentist point estimate does not.

## Citing

See `CITATION.cff`. The Zenodo DOI is added when the release is archived. Full
references for the model and the study system are in the accompanying
manuscript.

## License

GPL-3, chosen because the package imports `unmarked` (GPL). See `LICENSE.md`.
