using System;
using System.IO;

namespace SysAdminSuite.DashboardHost;

/// <summary>
/// Locates the dashboard/ directory relative to the executing assembly.
/// Supports both dev-tree layout (repo\src\SysAdminSuite.DashboardHost\bin\...)
/// and portable layout (root\app\dashboard plus root\app\bin\... if published in place).
/// </summary>
public static class RepoRootResolver
{
    public const string DashboardFolderName = "dashboard";
    public const string DashboardIndex = "index.html";

    public static string? FindDashboardDirectory(string? startDirectory = null)
    {
        var start = startDirectory ?? AppContext.BaseDirectory;
        if (string.IsNullOrEmpty(start)) return null;

        var current = new DirectoryInfo(start);
        for (int hops = 0; hops < 12 && current != null; hops++)
        {
            var candidate = Path.Combine(current.FullName, DashboardFolderName, DashboardIndex);
            if (File.Exists(candidate))
            {
                return Path.Combine(current.FullName, DashboardFolderName);
            }
            // Portable layout: when EXE lives alongside an app\ folder.
            var appCandidate = Path.Combine(current.FullName, "app", DashboardFolderName, DashboardIndex);
            if (File.Exists(appCandidate))
            {
                return Path.Combine(current.FullName, "app", DashboardFolderName);
            }
            current = current.Parent;
        }
        return null;
    }
}
