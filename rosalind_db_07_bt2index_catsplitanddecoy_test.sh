#!/usr/bin/bash -l
#PBS -N rosalind_bt2index_cat_fungiprotist_test
#PBS -M emily.davis@utas.edu.au
#PBS -m abe
#PBS -l select=1:ncpus=4:mem=32G
#PBS -l walltime=60:00:00

set -euo pipefail

#module load 
# -------- Conda environment ----------
# Prefer the modern activation method; avoids surprises on PBS
module load Anaconda3/2024.02-1 || true
source activate /u/davisee/.conda/envs/bowtie2 || {
  echo "ERROR: could not activate conda env"; exit 1; }

# -------- Variables and directories --------
#basic script with variables to add
    #name="Fungi_Protists"
    #number=1:7
    #PART_FNA=fna_parts/${name}_part${number}.fna
    #DECOY_FNA=prokaryotic_decoy.fna 
    #INDEX_OUT=indexes/${name}_part${number}
BASE="/data/imas_projects/ancient/share/Databases/2026_SO_RefGen_Chordataheavy_curated"
PART="Fungi_Protists_part_001"
DECOY="${BASE}/prokaryotic_decoy_withHuman.fna"
FNA_DIR="${BASE}/fna_parts"
IDX_DIR="${BASE}/indexes"
LOG_DIR="${BASE}/logs"

mkdir -p  $LOG_DIR
cd $BASE

# -------- Start memory logging in the background --------
while true; do
    echo -n "$(date '+%Y-%m-%d %H:%M:%S') " >> "${LOG_DIR}/${PART}_mem_log.txt"
    /opt/pbs/bin/qstat -fx "${PBS_JOBID}" \
        | grep "resources_used.mem"        >> "${LOG_DIR}/${PART}_mem_log.txt"
    sleep 300
done &
MEM_LOG_PID=$!   # capture the loop's PID so we can stop it later

# -------- Run the index build --------
bowtie2-build \
    <(cat "${FNA_DIR}/${PART}.fasta.fna" "${DECOY}") \
    "${IDX_DIR}/${PART}"

BT2_EXIT=$?   # save bowtie2 exit code before anything else runs

# -------- Stop the logging loop --------
kill "$MEM_LOG_PID" 2>/dev/null
wait  "$MEM_LOG_PID" 2>/dev/null   # reap the background process cleanly

echo "bowtie2-build finished with exit code ${BT2_EXIT}" \
    >> "${LOG_DIR}/${PART}_mem_log.txt"

module purge
exit "$BT2_EXIT"

#end of script 

