# Chrome audio-session recovery — Windows 10/11

**Owner:** SysAdminSuite. **Agent orchestration:** MoonWake /sixth-gear. **Scope:** interactive-user Windows workstation; no organization-managed endpoint without separate authorization.

## Failure semantics

A running Chrome window is not sufficient to produce a row in Windows Volume Mixer. An inactive or player-muted YouTube Short may have no active stream. A missing row is not proof that Windows permanently lost Chrome identity. Other causes include Chrome session mute, zero volume, a nondefault output endpoint and website permissions.

Use the repo-owned Recover-ChromeAudio.cmd as the front door. With no arguments, it runs read-only Inspect and pauses at the result. From a command shell, pass Inspect explicitly for non-pausing inspection; pass Repair to explicitly unmute existing ACTIVE Chrome-owned sessions and raise only exactly-zero Chrome session volume to 25% by default. Existing nonzero Chrome levels, all other applications, master volume, devices, drivers and services are preserved. Missing/inactive Chrome sessions are never fabricated or automatically repaired.

Before either action, the launcher proves the Windows Desktop known-folder canonical Dev\SysAdminSuite checkout is clean on main, official origin, refreshed and current; it uses only a permitted clean fast-forward and will not switch a network. On protected or unknown network posture, a missing checkout or failed Git I/O, it fails closed without target audio changes. The caller must use the existing network-aware repository handoff before launching if InternetSync is not already available. The wrapper is username-agnostic and resolves scripts relative to itself, rather than relying on the current shell directory.

Receipts are written privately to %LOCALAPPDATA%\SysAdminSuite\Evidence\ChromeAudio and are not uploaded automatically. A Core Audio API success is not audible-output proof: the operator must independently verify player sound and unchanged control-app volume.

## Host and container boundary

Windows PowerShell 5.1 compiles the bundled C# bridge against Windows Core Audio COM (WASAPI); no SDK/package install, administrator privilege or external module is required. It cannot repair an audio session that does not exist. The Linux container is strictly an offline **policy evaluator**, not a Windows sound device driver or a host-audio repair service. Docker is optional for the Windows operation, and can be used on Linux, macOS and Windows to analyze previously generated receipt JSON.

Build the portable image from repo root:

~~~sh
docker build -t sas-chrome-audio-policy -f tools/chrome-audio-policy/Dockerfile .
~~~

Use an actual observed receipt name and local evidence mount, e.g. from a Unix shell:

~~~sh
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges -v "$PWD/receipts:/receipts:ro" sas-chrome-audio-policy --input /receipts/chrome-audio.json
~~~

On Windows PowerShell:

~~~powershell
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$env:LOCALAPPDATA\SysAdminSuite\Evidence\ChromeAudio,target=/receipts,readonly" sas-chrome-audio-policy --input /receipts/ACTUAL_RECEIPT_FILENAME.json
~~~

For multi-platform publishing, buildx can target linux/amd64 and linux/arm64 with an explicitly authorized registry push; multi-platform --load is not a general substitute. Do not publish local evidence or images as a side effect of inspection.

## Regression and live certification

Dependency-free offline tests: python -m unittest discover -s Tests/survey -p test_chrome_audio_policy.py -v.

Host live test: (1) inspect when Chrome is running but a player is muted or inactive; absent session remains inconclusive, (2) unmute site/player and start playback, (3) confirm the active endpoint and volume, (4) deliberately mute the Chrome **app session** and run explicit Repair, (5) verify the Chrome session change, actual audible output and an unchanged other-application control, and (6) compare before/after JSON and retained host evidence. A workstation user must approve/perform the live step. A fixture, Docker run or committed script cannot certify host audio.

Chrome multi-process/shared sessions can expose a creator PID not named chrome.exe. In that case the result remains inconclusive; no global reset is justified. Session enumeration is a point-in-time observation and can race with playback. A nondefault endpoint is reported, never automatically rerouted.

Rollback: no service, scheduled job, or background agent is installed. Re-adjust only Chrome's app mute/volume in Volume Mixer if needed. Preserve user-created evidence until the operator chooses to remove it.
