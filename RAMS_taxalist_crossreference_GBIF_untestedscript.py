# crosscheck_rams_gbif.py
# Purpose: Classify species as Recorded / Questionable / Not recorded in Antarctic/SO/Subantarctic
# Inputs:  taxa_input_clean_unique.txt  (one "Genus species" per line)
# Outputs: rams_gbif_crosscheck_all.csv, rams_gbif_questionable_notRecorded.tsv, rams_gbif_log.json

import csv, json, time, urllib.parse, sys
from pathlib import Path
import requests

# ----------------- Settings you can tweak -----------------
INPUT = "taxa_input_clean_unique.txt"        # produced above
SLEEP = 0.15                                 # seconds between API calls (be gentle)
TIMEOUT = 20                                 # seconds for each request
# Regions
ANTARCTIC_LAT_MAX = -60.0
SUBANT_LO = -60.0
SUBANT_HI = -46.0
# Decision thresholds
QUESTIONABLE_MAX = 3                         # 1..N SO records (and not in RAMS) → Questionable
# ----------------------------------------------------------

GBIF_OCC_URL = "https://api.gbif.org/v1/occurrence/search"
# RAMS shares the WoRMS API; using RAMS subregister endpoint
RAMS_BYNAME_URL = "https://www.marinespecies.org/rams/aphia.php?p=rest/AphiaRecordsByName/{}?like=false&marine_only=false"

def gbif_count_latband(scientific_name: str, lo: float, hi: float) -> int:
    # decimalLatitude filter uses "min,max" value
    lat_param = f"{lo},{hi}"
    params = {"scientificName": scientific_name, "decimalLatitude": lat_param, "limit": 0}
    r = requests.get(GBIF_OCC_URL, params=params, timeout=TIMEOUT)
    r.raise_for_status()
    data = r.json()
    return int(data.get("count", 0))

def rams_present(scientific_name: str) -> bool:
    url = RAMS_BYNAME_URL.format(urllib.parse.quote(scientific_name))
    r = requests.get(url, timeout=TIMEOUT)
    if r.status_code == 204:   # WoRMS/RAMS returns 204 when no content
        return False
    r.raise_for_status()
    data = r.json()
    if not isinstance(data, list) or len(data) == 0:
        return False
    # Any match (accepted or unaccepted) indicates the name exists in the RAMS subregister
    return True

def classify(in_rams: bool, n_SO: int) -> str:
    if in_rams or n_SO >= 1:
        return "Recorded"
    if (not in_rams) and (1 <= n_SO <= QUESTIONABLE_MAX):
        return "Questionable"
    return "Not recorded"

def main():
    names = [ln.strip() for ln in Path(INPUT).read_text(encoding="utf-8").splitlines() if ln.strip()]
    out_rows = []
    log = {}
    for i, name in enumerate(names, 1):
        try:
            # RAMS
            in_rams = rams_present(name)
            time.sleep(SLEEP)
            # GBIF counts
            n_ant = gbif_count_latband(name, -90.0, ANTARCTIC_LAT_MAX)
            time.sleep(SLEEP)
            n_sub = gbif_count_latband(name, SUBANT_LO, SUBANT_HI)
            time.sleep(SLEEP)
            n_so = n_ant + n_sub
            status = classify(in_rams, n_so)
            out_rows.append({
                "scientificName": name,
                "in_RAMS": str(in_rams),
                "n_Antarctic": n_ant,
                "n_Subantarctic": n_sub,
                "n_SO_total": n_so,
                "status": status
            })
            log[name] = {
                "rams_endpoint": "RAMS AphiaRecordsByName",
                "in_RAMS": in_rams,
                "GBIF_occ_search_params": {
                    "antarctic_decimalLatitude": "-90,-60",
                    "subantarctic_decimalLatitude": "-60,-46"
                }
            }
            if i % 25 == 0:
                print(f"...processed {i}/{len(names)}")
        except Exception as e:
            out_rows.append({
                "scientificName": name,
                "in_RAMS": "ERROR",
                "n_Antarctic": "",
                "n_Subantarctic": "",
                "n_SO_total": "",
                "status": f"ERROR: {e}"
            })

    # Write full CSV
    with open("rams_gbif_crosscheck_all.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["scientificName","in_RAMS","n_Antarctic","n_Subantarctic","n_SO_total","status"])
        w.writeheader()
        for r in out_rows:
            w.writerow(r)

    # Write only Questionable / Not recorded to TSV
    with open("rams_gbif_questionable_notRecorded.tsv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["scientificName","in_RAMS","n_Antarctic","n_Subantarctic","n_SO_total","status"])
        for r in out_rows:
            if r["status"] in ("Questionable","Not recorded"):
                w.writerow([r[k] for k in ["scientificName","in_RAMS","n_Antarctic","n_Subantarctic","n_SO_total","status"]])

    # Save a small log
    with open("rams_gbif_log.json", "w", encoding="utf-8") as f:
        json.dump(log, f, indent=2)

    print("Done. Files written: rams_gbif_crosscheck_all.csv, rams_gbif_questionable_notRecorded.tsv, rams_gbif_log.json")

if __name__ == "__main__":
    main()