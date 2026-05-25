#!/usr/bin/bash -l
#PBS -N rosalind_03_komplexity_dedupe ######### notes for AVITI vs illumina/NovaSeq
#PBS -M emily.davis@utas.edu.au
#PBS -m abe
# Select 2 nodes with 28 cpus per node
#PBS -l select=1:ncpus=28:mem=800G
# Allow the job to run for up to 24 hours
#PBS -l walltime=48:00:00

## BEGIN SCRIPT
set -euo pipefail

# --- Load modules --- # 
module load rosalind/1.0
module load GCCcore/6.4.0
module load rosalind komplexity bbtools

# --- Job Information ---
date
echo ">>> Job started on: $(hostname)"
echo ">>> Working directory: $(pwd)"
echo ">>> PBS job ID: $PBS_JOBID"

# --- Node resource diagnostics ---
echo ">>> Checking node resources..."
MEM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
MEM_FREE=$(free -h | awk '/Mem:/ {print $7}')
echo " Total memory: $MEM_TOTAL"
echo " Free memory: $MEM_FREE"

# --- Configuration: sample subdirectories to loop script through --- # 
TARGETS=(
   "20210706_IODPExp382_deep_raw"
   "20250111_Aviti_SED24SeqPool2_ARCHIE_COLLAPS_Nantes_LIBtests"
   "20250307_NovaSeq_SED24SeqPool3_SWAIS2CPilot_IODPExp403_KrillBaitsTrial_CANYONSPC01"
   "20250728_SED25SeqPool1_Aviti_COLLAPS_TN"
   "20250901_SED25SeqPool2_KCCGNovaSeq"  
   "SED23SeqPool3_Novaseq_raw"
)

#notes: scheduled job to run komplexity across all sample directories
#if you are using AVITI sequenced samples, add qin=33 after the ac=f to dedupe code --> line 74

# --- Variables --- #
ROOT_DIR="/u/davisee/chapter2_data/Elisa_Prashasti_shotgun_Antarctica_reanalysis_2025"
SUB_target="Komplexity_dedupe_for_fastq_renaming"

# --- Validate Variables --- # 
if [[ ! -d "$ROOT_DIR" ]]; then
  echo "ERROR: Not a directory: $ROOT_DIR" >&2
  usage
  exit 1
fi

echo "Root: $ROOT_DIR"
echo "Creating subfolders in each immediate subdirectory:"
printf '  - %s\n' "${TARGETS[@]}"
echo

#running komplexity and dedupe
for relpath in "${TARGETS[@]}"; do
    echo "Komplexity Processing: $relpath"
    cd "$ROOT_DIR/$relpath" || { echo "Failed to cd into $relpath"; exit 1; }
    mkdir -p "$SUB_target"

    for sample in *.collapsed; do
        kz --filter --threshold 0.55 < "$sample" > "$SUB_target/$sample.kx"
    done

    cd "$SUB_target" || exit 1

    for sample in *.kx; do
        echo "Deduplication Processing: $sample"
        dedupe.sh in="$sample" out="$sample-dd.gz" outd="$sample-duplicates.fa" ac=f
    done

    cd "$ROOT_DIR" || exit 1
done

echo "Done procesing all subdirectory samples in $ROOT_DIR"

module purge

#END SCRIPT

