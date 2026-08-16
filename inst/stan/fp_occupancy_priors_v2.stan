// ============================================================================
// Bayesian false-positive (single-season) occupancy model — JAV-03737
// PRIORS v2: intercepts tightened to normal(0, 1.5) (near-flat on the
//   probability scale) and the p11–p10 gap given a normal(2, 1.5) prior
//   truncated at 0 (favours a substantial gap => low p10, no mass at p10 ~ p11).
//   Structure, likelihood, and generated quantities are IDENTICAL to v1.
//
// Multiple-detection-method design (Miller et al. 2011), marginalized over the
// latent occupancy state. Aligned with the spOccupancy PGOcc structure:
//   psi (occupancy)      ~ site covariates X (intercept + Temp + RH + log moon)
//   p11 (true detection) ~ BIO + ACI + recorder random effect u[obser]
//   p10 (false positive) ~ intercept   (Method 2 / automated only)
//   r11 (verified det.)  ~ intercept   (Method 1 / certain, no false positives)
//
// One program fits BOTH frameworks via `estimate_fp`:
//   estimate_fp = 1 -> false-positive occupancy (p10 estimated)
//   estimate_fp = 0 -> standard occupancy (p10 = 0; any automated detection
//                      implies occupancy) — the nested comparison model.
//
// Verified (Method 1) occasions are CERTAIN: a detection proves occupancy
// (`known_present`), a non-detection has probability 1 under absence. They
// identify p10 for the automated data.
//
// IDENTIFIABILITY: p10 is constrained below the p11 intercept (p11 > p10) via a
// positive gap parameter `fp_gap`, preventing label switching between the
// occupied/unoccupied states (a known issue in false-positive occupancy models).
// ============================================================================
data {
  int<lower=1> nsite;                       // site-nights (occupancy sites)
  int<lower=1> Kbeta;                       // # occupancy coefficients (incl. intercept)
  matrix[nsite, Kbeta] X;                   // occupancy design matrix
  int<lower=1> nobser;                      // # recorders (Site) for the random effect

  // Method 2 — automated detections (long format)
  int<lower=0> N2;
  array[N2] int<lower=0, upper=1> y2;
  array[N2] int<lower=1, upper=nsite>  site2;
  array[N2] int<lower=1, upper=nobser> obser2;
  vector[N2] bio2;                          // standardized BIO
  vector[N2] aci2;                          // standardized ACI

  // Method 1 — verified detections (long format; may be empty, N1 = 0)
  int<lower=0> N1;
  array[N1] int<lower=0, upper=1> y1;
  array[N1] int<lower=1, upper=nsite> site1;

  int<lower=0, upper=1> estimate_fp;        // 1 = FP model; 0 = standard occupancy
  array[nsite] int<lower=0, upper=1> known_present;  // any verified detection at site
}

parameters {
  vector[Kbeta] beta;          // occupancy (logit psi)
  real alpha0;                 // p11 intercept (logit)
  real a_bio;                  // p11 ~ BIO
  real a_aci;                  // p11 ~ ACI
  vector[nobser] u_raw;        // recorder random effect (non-centered)
  real<lower=0> sigma_u;
  real<lower=0> fp_gap;        // p11_baseline(logit) - p10(logit) >= 0  (identifiability: p11 > p10)
  real delta0;                 // r11 intercept (logit; verified detection)
}

transformed parameters {
  vector[nobser] u = sigma_u * u_raw;
  real gamma0 = alpha0 - fp_gap;   // p10 logit constrained below p11 intercept
}

model {
  // ---- priors (weakly informative; checked by prior predictive on the probability scale) ----
  beta[1]       ~ normal(0, 1.5);   // occupancy INTERCEPT: ~flat on psi (avoids the U-shape at 0/1)
  beta[2:Kbeta] ~ normal(0, 2.5);   // occupancy slopes (standardized Temp/RH/log-moon)
  alpha0        ~ normal(0, 1.5);   // p11 intercept: ~flat on the probability scale
  a_bio         ~ normal(0, 2.5);   // p11 slopes
  a_aci         ~ normal(0, 2.5);
  u_raw         ~ std_normal();
  sigma_u       ~ normal(0, 2);     // half-normal (sigma_u > 0)
  delta0        ~ normal(0, 1.5);   // r11 (verified) intercept: ~flat on the probability scale
  fp_gap        ~ normal(2, 1.5);   // half-normal shifted to +2: favours a substantial p11-p10 gap
                                    //   => p10 kept low, no mass at p10 ~ p11; lower=0 keeps p11>p10

  // ---- per-site accumulators (marginalize latent z) ----
  vector[nsite] lpsi  = X * beta;                 // logit psi
  vector[nsite] occ   = rep_vector(0, nsite);     // automated loglik | z = 1
  vector[nsite] unocc = rep_vector(0, nsite);     // automated loglik | z = 0
  vector[nsite] occ_v = rep_vector(0, nsite);     // verified  loglik | z = 1

  real p10 = estimate_fp == 1 ? inv_logit(gamma0) : 0.0;
  real r11 = inv_logit(delta0);

  for (n in 1:N2) {
    real p11 = inv_logit(alpha0 + a_bio * bio2[n] + a_aci * aci2[n] + u[obser2[n]]);
    occ[site2[n]] += bernoulli_lpmf(y2[n] | p11);
    if (estimate_fp == 1)
      unocc[site2[n]] += bernoulli_lpmf(y2[n] | p10);
    else
      unocc[site2[n]] += (y2[n] == 1) ? negative_infinity() : 0;   // p10 = 0
  }
  for (n in 1:N1)
    occ_v[site1[n]] += bernoulli_lpmf(y1[n] | r11);

  for (i in 1:nsite) {
    real occ_branch = log_inv_logit(lpsi[i]) + occ[i] + occ_v[i];
    if (known_present[i] == 1)
      target += occ_branch;                                        // z = 1 with certainty
    else
      target += log_sum_exp(occ_branch,
                            log1m_inv_logit(lpsi[i]) + unocc[i]);   // verified all 0 -> +0
  }
}

generated quantities {
  vector[nsite] log_lik;                          // per-site marginal loglik (for loo/WAIC)
  vector[nsite] psi = inv_logit(X * beta);
  real p10     = estimate_fp == 1 ? inv_logit(gamma0) : 0.0;
  real p11_ref = inv_logit(alpha0);               // at BIO = ACI = 0, u = 0
  real r11     = inv_logit(delta0);
  {
    vector[nsite] lpsi  = X * beta;
    vector[nsite] occ   = rep_vector(0, nsite);
    vector[nsite] unocc = rep_vector(0, nsite);
    vector[nsite] occ_v = rep_vector(0, nsite);
    for (n in 1:N2) {
      real p11 = inv_logit(alpha0 + a_bio * bio2[n] + a_aci * aci2[n] + u[obser2[n]]);
      occ[site2[n]] += bernoulli_lpmf(y2[n] | p11);
      if (estimate_fp == 1)
        unocc[site2[n]] += bernoulli_lpmf(y2[n] | p10);
      else
        unocc[site2[n]] += (y2[n] == 1) ? negative_infinity() : 0;
    }
    for (n in 1:N1)
      occ_v[site1[n]] += bernoulli_lpmf(y1[n] | r11);
    for (i in 1:nsite) {
      real occ_branch = log_inv_logit(lpsi[i]) + occ[i] + occ_v[i];
      log_lik[i] = (known_present[i] == 1)
                   ? occ_branch
                   : log_sum_exp(occ_branch, log1m_inv_logit(lpsi[i]) + unocc[i]);
    }
  }
}
