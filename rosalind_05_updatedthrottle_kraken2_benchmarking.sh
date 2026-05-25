
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
# NOTE: In PBS, "-J start-end[:step]" selects indices; it does NOT limit concurrency.

# Resources per subjob (each array task gets this)
# >>> Adjust walltime if needed; the script auto-sets timeout to 5 min less <<<
#PBS -l select=1:ncpus=2:mem=20GB
#PBS -l walltime=02:00:00
#PBS -l place=scatter
# Merge stdout/stderr
#PBS -j oe

set -euo pipefail

# ======================== User-tunable block =======================
# How many Kraken2 tasks may run simultaneously across your array?
# For diagnosis start with 1; when stable, try 2 or more.
MAX_CONCURRENT=8

# Paths (adjust if needed)
DB_DIR="/data/imas_projects/ancient/share/Databases/GTDBr226_k2_ncbitaxonomy"
SAMPLE_DIR="/u/davisee/chapter2_data/collapsed_kxdd_rename_4k2"
SAMPLES_LIST="${SAMPLE_DIR}/samples.txt"

THREADS=2
CONFIDENCE=0.0

# Base directory for locks on a shared filesystem (do not use node-local /tmp)
LOCKDIR_BASE="${SAMPLE_DIR}/array_benchmarking/_locks"

# Wait cap while trying to acquire a slot (prevents wasting full walltime)
WAIT_LIMIT_SECS=1800   # 30 minutes; adjust if you like
# ===================================================================


# -------------------- Environment & tooling checks -----------------
module load Anaconda3/2024.02-1
# If your site prefers 'conda activate', feel free to swap the next line accordingly
source activate /u/davisee/.conda/envs/kraken2 || true
# Optional: quiet locale warnings
# export LC_ALL=C.UTF-8; export LANG=C.UTF-8

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
mkdir -p "${LOCKDIR_BASE}"
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

# Try common forms in priority order (gz-aware):
# 1) ${SAMPLE_DIR}/${SAMPLE}.ckdd.fastq.gz       (bare base name in the list)
# 2) ${SAMPLE_DIR}/${SAMPLE}                     (list already has filename)
# 3) ${SAMPLE}                                   (list provides full/relative path)
CANDIDATES=(
  "${SAMPLE_DIR}/${SAMPLE}.ckdd.fastq.gz"
  "${SAMPLE_DIR}/${SAMPLE}"
  "${SAMPLE}"
)

IN=""
for c in "${CANDIDATES[@]}"; do
  if [[ -f "$c" ]]; then IN="$c"; break; fi
done

echo "========== INPUTS =========="
echo "THREADS=${THREADS}"
echo "SAMPLE=${SAMPLE}"
echo "DB_DIR=${DB_DIR}"
echo "JobID=${PBS_JOBID}"

if [[ -z "${IN}" ]]; then
  echo "ERROR: Could not find FASTQ for sample '${SAMPLE}'. Tried:" >&2
  printf '  - %s\n' "${CANDIDATES[@]}" >&2
  exit 1
fi

echo "INPUT=${IN}"
ls -l "${IN}"

# Quick gzip integrity test (fast; avoids running Kraken2 on corrupt input)
if ! zcat -t "${IN}" >/dev/null 2>&1; then
  echo "GZIP integrity check FAILED for ${IN}" >&2
  exit 1
fi

# ----------------- Per-array lock namespace + stale-aware limiter -----------------
# Derive a stable array ID (strip the [N] part from PBS_JOBID), e.g. 1326125.server
ARRAY_ID="${PBS_JOBID%%[*}"
ARRAY_LOCKDIR="${LOCKDIR_BASE}/${ARRAY_ID}"
mkdir -p "${ARRAY_LOCKDIR}"
echo "[${PBS_ARRAY_INDEX}] Using lockdir: ${ARRAY_LOCKDIR}"

LOCKFILE="${ARRAY_LOCKDIR}/${PBS_JOBID}.lock"
LOCKMETA="${LOCKFILE}.meta"

cleanup_lock() { rm -f "${LOCKFILE}" "${LOCKMETA}" || true; }
# Clean lock on normal exit and common termination signals
trap cleanup_lock EXIT TERM INT

purge_stale_locks() {
  shopt -s nullglob
  local now=$(date +%s)
  local soft_age=600       # 10 min soft expiry
  local hard_age=$((3600)) # 4 h hard expiry

  for lf in "${ARRAY_LOCKDIR}"/*.lock; do
    local base="$(basename "$lf" .lock)"   # looks like 1328580[1].server
    local meta="${ARRAY_LOCKDIR}/${base}.meta"
    local mtime=$(stat -c %Y "$lf" 2>/dev/null || echo "$now")
    local age=$(( now - mtime ))

    # Hard-expiry: very old lock -> remove unconditionally
    if (( age > hard_age )); then
      echo "[${PBS_ARRAY_INDEX}] Purge: hard-expired lock ${base} (age=${age}s)"
      rm -f "$lf" "$meta"
      continue
    fi

    # If PBS doesn't know about this subjob, it's stale
    if ! qstat -f "$base" >/dev/null 2>&1; then
      echo "[${PBS_ARRAY_INDEX}] Purge: orphan lock ${base} (job unknown to PBS)"
      rm -f "$lf" "$meta"
      continue
    fi

    # Soft-expiry: if older than soft_age AND not Busy/Running/Ending, remove
    local state=$(
      qstat -f "$base" 2>/dev/null |
      awk -F= '/\bjob_state\b/ {gsub(/[ \t]/,"",$2); print $2; exit}'
    )
    if (( age > soft_age )) && [[ "$state" != "B" && "$state" != "R" && "$state" != "E"]]; then
      echo "[${PBS_ARRAY_INDEX}] Purge: soft-expired lock ${base} (state=${state}, age=${age}s)"
      rm -f "$lf" "$meta"
    fi
  done
}

echo "========== THROTTLE =========="
echo "[${PBS_ARRAY_INDEX}] Attempting to acquire a slot (max ${MAX_CONCURRENT}) ..."
wait_start=$(date +%s)

while :; do
  purge_stale_locks

  # Count current locks for THIS array submission only
  current_locks=$(find "${ARRAY_LOCKDIR}" -maxdepth 1 -type f -name '*.lock' | wc -l | tr -d ' ')

  if [[ "${current_locks}" -lt "${MAX_CONCURRENT}" ]]; then
    # Atomically create our lock; if another task wins the race, loop again
    if ( set -o noclobber; : > "${LOCKFILE}" ) 2>/dev/null; then
      {
        echo "jid=${PBS_JOBID}"
        echo "host=$(hostname)"
        echo "pid=$$"
        echo "start_epoch=$(date +%s)"
      } > "${LOCKMETA}" 2>/dev/null || true
      echo "[${PBS_ARRAY_INDEX}] Slot acquired (was ${current_locks}, now $((current_locks+1)))"
      break
    fi
  fi

  # Check wait limit so we don't waste walltime indefinitely, taking this out, could be causing problems
  #now=$(date +%s)
  #waited=$(( now - wait_start ))
  #if [[ "${waited}" -ge "${WAIT_LIMIT_SECS}" ]]; then
  #  echo "[${PBS_ARRAY_INDEX}] Waited ${WAIT_LIMIT_SECS}s without a free slot; exiting 99 to avoid walltime waste."
  #  exit 99
  #fi

  echo "[${PBS_ARRAY_INDEX}] Waiting for free slot... (${current_locks}/${MAX_CONCURRENT})"
  sleep 10
done

# -------------------- (Optional) stage to node-local scratch --------------------
# To reduce file server I/O, you can stage the input to local scratch (then use IN_LOCAL below).
# Uncomment this block to enable staging.
#
WORK="${TMPDIR:-/tmp}/k2_${PBS_JOBID}_${PBS_ARRAY_INDEX}"
 mkdir -p "$WORK"
 cp -p "${IN}" "$WORK/input.fastq.gz"
 IN_LOCAL="$WORK/input.fastq.gz"
#
# If NOT staging, just point IN_LOCAL to IN:
#IN_LOCAL="${IN}"

# ------------------------ Compute TASK_LIMIT from walltime -----------------------
# Set timeout to end a few minutes before PBS walltime so trap runs and lock is removed.
WL="${PBS_RESOURCE_LIST_walltime:-02:00:00}"  # fallback matches #PBS above
IFS=':' read -r WL_H WL_M WL_S <<< "${WL}"
WL_H=${WL_H#0}; WL_M=${WL_M#0}; WL_S=${WL_S#0}
WL_SECS=$(( ${WL_H:-0}*3600 + ${WL_M:-0}*60 + ${WL_S:-0} ))
MARGIN_SECS=300     # end 5 minutes early
TASK_LIMIT_SECS=$(( WL_SECS - MARGIN_SECS ))
# Ensure a sane lower bound
if [[ "${TASK_LIMIT_SECS}" -lt 60 ]]; then TASK_LIMIT_SECS=$(( WL_SECS - 10 )); fi
echo "[${PBS_ARRAY_INDEX}] Walltime=${WL}, timeout=${TASK_LIMIT_SECS}s (margin=${MARGIN_SECS}s)"

# ------------------------ Run Kraken2 safely (with heartbeat) -------------------
echo "========== RUN =========="
SECONDS=0

# Use a clean basename for outputs (strip trailing .ckdd.fastq.gz if present)
SAMPLE_BN="$(basename "${IN_LOCAL}")"
SAMPLE_BN="${SAMPLE_BN%.ckdd.fastq.gz}"

CLASSIFIED_OUT="array_benchmarking/k2_hits/classified-${SAMPLE_BN}-${PBS_JOBID}.fq"
UNCLASS_OUT="array_benchmarking/for_competitive/unclassified-${SAMPLE_BN}-${PBS_JOBID}.fq"
REPORT_OUT="array_benchmarking/k2_classification/report-${SAMPLE_BN}-${PBS_JOBID}.txt"
OUTPUT_OUT="array_benchmarking/k2_classification/classifications-${SAMPLE_BN}-${PBS_JOBID}.txt"
LOG_OUT="array_benchmarking/logs/${SAMPLE_BN}-${PBS_JOBID}.log"

# Heartbeat: keep lock mtime fresh while actively running
heartbeat() {
  while :; do
    touch -c "${LOCKFILE}" 2>/dev/null || true
    sleep 20
  done
}
heartbeat &
HB_PID=$!

echo "[${PBS_ARRAY_INDEX}] Starting Kraken2 at: $(date)"
set +e
timeout --preserve-status "${TASK_LIMIT_SECS}s" kraken2 \
  --db "${DB_DIR}" \
  --memory-mapping \
  --threads "${THREADS}" \
  --confidence "${CONFIDENCE}" \
  --classified-out "${CLASSIFIED_OUT}" \
  --unclassified-out "${UNCLASS_OUT}" \
  --report "${REPORT_OUT}" \
  --output "${OUTPUT_OUT}" \
  "${IN_LOCAL}" \
  2> "${LOG_OUT}"
RC=$?
set -e

# Stop heartbeat
kill "${HB_PID}" 2>/dev/null || true
wait "${HB_PID}" 2>/dev/null || true

ELAPSED=$SECONDS
echo "[${PBS_ARRAY_INDEX}] Kraken2 exit code: ${RC}"
echo "[${PBS_ARRAY_INDEX}] Finished at: $(date)"
echo "[${PBS_ARRAY_INDEX}] Elapsed seconds: ${ELAPSED}"

# -------------------- PBS accounting / diagnostics -----------------
qstat -fx "${PBS_JOBID}" || true

# If you enabled scratch staging above, you may also want to clean it up:
 rm -rf "$WORK" || true

# Lock gets removed by trap on exit (and also on TERM/INT)
exit "${RC}"
