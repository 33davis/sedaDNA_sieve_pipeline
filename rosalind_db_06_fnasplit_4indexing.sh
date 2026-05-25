#!/usr/bin/env bash
#PBS -M emily.davis@utas.edu.au
#PBS -m abe
#PBS -N split_Reptiles_byparts
#PBS -l select=1:ncpus=4:mem=50G
#PBS -l walltime=24:00:00
set -euo pipefail 

#START SCRIPT

module load Anaconda3/2024.02-1
source activate /u/davisee/.conda/envs/SeqKit || true

BASE_DIR="/data/imas_projects/ancient/share/Databases/2026_SO_RefGen_Chordataheavy_curated"
cd $BASE_DIR

cat db_part_Reptiles/all_euks_Reptiles_clean.fna | \
seqkit split2 \
    -p 4 \
    --out-dir fna_parts/ \
    -P Reptiles_part_ \
    -e .fna \
    -
date 
module purge
# END SCRIPT