using System;
using System.Diagnostics;
using System.Drawing;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace SysAdminSuite.DashboardHost;

/// <summary>
/// NotifyIcon-driven application context. Owns the tray icon and provides
/// menu entries (Open, Copy URL, Stop) that drive the supplied stop callback.
/// </summary>
public sealed class TrayApplicationContext : ApplicationContext
{
    private readonly NotifyIcon _notifyIcon;
    private readonly string _url;
    private readonly Func<Task> _stopAsync;
    private bool _stopping;

    public TrayApplicationContext(string url, string tooltip, Func<Task> stopAsync)
    {
        _url = url;
        _stopAsync = stopAsync;

        var menu = new ContextMenuStrip();
        var openItem = new ToolStripMenuItem("Open Dashboard");
        openItem.Click += (_, _) => OpenBrowser();
        var copyItem = new ToolStripMenuItem("Copy URL");
        copyItem.Click += (_, _) => CopyUrl();
        var stopItem = new ToolStripMenuItem("Stop Dashboard");
        stopItem.Click += (_, _) => BeginShutdown();
        menu.Items.Add(openItem);
        menu.Items.Add(copyItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(stopItem);

        _notifyIcon = new NotifyIcon
        {
            Icon = CreateTrayIcon(),
            Text = TruncateForTooltip(tooltip),
            Visible = true,
            ContextMenuStrip = menu,
            BalloonTipTitle = "SysAdminSuite Dashboard",
            BalloonTipText = "Server is running. Right-click the tray icon to stop.",
            BalloonTipIcon = ToolTipIcon.Info,
        };
        _notifyIcon.DoubleClick += (_, _) => OpenBrowser();
        _notifyIcon.ShowBalloonTip(4000);
    }

    public void NotifyError(string title, string message)
    {
        if (_notifyIcon.Visible)
        {
            _notifyIcon.BalloonTipTitle = title;
            _notifyIcon.BalloonTipText = message;
            _notifyIcon.BalloonTipIcon = ToolTipIcon.Error;
            _notifyIcon.ShowBalloonTip(8000);
        }
    }

    private void OpenBrowser()
    {
        try
        {
            Process.Start(new ProcessStartInfo(_url) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            NotifyError("SysAdminSuite Dashboard", "Could not open browser: " + ex.Message);
        }
    }

    private void CopyUrl()
    {
        try { Clipboard.SetText(_url); }
        catch { /* clipboard can race; ignore */ }
    }

    private void BeginShutdown()
    {
        if (_stopping) return;
        _stopping = true;
        _ = Task.Run(async () =>
        {
            try { await _stopAsync(); }
            catch { /* swallow - shutdown is best effort */ }
            finally
            {
                try { _notifyIcon.Visible = false; } catch { }
                try { _notifyIcon.Dispose(); } catch { }
                Application.Exit();
            }
        });
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            try { _notifyIcon.Visible = false; } catch { }
            try { _notifyIcon.Dispose(); } catch { }
        }
        base.Dispose(disposing);
    }

    private static string TruncateForTooltip(string text)
        => string.IsNullOrEmpty(text) ? "SysAdminSuite Dashboard"
            : text.Length <= 63 ? text : text.Substring(0, 63);

    private static Icon CreateTrayIcon()
    {
        using var bmp = new Bitmap(16, 16);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.SteelBlue);
        }
        var hicon = bmp.GetHicon();
        return Icon.FromHandle(hicon);
    }
}
