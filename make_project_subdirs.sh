
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration: subfolders to create in each project directory ---
TARGETS=(
  "AdapterRemoval_demux_nocollapse"
  "AdapterRemoval_demux_collapse"
  "QC_files/rawQCfiles"
  "QC_files/demux_trim_collapse_QCfiles"
  "QC_files/post_komplexity_dedupe"
  "Komplexity_dedupe_for_fastq_renaming"
)

usage() {
  cat <<'EOF'
Usage:
  make_project_subdirs.sh [ROOT_DIR]

Description:
  For every immediate subdirectory under ROOT_DIR (default: current directory),
  create the following subfolders inside each one:
    - AdapterRemoval_demux_nocollapse
    - AdapterRemoval_demux_collapse
    - QC_files/rawQCfiles
    - QC_files/demux_trim_collapse_QCfiles
    - QC_files/post_komplexity_dedupe
    - Komplexity_dedupe_for_fastq_renaming

Examples:
  ./make_project_subdirs.sh
  ./make_project_subdirs.sh /path/to/root

Notes:
  - Uses `mkdir -p` (no errors if directories already exist).
  - Processes depth-1 directories only (not recursive).
  - Handles spaces in directory names.
  - Excludes hidden entries by default; remove the filter to include them.
EOF
}

ROOT_DIR="${1:-.}"

# Validate root
if [[ ! -d "$ROOT_DIR" ]]; then
  echo "ERROR: Not a directory: $ROOT_DIR" >&2
  usage
  exit 1
fi

echo "Root: $ROOT_DIR"
echo "Creating subfolders in each immediate subdirectory:"
printf '  - %s\n' "${TARGETS[@]}"
echo

# Iterate immediate subdirectories safely (handles spaces/newlines)
while IFS= read -r -d '' subdir; do
  echo "Processing: $subdir"
  for relpath in "${TARGETS[@]}"; do
    target="$subdir/$relpath"
    echo "  Creating: $target"
    mkdir -p -- "$target"
  done
done < <(find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d -not -path "*/.*" -print0)

echo "Done."

