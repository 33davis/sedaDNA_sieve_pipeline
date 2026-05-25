#!/usr/bin/env python3
import sys
from Bio import Entrez
from time import sleep

# Set your email (required by NCBI)
Entrez.email = "emily.davis@utas.edu.au"


# Check for input file argument
if len(sys.argv) < 2:
    print("Usage: python get_taxids.py <accession_file.txt>")
    sys.exit(1)

input_file = sys.argv[1]
output_file = "taxids.txt"
missing_log = "missing_accessions.txt"

# Read accession numbers
with open(input_file) as f:
    accessions = [line.strip() for line in f if line.strip()]

taxids = []
missing = []

for acc in accessions:
    try:
        handle = Entrez.esummary(db="nucleotide", id=acc)
        record = Entrez.read(handle)
        handle.close()

        if record and "TaxId" in record[0]:
            # Extract the TaxId and ensure it's a plain string
            raw_taxid = record[0]["TaxId"]

            # Handle both possible Biopython types
            try:
                taxid = str(int(raw_taxid))
            except TypeError:
                # For IntegerElement or other wrapper types
                taxid = str(int(raw_taxid.data))

            taxids.append(taxid)
            print(f"{acc} -> {taxid}")

        sleep(0.4)

    except Exception as e:
        print(f"Error fetching {acc}: {e}")
        missing.append(acc)
        sleep(1)

unique_taxids = sorted(set(taxids))

with open(output_file, "w") as f:
    for tid in unique_taxids:
        f.write(f"{tid}\n")

if missing:
    with open(missing_log, "w") as f:
        for acc in missing:
            f.write(f"{acc}\n")
    print(f"\n{len(missing)} accessions missing - see {missing_log}")

print(f"\nDone! Wrote {len(unique_taxids)} unique TaxIDs to {output_file}.")