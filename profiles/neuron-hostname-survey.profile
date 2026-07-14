# SysAdminSuite QR Field Command Capsule Profile
profile_id=neuron-hostname-survey
description=Survey expected Neurons using saved discovery evidence and produce resolved-target and review artifacts.
runner=python3
script=survey/sas-match-neurons-from-nmap.py
mutation_allowed=false
requires_manifest=true
requires_discovery_evidence=true
output_contract=resolved_targets_csv,review_csv,optional_dashboard

# Intended QR payload:
# bash scripts/sas_qr_run.sh --profile neuron-hostname-survey -- \
#   --manifest GetInfo/Config/NeuronTargets.unresolved.csv \
#   --nmap-xml survey/artifacts/site_neuron_discovery.xml \
#   --output survey/output/neuron_resolved_targets.csv \
#   --review-output survey/output/neuron_probe_review.csv
