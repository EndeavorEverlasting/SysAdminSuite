# SysAdminSuite QR Field Command Capsule Profile
#
# Profile ID: neuron-hostname-survey
# Purpose: Survey expected Neurons by MAC/subnet evidence and resolve current hostnames.

profile_id=neuron-hostname-survey
description=Survey expected Neurons by MAC/subnet evidence and resolve current hostnames.
script=scripts/sas_neuron_hostname_survey.sh
mutation_allowed=false
requires_manifest=true
requires_nmap=true
scan_mode=host-discovery
max_hosts=32
output_prefix=neuron_hostname_survey

# Optional runtime arguments may be supplied by the QR launcher:
#   --manifest <csv>
#   --subnet <cidr>
#   --nmap-xml <saved xml>
#   --output-root <path>
#   --dry-run
