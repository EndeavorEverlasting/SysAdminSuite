# Final-gate path-budget PR proof

This stacked change is intentionally based on the stage-4 branch after the protected field run proved baseline capture and baseline eligibility. It owns only stage-6 final-step gate local evidence placement and the protected-runtime repair for that file.

The field failure class is a local Windows path-budget problem: the final gate attempted to create a roughly 270-character `autologon_final_step_gate.json` path before any package hash, target staging, S4U probe, installer execution, after-state capture, or reboot.

The implementation preserves the existing nested result layout for normal paths, compacts only when the nested result exceeds 240 characters, refuses any different-run compacted-file collision, and fails closed if even the compacted file exceeds the budget.

Protected-runtime repair remains local-only: no Git command, network request, target contact, target mutation, credential handling, package execution, or reboot behavior is introduced by the repair utility.
