using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Windows.Devices.Enumeration;

public static class SasBluetoothPairing
{
    public static async Task<string> Run(string exactName)
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
                    matches = seen.Values.Where(d => d.Name == exactName).ToArray();
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
