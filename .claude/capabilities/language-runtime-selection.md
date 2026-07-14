# Language Runtime Selection Capability

## Contract

Choose the implementation surface from the workflow and operating environment, not from a blanket language preference.

## Selection rules

- Northwell-targeted survey, audit, transport, target-intake, and preflight work is Bash-first on Windows, usually Git Bash or MSYS2 Bash.
- Bash-on-Windows may call Windows-native executables such as `cmd.exe`, `hostname.exe`, `ping.exe`, `nslookup.exe`, and `netsh.exe`.
- Windows-native operations involving WMI/CIM, PnP devices, registry, services, printer queues, Active Directory, COM ports, scheduled tasks, or deployment are valid PowerShell work.
- Managed dashboard or host changes belong in the existing .NET solution when that is the current implementation surface.
- Linux-native commands are quick fallbacks only when the actual environment supports them.

## PowerShell preservation

PowerShell files are active production-relevant tooling. Do not delete, truncate, label as dead, or silently deprecate `.ps1`, `.psm1`, or `.psd1` files because a Bash path exists.

When replacing or supplementing a capability:

1. preserve the existing PowerShell surface unless retirement is explicit;
2. add the new surface separately;
3. document the mapping and compatibility boundary;
4. update affected tests, docs, launchers, and generated commands.

## Conflict resolution

“Bash-first” governs suitable new Northwell field workflows. It does not prohibit explicit PowerShell work or Windows-native capabilities. A skill with a narrower operating context may choose PowerShell while preserving the Bash-first survey posture.

## Used by

- `.claude/skills/language-runtime/SKILL.md`
- `.claude/skills/field-workflow/SKILL.md`
- `.claude/skills/survey-low-noise/SKILL.md`
