# Native Linux WezTerm → tmux host

This lane configures a native Linux desktop as `WezTerm → local tmux dev → native agent wrappers`. It does not use WSL, Windows bridges, automatic authentication, or whole-dotfile replacement.

## Commands

```bash
# Read-only plan (default)
scripts/install-sas-linux-tmux-workspace.sh

# Explicit configuration; add --install-missing only for approved distro packages
scripts/install-sas-linux-tmux-workspace.sh --apply

scripts/start-sas-linux-tmux-workspace.sh --launch-gui
scripts/get-sas-linux-tmux-workspace-status.sh
scripts/stop-sas-linux-tmux-workspace.sh
scripts/repair-sas-linux-tmux-workspace.sh --apply
scripts/rollback-sas-linux-tmux-workspace.sh --apply
```

Apply backs up `.wezterm.lua`, `.bashrc`, and `.tmux.conf`, writes separate managed fragments, and inserts bounded include blocks. Rollback restores the manifest-recorded originals. Start refuses nested tmux and disables Windows agent bridges.

## Proof ceiling

The tracked fixture matrix proves configuration composition, preservation, idempotent lifecycle state, typed failures, and rollback. The current development host is Windows; running these fixtures under WSL is not native-Linux GUI proof. A native Linux desktop with WezTerm is still required for Sprint 11 live validation.
