#!/usr/bin/bash -l
#PBS -N rename_kxdd_outputs
#PBS -M emily.davis@utas.edu.au
#PBS -m abe
#PBS -l select=1:ncpus=1
#PBS -l walltime=01:00:00

# Change directory to where pre-kraken2 outputs are located
cd /u/davisee/chapter2_data/collapsed_kxdd_4k2

date
echo ">>> Renaming AdapterRemoval output files safely..."
echo ">>> Working directory: $(pwd)"

# 1️⃣ Check if compressed files exist (.gz extension)
if ls *.gz 1> /dev/null 2>&1; then
    echo ">>> Detected compressed files (.gz). Renaming to .fastq.gz..."
    for f in *.collapsed.kx-dd*; do
        if [ -f "$f" ]; then
            new="${f%.collapsed.kx-dd.}.ckdd.fastq.gz"
            if [ -f "$new" ]; then
                echo "⚠️  Skipping '$f' — target file '$new' already exists."
            else
                mv -v "$f" "$new"
            ficd 
        fi
    done
else
    # 2️⃣ Otherwise assume uncompressed
    echo ">>> Detected uncompressed files. Renaming to .fastq..."
    for f in *.collapsed.kx-dd*; do
        if [ -f "$f" ]; then
            new="${f%.collapsed.kx-dd*}.fastq"
            if [ -f "$new" ]; then
                echo "⚠️  Skipping '$f' — target file '$new' already exists."
            else
                mv -v "$f" "$new"
            fi
        fi
    done
fi

echo ">>> Renaming complete!"
date