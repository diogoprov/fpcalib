# Nightjar (curiango) data of the crywolf package in the form used by the
# manuscript: custom classifier, one-minute occasions, nights as sites,
# covariates standardized. Copied from dev/curiango-common.R of crywolf 1.9.0.
nightjar_data <- function() {
  zs <- function(v) as.numeric(scale(v))
  m <- crywolf::curiango$minutes
  nt <- crywolf::curiango$nights
  occasions <- data.frame(file = paste(m$site_night, format(m$time, "%Y%m%d_%H%M")),
                          site_night = m$site_night, time = m$time,
                          bio = zs(m$bio), aci = zs(m$aci), recorder = m$site)
  list(occasions = occasions,
       detections = data.frame(file = occasions$file, confidence = m$conf_custom),
       sites = data.frame(site_night = nt$site_night, temp = zs(nt$temp), rh = zs(nt$rh),
                          moon = zs(log(nt$moon))),
       verified = data.frame(site_night = crywolf::curiango$verified$site_night,
                             y = crywolf::curiango$verified$y))
}
