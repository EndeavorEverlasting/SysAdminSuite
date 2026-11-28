# Fan Control diagnostics: SysAdminSuite ownership

**Owner:** SysAdminSuite. **Purchasing and cooling SKU/price/cart decisions:** the operator's existing shopping repositories and original private ledgers, **not** SysAdminSuite. Read [machine route](../../harness/api/fan-cooling-task-ownership.v1.json) and invoke the read-only [route classifier](../../harness/api/sas_fan_cooling_route.py) when intent is ambiguous or mixed.

## Why this route exists

A Windows fan diagnostic must not be mistaken for a shopping workflow, and a shopping request must not be held hostage by troubleshooting a GUI. If a request includes both, split into independently progressing work products; share only vetted compatibility facts. The assistant/local agent must not hand an agent-capable GUI step to the operator just because an app icon or window is missing.

## Read-only diagnostic gate

1. Recover fresh target host profile, operating environment, installed fan-control software, process state, desktop session accessibility and available sensor APIs. An installed program or responsive process is **not** proof a GUI opened or a PWM control exists.
2. On an authorized Windows interactive host, use the local agent's GUI/computer-use facility to inspect existing windows and notification-area icons, and recover a hidden app window if feasible. Capture a local private screenshot; no raw host evidence in this public repository.
3. Read sensor and fan-header mappings first; distinguish CPU_FAN and case-fan channels from fan labels and observed behavior. Unknown or shared-hub mapping is `UNRESOLVED`; do not assume the physical rear fan has its own channel.
4. Only after separate operator authorization and verified mapping may a bounded controlled test modify **case** fan speed; restore on failure, timeout or temperature increase. Keep CPU fan on and protected. No stop command when the hardware does not confirm it is safe.
5. Report separate states: package installed, process responding, GUI observed, fan sensors exposed, channel identified, test executed, noise isolated. No skipped leap from installation to diagnosis or repair.

This guide defines behavior and expected proof, **not** an implemented Windows machine controller. No host program installation, settings change, fan speed change, or shopping checkout occurs by reading or running the classifier.

## Shopping boundary and nonblocking handoff

The shopping owner evaluates stock, SKU, width/depth, fan mounting clips, connector/ARGB standards, total delivered cost and return policy, and maintains `IN_CART`, `ORDERED`, `RECEIVED`, `INSTALLED`, `TESTED` independently. The SysAdminSuite agent may emit a sanitized statement such as "rear case fan not isolated; CPU cooler mounting unknown" and should not overwrite cart state. A discount does not authorize checkout, and unproven diagnostic hardware mapping does not prevent user-authorized conditional purchasing.

**Semantic regressions:** `python Tests/survey/test_fan_cooling_ownership_route.py`. Also run `python Tests/survey/test_agent_routing_manifest_contracts.py` after routing-manifest edits. Live Windows computer-use acceptance remains a separate host-local gate.
