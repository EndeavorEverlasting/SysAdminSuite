# Deployment Tracker to Network Inventory Pipeline

## Purpose

This workflow lets SysAdminSuite use a downloaded live deployment tracker workbook as the target source for network inventory surveys.

The first production use case is **Neuron inventory**:

1. Download the live deployment tracker as `.xlsx`.
2. Point SysAdminSuite at the workbook.
3. Extract known Neuron identifiers from the tracker.
4. Produce a clean target list for network survey.
5. Survey the network from the admin workstation.
6. Reconcile observed serials and MAC addresses against the tracked identifiers.

The design is intentionally expandable. After Neurons are squared away, the same pattern can be extended to Cybernets, printers, workstations, Tangents, or other device classes.

## Prime Directive

Artifacts remain on the **admin box**, not the targets.

This pipeline does **not**:

- copy payloads to target machines
- create scheduled tasks on target machines
- write reports to target machines
- edit the source tracker workbook
- require Excel COM automation
- require the ImportExcel PowerShell module

## Files

| File | Role |
|---|---|
| `GetInfo/Convert-DeploymentTrackerToTargets.ps1` | Reads a downloaded tracker `.xlsx` and creates target CSV files |
| `GetInfo/Get-NeuronNetworkInventory.ps1` | Surveys Neuron hosts remotely and writes inventory artifacts locally |
| `GetInfo/Config/NeuronTargets.example.csv` | Manual/template target CSV |
| `GetInfo/Config/NeuronTargets.csv` | Generated or manually maintained target CSV, git-ignored in practice if sensitive |
| `GetInfo/Config/NeuronTargets.unresolved.csv` | Rows with MAC/serial data but no host to query |
| `GetInfo/Output/NeuronNetworkInventory/` | Local admin-box output folder for CSV/JSON/HTML survey results |
| `docs/diagrams/device-tracker-network-inventory.mmd` | Mermaid flow diagram for this architecture |

## Workflow

### 1. Download the tracker

Download the live deployment tracker from Excel for Web or your shared source as an `.xlsx` file.

Do not edit it for this workflow. Treat it as input evidence.

### 2. Extract Neuron targets

From the repo root:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\GetInfo\Convert-DeploymentTrackerToTargets.ps1 `
  -WorkbookPath "C:\Path\To\DeploymentTracker.xlsx" `
  -DeviceType Neuron `
  -OutputPath .\GetInfo\Config\NeuronTargets.csv
```

Optional, if the sheet name is known:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\GetInfo\Convert-DeploymentTrackerToTargets.ps1 `
  -WorkbookPath "C:\Path\To\DeploymentTracker.xlsx" `
  -WorksheetName "12 - Device_Configuration" `
  -DeviceType Neuron `
  -OutputPath .\GetInfo\Config\NeuronTargets.csv
```

### 3. Review unresolved identifiers

The converter writes unresolved rows beside the output CSV by default:

```text
GetInfo\Config\NeuronTargets.unresolved.csv
```

These are rows where the tracker had useful identifiers, usually MAC or serial, but no usable Neuron hostname.

Cold judge ruling: do not discard these. They are not failures. They are leads.

### 4. Run the survey

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\GetInfo\Get-NeuronNetworkInventory.ps1 `
  -ListPath .\GetInfo\Config\NeuronTargets.csv
```

If ICMP is blocked or unreliable:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\GetInfo\Get-NeuronNetworkInventory.ps1 `
  -ListPath .\GetInfo\Config\NeuronTargets.csv `
  -SkipPing
```

With alternate credentials:

```powershell
$cred = Get-Credential
powershell.exe -ExecutionPolicy Bypass -File .\GetInfo\Get-NeuronNetworkInventory.ps1 `
  -ListPath .\GetInfo\Config\NeuronTargets.csv `
  -Credential $cred
```

## Target CSV Contract

The Neuron survey expects a CSV that includes these fields:

| Column | Required | Purpose |
|---|---:|---|
| `NeuronHost` | Yes | Hostname to query remotely |
| `ExpectedMAC` | No | MAC address from tracker or field list |
| `ExpectedSerial` | No | Serial number from tracker or field list |
| `Site` | No | Building/site/facility context |
| `Room` | No | Room/location/area context |
| `Notes` | No | Source row, tracker note, or operator context |

The converter currently maps flexible tracker headers into this contract.

## Header Aliases

For Neurons, the converter looks for headers similar to:

| Output Field | Accepted Tracker Header Shapes |
|---|---|
| `NeuronHost` | `Neuron Hostname`, `Neuron Host`, `Neuron Name`, `Neuron Computer Name`, `Neuron` |
| `ExpectedMAC` | `Neuron MAC`, `Neuron MAC Address`, `MAC Address`, `MAC` |
| `ExpectedSerial` | `Neuron Serial`, `Neuron Serial Number`, `Serial Number`, `Serial` |
| `Site` | `Site`, `Building`, `Facility`, `Current Building`, `Install Building` |
| `Room` | `Room`, `Location`, `Area`, `OR`, `Install Room`, `Current Room` |
| `Notes` | `Notes`, `Comment`, `Comments`, `Deployment Notes` |

The match is normalized, so spaces, casing, and punctuation are ignored.

## Output Interpretation

`Get-NeuronNetworkInventory.ps1` writes:

| Output | Meaning |
|---|---|
| `.csv` | Main reconciliation table |
| `.json` | Machine-readable equivalent for future tooling |
| `.html` | Human-readable report if the suite HTML helper is available |

Important columns:

| Column | Meaning |
|---|---|
| `MACAddress` | All IP-enabled adapter MACs found on the host |
| `PrimaryMAC` | First observed MAC, useful for quick review but not gospel |
| `SerialNumber` | BIOS serial |
| `SystemSerialNumber` | ComputerSystemProduct identifying number |
| `MatchExpectedMAC` | Whether observed MAC matched the tracker MAC |
| `MatchExpectedSerial` | Whether observed serial matched the tracker serial |
| `TargetSideArtifacts` | Must remain `None` for this workflow |

## Extension Model

Do not hardwire this forever to Neurons. The better architecture is:

```text
Tracker workbook
  -> device-type extractor
  -> target contract CSV
  -> survey engine
  -> reconciliation output
```

Future device types should reuse the same pattern:

| Device Type | Extractor Contract | Survey Method |
|---|---|---|
| Neuron | Host, MAC, serial, site, room | WMI remote query |
| Cybernet | Host, serial, app list, site, room | WMI remote query plus app checks |
| Printer | IP/hostname, MAC, serial, queue | SNMP/WMI/print server lookup |
| Workstation | Host, serial, asset tag, room | WMI/CIM remote query |

## Operator Checklist

Before sending results upstream:

- Confirm the tracker download date.
- Confirm the worksheet used if multiple sheets contain similar headers.
- Review `NeuronTargets.unresolved.csv`.
- Spot-check at least a few matched MACs and serials manually.
- Do not represent unresolved rows as network failures.
- Keep generated artifacts local unless intentionally attached to a report.

## Known Limits

- `.xls` is not supported. Export/download as `.xlsx`.
- Formula cells may expose cached values only if Excel saved them with cached results.
- Merged header cells are not ideal. Flatten headers if extraction misses columns.
- Hidden sheets may still be scanned unless `-WorksheetName` is specified.
- The converter is deliberately read-only. It never fixes the workbook.
