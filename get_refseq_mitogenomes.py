#!/usr/bin/env python3
import os
import gzip
import shutil
import argparse
import time
from pathlib import Path
import pandas as pd
from Bio import Entrez, SeqIO

# --- Configure Entrez ---
Entrez.email = "emily.davis@utas.edu.au"
Entrez.api_key = "001c90f50ff94f323e68b7ab1e549f36ef09"  # optional but recommended

def fetch_species_from_taxid(taxid, delay=0.2):
    """Expand higher-level taxid to all species-level taxids"""
    try:
        handle = Entrez.esearch(db="taxonomy", term=f"txid{taxid}[Subtree] AND species[Rank]", retmax=50000)
        record = Entrez.read(handle)
        handle.close()
        time.sleep(delay)
        return record.get("IdList", [])
    except Exception as e:
        print(f"ERROR fetching species for TaxID {taxid}: {e}")
        return []

def fetch_mito_genomes(taxid, outdir, delay=0.2):
    """Fetch mitochondrial genomes (RefSeq only) for a species taxid"""
    try:
        handle = Entrez.esearch(
            db="nuccore",
            term=f"txid{taxid}[Organism:exp] AND mitochondrion[filter] AND refseq[filter]",
            retmax=500
        )
        record = Entrez.read(handle)
        handle.close()
        time.sleep(delay)
    except Exception as e:
        print(f"ERROR fetching mitogenomes for {taxid}: {e}")
        return []

    idlist = record.get("IdList", [])
    fasta_files = []
    for idx in idlist:
        try:
            handle = Entrez.efetch(db="nuccore", id=idx, rettype="fasta", retmode="text")
            seqs = list(SeqIO.parse(handle, "fasta"))
            handle.close()
            time.sleep(delay)

            if seqs:
                outfile = outdir / f"{taxid}_{idx}.fna"
                SeqIO.write(seqs, outfile, "fasta")
                fasta_files.append(outfile)
        except Exception as e:
            print(f"--- Failed fetching FASTA for {taxid}, id {idx}: {e}")
    return fasta_files

def merge_fastas(fasta_files, merged_file):
    with open(merged_file, "w") as out_f:
        for file in fasta_files:
            with open(file) as in_f:
                shutil.copyfileobj(in_f, out_f)

def compute_metrics(fasta_file):
    lengths = [len(rec.seq) for rec in SeqIO.parse(open(fasta_file), "fasta")]
    return {
        "NumSeqs": len(lengths),
        "TotalLength": sum(lengths),
        "MeanLength": sum(lengths) / len(lengths) if lengths else 0,
        "MinLength": min(lengths) if lengths else 0,
        "MaxLength": max(lengths) if lengths else 0
    }

def main():
    parser = argparse.ArgumentParser(description="Run mito metrics pipeline with a taxid list (strict - RefSeq).")
    parser.add_argument("--taxid-file", required=True, help="Path to taxa ID file.")
    parser.add_argument("--outdir", default=".", help="Output directory (default: current dir).")
    parser.add_argument("--compress", action="store_true", help="Compress results.")
    parser.add_argument("--entrez-delay", type=float, default=0.2,
                        help="Delay (in seconds) between Entrez requests (default: 0.2)")
    args = parser.parse_args()

    taxids = [line.strip() for line in open(args.taxid_file) if line.strip()]
    outdir = Path(args.outdir)
    outdir.mkdir(exist_ok=True)

    all_results = []
    skipped_species = {}

    for taxid in taxids:
        print(f"\n>>> Processing TaxID: {taxid}")
        taxon_dir = outdir / taxid
        taxon_dir.mkdir(parents=True, exist_ok=True)

        species_taxids = fetch_species_from_taxid(taxid, delay=args.entrez_delay)
        print(f">>> Found {len(species_taxids)} species taxids under TaxID {taxid}")

        fasta_files_all = []
        for sp_taxid in species_taxids:
            print(f">>> Fetching mitochondrial genomes for species TaxID {sp_taxid}...")
            fasta_files = fetch_mito_genomes(sp_taxid, taxon_dir, delay=args.entrez_delay)
            if not fasta_files:
                print(f"--- No mitogenomes found for species TaxID {sp_taxid}, skipping")
                skipped_species[sp_taxid] = taxid
                continue
            print(f">>> Downloaded {len(fasta_files)} FASTA(s) for species TaxID {sp_taxid}")
            fasta_files_all.extend(fasta_files)

        print(f">>> Total FASTAs collected for TaxID {taxid}: {len(fasta_files_all)}")

        if not fasta_files_all:
            continue

        merged_fasta = taxon_dir / f"{taxid}_mitogenomes.fna"
        try:
            merge_fastas(fasta_files_all, merged_fasta)
        except Exception as e:
            print(f"ERROR merging FASTAs for TaxID {taxid}: {e}")
            continue

        if merged_fasta.exists():
            metrics = compute_metrics(merged_fasta)
            metrics["Parent_TaxID"] = taxid
            metrics["TaxID"] = taxid
            metrics["Compression"] = "Uncompressed"
            all_results.append(metrics)
            pd.DataFrame([metrics]).to_csv(taxon_dir / f"{taxid}_metrics.csv", index=False)

            if args.compress:
                gz_path = merged_fasta.with_suffix(merged_fasta.suffix + ".gz")
                with open(merged_fasta, "rb") as f_in, gzip.open(gz_path, "wb") as f_out:
                    shutil.copyfileobj(f_in, f_out)
                os.remove(merged_fasta)
                for f in fasta_files_all:
                    try:
                        os.remove(f)
                    except Exception as e:
                        print(f"--- Could not delete {f}: {e}")
                all_results[-1]["Compression"] = "Compressed"

    if all_results:
        pd.DataFrame(all_results).to_csv(outdir / "all_metrics.csv", index=False)

    if skipped_species:
        pd.DataFrame(
            [{"Parent_TaxID": p, "Species_TaxID": s, "Status": "No FASTAs"} for s, p in skipped_species.items()]
        ).to_csv(outdir / "skipped_species.csv", index=False)

if __name__ == "__main__":
    main()