#1. BWA indexing

# do once for each database -> map/align -> convert to BAM files -> dedupe BAM files -> mapdamge (takes filtered/deduped BAM files)
#adapt
#set up bwa environment and download into there
#make sure output index goes to bwa_indices in my home directory
#do this for RefSeq (protozoa, mitochondria, plastids) and RefSeq plants (total 2x)
#bwa index cannot index a compressed FASTA gile (.gz) - need to decompress first

#!/usr/bin/bash -l
#PBS -N BWA_Indexing_RefSeq_20241117_protozoa_mitochondrion_plastid_genomic
#PBS -M ej.miller@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
# Select 1 node with 8 cpus per node (extra memory because RefSeq is huge)
#PBS -l select=1:ncpus=8:mem=128GB
#Allow the job to run for up to 24 hours
#PBS -l walltime=24:00:00

# Load required modules
module load Anaconda3/2024.02-1  #Check latest version (may have to update this) *abort job and re-run with latest anaconda

# activate a new environment for BWA
source ~/.bashrc
conda activate bwa_env

# Define the reference FASTA file 
REF_FASTA="/data/imas_projects/ancient/share/Databases/RefSeq_20241117_partial/RefSeq_20241117_protozoa_mitochondrion_plastid_genomic.fna.gz"
OUT_DIR="/u/millere0/bwa_indices/RefSeq_20241117_protozoa_mito_plastid"
mkdir -p "$OUT_DIR"
cd "$OUT_DIR"


# Decompress FASTA for indexing (cannot index compressed .gz files) - decompressed files will be in output directory from cd out_dir above (/u/millere0/bwa_indices/RefSeq_20241117_protozoa_mito_plastid/RefSeq_20241117_protozoa_mito_plastid.fna)
gunzip -c "$REF_FASTA" > RefSeq_20241117_protozoa_mito_plastid.fna


# Run BWA indexing
bwa index RefSeq_20241117_protozoa_mito_plastid.fna

conda deactivate
module purge

#submitted 06-11-2025 12:51pm job ID 1242547
#job finished 4:51pm 06-11-2025

#to confirm index is ready for use: look for .amb, .ann, .bwt, .pac. sa files (standard BWA index files) - it does!




