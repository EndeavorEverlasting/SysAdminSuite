# Capture a Windows dock incident

Use this path for a Lenovo dock LED turning off, alternating monitors, USB or Ethernet interruptions, or possible Bluetooth fallout during the same incident. Start on the affected Windows host in the signed-in user's session. Keep a working input path independent of the dock if available.

## Capture before recovery

From a verified current SysAdminSuite checkout or an approved local copy of its launcher and scripts, open `Capture-DockIncident.cmd`. With no arguments it collects the preceding 10 minutes and takes a current device snapshot. Run once while the setup is working and retain the returned JSON path as a baseline. Run again immediately after a recurrence, before disconnecting the dock, restarting Windows, applying firmware or restarting devices or services. Add `-BaselinePath "FULL_PATH_FROM_THE_FIRST_CAPTURE"` to compare the current captures from the same Windows installation.

For an earlier incident, provide both timestamps with an offset. The end time is exclusive. Include the complete end minute if the finish time was approximate.

```cmd
Capture-DockIncident.cmd -Start "2026-01-15T13:00:00-05:00" -End "2026-01-15T13:03:00-05:00" -Observation "Dock power-button LED went white to off as external monitors alternated. Ethernet still passed traffic. Bluetooth mouse function was not checked."
```

Record which LED changed, how the dock connects to the PC, and which displays, USB devices, network, charging and Bluetooth input or audio actually worked. Keep unknowns explicit. Use `-DockType` for the type on the physical label and `-DockFirmwareVersion` for a verified model-specific version. These fields store operator-provided evidence. The capture uses the current connection and network posture and requires neither an installation nor a network transition. It writes to `%LOCALAPPDATA%\SysAdminSuite\Evidence\Dock`. Keep the JSON local and share only reviewed, sanitized findings.

## Read the receipt

- `OperatorReport` records physical observations. Compare it against `Timeline`, the retained Windows events in the requested UTC interval. Compare the separately timestamped `Snapshot` for present devices, PnP parents, driver versions, Bluetooth services, and physical network adapters.
- An empty `Timeline` means no matching events were collected. Inspect `EventSources` for disabled, unavailable, failed or truncated logs and their retention metadata. A disabled channel is listed without querying its retained events. SetupAPI records install/configuration activity and can miss a disconnect or a firmware change. SetupAPI timestamps are interpreted using the host's current time-zone rules. An ambiguous daylight-saving hour is marked rather than guessed.
- Look for a Display 4101 reset or graphics events, correlated USB/PnP removal and arrival of dock children, Windows Update or SetupAPI installation activity, and Bluetooth radio/service events. A baseline difference identifies a state change between two snapshots. The event ordering and common PnP parent are stronger evidence of a shared path than a nearby timestamp alone. A USB radio can be internal to the PC. Monitor inventory can include phantom EDID entries, so corroborate with actual screen behavior.
- Treat LED meaning and firmware application as open until the exact dock type, its connection mode and Lenovo's model documentation or updater evidence are known. A healthy current snapshot cannot establish what happened during an earlier reset.

`CAPTURED` (exit 0) means the required reads completed. `CAPTURE_PARTIAL` (exit 2) preserves available evidence with individual source states. `CAPTURE_FAILED` (exit 1) means no usable incident receipt was written.

## If Bluetooth input drops

Use the [Bluetooth recovery guide](BLUETOOTH-PERIPHERAL-RECOVERY.md) for the existing profile and Inspect flows. Capture paired devices while they work. After the next event, preserve the dock receipt, run Inspect in the affected session, and choose only the existing recovery action justified by the exact endpoint, radio or service evidence. A paired, sleeping spare and a stopped Manual per-user service are insufficient evidence of failure. Test pointer movement and clicks or audio on the intended device before closing the incident. Keep a pre-repair receipt and take a second snapshot if a repair is performed.

The capture does not reset devices, start or stop services, install firmware, schedule repairs or change network posture. Use Lenovo documentation for the identified dock type before considering a separately authorized firmware change.
