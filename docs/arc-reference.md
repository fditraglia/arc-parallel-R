# ARC HPC Quick Reference

Reference for writing correct SLURM scripts on Oxford's ARC cluster.
Compiled from the [ARC User Guide](https://arc-user-guide.readthedocs.io)
and [ARC Software Guide](https://arc-software-guide.readthedocs.io).

## Clusters

| Cluster | Purpose | Node CPUs | Node RAM | Scheduler preference |
|---------|---------|-----------|----------|---------------------|
| **arc** | Large parallel jobs, multi-node | 48 Intel cores @ 2.90GHz | 384GB | Prefers large jobs |
| **htc** | High-throughput, many small jobs | Mixed (16/20/48 cores) | Varies | Prefers small jobs |

Both clusters share the same filesystem (`$DATA` accessible from both).

- ARC: 262 uniform nodes + 10 high-memory AMD nodes (288 cores, 2.3TB RAM)
- HTC: 124 worker nodes, heterogeneous hardware, includes GPUs
- Interconnect: HDR 100 Infiniband (ARC)
- **For serial/job-array workloads, use HTC** (scheduler optimized for small jobs)
- **For single-node multi-core jobs, use ARC** (scheduler prefers large jobs)
- Submit to other cluster: `--clusters=htc` or `--clusters=arc`

## Partitions (same on both clusters)

| Partition | Default time | Max time | Notes |
|-----------|-------------|----------|-------|
| `short` | 1hr | 12hr | Higher priority |
| `medium` | 12hr | 48hr | Higher priority |
| `long` | 24hr | unlimited | Lower priority |
| `devel` | — | 10min | Testing only |
| `interactive` | — | 24hr | Software builds, allows oversubscription |

## Node Types

- **Login nodes**: Job submission only. Max 1hr CPU per process. Different architecture from compute nodes.
- **Interactive nodes**: Pre/post-processing, software builds. Same CPU architecture as most compute nodes.
- **Compute nodes**: The actual workhorses. 48 cores, 384GB RAM per node (arc).

**Important**: Login nodes have different CPU architecture from compute/interactive nodes. Software compiled on login nodes may fail with "Illegal instruction" on compute nodes. Always build software in an interactive session (`srun -p interactive --pty /bin/bash`).

## Storage

| Path | Size | Persists? | Shared across nodes? | Use for |
|------|------|-----------|---------------------|---------|
| `$HOME` | 15GB quota | Yes | Yes | Config files, scripts |
| `$DATA` | 5TB (project-wide) | Yes | Yes | Code, results, R libraries |
| `$SCRATCH` | Large | **No** (deleted on job exit) | Yes (across job nodes) | Intermediate files during job |
| `$TMPDIR` | Local disk | **No** (deleted on job exit) | No (node-local only) | Fast local I/O |

- **No backups** on any storage. Keep copies elsewhere.
- Snapshots available in `.snapshot` directories (hourly/daily/weekly, max 2-week retention) for accidental deletion recovery.
- Check quota: `myquota`
- For long-running jobs, periodically copy intermediate results from `$SCRATCH` to `$DATA`.

## Environment Modules

```bash
module spider R              # Search for R (case-insensitive). Run from interactive node, not login.
module -r spider '^R$'       # Regex search (exact match for "R")
module load R/4.4.2-gfbf-2024a  # Load specific version (case-sensitive!)
module list                  # Show loaded modules
module purge                 # Unload all modules
```

- Always `module purge` before `module load` in SLURM scripts for a clean environment.
- Module names are **case-sensitive** when loading (unlike `module spider`).
- Older modules ending in `-ARC` come with extra pre-installed R packages.

## SLURM Submission Script Template

```bash
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --partition=short
#SBATCH --time=12:00:00
#SBATCH --job-name=my_job
#SBATCH --output=my_job_%j.out

module purge
module load R/4.4.2-gfbf-2024a

Rscript --no-restore --no-save my_script.R
```

Key rules:
- `#SBATCH` directives **must come before any other commands** (after `#!/bin/bash`)
- Default memory: 8000MB per CPU (no need to specify unless you need more)
- Max memory per node: ~380GB (arc), up to 3000GB on special htc nodes
- Nodes are **shared** — multiple jobs run on the same node
- Output goes to `slurm-[jobid].out` by default, or use `--output` to customize
- `%j` in output filename = job ID; `%A` = array job ID; `%a` = array task ID
- Create scripts on the cluster (nano/vi) or ensure no Windows line endings (`dos2unix` to fix)

## Key SLURM Environment Variables

| Variable | Description |
|----------|-------------|
| `SLURM_SUBMIT_DIR` | Directory where `sbatch` was run |
| `SLURM_JOB_ID` | Unique job identifier |
| `SLURM_JOB_NODELIST` | List of allocated nodes |
| `SLURM_CPUS_PER_TASK` | Number of CPUs allocated per task |
| `SLURM_ARRAY_TASK_ID` | Index of current array task |
| `SLURM_ARRAY_JOB_ID` | Job ID of the array parent |

## Job Arrays

For running many independent tasks with different parameters:

```bash
#!/bin/bash
#SBATCH --array=1-100
#SBATCH --output=results_%A_%a.out
#SBATCH --partition=short

module purge
module load R/4.4.2-gfbf-2024a

Rscript --no-restore --no-save my_script.R $SLURM_ARRAY_TASK_ID
```

- `--array=1-100` creates 100 tasks, each with `SLURM_ARRAY_TASK_ID` from 1 to 100
- `%A` = parent job ID, `%a` = array task ID (for unique output files)
- Can limit concurrent tasks: `--array=1-100%10` (max 10 running at once)
- **Use HTC for job arrays** — its scheduler is optimized for many small jobs
- Two approaches for parameters:
  1. Compute from task ID inside the script
  2. Read from a parameter file using `sed -n "${SLURM_ARRAY_TASK_ID}p" params.txt`

## Job Dependencies

Chain jobs that depend on each other:

```bash
JOB1=$(sbatch --parsable job1.slurm)
sbatch --dependency=afterok:$JOB1 job2.slurm
```

Dependency types: `afterok`, `afterany`, `afternotok`, `after`

## R on ARC

### Loading R
```bash
module purge
module load R/4.4.2-gfbf-2024a
```

### Installing packages
- **Must be done from an interactive session** (not login node)
- Set `R_LIBS` to a directory under `$DATA` (not `$HOME` — 15GB is too small)
- Add `export R_LIBS=$DATA/R_libs` to your SLURM scripts
- Packages with compiled code must be built on interactive/compute nodes to match architecture

### Architecture warning
Interactive/compute nodes use Cascade Lake CPUs. Login nodes use a different architecture. If you install packages on a login node, they may crash with "Illegal instruction" when run on compute nodes. To be safe, add to SLURM scripts:
```bash
#SBATCH --constraint='cpu_gen:Cascade_Lake'
```

### Parallel R
The docs' example SLURM script requests `--cpus-per-task=8` and notes: "Your R script must use a parallel R library to make use of these cores." Simply requesting multiple CPUs does **not** automatically parallelize R — you must use `parallel`, `future`, `foreach`, etc. in your R code.

### Rmpi (multi-node R)
For R across multiple nodes, use Rmpi with `mpirun -np 1 R --vanilla -f script.R`. This spawns R workers across allocated nodes. Requires `--ntasks-per-node` to set processes per node.

## Useful Commands

```bash
sbatch script.slurm         # Submit job
sbatch --test-only script.slurm  # Validate script, estimate start time
squeue -u $USER             # Check your jobs
scancel <jobid>             # Cancel a job
sinfo                       # Partition and node status
scontrol show job <jobid>   # Detailed job info (including why it's queued)
seff <jobid>                # Efficiency report (after completion)
mybalance                   # Check compute credits
myquota                     # Check storage quota
```

## Common Pitfalls

1. **SLURM does NOT source `~/.bashrc` or `~/.bash_profile`** — set all env vars explicitly in scripts
2. **Windows line endings** cause `"/bin/bash^M: bad interpreter"` — use `dos2unix`
3. **Login node architecture differs from compute nodes** — build software on interactive nodes
4. **Job exceeds walltime** — most common cause of unexpected job death
5. **No backups** — copy results off ARC after runs complete
6. **`$SCRATCH` and `$TMPDIR` are deleted on job exit** — save results to `$DATA` before finishing
7. **`module spider` shows incomplete results on login nodes** — search from interactive sessions
8. **Requesting CPUs doesn't parallelize R** — your R code must use parallel libraries explicitly
