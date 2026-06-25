using System;
using System.Collections.Generic;

namespace SysAdminSuite.DashboardHost;

/// <summary>
/// Parsed command-line options for the dashboard tray host.
/// Defaults match the existing Launch-SysAdminSuiteDashboard.ps1 behavior:
/// bind 127.0.0.1:5000, open default browser, show tray icon.
/// </summary>
public sealed class HostOptions
{
    public const int DefaultPort = 5000;
    public const string DefaultBindAddress = "127.0.0.1";

    public int Port { get; init; } = DefaultPort;
    public string BindAddress { get; init; } = DefaultBindAddress;
    public bool OpenBrowser { get; init; } = true;
    public bool ShowTray { get; init; } = true;
    public string? DashboardRootOverride { get; init; }

    public string Url => $"http://{BindAddress}:{Port}/dashboard/";

    public static HostOptions Parse(IReadOnlyList<string> args)
    {
        int port = DefaultPort;
        string bind = DefaultBindAddress;
        bool openBrowser = true;
        bool showTray = true;
        string? rootOverride = null;

        for (int i = 0; i < args.Count; i++)
        {
            var a = args[i];
            switch (a)
            {
                case "--port":
                    if (i + 1 < args.Count && int.TryParse(args[i + 1], out var p) && p > 0 && p < 65536)
                    {
                        port = p;
                        i++;
                    }
                    break;
                case "--bind":
                    if (i + 1 < args.Count)
                    {
                        bind = args[i + 1];
                        i++;
                    }
                    break;
                case "--no-browser":
                    openBrowser = false;
                    break;
                case "--no-tray":
                    showTray = false;
                    break;
                case "--dashboard-root":
                    if (i + 1 < args.Count)
                    {
                        rootOverride = args[i + 1];
                        i++;
                    }
                    break;
            }
        }

        return new HostOptions
        {
            Port = port,
            BindAddress = bind,
            OpenBrowser = openBrowser,
            ShowTray = showTray,
            DashboardRootOverride = rootOverride,
        };
    }
}
