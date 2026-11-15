using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Windows.Devices.Bluetooth;
using Windows.Devices.Enumeration;
using Windows.Foundation;

public static class SasBluetoothPairing
{
    public sealed class StableMatchWindow
    {
        private string lastId;
        private int samples;
        public bool Observe(string[] ids)
        {
            if (ids.Length != 1) { lastId = null; samples = 0; return false; }
            samples = ids[0] == lastId ? samples + 1 : 1;
            lastId = ids[0];
            return samples >= 12;
        }
    }
    public sealed class Mapping
    {
        public string Name { get; set; }
        public string DeviceId { get; set; }
        public bool Paired { get; set; }
        public bool? Connected { get; set; }
        public string State { get; set; }
    }

    public sealed class Endpoint
    {
        public string DeviceId { get; set; }
        public bool Paired { get; set; }
        public bool? Connected { get; set; }
        public bool? Present { get; set; }
        public bool CanPair { get; set; }
    }

    private const string ClassicProtocol = "e0cbf06c-cd8b-4647-bb8a-263b43f0f974";
    private const string LowEnergyProtocol = "bb7bb05e-5972-42b5-94fc-76eaa7084d49";
    private const string ProtocolProperty = "System.Devices.Aep.ProtocolId";
    private const string ConnectedProperty = "System.Devices.Aep.IsConnected";
    private const string PresentProperty = "System.Devices.Aep.IsPresent";

    private sealed class BluetoothWatch : IDisposable
    {
        private readonly DeviceWatcher watcher;
        private readonly Dictionary<string, DeviceInformation> devices =
            new Dictionary<string, DeviceInformation>(StringComparer.OrdinalIgnoreCase);

        public BluetoothWatch()
        {
            watcher = DeviceInformation.CreateWatcher(
                "(" + ProtocolProperty + ":=\"{" + ClassicProtocol + "}\" OR "
                    + ProtocolProperty + ":=\"{" + LowEnergyProtocol + "}\")",
                new[] { ProtocolProperty, ConnectedProperty, PresentProperty },
                DeviceInformationKind.AssociationEndpoint);
            watcher.Added += (sender, device) => { lock (devices) devices[device.Id] = device; };
            watcher.Updated += (sender, update) =>
            {
                lock (devices)
                {
                    DeviceInformation device;
                    if (devices.TryGetValue(update.Id, out device)) device.Update(update);
                }
            };
            watcher.Removed += (sender, update) => { lock (devices) devices.Remove(update.Id); };
            watcher.Start();
        }

        public T Read<T>(Func<IEnumerable<DeviceInformation>, T> read)
        {
            if (watcher.Status == DeviceWatcherStatus.Aborted)
                throw new InvalidOperationException("BLUETOOTH_ENUMERATION_ABORTED");
            lock (devices) return read(devices.Values.Where(d => IsProtocol(d, ClassicProtocol)
                || IsProtocol(d, LowEnergyProtocol)));
        }

        public void Dispose()
        {
            if (watcher.Status == DeviceWatcherStatus.Started ||
                watcher.Status == DeviceWatcherStatus.EnumerationCompleted)
                watcher.Stop();
        }
    }

    private static bool IsProtocol(DeviceInformation device, string protocol)
    {
        object value;
        return device.Properties.TryGetValue(ProtocolProperty, out value)
            && String.Equals(Convert.ToString(value).Trim('{', '}'), protocol, StringComparison.OrdinalIgnoreCase);
    }

    private static bool? ReadFlag(DeviceInformation device, string property)
    {
        object value;
        return device.Properties.TryGetValue(property, out value) && value is bool ? (bool?)value : null;
    }

    private static bool MatchesId(DeviceInformation device, string id)
    {
        return String.Equals(device.Id, id, StringComparison.OrdinalIgnoreCase);
    }

    public static async Task<Mapping[]> List()
    {
        using (var watch = new BluetoothWatch())
        {
            await Task.Delay(4000);
            return watch.Read(devices => devices.Where(d => d.Pairing.IsPaired).Select(d =>
            {
                bool? connected = ReadFlag(d, ConnectedProperty);
                return new Mapping { Name = d.Name, DeviceId = d.Id, Paired = true,
                    Connected = connected, State = connected == true ? "PAIRED_CONNECTED"
                        : connected == false ? "PAIRED_DISCONNECTED" : "PAIRED_CONNECTION_UNKNOWN" };
            }).ToArray());
        }
    }

    public static async Task<Endpoint> Observe(string id)
    {
        using (var watch = new BluetoothWatch())
        {
            await Task.Delay(4000);
            return watch.Read(devices =>
            {
                var device = devices.SingleOrDefault(d => MatchesId(d, id));
                return device == null ? null : new Endpoint { DeviceId = device.Id,
                    Paired = device.Pairing.IsPaired, CanPair = device.Pairing.CanPair,
                    Connected = ReadFlag(device, ConnectedProperty), Present = ReadFlag(device, PresentProperty) };
            });
        }
    }

    private static async Task<T> WaitFor<T>(IAsyncOperation<T> operation, int timeoutMs)
    {
        var task = operation.AsTask();
        if (await Task.WhenAny(task, Task.Delay(timeoutMs)) == task) return await task;
        operation.Cancel();
        throw new TimeoutException("BLUETOOTH_NATIVE_OPERATION_TIMEOUT");
    }

    public static async Task<string> Reconnect(string id)
    {
        using (var watch = new BluetoothWatch())
        {
            await Task.Delay(4000);
            var device = watch.Read(devices => devices.SingleOrDefault(d => MatchesId(d, id)));
            if (device == null || !device.Pairing.IsPaired) return "SAVED_PAIRED_ENDPOINT_NOT_OBSERVED";
            if (ReadFlag(device, ConnectedProperty) == true) return "ALREADY_CONNECTED";

            if (IsProtocol(device, LowEnergyProtocol))
            {
                using (var target = await WaitFor(BluetoothLEDevice.FromIdAsync(device.Id), 10000))
                {
                    if (target == null) return "LE_DEVICE_ACCESS_UNAVAILABLE";
                    var result = await WaitFor(target.GetGattServicesAsync(BluetoothCacheMode.Uncached), 15000);
                    foreach (var service in result.Services) service.Dispose();
                    return "GATT_DISCOVERY=" + result.Status;
                }
            }

            using (var target = await WaitFor(BluetoothDevice.FromIdAsync(device.Id), 10000))
            {
                if (target == null) return "CLASSIC_DEVICE_ACCESS_UNAVAILABLE";
                var result = await WaitFor(target.GetRfcommServicesAsync(BluetoothCacheMode.Uncached), 15000);
                foreach (var service in result.Services) service.Dispose();
                return "RFCOMM_DISCOVERY=" + result.Error;
            }
        }
    }

    public static Task<string> Run(string exactName) { return RunExact(exactName, null); }

    public static Task<string> RunExact(string exactName, string exactId)
    {
        return Pair(exactName, exactId, false);
    }

    public static Task<string> PairSaved(string id)
    {
        if (String.IsNullOrWhiteSpace(id)) throw new ArgumentException("SAVED_DEVICE_ID_REQUIRED");
        return Pair(null, id, true);
    }

    private static async Task<string> Pair(string exactName, string exactId, bool requirePresent)
    {
        using (var watch = new BluetoothWatch())
        {
            var stability = new StableMatchWindow();
            for (int attempt = 0; attempt < 80; attempt++)
            {
                var matches = watch.Read(devices => devices.Where(d =>
                    (exactName == null || d.Name == exactName)
                    && (String.IsNullOrEmpty(exactId) || MatchesId(d, exactId))
                    && (!requirePresent || ReadFlag(d, PresentProperty) == true)).ToArray());
                if (matches.Length > 1) return "AMBIGUOUS_NAME_USE_WINDOWS_UI";
                // The same ID must remain the sole match for about three seconds.
                if (stability.Observe(matches.Select(d => d.Id).ToArray()))
                {
                    var found = matches[0];
                    if (!requirePresent) Console.WriteLine("TARGET_FOUND=" + found.Name);
                    if (found.Pairing.IsPaired) return "ALREADY_PAIRED";
                    if (!found.Pairing.CanPair) return "TARGET_NOT_PAIRABLE";
                    var custom = found.Pairing.Custom;
                    custom.PairingRequested += (sender, request) =>
                    {
                        if (request.PairingKind == DevicePairingKinds.ConfirmOnly)
                            request.Accept();
                    };
                    try
                    {
                        return "PAIRING_RESULT=" + (await WaitFor(custom.PairAsync(DevicePairingKinds.ConfirmOnly), 30000)).Status;
                    }
                    catch (TimeoutException)
                    {
                        return "PAIRING_TIMEOUT_REQUIRES_INSPECTION";
                    }
                }
                await Task.Delay(250);
            }
            return "TARGET_NOT_DISCOVERED";
        }
    }
}
