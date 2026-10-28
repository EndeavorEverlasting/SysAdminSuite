# Start here: BIOS/UEFI access from Windows Setup

**First answer for a technician at Windows installation/OOBE:** press **Shift+F10** (or **Shift+Fn+F10**), then type `shutdown /r /fw /t 0` and press Enter. This immediately restarts the target toward UEFI firmware; verify that the BIOS menu actually appears.

**No desktop required.** Do not send a technician to Win+X, Windows Settings, or an administrative PowerShell window when Windows is not configured yet.

For a scannable QR and confirmation checklist on a separate support PC, double-click **`Open-WindowsSetupBios.cmd`** in the approved SysAdminSuite checkout. It displays the command but does not restart the support PC.

If the shell is disabled, the command is refused, or redirection fails, **restart and tap F2 at the Dell QCM1250 logo**. The longer failure tree, safe proof states, references and agent keywords live at [docs/field/WINDOWS-SETUP-UEFI-BIOS.md](docs/field/WINDOWS-SETUP-UEFI-BIOS.md).

**Canonical owner:** SysAdminSuite. This is a general field procedure, not a client-specific workaround and not the unrelated Cybernet registry setup-loop hotfix.
