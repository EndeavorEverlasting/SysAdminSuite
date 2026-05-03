// sample-data.js — Self-contained demo dataset for all five dashboard panels.
// Loaded as a plain <script> (NOT an ES module) so it does not add an extra
// ES module dependency that must be resolved at load time.
// Defines window globals read by app.js: _sasSampleStore() and _sasSampleStatus().

(function () {
  var sampleStore = {

    // ── Printer Mapping ────────────────────────────────────────────────────
    results: [
      { ComputerName: 'WMH300OPR101', Target: '\\\\PRINTSRV01\\HP-LJ-Q67',    Type: 'Network', Driver: 'HP LaserJet 400 MFP M401',       Port: '10.10.1.67', Status: 'Mapped',  Timestamp: '2026-05-03T08:05:00Z' },
      { ComputerName: 'WMH300OPR101', Target: '\\\\PRINTSRV01\\HP-LJ-Q62',    Type: 'Network', Driver: 'HP LaserJet 400 MFP M401',       Port: '10.10.1.62', Status: 'Mapped',  Timestamp: '2026-05-03T08:05:00Z' },
      { ComputerName: 'WMH300OPR102', Target: '\\\\PRINTSRV01\\ZEBRA-ZPL-01', Type: 'Network', Driver: 'ZDesigner ZT410-300dpi ZPL',     Port: '10.10.2.11', Status: 'Mapped',  Timestamp: '2026-05-03T08:06:00Z' },
      { ComputerName: 'WMH300OPR103', Target: '\\\\PRINTSRV01\\HP-LJ-Q67',    Type: 'Network', Driver: 'HP LaserJet 400 MFP M401',       Port: '10.10.1.67', Status: 'Mapped',  Timestamp: '2026-05-03T08:07:00Z' },
      { ComputerName: 'WMH300OPR104', Target: '\\\\PRINTSRV01\\KYOCERA-MFP',  Type: 'Network', Driver: 'Kyocera TASKalfa 3553ci',        Port: '10.10.1.88', Status: 'Mapped',  Timestamp: '2026-05-03T08:08:00Z' },
      { ComputerName: 'WMH300OPR105', Target: '\\\\PRINTSRV01\\ZEBRA-ZPL-02', Type: 'Network', Driver: 'ZDesigner ZT410-300dpi ZPL',     Port: '10.10.2.12', Status: 'Failed',  Timestamp: '2026-05-03T08:09:00Z' },
      { ComputerName: 'WMH300OPR106', Target: '\\\\PRINTSRV01\\HP-LJ-Q62',    Type: 'Network', Driver: 'HP LaserJet 400 MFP M401',       Port: '10.10.1.62', Status: 'Mapped',  Timestamp: '2026-05-03T08:10:00Z' },
      { ComputerName: 'WMH300OPR107', Target: '\\\\PRINTSRV01\\KYOCERA-MFP',  Type: 'Network', Driver: 'Kyocera TASKalfa 3553ci',        Port: '10.10.1.88', Status: 'Mapped',  Timestamp: '2026-05-03T08:11:00Z' },
    ],

    preflight: [
      { ComputerName: 'WMH300OPR108', Target: '\\\\PRINTSRV01\\HP-LJ-Q67',    Type: 'Network', PresentNow: 'True',  InDesired: 'True', SnapshotTime: '2026-05-03T08:00:00Z', Notes: '' },
      { ComputerName: 'WMH300OPR109', Target: '\\\\PRINTSRV01\\ZEBRA-ZPL-01', Type: 'Network', PresentNow: 'False', InDesired: 'True', SnapshotTime: '2026-05-03T08:00:00Z', Notes: 'Driver missing' },
      { ComputerName: 'WMH300OPR110', Target: '\\\\PRINTSRV01\\HP-LJ-Q62',    Type: 'Network', PresentNow: 'True',  InDesired: 'True', SnapshotTime: '2026-05-03T08:00:00Z', Notes: '' },
    ],

    printerProbe: [
      { Target: '10.10.1.67', ResolvedAddress: '10.10.1.67', PingStatus: 'Reachable',   MAC: '00:1B:A9:2F:5C:01', Serial: 'CNBCJ12345', Source: 'SNMP',     Timestamp: '2026-05-03T08:00:00Z', Notes: '' },
      { Target: '10.10.1.62', ResolvedAddress: '10.10.1.62', PingStatus: 'Reachable',   MAC: '00:1B:A9:2F:5C:02', Serial: 'CNBCJ67890', Source: 'SNMP',     Timestamp: '2026-05-03T08:00:00Z', Notes: '' },
      { Target: '10.10.2.11', ResolvedAddress: '10.10.2.11', PingStatus: 'Reachable',   MAC: '00:07:4D:AB:CD:01', Serial: 'ZBR-00123',   Source: '9100/ZPL', Timestamp: '2026-05-03T08:00:00Z', Notes: '' },
      { Target: '10.10.2.12', ResolvedAddress: '',            PingStatus: 'Unreachable', MAC: '',                  Serial: '',            Source: 'ARP',      Timestamp: '2026-05-03T08:00:00Z', Notes: 'Ping failed — device may be offline' },
      { Target: '10.10.1.88', ResolvedAddress: '10.10.1.88', PingStatus: 'Reachable',   MAC: '00:C0:EE:88:11:22', Serial: 'KYO-2024-004',Source: 'SNMP',     Timestamp: '2026-05-03T08:00:00Z', Notes: '' },
    ],

    // ── Hardware Inventory ─────────────────────────────────────────────────
    machineInfo: [
      { HostName: 'WMH300OPR101', Serial: 'SN-00101', IPAddress: '10.10.3.101', MACAddress: 'AA:BB:CC:DD:01:01', MonitorSerials: 'MON-A001;MON-A002', Status: 'Online' },
      { HostName: 'WMH300OPR102', Serial: 'SN-00102', IPAddress: '10.10.3.102', MACAddress: 'AA:BB:CC:DD:01:02', MonitorSerials: 'MON-B001',          Status: 'Online' },
      { HostName: 'WMH300OPR103', Serial: 'SN-00103', IPAddress: '10.10.3.103', MACAddress: 'AA:BB:CC:DD:01:03', MonitorSerials: 'MON-C001;MON-C002', Status: 'Online' },
      { HostName: 'WMH300OPR104', Serial: 'SN-00104', IPAddress: '10.10.3.104', MACAddress: 'AA:BB:CC:DD:01:04', MonitorSerials: 'MON-D001',          Status: 'Online' },
      { HostName: 'WMH300OPR105', Serial: 'SN-00105', IPAddress: '10.10.3.105', MACAddress: 'AA:BB:CC:DD:01:05', MonitorSerials: '',                  Status: 'Offline' },
      { HostName: 'WMH300OPR106', Serial: 'SN-00106', IPAddress: '10.10.3.106', MACAddress: 'AA:BB:CC:DD:01:06', MonitorSerials: 'MON-F001',          Status: 'Online' },
      { HostName: 'WMH300OPR107', Serial: 'SN-00107', IPAddress: '10.10.3.107', MACAddress: 'AA:BB:CC:DD:01:07', MonitorSerials: 'MON-G001;MON-G002', Status: 'Online' },
      { HostName: 'WMH300OPR108', Serial: 'SN-00108', IPAddress: '10.10.3.108', MACAddress: 'AA:BB:CC:DD:01:08', MonitorSerials: 'MON-H001',          Status: 'Online' },
    ],

    ramInfo: [
      { HostName: 'WMH300OPR101', CapacityGB: '8',  MemoryType: 'DDR4', ConfiguredClockSpeed: '3200', Slot: 'DIMM-A1' },
      { HostName: 'WMH300OPR101', CapacityGB: '8',  MemoryType: 'DDR4', ConfiguredClockSpeed: '3200', Slot: 'DIMM-B1' },
      { HostName: 'WMH300OPR102', CapacityGB: '16', MemoryType: 'DDR4', ConfiguredClockSpeed: '2666', Slot: 'DIMM-A1' },
      { HostName: 'WMH300OPR103', CapacityGB: '8',  MemoryType: 'DDR4', ConfiguredClockSpeed: '3200', Slot: 'DIMM-A1' },
      { HostName: 'WMH300OPR103', CapacityGB: '8',  MemoryType: 'DDR4', ConfiguredClockSpeed: '3200', Slot: 'DIMM-B1' },
      { HostName: 'WMH300OPR104', CapacityGB: '32', MemoryType: 'DDR5', ConfiguredClockSpeed: '4800', Slot: 'DIMM-A1' },
      { HostName: 'WMH300OPR105', CapacityGB: '8',  MemoryType: 'DDR4', ConfiguredClockSpeed: '2133', Slot: 'DIMM-A1' },
      { HostName: 'WMH300OPR106', CapacityGB: '16', MemoryType: 'DDR4', ConfiguredClockSpeed: '3200', Slot: 'DIMM-A1' },
      { HostName: 'WMH300OPR107', CapacityGB: '16', MemoryType: 'DDR4', ConfiguredClockSpeed: '2666', Slot: 'DIMM-A1' },
      { HostName: 'WMH300OPR108', CapacityGB: '8',  MemoryType: 'DDR4', ConfiguredClockSpeed: '3200', Slot: 'DIMM-A1' },
    ],

    ramByHost: {
      'WMH300OPR101': [ { HostName: 'WMH300OPR101', CapacityGB: '8',  MemoryType: 'DDR4', ConfiguredClockSpeed: '3200', Slot: 'DIMM-A1' }, { HostName: 'WMH300OPR101', CapacityGB: '8',  MemoryType: 'DDR4', ConfiguredClockSpeed: '3200', Slot: 'DIMM-B1' } ],
      'WMH300OPR102': [ { HostName: 'WMH300OPR102', CapacityGB: '16', MemoryType: 'DDR4', ConfiguredClockSpeed: '2666', Slot: 'DIMM-A1' } ],
      'WMH300OPR103': [ { HostName: 'WMH300OPR103', CapacityGB: '8',  MemoryType: 'DDR4', ConfiguredClockSpeed: '3200', Slot: 'DIMM-A1' }, { HostName: 'WMH300OPR103', CapacityGB: '8',  MemoryType: 'DDR4', ConfiguredClockSpeed: '3200', Slot: 'DIMM-B1' } ],
      'WMH300OPR104': [ { HostName: 'WMH300OPR104', CapacityGB: '32', MemoryType: 'DDR5', ConfiguredClockSpeed: '4800', Slot: 'DIMM-A1' } ],
      'WMH300OPR105': [ { HostName: 'WMH300OPR105', CapacityGB: '8',  MemoryType: 'DDR4', ConfiguredClockSpeed: '2133', Slot: 'DIMM-A1' } ],
      'WMH300OPR106': [ { HostName: 'WMH300OPR106', CapacityGB: '16', MemoryType: 'DDR4', ConfiguredClockSpeed: '3200', Slot: 'DIMM-A1' } ],
      'WMH300OPR107': [ { HostName: 'WMH300OPR107', CapacityGB: '16', MemoryType: 'DDR4', ConfiguredClockSpeed: '2666', Slot: 'DIMM-A1' } ],
      'WMH300OPR108': [ { HostName: 'WMH300OPR108', CapacityGB: '8',  MemoryType: 'DDR4', ConfiguredClockSpeed: '3200', Slot: 'DIMM-A1' } ],
    },

    monitorInfo: [
      { HostName: 'WMH300OPR101', ComputerName: 'WMH300OPR101', Serial: 'MON-A001', Model: 'Dell P2422H',    DisplayNumber: '1', IsPrimary: 'True' },
      { HostName: 'WMH300OPR101', ComputerName: 'WMH300OPR101', Serial: 'MON-A002', Model: 'Dell P2422H',    DisplayNumber: '2', IsPrimary: 'False' },
      { HostName: 'WMH300OPR102', ComputerName: 'WMH300OPR102', Serial: 'MON-B001', Model: 'LG 24MK600M',   DisplayNumber: '1', IsPrimary: 'True' },
      { HostName: 'WMH300OPR103', ComputerName: 'WMH300OPR103', Serial: 'MON-C001', Model: 'HP E24 G5',     DisplayNumber: '1', IsPrimary: 'True' },
      { HostName: 'WMH300OPR103', ComputerName: 'WMH300OPR103', Serial: 'MON-C002', Model: 'HP E24 G5',     DisplayNumber: '2', IsPrimary: 'False' },
      { HostName: 'WMH300OPR104', ComputerName: 'WMH300OPR104', Serial: 'MON-D001', Model: 'Dell U2722D',   DisplayNumber: '1', IsPrimary: 'True' },
      { HostName: 'WMH300OPR106', ComputerName: 'WMH300OPR106', Serial: 'MON-F001', Model: 'LG 27UK850',    DisplayNumber: '1', IsPrimary: 'True' },
      { HostName: 'WMH300OPR107', ComputerName: 'WMH300OPR107', Serial: 'MON-G001', Model: 'Dell P2422H',   DisplayNumber: '1', IsPrimary: 'True' },
      { HostName: 'WMH300OPR107', ComputerName: 'WMH300OPR107', Serial: 'MON-G002', Model: 'Dell P2422H',   DisplayNumber: '2', IsPrimary: 'False' },
      { HostName: 'WMH300OPR108', ComputerName: 'WMH300OPR108', Serial: 'MON-H001', Model: 'HP E24 G5',     DisplayNumber: '1', IsPrimary: 'True' },
    ],

    // ── Remote Tasks ───────────────────────────────────────────────────────
    // Field names match what panel-tasks.js buildTaskRows normalizes from store.remoteTasks
    remoteTasks: [
      { Timestamp: '2026-05-03T08:10:00Z',  Machine: 'WMH300OPR101', TaskName: 'RAM-Profile',         TaskId: 'QR-2026-0503-001', Outcome: 'Success', Operator: 'jsmith',       Notes: '' },
      { Timestamp: '2026-05-03T08:22:00Z',  Machine: 'WMH300OPR102', TaskName: 'Network-Preflight',   TaskId: 'QR-2026-0503-002', Outcome: 'Success', Operator: 'jsmith',       Notes: '' },
      { Timestamp: '2026-05-03T08:45:00Z',  Machine: 'WMH300OPR103', TaskName: 'Printer-Probe',       TaskId: 'QR-2026-0503-003', Outcome: 'Failed',  Operator: 'jsmith',       Notes: 'Timeout reaching 10.10.5.22:9100' },
      { Timestamp: '2026-05-03T08:55:00Z',  Machine: 'WMH300OPR101', TaskName: 'WorkstationIdentity', TaskId: 'RC-0001',           Outcome: 'Success', Operator: 'svc-sysadmin', Notes: 'WMI transport' },
      { Timestamp: '2026-05-03T08:56:30Z',  Machine: 'WMH300OPR102', TaskName: 'WorkstationIdentity', TaskId: 'RC-0002',           Outcome: 'Failed',  Operator: 'svc-sysadmin', Notes: 'WMI access denied' },
      { Timestamp: '2026-05-03T08:58:00Z',  Machine: 'WMH300OPR103', TaskName: 'WorkstationIdentity', TaskId: 'RC-0003',           Outcome: 'Success', Operator: 'svc-sysadmin', Notes: 'SSH fallback' },
      { Timestamp: '2026-05-03T09:05:00Z',  Machine: 'WMH300OPR104', TaskName: 'MachineInfo',         TaskId: 'RC-0004',           Outcome: 'Success', Operator: 'svc-sysadmin', Notes: '' },
      { Timestamp: '2026-05-03T09:08:00Z',  Machine: 'WMH300OPR105', TaskName: 'MachineInfo',         TaskId: 'RC-0005',           Outcome: 'Success', Operator: 'svc-sysadmin', Notes: '' },
      { Timestamp: '2026-05-03T09:12:00Z',  Machine: 'WMH300OPR106', TaskName: 'Printer-Mapping',     TaskId: 'RC-0006',           Outcome: 'Success', Operator: 'svc-sysadmin', Notes: '' },
      { Timestamp: '2026-05-03T09:15:00Z',  Machine: 'WMH300OPR107', TaskName: 'Printer-Mapping',     TaskId: 'RC-0007',           Outcome: 'Success', Operator: 'svc-sysadmin', Notes: '' },
      { Timestamp: '2026-05-03T09:18:00Z',  Machine: 'WMH300OPR108', TaskName: 'Printer-Mapping',     TaskId: 'RC-0008',           Outcome: 'Failed',  Operator: 'svc-sysadmin', Notes: 'Print spooler not running' },
      { Timestamp: '2026-05-03T09:25:00Z',  Machine: 'WMH300OPR105', TaskName: 'Network-Preflight',   TaskId: 'RC-0009',           Outcome: 'Success', Operator: 'agarcia',      Notes: '' },
    ],

    // ── Network & Protocol Trace ───────────────────────────────────────────
    // networkPreflight rows already in merged/grouped format (same as parsers.parseNetworkPreflight output)
    networkPreflight: [
      { Target: 'WMH300OPR101', ResolvedAddress: '10.10.3.101', PingStatus: 'Reachable',   Timestamp: '2026-05-03T08:00:00Z', ports: { '135': 'Open', '139': 'Open', '445': 'Open', '3389': 'Open',   '515': 'Closed', '631': 'Closed', '9100': 'Closed' } },
      { Target: 'WMH300OPR102', ResolvedAddress: '10.10.3.102', PingStatus: 'Reachable',   Timestamp: '2026-05-03T08:00:00Z', ports: { '135': 'Open', '139': 'Open', '445': 'Open', '3389': 'Open',   '515': 'Closed', '631': 'Closed', '9100': 'Closed' } },
      { Target: 'WMH300OPR103', ResolvedAddress: '10.10.3.103', PingStatus: 'Reachable',   Timestamp: '2026-05-03T08:00:00Z', ports: { '135': 'Open', '139': 'Open', '445': 'Open', '3389': 'Open',   '515': 'Open',   '631': 'Open',   '9100': 'Closed' } },
      { Target: 'WMH300OPR104', ResolvedAddress: '10.10.3.104', PingStatus: 'Reachable',   Timestamp: '2026-05-03T08:00:00Z', ports: { '135': 'Open', '139': 'Open', '445': 'Open', '3389': 'Open',   '515': 'Closed', '631': 'Closed', '9100': 'Closed' } },
      { Target: 'WMH300OPR105', ResolvedAddress: '',            PingStatus: 'Unreachable', Timestamp: '2026-05-03T08:00:00Z', ports: { '135': 'Closed','139': 'Closed','445': 'Closed','3389': 'Closed','515': 'Closed', '631': 'Closed', '9100': 'Closed' } },
      { Target: 'WMH300OPR106', ResolvedAddress: '10.10.3.106', PingStatus: 'Reachable',   Timestamp: '2026-05-03T08:00:00Z', ports: { '135': 'Open', '139': 'Open', '445': 'Open', '3389': 'Closed', '515': 'Closed', '631': 'Closed', '9100': 'Closed' } },
      { Target: 'WMH300OPR107', ResolvedAddress: '10.10.3.107', PingStatus: 'Reachable',   Timestamp: '2026-05-03T08:00:00Z', ports: { '135': 'Open', '139': 'Open', '445': 'Open', '3389': 'Open',   '515': 'Closed', '631': 'Closed', '9100': 'Closed' } },
      { Target: '10.10.1.67',   ResolvedAddress: '10.10.1.67',  PingStatus: 'Reachable',   Timestamp: '2026-05-03T08:00:00Z', ports: { '135': 'Closed','139': 'Closed','445': 'Closed','3389': 'Closed','515': 'Open',   '631': 'Open',   '9100': 'Open' } },
      { Target: '10.10.1.62',   ResolvedAddress: '10.10.1.62',  PingStatus: 'Reachable',   Timestamp: '2026-05-03T08:00:00Z', ports: { '135': 'Closed','139': 'Closed','445': 'Closed','3389': 'Closed','515': 'Open',   '631': 'Open',   '9100': 'Open' } },
      { Target: '10.10.2.12',   ResolvedAddress: '',            PingStatus: 'Unreachable', Timestamp: '2026-05-03T08:00:00Z', ports: { '135': 'Closed','139': 'Closed','445': 'Closed','3389': 'Closed','515': 'Closed', '631': 'Closed', '9100': 'Closed' } },
    ],

    networkPreflightRaw: [],

    // workstationIdentity uses Target (not HostName) — key field for buildProtocolRows merge
    workstationIdentity: [
      { Target: 'WMH300OPR101', ResolvedAddress: '10.10.3.101', DnsName: 'wmh300opr101.corp.local', PingStatus: 'Reachable',   TransportUsed: 'WMI', IdentityStatus: 'Collected', ObservedHostName: 'WMH300OPR101', ObservedSerial: 'SN-00101', ObservedMACs: 'AA:BB:CC:DD:01:01', Notes: '', Timestamp: '2026-05-03T08:55:00Z' },
      { Target: 'WMH300OPR102', ResolvedAddress: '10.10.3.102', DnsName: 'wmh300opr102.corp.local', PingStatus: 'Reachable',   TransportUsed: 'SSH', IdentityStatus: 'Failed',    ObservedHostName: '',             ObservedSerial: '',         ObservedMACs: '',                  Notes: 'WMI access denied — SSH fallback attempted', Timestamp: '2026-05-03T08:56:30Z' },
      { Target: 'WMH300OPR103', ResolvedAddress: '10.10.3.103', DnsName: 'wmh300opr103.corp.local', PingStatus: 'Reachable',   TransportUsed: 'SSH', IdentityStatus: 'Collected', ObservedHostName: 'WMH300OPR103', ObservedSerial: 'SN-00103', ObservedMACs: 'AA:BB:CC:DD:01:03', Notes: 'SSH fallback', Timestamp: '2026-05-03T08:58:00Z' },
      { Target: 'WMH300OPR104', ResolvedAddress: '10.10.3.104', DnsName: 'wmh300opr104.corp.local', PingStatus: 'Reachable',   TransportUsed: 'WMI', IdentityStatus: 'Collected', ObservedHostName: 'WMH300OPR104', ObservedSerial: 'SN-00104', ObservedMACs: 'AA:BB:CC:DD:01:04', Notes: '', Timestamp: '2026-05-03T09:00:00Z' },
      { Target: 'WMH300OPR105', ResolvedAddress: '',            DnsName: '',                        PingStatus: 'Unreachable', TransportUsed: 'None',IdentityStatus: 'Unreachable',ObservedHostName: '',             ObservedSerial: '',         ObservedMACs: '',                  Notes: 'Host unreachable', Timestamp: '2026-05-03T09:01:00Z' },
      { Target: 'WMH300OPR106', ResolvedAddress: '10.10.3.106', DnsName: 'wmh300opr106.corp.local', PingStatus: 'Reachable',   TransportUsed: 'WMI', IdentityStatus: 'Collected', ObservedHostName: 'WMH300OPR106', ObservedSerial: 'SN-00106', ObservedMACs: 'AA:BB:CC:DD:01:06', Notes: '', Timestamp: '2026-05-03T09:02:00Z' },
    ],

    // ── Software Superset (install inventory from Inventory-Software.ps1) ─────
    // One row per Name+Host — mirrors what Inventory-Software.ps1 emits.
    // 4 surveyed hosts: OPR101, OPR102, OPR103, OPR104
    // This lets the panel demonstrate: Installed (all 4), Partial (some), Missing (none),
    // and Unmanaged (found on hosts but not in catalog / flagged unmanaged in catalog).
    softwareInventory: [
      // Chrome — all 4 hosts → Installed
      { Name: 'Chrome',           Version: '124.0.6367.78',  Publisher: 'Google LLC',                    DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Google\\Chrome',               Host: 'WMH300OPR101', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'Chrome',           Version: '124.0.6367.78',  Publisher: 'Google LLC',                    DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Google\\Chrome',               Host: 'WMH300OPR102', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'Chrome',           Version: '124.0.6367.78',  Publisher: 'Google LLC',                    DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Google\\Chrome',               Host: 'WMH300OPR103', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'Chrome',           Version: '124.0.6367.78',  Publisher: 'Google LLC',                    DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Google\\Chrome',               Host: 'WMH300OPR104', Timestamp: '2026-05-03T08:00:00Z' },
      // Teams — all 4 hosts → Installed
      { Name: 'Teams',            Version: '23293.918.2293', Publisher: 'Microsoft Corporation',         DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Microsoft\\Teams',             Host: 'WMH300OPR101', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'Teams',            Version: '23293.918.2293', Publisher: 'Microsoft Corporation',         DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Microsoft\\Teams',             Host: 'WMH300OPR102', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'Teams',            Version: '23293.918.2293', Publisher: 'Microsoft Corporation',         DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Microsoft\\Teams',             Host: 'WMH300OPR103', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'Teams',            Version: '23293.918.2293', Publisher: 'Microsoft Corporation',         DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Microsoft\\Teams',             Host: 'WMH300OPR104', Timestamp: '2026-05-03T08:00:00Z' },
      // Adobe Acrobat DC — 3 of 4 hosts → Partial
      { Name: 'Adobe Acrobat DC', Version: '23.008.20470',   Publisher: 'Adobe Inc.',                    DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Adobe\\Acrobat Reader\\DC',    Host: 'WMH300OPR101', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'Adobe Acrobat DC', Version: '23.008.20470',   Publisher: 'Adobe Inc.',                    DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Adobe\\Acrobat Reader\\DC',    Host: 'WMH300OPR102', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'Adobe Acrobat DC', Version: '23.008.20470',   Publisher: 'Adobe Inc.',                    DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Adobe\\Acrobat Reader\\DC',    Host: 'WMH300OPR104', Timestamp: '2026-05-03T08:00:00Z' },
      // Malwarebytes — 2 of 4 hosts → Partial
      { Name: 'Malwarebytes',     Version: '4.6.8.287',      Publisher: 'Malwarebytes',                  DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Malwarebytes',                 Host: 'WMH300OPR101', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'Malwarebytes',     Version: '4.6.8.287',      Publisher: 'Malwarebytes',                  DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Malwarebytes',                 Host: 'WMH300OPR102', Timestamp: '2026-05-03T08:00:00Z' },
      // 7-Zip — 2 of 4 hosts → Partial
      { Name: '7-Zip',            Version: '23.01',          Publisher: 'Igor Pavlov',                   DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\7-Zip',                         Host: 'WMH300OPR101', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: '7-Zip',            Version: '23.01',          Publisher: 'Igor Pavlov',                   DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\7-Zip',                         Host: 'WMH300OPR103', Timestamp: '2026-05-03T08:00:00Z' },
      // Notepad++ — 1 of 4 hosts → Partial
      { Name: 'Notepad++',        Version: '8.6.4',          Publisher: 'Notepad++ Team',                DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Notepad++',                     Host: 'WMH300OPR104', Timestamp: '2026-05-03T08:00:00Z' },
      // Git — 2 of 4 (admin only) → Partial
      { Name: 'Git',              Version: '2.44.0',         Publisher: 'The Git Development Community', DetectType: 'exe',    DetectValue: 'C:\\Program Files\\Git\\bin\\git.exe',            Host: 'WMH300OPR101', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'Git',              Version: '2.44.0',         Publisher: 'The Git Development Community', DetectType: 'exe',    DetectValue: 'C:\\Program Files\\Git\\bin\\git.exe',            Host: 'WMH300OPR102', Timestamp: '2026-05-03T08:00:00Z' },
      // VS Code — 1 of 4 → Partial
      { Name: 'VS Code',          Version: '1.89.0',         Publisher: 'Microsoft Corporation',         DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\Microsoft\\VisualStudio Code', Host: 'WMH300OPR101', Timestamp: '2026-05-03T08:00:00Z' },
      // Firefox — 0 of 4 → Missing
      // VLC — 0 of 4 → Missing
      // Zoom — 0 of 4 → Missing
      // Windows Terminal — 0 of 4 → Missing
      // CutePDF Writer — 0 of 4 → Missing
      // WinSCP — 0 of 4 → Missing
      // PuTTY — 0 of 4 → Missing
      // OldFaxTool 2.1 — in catalog as unmanaged, found on 2 hosts
      { Name: 'OldFaxTool 2.1',   Version: '2.1',            Publisher: 'LegacySoft',                    DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\OldFaxTool',                   Host: 'WMH300OPR101', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'OldFaxTool 2.1',   Version: '2.1',            Publisher: 'LegacySoft',                    DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\OldFaxTool',                   Host: 'WMH300OPR103', Timestamp: '2026-05-03T08:00:00Z' },
      // ScreenConnect Client — NOT in catalog, found on 3 hosts → inventory-only / Unmanaged
      { Name: 'ScreenConnect Client', Version: '23.9.8.8811', Publisher: 'ConnectWise',                  DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\ScreenConnect Client',          Host: 'WMH300OPR101', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'ScreenConnect Client', Version: '23.9.8.8811', Publisher: 'ConnectWise',                  DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\ScreenConnect Client',          Host: 'WMH300OPR102', Timestamp: '2026-05-03T08:00:00Z' },
      { Name: 'ScreenConnect Client', Version: '23.9.8.8811', Publisher: 'ConnectWise',                  DetectType: 'regkey', DetectValue: 'HKLM:\\Software\\ScreenConnect Client',          Host: 'WMH300OPR104', Timestamp: '2026-05-03T08:00:00Z' },
    ],

    // ── Software Tracker ───────────────────────────────────────────────────
    // Fields: name, source, strategy, version, type, detect_type, detect_value, unmanaged
    software: {
      apps: [
        { name: 'Chrome',           source: 'url',    strategy: 'latest', version: null,    type: 'msi',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\Google\\Chrome',                    unmanaged: false },
        { name: 'Firefox',          source: 'url',    strategy: 'latest', version: null,    type: 'msi',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\Mozilla\\Firefox',                  unmanaged: false },
        { name: 'Adobe Acrobat DC', source: 'url',    strategy: 'pinned', version: '23.008',type: 'msi',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\Adobe\\Acrobat Reader\\DC',         unmanaged: false },
        { name: '7-Zip',            source: 'url',    strategy: 'pinned', version: '23.01', type: 'msi',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\7-Zip',                              unmanaged: false },
        { name: 'VLC',              source: 'url',    strategy: 'latest', version: null,    type: 'msi',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\VideoLAN\\VLC',                     unmanaged: false },
        { name: 'Notepad++',        source: 'url',    strategy: 'latest', version: null,    type: 'exe',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\Notepad++',                         unmanaged: false },
        { name: 'Windows Terminal', source: 'github', strategy: 'latest', version: null,    type: 'msix',  detect_type: 'store', detect_value: 'Microsoft.WindowsTerminal',                           unmanaged: false },
        { name: 'Git',              source: 'url',    strategy: 'pinned', version: '2.44.0',type: 'exe',   detect_type: 'exe',   detect_value: 'C:\\Program Files\\Git\\bin\\git.exe',                unmanaged: false },
        { name: 'VS Code',          source: 'url',    strategy: 'latest', version: null,    type: 'exe',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\Microsoft\\VisualStudio Code',      unmanaged: false },
        { name: 'Zoom',             source: 'url',    strategy: 'latest', version: null,    type: 'msi',   detect_type: 'reg',   detect_value: 'HKCU:\\Software\\Zoom',                               unmanaged: false },
        { name: 'Teams',            source: 'url',    strategy: 'pinned', version: '23293', type: 'msi',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\Microsoft\\Teams',                  unmanaged: false },
        { name: 'CutePDF Writer',   source: 'url',    strategy: 'pinned', version: '4.0',   type: 'exe',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\Acro Software\\CutePDF Writer',     unmanaged: false },
        { name: 'WinSCP',           source: 'url',    strategy: 'latest', version: null,    type: 'msi',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\WinSCP',                             unmanaged: false },
        { name: 'PuTTY',            source: 'url',    strategy: 'pinned', version: '0.80',  type: 'msi',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\SimonTatham\\PuTTY',                unmanaged: false },
        { name: 'Malwarebytes',     source: 'url',    strategy: 'pinned', version: '4.6',   type: 'exe',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\Malwarebytes',                       unmanaged: false },
        { name: 'OldFaxTool 2.1',   source: 'url',    strategy: 'pinned', version: '2.1',   type: 'exe',   detect_type: 'reg',   detect_value: 'HKLM:\\Software\\OldFaxTool',                         unmanaged: true },
      ],
      lists: {
        mandatory:            ['Chrome', 'Adobe Acrobat DC', 'Malwarebytes', 'Teams'],
        optional:             ['Firefox', 'VLC', 'CutePDF Writer'],
        admin_only:           ['Git', 'VS Code', 'WinSCP', 'PuTTY'],
        standard_workstation: ['Chrome', 'Adobe Acrobat DC', '7-Zip', 'Notepad++', 'Zoom', 'Teams', 'Malwarebytes'],
      }
    },
  };

  var sampleStatus = {
    State: 'Completed',
    Stage: 'Results',
    Message: 'Demo mode — 8 machines, 5 printers, 12 tasks processed.',
    GeneratedAt: new Date().toISOString(),
    Data: {
      ComputerName: 'ADMIN-WS-001',
      OutputRoot: 'C:\\ProgramData\\SysAdminSuite\\Mapping',
      DesiredQueues: ['\\\\PRINTSRV01\\HP-LJ-Q67', '\\\\PRINTSRV01\\ZEBRA-ZPL-01'],
      StopRequested: false,
      EnableUndoRedo: true
    }
  };

  // Expose as globals so app.js (ES module) can read them even on file:// URLs
  window._sasSampleStore  = function () { return JSON.parse(JSON.stringify(sampleStore)); };
  window._sasSampleStatus = function () { return Object.assign({}, sampleStatus, { GeneratedAt: new Date().toISOString() }); };
})();
