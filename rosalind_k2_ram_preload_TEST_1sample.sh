#!/usr/bin/env bash
# =====================================================================
# Kraken2 RAM-preload TEST on a single sample (fixed)
# - Confirms DB visibility and preload via kraken2-inspect
# - Processes 1 *.ckdd.fastq.gz from SAMPLE_DIR
# - Writes unclassified FASTQ + classified FASTQ + report + classifications + log
# =====================================================================

# ------------------------- PBS directives ----------------------------
#PBS -N k2_ram_preload_TEST
#PBS -M you@utas.edu.au
#PBS -m abe
# Request enough RAM to safely read the ~645 GB DB into memory for this test
#PBS -l select=1:ncpus=8:mem=800GB
#PBS -l walltime=08:00:00
#PBS -j oe

set -euo pipefail

# Silence locale warnings on nodes lacking C.UTF-8
export LC_ALL=C
export LANG=C

# -------------------------- User settings ----------------------------
DB_DIR="/data/imas_projects/ancient/share/Databases/GTDBr226_k2_ncbitaxonomy"
SAMPLE_DIR="/u/davisee/chapter2_data/collapsed_kxdd_rename_4k2"

OUT_REPORTS="${SAMPLE_DIR}/k2_reports"
OUT_CLASSIF="${SAMPLE_DIR}/k2_classifications"
OUT_LOGS="${SAMPLE_DIR}/k2_logs"
OUT_UNCL="${SAMPLE_DIR}/for_competitive_k2_unclassified_fq"
OUT_CL="${SAMPLE_DIR}/k2_classified_fq"

THREADS=8
CONFIDENCE=0.0

# -------------------------- Environment ------------------------------
echo "========== ENV =========="
date
echo "Host: $(hostname)"
echo "JobID: ${PBS_JOBID:-unset}"
echo "Workdir: ${PBS_O_WORKDIR:-unset}"

module load Anaconda3/2024.02-1 || true
source activate /u/davisee/.conda/envs/kraken2 || { echo "ERROR: activate kraken2 env"; exit 1; }

echo "Kraken2 bin: $(command -v kraken2 || echo 'not found')"
kraken2 --version

# Also ensure kraken2-inspect exists (we'll use this for preload)
echo "Kraken2-inspect bin: $(command -v kraken2-inspect || echo 'not found')"

# ----------------------- Sanity: DB presence -------------------------
for f in hash.k2d opts.k2d taxo.k2d; do
  if [[ ! -f "${DB_DIR}/${f}" ]]; then
    echo "ERROR: DB_DIR (${DB_DIR}) missing required file: ${f}"; exit 2;
  fi
done
ls -lh "${DB_DIR}/"{hash.k2d,opts.k2d,taxo.k2d}

# ------------------------ Prepare outputs ----------------------------
mkdir -p "${OUT_REPORTS}" "${OUT_CLASSIF}" "${OUT_LOGS}" "${OUT_UNCL}" "${OUT_CL}"

# ----------------------- Pick ONE test sample ------------------------
echo "Discovering one sample in: ${SAMPLE_DIR}"
# Safer pick: avoid 'sort | head' broken-pipe warning by using a shell loop
sample_fq=""
while IFS= read -r -d '' f; do sample_fq="$f"; break; done < <(find "${SAMPLE_DIR}" -maxdepth 1 -type f -name "*.ckdd.fastq.gz" -print0 | sort -z)
if [[ -z "${sample_fq}" ]]; then
  echo "ERROR: No *.ckdd.fastq.gz found under ${SAMPLE_DIR}"; exit 3;
fi
sample_bn="$(basename "${sample_fq}" .ckdd.fastq.gz)"
echo "Using sample: ${sample_bn}"

# ------------------------- DB RAM PRELOAD ----------------------------
echo "========== PRELOAD =========="
echo "Preloading Kraken2 DB into RAM with kraken2-inspect (one-time test)..."
# Use the documented inspector binary (not a flag to kraken2)
kraken2-inspect --db "${DB_DIR}" --threads "${THREADS}" > /dev/null
echo "DB preload test complete."
# Docs note kraken2-inspect is the separate program to examine the DB structure. [1](https://paleogenomics-tor-vergata.readthedocs.io/en/latest/4_Metagenomics_v2.html)[2](https://avilpage.com/2024/07/mastering-kraken2-performance-optimisation.html)

# ---------------------- Single classification ------------------------
echo "========== RUN =========="
rep="${OUT_REPORTS}/report-${sample_bn}.txt"
out="${OUT_CLASSIF}/classifications-${sample_bn}.txt"
slog="${OUT_LOGS}/${sample_bn}.log"
uncl="${OUT_UNCL}/unclassified-${sample_bn}.fq"
cl="${OUT_CL}/classified-${sample_bn}.fq"

echo "[`date`] START ${sample_bn}"

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
  "${sample_fq}" \
  2> "${slog}"
rc=$?
set -e

echo "[`date`] DONE  ${sample_bn}  rc=${rc}"

echo "Outputs for ${sample_bn}:"
echo "  Report         : ${rep}"
echo "  Classifications: ${out}"
echo "  Unclassified   : ${uncl}"
echo "  Classified     : ${cl}"
echo "  Log            : ${slog}"

exit "${rc}"