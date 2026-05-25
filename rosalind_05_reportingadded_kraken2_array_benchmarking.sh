#!/usr/bin/env bash
#PBS -N kraken2_samples_benchmarking_cpu2_memGB20_concurrency_test
#PBS -M emily.davis@utas.edu.au
#PBS -m abe
# 10 test samples
#PBS -J 1-10[2]
# Conservative per-sample resources (benchmarkable)
#PBS -l select=1:ncpus=2:mem=20GB
#PBS -l walltime=02:00:00
#PBS -l place=scatter
#PBS -j oe

set -euo pipefail

# environment set up 
module load Anaconda3/2024.02-1
source activate /u/davisee/.conda/envs/kraken2
echo "Conda: $(which conda || echo no_conda)"
echo "Env: ${CONDA_PREFIX:-unset}"
echo "Kraken2: $(which kraken2 || echo missing)"
kraken2 --version || { echo "kraken2 --version failed"; exit 1; }

# variables
DB_DIR="/data/imas_projects/ancient/share/Databases/GTDBr226_k2_ncbitaxonomy"
SAMPLE_DIR="/u/davisee/chapter2_data/collapsed_kxdd_rename_4k2"
THREADS=2
CONFIDENCE=0.0

cd "$SAMPLE_DIR"

# Pick exactly ONE sample for task from array list (subset file already in place)
SAMPLE=$(sed -n "${PBS_ARRAY_INDEX}p" samples.txt)
IN="${SAMPLE}.ckdd.fastq.gz"

echo "========== INPUTS =========="
echo "THREADS=$THREADS"
echo "SAMPLE=$SAMPLE"
echo "DB_DIR=$DB_DIR"
echo "JobID=$PBS_JOBID"
echo "Host: $(hostname)"
echo "Start time: $(date)"

# Validate input exists and gzip integrity
ls -l "$IN"
zcat -t "$IN" >/dev/null 2>&1 || { echo "GZIP test FAILED for $IN"; exit 1; }

echo "========== RUN =========="
SECONDS=0

kraken2 \
  --db "$DB_DIR" \
  --memory-mapping \
  --threads "$THREADS" \
  --confidence "$CONFIDENCE" \
  --classified-out   "array_benchmarking/k2_hits/classified-${SAMPLE}-${PBS_JOBID}.fq" \
  --unclassified-out "array_benchmarking/for_competitive/unclassified-${SAMPLE}-${PBS_JOBID}.fq" \
  --report           "array_benchmarking/k2_classification/report-${SAMPLE}-${PBS_JOBID}.txt" \
  --output           "array_benchmarking/k2_classification/classifications-${SAMPLE}-${PBS_JOBID}.txt" \
  "$IN" \
  2> "array_benchmarking/logs/${SAMPLE}-${PBS_JOBID}.log"

RC=$?
ELAPSED=$SECONDS
echo "Kraken2 exit code: $RC"
echo "End time: $(date)"
echo "Elapsed seconds: $ELAPSED"

# ===== PBS accounting (authoritative usage for scaling) =====
# Will include resources_used.walltime, cput, mem, vmem and the requested resources.
# This is recommended in the Rosalind docs for checking resources
qstat -fx "$PBS_JOBID" || true

exit $RC
