#!/usr/bin/env python3
"""
rams_ncbi_lineage_python.py
============================
Pure-Python fallback for the RAMS → NCBI lineage pipeline.
Use this if TaxonKit is unavailable (e.g., on a Windows machine or
restricted HPC without conda).

INPUT:
    RAMSncbi_speciesNsub_leftjoinLocalityexport.csv
    $HOME/.taxonkit/names.dmp
    $HOME/.taxonkit/nodes.dmp
    $HOME/.taxonkit/merged.dmp   (optional – handles deprecated TaxIDs)

OUTPUT:
    RAMS_to_NCBI_taxa_with_lineage_ids.txt   (same schema as shell pipeline)
    RAMS_unmatched_taxa.tsv                  (TaxIDs taxdump could not resolve)

USAGE:
    python3 rams_ncbi_lineage_python.py
    python3 rams_ncbi_lineage_python.py --taxdump /path/to/taxdump/dir
"""

import argparse
import os
import sys
import pandas as pd
from pathlib import Path
from collections import defaultdict

# ---------------------------------------------------------------------------
STANDARD_RANKS = ["superkingdom", "kingdom", "phylum", "class",
                  "order", "family", "genus", "species", "subspecies"]
RANK_ALIASES = {          # map NCBI rank names → our column names
    "superkingdom": "kingdom",
    "kingdom": "kingdom",
    "phylum": "phylum",
    "class": "class",
    "order": "order",
    "family": "family",
    "genus": "genus",
    "species": "species",
    "subspecies": "species",   # subspecies goes under 'species' column
}
OUTPUT_COLS = ["kingdom", "phylum", "class", "order", "family", "genus", "species"]
# ---------------------------------------------------------------------------


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--csv", default="RAMSncbi_speciesNsub_leftjoinLocalityexport.csv")
    p.add_argument("--taxdump", default=str(Path.home() / ".taxonkit"),
                   help="Directory containing names.dmp, nodes.dmp, merged.dmp")
    p.add_argument("--out", default="RAMS_to_NCBI_taxa_with_lineage_ids.txt")
    return p.parse_args()


def load_merged(taxdump_dir: str) -> dict:
    """Returns dict of old_taxid → new_taxid for deprecated IDs."""
    merged = {}
    path = Path(taxdump_dir) / "merged.dmp"
    if not path.exists():
        return merged
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 2:
                merged[parts[0]] = parts[1]
    return merged


def load_nodes(taxdump_dir: str) -> tuple[dict, dict]:
    """Returns (parent_map, rank_map): taxid → parent_taxid, taxid → rank."""
    parent_map, rank_map = {}, {}
    with open(Path(taxdump_dir) / "nodes.dmp", encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 3:
                tid, parent, rank = parts[0], parts[1], parts[2]
                parent_map[tid] = parent
                rank_map[tid] = rank
    return parent_map, rank_map


def load_names(taxdump_dir: str) -> dict:
    """Returns taxid → scientific name."""
    sci_names = {}
    with open(Path(taxdump_dir) / "names.dmp", encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 4 and parts[3] == "scientific name":
                sci_names[parts[0]] = parts[1]
    return sci_names


def build_lineage(taxid: str, parent_map: dict, rank_map: dict,
                  sci_names: dict, merged_map: dict) -> dict:
    """
    Walk up the taxonomy tree for `taxid`.
    Returns a dict with keys: lineage, lineage_ids, taxon_rank_ncbi,
    ncbi_scientific_name, kingdom, phylum, class, order, family, genus, species
    """
    # resolve deprecated IDs
    taxid = merged_map.get(taxid, taxid)

    if taxid not in parent_map:
        return {"ncbi_scientific_name": None, "taxon_rank_ncbi": None,
                "lineage": None, "lineage_ids": None,
                **{c: None for c in OUTPUT_COLS}}

    ncbi_name = sci_names.get(taxid)
    ncbi_rank = rank_map.get(taxid)

    # walk tree
    path_ids, path_names, path_ranks = [], [], []
    current = taxid
    visited = set()
    while current not in visited and current != "1":
        visited.add(current)
        name = sci_names.get(current, "")
        rank = rank_map.get(current, "no rank")
        path_ids.append(current)
        path_names.append(name)
        path_ranks.append(rank)
        current = parent_map.get(current, "1")

    # reverse so root is first
    path_ids.reverse()
    path_names.reverse()
    path_ranks.reverse()

    lineage_str  = ";".join(path_names)
    lineage_ids  = ";".join(path_ids)

    # fill standard rank columns
    rank_cols = {c: None for c in OUTPUT_COLS}
    for pid, pname, prank in zip(path_ids, path_names, path_ranks):
        col = RANK_ALIASES.get(prank)
        if col:
            rank_cols[col] = pname

    return {
        "ncbi_scientific_name": ncbi_name,
        "taxon_rank_ncbi": ncbi_rank,
        "lineage": lineage_str,
        "lineage_ids": lineage_ids,
        **rank_cols,
    }


def main():
    args = parse_args()

    # ── validate inputs ──────────────────────────────────────────────────────
    for fname in ["names.dmp", "nodes.dmp"]:
        p = Path(args.taxdump) / fname
        if not p.exists():
            sys.exit(f"ERROR: {p} not found.\n"
                     "Download taxdump.tar.gz from:\n"
                     "  https://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz\n"
                     "Then: tar -zxvf taxdump.tar.gz && mkdir -p ~/.taxonkit\n"
                     "      cp names.dmp nodes.dmp delnodes.dmp merged.dmp ~/.taxonkit/")

    # ── load taxonomy ─────────────────────────────────────────────────────────
    print("[1/4] Loading NCBI taxonomy (this takes ~30–60 s on first run)...")
    merged_map  = load_merged(args.taxdump)
    parent_map, rank_map = load_nodes(args.taxdump)
    sci_names   = load_names(args.taxdump)
    print(f"  Loaded {len(sci_names):,} scientific names, "
          f"{len(parent_map):,} nodes, {len(merged_map):,} merged IDs.")

    # ── load RAMS CSV ─────────────────────────────────────────────────────────
    print("[2/4] Loading RAMS CSV...")
    df = pd.read_csv(args.csv)
    unique_taxa = (
        df[["scientificName", "taxonRank", "genbank_id"]]
        .drop_duplicates(subset=["scientificName", "genbank_id"])
        .dropna(subset=["genbank_id"])
        .copy()
    )
    unique_taxa["genbank_id"] = unique_taxa["genbank_id"].astype(int).astype(str)
    print(f"  {len(unique_taxa)} unique RAMS taxa to process.")

    # ── build lineage for every taxID ────────────────────────────────────────
    print("[3/4] Building lineage for each TaxID...")
    records = []
    for _, row in unique_taxa.iterrows():
        lin = build_lineage(row["genbank_id"], parent_map, rank_map,
                            sci_names, merged_map)
        records.append({
            "rams_scientificName": row["scientificName"],
            "tax_id":              row["genbank_id"],
            "rams_taxonRank":      row["taxonRank"],
            **lin,
        })
    result = pd.DataFrame(records)

    # ── reorder to match Rmd expectations (tax_id in column 2) ───────────────
    col_order = [
        "rams_scientificName",
        "tax_id",
        "ncbi_scientific_name",
        "taxon_rank_ncbi",
        "rams_taxonRank",
        "lineage",
        "lineage_ids",
        "kingdom", "phylum", "class", "order", "family", "genus", "species",
    ]
    result = result[col_order]

    # ── save ──────────────────────────────────────────────────────────────────
    print("[4/4] Saving output...")
    result.to_csv(args.out, sep="\t", index=False)

    n_matched = result["ncbi_scientific_name"].notna().sum()
    n_missing = result["ncbi_scientific_name"].isna().sum()
    print(f"\n  === Summary ===")
    print(f"  Total RAMS taxa:          {len(result)}")
    print(f"  Matched to NCBI:          {n_matched}")
    print(f"  Unmatched (review these): {n_missing}")
    if n_missing > 0:
        unmatched_path = Path(args.out).stem + "_unmatched.tsv"
        result[result["ncbi_scientific_name"].isna()][
            ["rams_scientificName", "tax_id", "rams_taxonRank"]
        ].to_csv(unmatched_path, sep="\t", index=False)
        print(f"  → Unmatched saved to: {unmatched_path}")

    print(f"\n  Output:  {args.out}")
    print(result.head(5).to_string(index=False))
    print("\nDone.")


if __name__ == "__main__":
    main()
