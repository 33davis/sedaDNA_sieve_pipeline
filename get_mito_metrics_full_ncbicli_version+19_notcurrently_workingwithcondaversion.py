#!/usr/bin/env python3

import os
import sys
import argparse
import subprocess
import gzip
import shutil
from pathlib import Path
from Bio import SeqIO, Entrez
import pandas as pd
import numpy as np

# --- Setup Entrez ---
Entrez.email = "emily.davis@utas.edu.au"  # <- change to your email for NCBI

def run_cmd(cmd, cwd=None):
    """Run shell command safely, raise error if fails."""
    result = subprocess.run(cmd, shell=True, cwd=cwd,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            text=True)
    if result.returncode != 0:
        print(f"ERROR running: {cmd}\n{result.stderr}")
        sys.exit(1)
    return result.stdout

def download_mito_genomes(taxid, outdir):
    """Download mitochondrial genomes for a given TaxID using NCBI datasets CLI."""
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    zipfile = outdir / "genomes.zip"

    # restrict to mitochondria assemblies only
    cmd = (
        f"datasets download genome taxon {taxid} "
        f"--assembly-source refseq "
        f"--include genome "
        f"--filters organelle:mitochondrion "
        f"--filename {zipfile}"
    )
    run_cmd(cmd)

    # unzip
    run_cmd(f"unzip -o {zipfile} -d {outdir}")
    fasta_files = list(outdir.glob("ncbi_dataset/data/*/*.fna"))
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
   parser = argparse.ArgumentParser(
    description="Run mito metrics pipeline with a taxid list.")
parser.add_argument("--taxa-list",
    dest="taxid_file",
    required=True,
    help="Path to taxa ID file.")
parser.add_argument(
    "--outdir",
    default=".",
    help="Output directory (default: current dir).")
parser.add_argument(
    "--compress",
    action="store_true",
    help="Compress results.")
args = parser.parse_args()

    taxids = [line.strip() for line in open(args.taxid_file) if line.strip()]
    outdir = Path(args.outdir)
    outdir.mkdir(exist_ok=True)

    all_results = []

    for taxid in taxids:
        print(f">>> Processing Taxon ID: {taxid}")
        taxon_dir = outdir / taxid
        taxon_dir.mkdir(parents=True, exist_ok=True)

        fasta_files = download_mito_genomes(taxid, taxon_dir)

        if not fasta_files:
            print(f"WARNING: No mitochondrial FASTAs found for {taxid}")
            continue

        merged_fasta = taxon_dir / f"{taxid}_mitogenomes.fna"
        merge_fastas(fasta_files, merged_fasta)

        metrics = compute_metrics(merged_fasta)
        metrics["TaxID"] = taxid
        all_results.append(metrics)

        # save per-taxon metrics
        pd.DataFrame([metrics]).to_csv(taxon_dir / f"{taxid}_metrics.csv", index=False)

        # optional compress
        if args.compress:
            with open(merged_fasta, "rb") as f_in, gzip.open(f"{merged_fasta}.gz", "wb") as f_out:
                shutil.copyfileobj(f_in, f_out)
            os.remove(merged_fasta)

    # save combined results
    if all_results:
        combined = pd.DataFrame(all_results)
        combined.to_csv(outdir / "combined_metrics.csv", index=False)

if __name__ == "__main__":
    main()
