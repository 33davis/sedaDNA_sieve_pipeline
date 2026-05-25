#!/usr/bin/bash -l
#PBS -N mito_mining_python_test
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

## BEGIN SCRIPT

# Load and activate conda environment
module load Anaconda3/2024.02-1
source activate /u/davisee/miniconda2/envs/mito_mining || { echo "Failed to activate mito_mining env"; exit 1; }

# Debug info (appears in PBS log)
echo ">>> Conda binary: $(which conda)"
echo ">>> Active env: $CONDA_PREFIX"
echo ">>> Env Python: $CONDA_PREFIX/bin/python"
$CONDA_PREFIX/bin/python --version
$CONDA_PREFIX/bin/python -c "import Bio; print('Biopython available:', Bio.__version__)"

# Export environment snapshot for reproducibility
echo ">>> Exporting current environment to mito_mining_env_$(date +%Y%m%d).yaml"
conda env export > "$HOME/mito_mining_env_$(date +%Y%m%d).yaml"

# Define paths
DIR="/u/davisee/Scratch/mito_mining"
ID="/u/davisee/Scratch/mito_mining/taxa_ids_test.txt"
OUTDIR="/u/davisee/Scratch/mito_mining/mito_metrics_output"

# Verify files exist
echo ">>> Checking files..."
ls -lh $DIR/get_mito_metrics_full.py
ls -lh $ID

# Run Python pipeline
echo ">>> Running mito metrics pipeline"
cd $DIR
$CONDA_PREFIX/bin/python get_mito_metrics_full.py --taxid-file $ID --outdir $OUTDIR --compress

echo ">>> Job finished at $(date)"

module purge

# END OF SCRIPT
