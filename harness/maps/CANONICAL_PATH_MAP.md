# Canonical Path Map

This map prevents a fresh agent from treating "a checkout that exists" as "the checkout that owns development" or "the runtime the operator actually uses."

## Canonical owner

Read `harness/api/canonical-path-registry.json` before choosing a repository directory, creating another clone, preparing a worktree, resolving an installed runtime, or emitting an operator path.

## Windows development profile

| Role | Canonical path | Meaning |
|---|---|---|
| Development checkout | `%USERPROFILE%\Desktop\Dev\SysAdminSuite` | Normal mutable SysAdminSuite development checkout. |
| Temporary worktrees | `%LOCALAPPDATA%\SysAdminSuite\worktrees` | Collision-isolated Git worktrees; never a second canonical clone. |
| Ephemeral acquisition | `%LOCALAPPDATA%\SysAdminSuite\closeout-entry-*` | Temporary acquisition only. Current `main` here does not promote it to canonical development. |
| Production/use path | not applicable | Use a product/field profile when an installed or served runtime exists. |

## Windows Admin Box profile

| Role | Canonical path | Meaning |
|---|---|---|
| Development checkout | `%USERPROFILE%\Desktop\Dev\SysAdminSuite` | Repository development and maintenance authority. |
| Temporary worktrees | `%LOCALAPPDATA%\SysAdminSuite\worktrees` | Safe parallel-writer isolation. |
| Production/use path | `C:\SASAL` | Short sealed AutoLogon field runtime. It is not the full development checkout. |
| Real operator authority | `harness/api/operator-execution-route-registry.json` | Selects the registered operator front door and resolves the installed runtime/checkout. |
| Sealed AutoLogon entrypoint | `C:\SASAL\Bootstrap-SysAdminSuiteAutoLogon.cmd` | Protected-runtime entrypoint when the owning seal/manifest proof is current. |

## Four proof states

Never collapse these states:

1. `remote_default_contains_sha` — remote default branch contains the commit.
2. `canonical_development_checkout_current` — the registered development checkout is intentionally on that commit.
3. `production_use_path_current` — the registered installed/field runtime was actually updated and verified.
4. `operator_entrypoint_observes_current` — the real operator entrypoint resolves the intended current runtime.

A GitHub merge proves only state 1. A fresh clone under AppData may prove that clone has the commit, but it proves neither state 2 nor state 3.

## Path-sprawl rule

Do not solve a stale or dirty canonical checkout by creating another mutable clone and silently using it forever. Preserve unique work. If another writer needs isolation, use a Git worktree under the registered temporary worktree root. Ephemeral acquisition checkouts are disposable routing aids, not path authorities.

## PowerShell copy/paste trap

PowerShell `else` belongs to the same parsed statement as its `if`. If an operator instruction uses control flow, provide the complete block in one paste submission:

```powershell
if ($condition) {
    Do-Something
} else {
    Do-SomethingElse
}
```

Do **not** send the `if { ... }` block first and `else { ... }` as a later command. A standalone `else` is parsed as a command name and fails.

## Workflow chain

```text
fresh-agent-intake
  -> canonical-path-resolution
     -> repository-freshness-before-launch (when remote freshness is required)
     -> operator-execution-route (when a real operator command is required)
```

Path selection creates no product or target authority.
