#!/usr/bin/env python3

import os
import sys
import argparse
from pathlib import Path
import gzip
import shutil
import time
import random
from Bio import SeqIO, Entrez
import pandas as pd

# --- Setup Entrez ---
Entrez.email = "emily.davis@utas.edu.au"  # Change to your email
Entrez.api_key = "001c90f50ff94f323e68b7ab1e549f36ef09"
# Delay between requests to avoid NCBI throttling
ENTREZ_DELAY = 0.2

def fetch_species_from_taxid(taxid):
    """Fetch all species taxids under a given higher-level taxid."""
    handle = Entrez.esearch(db="taxonomy", term=f"txid{taxid}[Subtree] AND species[Rank]", retmax=10000)
    record = Entrez.read(handle)
    handle.close()
    return record["IdList"]

def fetch_mito_genomes(taxid, outdir, max_retries=5):
    """Fetch mitochondrial genomes for a given species taxid."""
    fasta_files = []
    attempt = 0

    while attempt < max_retries:
        try:
            handle = Entrez.esearch(
                db="nucleotide",
                term=f"txid{taxid}[Organism:exp] AND mitochondrion[filter]",
                rettype="fasta",
                retmode="text",
                retmax=5000
            )
            record = Entrez.read(handle)
            handle.close()

            ids = record.get("IdList", [])
            if not ids:
                return []

            for seq_id in ids:
                try:
                    fasta_handle = Entrez.efetch(db="nucleotide", id=seq_id,
                                                 rettype="fasta", retmode="text")
                    fasta = fasta_handle.read()
                    fasta_handle.close()

                    outfile = outdir / f"{taxid}_{seq_id}.fna"
                    with open(outfile, "w") as f:
                        f.write(fasta)
                    fasta_files.append(outfile)

                except Exception as e:
                    print(f"--- ERROR fetching {seq_id} for taxid {taxid}: {e}")
                    continue
            return fasta_files

        except Exception as e:
            attempt += 1
            wait_time = (2 ** attempt) + random.random()  # exponential backoff
            print(f"!!! NCBI fetch error for taxid {taxid} (attempt {attempt}/{max_retries}): {e}")
            print(f"    Waiting {wait_time:.1f}s before retry...")
            time.sleep(wait_time)

    print(f"!!! Skipping taxid {taxid} after {max_retries} failed attempts")
    return []

    # Fetch sequences in FASTA
    for seq_id in ids:
        out_fasta = outdir / f"{seq_id}.fna"
        with Entrez.efetch(db="nucleotide", id=seq_id, rettype="fasta", retmode="text") as handle:
            seq_data = handle.read()
        with open(out_fasta, "w") as f:
            f.write(seq_data)
        fasta_files.append(out_fasta)

    return fasta_files

def merge_fastas(fasta_files, merged_fasta):
    """Merge multiple fasta files into one combined fasta."""
    with open(merged_fasta, "w") as out_f:
        for f in fasta_files:
            for record in SeqIO.parse(str(f), "fasta"):
                SeqIO.write(record, out_f, "fasta")

def compute_metrics(fasta_file):
    """Compute GC content, GC skew, AT skew, completeness metrics."""
    total_len = 0
    gc_count = 0
    g_count = 0
    c_count = 0
    a_count = 0
    t_count = 0
    num_seqs = 0

    for record in SeqIO.parse(str(fasta_file), "fasta"):
        seq = str(record.seq).upper()
        num_seqs += 1
        total_len += len(seq)
        g_count += seq.count("G")
        c_count += seq.count("C")
        a_count += seq.count("A")
        t_count += seq.count("T")

    if total_len == 0:
        return dict(GC=0, GC_skew=0, AT_skew=0, Completeness=0, NumSeqs=0, Length=0)

    gc_content = (g_count + c_count) / total_len
    gc_skew = (g_count - c_count) / (g_count + c_count + 1e-9)
    at_skew = (a_count - t_count) / (a_count + t_count + 1e-9)
    completeness = 1.0 if num_seqs > 0 else 0.0

    return dict(
        GC=gc_content,
        GC_skew=gc_skew,
        AT_skew=at_skew,
        Completeness=completeness,
        NumSeqs=num_seqs,
        Length=total_len
    )

def main():
    parser = argparse.ArgumentParser(description="Run mito metrics pipeline with a taxid list.")
    parser.add_argument("--taxid-file", required=True, help="Path to taxa ID file.")
    parser.add_argument("--outdir", default=".", help="Output directory (default: current dir).")
    parser.add_argument("--compress", action="store_true", help="Compress results.")
    args = parser.parse_args()

    taxids = [line.strip() for line in open(args.taxid_file) if line.strip()]
    outdir = Path(args.outdir)
    outdir.mkdir(exist_ok=True)

    all_results = []
    skipped_species = {}  # Keep track of species without FASTAs

    for taxid in taxids:
        print(f"\n>>> Processing TaxID: {taxid}")
        taxon_dir = outdir / taxid
        taxon_dir.mkdir(parents=True, exist_ok=True)

        # Expand higher-level taxon to species
        species_taxids = fetch_species_from_taxid(taxid)
        print(f">>> Found {len(species_taxids)} species taxids under TaxID {taxid}")

        fasta_files_all = []

        for sp_taxid in species_taxids:
            print(f">>> Fetching mitochondrial genomes for species TaxID {sp_taxid}...")
            fasta_files = fetch_mito_genomes(sp_taxid, taxon_dir)
            if not fasta_files:
                print(f"--- No mitogenomes found for species TaxID {sp_taxid}, skipping")
                skipped_species[sp_taxid] = "No FASTAs"
                continue
            print(f">>> Downloaded {len(fasta_files)} FASTA(s) for species TaxID {sp_taxid}")
            fasta_files_all.extend(fasta_files)
            import time; time.sleep(0.2)

        print(f">>> Total FASTAs collected for TaxID {taxid}: {len(fasta_files_all)}")

        if not fasta_files_all:
            print(f"WARNING: No mitochondrial FASTAs found for TaxID {taxid}, skipping metrics/compression")
            continue

        merged_fasta = taxon_dir / f"{taxid}_mitogenomes.fna"
        try:
            merge_fastas(fasta_files_all, merged_fasta)
            print(f">>> Merged FASTAs into {merged_fasta}")
        except Exception as e:
            print(f"ERROR merging FASTAs for TaxID {taxid}: {e}")
            continue

        if merged_fasta.exists():
            try:
                metrics = compute_metrics(merged_fasta)
                metrics["TaxID"] = taxid
                all_results.append(metrics)
                print(f">>> Metrics computed for TaxID {taxid}: {metrics}")
                pd.DataFrame([metrics]).to_csv(taxon_dir / f"{taxid}_metrics.csv", index=False)
            except Exception as e:
                print(f"ERROR computing metrics for TaxID {taxid}: {e}")

            # Optional compress
            if args.compress:
                try:
                    with open(merged_fasta, "rb") as f_in, gzip.open(f"{merged_fasta}.gz", "wb") as f_out:
                        shutil.copyfileobj(f_in, f_out)
                    os.remove(merged_fasta)
                    print(f">>> Compressed merged FASTA for TaxID {taxid}")
                except Exception as e:
                    print(f"ERROR compressing FASTA for TaxID {taxid}: {e}")
        else:
            print(f"WARNING: Merged FASTA does not exist for TaxID {taxid}, skipping metrics/compression")

    # Save combined results
    if all_results:
        combined = pd.DataFrame(all_results)
        combined.to_csv(outdir / "combined_metrics.csv", index=False)
        print(f">>> Saved combined metrics to {outdir / 'combined_metrics.csv'}")
    else:
        print("WARNING: No results to save.")

    # Report skipped species
    if skipped_species:
        print("\n>>> Species skipped due to no mitochondrial FASTAs:")
        for sp_taxid, reason in skipped_species.items():
            print(f" - Species TaxID {sp_taxid}: {reason}")
    
    # Save skipped species to CSV
    if skipped_species:
        skipped_df = pd.DataFrame(
            list(skipped_species.items()), columns=["SpeciesTaxID", "Reason"]
            )
        skipped_csv = outdir / "skipped_species.csv"
        skipped_df.to_csv(skipped_csv, index=False)
        print(f">>> Saved skipped species list to {skipped_csv}")
        
if __name__ == "__main__":
    main()
