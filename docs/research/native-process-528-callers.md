# P95 caller audit — native-process evidence #528

Inspection floor: `76a4caf2db769a156765d5a1d74e2d0c795978f7`; branch `codex/native-528-callers-research`. Scope is the Android lifecycle and operator Git refresh adapters. Only this audit is owned. Android Apply, installation, emulator/ADB, devices, S4U production, DTop and unrelated PRs are excluded. This is source/history and harmless local regression evidence, not toolchain installation or qualified-device proof.

## Actual call stacks and result ownership

* `Manage-AndroidToolchain.cmd:8` selects Windows PowerShell 5.1 and sibling bootstrap; `scripts/Start-SasAndroidToolchain.ps1:3-7` resolves registered canonical development checkout then invokes the current engine. `scripts/Invoke-SasAndroidToolchain.ps1:99-115` uses the existing AndroidProvider source admission subprocess and restarts once when freshness updates source. The process seam must preserve **stdout-only plain string**: line 108 assigns `result.source`, line 109 parses JSON while schema `schemas/harness/android-toolchain-result.schema.json:17` allows string/null, not parsed object. Stdout/stderr log paths, executable, arguments and exit evidence belong to private `result.checks`; final BLOCK/reasons and receipt JSON depth12 belong to engine lines 250-256.
* Android `Invoke-Bounded:29-65` quotes arguments, rejects embedded quotes, scopes WindowsPS-compatible PSModulePath only around child start, gives CMD `/d /s /c` nested quoting and rejects shell operators/expansion, redirects two streams separately, captures Handle before wait, checks nonzero/null exit, classifies actionable diagnostics, and returns only stdout. Timeout (48-52) invokes exact PID tree taskkill and records `timed_out`; it does **not** record cleanup success or await taskkill under a second independent timeout. Output files are private retained evidence. Handle/process disposal is absent. Default timeout1800 (parameter12), source/provider120, emulator queries15.
* `scripts/Refresh-SasOperatorCommand.ps1:55-106` invokes resolved Git directly, with optional `-C Root`, stderr file and `ErrorActionPreference=Continue`, captures `$global:LASTEXITCODE` immediately, restores preference, deletes stderr tempfile, throws annotated nonzero failure or returns stdout **line collection**, optionally displaying both streams. `Get-SasRefreshGitScalar:108-117` owns empty scalar rejection. This wrapper has **no timeout/process-tree contract**. Network GUEST_INTERNET admission at188 precedes remote Git; ref validation194, clone201, fetch218, object completeness repair220, detached field-ready checkout238-240, recheck network287-290, installer and seal315 onward remain domain owners. Do not change network/source admission when factoring process mechanics.

## Four real post-feature fixes

| Merged change | Failure and exact current seam | Regression evidence |
|---|---|---|
| #524 `84209d3d6b910e8972ff78e48fdaa4f5f18dcc39` | WindowsPS5.1 lost Start-Process ExitCode unless Handle retained before waiting; Handle47, explicit null exit58 | `test_windows_powershell_owned_subprocess_exit`: zero exit and nonzero7 through extracted production function |
| #525 `f9c2fd03` | Get-Content decorated string leaked PSProvider metadata into deep receipt; string flattening64 | same test serializes depth12, rejects PSProvider and excessive size; this commit also briefly changed source to parsed object |
| #526 `17bda839` | Parsed source object contradicted registered string/null schema; keep result.source text108, parse into sourceState109 | exact source-is-string assertion; schema fixture validation is optional if jsonschema absent |
| #527 `846e8c1b00cf12134574d06ab0ddf071832c7024` | Single-argument String.Concat with empty Get-Content output ambiguous; explicit empty string plus cast64 | same test silent successful child and CMD wrapper path containing spaces |

Historical commits were inspected with `git show`, not inferred from PR title alone. #523 initial feature is `b043a3e8`. No historical private runtime receipts were imported into this tracked audit.

## Shared primitive comparison

`scripts/SasBoundedNative.psm1` exports `Invoke-SasBoundedNative(FilePath,Arguments,TimeoutSeconds1..300)` and `Invoke-SasBoundedPowerShell(ScriptText,TimeoutSeconds1..300)`. Native currently creates encoded WindowsPS5.1 child, invokes native with `2>&1` under Stop, stringifies combined output, returns structured output/error/exit/timing/tree/reconciliation object. AutoLogon S4U recognition and finite exact-task Query reconciliation belong to its native wrapper; never replay Create. A direct Android replacement is unsafe without adapter/seam work:

1. Combined stderr contaminates source JSON and changes Java stderr-only success semantics; PS5.1 NativeCommandError under Stop needs a real negative control.
2. Timeout ceiling300 excludes Android build/acquisition1800. Raising all domain timeouts casually changes S4U/network bounds.
3. Android needs separate persisted output files plus actionable classification and scoped child environment; shared output is memory strings. A structured object cannot flow into string/null receipt without explicit projection.
4. CMD nested quoting behavior is caller-specific and currently tested; shared native string[] splatting is another WindowsPS parsing path requiring exact batch coverage.
5. Git requires line collection, immediate automatic native exit evidence, quiet/diagnostic display and `-C`; bounded typed result could be projected by its adapter, but timeout would be new behavior needing deliberately chosen per-operation policy.
6. S4U remote timeout uncertainty is not generic execution retry. New generic process primitive must not gain target, task or reconciliation policy.

Three decision options remain valid: direct module reuse with explicit adapters **only after** stream/timeout equivalence proof; narrow generic typed process seam in existing owner leaving native S4U adapter intact; or separate engines with small common evidence contract/tests. A typed result alone does not cure duplicated launch/exit bugs. Lowest-coupling candidate is a new narrow interface within existing module, preserving its current exports, with one consumer adapter selected by P95. This is a candidate, not approval or implementation.

## Coverage, negative controls and decision questions

Existing Python fixture suite proves prerequisites/reason propagation and pure host-authority gate, not actual network/download/license/emulator failure mechanics. Its Windows test extracts real production Invoke-Bounded via AST; it proves stdout plain type, zero/nonzero, empty output and CMD spaces under5.1. It does not currently exercise stderr-only success, unicode, output saturation, timeout cleanup, missing executable, actual source schema admission, or adapter PS7 runtime parity. CI android-toolchain workflow invokes Python on windows-latest; new module/test paths must be added to path filters if selected.

Git standalone regression extracts production function, invokes real read-only check-ref-format, silent ref validation, then missing ref raw negative control exit128 and verifies same nonzero survives helper. No full refresh/network/seal action runs. Test message says5.1 even when executed with7; record actual invoking shell independently.

P95 should decide: Which consumer has the smallest changed semantic surface? Can stdout/stderr remain separate with ordinary strings and explicit unavailable-exit failure? What timeout and owned-tree teardown facts are guaranteed versus attempted? Does environment scoping belong solely to Android adapter? How are batch argv, empty strings, quotes and unicode transported under5.1/7? Can old S4U tests remain unchanged and prove no Create replay? Preserve #522 independent qualification blocker; neither installed SDK ADB nor computed archive hash supplies authority.

## Executed validation

* `powershell.exe -NoProfile -File Tests/PowerShell/SasOperatorRefreshNativeStderr.Tests.ps1`: exit0, successful/silent cases and raw missing-ref negative control exit128; helper preserved failure.
* `pwsh.exe -NoProfile -File Tests/PowerShell/SasOperatorRefreshNativeStderr.Tests.ps1`: exit0, same negative control128; this is actual PowerShell7 execution despite fixed5.1 success message.
* Python toolchain fixture execution result is recorded after completion below.
* Worktree normal status initially reported deep archived VBS modifications; `git -c core.longpaths=true status --short` was clean. No unrelated files reset or staged.

Skipped: Android Apply/Verify, GUI launch, Gradle, emulator, ADB, full operator refresh and S4U live execution because this lane is source/harmless regression only. No installation, source qualification, device or production claim.
- `python.exe Tests/survey/test_android_toolchain_contracts.py`: exit0, seven groups passed including 20 synthetic fixture scenarios and actual WindowsPS5.1 harmless child process checks. No skip in the Windows-specific group; jsonschema validation remains conditional on dependency availability.
