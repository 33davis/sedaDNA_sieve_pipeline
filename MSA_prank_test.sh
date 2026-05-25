#!/usr/bin/env bash 
#PBS -N mito_msa_prank
#PBS -M emily.davis@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
# Select 1 nodes with 28 cpus per node
#PBS -l select=1:ncpus=28
# Allow the job to run for up to 24 hours
#PBS -l walltime=24:00:00
# force the job to a specific queue
####PBS -q [destination queue]

## BEGIN SCRIPT

# Load and activate conda environment
module load Anaconda3/2024.02-1
source activate /u/davisee/.conda/envs/prank_alignments || { echo "Failed to activate prank_alignments env"; exit 1; }

# Debug info (appears in PBS log)
echo ">>> Conda binary: $(which conda)"
echo ">>> Active env: $CONDA_PREFIX"

# Export environment snapshot for reproducibility
echo ">>> Exporting current environment to mito_msa_prank$(date +%Y%m%d).yaml"
conda env export > "$HOME/mito_msa_prank$(date +%Y%m%d).yaml"

# Define paths
DIR="/u/davisee/Scratch/mito_mining/mito_refseq_all_vish_mitogenomes/3410120_lobontini/"
cd $DIR

# Define other variables
INPUT=$(ls "$DIR"/*_clean.fna)
BASENAME=$(basename "$INPUT" .fna) 
OUTDIR="/u/davisee/Scratch/mito_mining/mito_refseq_all_vish_mitgenomes/${BASENAME}"

# Verify files exist
echo ">>> Checking files..."
ls -lh $INPUT

# Run PRANK
echo ">>> Running prank alignments, verbose 50 iterations +f"
prank -d="$INPUT" -o="$OUTDIR" -iterate=50 -verbose +F 

echo ">>> Job finished at $(date)"

module purge

# END OF SCRIPT
