#!/usr/bin/env bash 
#PBS -N kraken2_testing_script_structure
#PBS -M emily.davis@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
#PBS -l select=1:ncpus=2
#PBS -l walltime=00:10:00

set -euo pipefail

## BEGIN SCRIPT

# Load and activate conda environment 
module load Anaconda3/2024.02-1
source activate /u/davisee/.conda/envs/kraken2 || { echo "Failed to activate prank_alignments env"; exit 1; }

# Debug info (appears in PBS log)
echo ">>> Conda binary: $(which conda)"
echo ">>> Active env: $CONDA_PREFIX"


DB_DIR="/data/imas_projects/ancient/share/Databases/GTDBr226_k2_ncbitaxonomy"
SAMPLE_DIR="/u/davisee/chapter2_data/kraken2_filter_testing"
THREADS=28  # adjust to your node
CONFIDENCE=0.0  # set >0 (e.g., 0.1–0.2) if you want stricter calls

cd $SAMPLE_DIR

## Configure sample_basename as targets to only process some samples at a time ##
TARGETS=(
    #"IMAS_IODP382*"
    #"Aviti_SED24SeqPool2*"
    #"SED24SeqPool3*"
    "SED25SeqPool1_Aviti_COLLAPS*"
    #"SED25SeqPool2_KCCGNovaSeq*"
    #"SED23SeqPool3_Novaseq*""
)
for basename in "${TARGETS[@]}"; do
    echo "Kraken2 filtering samples: $basename"
# Guard: ensure there is at least one file
  shopt -s nullglob
  files=($basename)
  if (( ${#files[@]} == 0 )); then
    echo "No *.ckdd.fastq.gz files found in with $basename" >&2
    exit 1
  fi

  for sample in "${files[@]}"; do
    # Make a clean new basename: drop .fastq.gz (or .fq.gz if that’s your convention)
    base="${sample%.ckdd.fastq.gz}"
    #base="${base%.ckdd.fq.gz}"
    echo "Kraken2 loop will be using $base for outputs"
    # Optional: make a per-sample log dir
    #mkdir -p logs
    #mkdir -p for_competitive
    #mkdir -p k2_classification
    #mkdir -p k2_hits

   # k2 classify \
    #  --db "$DB_DIR" \
    #  --threads "$THREADS" \
    #  --confidence "$CONFIDENCE" \
    #  --unclassified-out "for_competitive/unclassified-${base}.fq" \
    #  --classified-out   "k2_hits/classified-${base}.fq" \
    #  --report           "k2_classification/report-${base}.txt" \
    #  --output           "k2_classification/classifications-${base}.txt" \
    #  --log              "logs/${base}.log" \
    #  "$sample"
    echo $sample
  done
done            