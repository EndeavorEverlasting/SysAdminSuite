# implementation.ps1 — Usage examples for Publish-EL082-Pack.ps1
# This file is a reference template. Uncomment one of the invocations below
# to run it, or copy the command into your terminal.
#
# In the folder that contains this script + CSVs (+ helper scripts if needed):
# 1) Push CSVs only (most lightweight):
.\Publish-EL082-Pack.ps1 -PauseAtEnd

# 2) Push CSVs + kick machine-wide /ga mapping NOW (SYSTEM, one-shot, auto-deletes):
.\Publish-EL082-Pack.ps1 -MapNow -PauseAtEnd

# 3) Push CSVs + install per-user default script for future logons:
.\Publish-EL082-Pack.ps1 -InstallDefaultAtLogon -PauseAtEnd

# 4) Do everything in one go:
.\Publish-EL082-Pack.ps1 -MapNow -InstallDefaultAtLogon -PauseAtEnd
