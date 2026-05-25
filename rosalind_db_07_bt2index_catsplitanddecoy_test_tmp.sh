#!/usr/bin/bash -l
#PBS -N rosalind_bt2index_cat_fungiprotist_test
#PBS -M emily.davis@utas.edu.au
#PBS -m abe
#PBS -l select=1:ncpus=4:mem=32G
#PBS -l walltime=60:00:00

# -------- Conda environment ----------
module load Anaconda3/2024.02-1 || true
source activate /u/davisee/.conda/envs/bowtie2 || {
  echo "ERROR: could not activate conda env"; exit 1; }

# -------- Variables and directories --------
BASE="/data/imas_projects/ancient/share/Databases/2026_SO_RefGen_Chordataheavy_curated"
PART="Fungi_Protists_part_001"
DECOY="${BASE}/prokaryotic_decoy_withHuman.fna"
FNA_DIR="${BASE}/fna_parts"
IDX_DIR="${BASE}/indexes"
LOG_DIR="${BASE}/logs"
TMP_FNA="/scratch/${USER}/${PBS_JOBID}/${PART}_with_decoy.fna"

mkdir -p "$LOG_DIR" "/scratch/${USER}/${PBS_JOBID}"
cd "$BASE"
# -------- Trap: cleanup temp file and stop logging loop on any exit --------
cleanup() {
    kill "$MEM_LOG_PID" 2>/dev/null || true
    wait  "$MEM_LOG_PID" 2>/dev/null || true
    rm -f "$TMP_FNA"
    rmdir "/scratch/${USER}/${PBS_JOBID}" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') bowtie2-build exited" \
        >> "${LOG_DIR}/${PART}_mem_log.txt"
}
trap cleanup EXIT

# -------- Start memory + I/O logging in the background --------
while true; do
    TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

    # --- RAM usage from PBS ---
    echo -n "${TIMESTAMP} " >> "${LOG_DIR}/${PART}_mem_log.txt"
    /opt/pbs/bin/qstat -fx "${PBS_JOBID}" \
        | grep "resources_used.mem" >> "${LOG_DIR}/${PART}_mem_log.txt"

    # --- Disk I/O pressure (3 snapshots, 2 sec apart, averaged by iostat) ---
    echo "=== ${TIMESTAMP} ===" >> "${LOG_DIR}/${PART}_io_log.txt"
    iostat -x 2 3 \
        | grep -E "^(Device|sd|nvm|xv)" >> "${LOG_DIR}/${PART}_io_log.txt"

     # --- Temp file growth ---
    echo -n "${TIMESTAMP} tmp_size=" >> "${LOG_DIR}/${PART}_io_log.txt"
    du -sh "${TMP_FNA}" 2>/dev/null | awk '{print $1}' \
        >> "${LOG_DIR}/${PART}_io_log.txt"

    # --- Scratch space remaining (shared across all jobs) ---
    echo -n "${TIMESTAMP} scratch_avail=" >> "${LOG_DIR}/${PART}_io_log.txt"
    df -h /scratch \
        | awk 'NR==2 {print $4}' >> "${LOG_DIR}/${PART}_io_log.txt"

    sleep 300
done &
MEM_LOG_PID=$!

# -------- Concatenate input into a real file --------
echo "$(date '+%Y-%m-%d %H:%M:%S') Concatenating FASTA files..." \
    >> "${LOG_DIR}/${PART}_mem_log.txt"

cat "${FNA_DIR}/${PART}.fasta.fna" "${DECOY}" > "$TMP_FNA"

# -------- Run the index build --------
echo "$(date '+%Y-%m-%d %H:%M:%S') Starting bowtie2-build..." \
    >> "${LOG_DIR}/${PART}_mem_log.txt"

bowtie2-build "$TMP_FNA" "${IDX_DIR}/${PART}"

module purge
# EXIT trap fires here: kills logging loop and deletes temp file