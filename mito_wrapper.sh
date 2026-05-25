#!/usr/bin/bash -l
#PBS -N mito_mining_test_penguin 
#PBS -M emily.davis@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
# Select 1 nodes with 28 cpus per node
#PBS -l select=1:ncpus=28
# Allow the job to run for up to 24 hours
#PBS -l walltime=24:00:00
# force the job to a specific queue
####PBS -q [destination queue]


# BEGIN SCRIPT

# --- Load environment ---
module load Anaconda3/2024.02-1
source activate /u/davisee/miniconda2/envs/mito_mining || { echo "Failed to activate mito_mining env"; exit 1; }

# --- Debug info ---
echo ">>> Conda binary: $(which conda)"
echo ">>> Active env: $CONDA_PREFIX"

# --- Export environment snapshot ---
echo ">>> Exporting current environment to mito_mining_env_$(date +%Y%m%d).yaml"
conda env export > "$HOME/mito_mining_env_$(date +%Y%m%d).yaml"

# --- Define variables ---
DIR="/u/davisee/mito_mining"
ID_FILE="/u/davisee/mito_mining/taxa_ids_test.txt"
COMPRESS_FLAG="--compress"

# --- Verify files exist ---
echo ">>> Checking files..."
[[ -x "$DIR/get_mito_metrics_full.sh" ]] || { echo "ERROR: get_mito_metrics_full.sh not found or not executable"; exit 1; }
[[ -s "$ID_FILE" ]] || { echo "ERROR: TaxID file is missing or empty"; exit 1; }

# --- Run mito metrics pipeline ---
echo ">>> Running mito metrics pipeline"
cd "$DIR"
./get_mito_metrics_full.sh "$ID_FILE" $COMPRESS_FLAG

# --- Check for taxa with no mitochondrial genomes ---
echo ">>> Checking for taxa with no mitochondrial genomes..."
while read -r TAXID; do
    [[ -z "$TAXID" ]] && continue
    if [[ ! -s "$DIR/mito_metrics_output/$TAXID/mitogenomes.fasta" && ! -s "$DIR/mito_metrics_output/$TAXID/mitogenomes.fasta.gz" ]]; then
        echo "WARNING: No mitochondrial genomes found for TaxID $TAXID"
    fi
done < "$ID_FILE"

echo ">>> Job finished at $(date)"

# --- Clean up ---
module purge

#END OF SCRIPT
