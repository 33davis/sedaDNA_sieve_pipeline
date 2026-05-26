#!/usr/bin/bash -l
#PBS -N so_RAMS_whitelist_gbif_crosscheck_wrapper
#PBS -M emily.davis@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
#PBS -l select=1:ncpus=1:mem=16gb
#PBS -l walltime=8:00:00

#START SCRIPT

# load modules
module load R/4.4.1-gfbf-2023b

# set variables
HOME_DIR="/u/davisee/Refseq_2026/RAMS_whitelist_construction"

cd ${HOME_DIR}

#run script that has previously been scripted to convert the NCBI lineage file into a format that can be used for the RAMS whitelist construction

Rscript 02_gbif_csvmerge_gbifcheck_whitelistconstruction.R


module purge
date
#END SCRIPT