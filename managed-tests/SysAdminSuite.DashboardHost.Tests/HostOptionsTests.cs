using SysAdminSuite.DashboardHost;
using Xunit;

namespace SysAdminSuite.DashboardHost.Tests;

public sealed class HostOptionsTests
{
    [Fact]
    public void Parse_NoArgs_UsesDefaults()
    {
        var options = HostOptions.Parse(System.Array.Empty<string>());
        Assert.Equal(HostOptions.DefaultPort, options.Port);
        Assert.Equal(HostOptions.DefaultBindAddress, options.BindAddress);
        Assert.True(options.OpenBrowser);
        Assert.True(options.ShowTray);
        Assert.Null(options.DashboardRootOverride);
        Assert.Equal("http://127.0.0.1:5000/dashboard/", options.Url);
    }

    [Fact]
    public void Parse_Port_Overrides()
    {
        var options = HostOptions.Parse(new[] { "--port", "5050" });
        Assert.Equal(5050, options.Port);
        Assert.Equal("http://127.0.0.1:5050/dashboard/", options.Url);
    }

    [Fact]
    public void Parse_InvalidPort_KeepsDefault()
    {
        var options = HostOptions.Parse(new[] { "--port", "not-a-number" });
        Assert.Equal(HostOptions.DefaultPort, options.Port);
    }

    [Fact]
    public void Parse_NoBrowserAndNoTray_FlagsAreRespected()
    {
        var options = HostOptions.Parse(new[] { "--no-browser", "--no-tray" });
        Assert.False(options.OpenBrowser);
        Assert.False(options.ShowTray);
    }

    [Fact]
    public void Parse_DashboardRootOverride_IsCaptured()
    {
        var options = HostOptions.Parse(new[] { "--dashboard-root", @"C:\custom\dashboard" });
        Assert.Equal(@"C:\custom\dashboard", options.DashboardRootOverride);
    }

    [Fact]
    public void Parse_Bind_Overrides()
    {
        var options = HostOptions.Parse(new[] { "--bind", "0.0.0.0", "--port", "8080" });
        Assert.Equal("0.0.0.0", options.BindAddress);
        Assert.Equal(8080, options.Port);
    }
}
