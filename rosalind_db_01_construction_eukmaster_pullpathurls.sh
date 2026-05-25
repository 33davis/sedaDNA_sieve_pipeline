#!/usr/bin/bash -l
#PBS -N rosalind_constructiondb_eukmaster_01
#PBS -M emily.davis@utas.edu.au
#PBS -m abe
#PBS -l select=1:ncpus=2:mem=10G
#PBS -l walltime=10:00:00

set -euo pipefail

echo "========== ENV =========="
date
echo "Host: $(hostname)"
echo "JobID: ${PBS_JOBID:-unset}"
echo "Workdir at submit: ${PBS_O_WORKDIR:-unset}"

# -------- Conda environment ----------
# Prefer the modern activation method; avoids surprises on PBS
module load Anaconda3/2024.02-1 || true
source activate /u/davisee/.conda/envs/db_mito_mining_building || {
  echo "ERROR: could not activate conda env"; exit 1; }

# Sanity: confirm EDirect is in PATH *inside the job*
command -v esearch >/dev/null || { echo "ERROR: edirect (esearch) not found in PATH"; exit 2; }

# -------- Paths ----------
base_dir="/u/davisee/Refseq_2026/master_curated_accessions"
input="assembly_accessions_nocontig.txt"   # <-- fixed spelling
paths="dbassembly_paths.tsv"
output="assembly_fasta_urls.tsv"
missing="missing_paths.log"

cd "$base_dir"

echo "Input file: $PWD/$input"
[[ -s "$input" ]] || { echo "ERROR: input file missing or empty: $input"; exit 3; }

# -------- Resolve RefSeq/GenBank paths for *all* curated accessions ----------
# EDirect keeps every accession; we do NOT filter here.
epost -db assembly -format acc < "$input" \
  | esummary \
  | xtract -pattern DocumentSummary \
           -element AssemblyAccession,FtpPath_RefSeq,FtpPath_GenBank \
  > "$paths"

# Optional: quick sanity check
echo "Wrote $(wc -l < "$paths") lines to $paths"

# -------- Build download URLs (prefer RefSeq, fallback to GenBank) ----------
rm -f "$missing"  # start fresh
awk -F '\t' '
BEGIN {OFS="\t"}
{
  acc=$1; rs=$2; gb=$3;

  # Prefer RefSeq if present; else GenBank
  if (rs != "" && rs != "-")      base = rs;
  else if (gb != "" && gb != "-") base = gb;
  else {
     print acc "\tNO_FTP_PATH" >> "'"$missing"'";
     next;
  }

  # Build *_genomic.fna.gz URL
  n = split(base, arr, "/");
  asm_name = arr[n];
  print acc, base "/" asm_name "_genomic.fna.gz";
}
' "$paths" > "$output"

echo "Done. URL table: $output"
[[ -f "$missing" ]] && echo "Note: some accessions lacked FTP paths. See $missing (if non-empty)."

date
echo "========== DONE =========="

