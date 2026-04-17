# Taskbar pins vs Public Desktop shortcuts

`Deploy-Shortcuts.ps1` copies shortcut files (for example `.lnk`) to `C:\Users\Public\Desktop` on target PCs. That makes icons available to every user on that machine, but it does **not** pin anything to the taskbar.

## Why taskbar pinning is different

Windows treats the taskbar as a per-user shell surface. Copying a shortcut to the Public Desktop does not add a pin next to Start. Fleet-wide “always show Microsoft Teams on the taskbar” usually requires one of these approaches:

1. **Mobile device management / Group Policy**  
   Use the controls your organization already has for Start layout or app defaults (product-specific; paths change between Windows releases).

2. **Default user profile / provisioning**  
   Some environments use `LayoutModification.xml` under the default user profile so **new** profiles get a chosen layout. This is an imaging or build-time concern, not something a one-off SMB file copy replaces.

3. **Per-user scripting**  
   Automating “pin to taskbar” from a logon script is fragile across Windows versions and is often blocked or discouraged by Microsoft. Prefer policy or a supported layout mechanism instead.

## Practical split for this repo

- Use **Deploy-Shortcuts** (or your future file share) for **Public Desktop** Teams and other shortcuts so users can launch apps consistently.
- Align with your **platform team** on **one** supported method for default taskbar or Start layout if pins are mandatory.

This avoids unsupported hacks while keeping desktop coverage predictable.
