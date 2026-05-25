#!/usr/bin/bash -l
# ==============================================================================
# get_mito_metrics_full.sh
# ==============================================================================
# Description:
#   Download all mitochondrial genomes for TaxIDs listed in input file,
#   compute GC content, GC skew, AT skew, completeness,
#   optionally compress output, and produce per-taxon & combined summaries.
#
# Usage:
#   ./get_mito_metrics_full.sh taxa_ids.txt [--compress]
#
# Requirements:
#   - conda env with: entrez-direct, seqkit, pigz, coreutils, bioawk
# ==============================================================================

set -euo pipefail

# --- Parse input arguments ---
TAXID_FILE="$1"
COMPRESS=false
if [[ "${2:-}" == "--compress" ]]; then
    COMPRESS=true
fi

OUTDIR="mito_metrics_output"
mkdir -p "$OUTDIR"

COMBINED_REPORT="$OUTDIR/combined_metrics.tsv"
echo -e "TaxID\tNum_Genomes\tTotal_Sequences\tGC_Content\tGC_Skew\tAT_Skew" > "$COMBINED_REPORT"

# --- Loop through TaxIDs ---
while read -r TAXID; do
    [[ -z "$TAXID" ]] && continue  # skip empty lines

    TAXON_OUT="$OUTDIR/$TAXID"
    mkdir -p "$TAXON_OUT"
    echo ">>> Processing Taxon ID: $TAXID"

    # --- Step 1: Download mitochondrial genomes only using entrez-direct ---
    echo "Downloading mitochondrial genomes for $TAXID..."
    esearch -db nucleotide -query "txid${TAXID}[Organism:exp] AND mitochondrion[Filter] AND refseq[filter]" \
        | efetch -format fasta > "$TAXON_OUT/mitogenomes.fasta"

    if [[ ! -s "$TAXON_OUT/mitogenomes.fasta" ]]; then
        echo "Warning: No mitochondrial genomes found for TaxID $TAXID"
        continue
    fi

    # --- Step 2: Compute metrics using seqkit ---
    FASTA="$TAXON_OUT/mitogenomes.fasta"
    NUM_GENOMES=$(grep -c "^>" "$FASTA")
    GC_CONTENT=$(seqkit fx2tab -n -g "$FASTA" | awk '{gc=($2+$3); total=($2+$3+$4+$5); if(total>0) sum+=gc/total} END{if(NR>0) print sum/NR; else print 0}')
    GC_SKEW=$(seqkit fx2tab -n -g "$FASTA" | awk '{gc=$2-$3; at=$4-$5; if(($2+$3)>0) sum_gc+=gc/($2+$3); if(($4+$5)>0) sum_at+=at/($4+$5)} END{print sum_gc/NR, sum_at/NR}' | awk '{print $1}')
    AT_SKEW=$(seqkit fx2tab -n -g "$FASTA" | awk '{gc=$2-$3; at=$4-$5; if(($2+$3)>0) sum_gc+=gc/($2+$3); if(($4+$5)>0) sum_at+=at/($4+$5)} END{print sum_at/NR}')

    # --- Step 3: Save per-taxon report ---
    echo -e "$TAXID\t$NUM_GENOMES\t$NUM_GENOMES\t$GC_CONTENT\t$GC_SKEW\t$AT_SKEW" \
        > "$TAXON_OUT/metrics.tsv"

    # --- Step 4: Update combined report ---
    echo -e "$TAXID\t$NUM_GENOMES\t$NUM_GENOMES\t$GC_CONTENT\t$GC_SKEW\t$AT_SKEW" >> "$COMBINED_REPORT"

    # --- Step 5: Optional compression ---
    if [[ "$COMPRESS" == true ]]; then
        pigz -f "$FASTA"
        pigz -f "$TAXON_OUT/metrics.tsv"
    fi

done < "$TAXID_FILE"

echo ">>> Pipeline finished. Combined metrics: $COMBINED_REPORT"

