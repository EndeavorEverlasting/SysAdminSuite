// Windows-only Core Audio bridge. Built into the interactive user's PowerShell process.
// No NuGet packages, machine policy change, service restart, or cross-app volume changes.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace SasChromeAudio
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        void EnumAudioEndpoints(int dataFlow, uint stateMask, out IMMDeviceCollection devices);
        void GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        void GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        void RegisterEndpointNotificationCallback(IntPtr client);
        void UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-C0A49E1ABF5B"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceCollection
    {
        void GetCount(out uint count);
        void Item(uint index, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        void Activate(ref Guid iid, uint clsCtx, IntPtr activationParams,
            [MarshalAs(UnmanagedType.IUnknown)] out object result);
        void OpenPropertyStore(uint access, out IntPtr store);
        void GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        void GetState(out uint state);
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionManager2
    {
        void GetAudioSessionControl(ref Guid id, uint flags, out IntPtr control);
        void GetSimpleAudioVolume(ref Guid id, uint flags, out IntPtr volume);
        void GetSessionEnumerator(out IAudioSessionEnumerator enumerator);
        void RegisterSessionNotification(IntPtr client);
        void UnregisterSessionNotification(IntPtr client);
        void RegisterDuckNotification(IntPtr sessionId, IntPtr client);
        void UnregisterDuckNotification(IntPtr client);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionEnumerator
    {
        void GetCount(out int count);
        void GetSession(int index, out IAudioSessionControl2 control);
    }

    // Flattened inherited IAudioSessionControl methods preserve COM vtable order.
    [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionControl2
    {
        void GetState(out int state);
        void GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        void SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string name, ref Guid context);
        void GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
        void SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string path, ref Guid context);
        void GetGroupingParam(out Guid grouping);
        void SetGroupingParam(ref Guid grouping, ref Guid context);
        void RegisterAudioSessionNotification(IntPtr client);
        void UnregisterAudioSessionNotification(IntPtr client);
        void GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        void GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        void GetProcessId(out uint pid);
        void IsSystemSoundsSession();
        void SetDuckingPreference([MarshalAs(UnmanagedType.Bool)] bool optOut);
    }

    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface ISimpleAudioVolume
    {
        void SetMasterVolume(float level, ref Guid context);
        void GetMasterVolume(out float level);
        void SetMute([MarshalAs(UnmanagedType.Bool)] bool muted, ref Guid context);
        void GetMute([MarshalAs(UnmanagedType.Bool)] out bool muted);
    }

    public sealed class SessionEntry
    {
        public int ProcessId { get; set; }
        public string DeviceId { get; set; }
        public bool IsDefaultDevice { get; set; }
        public string SessionState { get; set; }
        public int BeforeVolumePercent { get; set; }
        public bool BeforeMuted { get; set; }
        public int VolumePercent { get; set; }
        public bool Muted { get; set; }
        public bool RepairApplied { get; set; }
    }

    public static class CoreAudio
    {
        // Enumerates active playback endpoints; only chrome.exe-owned sessions are returned.
        // A missing session is an observation, NEVER authorization for a system-wide reset.
        public static List<SessionEntry> Scan(bool repair, int zeroVolumeRecoveryPercent)
        {
            if (Environment.OSVersion.Platform != PlatformID.Win32NT)
                throw new PlatformNotSupportedException("WINDOWS_INTERACTIVE_HOST_REQUIRED");
            if (zeroVolumeRecoveryPercent < 1 || zeroVolumeRecoveryPercent > 50)
                throw new ArgumentOutOfRangeException("zeroVolumeRecoveryPercent");

            var output = new List<SessionEntry>();
            var deviceEnumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
            IMMDevice defaultDevice;
            deviceEnumerator.GetDefaultAudioEndpoint(0, 1, out defaultDevice);
            string defaultId;
            defaultDevice.GetId(out defaultId);

            IMMDeviceCollection devices;
            deviceEnumerator.EnumAudioEndpoints(0, 1, out devices);
            uint count;
            devices.GetCount(out count);
            var managerId = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");

            for (uint deviceIndex = 0; deviceIndex < count; deviceIndex++)
            {
                IMMDevice device;
                devices.Item(deviceIndex, out device);
                string deviceId;
                device.GetId(out deviceId);
                object managerObject;
                device.Activate(ref managerId, 23, IntPtr.Zero, out managerObject);
                var manager = (IAudioSessionManager2)managerObject;
                IAudioSessionEnumerator sessions;
                manager.GetSessionEnumerator(out sessions);
                int sessionCount;
                sessions.GetCount(out sessionCount);

                for (int i = 0; i < sessionCount; i++)
                {
                    IAudioSessionControl2 session;
                    sessions.GetSession(i, out session);
                    uint processId;
                    session.GetProcessId(out processId);
                    if (processId == 0 || processId > Int32.MaxValue) continue;

                    string processName;
                    try
                    {
                        using (var process = Process.GetProcessById((int)processId))
                            processName = process.ProcessName;
                    }
                    catch (ArgumentException) { continue; }
                    catch (InvalidOperationException) { continue; }
                    if (!String.Equals(processName, "chrome", StringComparison.OrdinalIgnoreCase))
                        continue;

                    int state;
                    session.GetState(out state);
                    var volume = (ISimpleAudioVolume)session;
                    float beforeLevel;
                    bool beforeMuted;
                    volume.GetMasterVolume(out beforeLevel);
                    volume.GetMute(out beforeMuted);
                    bool changed = false;

                    // Only a signed-in operator's explicit Repair may modify Chrome.
                    // Inactive sessions and all other apps are never changed.
                    if (repair && state == 1)
                    {
                        var context = Guid.NewGuid();
                        if (beforeMuted)
                        {
                            volume.SetMute(false, ref context);
                            changed = true;
                        }
                        if (beforeLevel <= 0.0001f)
                        {
                            volume.SetMasterVolume(zeroVolumeRecoveryPercent / 100f, ref context);
                            changed = true;
                        }
                    }

                    float afterLevel;
                    bool afterMuted;
                    volume.GetMasterVolume(out afterLevel);
                    volume.GetMute(out afterMuted);
                    output.Add(new SessionEntry
                    {
                        ProcessId = (int)processId,
                        DeviceId = deviceId,
                        IsDefaultDevice = String.Equals(defaultId, deviceId, StringComparison.OrdinalIgnoreCase),
                        SessionState = state == 1 ? "ACTIVE" : (state == 0 ? "INACTIVE" : "EXPIRED"),
                        BeforeVolumePercent = (int)Math.Round(beforeLevel * 100),
                        BeforeMuted = beforeMuted,
                        VolumePercent = (int)Math.Round(afterLevel * 100),
                        Muted = afterMuted,
                        RepairApplied = changed
                    });
                }
            }
            return output;
        }
    }
}
