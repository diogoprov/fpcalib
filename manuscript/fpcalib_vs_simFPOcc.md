# fpcalib vs spOccupancy::simFPOcc

Comparison of the simulator in `fpcalib/R/fp_sim_pilot.R` (`simulate_fp()`, read from the
working copy at `~/Documents/fpcalib`, 2026-08-16) against `simFPOcc()` in spOccupancy,
read from the package source on GitHub (`R/simFPOcc.R`, 451 lines) rather than from the
reference page, so that the data-generating process is taken from the code itself.

**Status of simFPOcc.** It is new. The spOccupancy `NEWS.md` entry for version 0.8.2 reads
"Created a new function `simFPOcc()` that simulates data for the false-positive occupancy
model of Chambert et al. (2018)", and CRAN published 0.8.2 on 2026-10-07, two days ago.
The package `NAMESPACE` at `main` exports `simFPOcc` and **no corresponding model-fitting
function**: there is no `fpPGOcc`, `svcFPOcc` or equivalent in the export list. As of this
release spOccupancy can simulate data of this kind but not fit it. Worth re-checking before
the note is submitted, since that is clearly the direction of travel.

---

## 1. The short answer

They are not the same model, and the difference is not a detail. `simFPOcc` implements the
**count-detection** false-positive model of Chambert et al. (2018): the observation at a
site-visit is the *number* of signals, Poisson or negative binomial, and the false-positive
component is a *rate*. `simulate_fp` implements the **binary multiple-detection-method**
model of Miller et al. (2011): the observation is a 0/1 per occasion, and the
false-positive component is a *probability*. The two families identify the false-positive
component in different ways: Chambert by validating a random subsample of the detected
signals, Miller by adding a second, certain detection method.

So the arrival of `simFPOcc` does not make `fpcalib` redundant, but it does change how the
software note has to position itself, and it should now be cited.

---

## 2. The two generative processes, side by side

| | `fpcalib::simulate_fp` | `spOccupancy::simFPOcc` |
|---|---|---|
| Latent state | `z ~ Bernoulli(plogis(b0 + b1·xs))` | `z ~ rbinom(J, 1, logit.inv(Xβ [+ spatial w] [+ RE]))` |
| Detection data | **binary** per occasion | **counts** per visit |
| True-positive component | `p11 = plogis(a0 + a_bio·BIO + a_aci·ACI + u[recorder])`, a probability | `mu = exp(X.mu·γ [+ RE])`, a rate |
| False-positive component | `p10`, a probability; intercept only in the fitted model | `omega = exp(X.omega·δ [+ RE])`, a rate with covariates |
| Combination | `y2 ~ Bernoulli(z·p11 + (1−z)·p10)` | `y ~ Poisson(mu·z + omega)` or `rnbinom(size = kappa, mu = mu·z + omega)` |
| How truth enters | a **second method**: `y1 ~ Bernoulli(z·r11)`, certain, no false positives; `known_present` forces `z = 1` where a verified detection occurred | a **validated subsample**: `D ~ Binomial(y, mu·z/(mu·z+omega))`, `Q = y − D`, `n.val = round(prop.val·y)`, `d ~ rhyper(D, Q, n.val)` |
| Verification design parameters | `verified_coverage` (fraction of sites verified), `n_verified` (occasions per verified site), `r11` | `prop.val` (fraction of signals vetted) |
| Visits | balanced, `K` automated occasions per site | unbalanced, `n.rep` per site with `n.rep.max` padding and `rep.indx` |
| Spatial structure | none | optional Gaussian process, Matérn/exponential/spherical/gaussian, spatially varying coefficients via `svc.cols`, separate simulation `grid` |
| Random effects | one recorder random intercept on `p11` (`sig_u`), toggled off by default | random intercepts **and random slopes** on all three submodels (`psi.RE`, `mu.RE`, `omega.RE`), multiple grouping factors each |
| Overdispersion | not applicable (Bernoulli) | `kappa` under `family = "NB"` |
| Returns | Stan data list, an `unmarked::occuFP` frame, and the truth | design matrices, `psi`, `z`, `mu`, `omega`, `y`, `n.val`, `d`, `D`, `Q`, and the random-effect values |

What is shared is the skeleton, and it is shared because both descend from the same
literature: a latent Bernoulli occupancy state; a true-detection process that operates only
where `z = 1`; a false-positive process that operates regardless of `z`; and partial
verification as the device that identifies the false-positive component. Everything below
that skeleton differs.

---

## 3. What spOccupancy has that fpcalib does not

Spatial occupancy with a Gaussian process and spatially varying coefficients; random
intercepts and slopes on all three submodels with several grouping factors; covariates on
the false-positive rate; negative-binomial overdispersion; unbalanced survey effort. For a
general-purpose simulator that is the right feature set, and fpcalib should not try to
match it.

---

## 4. What fpcalib has that simFPOcc does not

This is where the compendium earns its place, and all three items are the object of the
study rather than incidental.

**4.1 Parameterized misspecification of the false-positive rate.** `simulate_fp` offers
three regimes for how `p10` varies across sites, and the fitted Stan model assumes a single
`p10`, so the variation is a controlled misspecification:

- homogeneous, `p10_i = p10`;
- unstructured, either logit-normal (`sigma_p10`) or Beta with a concentration parameter
  (`p10_beta_conc`), where small concentration aggregates the rate toward 0 and 1;
- structured confusion, `logit(p10_i) += conf_effect · w_i`, where `w` is a second latent
  gradient built to have a chosen correlation with the occupancy covariate
  (`w = conf_cor·xs + sqrt(1−conf_cor²)·rnorm(n)`) and is absent from the fitted model.

`simFPOcc` has no equivalent of the third one, and it cannot be emulated by passing a
covariate to `X.omega`, because the simulator draws `X`, `X.mu` and `X.omega` as
independent standard normals (`X.omega[j, rep.indx[[j]], i] <- rnorm(n.rep[j])`, lines
218–225). The occupancy covariate and the false-positive covariate are independent by
construction, so the correlation that drives the attenuation of the occupancy slope cannot
be induced without rewriting the returned object.

Note the asymmetry of intent as well: in the Chambert framework, covariates on the
false-positive rate are a modelled feature, so heterogeneity is something you fit. In the
fpcalib study it is deliberately *not* fitted, because the question is what happens to an
ecologist who assumes a single rate when the classifier does not have one. The compendium
does contain an `fp_occupancy_fpcov.stan` variant in `inst/stan`, so the capability exists;
the manuscript model is intercept-only on purpose.

**4.2 The site-confirmation arm.** The verified-method design (`verified_coverage`,
`n_verified`, `r11`, `known_present`) is the Miller et al. (2011) multiple-detection-method
structure, which is what the JAV-03737 data actually have: manually annotated clips that
are certain. `simFPOcc` has no certain second method; its `prop.val` vets a random
subsample of the automated signals instead. If you wanted to study the Curiango design you
could not do it with `simFPOcc`.

**4.3 The head-to-head.** `simulate_fp` returns, from a single call, both the Stan data
list and the `unmarked::occuFP` frame (`type = c(n_verified, K, 0)`) built from the same
realized dataset, which is what lets `fit_both()` score the Bayesian and frequentist
estimators on identical data, including the near-boundary arm where `occuFP` goes singular.
`simFPOcc` returns one representation and has no comparator.

---

## 5. What to do about it in the software note

1. **Cite it.** `simFPOcc` is now the obvious prior art a reviewer will raise. Not citing it
   two days after it reached CRAN would look worse than citing it.
2. **State the difference in one paragraph, in terms of the data.** Draft:

   > The false-positive occupancy literature splits into two families according to what is
   > observed. In the count-detection family (Chambert et al. 2018), the datum is the number
   > of signals at a visit, the false-positive component is a rate, and it is identified by
   > validating a random subsample of signals; `spOccupancy` now provides `simFPOcc()` for
   > simulating data of this kind. In the multiple-detection-method family (Miller et al.
   > 2011), the datum is a binary detection, the false-positive component is a probability,
   > and it is identified by a second method that is certain. Our data belong to the second
   > family, and `fpcalib` simulates from it. The two are not interchangeable: the
   > identifying information has a different form, and so does the estimand.

3. **Lead with the misspecification, not the simulator.** The contribution of `fpcalib` is
   not "a simulator for false-positive occupancy data" — that framing is now contested. It
   is "what happens to interval coverage and to the estimated environmental effect when the
   false-positive rate is heterogeneous in ways the model does not represent, and
   particularly when that heterogeneity tracks the covariate of interest". No published
   simulator parameterizes that, including `simFPOcc`.
4. **Check before submission** whether a fitting function for `simFPOcc` has appeared. If
   spOccupancy ships one, the note should say how the two models relate; if it does not, the
   note can say, accurately, that the simulator exists without a companion estimator in the
   package.

---

## Sources

- `spOccupancy` package source, `R/simFPOcc.R` and `NAMESPACE`, branch `main`
  (https://github.com/doserjef/spOccupancy).
- `spOccupancy` `NEWS.md`, entry for version 0.8.2.
- CRAN metadata for `spOccupancy`: version 0.8.2, published 2026-10-07.
- Reference page https://doserlab.com/files/spoccupancy-web/reference/simfpocc (argument
  list and example; the page has no Details section, so the generative process above was
  read from the source).
- `fpcalib/R/fp_sim_pilot.R` and `fpcalib/README.md`, working copy at
  `~/Documents/fpcalib`.
