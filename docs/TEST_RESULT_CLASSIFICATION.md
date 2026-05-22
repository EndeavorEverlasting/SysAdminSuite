# SysAdminSuite Test Result Classification

## Purpose

Use this guide when reviewing field results so the repo does not confuse environment failures with product failures.

A result is only a product failure when the environment is valid for the feature being tested.

## Classification table

| Classification | Use when | Product bug? | Next action |
| --- | --- | --- | --- |
| `OK_LOCAL_SMOKE` | App launches, local task executes, or artifact is generated without network dependency | No | Proceed to network preflight |
| `ENVIRONMENT_BLOCKED_GUEST_NETWORK` | Host is on guest network and internal DNS/ports/UNC fail | No | Move to correct network and retest |
| `ENVIRONMENT_BLOCKED_POLICY` | Execution policy, AppLocker, admin rights, antivirus, EDR, or endpoint controls block the run | Not by default | Document policy and pivot runtime path if needed |
| `NETWORK_PREFLIGHT_FAILED` | Host claims correct network but DNS, SMB, RPC, or print server reachability fails | Not by default | Fix network/access posture first |
| `PRODUCT_FAILURE` | Supported environment passes preflight, but SysAdminSuite logic fails | Yes | Open bug or PR with reproducible evidence |
| `INCONCLUSIVE` | Output lacks command, network posture, environment, artifact, or raw error | Unknown | Retest with full evidence |

## Evidence minimum

Capture this before marking anything as a product failure:

```text
Date:
Tester:
Branch/commit:
Machine hostname:
Network posture: guest / enterprise wired / enterprise Wi-Fi / VPN / lab
Elevation: yes/no
PowerShell version:
Command executed:
Raw output:
Artifacts generated:
Classification:
Expected behavior:
Actual behavior:
```

## Field rule

If the device is on guest network, offline printer/network results are expected. Guest network results may prove local launch behavior, but they do not validate printer mapping, UNC access, RPC, DNS, AD, or internal print-server reachability.
