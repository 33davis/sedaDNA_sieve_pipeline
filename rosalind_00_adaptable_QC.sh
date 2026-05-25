#!/usr/bin/bash -l
#PBS -N rosalind_QV_postk2_unmatched
#PBS -M emily.davis@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
#PBS -l select=1:ncpus=28
#PBS -l walltime=24:00:00

# --- Begin script --- #
#establish variables 
home_dir="/u/davisee/chapter2_data/collapsed_kxdd_rename_4k2/for_competitive_k2_unclassified_fq"
output_dir="/u/davisee/chapter2_data/collapsed_kxdd_rename_4k2/for_competitive_k2_unclassified_fq/fastqc_multiqc_output"

cd $home_dir
mkdir -p $output_dir

# Load necessary fastqc modules 
module load rosalind/1.0
module load fastqc/0.11.9
fastqc *.fq -o $output_dir
module purge

#load necessary multiqc modules
module load rosalind/1.0  
module load gcc-env/6.4.0  
module load openmpi-env/3.1.1
module load python/3.7.4
multiqc *fastqc* -o $output_dir

date

module purge

#END OF SCRIPT