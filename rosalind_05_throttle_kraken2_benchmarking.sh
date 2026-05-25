
#!/usr/bin/env bash
# ========================= PBS directives =========================
# Job name
#PBS -N kraken2_samples_benchmarking_cpu2_memGB20_concurrency_test
# Email notifications
#PBS -M emily.davis@utas.edu.au
#PBS -m abe

# --------- Array size: set ONE range that matches samples.txt ---------
# Quick test:
#PBS -J 1-10
# For bigger runs, change the previous line to e.g.:
#   #PBS -J 1-82
#   #PBS -J 1-410
# NOTE: In PBS, "-J start-end:step" selects indices; it does NOT limit concurrency.

# Resources per subjob (each array task gets this)
#PBS -l select=1:ncpus=2:mem=20GB
#PBS -l walltime=02:00:00
#PBS -l place=scatter
# Merge stdout/stderr
#PBS -j oe

set -euo pipefail

# ======================== User-tunable block =======================
# How many Kraken2 tasks may run simultaneously across your array?
# Start with 2; increase if the system is happy (e.g., 3 or 4).
MAX_CONCURRENT=2

# Paths (adjust if needed)
DB_DIR="/data/imas_projects/ancient/share/Databases/GTDBr226_k2_ncbitaxonomy"
SAMPLE_DIR="/u/davisee/chapter2_data/collapsed_kxdd_rename_4k2"
SAMPLES_LIST="${SAMPLE_DIR}/samples.txt"

THREADS=2
CONFIDENCE=0.0

# A shared directory for lock files so all array tasks can see them.
# Keep this on shared storage (not node-local /tmp).
LOCKDIR="${SAMPLE_DIR}/array_benchmarking/_locks"
# ===================================================================


# -------------------- Environment & tooling checks -----------------
module load Anaconda3/2024.02-1
# If your site prefers 'conda activate', feel free to swap the next line accordingly
source activate /u/davisee/.conda/envs/kraken2 || true

echo "========== ENV =========="
echo "Date:        $(date)"
echo "Host:        $(hostname)"
echo "JobID:       ${PBS_JOBID:-unset}"
echo "ArrayIndex:  ${PBS_ARRAY_INDEX:-unset}"
echo "Workdir:     ${PBS_O_WORKDIR:-unset}"
echo "Conda:       $(command -v conda || echo 'not found')"
echo "Env:         ${CONDA_PREFIX:-unset}"
echo "Kraken2:     $(command -v kraken2 || echo 'not found')"
kraken2 --version || { echo "kraken2 --version failed"; exit 1; }

# -------------------------- Directories ---------------------------
mkdir -p "${LOCKDIR}"
cd "${SAMPLE_DIR}"

mkdir -p \
  array_benchmarking/k2_hits \
  array_benchmarking/for_competitive \
  array_benchmarking/k2_classification \
  array_benchmarking/logs

# ------------------------- Resolve inputs -------------------------
if [[ ! -f "${SAMPLES_LIST}" ]]; then
  echo "ERROR: samples.txt not found at ${SAMPLES_LIST}" >&2
  exit 1
fi

if [[ -z "${PBS_ARRAY_INDEX:-}" ]]; then
  echo "ERROR: PBS_ARRAY_INDEX is unset (are you running as an array job?)" >&2
  exit 1
fi

SAMPLE="$(sed -n "${PBS_ARRAY_INDEX}p" "${SAMPLES_LIST}")"
if [[ -z "${SAMPLE}" ]]; then
  echo "ERROR: No sample on line ${PBS_ARRAY_INDEX} of ${SAMPLES_LIST}" >&2
  exit 1
fi

IN="${SAMPLE}.ckdd.fastq.gz"

echo "========== INPUTS =========="
echo "THREADS=${THREADS}"
echo "SAMPLE=${SAMPLE}"
echo "INPUT=${IN}"
echo "DB_DIR=${DB_DIR}"
echo "JobID=${PBS_JOBID}"

# Validate input exists and gzip integrity
ls -l "${IN}"
if ! zcat -t "${IN}" >/dev/null 2>&1; then
  echo "GZIP integrity check FAILED for ${IN}" >&2
  exit 1
fi

# -------------------- Concurrency limiter (locks) ------------------
# Prevent too many Kraken2 processes from running at once.
# Extra subjobs will sleep and poll until a slot frees up.
LOCKFILE="${LOCKDIR}/${PBS_JOBID}.${PBS_ARRAY_INDEX}.lock"

cleanup_lock() {
  rm -f "${LOCKFILE}" || true
}
trap cleanup_lock EXIT

echo "========== THROTTLE =========="
echo "[${PBS_ARRAY_INDEX}] Attempting to acquire a slot (max ${MAX_CONCURRENT}) ..."
while true; do
  # Count current locks safely
  current_locks=$(find "${LOCKDIR}" -maxdepth 1 -type f -name '*.lock' | wc -l | tr -d ' ')
  if [[ "${current_locks}" -lt "${MAX_CONCURRENT}" ]]; then
    # Atomically create our lock; if another task wins the race, try again
    if ( set -o noclobber; : > "${LOCKFILE}" ) 2>/dev/null; then
      echo "[${PBS_ARRAY_INDEX}] Slot acquired (was ${current_locks}, now $((current_locks+1)))"
      break
    fi
  fi
  echo "[${PBS_ARRAY_INDEX}] Waiting for free slot... (${current_locks}/${MAX_CONCURRENT})"
  sleep 10
done

# ------------------------ Run Kraken2 safely -----------------------
echo "========== RUN =========="
SECONDS=0

CLASSIFIED_OUT="array_benchmarking/k2_hits/classified-${SAMPLE}-${PBS_JOBID}.fq"
UNCLASS_OUT="array_benchmarking/for_competitive/unclassified-${SAMPLE}-${PBS_JOBID}.fq"
REPORT_OUT="array_benchmarking/k2_classification/report-${SAMPLE}-${PBS_JOBID}.txt"
OUTPUT_OUT="array_benchmarking/k2_classification/classifications-${SAMPLE}-${PBS_JOBID}.txt"
LOG_OUT="array_benchmarking/logs/${SAMPLE}-${PBS_JOBID}.log"

echo "[${PBS_ARRAY_INDEX}] Starting Kraken2 at: $(date)"

set +e
kraken2 \
  --db "${DB_DIR}" \
  --memory-mapping \
  --threads "${THREADS}" \
  --confidence "${CONFIDENCE}" \
  --classified-out "${CLASSIFIED_OUT}" \
  --unclassified-out "${UNCLASS_OUT}" \
  --report "${REPORT_OUT}" \
  --output "${OUTPUT_OUT}" \
  "${IN}" \
  2> "${LOG_OUT}"
RC=$?
set -e

ELAPSED=$SECONDS
echo "[${PBS_ARRAY_INDEX}] Kraken2 exit code: ${RC}"
echo "[${PBS_ARRAY_INDEX}] Finished at: $(date)"
echo "[${PBS_ARRAY_INDEX}] Elapsed seconds: ${ELAPSED}"

# -------------------- PBS accounting / diagnostics -----------------
qstat -fx "${PBS_JOBID}" || true

# Lock gets removed by trap on exit
exit "${RC}"

