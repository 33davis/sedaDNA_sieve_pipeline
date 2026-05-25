
#!/usr/bin/env bash
#PBS -N kraken2_array
#PBS -M emily.davis@utas.edu.au
#PBS -m abe
#PBS -J 1-82
#PBS -l select=1:ncpus=2:mem=20GB
#PBS -l walltime=02:00:00
#PBS -j oe

set -eu

# ---- User settings ----
MAX_CONCURRENT=2
DB_DIR="/data/imas_projects/ancient/share/Databases/GTDBr226_k2_ncbitaxonomy"
SAMPLE_DIR="/u/davisee/chapter2_data/collapsed_kxdd_rename_4k2"
SAMPLES_LIST="${SAMPLE_DIR}/samples.txt"
LOCKDIR="${SAMPLE_DIR}/array_locks"
THREADS=2
CONFIDENCE=0.0

# ---- Environment ----
module load Anaconda3/2024.02-1
source activate /u/davisee/.conda/envs/kraken2

mkdir -p "$LOCKDIR"
cd "$SAMPLE_DIR"

# ---- Get sample ----
SAMPLE=$(sed -n "${PBS_ARRAY_INDEX}p" "$SAMPLES_LIST")
IN="${SAMPLE}.ckdd.fastq.gz"

echo "Running sample: $SAMPLE   Job: $PBS_JOBID   Index: $PBS_ARRAY_INDEX"

# ---- Concurrency limiter ----
LOCKFILE="${LOCKDIR}/${PBS_JOBID}.${PBS_ARRAY_INDEX}.lock"
trap 'rm -f "$LOCKFILE"' EXIT

while true; do
    current=$(find "$LOCKDIR" -type f -name '*.lock' | wc -l)
    if [ "$current" -lt "$MAX_CONCURRENT" ]; then
        ( set -o noclobber; : > "$LOCKFILE" ) 2>/dev/null && break
    fi
    sleep 10
done

# ---- Run Kraken2 ----
OUT_CLASS="classified-${SAMPLE}-${PBS_JOBID}.fq"
OUT_UNCLASS="unclassified-${SAMPLE}-${PBS_JOBID}.fq"
OUT_REPORT="report-${SAMPLE}-${PBS_JOBID}.txt"
OUT_OUTPUT="classifications-${SAMPLE}-${PBS_JOBID}.txt"
LOGFILE="${SAMPLE}-${PBS_JOBID}.log"

set +e
kraken2 \
  --db "$DB_DIR" \
  --memory-mapping \
  --threads "$THREADS" \
  --confidence "$CONFIDENCE" \
  --classified-out "$OUT_CLASS" \
  --unclassified-out "$OUT_UNCLASS" \
  --report "$OUT_REPORT" \
  --output "$OUT_OUTPUT" \
  "$IN" 2> "$LOGFILE"
RC=$?
set -e

echo "Kraken2 finished for $SAMPLE with exit code $RC"
exit $RC

