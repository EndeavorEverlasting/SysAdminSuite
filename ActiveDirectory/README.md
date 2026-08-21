# Active Directory tools

SysAdminSuite keeps Active Directory **group membership**, **OU/policy discovery**, and **OU placement** as separate operations. Do not substitute one for another.

## Group membership

`Add-Computers-To-PrintingGroup.ps1`

- Adds computer objects to an explicitly named AD security group.
- Preserves the repository's historical rule that this group tool does **not** move OU objects.
- Generates group-membership undo evidence.

## OU and policy discovery

`Probe-ComputerOuPolicy.ps1`

- Reads the current parent OU/container for explicitly supplied computer objects.
- Searches Group Policy by an explicit keyword; the SAS field route uses `Imprivata` by default.
- Inspects matching GPO reports for link scopes and checks each computer OU for direct/inherited matching GPO links.
- Resolves GPO canonical link paths back to readable OU distinguished names when possible.
- Writes `Probe.json`, `Computers.csv`, `PolicyLinks.csv`, and ticket-ready `TicketNotes.txt` below the operator-local SysAdminSuite evidence root.
- Performs no `Move-ADObject`, GPO mutation, or group-membership mutation.
- A uniquely resolved policy-linked managed OU is **candidate evidence only**. It is not authorization, does not automatically select a move target, and does not prove that OU placement alone installs/configures the application.

SAS routes:

- `sas ad ou probe HOST01 [HOST02 ...]` — read-only OU + Imprivata GPO evidence.
- `sas ad ou plan HOST "TARGET_OU_DN"` — calls the existing OU engine without `-Apply`.
- `sas ad ou apply HOST "TARGET_OU_DN" CHANGE_REFERENCE` — calls the existing guarded one-host apply path. Organizational approval remains external to SysAdminSuite.

The SAS router does not expose batch Apply. The administrator pilot/rollback proof ceiling below remains authoritative.

## OU placement

`Move-Computers-To-OU.ps1`

- Plans computer-object placement into an explicitly supplied approved managed OU.
- Mutation requires `-Apply` plus `-ChangeReference`; the reference is recorded for audit/traceability and does not validate an external ticket/change system or grant AD privileges.
- Organizational approval must exist independently before Apply or rollback; AD delegation/permissions remain the technical privilege boundary.
- Defaults to a one-computer live-change ceiling.
- Rejects legacy workstation OU paths and permits only current managed workstation roots on complete DN component boundaries.
- Uses ObjectGUID identity, checks source drift immediately before mutation, verifies the new OU after mutation, and stops later changes after the first failed move.
- Generates `Undo-OUMove.ps1` only for verified moves; rollback refuses to overwrite a later OU change.
- Stores live run evidence outside the repository under the operator's local SysAdminSuite cache.

Administrator pilot sequence and exact proof gates: [`../docs/ACTIVE_DIRECTORY_OU_MOVE_PILOT.md`](../docs/ACTIVE_DIRECTORY_OU_MOVE_PILOT.md).

The non-technical CMD/tutorial layer is intentionally deferred until a real one-host move + rollback and a bounded batch are field-proven.
