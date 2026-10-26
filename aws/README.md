# Running the long simulations on AWS EC2 (spot)

Scripts 07, 08 and 10 (and new runs built the same way) fit thousands of Stan
models, one core per fit, and save each task in a job folder
(`data/*_jobs/`) as soon as it ends, skipping tasks whose job file exists.
These files run one such script on a single EC2 spot instance instead of a
local machine:

- `Dockerfile` (compendium root): `rocker/r-ver:4.6.1`, CmdStan 2.40.0,
  cmdstanr, crywolf at commit `a5d2516` (Stan programs identical to release
  1.9.0, model compiled in the image) and the packages of scripts 07 to 10;
  single-threaded OpenBLAS. The image holds only software: the compendium
  (git HEAD) is mounted at `/project` at run time.
- `pack_code.sh`: uploads git HEAD (with the tracked `data/*.rds`) for one run.
- `launch_spot.sh`: starts the instance. `user_data.sh` builds the image on
  it, restores the job files saved in S3, runs the script with
  `WORKERS=<n>` (and `REPS` if given), syncs the job folder to S3 every
  10 min and on a spot interruption notice, copies the outputs and the log,
  writes a `DONE` (or `FAILED`) marker and terminates the instance. A hard
  limit (`max_hours`) terminates it whatever happens.
- `supervise.sh`: relaunches the run when a spot instance is reclaimed, until
  the marker appears.

Everything of a run lives under `s3://<bucket>/fpcalib/runs/<run>/`:
`code.tar.gz`, `jobs/`, `results/` (the `data/*.rds` and any figures or tables
written by the script), `logs/run_<instance-id>.log` and the marker. Launching
again with the same `<run>` resumes from `jobs/`. Use a new `<run>` label for a
run with other settings: tasks are named by cell and replicate only, and the
seeds of a script depend on `REPS`, so job files of a `REPS = 1` test must not
be mixed with those of a full run.

## One-time setup

The account set up for pcps-sim is reused: AWS CLI profile `pcps` (SSO,
region `us-east-1`), its bucket under the prefix `fpcalib/`, and its EC2
instance profile `pcps-sim-ec2`, whose role can read and write that prefix.

```bash
aws sso login --profile pcps       # opens the browser; the session lasts some hours
export AWS_PROFILE=pcps
```

The spot vCPU quota (Service Quotas > EC2 > "All Standard (A, C, D, H, I, M,
R, T, Z) Spot Instance Requests") must cover the instance; a c7a.48xlarge
needs 192 vCPUs.

## Each run

Commit first (`pack_code.sh` refuses uncommitted changes), then:

```bash
aws/pack_code.sh <bucket> test10
aws/launch_spot.sh <bucket> test10 analysis/10_obsconfirm_weak.R c7a.2xlarge 8 pcps-sim-ec2 2 1
aws s3 ls s3://<bucket>/fpcalib/runs/test10/       # DONE marker, logs/, results/
aws s3 sync s3://<bucket>/fpcalib/runs/test10/jobs <local folder>
```

For a full run on a large instance, keep it alive with `supervise.sh` in a
terminal (it polls every 5 min):

```bash
aws/pack_code.sh <bucket> obs08
ID=$(aws/launch_spot.sh <bucket> obs08 analysis/08_observation_confirmation.R c7a.48xlarge 190 pcps-sim-ec2 12)
aws/supervise.sh <bucket> obs08 analysis/08_observation_confirmation.R 190 pcps-sim-ec2 12 $ID \
  c7a.48xlarge c7i.48xlarge m7a.48xlarge
```

`supervise.sh` relaunches without `REPS`, so use it only for runs with the
script's default number of replicates. Then copy the job files into the
local job folder and run the summary (09) locally, in seconds:

```bash
aws s3 sync s3://<bucket>/fpcalib/runs/obs08/jobs data/obsconfirm_jobs
aws s3 sync s3://<bucket>/fpcalib/runs/obs08/results .
```

After the run, check that nothing is left running and empty the prefix
when it is no longer needed (storage is charged):

```bash
aws ec2 describe-instances --filters Name=tag:project,Values=fpcalib \
  Name=instance-state-name,Values=pending,running,stopping \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' --output text
aws ec2 describe-volumes --filters Name=tag:project,Values=fpcalib --query 'Volumes[].VolumeId'
aws s3 rm --recursive s3://<bucket>/fpcalib/runs/<run>/
```

## Time and cost

Prices change; check the current spot price before each launch:

```bash
aws ec2 describe-spot-price-history --instance-types c7a.48xlarge \
  --product-descriptions Linux/UNIX --start-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --query 'SpotPriceHistory[].[AvailabilityZone,SpotPrice]' --output text
```

Test on 26 Oct 2026: `REPS = 1` of script 10 (12 tasks, 24 fits) on a
c7a.2xlarge spot instance in us-east-1a, 8 workers. The instance ran 19 min
(image build 3.5 min, fits 14.5 min) at US$ 0.19/h, about US$ 0.06. The
median fit took 3.3 min (range 2.8 to 4.2), against 2.9 min for the same
fits on the Mac (M5 Pro, 16 workers), so a c7a core is about 15% slower.
The simulated data were identical to those of the local run (same seeds;
the true marginal false-positive rate differs by 1e-17, floating-point
arithmetic of another platform), and the posterior means differed by at
most 1.2% of the width of the 95% interval: the fits are close, not bitwise
equal, as expected across platforms. All 24 intervals for the slope agreed
on whether they covered the true value.

From that rate, a run of 3,600 fits (about 170 core-hours on the Mac) needs
about 200 core-hours on c7a: about 1.1 h of sampling on a c7a.48xlarge
with 190 workers, plus build and the tail of the last tasks, about 1.5 h
in all, or about US$ 4.5 at US$ 2.8 to 3.1/h (spot price of 26 Oct 2026;
check it again). A c7a.24xlarge (96 vCPUs, US$ 1.4 to 1.5/h) costs about
the same and takes twice as long. EBS and S3 add cents. A spot interruption
loses only the tasks running at that moment (at most about 10 min of work
each) plus the image build on the new instance.

Full run on 26 Oct 2026: script 11 (1,800 tasks, 3,600 Stan fits plus 1,800
fits of `unmarked::occu`) on c7a.48xlarge, 190 workers. With all cores busy,
the median fit took 4.9 min (range 3.5 to 7.0), about 50% more than on the
small instance, so that run needed about 300 core-hours. Two spot
interruptions (after 20 and 35 min) were resumed from the saved job files
by `supervise.sh`; the last instance finished the remaining 1,040 tasks in
1.0 h. Wall time 2.3 h from the first launch, about 2.1 instance-hours in
all, about US$ 6 to 7 at US$ 2.8 to 3.0/h. A first attempt failed at once:
R allows 128 connections, one per worker, so `user_data.sh` runs the script
with `Rscript --max-connections=512`. For the estimate of a new run, use
about 5 min per fit on the large instances.
