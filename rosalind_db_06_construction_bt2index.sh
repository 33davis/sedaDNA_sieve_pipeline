#!/usr/bin/bash -l
#PBS -N rosalind_constructiondb06_eukmaster_bt2index
#PBS -M emily.davis@utas.edu.au
#PBS -m abe
#PBS -l select=1:ncpus=4:mem=32G
#PBS -l walltime=192:00:00

## BEGIN SCRIPT
set -euo pipefail
#
echo "========== ENV =========="
date
echo "Host: $(hostname)"
echo "JobID: ${PBS_JOBID:-unset}"
echo "Workdir at submit: ${PBS_O_WORKDIR:-unset}"

# -------- Conda environment ----------
# Prefer the modern activation method; avoids surprises on PBS
module load Anaconda3/2024.02-1 || true
source activate /u/davisee/.conda/envs/bowtie2 || {
  echo "ERROR: could not activate conda env"; exit 1; }

# ----- paths ----
number="Plants_Algae_Other"
#part="forwhenI split some indexes into several part"
base_dir="/data/imas_projects/ancient/share/Databases/2026_SO_RefGen_Chordataheavy_curated/db_part_$number"
cd "$base_dir"

ref_in="all_euks_${number}.fna"
index_base="index_part_${number}"

[[ -s "$ref_in" ]] || { echo "ERROR: missing $ref_in"; exit 1; }


# --- running index ---
bowtie2-build $ref_in $index_base


## END OF SCRIPT