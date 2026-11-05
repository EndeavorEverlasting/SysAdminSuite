# ScanSnap multimodal deployment continuation

**Status:** durable execution plan after PR #510  
**Base:** `main@1b2b86bde7003531ff2b40b79354e957804ab0dd`  
**Control host:** Admin Box 1 = `LPW003ASI173`  
**Home/lab target:** PTop = `CheexMcClappeth`  
**Priority field targets:** `WRH250STR001`, `WRH250STR002`  
**Retired target:** `LPW003ASI105` — do not reintroduce.

## Prompt invocation provenance

This continuation is factored under:

- **P04 — Repo-Aware Sprint + Harness Factoring Distributor**
  - canonical owner: `EndeavorEverlasting/TokenCorridor`
  - registry: `src/tokencorridor/interface/promptkit/registry/base/prompts.json`
  - source blob: `848728632c1243ebba023fa0012292a2ad33cada`
- **P82 — Prototype-Measure-Refine Delivery Loop**
  - canonical owner: `EndeavorEverlasting/TokenCorridor`
  - registry: `src/tokencorridor/interface/promptkit/registry/prompts/spec-architecture-prompts.v1.json`
  - source blob: `5926a198a14567de55110ed19e922fc444b4dec7`

P04 owns factoring, durable repository context, collision avoidance, and execution placement. P82 owns each empirical network/package experiment as **HYPOTHESIS -> BUILD -> MEASURE -> CRITIQUE -> DECIDE**.

## Proven deployment factory successor

The implementation successor for this multimodal plan is:

- `docs/SCANSNAP_PROVEN_DEPLOYMENT_FACTORY_PLAN.md`
- `docs/handoff/SCANSNAP_ONE_PASS_CURSOR_HANDOFF.md`

The decisive factoring rule is now settled: ScanSnap owns web package acquisition/binding and mode-aware target resolution, while remote staging, hash verification, SYSTEM Task Scheduler execution, package validation, result retrieval, and teardown converge on the existing canonical SysAdminSuite software-deployment factory in `scripts/SasSoftwareDeploymentAdapter.psm1`.

Do not maintain the bespoke ScanSnap remote-install lifecycle as a parallel production engine after the canonical delegation is proven.

## User outcome

Deploy the requested ScanSnap application to the two field hosts. Home-network PTop testing is useful but is **not a release gate** and must not consume the critical path if it cannot be made useful quickly.

The package is Internet-sourced for this application. It is **not** sourced from the internal Northwell software directory used by some prior deployments.

The durable workflow must support more than one network posture without forking separate deployment architectures.

## Non-negotiable unattended deployment invariant

The normal field deployment path is **controller-initiated, remote, unattended, and independent of physical workstation location**.

A deployment target is selected by its authorized logical identity (hostname/FQDN and the domain/network records that resolve it), not by a technician physically locating the device.

The workflow must support deployment when:

- no user is logged on;
- a user is logged on but must not interact;
- the workstation is in a locked room, cart, closet, clinical area, or otherwise physically difficult to locate;
- nobody is standing at the target;
- deployment occurs overnight;
- the technician knows the authorized hostname but not the workstation's physical location.

The standard path must **not** require target-side clicks, interactive approval, local console access, target-side credential entry, or a person physically present at the workstation.

"Identity binding" in this document means controller-side resolution and authorization of the intended remote computer identity. It does **not** mean physical discovery or user-assisted pairing.

If a transport requires target-side interaction, classify it as unsuitable for the unattended production path unless there is a separate, explicitly approved bootstrap phase. Do not let a lab-only limitation weaken the production requirement.


## Separate the two axes

Do not conflate package acquisition with target transport.

### Axis A — package acquisition

`INTERNET_PACKAGE_PREP`

- obtain the exact authorized ScanSnap installer from an official vendor source or already-authoritative client source;
- record source identity/version when observable;
- compute SHA256;
- establish actual silent-install behavior and detection contract;
- bind `package.manifest.json`;
- perform no field-target mutation.

This can happen while the Admin Box has ordinary Internet access. The installer then travels with the bounded ScanSnap package for target staging.

### Axis B — target execution posture

The same deployment package/front door should adapt to these tested execution modes:

| Mode | Purpose | Authority / identity model | Release importance |
|---|---|---|---|
| `LAB_LOCAL` | last bounded home-network prototype against PTop | exact known target `CheexMcClappeth`; short name / `.local` / runtime-resolved IP; explicit local-admin SMB auth where required | diagnostic only |
| `NORTHWELL_PROTECTED` | direct field deployment on Northwell LAN/WAB | reuse `Get-SasNorthwellNetworkAuthority`; Kerberos/domain identity; short host or canonical FQDN | primary |
| `NORTHWELL_VPN` | off-path field deployment over authenticated corporate VPN | `DomainAuthenticated` protected route; corporate DNS/FQDN; same SMB + Task Scheduler transport | primary |
| `UNKNOWN_BLOCKED` | insufficient authority/identity | no mutation | fail closed |

Do not create a new network-authority subsystem. Reuse the existing repository contracts in `scripts/SasNorthwellNetworkAuthority.psm1`, `scripts/SasNetworkGuard.psm1`, `Config/NETWORK_GUARD_README.md`, and `docs/SOFTWARE_DEPLOYMENT_LOW_NOISE.md`.

## Authoritative topology

```text
CONTROL
LPW003ASI173  (Admin Box 1)

LAB_LOCAL
LPW003ASI173
    -> CheexMcClappeth
       aliases may include CheexMcClappeth.local and a runtime-resolved DHCP IPv4
       do not hard-code the current home IPv4 into the durable target contract

NORTHWELL_PROTECTED / NORTHWELL_VPN
LPW003ASI173
    -> WRH250STR001
    -> WRH250STR002
```

The field hostnames are authoritative deployment targets. The lab target is not a substitute for them.

## Current evidence floor

PR #507 implemented the ScanSnap package. PR #510 improved access classification.

Proven on the home LAN:

- Admin Box local IP observed as `192.168.1.88`.
- PTop responded at `CheexMcClappeth` / `192.168.1.79` during the prior run.
- `nltest /dsgetdc:nslijhs.net` returned `ERROR_NO_SUCH_DOMAIN (1355)`.
- hostname C$ classified `AUTH_DC_UNAVAILABLE`;
- IP C$ classified `LOGON_FAILURE`;
- no live stage/task/install occurred.

Interpretation: the last run did **not** prove that PTop was absent. It proved target reachability but failed administrative authentication. The next lab experiment must identity-bind the candidate before mutation and must not rely on domain authentication on the home LAN.

## P82 experiment ladder

### E1 — exact-target LAB_LOCAL remote identity resolution

**Hypothesis:** Admin Box 1 can resolve and remotely address the intended PTop from its authorized logical identity on the home LAN without any target-side interaction or physical discovery.

**Build / probe only:**

- run from `LPW003ASI173`; record `$env:COMPUTERNAME` first and fail the lab lane if the controller is not the expected Admin Box unless an explicit test override already exists in repository policy;
- resolve `CheexMcClappeth`;
- test `CheexMcClappeth.local` only as an alias candidate;
- resolve or use the current IPv4 only as runtime evidence;
- compare returned address/hostname evidence;
- use exact-target tools only. No subnet scan.

**Measure:** produce one controller-side identity receipt that says whether short name, `.local`, and IPv4 converge on the same remote PTop identity. No target-side action is part of this proof.

**Decision:**

- KEEP when identity converges;
- REFINE once if one alias mechanism is stale but another exact identity is authoritative;
- DISCARD the lab lane if target identity remains ambiguous.

### E2 — LAB_LOCAL admin transport

**Hypothesis:** after exact identity binding, explicit PTop local-admin authentication can make SMB admin-share access ready without a Northwell DC.

Use the existing SMB/auth patterns in the repository. Do not use the Admin Box domain token as evidence that local PTop auth should work.

**Measure:** `ADMIN_SHARE_READY` to the exact bound PTop target.

**Decision:**

- KEEP and continue to package/live install if ready;
- if credentials are unavailable or rejected, record the typed result and end the lab experiment. Do not spend the field critical path repairing home-domain semantics.

This is the **last bounded home attempt**, not a required certification gate.

### E3 — Internet package qualification

**Hypothesis:** the required ScanSnap package can be acquired from an authoritative web source and bound without the internal Northwell software share.

- search existing client/repository evidence first for exact product/version;
- prefer official Ricoh/PFU/Fujitsu distribution evidence over mirrors;
- do not silently choose between ScanSnap Home / ScanSnap Manager or another product if the client request does not support the choice;
- download only once package identity is defensible;
- fingerprint type + SHA256;
- empirically establish silent arguments and detection;
- bind through `Bind-ScanSnapPackage.ps1`.

**Measure:** `Bound=true` plus real SHA256, silent args, and detection evidence.

### E4 — protected Northwell target readiness

**Hypothesis:** the existing SysAdminSuite protected-network authority + low-noise SMB/Task Scheduler path can reach the two exact field targets without a ScanSnap-specific transport fork.

Run on the protected network with the exact target set:

- `WRH250STR001`
- `WRH250STR002`

Reuse current authority and low-noise contracts. For short hostnames, derive/confirm the current domain suffix before constructing an FQDN; `nslijhs.net` is known repository context but FQDN use should still be evidenced in the active session.

**Measure per target:**

- protected network authority;
- exact hostname/FQDN resolution;
- CIFS/SMB readiness;
- admin-share authorization;
- scheduled-task readiness as required by the current transport;
- no broad scanning.

### E5 — field live deployment

When the package is bound and one protected mode reaches the target:

```text
PACKAGE_VALIDATED
-> PROTECTED_NETWORK_AUTHORIZED
-> TARGET_IDENTITY_BOUND
-> ADMIN_SHARE_READY
-> STAGED
-> TASK_EXECUTED
-> INSTALLER_COMPLETED
-> DETECTION_HIT
-> INSTALLATION_DETECTED
```

Run `/WHATIF` first when the final field transport has not yet been classified. Then deploy live.

Home PTop success is useful evidence, but **field deployment does not wait for PTop** if protected Northwell/VPN readiness is available.

## CMD convergence requirement

Do not ship one-off successful shell commands as the final interface.

The existing `Deploy-ScanSnap.cmd` remains the preferred front door. After experiments select the working behaviors, promote them behind that front door (or the repository's stronger canonical `sas` deployment front door if current factoring proves that is the correct owner).

Desired external behavior:

- one exact target list;
- explicit or deterministically inferred execution posture;
- package binding remains independent of network posture;
- target identity resolution is mode-aware;
- protected Northwell modes consume existing network-authority contracts;
- lab mode is explicitly bounded to the authorized PTop test target;
- logs record mode, controller host, requested target, resolved target, auth route, and proof ceiling;
- no successful prototype remains only in operator history.

Do not prematurely invent `/MODE` syntax if the repository already has a stronger command-routing convention. Inspect first; implement the smallest compatible surface.

## P04 factoring

### Lane A — package provenance / bind
Independent until live installation. Owns official web source, installer identity, SHA256, silent args, detect contract, manifest binding. Must not mutate remote targets.

### Lane B — final LAB_LOCAL experiment
Owns controller-side PTop resolution/addressability + remote local-admin SMB proof. It must remain fully unattended from the target's perspective. Must not touch field hosts. Stop after one materially informative experiment cycle if it cannot reach `ADMIN_SHARE_READY`.

### Lane C — protected field transport
Depends on protected authority becoming available, not on Lane B success. Owns exact `WRH250STR001/002` readiness on Northwell LAN/WAB or VPN. Reuse existing authority/low-noise contracts.

### Lane D — deployment convergence
Depends on package bound + at least one protected target transport ready. Owns live install, detection, evidence, and promotion of proven behavior into the durable CMD/front-door contract.

Parallel width is at least 2 while package qualification and lab/field transport evidence are independent. Use actual available Cursor/local-agent execution adapters; do not make the operator shuttle independent lanes manually when the environment can dispatch them.

## Acceptance

- Repository records `LPW003ASI173` as Admin Box 1 for this workflow.
- Repository records `CheexMcClappeth` as the bounded PTop lab target.
- Repository records `WRH250STR001/002` as the priority field targets.
- Home LAN testing is diagnostic and explicitly non-blocking for field deployment.
- Web package acquisition is separate from target transport.
- Protected Northwell LAN/WAB and VPN are first-class deployment modes through existing authority contracts.
- Field deployment requires no user presence or physical target access; authorized logical identity + remote administrative transport are sufficient inputs.
- Each empirical uncertainty produces a P82 receipt and KEEP/REFINE/DISCARD decision.
- Working behavior is promoted into the repository CMD/operator surface with tests.
- Final field success requires `INSTALLATION_DETECTED`; transport/readiness alone is not completion.
