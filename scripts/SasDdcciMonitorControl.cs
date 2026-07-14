using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace SysAdminSuite.DisplayControl
{
    public sealed class MonitorProbeResult
    {
        public int MonitorIndex { get; set; }
        public string Description { get; set; }
        public string Capabilities { get; set; }
        public bool CapabilitiesRead { get; set; }
        public string CapabilitiesError { get; set; }
        public bool VcpVersionRead { get; set; }
        public int MccsMajor { get; set; }
        public int MccsMinor { get; set; }
        public string MccsVersion { get; set; }
        public bool VcpCaAdvertised { get; set; }
        public bool VcpCaRead { get; set; }
        public uint VcpCaCurrentValue { get; set; }
        public string VcpCaCurrentHex { get; set; }
        public int OsdButtonControlByte { get; set; }
        public int PowerButtonControlByte { get; set; }
        public bool HostOsdButtonControlSupported { get; set; }
        public bool HostPowerButtonControlSupported { get; set; }
        public bool EligibleForButtonLock { get; set; }
        public string Classification { get; set; }
        public string Error { get; set; }
    }

    public sealed class MonitorMutationResult
    {
        public int MonitorIndex { get; set; }
        public string Description { get; set; }
        public string Operation { get; set; }
        public string Status { get; set; }
        public string MccsVersion { get; set; }
        public uint OriginalValue { get; set; }
        public string OriginalHex { get; set; }
        public uint DesiredValue { get; set; }
        public string DesiredHex { get; set; }
        public uint FinalValue { get; set; }
        public string FinalHex { get; set; }
        public bool MutationAttempted { get; set; }
        public bool MutationPerformed { get; set; }
        public bool VerificationPassed { get; set; }
        public bool RollbackAttempted { get; set; }
        public bool RollbackVerified { get; set; }
        public string Error { get; set; }
    }

    public static class MonitorController
    {
        public const byte MccsVersionCode = 0xDF;
        public const byte OsdButtonControlCode = 0xCA;
        public const uint LockedButtonValue = 0x0303;

        private const int ErrorNotSupported = 50;

        [StructLayout(LayoutKind.Sequential)]
        private struct Rect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct PhysicalMonitor
        {
            public IntPtr Handle;

            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string Description;
        }

        private sealed class PhysicalMonitorRef
        {
            public IntPtr Handle;
            public string Description;
        }

        private delegate bool MonitorEnumProc(IntPtr monitor, IntPtr hdc, ref Rect rect, IntPtr data);

        private enum VcpCodeType
        {
            Momentary = 0,
            SetParameter = 1
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool EnumDisplayMonitors(
            IntPtr hdc,
            IntPtr clip,
            MonitorEnumProc callback,
            IntPtr data);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(
            IntPtr logicalMonitor,
            out uint count);

        [DllImport("dxva2.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool GetPhysicalMonitorsFromHMONITOR(
            IntPtr logicalMonitor,
            uint arraySize,
            [Out] PhysicalMonitor[] physicalMonitorArray);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool DestroyPhysicalMonitor(IntPtr physicalMonitor);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool GetCapabilitiesStringLength(
            IntPtr physicalMonitor,
            out uint capabilitiesStringLength);

        [DllImport("dxva2.dll", SetLastError = true, CharSet = CharSet.Ansi)]
        private static extern bool CapabilitiesRequestAndCapabilitiesReply(
            IntPtr physicalMonitor,
            StringBuilder capabilitiesString,
            uint capabilitiesStringLength);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool GetVCPFeatureAndVCPFeatureReply(
            IntPtr physicalMonitor,
            byte vcpCode,
            out VcpCodeType vcpType,
            out uint currentValue,
            out uint maximumValue);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool SetVCPFeature(
            IntPtr physicalMonitor,
            byte vcpCode,
            uint newValue);

        public static MonitorProbeResult[] ProbeAll()
        {
            List<PhysicalMonitorRef> monitors = EnumeratePhysicalMonitors();
            try
            {
                List<MonitorProbeResult> results = new List<MonitorProbeResult>();
                for (int index = 0; index < monitors.Count; index++)
                {
                    results.Add(Probe(index, monitors[index]));
                }
                return results.ToArray();
            }
            finally
            {
                DestroyAll(monitors);
            }
        }

        public static MonitorMutationResult ApplyButtonLock(int requestedMonitorIndex)
        {
            return ExecuteMutation("Apply", requestedMonitorIndex, LockedButtonValue, true);
        }

        public static MonitorMutationResult RestoreButtonLock(int requestedMonitorIndex, uint restoreValue)
        {
            ValidateControlValue(restoreValue, "restore");
            return ExecuteMutation("Restore", requestedMonitorIndex, restoreValue, false);
        }

        private static MonitorMutationResult ExecuteMutation(
            string operation,
            int requestedMonitorIndex,
            uint desiredValue,
            bool requireEligibleLockState)
        {
            List<PhysicalMonitorRef> monitors = EnumeratePhysicalMonitors();
            try
            {
                MonitorProbeResult[] probes = new MonitorProbeResult[monitors.Count];
                for (int index = 0; index < monitors.Count; index++)
                {
                    probes[index] = Probe(index, monitors[index]);
                }

                int selectedIndex = SelectMonitorIndex(probes, requestedMonitorIndex, requireEligibleLockState);
                MonitorProbeResult selected = probes[selectedIndex];
                PhysicalMonitorRef monitor = monitors[selectedIndex];

                MonitorMutationResult result = new MonitorMutationResult
                {
                    MonitorIndex = selectedIndex,
                    Description = selected.Description,
                    Operation = operation,
                    Status = "NOT_STARTED",
                    MccsVersion = selected.MccsVersion,
                    DesiredValue = desiredValue,
                    DesiredHex = Hex(desiredValue),
                    OriginalValue = selected.VcpCaCurrentValue,
                    OriginalHex = Hex(selected.VcpCaCurrentValue)
                };

                if (!selected.VcpCaRead)
                {
                    result.Status = "REFUSED_VCP_CA_UNREADABLE";
                    result.Error = selected.Error;
                    return result;
                }

                if (!IsMccs22OrLater(selected))
                {
                    result.Status = "REFUSED_MCCS_PRE_2_2";
                    result.Error = "VCP 0xCA button-control bytes require confirmed MCCS 2.2 or later.";
                    return result;
                }

                if (requireEligibleLockState && !selected.EligibleForButtonLock)
                {
                    result.Status = "REFUSED_HOST_CONTROL_UNSUPPORTED";
                    result.Error = selected.Classification;
                    return result;
                }

                if (selected.VcpCaCurrentValue == desiredValue)
                {
                    result.Status = operation == "Apply" ? "ALREADY_LOCKED_VERIFIED" : "ALREADY_RESTORED_VERIFIED";
                    result.FinalValue = selected.VcpCaCurrentValue;
                    result.FinalHex = Hex(selected.VcpCaCurrentValue);
                    result.VerificationPassed = true;
                    return result;
                }

                result.MutationAttempted = true;
                if (!SetVCPFeature(monitor.Handle, OsdButtonControlCode, desiredValue))
                {
                    result.Status = "SET_FAILED";
                    result.Error = LastError("SetVCPFeature(0xCA)");
                    return result;
                }

                result.MutationPerformed = true;
                Thread.Sleep(300);

                uint finalValue;
                string readError;
                if (TryReadVcp(monitor.Handle, OsdButtonControlCode, out finalValue, out readError))
                {
                    result.FinalValue = finalValue;
                    result.FinalHex = Hex(finalValue);
                    result.VerificationPassed = finalValue == desiredValue;
                }
                else
                {
                    result.Error = readError;
                }

                if (result.VerificationPassed)
                {
                    result.Status = operation == "Apply" ? "APPLIED_VERIFIED" : "RESTORED_VERIFIED";
                    return result;
                }

                result.Status = "VERIFY_FAILED_ROLLBACK_PENDING";
                result.RollbackAttempted = true;
                if (SetVCPFeature(monitor.Handle, OsdButtonControlCode, selected.VcpCaCurrentValue))
                {
                    Thread.Sleep(300);
                    uint rollbackValue;
                    string rollbackReadError;
                    if (TryReadVcp(monitor.Handle, OsdButtonControlCode, out rollbackValue, out rollbackReadError))
                    {
                        result.RollbackVerified = rollbackValue == selected.VcpCaCurrentValue;
                        result.FinalValue = rollbackValue;
                        result.FinalHex = Hex(rollbackValue);
                    }
                    else
                    {
                        result.Error = AppendError(result.Error, rollbackReadError);
                    }
                }
                else
                {
                    result.Error = AppendError(result.Error, LastError("rollback SetVCPFeature(0xCA)"));
                }

                result.Status = result.RollbackVerified
                    ? "VERIFY_FAILED_ROLLED_BACK"
                    : "VERIFY_FAILED_ROLLBACK_UNVERIFIED";
                return result;
            }
            finally
            {
                DestroyAll(monitors);
            }
        }

        private static MonitorProbeResult Probe(int index, PhysicalMonitorRef monitor)
        {
            MonitorProbeResult result = new MonitorProbeResult
            {
                MonitorIndex = index,
                Description = monitor.Description ?? string.Empty,
                Capabilities = string.Empty,
                CapabilitiesError = string.Empty,
                Error = string.Empty,
                Classification = "UNCLASSIFIED",
                MccsVersion = "unknown"
            };

            uint capabilitiesLength;
            if (GetCapabilitiesStringLength(monitor.Handle, out capabilitiesLength) && capabilitiesLength > 0)
            {
                StringBuilder builder = new StringBuilder((int)capabilitiesLength);
                if (CapabilitiesRequestAndCapabilitiesReply(monitor.Handle, builder, capabilitiesLength))
                {
                    result.CapabilitiesRead = true;
                    result.Capabilities = builder.ToString();
                    result.VcpCaAdvertised = Regex.IsMatch(
                        result.Capabilities,
                        @"(?i)(?:^|[\s(])ca(?:[\s(]|$)");
                }
                else
                {
                    result.CapabilitiesError = LastError("CapabilitiesRequestAndCapabilitiesReply");
                }
            }
            else
            {
                int error = Marshal.GetLastWin32Error();
                if (error != 0 && error != ErrorNotSupported)
                {
                    result.CapabilitiesError = "GetCapabilitiesStringLength failed with Win32 error " + error + ".";
                }
            }

            uint versionValue;
            string versionError;
            if (TryReadVcp(monitor.Handle, MccsVersionCode, out versionValue, out versionError))
            {
                result.VcpVersionRead = true;
                result.MccsMajor = (int)((versionValue >> 8) & 0xFF);
                result.MccsMinor = (int)(versionValue & 0xFF);
                result.MccsVersion = result.MccsMajor + "." + result.MccsMinor;
            }
            else
            {
                result.Error = AppendError(result.Error, versionError);
            }

            uint caValue;
            string caError;
            if (TryReadVcp(monitor.Handle, OsdButtonControlCode, out caValue, out caError))
            {
                result.VcpCaRead = true;
                result.VcpCaCurrentValue = caValue & 0xFFFF;
                result.VcpCaCurrentHex = Hex(result.VcpCaCurrentValue);
                result.OsdButtonControlByte = (int)(caValue & 0xFF);
                result.PowerButtonControlByte = (int)((caValue >> 8) & 0xFF);
                result.HostOsdButtonControlSupported = IsSupportedControlByte(result.OsdButtonControlByte);
                result.HostPowerButtonControlSupported = IsSupportedControlByte(result.PowerButtonControlByte);
            }
            else
            {
                result.Error = AppendError(result.Error, caError);
            }

            if (!result.VcpCaRead)
            {
                result.Classification = "VCP_CA_UNREADABLE";
            }
            else if (!result.VcpVersionRead)
            {
                result.Classification = "MCCS_VERSION_UNREADABLE";
            }
            else if (!IsMccs22OrLater(result))
            {
                result.Classification = "MCCS_PRE_2_2_OSD_ONLY";
            }
            else if (!result.HostOsdButtonControlSupported || !result.HostPowerButtonControlSupported)
            {
                result.Classification = "HOST_BUTTON_CONTROL_UNSUPPORTED";
            }
            else
            {
                result.EligibleForButtonLock = true;
                result.Classification = "VCP_CA_V22_BUTTON_LOCK_READY";
            }

            return result;
        }

        private static int SelectMonitorIndex(
            MonitorProbeResult[] probes,
            int requestedMonitorIndex,
            bool requireEligible)
        {
            if (requestedMonitorIndex >= 0)
            {
                if (requestedMonitorIndex >= probes.Length)
                {
                    throw new InvalidOperationException("Requested physical monitor index is outside the enumerated range.");
                }
                return requestedMonitorIndex;
            }

            List<int> candidates = new List<int>();
            for (int index = 0; index < probes.Length; index++)
            {
                if (!requireEligible || probes[index].EligibleForButtonLock)
                {
                    candidates.Add(index);
                }
            }

            if (candidates.Count == 1)
            {
                return candidates[0];
            }

            if (candidates.Count == 0)
            {
                throw new InvalidOperationException("No eligible physical monitor exposes MCCS 2.2 VCP 0xCA host button control.");
            }

            throw new InvalidOperationException(
                "Multiple eligible physical monitors were found. Supply an explicit -MonitorIndex after a probe run.");
        }

        private static List<PhysicalMonitorRef> EnumeratePhysicalMonitors()
        {
            List<IntPtr> logicalMonitors = new List<IntPtr>();
            MonitorEnumProc callback = delegate(IntPtr monitor, IntPtr hdc, ref Rect rect, IntPtr data)
            {
                logicalMonitors.Add(monitor);
                return true;
            };

            if (!EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero))
            {
                throw new InvalidOperationException(LastError("EnumDisplayMonitors"));
            }

            List<PhysicalMonitorRef> physicalMonitors = new List<PhysicalMonitorRef>();
            foreach (IntPtr logicalMonitor in logicalMonitors)
            {
                uint count;
                if (!GetNumberOfPhysicalMonitorsFromHMONITOR(logicalMonitor, out count) || count == 0)
                {
                    continue;
                }

                PhysicalMonitor[] nativeMonitors = new PhysicalMonitor[count];
                if (!GetPhysicalMonitorsFromHMONITOR(logicalMonitor, count, nativeMonitors))
                {
                    DestroyAll(physicalMonitors);
                    throw new InvalidOperationException(LastError("GetPhysicalMonitorsFromHMONITOR"));
                }

                foreach (PhysicalMonitor nativeMonitor in nativeMonitors)
                {
                    physicalMonitors.Add(new PhysicalMonitorRef
                    {
                        Handle = nativeMonitor.Handle,
                        Description = nativeMonitor.Description
                    });
                }
            }

            if (physicalMonitors.Count == 0)
            {
                throw new InvalidOperationException(
                    "No physical monitors were exposed through the Windows Monitor Configuration API.");
            }

            return physicalMonitors;
        }

        private static bool TryReadVcp(IntPtr monitor, byte code, out uint currentValue, out string error)
        {
            VcpCodeType type;
            uint maximumValue;
            currentValue = 0;
            if (GetVCPFeatureAndVCPFeatureReply(monitor, code, out type, out currentValue, out maximumValue))
            {
                currentValue &= 0xFFFF;
                error = string.Empty;
                return true;
            }

            error = LastError("GetVCPFeatureAndVCPFeatureReply(0x" + code.ToString("X2") + ")");
            return false;
        }

        private static bool IsMccs22OrLater(MonitorProbeResult result)
        {
            return result.VcpVersionRead &&
                (result.MccsMajor > 2 || (result.MccsMajor == 2 && result.MccsMinor >= 2));
        }

        private static bool IsSupportedControlByte(int value)
        {
            return value >= 1 && value <= 3;
        }

        private static void ValidateControlValue(uint value, string role)
        {
            int low = (int)(value & 0xFF);
            int high = (int)((value >> 8) & 0xFF);
            if (!IsSupportedControlByte(low) || !IsSupportedControlByte(high))
            {
                throw new ArgumentOutOfRangeException(
                    role + "Value",
                    "VCP 0xCA restore values must contain supported MCCS 2.2 control bytes 0x01 through 0x03.");
            }
        }

        private static void DestroyAll(List<PhysicalMonitorRef> monitors)
        {
            if (monitors == null)
            {
                return;
            }

            foreach (PhysicalMonitorRef monitor in monitors)
            {
                if (monitor != null && monitor.Handle != IntPtr.Zero)
                {
                    DestroyPhysicalMonitor(monitor.Handle);
                    monitor.Handle = IntPtr.Zero;
                }
            }
        }

        private static string Hex(uint value)
        {
            return "0x" + (value & 0xFFFF).ToString("X4");
        }

        private static string LastError(string operation)
        {
            int error = Marshal.GetLastWin32Error();
            return operation + " failed with Win32 error " + error + ".";
        }

        private static string AppendError(string existing, string next)
        {
            if (string.IsNullOrWhiteSpace(existing))
            {
                return next ?? string.Empty;
            }
            if (string.IsNullOrWhiteSpace(next))
            {
                return existing;
            }
            return existing + " | " + next;
        }
    }
}
