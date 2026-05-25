
#!/usr/bin/bash -l
#PBS -N rosalind_demux_trim_no_merge
#PBS -M emily.davis@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
#PBS -l select=1:ncpus=28
#PBS -l walltime=24:00:00
####PBS -q [destination queue]

# --- BEGIN SCRIPT ---
module load rosalind/1.0
module load gcc-env/6.4.0
module load rosalind adapterremoval komplexity bbtools megan

# Working directory for demux and adapterremoval
cd /u/davisee/chapter2_data/Elisa_Prashasti_shotgun_Antarctica_reanalysis_2025/20250901_SED25SeqPool2_KCCGNovaSeq_SWAIS2C

date
echo ">>> Job started on: $(hostname)"
echo ">>> Working directory: $(pwd)"
echo ">>> PBS job ID: $PBS_JOBID"

# --- Node resource diagnostics (unchanged) ---
echo ">>> Checking node resources..."
MEM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
MEM_FREE=$(free -h | awk '/Mem:/ {print $7}') 
echo " Total memory: $MEM_TOTAL"
echo " Free memory: $MEM_FREE"

# Threads (you set 16 previously; keep or raise to 28 if stable)
THREADS=28
echo ">>> AdapterRemoval will run using $THREADS threads."

# --- Inputs ---
BARCODE_LIST="barcodes_SWAIS2C.txt"           # same folder
ADAPTER_LIST="./adapter_list.txt"              # same folder
IN_R1="HCCLNDSXF_1_250717_FS28687269_Other_GCAAGAT-AGATCTC_R_250715_LINARM_INDEXLIBNOVASEQ_P001_R1.fastq.gz"
IN_R2="HCCLNDSXF_1_250717_FS28687269_Other_GCAAGAT-AGATCTC_R_250715_LINARM_INDEXLIBNOVASEQ_P001_R2.fastq.gz"

# --- Outputs ---
BASENAME="20250901_SED25SeqPool2_KCCGNovaSeq_SWAIS2C"
DEMUX_PREFIX="${BASENAME}_demux_atrim_"  # per-barcode prefixes

# --- Run AdapterRemoval: demultiplex + adapter-trim, no merging ---
# Notes:
# - --barcode-mm 1 : allow 1 mismatch in barcode matching (same as your original)
# - --trimns --trimqualities : trim terminal Ns and low qualities
# - --minlength 25 : drop very short reads post-trimming
# - --demultiplexed-output-prefix : clearer per-sample file names
# - No --collapse flags: paired-end remains separate (no merging)
# - Uncomment --gzip if you want compressed outputs immediately

AdapterRemoval \
  --file1 "$IN_R1" \
  --file2 "$IN_R2" \
  --barcode-list "$BARCODE_LIST" \
  --barcode-mm 1 \
  --adapter-list "$ADAPTER_LIST" \
  --trimns \
  --trimqualities \
  --minlength 25 \
  --threads "$THREADS" \
  --basename "$BASENAME" \
  --demultiplexed-output-prefix "$DEMUX_PREFIX" \
  --threads "$THREADS"
  # --gzip   # optional: produce .gz outputs directly

date
echo ">>> If output files are compressed, ensure they end with .fastq.gz"
echo ">>> If uncompressed, ensure they end with .fastq"

module purge
# --- END OF SCRIPT ---
