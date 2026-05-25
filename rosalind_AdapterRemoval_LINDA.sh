#!/usr/bin/bash -l
#PBS -N rosalind_AdapterRemoval_SWAIS2C
#PBS -M linda.armbrecht@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
# Select 2 nodes with 28 cpus per node
#PBS -l select=2:ncpus=28
# Allow the job to run for up to 24 hours
#PBS -l walltime=24:00:00
# force the job to a specific queue
####PBS -q [destination queue]

## BEGIN SCRIPT
cd /u/lindaa3/Scratch/SED25SeqPool2_KCCGNovaSeq_SWAIS2C/

date # Print the current time and date to standard output (so you can see when the job started)

module load rosalind/1.0
module load gcc-env/6.4.0
module load rosalind adapterremoval komplexity bbtools megan
module load java/jdk-18.0.2
module load apptainer/ApptainerSigularityAlias 
module load fastqc/0.11.9

fastqc *fastq.gz
multiqc *fastqc*

#if AVITI: include --qualitymax 60
AdapterRemoval --barcode-list /u/lindaa3/Scratch/SED25SeqPool2_KCCGNovaSeq_SWAIS2C/barcodes_SWAIS2C.txt --adapter-list /u/lindaa3/Scratch/SED25SeqPool2_KCCGNovaSeq_SWAIS2C/adapter_list.txt --file1 /u/lindaa3/Scratch/SED25SeqPool2_KCCGNovaSeq_SWAIS2C/HCCLNDSXF_1_250717_FS28687269_Other_GCAAGAT-AGATCTC_R_250715_LINARM_INDEXLIBNOVASEQ_P001_R1.fastq.gz --file2 /u/lindaa3/Scratch/SED25SeqPool2_KCCGNovaSeq_SWAIS2C/HCCLNDSXF_1_250717_FS28687269_Other_GCAAGAT-AGATCTC_R_250715_LINARM_INDEXLIBNOVASEQ_P001_R2.fastq.gz --basename IMAS  --collapse --trimns --trimqualities --barcode-mm 1 --minlength 25 --threads 2

#fastqc multiqc
cd /u/lindaa3/Scratch/SED25SeqPool2_KCCGNovaSeq_SWAIS2C/
fastqc *collapsed
multiqc *fastqc*

date

module purge

#END OF SCRIPT
