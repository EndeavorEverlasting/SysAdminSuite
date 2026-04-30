#!/usr/bin/env bash
set -Eeuo pipefail

REFERENCE_ID="11.8.0.328"
OBSERVED_PATH=""
OUT_DIR="$PWD/output/neuron-software-reference"
NEURON_HOST="Neuron"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reference-id)
      REFERENCE_ID="${2:?missing value for --reference-id}"
      shift 2
      ;;
    --observed)
      OBSERVED_PATH="${2:?missing value for --observed}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:?missing value for --out-dir}"
      shift 2
      ;;
    --host)
      NEURON_HOST="${2:?missing value for --host}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage:
  neuron_software_reference.sh [--observed path.csv] [--reference-id 11.8.0.328] [--out-dir output] [--host label]

Observed CSV schema:
  Category,Name,Version
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REFERENCE_PATH="$SUITE_ROOT/GetInfo/Config/NeuronSoftwareReferences/${REFERENCE_ID}.json"

if [[ ! -f "$REFERENCE_PATH" ]]; then
  echo "Reference not found: $REFERENCE_PATH" >&2
  exit 66
fi

mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
SAFE_HOST="$(echo "$NEURON_HOST" | tr -cd 'A-Za-z0-9_.-' | sed 's/^$/Neuron/')"
EXPECTED_CSV="$OUT_DIR/${SAFE_HOST}_SoftwareReference_${REFERENCE_ID}_${STAMP}_expected.csv"
COMPARISON_CSV="$OUT_DIR/${SAFE_HOST}_SoftwareReference_${REFERENCE_ID}_${STAMP}_comparison.csv"
SUMMARY_JSON="$OUT_DIR/${SAFE_HOST}_SoftwareReference_${REFERENCE_ID}_${STAMP}_summary.json"

python3 - "$REFERENCE_PATH" "$OBSERVED_PATH" "$EXPECTED_CSV" "$COMPARISON_CSV" "$SUMMARY_JSON" "$NEURON_HOST" <<'PY'
import csv
import json
import sys
from pathlib import Path

reference_path, observed_path, expected_csv, comparison_csv, summary_json, neuron_host = sys.argv[1:]

def norm_name(value):
    return ''.join(str(value or '').split()).upper()

def norm_version(value):
    return ''.join(str(value or '').split())

with open(reference_path, 'r', encoding='utf-8') as f:
    ref = json.load(f)

reference_rows = []
for category in ('firmware', 'ddi'):
    for pkg in ref.get(category, []):
        reference_rows.append({
            'Category': category,
            'Name': str(pkg.get('name', '')),
            'Version': str(pkg.get('version', '')),
            'NormalizedName': norm_name(pkg.get('name', '')),
            'NormalizedVersion': norm_version(pkg.get('version', '')),
        })

observed_rows = []
if observed_path:
    with open(observed_path, newline='', encoding='utf-8-sig') as f:
        for row in csv.DictReader(f):
            name = row.get('Name') or row.get('Package') or ''
            if not name:
                continue
            category = (row.get('Category') or '').lower()
            version = row.get('Version') or ''
            observed_rows.append({
                'Category': category,
                'Name': name,
                'Version': version,
                'NormalizedName': norm_name(name),
                'NormalizedVersion': norm_version(version),
            })

with open(expected_csv, 'w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=['Category', 'Name', 'Version'])
    writer.writeheader()
    for row in reference_rows:
        writer.writerow({k: row[k] for k in ['Category', 'Name', 'Version']})

comparison = []
observed_by_key = {}
for row in observed_rows:
    observed_by_key.setdefault((row['Category'], row['NormalizedName']), []).append(row)

reference_keys = set()
for ref_row in reference_rows:
    key = (ref_row['Category'], ref_row['NormalizedName'])
    reference_keys.add(key)
    matches = observed_by_key.get(key, [])
    if not observed_rows:
        status = 'ReferenceOnly'
        observed_version = ''
        detail = 'No observed snapshot supplied; this is the expected baseline.'
    elif not matches:
        status = 'Missing'
        observed_version = ''
        detail = 'Package expected by reference was not found in observed snapshot.'
    else:
        observed_versions = sorted({m['Version'] for m in matches})
        observed_version = ';'.join(observed_versions)
        status = 'OK' if any(m['NormalizedVersion'] == ref_row['NormalizedVersion'] for m in matches) else 'VersionMismatch'
        detail = 'Observed package matches reference.' if status == 'OK' else 'Observed package exists but version differs from reference.'
    comparison.append({
        'Category': ref_row['Category'],
        'Package': ref_row['Name'],
        'ExpectedVersion': ref_row['Version'],
        'ObservedVersion': observed_version,
        'Status': status,
        'Detail': detail,
    })

for obs in observed_rows:
    key = (obs['Category'], obs['NormalizedName'])
    if key in reference_keys:
        continue
    comparison.append({
        'Category': obs['Category'],
        'Package': obs['Name'],
        'ExpectedVersion': '',
        'ObservedVersion': obs['Version'],
        'Status': 'Extra',
        'Detail': 'Observed package is not in the selected reference baseline.',
    })

with open(comparison_csv, 'w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=['Category', 'Package', 'ExpectedVersion', 'ObservedVersion', 'Status', 'Detail'])
    writer.writeheader()
    writer.writerows(comparison)

summary = {
    'neuronHost': neuron_host,
    'referenceId': ref.get('referenceId'),
    'referencePath': reference_path,
    'observedPath': observed_path,
    'expectedPackageCount': len(reference_rows),
    'observedPackageCount': len(observed_rows),
    'OK': sum(1 for r in comparison if r['Status'] == 'OK'),
    'Missing': sum(1 for r in comparison if r['Status'] == 'Missing'),
    'VersionMismatch': sum(1 for r in comparison if r['Status'] == 'VersionMismatch'),
    'Extra': sum(1 for r in comparison if r['Status'] == 'Extra'),
    'ReferenceOnly': sum(1 for r in comparison if r['Status'] == 'ReferenceOnly'),
    'expectedCsv': expected_csv,
    'comparisonCsv': comparison_csv,
}
with open(summary_json, 'w', encoding='utf-8') as f:
    json.dump(summary, f, indent=2)
PY

echo "Neuron software reference complete"
echo "Expected CSV: $EXPECTED_CSV"
echo "Comparison CSV: $COMPARISON_CSV"
echo "Summary JSON: $SUMMARY_JSON"
