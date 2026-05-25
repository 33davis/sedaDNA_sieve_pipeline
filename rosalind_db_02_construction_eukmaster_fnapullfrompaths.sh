#!/usr/bin/bash -l
#PBS -N rosalind_constructiondb_eukmaster_02
#PBS -M emily.davis@utas.edu.au
#PBS -m abe
#PBS -l select=1:ncpus=4:mem=16G
#PBS -l walltime=24:00:00

## BEGIN SCRIPT

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


# --- paths ---
base_dir="/u/davisee/Refseq_2026/master_curated_accessions"
cd "$base_dir"

urls="assembly_fasta_urls.tsv"        # from step 1
out="all_euks.fna"
manifest="stream_manifest.tsv"
failed="stream_failed.tsv"
log="stream_merge.log"

[[ -s "$urls" ]] || { echo "ERROR: missing $urls"; exit 1; }

# --- resume-friendly prep ---
: > "$log"                             # truncate logs each run
touch "$manifest" "$failed"            # create if absent

# Build a set of already processed accessions (for resume)
# Manifest format we’ll write: acc \t url \t status \t bytes_appended
awk -F'\t' '$3=="OK"{print $1}' "$manifest" | sort -u > .done_acc.list || true

# Start output file if not exists; do not auto-truncate on resume
if [[ ! -f "$out" ]]; then
  : > "$out"
fi

# --- process loop ---
# Notes: 
#  - Use --fail to make curl non-zero on HTTP >= 400.
#  - Use -S for verbose errors, -s for silent progress.
#  - Append per-accession marker to keep provenance inside the FASTA.
while IFS=$'\t' read -r acc url; do
  # Skip already done accessions
  if grep -qx "$acc" .done_acc.list 2>/dev/null; then
    echo "[RESUME] Skipping $acc (already in manifest OK)" | tee -a "$log"
    continue
  fi

  echo "[GET] $acc  $url" | tee -a "$log"

  before=$(stat -c%s "$out" 2>/dev/null || echo 0)

  # Append a provenance comment (starts with >? keep as a FASTA header separator)
  # We’ll add a FASTA header-like comment line, but not a sequence. 
  # If you prefer real FASTA comment lines, you can use "; " or just keep this as-is.
  echo "### $acc" >> "$out"

  if curl --fail -S -sL "$url" | gzip -dc >> "$out"; then
    after=$(stat -c%s "$out")
    bytes=$(( after - before ))
    printf "%s\t%s\tOK\t%d\n" "$acc" "$url" "$bytes" >> "$manifest"
    echo "[OK]  $acc  +${bytes} bytes" | tee -a "$log"
    echo "$acc" >> .done_acc.list
  else
    printf "%s\t%s\tFAIL\n" "$acc" "$url" >> "$failed"
    echo "[FAIL] $acc" | tee -a "$log"
    # remove the trailing provenance marker if nothing actually appended
    # (only if the last line starts with ### and no bytes were added)
    tail -n 1 "$out" | grep -q '^### '"$acc"'$' && sed -i '$ d' "$out" || true
  fi

done < "$urls"

# Deduplicate done list for neatness
sort -u -o .done_acc.list .done_acc.list

echo "========== SUMMARY =========="
echo "Output FASTA: $out  (size: $(stat -c%s "$out") bytes)"
echo "Manifest:     $manifest  (OK count: $(awk -F'\t' '$3=="OK"' "$manifest" | wc -l))"
echo "Failed:       $failed    (FAIL count: $(wc -l < "$failed"))"
date
