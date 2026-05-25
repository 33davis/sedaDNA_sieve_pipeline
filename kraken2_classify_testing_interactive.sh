
#!/usr/bin/env bash
set -euo pipefail

DB_DIR="/data/imas_projects/ancient/share/Databases/GTDBr226_k2_ncbitaxonomy"
SAMPLE_DIR="/u/davisee/chapter2_data/kraken2_filter_testing"
THREADS=16  # adjust to your node
CONFIDENCE=0.0  # set >0 (e.g., 0.1–0.2) if you want stricter calls

cd "$SAMPLE_DIR"

# Guard: ensure there is at least one file
  shopt -s nullglob
  files=( *.ckdd.fastq.gz )
  if (( ${#files[@]} == 0 )); then
    echo "No *.ckdd.fastq.gz files found in $SAMPLE_DIR" >&2
    exit 1
  fi

  for sample in "${files[@]}"; do
    # Make a clean basename: drop .fastq.gz (or .fq.gz if that’s your convention)
    base="${sample%.fastq.gz}"
    base="${base%.fq.gz}"

    # Optional: make a per-sample log dir
    #mkdir -p logs
    #mkdir -p for_competitive
    #mkdir -p k2_classification
    #mkdir -p k2_hits

    k2 classify \
      --db "$DB_DIR" \
      --threads "$THREADS" \
      --confidence "$CONFIDENCE" \
      --unclassified-out "for_competitive/unclassified-${base}.fq" \
      --classified-out   "k2_hits/classified-${base}.fq" \
      --report           "k2_classification/report-${base}.txt" \
      --output           "k2_classification/classifications-${base}.txt" \
      --log              "logs/${base}.log" \
      "$sample"
  done
                                                        