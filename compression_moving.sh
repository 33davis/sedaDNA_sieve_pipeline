#!/usr/bin/env bash 
#PBS -N db_compression_moving
#PBS -M emily.davis@utas.edu.au
# Send mail for (a)borted, (b)eginning and (e)nd job
#PBS -m abe
#PBS -l select=1:ncpus=8
#PBS -l walltime=24:00:00

# BEGIN SCRIPT 
module spider zstd/1.5.5-GCCcore-13.2.0

# ----- CONFIGURE THESE -----
DB_DIR="/u/davisee/GTDBr226_k2_ncbitaxonomy"
OUTDIR="/data/imas_projects/ancient/share/Databases"
ARCHIVE_NAME="GTDBr226_k2_ncbitaxonomy.tar.zst"
# ----------------------------

echo "Starting compression job at $(date)"
cd $HOME

echo "Creating tarball with zstd compression..."
tar --use-compress-program="zstd -T8 --ultra -22" -cvf $ARCHIVE_NAME "$DB_DIR"

echo "Generating MD5 checksum..."
md5sum $ARCHIVE_NAME > ${ARCHIVE_NAME}.md5

echo "Copying to shared lab folder via SCP..."
scp $ARCHIVE_NAME ${ARCHIVE_NAME}.md5 "$OUTDIR/"

echo "Verifying file size matches source..."
echo "--- Source ---"
ls -lh $ARCHIVE_NAME
echo "--- Destination ---"
ls -lh "$OUTDIR/$ARCHIVE_NAME"

echo "Compression + transfer finished at $(date)"

module purge

# END OF SCRIPT 
n