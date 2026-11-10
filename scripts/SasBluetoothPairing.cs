using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Windows.Devices.Enumeration;

public static class SasBluetoothPairing
{
    public sealed class Mapping
    {
        public string Name { get; set; }
        public string DeviceId { get; set; }
        public bool Paired { get; set; }
        public bool? Connected { get; set; }
        public string State { get; set; }
    }

    public static async Task<Mapping[]> List()
    {
        var watcher = DeviceInformation.CreateWatcher("", new string[] {
            "System.Devices.Aep.ProtocolId", "System.Devices.Aep.IsConnected"
        }, DeviceInformationKind.AssociationEndpoint);
        var devices = new Dictionary<string, DeviceInformation>();
        object gate = new object();
        watcher.Added += (sender, device) => { lock (gate) { devices[device.Id] = device; } };
        watcher.Updated += (sender, update) =>
        {
            lock (gate)
            {
                DeviceInformation device;
                if (devices.TryGetValue(update.Id, out device)) device.Update(update);
            }
        };
        watcher.Start();
        try
        {
            await Task.Delay(4000);
            lock (gate)
            {
                return devices.Values.Where(d => IsBluetooth(d) && d.Pairing.IsPaired).Select(d =>
                {
                    object value;
                    bool? connected = d.Properties.TryGetValue("System.Devices.Aep.IsConnected", out value)
                        && value is bool ? (bool?)value : null;
                    return new Mapping { Name = d.Name, DeviceId = d.Id, Paired = true,
                        Connected = connected, State = connected == true ? "PAIRED_CONNECTED"
                            : connected == false ? "PAIRED_DISCONNECTED" : "PAIRED_CONNECTION_UNKNOWN" };
                }).ToArray();
            }
        }
        finally { watcher.Stop(); }
    }

    private static bool IsBluetooth(DeviceInformation device)
    {
        object value;
        if (!device.Properties.TryGetValue("System.Devices.Aep.ProtocolId", out value)) return false;
        var protocol = Convert.ToString(value).Trim('{', '}');
        return String.Equals(protocol, "bb7bb05e-5972-42b5-94fc-76eaa7084d49", StringComparison.OrdinalIgnoreCase)
            || String.Equals(protocol, "e0cbf06c-cd8b-4647-bb8a-263b43f0f974", StringComparison.OrdinalIgnoreCase);
    }

    public static Task<string> Run(string exactName) { return RunExact(exactName, null); }

    public static async Task<string> RunExact(string exactName, string exactId)
    {
        var watcher = DeviceInformation.CreateWatcher(
            "", new string[] { "System.Devices.Aep.ProtocolId" },
            DeviceInformationKind.AssociationEndpoint);
        var seen = new Dictionary<string, DeviceInformation>();
        object gate = new object();
        watcher.Added += (sender, device) =>
        {
            lock (gate) { seen[device.Id] = device; }
        };
        watcher.Updated += (sender, update) =>
        {
            lock (gate)
            {
                DeviceInformation device;
                if (seen.TryGetValue(update.Id, out device)) device.Update(update);
            }
        };
        watcher.Start();
        try
        {
            for (int attempt = 0; attempt < 80; attempt++)
            {
                DeviceInformation[] matches;
                lock (gate)
                {
                    matches = seen.Values.Where(d => IsBluetooth(d) && d.Name == exactName
                        && (String.IsNullOrEmpty(exactId) || d.Id == exactId)).ToArray();
                }
                if (matches.Length > 1) return "AMBIGUOUS_NAME_USE_WINDOWS_UI";
                // Allow initial discovery callbacks to settle before choosing a target.
                if (matches.Length == 1 && attempt >= 4)
                {
                    var found = matches[0];
                    Console.WriteLine("TARGET_FOUND=" + found.Name);
                    if (found.Pairing.IsPaired) return "ALREADY_PAIRED";
                    if (!found.Pairing.CanPair) return "TARGET_NOT_PAIRABLE";
                    var custom = found.Pairing.Custom;
                    custom.PairingRequested += (sender, request) =>
                    {
                        if (request.PairingKind == DevicePairingKinds.ConfirmOnly)
                            request.Accept();
                    };
                    var operation = custom.PairAsync(DevicePairingKinds.ConfirmOnly);
                    var pair = operation.AsTask();
                    if (await Task.WhenAny(pair, Task.Delay(30000)) != pair)
                    {
                        operation.Cancel();
                        return "PAIRING_TIMEOUT_REQUIRES_INSPECTION";
                    }
                    return "PAIRING_RESULT=" + (await pair).Status;
                }
                await Task.Delay(250);
            }
            return "TARGET_NOT_DISCOVERED";
        }
        finally { watcher.Stop(); }
    }
}
