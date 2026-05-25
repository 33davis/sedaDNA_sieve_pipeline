#!/usr/bin/bash -l
#PBS -N rosalind_EAGER_apptainer_IODP_test
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
##Run EAGER
#changing directory to the run directory, e.g. where I want /work and /results
cd /u/davisee/chapter2_data/Elisa_Prashasti_shotgun_Antarctica_reanalysis_2025/eager_humanref_kraken2gtdb



#If using newest version of nextflow installed in my directory (works well)
#/u/davisee/nextflow run nf-core/eager \


 # JUST PUT IN ADAPTER LIST AND SEE WHAT HAPPENS
#If using nfcore EAGER link
#nextflow pull nf-core/eager -r 2.5.3 \
nextflow run nf-core/eager \
-r 2.5.3 \
-profile singularity \
-c /u/davisee/scripts_chapter2/IMAS_Nextflow_2025.config \
-w './work/' \
--input '/u/davisee/chapter2_data/Elisa_Prashasti_shotgun_Antarctica_reanalysis_2025/20210706_Exp382_Deep_demux_noncollapsed/*.pair{1,2}.fastq' \
--fasta /data/imas_projects/ancient/share/Databases/HumanRefGenome_GRCh38_latest_genomic.fasta.gz \
--bwa_index '/data/imas_projects/ancient/share/Indices_bwa/HumanRefGenomeGRCh38/' \
--fasta_index '/data/imas_projects/ancient/share/Indices_samtools/HumanRefGenome_GRCh38_latest_genomic.fasta.fai' \
--seq_dict '/data/imas_projects/ancient/share/Indices_picardSeqID/HumanRefGenome_GRCh38_latest_genomic.dict' \
--clip_adapters_list /u/davisee/chapter2_data/Elisa_Prashasti_shotgun_Antarctica_reanalysis_2025/20210706_Exp382_Deep_demux_noncollapsed/adapter_list.txt \
--trimns \
--trimqualities \
--collapse \
--dedupper "dedup" \
--mapper "bowtie2" \
--damage_calculation_tool "mapdamage" \
--run_bam_filtering true \
--bam_unmapped_type "fastq" \
--run_metagenomic_screening true \
--metagenomic_tool "kraken" \
--database '/data/imas_projects/ancient/share/Databases/GTDBr226_k2_ncbitaxonomy/' \
--outdir './results_20210706_Exp382_noncollapsed/' 

date


echo ">>> finished eager run."
echo ">>> You can clean up temporary work files with:"
echo "nextflow clean -f -k"

module purge



#END OF SCRIPT
