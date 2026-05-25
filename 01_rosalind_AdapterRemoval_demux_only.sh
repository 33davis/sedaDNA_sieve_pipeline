#!/usr/bin/bash -l
#PBS -N rosalind_AdapterRemoval_just_demux
#PBS -M emily.davis@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
#PBS -l select=1:ncpus=28
#PBS -l walltime=24:00:00
# force the job to a specific queue
####PBS -q [destination queue]

## BEGIN SCRIPT
cd /u/davisee/chapter2_data/Elisa_Prashasti_shotgun_Antarctica_reanalysis_2025/20250901_SED25SeqPool2_KCCGNovaSeq_SWAIS2C

date # Print the current time and date to standard output (so you can see when the job started)
echo ">>> Job started on: $(hostname)"
echo ">>> Working directory: $(pwd)"
echo ">>> PBS job ID: $PBS_JOBID"

module load rosalind/1.0
module load gcc-env/6.4.0
module load rosalind adapterremoval komplexity bbtools megan

# Memory and CPU diagnostic block
echo ">>> Checking node resources..."
MEM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
MEM_FREE=$(free -h | awk '/Mem:/ {print $7}')
echo "    Total memory: $MEM_TOTAL"
echo "    Free memory: $MEM_FREE"

THREADS=16  # <-- You can safely adjust this later to 20–28 if stable
echo ">>> AdapterRemoval will run using $THREADS threads."

#AdapterRemoval command will demultiplex and remove the barcodes, but not remove adapters or collapse the reads; suitable for nf-core/EAGER
AdapterRemoval \
--barcode-list /u/davisee/chapter2_data/Elisa_Prashasti_shotgun_Antarctica_reanalysis_2025/20250901_SED25SeqPool2_KCCGNovaSeq_SWAIS2C/barcodes_SWAIS2C.txt \
--file1 /u/davisee/chapter2_data/Elisa_Prashasti_shotgun_Antarctica_reanalysis_2025/20250901_SED25SeqPool2_KCCGNovaSeq_SWAIS2C/HCCLNDSXF_1_250717_FS28687269_Other_GCAAGAT-AGATCTC_R_250715_LINARM_INDEXLIBNOVASEQ_P001_R1.fastq.gz \
--file2 /u/davisee/chapter2_data/Elisa_Prashasti_shotgun_Antarctica_reanalysis_2025/20250901_SED25SeqPool2_KCCGNovaSeq_SWAIS2C/HCCLNDSXF_1_250717_FS28687269_Other_GCAAGAT-AGATCTC_R_250715_LINARM_INDEXLIBNOVASEQ_P001_R2.fastq.gz \
--basename 20250901_SED25SeqPool2_KCCGNovaSeq_SWAIS2C \
--barcode-mm 1 \
--minlength 25 \
--threads $THREADS

date

echo ">>> If output files are compressed, the file extension needs to be renamed to .fastq.gz"
echo ">>> If uncompressed, the file extension needs to be renamed to .fastq"

module purge

#END OF SCRIPT
