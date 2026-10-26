# Environment for the long simulation runs (analysis/07, 08, 10 and the summary
# 09) on an AWS EC2 spot instance; see aws/README.md. The image holds only the
# software: the compendium (git HEAD, from aws/pack_code.sh) is mounted at
# /project when the container runs.
# Build from the compendium root:  docker build -t fpcalib .
FROM rocker/r-ver:4.6.1

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl libcurl4-openssl-dev libssl-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# rocker/r-ver links R to multithreaded OpenBLAS; with one Stan fit per core,
# its threads only compete with the other workers
ENV OPENBLAS_NUM_THREADS=1 \
    OMP_NUM_THREADS=1 \
    RENV_ACTIVATE_PROJECT=FALSE \
    CMDSTAN=/opt/cmdstan/cmdstan-2.40.0 \
    MAKEFLAGS="-j8"

# rocker points `repos` to the dated Posit Package Manager snapshot of this R
# release (Linux binaries); cmdstanr comes from the Stan r-universe
RUN R -q -e 'install.packages(c("furrr", "future", "purrr", "dplyr", "tidyr", \
      "tibble", "posterior", "loo", "ggplot2", "scales", "patchwork", \
      "unmarked", "remotes"))' \
 && R -q -e 'install.packages("cmdstanr", repos = c("https://stan-dev.r-universe.dev", getOption("repos")))'

RUN mkdir -p /opt/cmdstan \
 && R -q -e 'cmdstanr::install_cmdstan(dir = "/opt/cmdstan", version = "2.40.0", cores = 8, quiet = TRUE)'

# crywolf at a5d2516 (Stan programs identical to release 1.9.0); compiling
# here leaves the executable in the cache of the root user, so every run
# starts sampling at once
RUN R -q -e 'remotes::install_github("diogoprov/crywolf@a5d25168c228d8a09c13d43cfeba640ae8b85547", upgrade = "never", dependencies = FALSE)' \
 && R -q -e 'crywolf::fp_compile(); sessionInfo(); cmdstanr::cmdstan_version()'

WORKDIR /project
