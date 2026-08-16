// ============================================================================
// Bayesian false-positive occupancy model — JAV-03737
// v2 priors + a RECORDER-RANDOM-EFFECT TOGGLE (estimate_re).
//
// WHY THIS FILE EXISTS (divergence investigation):
//   The head-to-head simulation cells generate data with NO recorder effect
//   (sig_u = 0), for apples-to-apples comparison with occuFP, which has none.
//   The v2 model nonetheless estimates sigma_u from only nobser = 5 groups with
//   a TRUE variance of zero. That is Neal's funnel: the sigma_u -> 0 neck is
//   what produces the ~1 divergence per fit seen even in the well-specified
//   baseline, roughly uniform across p10 (the signature of a variance-component
//   funnel, not of the fp_gap/p10 identifiability, which would scale with p10).
//
//   estimate_re = 0 removes u from the likelihood, so sigma_u and u_raw sample
//   from their priors independently (no data-induced funnel, no divergences from
//   this source). estimate_re = 1 keeps the full model for the REAL data, which
//   does have recorders. This mirrors the existing estimate_fp toggle and does
//   NOT change the estimand: with true sig_u = 0 the recorder effect was only
//   fitting noise, so the coverage/bias numbers should be unchanged; only the
//   sampler geometry improves.
//
//   Everything else (structure, likelihood, GQ) is identical to
//   fp_occupancy_priors_v2.stan. Set estimate_re = 1 to reproduce v2 exactly.
// ============================================================================
data {
  int<lower=1> nsite;
  int<lower=1> Kbeta;
  matrix[nsite, Kbeta] X;
  int<lower=1> nobser;

  int<lower=0> N2;
  array[N2] int<lower=0, upper=1> y2;
  array[N2] int<lower=1, upper=nsite>  site2;
  array[N2] int<lower=1, upper=nobser> obser2;
  vector[N2] bio2;
  vector[N2] aci2;

  int<lower=0> N1;
  array[N1] int<lower=0, upper=1> y1;
  array[N1] int<lower=1, upper=nsite> site1;

  int<lower=0, upper=1> estimate_fp;        // 1 = FP model; 0 = standard occupancy
  int<lower=0, upper=1> estimate_re;        // 1 = fit recorder random effect; 0 = drop it (no sigma_u funnel)
  array[nsite] int<lower=0, upper=1> known_present;
}

parameters {
  vector[Kbeta] beta;
  real alpha0;
  real a_bio;
  real a_aci;
  vector[nobser] u_raw;        // when estimate_re = 0 these sample from the prior only
  real<lower=0> sigma_u;
  real<lower=0> fp_gap;
  real delta0;
}

transformed parameters {
  vector[nobser] u = sigma_u * u_raw;
  real gamma0 = alpha0 - fp_gap;
}

model {
  // ---- priors ----
  beta[1]       ~ normal(0, 1.5);
  beta[2:Kbeta] ~ normal(0, 2.5);
  alpha0        ~ normal(0, 1.5);
  a_bio         ~ normal(0, 2.5);
  a_aci         ~ normal(0, 2.5);
  u_raw         ~ std_normal();
  sigma_u       ~ normal(0, 2);
  delta0        ~ normal(0, 1.5);
  fp_gap        ~ normal(2, 1.5);

  // ---- per-site accumulators (marginalize latent z) ----
  vector[nsite] lpsi  = X * beta;
  vector[nsite] occ   = rep_vector(0, nsite);
  vector[nsite] unocc = rep_vector(0, nsite);
  vector[nsite] occ_v = rep_vector(0, nsite);

  real p10 = estimate_fp == 1 ? inv_logit(gamma0) : 0.0;
  real r11 = inv_logit(delta0);

  for (n in 1:N2) {
    real re_n = (estimate_re == 1) ? u[obser2[n]] : 0;    // <-- toggle: no RE in the likelihood when 0
    real p11  = inv_logit(alpha0 + a_bio * bio2[n] + a_aci * aci2[n] + re_n);
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
    if (known_present[i] == 1)
      target += occ_branch;
    else
      target += log_sum_exp(occ_branch, log1m_inv_logit(lpsi[i]) + unocc[i]);
  }
}

generated quantities {
  vector[nsite] log_lik;
  vector[nsite] psi = inv_logit(X * beta);
  real p10     = estimate_fp == 1 ? inv_logit(gamma0) : 0.0;
  real p11_ref = inv_logit(alpha0);
  real r11     = inv_logit(delta0);
  {
    vector[nsite] lpsi  = X * beta;
    vector[nsite] occ   = rep_vector(0, nsite);
    vector[nsite] unocc = rep_vector(0, nsite);
    vector[nsite] occ_v = rep_vector(0, nsite);
    for (n in 1:N2) {
      real re_n = (estimate_re == 1) ? u[obser2[n]] : 0;
      real p11  = inv_logit(alpha0 + a_bio * bio2[n] + a_aci * aci2[n] + re_n);
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
