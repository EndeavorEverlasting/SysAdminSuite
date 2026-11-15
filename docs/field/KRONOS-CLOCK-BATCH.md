# Kronos clock batch report

The field front door is `Report-KronosClocks.cmd` in the canonical SysAdminSuite Windows checkout. It verifies origin main using the existing InternetSync network workflow, safely fast-forwards a clean checkout when needed, and restores the starting network before opening the report prompts. When the existing network workflow requires a manual network transition, coordinate the launch from a workstation that can meet both the refresh and protected-access requirements. It opens the HTML when the report is ready and prints the locations of the HTML and CSV. Each run has its own folder under `%LOCALAPPDATA%\SysAdminSuite\Evidence\KronosClock`.

At the assignment prompt, enter a CSV path for a batch or a typed value such as `SerialNumber=CLOCK-SERIAL` for a single clock. A CSV can contain 1–250 assignments, one row per clock, with any of these columns. Leave unknown values blank.

```csv
IPAddress,HostName,MACAddress,SerialNumber,SubnetMask,DeviceID,DeviceName,ScopeId,DefaultGateway
,clock-a,02-00-00-00-00-11,CLOCK-SERIAL,,,,,
```

Use an approved site evidence folder. The local default is `%LOCALAPPDATA%\SysAdminSuite\KronosClock`. When multiple sites share an inventory, first select the file for the assigned site so identity and scope remain meaningful. The launcher recognizes these files when present.

| File | Evidence used |
| --- | --- |
| `ClockInventory.csv` | Existing Kronos inventory or a clock-only site export. Recognizes the assignment columns and Model. |
| `DhcpLeases.csv` | IPv4 lease export with IPAddress, HostName, ClientId or MACAddress, ScopeId and AddressState when available. |
| `DhcpScopes.csv` | Approved site IPv4 scopes with ScopeId and SubnetMask. Include DefaultGateway when available for documentation. |
| `DhcpReservations.csv` | IPv4 reservations with IPAddress and ClientId or MACAddress. Include ScopeId when available. |

Use current exports from the authorized site owner, and keep assignments, source exports and results in approved local storage. A lease does not establish a reservation. The reservation column reports matching export evidence and otherwise stays Unknown. A subnet-only hint can complete a record only when the supplied evidence identifies a unique clock.

Local evidence mode is the default. For live reachability, already be on an authorized protected Northwell connection, select LIVE, and use the approved site scope file. An optional approved DNS suffix enables exact hostname lookups. Live mode checks one eligible address per assignment, caches repeats, and leaves the network connection as it found it. An ICMP response is evidence that the matched address responded. UKG backend activation and any DHCP configuration are separate field activities.

In the report, **Complete** means the five core fields are present: IPv4 address, hostname, MAC, serial and subnet mask. Review **Missing**, **Notes**, and **Sources** before copying data into the assignment. Give a flagged row another identifier or reconcile the source exports before using the record. Scope and gateway are sourced from the export or technician data. Report reachability can be Not checked, Responded to ICMP, No ICMP reply or ICMP unavailable.
