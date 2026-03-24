# EL082 Deployment Results Guide

## Overview

This guide explains the results table shown when running the EL082 deployment scripts, particularly focusing on the sandbox mode results and why certain fields may show unexpected values.

## Results Table Columns

### Host
- **Description**: The target computer name where deployment was attempted
- **Example**: `WEL082MST051`, `WEL082MST055`, etc.
- **What it means**: Each row represents one target machine in your deployment list

### Reachable
- **Description**: Whether the script could establish connectivity to the target host
- **Values**: `True` or `False`
- **What it means**:
  - `True`: Script successfully connected to the host (or sandbox mode is enabled)
  - `False`: Host is offline, unreachable, or has network connectivity issues

### CsvsPushed
- **Description**: Whether CSV files were actually copied to the target during this run
- **Values**: `True` or `False`
- **What it means**:
  - `True`: CSV files were copied because they were new or had changed content
  - `False`: CSV files already existed with identical content (no copy needed)

### DefaultVbs
- **Description**: Whether the per-user default VBS script was installed
- **Values**: `True` or `False`
- **What it means**:
  - `True`: The `Set-EL082-Default-FromCSV.vbs` script was successfully copied to the All Users Startup folder
  - `False`: This step was not performed (script not run with `-InstallDefaultAtLogon` parameter)

### MapTask
- **Description**: Whether the machine-wide mapping task was created/executed
- **Values**: `True` or `False`
- **What it means**:
  - `True`: Task was created and executed (or task file created in sandbox mode)
  - `False`: This step was not performed (script not run with `-MapNow` parameter)

### Notes
- **Description**: Additional information about the deployment process
- **Common values**:
  - `True sandbox mode - task file created`: Sandbox mode is active, simulated task files were created
  - `offline/unreachable`: Host could not be reached
  - `[error message]`: Specific error that occurred during deployment

## Why CsvsPushed Shows as False

### The Issue
In your sandbox deployment results, `CsvsPushed` shows as `False` for all hosts, even though the CSV files are actually present in the sandbox directories.

### Root Cause
The `CsvsPushed` field is determined by the `_CopyIfChanged` function, which:

1. **Checks if destination file exists**: If the file doesn't exist, it copies and returns `True`
2. **Compares file hashes**: If the file exists, it compares SHA256 hashes of source and destination
3. **Only copies if different**: Only copies if the hashes don't match, returning `True` only if a copy was actually performed

### Why It's False in Sandbox Mode
The CSV files are being copied successfully, but the `_CopyIfChanged` function is designed to be efficient and only report changes when files are actually modified. Since:

1. The CSV files exist in the sandbox directories (as confirmed by directory listing)
2. The files have identical content to the source files
3. The function correctly determines no copy is needed

The `CsvsPushed` field correctly shows `False` because no new copy operation was required.

### Verification
You can verify the files are actually there by checking:
```
.\sandbox\WEL082MST051\C$\ProgramData\EL082\
```

This directory contains:
- `el082_defaults.csv`
- `el082_printers.csv`
- `Map-EL082-MachineWide.ps1`

## Deployment Modes

### Sandbox Mode
- **Purpose**: Test deployment without affecting real systems
- **Behavior**: Creates local directory structure simulating remote deployment
- **File Locations**: `.\sandbox\<HOST>\C$\...`
- **Task Execution**: Creates simulation files instead of running actual tasks

### Production Mode
- **Purpose**: Deploy to actual remote systems
- **Behavior**: Connects to real hosts and performs actual deployment
- **File Locations**: `\\<HOST>\C$\ProgramData\EL082\`
- **Task Execution**: Creates and runs actual scheduled tasks

## Understanding the Results

### Successful Deployment Indicators
- `Reachable = True`: Host is accessible
- `DefaultVbs = True`: Per-user script installed (if `-InstallDefaultAtLogon` used)
- `MapTask = True`: Mapping task created/executed (if `-MapNow` used)
- `CsvsPushed = True/False`: Files are present (False is normal if files already exist)

### Problem Indicators
- `Reachable = False`: Network connectivity issues
- `DefaultVbs = False`: Script installation failed (check permissions)
- `MapTask = False`: Task creation failed (check permissions)
- Error messages in `Notes` column

## Best Practices

1. **Always check the Notes column** for specific error messages
2. **Verify file presence** in target directories regardless of `CsvsPushed` value
3. **Use sandbox mode first** to test deployment logic
4. **Check permissions** when deploying to production systems
5. **Review task files** in sandbox mode to understand what would be executed

## Troubleshooting

### If CsvsPushed is False but files are missing:
- Check source file paths in the script
- Verify file permissions
- Look for error messages in the Notes column

### If deployment fails:
- Check network connectivity
- Verify administrative permissions
- Review Windows Event Logs on target systems
- Use sandbox mode to isolate issues