using System;
using System.IO;
using SysAdminSuite.DashboardHost;
using Xunit;

namespace SysAdminSuite.DashboardHost.Tests;

public sealed class RepoRootResolverTests : IDisposable
{
    private readonly string _scratch;

    public RepoRootResolverTests()
    {
        _scratch = Path.Combine(Path.GetTempPath(), "sas-resolver-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_scratch);
    }

    public void Dispose()
    {
        try { Directory.Delete(_scratch, recursive: true); } catch { }
    }

    [Fact]
    public void FindDashboardDirectory_DevTreeLayout_LocatesDashboard()
    {
        var dashboardDir = Path.Combine(_scratch, "dashboard");
        Directory.CreateDirectory(dashboardDir);
        File.WriteAllText(Path.Combine(dashboardDir, "index.html"), "<html></html>");

        var fromNested = Path.Combine(_scratch, "src", "SysAdminSuite.DashboardHost", "bin", "Release", "net8.0-windows");
        Directory.CreateDirectory(fromNested);

        var found = RepoRootResolver.FindDashboardDirectory(fromNested);
        Assert.Equal(dashboardDir, found);
    }

    [Fact]
    public void FindDashboardDirectory_PortableAppLayout_LocatesDashboard()
    {
        var portable = Path.Combine(_scratch, "portable");
        var dashboardDir = Path.Combine(portable, "app", "dashboard");
        Directory.CreateDirectory(dashboardDir);
        File.WriteAllText(Path.Combine(dashboardDir, "index.html"), "<html></html>");

        var found = RepoRootResolver.FindDashboardDirectory(portable);
        Assert.Equal(dashboardDir, found);
    }

    [Fact]
    public void FindDashboardDirectory_NoDashboard_ReturnsNull()
    {
        var found = RepoRootResolver.FindDashboardDirectory(_scratch);
        Assert.Null(found);
    }
}
