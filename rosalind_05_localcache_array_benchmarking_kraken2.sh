#!/usr/bin/env bash
# ===================================================================
# Kraken2 array: Option A (node-local DB cache + --memory-mapping)
# - Copies only required *.k2d DB files once per node to fast storage
# - Prefers /scratch/$USER/k2db_cache/$HOSTNAME, then $TMPDIR, then /dev/shm
# - Limits concurrency across the array to avoid I/O spikes
# - Safe 8h walltime; tune after first run
# ===================================================================

# ------------------------ PBS directives ---------------------------
#PBS -N k2_array_localdb_optA
#PBS -M you@utas.edu.au
#PBS -m abe
# >>> Set ONE range matching samples.txt
#PBS -J 1-10
# Resources per subjob (threads controlled below)
#PBS -l select=1:ncpus=2:mem=40GB
#PBS -l walltime=08:00:00
# Prefer packing subjobs together to reuse the cache on a node
#PBS -l place=pack
# Merge stdout/stderr
#PBS -j oe

set -euo pipefail

# Avoid locale warnings on nodes that lack C.UTF-8
export LC_ALL=C
export LANG=C

# ----------------------- User configuration ------------------------
# Shared Kraken2 database (read-only)
DB_DIR="/data/imas_projects/ancient/share/Databases/GTDBr226_k2_ncbitaxonomy"

# Inputs
SAMPLE_DIR="/u/davisee/chapter2_data/collapsed_kxdd_rename_4k2"
SAMPLES_LIST="${SAMPLE_DIR}/samples.txt"

# Kraken2 options
THREADS=2
CONFIDENCE=0.0
USE_MMAP=1

# Concurrency limiter for this array submission
MAX_CONCURRENT=2

# Outputs
OUT_BASE="${SAMPLE_DIR}/array_benchmarking"
OUT_CLASS="${OUT_BASE}/k2_hits"
OUT_UNCL="${OUT_BASE}/for_competitive"
OUT_CLF="${OUT_BASE}/k2_classification"
OUT_LOGS="${OUT_BASE}/logs"

# Concurrency lock base (on shared FS so all tasks see it)
LOCKDIR_BASE="${OUT_BASE}/_locks"
WAIT_POLL_SECS=10

# --------------------- Environment & checks ------------------------
echo "========== ENV =========="
date
echo "Host: $(hostname)"
echo "JobID: ${PBS_JOBID:-unset}"
echo "ArrayIndex: ${PBS_ARRAY_INDEX:-unset}"
echo "Workdir: ${PBS_O_WORKDIR:-unset}"
echo "Conda: $(command -v conda || echo 'not found')"

# Activate Kraken2 environment (adjust to your setup)
if command -v module >/dev/null 2>&1; then
  module load Anaconda3/2024.02-1 || true
fi
if command -v conda >/dev/null 2>&1; then
  source activate /u/davisee/.conda/envs/kraken2 || true
fi

echo "Kraken2: $(command -v kraken2 || echo 'not found')"
kraken2 --version || { echo "kraken2 --version failed"; exit 1; }

mkdir -p "${OUT_CLASS}" "${OUT_UNCL}" "${OUT_CLF}" "${OUT_LOGS}" "${LOCKDIR_BASE}"

# Inputs
if [[ ! -f "${SAMPLES_LIST}" ]]; then
  echo "ERROR: samples.txt not found at ${SAMPLES_LIST}" >&2
  exit 1
fi
if [[ -z "${PBS_ARRAY_INDEX:-}" ]]; then
  echo "ERROR: PBS_ARRAY_INDEX is unset (array job required)" >&2
  exit 1
fi

SAMPLE="$(sed -n "${PBS_ARRAY_INDEX}p" "${SAMPLES_LIST}")"
if [[ -z "${SAMPLE}" ]]; then
  echo "ERROR: No sample on line ${PBS_ARRAY_INDEX} of ${SAMPLES_LIST}" >&2
  exit 1
fi

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
echo "INPUT=${IN}"
ls -l "${IN}"

# Quick integrity check
if ! zcat -t "${IN}" >/dev/null 2>&1; then
  echo "ERROR: gzip integrity check FAILED for ${IN}" >&2
  exit 1
fi

# -------------------- Concurrency throttling -----------------------
# Per-array lock namespace (shared FS)  -- ensures MAX_CONCURRENT
ARRAY_ID="${PBS_JOBID%%[*]*}"
ARRAY_LOCKDIR="${LOCKDIR_BASE}/${ARRAY_ID}"
mkdir -p "${ARRAY_LOCKDIR}"

LOCKFILE="${ARRAY_LOCKDIR}/${PBS_JOBID}.lock"
cleanup_lock() { rm -f "${LOCKFILE}" 2>/dev/null || true; }
trap cleanup_lock EXIT TERM INT

echo "========== THROTTLE =========="
echo "[${PBS_ARRAY_INDEX}] Attempting to acquire a slot (max ${MAX_CONCURRENT}) ..."
while :; do
  current_locks="$(find "${ARRAY_LOCKDIR}" -maxdepth 1 -type f -name '*.lock' | wc -l | tr -d ' ')"
  if [[ "${current_locks}" -lt "${MAX_CONCURRENT}" ]]; then
    if ( set -o noclobber; : > "${LOCKFILE}" ) 2>/dev/null; then
      echo "[${PBS_ARRAY_INDEX}] Slot acquired (was ${current_locks}, now $((current_locks+1)))"
      break
    fi
  fi
  echo "[${PBS_ARRAY_INDEX}] Waiting for free slot... (${current_locks}/${MAX_CONCURRENT})"
  sleep "${WAIT_POLL_SECS}"
done

# ---------------- Stage input to node-local scratch ----------------
WORK="${TMPDIR:-/tmp}/k2_${ARRAY_ID}_${PBS_ARRAY_INDEX}"
mkdir -p "${WORK}"
cp -p "${IN}" "${WORK}/input.fastq.gz"
IN_LOCAL="${WORK}/input.fastq.gz"

# --------- Helpers: size & space checks, selective DB copy ----------
# Returns total size (KB) of required DB files at source
db_required_kb() {
  # Only *.k2d files are required for classification (hash/opts/taxo). [3](https://software.cqls.oregonstate.edu/updates/docs/kraken2/MANUAL.html)
  local src="$1"
  local kb=0
  while IFS= read -r -d '' f; do
    local s
    s=$(du -k "$f" | awk '{print $1}')
    kb=$((kb + s))
  done < <(find "$src" -maxdepth 1 -type f -name '*.k2d' -print0)
  echo "${kb}"
}

# Returns free space (KB) for filesystem containing path
fs_free_kb() {
  df -Pk "$1" | awk 'NR==2 {print $4}'
}

# Copy only *.k2d files
copy_k2d_files() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --include='*.k2d' --exclude='*' "${src}/" "${dst}/"
  else
    shopt -s nullglob
    cp -a "${src}"/*.k2d "${dst}/"
    shopt -u nullglob
  fi
}

# ---------------- Per-node local DB cache (smart) ------------------
ensure_local_db() {
  local src_db="${DB_DIR}"
  local db_tag="GTDBr226_k2_ncbitaxonomy"  # edit if DB build changes
  local host="${HOSTNAME%%.*}"

  local req_kb
  req_kb="$(db_required_kb "${src_db}")"
  [[ -z "${req_kb}" || "${req_kb}" -eq 0 ]] && { echo "ERROR: No *.k2d files found in ${src_db}" >&2; exit 2; }

  # Prefer big /scratch (designed for active jobs), then $TMPDIR, then /dev/shm. [1](https://universitytasmania-my.sharepoint.com/personal/emily_davis_utas_edu_au/Documents/Microsoft%20Copilot%20Chat%20Files/Rosalind%20Presentation%20November%202022%20update.pdf)
  local candidate_bases=()
  candidate_bases+=("/scratch/${USER}/k2db_cache/${host}")
  candidate_bases+=("${TMPDIR:-/tmp}")
  [[ -d /dev/shm ]] && candidate_bases+=("/dev/shm")

  local dst_db=""
  for base in "${candidate_bases[@]}"; do
    mkdir -p "${base}" 2>/dev/null || true
    local free_kb
    free_kb="$(fs_free_kb "${base}")"
    local need_kb=$(( req_kb + req_kb / 5 ))   # 1.2x headroom
    echo "[${PBS_ARRAY_INDEX}] DB requires ~${req_kb} KB; free at ${base} = ${free_kb} KB; need >= ${need_kb} KB"
    if [[ "${free_kb:-0}" -gt "${need_kb}" ]]; then
      dst_db="${base}/k2db_${db_tag}"
      break
    fi
  done

  if [[ -z "${dst_db}" ]]; then
    echo "[${PBS_ARRAY_INDEX}] WARNING: No destination with sufficient space; will use DB on shared storage directly (slower)."
    echo "${src_db}"
    return 0
  fi

  local lock="${dst_db}.copy.lock"
  local stamp="${dst_db}.ready"

  # Fast path: reuse
  if [[ -f "${dst_db}/hash.k2d" && -f "${dst_db}/opts.k2d" && -f "${dst_db}/taxo.k2d" && -f "${stamp}" ]]; then
    echo "[${PBS_ARRAY_INDEX}] Local DB already present at ${dst_db}"
    echo "${dst_db}"
    return 0
  fi

  mkdir -p "${dst_db%/*}"

  if ( set -o noclobber; : > "${lock}" ) 2>/dev/null; then
    echo "[${PBS_ARRAY_INDEX}] Caching DB (*.k2d only) to ${dst_db}"
    rm -rf "${dst_db}"
    mkdir -p "${dst_db}"
    copy_k2d_files "${src_db}" "${dst_db}"
    if [[ -f "${dst_db}/hash.k2d" && -f "${dst_db}/opts.k2d" && -f "${dst_db}/taxo.k2d" ]]; then
      touch "${stamp}"
      echo "[${PBS_ARRAY_INDEX}] Local DB ready: ${dst_db}"
    else
      echo "[${PBS_ARRAY_INDEX}] ERROR: Local DB copy missing core *.k2d files" >&2
      rm -f "${lock}"
      exit 3
    fi
    rm -f "${lock}"
  else
    echo "[${PBS_ARRAY_INDEX}] Waiting for local DB copy on this node..."
    # Adaptive wait: estimate from required KB and conservative IO rate.
    # IO_RATE_KBPS default ~150 MB/s; tweak via env if needed.
    local IO_RATE_KBPS="${IO_RATE_KBPS:-153600}"
    local est_secs=$(( req_kb / IO_RATE_KBPS + 600 ))   # +10 min buffer
    local max_wait=$(( est_secs > 3600 ? est_secs : 3600 ))  # at least 1h
    local waited=0
    while (( waited < max_wait )); do
      if [[ -f "${stamp}" ]]; then
        break
      fi
      if [[ -d "${dst_db}" ]]; then
        local have_kb
        have_kb=$(db_required_kb "${dst_db}")
        # bound percentage to [0,100]
        local pct=$(( req_kb > 0 ? (100*have_kb/req_kb) : 0 ))
        (( pct > 100 )) && pct=100
        echo "[${PBS_ARRAY_INDEX}] Cache progress: ${have_kb}/${req_kb} KB (~${pct}%) at ${dst_db} (waited ${waited}s/${max_wait}s)"
      fi
      sleep 15
      waited=$(( waited + 15 ))
    done
    if [[ ! -f "${stamp}" ]]; then
      echo "[${PBS_ARRAY_INDEX}] WARNING: Timed out waiting for local DB cache at ${dst_db}; will fall back to shared DB (slower)." >&2
      echo "${src_db}"
      return 0
    fi
  fi

  echo "${dst_db}"
}

DB_DIR_LOCAL="$(ensure_local_db)"

# -------------------------- Run Kraken2 ----------------------------
echo "========== RUN =========="
SECONDS=0
SAMPLE_BN="$(basename "${IN_LOCAL}")"
SAMPLE_BN="${SAMPLE_BN%.ckdd.fastq.gz}"
SAMPLE_BN="${SAMPLE_BN%.fastq.gz}"

CLASSIFIED_OUT="${OUT_CLASS}/classified-${SAMPLE_BN}-${PBS_JOBID}.fq"
UNCLASS_OUT="${OUT_UNCL}/unclassified-${SAMPLE_BN}-${PBS_JOBID}.fq"
REPORT_OUT="${OUT_CLF}/report-${SAMPLE_BN}-${PBS_JOBID}.txt"
OUTPUT_OUT="${OUT_CLF}/classifications-${SAMPLE_BN}-${PBS_JOBID}.txt"
LOG_OUT="${OUT_LOGS}/${SAMPLE_BN}-${PBS_JOBID}.log"

# Heartbeat keeps the lock mtime fresh while running
heartbeat() { while :; do touch -c "${LOCKFILE}" 2>/dev/null || true; sleep 60; done; }
heartbeat & HB_PID=$!

echo "[${PBS_ARRAY_INDEX}] Starting Kraken2: $(date)"
set +e
kraken2 \
  --db "${DB_DIR_LOCAL}" \
  $([[ "${USE_MMAP}" -eq 1 ]] && echo "--memory-mapping") \
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

kill "${HB_PID}" 2>/dev/null || true
wait "${HB_PID}" 2>/dev/null || true

ELAPSED=$SECONDS
echo "[${PBS_ARRAY_INDEX}] Kraken2 exit code: ${RC}"
echo "[${PBS_ARRAY_INDEX}] Finished at: $(date)"
echo "[${PBS_ARRAY_INDEX}] Elapsed seconds: ${ELAPSED}"

if [[ "${RC}" -eq 0 && ! -s "${REPORT_OUT}" ]]; then
  echo "[${PBS_ARRAY_INDEX}] WARNING: Empty report file at ${REPORT_OUT}" >&2
fi

# Clean node-local staged input (keep DB cache for reuse)
rm -rf "${WORK}" || true

exit "${RC}"


## because this is an array job // batch script, it is not reccommended to put "module purge" at the end bc multiple jobs!