# EL082 Sandbox Script Fix Documentation

## Problem Description

The `Run-EL082-Sandbox.ps1` script was failing with the following error:

```
A parameter cannot be found that matches parameter name 'SandboxRoot'.
```

**Error Details:**
- **Script:** `Run-EL082-Sandbox.ps1`
- **Line:** 17, character 3
- **Command:** `-SandboxRoot $root`
- **Target Script:** `Publish-EL082-Pack.ps1`
- **Error Type:** `ParameterBindingException`

## Root Cause Analysis

The issue occurred because:

1. `Run-EL082-Sandbox.ps1` was calling `Publish-EL082-Pack.ps1` with a `-SandboxRoot` parameter
2. `Publish-EL082-Pack.ps1` does **not** have a `-SandboxRoot` parameter in its parameter block
3. The original script was designed for remote deployment only, not local sandbox creation

## Available Parameters in Publish-EL082-Pack.ps1

The original script only supports these parameters:
- `$ComputerName` (string array) - Target computers
- `$PrintersCsv` (string) - Path to printers CSV file
- `$DefaultsCsv` (string) - Path to defaults CSV file  
- `$MapScript` (string) - Path to mapping script
- `$UserVbs` (string) - Path to user VBS script
- `$MapNow` (switch) - Run mapping immediately
- `$InstallDefaultAtLogon` (switch) - Install default script at logon
- `$PauseAtEnd` (switch) - Pause before closing

## Solution Implemented

### Option 1: Quick Fix (Applied)
- **File Modified:** `Run-EL082-Sandbox.ps1`
- **Change:** Removed the `-SandboxRoot $root` parameter from the script call
- **Result:** Script now works with remote deployment only

### Option 2: Full Sandbox Support (Created)
- **New File:** `Publish-EL082-Pack-Sandbox.ps1`
- **Features Added:**
  - New `-SandboxRoot` parameter for local sandbox mode
  - Conditional logic to handle both remote and local deployment
  - Local directory structure creation
  - Task simulation files instead of actual remote task execution
  - Connectivity test bypass in sandbox mode

## Files Modified/Created

### Modified Files:
1. **`Run-EL082-Sandbox.ps1`**
   - Removed `-SandboxRoot` parameter (Option 1)
   - Updated to use new sandbox-enabled script (Option 2)
   - Fixed CSV file paths to correct locations

### New Files:
1. **`Publish-EL082-Pack-Sandbox.ps1`**
   - Sandbox-enabled version of the original script
   - Supports both remote deployment and local sandbox creation
   - Creates local directory structure: `.\sandbox\<HOST>\C$\...`

## Usage Instructions

### For Remote Deployment (Original Functionality):
```powershell
.\Publish-EL082-Pack.ps1 -ComputerName @('HOST1','HOST2') -MapNow -InstallDefaultAtLogon
```

### For Local Sandbox Testing:
```powershell
.\Run-EL082-Sandbox.ps1
```

This will:
1. Create `.\sandbox\` directory
2. Create subdirectories for each host: `.\sandbox\<HOST>\C$\ProgramData\EL082\`
3. Copy CSV files to local sandbox directories
4. Create simulated task files instead of running actual remote tasks
5. Show deployment results

## Directory Structure Created

When running in sandbox mode, the following structure is created:

```
.\sandbox\
├── WEL082MST051\
│   ├── C$\ProgramData\EL082\
│   │   ├── el082_printers.csv
│   │   ├── el082_defaults.csv
│   │   └── Map-EL082-MachineWide.ps1
│   ├── C$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\
│   │   └── Set-EL082-Default-FromCSV.vbs
│   └── EL082_MapAll_Task.txt
├── WEL082MST055\
│   └── [same structure]
└── [other hosts...]
```

## Testing the Fix

1. **Test Sandbox Mode:**
   ```powershell
   .\Run-EL082-Sandbox.ps1
   ```

2. **Verify Sandbox Creation:**
   - Check that `.\sandbox\` directory is created
   - Verify host subdirectories exist
   - Confirm CSV files are copied to sandbox locations
   - Verify task simulation files are created

3. **Test Original Remote Deployment:**
   ```powershell
   .\Publish-EL082-Pack.ps1 -ComputerName @('TESTHOST') -MapNow -PauseAtEnd
   ```

## Additional Fix Applied

**Issue:** After implementing the sandbox functionality, a new error appeared:
```
A positional parameter cannot be found that accepts argument 'C...
```

**Root Cause:** The `Join-Path` function was being called with 3 arguments incorrectly:
```powershell
Join-Path $SandboxRoot $c "C$\ProgramData\EL082"
```

**Fix:** Changed to proper nested `Join-Path` calls:
```powershell
Join-Path (Join-Path $SandboxRoot $c) "C$\ProgramData\EL082"
```

**Files Fixed:**
- `Publish-EL082-Pack-Sandbox.ps1` - Fixed `_ProgDataEL082()` and `_StartupPath()` functions
- Fixed task file path creation in sandbox mode

## Notes

- The sandbox mode creates a local simulation of the deployment without actually connecting to remote computers
- Task execution is simulated by creating text files with the commands that would be run
- This allows for testing the deployment logic without affecting production systems
- The original `Publish-EL082-Pack.ps1` remains unchanged for backward compatibility 