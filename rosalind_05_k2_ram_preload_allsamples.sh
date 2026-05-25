#!/usr/bin/env bash
# =====================================================================
# Kraken2 RAM-preload over all samples in one directory (410 samples)
# - Preloads DB into RAM once (no --memory-mapping)
# - Writes per-sample: UNCLASSIFIED fastq, CLASSIFIED fastq,
#   report, classifications, and a log
# =====================================================================

# ------------------------- PBS directives ----------------------------
#PBS -N k2_ram_preload_all
#PBS -M you@utas.edu.au
#PBS -m abe

# Your DB is ~645 GB → request >=800 GB RAM
# Adjust CPUs + walltime as appropriate
#PBS -l select=1:ncpus=32:mem=800GB
#PBS -l walltime=120:00:00
#PBS -j oe

set -euo pipefail

# -------------------------- User settings ----------------------------
DB_DIR="/data/imas_projects/ancient/share/Databases/GTDBr226_k2_ncbitaxonomy"
SAMPLE_DIR="/u/davisee/chapter2_data/collapsed_kxdd_rename_4k2"

OUT_REPORTS="${SAMPLE_DIR}/k2_reports"
OUT_CLASSIF="${SAMPLE_DIR}/k2_classifications"
OUT_LOGS="${SAMPLE_DIR}/k2_logs"
OUT_UNCL="${SAMPLE_DIR}/for_competitive_k2_unclassified_fq"
OUT_CL="${SAMPLE_DIR}/k2_classified_fq"

THREADS=32
CONFIDENCE=0.0

# -------------------------- Environment ------------------------------
echo "========== ENV =========="
date
echo "Host: $(hostname)"
echo "JobID: ${PBS_JOBID:-unset}"

module load Anaconda3/2024.02-1 || true
source activate /u/davisee/.conda/envs/kraken2 || { echo "ERROR activating env"; exit 1; }

echo "Kraken2 bin: $(command -v kraken2)"
kraken2 --version

# ----------------------- Sanity: DB presence -------------------------
for f in hash.k2d opts.k2d taxo.k2d; do
  if [[ ! -f "${DB_DIR}/${f}" ]]; then
    echo "ERROR: DB_DIR missing ${f}"; exit 2;
  fi
done

# ------------------------ Prepare outputs ----------------------------
mkdir -p "${OUT_REPORTS}" "${OUT_CLASSIF}" "${OUT_LOGS}" "${OUT_UNCL}" "${OUT_CL}"

# ------------------------ Build sample list --------------------------
echo "Discovering samples..."
mapfile -t SAMPLES < <(find "${SAMPLE_DIR}" -maxdepth 1 -type f -name "*.ckdd.fastq.gz" -printf "%f\n" | sort)
NS=${#SAMPLES[@]}
(( NS > 0 )) || { echo "ERROR: No samples found"; exit 3; }
echo "Found ${NS} samples."

# ------------------------- DB RAM PRELOAD ----------------------------
echo "========== PRELOAD =========="
echo "Preloading Kraken2 DB into RAM..."
kraken2 --db "${DB_DIR}" --threads "${THREADS}" --inspect > /dev/null
echo "DB preload complete."

# -------------------- Sequential classification ----------------------
echo "========== RUN =========="
for fq in "${SAMPLES[@]}"; do
  sample="${fq%.ckdd.fastq.gz}"
  in_fq="${SAMPLE_DIR}/${fq}"

  rep="${OUT_REPORTS}/report-${sample}.txt"
  out="${OUT_CLASSIF}/classifications-${sample}.txt"
  slog="${OUT_LOGS}/${sample}.log"
  uncl="${OUT_UNCL}/unclassified-${sample}.fq"
  cl="${OUT_CL}/classified-${sample}.fq"

  echo "[`date`] START ${sample}"

  set +e
  kraken2 \
    --db "${DB_DIR}" \
    --threads "${THREADS}" \
    --confidence "${CONFIDENCE}" \
    --gzip-compressed \
    --unclassified-out "${uncl}" \
    --classified-out   "${cl}" \
    --report "${rep}" \
    --output "${out}" \
    "${in_fq}" \
    2> "${slog}"
  rc=$?
  set -e

  echo "[`date`] DONE  ${sample}  rc=${rc}"
done

echo "All samples complete."