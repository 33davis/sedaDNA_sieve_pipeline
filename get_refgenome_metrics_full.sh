#!/usr/bin/env bash
# ========================================================
# get_mito_metrics_full.sh
# Safe version: no k-mer, full mitochondrial metrics
# ========================================================

# Usage:
#   ./get_mito_metrics_full.sh <taxid_file> [--compress]

set -euo pipefail

# === Parse arguments ===
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <taxid_file> [--compress]"
    exit 1
fi

TAXID_FILE="$1"
shift
COMPRESS=false
for arg in "$@"; do
    [[ "$arg" == "--compress" ]] && COMPRESS=true
done

# === Output directories ===
OUTDIR="mito_metrics_output"
COMBINED_STATS="$OUTDIR/combined_stats.tsv"
mkdir -p "$OUTDIR"

# Initialize combined stats
echo -e "TaxonID\tNumGenomes\tGC_Content\tGC_Skew\tAT_Skew\tCompleteness" > "$COMBINED_STATS"

# === Main loop over Taxon IDs ===
while read -r TAXID; do
    [[ -z "$TAXID" ]] && continue  # skip empty lines
    TAXON_OUT="$OUTDIR/${TAXID}"
    mkdir -p "$TAXON_OUT"

    echo ">>> Processing Taxon ID: $TAXID"

    # --- Step 1: Download mitochondrial genomes ---
    echo "Downloading mitochondrial genomes for $TAXID..."
    datasets download genome taxon "$TAXID" --assembly-source refseq --filename "$TAXON_OUT/genomes.zip"
    unzip -o "$TAXON_OUT/genomes.zip" -d "$TAXON_OUT"
    FASTA_FILES=($TAXON_OUT/ncbi_dataset/data/*/*.fna)

    if [[ ${#FASTA_FILES[@]} -eq 0 ]]; then
        echo "WARNING: No mitochondrial genomes found for $TAXID"
        continue
    fi

    # --- Step 2: Compute metrics ---
    for FASTA in "${FASTA_FILES[@]}"; do
        SEQ_NAME=$(basename "$FASTA" .fna)
        NUM_SEQS=$(grep -c "^>" "$FASTA")
        GC_CONTENT=$(seqtk comp "$FASTA" | awk '{gc+=($2+$3);total+=($2+$3+$4+$5)} END {if(total>0) print gc/total; else print 0}')
        GC_SKEW=$(seqtk comp "$FASTA" | awk '{gc+=$2;cg+=$3} END {if((gc+cg)>0) print (gc-cg)/(gc+cg); else print 0}')
        AT_SKEW=$(seqtk comp "$FASTA" | awk '{at+=$4;ta+=$5} END {if((at+ta)>0) print (at-ta)/(at+ta); else print 0}')
        COMPLETENESS="$NUM_SEQS"

        # Save per-genome metrics
        echo -e "${TAXID}\t$SEQ_NAME\t$NUM_SEQS\t$GC_CONTENT\t$GC_SKEW\t$AT_SKEW\t$COMPLETENESS" \
            >> "$TAXON_OUT/${TAXID}_metrics.tsv"

        # Append to combined table (aggregated by TaxID)
        echo -e "${TAXID}\t$NUM_SEQS\t$GC_CONTENT\t$GC_SKEW\t$AT_SKEW\t$COMPLETENESS" \
            >> "$COMBINED_STATS"
    done

    # --- Step 3: Optional compression ---
    if $COMPRESS; then
        echo "Compressing outputs for $TAXID..."
        tar -czf "$TAXON_OUT.tar.gz" -C "$OUTDIR" "$TAXID"
        rm -rf "$TAXON_OUT"
    fi

done < "$TAXID_FILE"

echo ">>> Pipeline finished successfully!"
echo ">>> Combined stats file: $COMBINED_STATS"
