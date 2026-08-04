# RAMS → NCBI Taxonomic Lineage Pipeline
## Purpose
Takes your `RAMSncbi_speciesNsub_leftjoinLocalityexport.csv` (RAMS taxa with `genbank_id` already mapped) and produces a fully-annotated lineage file ready to load as `so_RAMS_list` in `database_curation.Rmd`.

---

## Output file: `RAMS_to_NCBI_taxa_with_lineage_ids.txt`

| Column | Source | Notes |
|--------|--------|-------|
| `rams_scientificName` | RAMS CSV | original DarwinCore name |
| `tax_id` | RAMS CSV `genbank_id` | **column 2 – what the Rmd uses** |
| `ncbi_scientific_name` | NCBI taxdump | canonical accepted name |
| `taxon_rank_ncbi` | NCBI nodes.dmp | e.g. species, subspecies |
| `rams_taxonRank` | RAMS CSV | Species / Subspecies |
| `lineage` | NCBI | semicolon-delimited names, root→taxon |
| `lineage_ids` | NCBI | semicolon-delimited TaxIDs, root→taxon |
| `kingdom` … `species` | NCBI | standard rank columns |

The Rmd line `so_genomes <- clean_SO_RAMS_list[,2]` picks up `tax_id` as expected.

---

## Option A — TaxonKit pipeline (recommended, fastest)

### One-time setup

```bash
# 1. Install TaxonKit (pick one)
conda install -c bioconda taxonkit
# or:  brew install taxonkit

# 2. Download NCBI taxdump (~60 MB compressed)
wget https://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz
tar -zxvf taxdump.tar.gz

# 3. Put the dump where TaxonKit expects it
mkdir -p $HOME/.taxonkit
cp names.dmp nodes.dmp delnodes.dmp merged.dmp $HOME/.taxonkit/
```

### Run

```bash
# put the shell script and the CSV in the same directory, then:
chmod +x rams_ncbi_lineage_pipeline.sh
./rams_ncbi_lineage_pipeline.sh
```

That's it. The script:
1. 
2. Extracts all unique `genbank_id` values → `rams_taxids.txt`
3. Calls `taxonkit lineage -n -r` → canonical name + rank per TaxID
4. Calls `taxonkit reformat` → populates kingdom/phylum/.../species columns
5. Merges everything back onto the RAMS table and writes the output TSV

---

## Option B — Pure Python fallback (no TaxonKit needed)

Requires Python ≥ 3.10 + pandas. Works on Windows/HPC without conda.

```bash
pip install pandas

# taxdump still needed (same wget/tar steps above)
python3 rams_ncbi_lineage_python.py

# custom paths:
python3 rams_ncbi_lineage_python.py \
    --csv  /path/to/RAMSncbi_speciesNsub_leftjoinLocalityexport.csv \
    --taxdump /path/to/taxdump/dir \
    --out  RAMS_to_NCBI_taxa_with_lineage_ids.txt
```

---

## Rmd update

Replace the current `read_delim` path in `database_curation.Rmd`:

```r
so_RAMS_list <- read_delim(
  "RAMS_to_NCBI_taxa_with_lineage_ids.txt",   # ← update this path
  delim = "\t", escape_double = FALSE, trim_ws = TRUE
)
clean_SO_RAMS_list <- so_RAMS_list %>%
  filter(!is.na(tax_id))
so_genomes <- clean_SO_RAMS_list[, 2]         # tax_id column
colnames(so_genomes) <- c("tax_id")
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| TaxID not found in taxdump | TaxID may be deprecated → check `RAMS_unmatched_taxa.tsv`; look up ID in `merged.dmp` |
| `ncbi_scientific_name` is NA for some rows | TaxID valid but name resolution failed; try `taxonkit name2taxid` on the species name as cross-check |
| Subspecies lineage missing species rank | Expected for some NCBI entries; `species` column will still be populated from parent node |
| taxdump files not found | Confirm `names.dmp` is in `~/.taxonkit/`; pass `--data-dir /your/path` to taxonkit |
