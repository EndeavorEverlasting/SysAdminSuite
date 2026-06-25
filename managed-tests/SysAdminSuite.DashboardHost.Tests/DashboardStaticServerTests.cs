using System;
using System.IO;
using SysAdminSuite.DashboardHost;
using Xunit;

namespace SysAdminSuite.DashboardHost.Tests;

public sealed class DashboardStaticServerTests : IDisposable
{
    private readonly string _root;

    public DashboardStaticServerTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "sas-dashhost-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
        File.WriteAllText(Path.Combine(_root, "index.html"), "<html></html>");
        var jsDir = Path.Combine(_root, "js");
        Directory.CreateDirectory(jsDir);
        File.WriteAllText(Path.Combine(jsDir, "app.js"), "console.log('ok');");
        File.WriteAllText(Path.Combine(_root, "style.css"), "body{}");
        File.WriteAllText(Path.Combine(_root, "sample.json"), "{}");
        var assetsDir = Path.Combine(_root, "assets");
        Directory.CreateDirectory(assetsDir);
        File.WriteAllText(Path.Combine(assetsDir, "harold.jpg"), "jpegbytes");
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    [Fact]
    public void Resolve_BareDashboard_RedirectsToSlash()
    {
        var result = DashboardStaticServer.Resolve("/dashboard", _root);
        Assert.Equal(DashboardStaticServer.ResultKind.Redirect, result.Kind);
        Assert.Equal("/dashboard/", result.RedirectLocation);
    }

    [Fact]
    public void Resolve_DashboardSlash_ReturnsIndexHtml()
    {
        var result = DashboardStaticServer.Resolve("/dashboard/", _root);
        Assert.Equal(DashboardStaticServer.ResultKind.File, result.Kind);
        Assert.Equal(Path.Combine(_root, "index.html"), result.FilePath);
        Assert.Equal("text/html; charset=utf-8", result.MimeType);
    }

    [Fact]
    public void Resolve_KnownJs_ReturnsJavascriptMime()
    {
        var result = DashboardStaticServer.Resolve("/dashboard/js/app.js", _root);
        Assert.Equal(DashboardStaticServer.ResultKind.File, result.Kind);
        Assert.Equal("application/javascript; charset=utf-8", result.MimeType);
    }

    [Theory]
    [InlineData("/dashboard/style.css", "text/css; charset=utf-8")]
    [InlineData("/dashboard/sample.json", "application/json; charset=utf-8")]
    [InlineData("/dashboard/assets/harold.jpg", "image/jpeg")]
    public void Resolve_KnownMimeTypes_AreApplied(string url, string expectedMime)
    {
        var result = DashboardStaticServer.Resolve(url, _root);
        Assert.Equal(DashboardStaticServer.ResultKind.File, result.Kind);
        Assert.Equal(expectedMime, result.MimeType);
    }

    [Fact]
    public void Resolve_TraversalAttempt_IsForbidden()
    {
        var result = DashboardStaticServer.Resolve("/dashboard/../secret.txt", _root);
        Assert.True(
            result.Kind == DashboardStaticServer.ResultKind.Forbidden ||
            result.Kind == DashboardStaticServer.ResultKind.NotFound,
            $"Expected Forbidden or NotFound, got {result.Kind}");
        Assert.NotEqual(DashboardStaticServer.ResultKind.File, result.Kind);
    }

    [Fact]
    public void Resolve_AbsoluteWindowsPath_IsForbidden()
    {
        var result = DashboardStaticServer.Resolve("/dashboard/C:/Windows/win.ini", _root);
        Assert.NotEqual(DashboardStaticServer.ResultKind.File, result.Kind);
    }

    [Fact]
    public void Resolve_MissingFile_Returns404()
    {
        var result = DashboardStaticServer.Resolve("/dashboard/no-such-file.html", _root);
        Assert.Equal(DashboardStaticServer.ResultKind.NotFound, result.Kind);
    }

    [Fact]
    public void Resolve_UnknownPrefix_IsPassThrough()
    {
        var result = DashboardStaticServer.Resolve("/api/foo", _root);
        Assert.Equal(DashboardStaticServer.ResultKind.PassThrough, result.Kind);
    }

    [Fact]
    public void Resolve_EmptyPath_IsBadRequest()
    {
        var result = DashboardStaticServer.Resolve("", _root);
        Assert.Equal(DashboardStaticServer.ResultKind.BadRequest, result.Kind);
    }

    [Fact]
    public void GetMimeType_UnknownExtension_FallsBackToOctetStream()
    {
        Assert.Equal(DashboardStaticServer.DefaultMime, DashboardStaticServer.GetMimeType(".xyz"));
    }
}
