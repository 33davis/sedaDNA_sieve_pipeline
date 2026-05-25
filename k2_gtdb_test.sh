#!/usr/bin/bash -l
#PBS -N k2_gtdb_r226
#PBS -M emily.davis@utas.edu.au
#PBS -m abe
#PBS -l select=2:ncpus=28
#PBS -l walltime=72:00:00
####PBS -q [destination queue]

#START OF SCRIPT
# Load and activate conda environment
module load Anaconda3/2024.02-1
source activate /u/davisee/.conda/envs/kraken2 || { echo "Failed to activate kraken2 env"; exit 1; }

# Debug info (appears in PBS log)
echo ">>> Conda binary: $(which conda)"
echo ">>> Active env: $CONDA_PREFIX"

# Paths
DB_DIR=/data/imas_projects/ancient/share/Databases/GTDBr266
GTDB_SERVER=data.ace.uq.edu.au
THREADS=28


echo ">>> Starting Kraken2 GTDB build at $(date)"


# Main build command
k2 build \
  --db "$DB_DIR" \
  --special gtdb \
  --gtdb-files \
    gtdb_genomes_reps.tar.gz \
    bac120_metadata.tsv.gz \
    ar53_metadata.tsv.gz \
    bac120_taxonomy.tsv \
    ar53_taxonomy.tsv \
  --gtdb-use-ncbi-taxonomy \
  --gtdb-server "$GTDB_SERVER" \
  --threads "$THREADS" \
  --masker-threads "$THREADS" 


module purge


#END OF SCRIPT 