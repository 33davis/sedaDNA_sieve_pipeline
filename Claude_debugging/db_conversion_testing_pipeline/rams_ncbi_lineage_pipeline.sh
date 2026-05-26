#!/usr/bin/env bash
# =============================================================================
# RAMS → NCBI Taxonomic Name + Full Lineage Pipeline
# =============================================================================
# INPUT:  RAMSncbi_speciesNsub_leftjoinLocalityexport.csv
#         (columns: scientificName, taxonRank, locality, occurrenceStatus, genbank_id)
#
# OUTPUT: RAMS_to_NCBI_taxa_with_lineage_ids.txt
#         (tab-separated; ready to drop into database_curation.Rmd as so_RAMS_list)
#
# COLUMNS in output (matching what Rmd expects via clean_SO_RAMS_list[,2]):
#   rams_scientificName | tax_id | ncbi_scientific_name | taxon_rank_ncbi |
#   lineage | lineage_ids | lineage_ranks |
#   kingdom | phylum | class | order | family | genus | species
#
# REQUIREMENTS (install once):
#   conda install -c bioconda taxonkit          # or: brew install taxonkit
#   python3 with pandas (conda install pandas)  # for the Python processing steps
#   wget https://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz
#   tar -zxvf taxdump.tar.gz
#   mkdir -p $HOME/.taxonkit
#   cp names.dmp nodes.dmp delnodes.dmp merged.dmp $HOME/.taxonkit/
# =============================================================================

set -euo pipefail

# ---------- config -----------------------------------------------------------
CSV_IN="RAMSncbi_speciesNsub_leftjoinLocalityexport.csv"
OUT_FILE="RAMS_to_NCBI_taxa_with_lineage_ids.txt"
TAXONKIT_DB="${HOME}/.taxonkit"          # path where taxdump files live
THREADS=4                                # parallel taxonkit threads
# -----------------------------------------------------------------------------

echo "[1/5] Checking dependencies..."
for cmd in taxonkit python3 awk; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' not found. See requirements above."; exit 1; }
done
for f in names.dmp nodes.dmp delnodes.dmp merged.dmp; do
    [[ -f "${TAXONKIT_DB}/${f}" ]] || { echo "ERROR: ${TAXONKIT_DB}/${f} missing. Download taxdump first."; exit 1; }
done
echo "  All dependencies found."

# ---------- step 1: extract unique taxon IDs from CSV -----------------------
echo "[2/5] Extracting unique NCBI taxon IDs from CSV..."

python3 - <<'PYEOF'
import pandas as pd, sys

df = pd.read_csv("RAMSncbi_speciesNsub_leftjoinLocalityexport.csv")

# keep one row per (scientificName, genbank_id) combination
unique_taxa = (
    df[["scientificName", "taxonRank", "genbank_id"]]
    .drop_duplicates(subset=["scientificName", "genbank_id"])
    .dropna(subset=["genbank_id"])
    .copy()
)
unique_taxa["genbank_id"] = unique_taxa["genbank_id"].astype(int).astype(str)

# save the mapping file (we'll join back later)
unique_taxa.to_csv("rams_taxid_mapping.tsv", sep="\t", index=False)

# save just the taxon IDs for taxonkit
unique_taxa["genbank_id"].drop_duplicates().to_csv(
    "rams_taxids.txt", index=False, header=False
)

print(f"  {len(unique_taxa)} unique RAMS taxa written to rams_taxids.txt")
print(f"  taxonRank breakdown: {unique_taxa.taxonRank.value_counts().to_dict()}")
PYEOF

# ---------- step 2: get NCBI canonical name + rank for each TaxID -----------
echo "[3/5] Fetching NCBI scientific names and ranks via taxonkit..."

# taxonkit lineage: outputs  taxid<TAB>lineage_names
# -n = include scientific name column
# -r = include rank column  
# --data-dir overrides default ~/.taxonkit path (explicit is safer)
taxonkit lineage \
    --data-dir "${TAXONKIT_DB}" \
    --threads "${THREADS}" \
    -n -r \
    rams_taxids.txt \
    > rams_lineage_raw.tsv

echo "  Done. $(wc -l < rams_lineage_raw.tsv) records returned."

# ---------- step 3: reformat lineage into named ranks -----------------------
echo "[4/5] Reformatting lineage to fill standard ranks..."

# taxonkit reformat: parses the lineage string into fixed-rank columns
# -f sets the output format template
# -F fills missing ranks with empty string (not "no rank")
# --data-dir keeps taxdump consistent
#
# Column order from taxonkit lineage -n -r:
#   1:taxid  2:lineage  3:lineage_taxids  4:rank  5:name
#
# We pass col 1 (taxid) to reformat2 which reads lineage from stdin context.
# Easiest: pipe the whole lineage output; reformat reads taxid + lineage.

taxonkit reformat \
    --data-dir "${TAXONKIT_DB}" \
    --threads "${THREADS}" \
    --taxid-field 1 \
    -i 2 \
    -f "{k}\t{p}\t{c}\t{o}\t{f}\t{g}\t{s}" \
    -F \
    -R "NA" \
    rams_lineage_raw.tsv \
    > rams_lineage_formatted.tsv

echo "  Done. $(wc -l < rams_lineage_formatted.tsv) records reformatted."

# ---------- step 4: merge everything into final output ----------------------
echo "[5/5] Merging RAMS names, NCBI names, lineage, and ranks..."

python3 - <<'PYEOF'
import pandas as pd

# ---- load the raw lineage file (taxid, lineage_str, lineage_ids, rank, ncbi_name)
lin_raw = pd.read_csv(
    "rams_lineage_raw.tsv", sep="\t",
    header=None,
    names=["tax_id", "lineage", "lineage_ids", "taxon_rank_ncbi", "ncbi_scientific_name"],
    dtype=str
)

# ---- load the formatted ranks file (taxid, lineage_str, ..., k, p, c, o, f, g, s)
lin_fmt = pd.read_csv(
    "rams_lineage_formatted.tsv", sep="\t",
    header=None,
    names=["tax_id", "lineage", "lineage_ids", "taxon_rank_ncbi", "ncbi_scientific_name",
           "kingdom", "phylum", "class", "order", "family", "genus", "species"],
    dtype=str
)
lin_fmt = lin_fmt[["tax_id", "kingdom", "phylum", "class", "order", "family", "genus", "species"]]

# ---- merge the two lineage tables
lin = lin_raw.merge(lin_fmt, on="tax_id", how="left")

# ---- load the original RAMS mapping
rams = pd.read_csv("rams_taxid_mapping.tsv", sep="\t", dtype={"genbank_id": str})
rams = rams.rename(columns={
    "scientificName": "rams_scientificName",
    "taxonRank": "rams_taxonRank",
    "genbank_id": "tax_id"
})

# ---- join RAMS onto lineage (left join keeps all RAMS taxa)
result = rams.merge(lin, on="tax_id", how="left")

# ---- column order that matches what the Rmd expects
# Rmd does: so_genomes <- clean_SO_RAMS_list[,2] → expects tax_id in column 2
col_order = [
    "rams_scientificName",   # col 1  – original RAMS name
    "tax_id",                # col 2  – used by Rmd whitelist filter
    "ncbi_scientific_name",  # col 3
    "taxon_rank_ncbi",       # col 4
    "rams_taxonRank",        # col 5  – Species / Subspecies from DarwinCore
    "lineage",               # col 6
    "lineage_ids",           # col 7
    "kingdom", "phylum", "class", "order", "family", "genus", "species"
]
result = result[col_order]

# ---- diagnostics
n_total   = len(result)
n_matched = result["ncbi_scientific_name"].notna().sum()
n_missing = result["ncbi_scientific_name"].isna().sum()

result.to_csv("RAMS_to_NCBI_taxa_with_lineage_ids.txt", sep="\t", index=False)

print(f"\n  === Summary ===")
print(f"  Total RAMS taxa:          {n_total}")
print(f"  Matched to NCBI:          {n_matched}")
print(f"  Unmatched (review these): {n_missing}")
if n_missing > 0:
    unmatched = result[result["ncbi_scientific_name"].isna()][["rams_scientificName","tax_id","rams_taxonRank"]]
    unmatched.to_csv("RAMS_unmatched_taxa.tsv", sep="\t", index=False)
    print(f"  → Saved to RAMS_unmatched_taxa.tsv for manual review")
print(f"\n  Output: RAMS_to_NCBI_taxa_with_lineage_ids.txt")
print(result.head(5).to_string(index=False))
PYEOF

echo ""
echo "Pipeline complete."
echo "  Main output:  RAMS_to_NCBI_taxa_with_lineage_ids.txt"
echo "  (update the path in your Rmd so_RAMS_list read_delim call)"
