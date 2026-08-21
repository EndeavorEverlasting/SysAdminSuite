# Active Directory tools

SysAdminSuite keeps Active Directory **group membership** and **OU placement** as separate operations. Do not substitute one for the other.

## Group membership

`Add-Computers-To-PrintingGroup.ps1`

- Adds computer objects to an explicitly named AD security group.
- Preserves the repository's historical rule that this group tool does **not** move OU objects.
- Generates group-membership undo evidence.

## OU placement

`Move-Computers-To-OU.ps1`

- Plans computer-object placement into an explicitly supplied approved managed OU.
- Mutation requires `-Apply` and `-AuthorizationReference`.
- Defaults to a one-computer live-change ceiling.
- Rejects legacy workstation OU paths and permits only current managed workstation roots.
- Uses ObjectGUID identity, checks source drift immediately before mutation, verifies the new OU after mutation, and stops later changes after the first failed move.
- Generates `Undo-OUMove.ps1` only for verified moves; rollback refuses to overwrite a later OU change.
- Stores live run evidence outside the repository under the operator's local SysAdminSuite cache.

Administrator pilot sequence and exact proof gates: [`../docs/ACTIVE_DIRECTORY_OU_MOVE_PILOT.md`](../docs/ACTIVE_DIRECTORY_OU_MOVE_PILOT.md).

The non-technical CMD/tutorial layer is intentionally deferred until a real one-host move + rollback and a bounded batch are field-proven.
