#!/usr/bin/bash -l
#PBS -N rosalind_EAGER_apptainer_EBC_test
#PBS -M emily.davis@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
#PBS -l select=1:ncpus=28
#PBS -l walltime=72:00:00
# force the job to a specific queue
####PBS -q [destination queue]

## Before running EAGER do manually in terminal: nextflow pull nf-core/eager -r 2.5.3

## BEGIN SCRIPT

        module load rosalind/1.0
		module load java/jdk-18.0.2
		module load apptainer/ApptainerSigularityAlias 
		module load nextflow/22.04.5 

## logs and diagnostics
# --- Node resource diagnostics (unchanged) ---
echo ">>> Checking node resources..."
MEM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
MEM_FREE=$(free -h | awk '/Mem:/ {print $7}')cd 
echo " Total memory: $MEM_TOTAL"
echo " Free memory: $MEM_FREE" 


## Setting Variables
inputFolder="/u/davisee/chapter2_data/adaptertrim_demultiplexed_nocollapse_sample_input_fastq/eager_testing"
resultsFolder="/u/davisee/chapter2_data/eager_kraken2gtdb_results"
configFile="/u/davisee/scripts_chapter2/IMAS_Nextflow_2025.config"
DBdir="/data/imas_projects/ancient/share/Databases/GTDBr226_k2_ncbitaxonomy/"
refGenome="/data/imas_projects/ancient/share/Databases/HumanRefGenome_GRCh38_latest_genomic.fasta.gz"


#If using newest version of nextflow installed in my directory (works well)
#/u/davisee/nextflow run nf-core/eager \


#### Run EAGER 
#If using nfcore EAGER link
#nextflow pull nf-core/eager -r 2.5.3 \
#-resume $runName --> add to this for resuming a run

for f in $inputFolder/*pair1.fastq
do
SAMPLE=$(echo ${f} | sed "s/pair1\.fastq//")
SAMPLE_pe="${SAMPLE}pair{1,2}.fastq"1
filename="${SAMPLE##*/}"
runName="filterGTDB_$(date +%Y%m%d)"
results="$resultsfolder/${runName}/"
workdir="/u/davisee/eager_testing/work_ED_${runName}/"
nextflow run nf-core/eager \
-r 2.5.3 \
-profile singularity \
-c $configFile \
-w $workdir \
--input $SAMPLE_pe \
--fasta $refGenome \
--clip_readlength 25 \
--mergedonly \
--dedupper "dedup" \
--mapper 'bowtie2' \
--bt2_alignmode 'local' \
--bt2_sensitivity 'sensitive' \
--run_bam_filtering \
--bam_unmapped_type 'fastq' \
--run_metagenomic_screening true \
--metagenomic_tool "kraken" \
--database $DBdir \
--outdir $results

done

echo ">>> finished eager run."
echo ">>> You can clean up temporary work files with:"
echo "nextflow clean -f -k"

module purge



#END OF SCRIPT
