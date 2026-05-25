#!/usr/bin/bash -l
#PBS -N kddm2_MARESonly
#PBS -M emily.davis@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
# Select 2 nodes with 28 cpus per node
#PBS -l select=2:ncpus=28
# Allow the job to run for up to 24 hours
#PBS -l walltime=24:00:00
# force the job to a specific queue
####PBS -q [destination queue]

## BEGIN SCRIPT
cd ~
date # Print the current time and date to standard output (so you can see when the job started)

#################### modules #####################
module load rosalind/1.0
module load GCCcore/6.4.0
module load rosalind komplexity bbtools megan


# Navigate to directory containing collapsed sample files
cd /u/davisee/Scratch/Exp382-Deep_collapsed/U1538

# Create new directory to input all results
################## define run variables #############
d=$(date +"%d_%m_%Y")
database="MARES_BAR_20240216"
align="MALT"
new_directory="/u/davisee/Scratch/Exp382-Deep_collapsed/U1538/$d-$database"
mkdir "$new_directory"

############## Komplexity #####################
for sample in *.collapsed; do kz --filter --threshold 0.55 < "$sample" > "$sample.kx"; done

# Move komplexity results to new directory
mv /u/davisee/Scratch/Exp382-Deep_collapsed/U1538/*.kx "$new_directory/"

################## Dedupe ######################
cd -- "$new_directory"
for sample in *.kx; do dedupe.sh in="$sample" out="$sample-dd.gz" outd="$sample-duplicates.fa" ac=f -Xmx80g; done

# Navigate to MALT directory
cd /u/davisee/miniconda2/pkgs/malt-0.62-hdfd78af_0/bin
export PATH="/u/davisee/miniconda2/pkgs/malt-0.62-hdfd78af_0/bin:$PATH"

################ Run MALT ########################
./malt-run -i "$new_directory"/*-dd.gz -a "$new_directory" -ou "$new_directory" -at SemiGlobal -f Text -d "/u/davisee/Scratch/$database/" -mem load --mode BlastN -t 8 -v

################ Blast2RMA #######################
module load parallel/20210622-GCCcore-10.3.0
input="$new_directory"
ms=50
me=0.01
supp=0
mpi=90

for i in "$input"/*.kx-dd.gz; do b=${i/.kx-dd.gz/.blastn.gz}; echo blast2rma -r "$i" -i "$b" -o "$input" -v -ms $ms -me $me -f BlastText -supp $supp -mpi $mpi -alg weighted -lcp 90; done | parallel -j 2 --delay 6

#ve post Blast2RMA results to subdirectory
mkdir "$new_directory/$align"
mv "$new_directory"/*.rma6 "$new_directory/$align/"
mv "$new_directory"/*.blastn.gz "$new_directory/$align/"

module purge

#END OF SCRIPT
