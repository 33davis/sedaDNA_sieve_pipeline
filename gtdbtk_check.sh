#!/usr/bin/bash -l
#PBS -N gtdbtk_check_install
#PBS -M emily.davis@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
# Select 2 nodes with 28 cpus per node
#PBS -l select=2:ncpus=28
# Allow the job to run for up to 24 hours
#PBS -l walltime=48:00:00
# force the job to a specific queue
####PBS -q [destination queue]

#START OF SCRIPT
# Load and activate conda environment
module load Anaconda3/2024.02-1
source activate /u/davisee/.conda/envs/gtdb_tk || { echo "Failed to activate kraken2 env"; exit 1; }

# Debug info (appears in PBS log)
echo ">>> Conda binary: $(which conda)"
echo ">>> Active env: $CONDA_PREFIX"


# change to right directory 
cd /u/davisee/.conda/envs/gtdb_tk

gtdbtk check_install

echo ">>> gtdb_tk successfully downloaded"

module purge 

#END OF SCRIPT


