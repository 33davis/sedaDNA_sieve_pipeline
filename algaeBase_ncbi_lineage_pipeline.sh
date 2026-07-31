#!/usr/bin/env bash
# =============================================================================
# AlgaeBase → NCBI TaxID + Full Lineage Pipeline
# =============================================================================
# INPUT:  AlgaeBase_Antarctic_SubAnartic_Species_list_clean.csv
#         (output of algaeBase_download_database_cleaning.R;
#          must contain a "scientific_name" column)
#
# OUTPUT: AlgaeBase_to_NCBI_taxa_with_lineage_ids.txt
#         (tab-separated; column-compatible with RAMS_to_NCBI_taxa_with_lineage_ids.txt
#          for downstream bind_rows() in R — see merge snippet at the bottom of this file)
#
# WHAT'S DIFFERENT FROM THE RAMS PIPELINE:
#   RAMS already carried a genbank_id (=taxid), so that pipeline went straight
#   to `taxonkit lineage`. AlgaeBase only gives us a name, so this pipeline
#   adds an extra first step: `taxonkit name2taxid` to resolve
#   scientific_name -> tax_id before doing lineage/reformat.
#
# ALSO FIXED (see database_curation notes): the original reformat call used
#   `-F -R "NA"`. `-F/--fill-miss-rank` *estimates* missing ranks by
#   backfilling from the nearest higher rank, prefixed "unclassified " —
#   that's what produced values like "unclassified cellular organisms
#   superkingdom" for kingdom and "unclassified Polychaeta order" for order.
#   `-R` is --miss-taxid-repl (missing TAXID), not missing rank, so it was a
#   silent no-op. This script drops -F and uses lowercase
#   -r/--miss-rank-repl "NA" instead, so genuinely-missing ranks are left as
#   a plain "NA" rather than a fabricated guess.
#
# REQUIREMENTS (same as RAMS pipeline; skip if already set up):
#   conda install -c bioconda taxonkit
#   wget https://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz
#   tar -zxvf taxdump.tar.gz
#   mkdir -p $HOME/.taxonkit
#   cp names.dmp nodes.dmp delnodes.dmp merged.dmp $HOME/.taxonkit/
# =============================================================================

set -euo pipefail

# ---------- config -----------------------------------------------------------
CSV_IN="AlgaeBase_Antarctic_SubAnartic_Species_list_clean.csv"
OUT_FILE="AlgaeBase_to_NCBI_taxa_with_lineage_ids.txt"
TAXONKIT_DB="${HOME}/.taxonkit"
THREADS=4
# -----------------------------------------------------------------------------

echo "[1/6] Checking dependencies..."
for cmd in taxonkit python3 awk; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' not found. See requirements above."; exit 1; }
done
for f in names.dmp nodes.dmp delnodes.dmp merged.dmp; do
    [[ -f "${TAXONKIT_DB}/${f}" ]] || { echo "ERROR: ${TAXONKIT_DB}/${f} missing. Download taxdump first."; exit 1; }
done
echo "  All dependencies found."

# ---------- step 1: extract unique scientific names from CSV ----------------
echo "[2/6] Extracting unique AlgaeBase scientific names from CSV..."

python3 - <<'PYEOF'
import pandas as pd

df = pd.read_csv("AlgaeBase_Antarctic_SubAnartic_Species_list_clean.csv")

if "scientific_name" not in df.columns:
    raise SystemExit("ERROR: expected a 'scientific_name' column - check the R cleaning script output.")

# keep provenance columns if present, drop rows with no name at all
keep_cols = [c for c in [
    "scientific_name", "species_algaebase", "algaebase_ID",
    "accepted_name", "status_species", "dist", "habitat"
] if c in df.columns]

unique_algae = (
    df[keep_cols]
    .dropna(subset=["scientific_name"])
    .drop_duplicates(subset=["scientific_name"])
    .copy()
)

unique_algae.to_csv("algae_name_mapping.tsv", sep="\t", index=False)

# plain list of names for taxonkit (one per line, no header)
unique_algae["scientific_name"].to_csv("algae_names.txt", index=False, header=False)

print(f"  {len(unique_algae)} unique AlgaeBase scientific names written to algae_names.txt")
PYEOF

# ---------- step 2: resolve scientific name -> NCBI TaxID -------------------
echo "[3/6] Resolving scientific names to NCBI TaxIDs via taxonkit name2taxid..."

# -s = restrict matches to scientific names (skip common/other name types)
# -r = also report the rank of the matched taxid, useful for QC
taxonkit name2taxid \
    --data-dir "${TAXONKIT_DB}" \
    -s -r \
    algae_names.txt \
    > algae_name2taxid_raw.tsv

echo "  Done. $(wc -l < algae_name2taxid_raw.tsv) records returned."

# ---------- step 3: get full lineage for each resolved TaxID ----------------
echo "[4/6] Fetching NCBI scientific names and full lineage via taxonkit lineage..."

# algae_name2taxid_raw.tsv columns: name, tax_id, rank (tax_id/rank blank if unmatched)
# pull just the tax_id column (2nd), drop blanks, dedupe before hitting lineage
awk -F'\t' '$2!="" {print $2}' algae_name2taxid_raw.tsv | sort -u > algae_taxids.txt

taxonkit lineage \
    --data-dir "${TAXONKIT_DB}" \
    --threads "${THREADS}" \
    -n -r \
    algae_taxids.txt \
    > algae_lineage_raw.tsv

echo "  Done. $(wc -l < algae_lineage_raw.tsv) records returned."

# ---------- step 4: reformat lineage into named ranks (no -F guessing) ------
echo "[5/6] Reformatting lineage to fill standard ranks..."

# NOTE: -F intentionally omitted (see header comment above - it fabricates
# "unclassified X <rank>" placeholders). -r (lowercase) sets the replacement
# text for genuinely missing ranks.
taxonkit reformat \
    --data-dir "${TAXONKIT_DB}" \
    --threads "${THREADS}" \
    --taxid-field 1 \
    -i 2 \
    -f "{k}\t{p}\t{c}\t{o}\t{f}\t{g}\t{s}" \
    -r "NA" \
    algae_lineage_raw.tsv \
    > algae_lineage_formatted.tsv

echo "  Done. $(wc -l < algae_lineage_formatted.tsv) records reformatted."

# ---------- step 5: merge everything into final output ----------------------
echo "[6/6] Merging AlgaeBase names, NCBI names, lineage, and ranks..."

python3 - <<'PYEOF'
import pandas as pd

# ---- name -> taxid -> rank map from name2taxid ----
n2t = pd.read_csv(
    "algae_name2taxid_raw.tsv", sep="\t", header=None,
    names=["scientific_name", "tax_id", "name2taxid_rank"], dtype=str
)

# flag names with zero matches
unmatched_names = n2t[n2t["tax_id"].isna() | (n2t["tax_id"] == "")]["scientific_name"]

# flag names with multiple matches (homonyms, e.g. genus shared across kingdoms)
dupe_counts = n2t.dropna(subset=["tax_id"]).groupby("scientific_name")["tax_id"].nunique()
ambiguous_names = dupe_counts[dupe_counts > 1].index.tolist()

matched = n2t[n2t["tax_id"].notna() & (n2t["tax_id"] != "")].copy()

# ---- load raw lineage (tax_id, lineage, ncbi_scientific_name, taxon_rank_ncbi) ----
lin_raw = pd.read_csv(
    "algae_lineage_raw.tsv", sep="\t", header=None,
    names=["tax_id", "lineage", "ncbi_scientific_name", "taxon_rank_ncbi"], dtype=str
)

# ---- load formatted ranks (tax_id, lineage, ncbi_scientific_name, taxon_rank_ncbi, k,p,c,o,f,g,s) ----
lin_fmt = pd.read_csv(
    "algae_lineage_formatted.tsv", sep="\t", header=None,
    names=["tax_id", "lineage", "ncbi_scientific_name", "taxon_rank_ncbi",
           "kingdom", "phylum", "class", "order", "family", "genus", "species"],
    dtype=str
)
lin_fmt = lin_fmt[["tax_id", "kingdom", "phylum", "class", "order", "family", "genus", "species"]]

lin = lin_raw.merge(lin_fmt, on="tax_id", how="left")

# ---- bring in the resolved names, then the lineage ----
result = matched.merge(lin, on="tax_id", how="left")

# ---- bring in original AlgaeBase provenance columns ----
mapping = pd.read_csv("algae_name_mapping.tsv", sep="\t", dtype=str)
result = result.merge(mapping, on="scientific_name", how="left")

# ---- also keep never-matched names in the output frame for completeness ----
never_matched = mapping[mapping["scientific_name"].isin(unmatched_names)].copy()
for col in ["tax_id", "name2taxid_rank", "lineage", "ncbi_scientific_name", "taxon_rank_ncbi",
            "kingdom", "phylum", "class", "order", "family", "genus", "species"]:
    if col not in never_matched.columns:
        never_matched[col] = pd.NA
result = pd.concat([result, never_matched], ignore_index=True)

# ---- rename to match RAMS output's column scheme so the two files can be
#      row-bound; algae has no DarwinCore taxonRank equivalent, so that
#      column is left NA. See merge snippet below for how to combine them. ----
result = result.rename(columns={
    "scientific_name": "algae_scientificName",
})
# status_species holds Species / Variety / Forma / Subspecies - this is
# AlgaeBase's equivalent of RAMS's DarwinCore taxonRank field
result["algae_taxonRank"] = result["status_species"] if "status_species" in result.columns else pd.NA
result["source_database"] = "AlgaeBase"

col_order = [
    "algae_scientificName", "tax_id", "ncbi_scientific_name", "taxon_rank_ncbi",
    "algae_taxonRank", "lineage",
    "kingdom", "phylum", "class", "order", "family", "genus", "species",
    "source_database",
    # extra AlgaeBase provenance, appended (harmless for bind_rows -> becomes NA on RAMS side)
    "species_algaebase", "algaebase_ID", "accepted_name", "dist", "habitat",
]
col_order = [c for c in col_order if c in result.columns]
result = result[col_order]

n_total = len(result)
n_matched = result["ncbi_scientific_name"].notna().sum()
n_missing = result["ncbi_scientific_name"].isna().sum()

result.to_csv("AlgaeBase_to_NCBI_taxa_with_lineage_ids.txt", sep="\t", index=False)

if len(unmatched_names) > 0:
    mapping[mapping["scientific_name"].isin(unmatched_names)].to_csv(
        "AlgaeBase_unmatched_taxa.tsv", sep="\t", index=False
    )

if len(ambiguous_names) > 0:
    n2t[n2t["scientific_name"].isin(ambiguous_names)].to_csv(
        "AlgaeBase_ambiguous_taxa.tsv", sep="\t", index=False
    )

print(f"\n  === Summary ===")
print(f"  Total AlgaeBase names:     {n_total}")
print(f"  Matched to NCBI:           {n_matched}")
print(f"  Unmatched (review these):  {n_missing}")
print(f"  Ambiguous (multiple TaxIDs for one name): {len(ambiguous_names)}")
if len(unmatched_names) > 0:
    print(f"  -> Saved to AlgaeBase_unmatched_taxa.tsv for manual review")
if len(ambiguous_names) > 0:
    print(f"  -> Saved to AlgaeBase_ambiguous_taxa.tsv for manual review")
print(f"\n  Output: AlgaeBase_to_NCBI_taxa_with_lineage_ids.txt")
print(result.head(5).to_string(index=False))
PYEOF

echo ""
echo "Pipeline complete."
echo "  Main output:  AlgaeBase_to_NCBI_taxa_with_lineage_ids.txt"
echo ""
echo "-----------------------------------------------------------------------"
echo " To merge with RAMS_to_NCBI_taxa_with_lineage_ids.txt in R:"
echo ""
echo "   library(dplyr); library(readr)"
echo "   rams  <- read_tsv(\"RAMS_to_NCBI_taxa_with_lineage_ids.txt\") %>%"
echo "              rename(scientificName = rams_scientificName,"
echo "                     taxonRank      = rams_taxonRank) %>%"
echo "              mutate(source_database = \"RAMS\", tax_id = as.character(tax_id))"
echo "   algae <- read_tsv(\"AlgaeBase_to_NCBI_taxa_with_lineage_ids.txt\") %>%"
echo "              rename(scientificName = algae_scientificName,"
echo "                     taxonRank      = algae_taxonRank)"
echo "   so_RAMS_list <- bind_rows(rams, algae)"
echo "-----------------------------------------------------------------------"