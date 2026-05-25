#!/bin/bash

# ============================
# get_mito_metrics_full.sh
# Safe version with optional kmer
# ============================

# Usage:
#   ./get_mito_metrics_full.sh <taxa_id_file> [--compress]
#
# Example:
#   ./get_mito_metrics_full.sh taxa_ids.txt --compress
#
# Notes:
# - If jellyfish is installed, k-mer frequencies will be calculated.
# - If not, the script runs safely without k-mers.
# - Outputs: one directory per Taxon ID and combined stats tables.

# === Parse arguments ===
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <taxa_id_file> [--compress]"
    exit 1
fi

TAXA_FILE="$1"
shift

COMPRESS=false
for arg in "$@"; do
    case $arg in
        --compress) COMPRESS=true ;;
    esac
done

# === Detect kmer support ===
if command -v jellyfish >/dev/null 2>&1; then
    echo ">>> jellyfish detected, enabling k-mer mode"
    USE_KMER=true
else
    echo ">>> jellyfish NOT found, running in no-kmer mode"
    USE_KMER=false
fi

# === Combined outputs ===
COMBINED_DIR="combined_results"
mkdir -p "$COMBINED_DIR"
COMBINED_STATS="$COMBINED_DIR/combined_stats.tsv"
COMBINED_KMERS="$COMBINED_DIR/combined_kmers.tsv"

# Initialize combined stats
echo -e "TaxonID\tNumGenomes\tGC_Content\tGC_Skew\tAT_Skew\tCompleteness" > "$COMBINED_STATS"
if $USE_KMER; then
    echo -e "TaxonID\tKmer\tCount" > "$COMBINED_KMERS"
fi

# === Main loop ===
while read -r TAXON_ID; do
    [[ -z "$TAXON_ID" ]] && continue  # skip empty lines

    echo ">>> Processing $TAXON_ID"
    OUTDIR="${TAXON_ID}_mito_metrics"
    mkdir -p "$OUTDIR"

    # Step 1: Download mitochondrial genomes
    echo "Downloading mitochondrial genomes for $TAXON_ID..."
    datasets download genome taxon "$TAXON_ID" --include genome --assembly-source refseq --filename "$OUTDIR/genomes.zip"
    unzip -o "$OUTDIR/genomes.zip" -d "$OUTDIR"
    FASTA="$OUTDIR/ncbi_dataset/data/*/*.fna"

    if [[ ! -f $FASTA ]]; then
        echo "WARNING: No FASTA found for $TAXON_ID"
        continue
    fi

    # Step 2: Compute metrics
    NUM_GENOMES=$(grep -c "^>" $FASTA)
    GC_CONTENT=$(seqtk comp $FASTA | awk '{gc+=($2+$3);total+=($2+$3+$4+$5)} END {if(total>0) print gc/total; else print 0}')
    GC_SKEW=$(seqtk comp $FASTA | awk '{gc+=$2;cg+=$3} END {if((gc+cg)>0) print (gc-cg)/(gc+cg); else print 0}')
    AT_SKEW=$(seqtk comp $FASTA | awk '{at+=$4;ta+=$5} END {if((at+ta)>0) print (at-ta)/(at+ta); else print 0}')
    COMPLETENESS=$(grep -c ">" $FASTA)

    echo -e "${TAXON_ID}\t${NUM_GENOMES}\t${GC_CONTENT}\t${GC_SKEW}\t${AT_SKEW}\t${COMPLETENESS}" >> "$COMBINED_STATS"

    # Step 3: K-mers (if enabled)
    if $USE_KMER; then
        echo "Running k-mer counting for $TAXON_ID..."
        jellyfish count -m 4 -s 100M -t 8 -C $FASTA -o "$OUTDIR/reads.jf"
        jellyfish dump "$OUTDIR/reads.jf" > "$OUTDIR/kmers.tsv"

        awk -v taxon="$TAXON_ID" '{print taxon"\t"$1"\t"$2}' "$OUTDIR/kmers.tsv" >> "$COMBINED_KMERS"
    fi

    # Step 4: Optional compression
    if $COMPRESS; then
        echo "Compressing outputs for $TAXON_ID..."
        tar -czf "${OUTDIR}.tar.gz" "$OUTDIR"
        rm -rf "$OUTDIR"
    fi

done < "$TAXA_FILE"

echo ">>> Pipeline finished successfully!"
echo ">>> Combined stats: $COMBINED_STATS"
if $USE_KMER; then
    echo ">>> Combined k-mers: $COMBINED_KMERS"
fi

