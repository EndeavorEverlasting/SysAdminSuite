# EL082 Troubleshooting Guide

## Quick Fix for "Missing required file" Error

### The Problem
You're getting this error:
```
Missing required file: C:\Users\pa_rperez26\OneDrive - Northwell Health\Desktop\dev\remote repo\mapping\el082_printers.csv
```

### The Root Cause
**File naming mismatch!** 

The script expects:
- `el082_printers.csv`
- `el082_defaults.csv`

But your files are named:
- `EL082_el082_printers.csv` (with extra "EL082_" prefix)
- `EL082_el082_defaults.csv` (with extra "EL082_" prefix)

### The Solution

**Option 1: Rename your files (Recommended)**
```powershell
Rename-Item "EL082_el082_printers.csv" "el082_printers.csv"
Rename-Item "EL082_el082_defaults.csv" "el082_defaults.csv"
```

**Option 2: Specify file paths explicitly**
```powershell
.\Publish-EL082-Pack.ps1 -PrintersCsv "EL082_el082_printers.csv" -DefaultsCsv "EL082_el082_defaults.csv" -MapNow -InstallDefaultAtLogon -PauseAtEnd
```

**Option 3: Copy files with correct names**
```powershell
Copy-Item "EL082_el082_printers.csv" "el082_printers.csv"
Copy-Item "EL082_el082_defaults.csv" "el082_defaults.csv"
```

## After Fixing the File Names

### Test Connectivity First
```powershell
.\Publish-EL082-Pack.ps1 -PauseAtEnd
```

### Full Deployment
```powershell
.\Publish-EL082-Pack.ps1 -MapNow -InstallDefaultAtLogon -PauseAtEnd
```

## Other Common Issues

### "Access Denied" Errors
- Run PowerShell as Administrator
- Verify you have admin rights on target machines
- Check Windows Event Logs for permission errors

### "Host Unreachable" Errors
- Verify target machines are online
- Check network connectivity
- Ensure firewall allows PowerShell remoting
- Verify DNS resolution for target hostnames

### Missing Script Files
Ensure these files are present:
- `Map-EL082-MachineWide.ps1` (required with `-MapNow`)
- `Set-EL082-Default-FromCSV.vbs` (required with `-InstallDefaultAtLogon`)

## File Requirements Summary

### Required Files:
- `el082_printers.csv` - Printer mappings
- `el082_defaults.csv` - Default printer settings
- `Map-EL082-MachineWide.ps1` - Mapping script
- `Set-EL082-Default-FromCSV.vbs` - User default script

### CSV Format:
**el082_printers.csv:**
```csv
Server,Share
SWBPHHHPS01V,EL082-MST15
SWBPHHHPS02V,EL082-MST16
```

**el082_defaults.csv:**
```csv
DefaultPrinter
EL082-MST15
```

## Quick Commands Reference

### Sandbox Testing:
```powershell
.\Run-EL082-Sandbox.ps1
```

### Production Deployment:
```powershell
# Fix file names first, then:
.\Publish-EL082-Pack.ps1 -MapNow -InstallDefaultAtLogon -PauseAtEnd
```

### Check File Names:
```powershell
Get-ChildItem *.csv
```

### Verify Target Connectivity:
```powershell
Test-Connection -ComputerName "WEL082MST051" -Count 1
```
```

## Summary

The issue you're experiencing is a **file naming mismatch**. Your CSV files have the extra "EL082_" prefix that the script doesn't expect. 

**Quick fix**: Rename your files to match what the script expects:
```powershell
Rename-Item "EL082_el082_printers.csv" "el082_printers.csv"
Rename-Item "EL082_el082_defaults.csv" "el082_defaults.csv"
```

Then run your deployment:
```powershell
.\Publish-EL082-Pack.ps1 -MapNow -InstallDefaultAtLogon -PauseAtEnd
```

This should resolve the "Missing required file" error and allow your printer mappings to deploy successfully. 