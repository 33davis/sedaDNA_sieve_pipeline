# Data Processing: MALT Index Build

# This script builds a MALT index using RefSeq plant genomic data (adapted from rosalind_malt_index_RefSeq.sh in shared rosalind folder)
# database downloaded to shared rosalind folder under RefSeq_20251024_plant_genomic.fna.gz
# now ready to be indexed

# Note: MALT index building requires FASTA format files (.fna, .fa, .fasta, .gz).

#!/usr/bin/bash -l
#PBS -N rosalind_malt-index_RefSeq_2025_plants
#PBS -M ej.miller@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
# Select 1 nodes with 128 cpus per node and 980 memory, this is maximum possible which you will need for Refseq databases
#PBS -l select=1:ncpus=128:mem=980G
# Allow the job to run for up to 72 hours - can extend this up to 120 hours
#PBS -l walltime=120:00:00
# force the job to a specific queue
####PBS -q [destination queue]

date # Print the current time and date to standard output (so you can see when the job started)

#load modules
module load rosalind/1.0
module load gcc-env/6.4.0
module load rosalind adapterremoval komplexity bbtools megan

# Activate Conda environment with MALT installed
source ~/.bashrc
conda activate malt_env

# Confirm malt-build is available
which malt-build


# Create output directory in home space
mkdir -p /u/millere0/malt_indices/RefSeq_20251024_plant_genomic

#run MALT index
malt-build \
  -i /data/imas_projects/ancient/share/Databases/RefSeq_20241117_partial/RefSeq_20251024_plant_genomic.fna.gz \
  --sequenceType DNA \
  --buildTableInMemory false \
  --index /u/millere0/malt_indices/RefSeq_20251024_plant_genomic \
  --threads 32 \
  --hashScaleFactor 0.1 \
  --maxHitsPerSeed 5 \
  --verbose
#put output into Indices malt folder (in shared rosalind) (keep dates in filenames - keep filename the same without gz)	
#here are some additional prameters that you can try when you still run out of memory - as per malt manual - please read that to understnd what they do and how you might need to chnge them
# --buildTableInMemory false #avoids keeping the entire table in RAM
# --extraStrict true #skips more low-complexity seeds *use with caution since ancient DNA is highly fragmented this may affect things
# --hashScaleFactor 0.1 #reduces hash table size (default is 1) - reduces memory usage by shrinking hash table (slow lookups but no major impact on alignment quality) - safe
# --maxHitsPerSeed 5 #limits memory per seed (default is 1000?) - limits number of locations a seed can align to (may miss alignments in repetitive regions but ancient DNA is usually short and unique) - should be safe
# --random 1 
# --step 10 #speeds up scanning - default is 1 and that is the most accurate, accuracy will go down a lot when increasing this number (max 100) *use with caution
# changing threads changes parallelism - speed of build but no impact on index quality (safe to reduce if memory is tight)
date
module purge

#End of script

#to submit script in rosalind:
#upload into scripts folder
#work inside the scripts directory 
#cd /u/millere0/scripts/
#qsub 06_malt_index_build.sh




###########TROUBLESHOOTING##########
# java.io.IOException: mkdir failed: /data/imas_projects/ancient/share/Indices_malt/RefSeq_20251024_plant_genomic

# means MALT cannot create the output directory for the index. This is almost always a permissions issue or the directory already exists but is not writable.

# #check if directory exists
# ls -ld /data/imas_projects/ancient/share/Indices_malt/RefSeq_20251024_plant_genomic
# if exists, check permissions
# ls -ld /data/imas_projects/ancient/share/Indices_malt

# If I don't have write access, i'll need to: use a directory in my home space (/u/millere0/malt_indices/)
# or ask admin to grant write permissions

# If directory does not exist, create it manually (if i can)
# mkdir -p /data/imas_projects/ancient/share/Indices_malt/RefSeq_20251024_plant_genomic
# or in my home directory



# # if cannot write to shared space, change --index path in script
# --index /u/millere0/malt_indices/RefSeq_20251024_plant_genomic
# create that folder
# mkdir -p /u/millere0/malt_indices/RefSeq_20251024_plant_genomic

# drwxr-s--- indicates permissions:
# Owner: read/write/execute
# Group: read/execute (NOT write)
# Others: no access

# I am in the group but cannot create (write) files because the group lacks permission

#can use home directory to put index and later copy over to shared folder (if permissions allow)
#might want to add --extraStrict true or --hashScaleFactor 0.1 if memory issues persist




#submitted 31-10-2025 2:58 pm Job ID 1241829
#terminated at 03-11-2025 3:00pm (set for 72 hours) - done? check output files
# PBS Job Id: 1241829.rosalind-pbs-0.tpac.org.au
# Job Name:   rosalind_malt-index_RefSeq_2025_plants
# Execution terminated
# Exit_status=271
# resources_used.cpupercent=6333
# resources_used.cput=52:38:24
# resources_used.mem=1036855024kb
# resources_used.ncpus=128
# resources_used.vmem=3477981548kb
# resources_used.walltime=72:02:01

#scheduler will say completed or done not terminated if it finishes successfully
#terminated incdicates an error in the run, job was killed by scheduler or system (due to resource limits)

# terminated due to not enough walltime (almost finished - got to the final hash table fill step -  but needed a little more than 72 hours! :'( )
# increased walltime to 120 and re-submitted (will overwrite files - cannot resume from any point - must re-submit)
# re-submitted 04-11-2025 10:59am job ID 1242255

#linda's script says can extend wall time to 120 hours - I have re-submitted with increased walltime
#if the max walltime is 72 hours, need to use memory saving parameters

#jod needed more walltime - didn't finish
# Filling hash table...
# =>> PBS: job killed: walltime 432004 exceeded limit 432000

#re-submitted at 8:50am 10-11-2025 job ID1242801 (in the queue)
#waiting in queue and forgot to comment out something - deleted and resubmitted 10-11-25 2:35pm job ID 1242823

