// ============================================================================
// Bayesian false-positive occupancy model — JAV-03737
// COVARIATE-DEPENDENT FALSE-POSITIVE RATE ("the fix").
//
// WHY THIS FILE EXISTS (the structured-confusion fix):
//   fp_occupancy_re_toggle.stan estimates a SINGLE constant p10. When the
//   false-positive rate tracks the occupancy covariate (structured confusion),
//   that misspecification leaks into the occupancy slope b1 and its interval
//   coverage collapses, and verifying more does not rescue it. This model lets
//   the analyst MODEL the structure instead: it puts a linear predictor on the
//   false-positive rate,
//       logit(p10_i) = gamma0 + Xfp_i . gamma_fp,   gamma0 = alpha0 - fp_gap,
//   where Xfp holds the covariate(s) suspected to drive the confusion (here the
//   same standardized covariate that drives occupancy). The gap parameter still
//   pins p11 > p10 at the reference (Xfp = 0), resolving the label switching to
//   which false-positive models are prone (Royle and Link 2006); the verified
//   clips anchor which state is which away from the reference.
//
//   Set Kfp = 0 (no FP covariate) to recover the constant-p10 model exactly.
//   Everything else (marginalization, the estimate_re toggle, the GQ block) is
//   the same as fp_occupancy_re_toggle.stan.
// ============================================================================
data {
  int<lower=1> nsite;
  int<lower=1> Kbeta;
  matrix[nsite, Kbeta] X;
  int<lower=1> nobser;

  int<lower=0> Kfp;                          // number of false-positive covariates (0 = constant p10)
  matrix[nsite, Kfp] Xfp;                    // FP design (NO intercept; the intercept is gamma0)

  int<lower=0> N2;
  array[N2] int<lower=0, upper=1> y2;
  array[N2] int<lower=1, upper=nsite>  site2;
  array[N2] int<lower=1, upper=nobser> obser2;
  vector[N2] bio2;
  vector[N2] aci2;

  int<lower=0> N1;
  array[N1] int<lower=0, upper=1> y1;
  array[N1] int<lower=1, upper=nsite> site1;

  int<lower=0, upper=1> estimate_fp;
  int<lower=0, upper=1> estimate_re;
  array[nsite] int<lower=0, upper=1> known_present;
}

parameters {
  vector[Kbeta] beta;
  real alpha0;
  real a_bio;
  real a_aci;
  vector[nobser] u_raw;
  real<lower=0> sigma_u;
  real<lower=0> fp_gap;
  vector[Kfp] gamma_fp;        // false-positive slopes (length 0 when Kfp = 0)
  real delta0;
}

transformed parameters {
  vector[nobser] u = sigma_u * u_raw;
  real gamma0 = alpha0 - fp_gap;              // logit(p10) at the FP-covariate reference
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
  gamma_fp      ~ normal(0, 2.5);             // weakly-informative; no-op when Kfp = 0

  // ---- per-site false-positive rate ----
  vector[nsite] logit_p10 = rep_vector(gamma0, nsite);
  if (Kfp > 0) logit_p10 += Xfp * gamma_fp;
  vector[nsite] p10v = inv_logit(logit_p10);

  // ---- per-site accumulators (marginalize latent z) ----
  vector[nsite] lpsi  = X * beta;
  vector[nsite] occ   = rep_vector(0, nsite);
  vector[nsite] unocc = rep_vector(0, nsite);
  vector[nsite] occ_v = rep_vector(0, nsite);

  real r11 = inv_logit(delta0);

  for (n in 1:N2) {
    real re_n = (estimate_re == 1) ? u[obser2[n]] : 0;
    real p11  = inv_logit(alpha0 + a_bio * bio2[n] + a_aci * aci2[n] + re_n);
    occ[site2[n]] += bernoulli_lpmf(y2[n] | p11);
    if (estimate_fp == 1)
      unocc[site2[n]] += bernoulli_lpmf(y2[n] | p10v[site2[n]]);
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
  vector[nsite] psi = inv_logit(X * beta);
  real p10_ref = estimate_fp == 1 ? inv_logit(gamma0) : 0.0;   // p10 at Xfp = 0
  real p11_ref = inv_logit(alpha0);
  real r11     = inv_logit(delta0);
  real p10_bar;                                                // mean p10 across sites (the marginal FP rate)
  {
    vector[nsite] logit_p10 = rep_vector(gamma0, nsite);
    if (Kfp > 0) logit_p10 += Xfp * gamma_fp;
    p10_bar = estimate_fp == 1 ? mean(inv_logit(logit_p10)) : 0.0;
  }
}
