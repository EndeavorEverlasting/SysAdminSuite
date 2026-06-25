using System;
using System.Collections.Generic;
using System.IO;

namespace SysAdminSuite.DashboardHost;

/// <summary>
/// Pure path-resolution and MIME logic for the dashboard static surface.
/// Mirrors the rules in server.py do_GET (lines 562-598) so the .NET host
/// behaves identically to the Python launcher on /dashboard/* requests.
/// </summary>
public static class DashboardStaticServer
{
    public const string DashboardPrefix = "/dashboard/";
    public const string DashboardBare = "/dashboard";
    public const string DefaultMime = "application/octet-stream";

    public static readonly IReadOnlyDictionary<string, string> MimeTypes =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            [".html"] = "text/html; charset=utf-8",
            [".css"] = "text/css; charset=utf-8",
            [".js"] = "application/javascript; charset=utf-8",
            [".json"] = "application/json; charset=utf-8",
            [".png"] = "image/png",
            [".jpg"] = "image/jpeg",
            [".jpeg"] = "image/jpeg",
            [".svg"] = "image/svg+xml",
            [".ico"] = "image/x-icon",
        };

    public enum ResultKind { Redirect, File, NotFound, Forbidden, BadRequest, PassThrough }

    public sealed record ResolveResult(
        ResultKind Kind,
        string? FilePath = null,
        string? MimeType = null,
        string? RedirectLocation = null);

    public static string GetMimeType(string extension)
    {
        if (string.IsNullOrEmpty(extension)) return DefaultMime;
        return MimeTypes.TryGetValue(extension, out var mime) ? mime : DefaultMime;
    }

    /// <summary>
    /// Resolve an incoming URL path against the dashboard root.
    /// </summary>
    /// <param name="urlPath">URL path without query string (e.g. "/dashboard/js/app.js").</param>
    /// <param name="dashboardRoot">Absolute path to the dashboard/ directory.</param>
    public static ResolveResult Resolve(string urlPath, string dashboardRoot)
    {
        if (string.IsNullOrEmpty(urlPath))
        {
            return new ResolveResult(ResultKind.BadRequest);
        }
        if (string.IsNullOrEmpty(dashboardRoot))
        {
            return new ResolveResult(ResultKind.NotFound);
        }

        if (string.Equals(urlPath, DashboardBare, StringComparison.Ordinal))
        {
            return new ResolveResult(ResultKind.Redirect, RedirectLocation: DashboardPrefix);
        }

        if (string.Equals(urlPath, DashboardPrefix, StringComparison.Ordinal))
        {
            var index = Path.Combine(dashboardRoot, "index.html");
            if (!File.Exists(index))
            {
                return new ResolveResult(ResultKind.NotFound);
            }
            return new ResolveResult(ResultKind.File, FilePath: index, MimeType: GetMimeType(".html"));
        }

        if (!urlPath.StartsWith(DashboardPrefix, StringComparison.Ordinal))
        {
            return new ResolveResult(ResultKind.PassThrough);
        }

        var relative = urlPath.Substring(DashboardPrefix.Length);
        if (string.IsNullOrEmpty(relative))
        {
            return new ResolveResult(ResultKind.BadRequest);
        }
        if (relative.IndexOfAny(Path.GetInvalidPathChars()) >= 0)
        {
            return new ResolveResult(ResultKind.BadRequest);
        }

        string candidate;
        string rootFull;
        try
        {
            candidate = Path.GetFullPath(Path.Combine(dashboardRoot, relative));
            rootFull = Path.GetFullPath(dashboardRoot);
        }
        catch (Exception)
        {
            return new ResolveResult(ResultKind.BadRequest);
        }

        var rootWithSep = rootFull.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            + Path.DirectorySeparatorChar;
        if (!candidate.StartsWith(rootWithSep, StringComparison.OrdinalIgnoreCase)
            && !string.Equals(candidate, rootFull, StringComparison.OrdinalIgnoreCase))
        {
            return new ResolveResult(ResultKind.Forbidden);
        }

        if (!File.Exists(candidate))
        {
            return new ResolveResult(ResultKind.NotFound);
        }

        var mime = GetMimeType(Path.GetExtension(candidate));
        return new ResolveResult(ResultKind.File, FilePath: candidate, MimeType: mime);
    }
}
