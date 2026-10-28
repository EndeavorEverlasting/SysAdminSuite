# Windows Setup / OOBE -> UEFI BIOS (Dell QCM1250 and other supported PCs)

**Owner:** SysAdminSuite Field Workflow. **Use case:** regain firmware setup from Windows installation/OOBE *before the Windows desktop exists*. **Support-PC entrypoint:** `Open-WindowsSetupBios.cmd`.

## At the Windows Setup screen on the TARGET

1. Confirm this is the right computer and that restarting it is approved. The command reboots **immediately**.
2. Press **Shift + F10** to open **Command Prompt (CMD)**. If function keys require Fn, use **Shift + Fn + F10**. This is **not** the desktop's Win+X administrator terminal.
3. Enter the following command, or scan the QR from the SysAdminSuite helper:

   ```cmd
   shutdown /r /fw /t 0
   ```

4. Press Enter; confirm the next boot actually shows BIOS/UEFI Setup. Do not mark success on a restart alone.

## QR/display-assisted technician workflow

On a separate **approved/current SysAdminSuite support workstation**, double-click `Open-WindowsSetupBios.cmd`. It delegates to the existing `Run-FieldHotfixesGui.cmd` and selects `configs/hotfix-commands/windows-setup-uefi-bios.json`, displaying the reviewed **CMD Shift+F10** payload. It **never** restarts the support workstation. Scan the payload into the target's Setup CMD window, then press Enter if the scanner does not send Enter.

If the GUI's QR image is unavailable because `lib/QRCoder.dll` is missing, read the command on screen or use the exact one-liner above. An offline technician cannot depend on fetching GitHub during Windows Setup; distribute the approved/certified helper from the support environment.

## Failure decision tree

| Symptom | Next action |
| --- | --- |
| No desktop or Settings, Windows installation still running | Use the target-side **Shift + F10**, not Win+X. |
| Shift + F10 does nothing | Try Shift + Fn + F10. Some Windows Setup configurations disable the diagnostic prompt; stop trying shell workarounds and use the hardware key. |
| `shutdown` errors, the firmware redirect is unsupported, or the PC restarts to Setup again | Restart normally and tap **F2** at the Dell logo to enter BIOS. On supported Dell systems, **F12** may show a One Time Boot menu with BIOS Setup. |
| BIOS appears | Record `BIOS_OBSERVED`; make only the separately approved firmware changes, if any. |
| Only a restart occurred, or outcome is unknown | Record `RESTART_ONLY` or `UNVERIFIED`; do not close as a successful BIOS entry. |

**Do not confuse this with the separate Cybernet setup-error completion-flag repair**, which uses a registry write. This procedure has **no registry edits, reinstall, network changes, and no automatic BIOS configuration**.

## Repeatability and proof

- This documented operator journey is device-/site-independent; the validated model-specific fallback here is Dell Pro Micro QCM1250 (F2).
- The reviewed QR source is the **versioned JSON manifest**, not a transcription from a ticket. The existing Field Hotfixes GUI reads the manifest selected by the CMD front door.
- Capture the exact result privately: `SHELL_OPENED`, `UEFI_REDIRECT_ACCEPTED`, `BIOS_OBSERVED`, `HARDWARE_F2_USED`, or `BLOCKED`. A command accepted is **not** a BIOS-observed result. Keep device IDs, technician identities and any client incident information out of the public repo.
- Test static controls with `python -m pytest Tests/survey/test_windows_setup_bios_field_contracts.py`. A field technician's observed success on one device does not certify every Windows build or Dell model.

## Vendor references

- Microsoft Windows Setup `/DiagnosticPrompt` (Shift+F10): https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options
- Microsoft `shutdown` (`/r /fw /t`): https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/shutdown/
- Dell QCM1250 model manuals: https://www.dell.com/support/product-details/en-ms/product/dell-pro-qcm1250-micro/resources/manuals

**Routing terms for agents:** `Dell QCM1250 BIOS`, `Windows setup BIOS`, `OOBE firmware`, `Shift+F10`, `shutdown /r /fw /t 0`, `pre-desktop Command Prompt`. Follow this SysAdminSuite authority and the Field Workflow skill before offering Windows desktop instructions.
