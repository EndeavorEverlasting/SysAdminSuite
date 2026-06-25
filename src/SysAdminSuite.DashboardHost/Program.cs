using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace SysAdminSuite.DashboardHost;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        var options = HostOptions.Parse(args);

        var dashboardRoot = options.DashboardRootOverride
            ?? RepoRootResolver.FindDashboardDirectory();

        if (string.IsNullOrEmpty(dashboardRoot) || !Directory.Exists(dashboardRoot))
        {
            ShowFatal("Dashboard folder not found. Expected a 'dashboard' directory next to the host executable or in a parent folder.");
            return 2;
        }

        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseUrls($"http://{options.BindAddress}:{options.Port}");

        var app = builder.Build();

        app.MapGet("/", (HttpContext ctx) =>
        {
            ctx.Response.Redirect(DashboardStaticServer.DashboardPrefix, permanent: false);
            return Task.CompletedTask;
        });

        app.Map("/dashboard/{**path}", (HttpContext ctx) => HandleDashboard(ctx, dashboardRoot!));
        app.Map("/dashboard", (HttpContext ctx) => HandleDashboard(ctx, dashboardRoot!));

        try
        {
            app.Start();
        }
        catch (Exception ex)
        {
            ShowFatal($"Failed to bind {options.BindAddress}:{options.Port}.\n{ex.Message}");
            return 3;
        }

        if (!options.ShowTray)
        {
            if (options.OpenBrowser) TryOpenBrowser(options.Url);
            app.WaitForShutdown();
            return 0;
        }

        Application.SetHighDpiMode(HighDpiMode.SystemAware);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        var trayCtx = new TrayApplicationContext(
            url: options.Url,
            tooltip: $"SysAdminSuite Dashboard ({options.BindAddress}:{options.Port})",
            stopAsync: () => app.StopAsync());

        if (options.OpenBrowser) TryOpenBrowser(options.Url);

        Application.Run(trayCtx);

        try { app.StopAsync().Wait(TimeSpan.FromSeconds(5)); } catch { }
        return 0;
    }

    private static async Task HandleDashboard(HttpContext ctx, string dashboardRoot)
    {
        var result = DashboardStaticServer.Resolve(ctx.Request.Path.Value ?? string.Empty, dashboardRoot);
        switch (result.Kind)
        {
            case DashboardStaticServer.ResultKind.Redirect:
                ctx.Response.StatusCode = 301;
                ctx.Response.Headers["Location"] = result.RedirectLocation!;
                return;
            case DashboardStaticServer.ResultKind.File:
                ctx.Response.StatusCode = 200;
                ctx.Response.ContentType = result.MimeType ?? DashboardStaticServer.DefaultMime;
                ctx.Response.Headers["Cache-Control"] = "no-cache";
                await ctx.Response.SendFileAsync(result.FilePath!);
                return;
            case DashboardStaticServer.ResultKind.Forbidden:
                ctx.Response.StatusCode = 403;
                await ctx.Response.WriteAsync("Forbidden");
                return;
            case DashboardStaticServer.ResultKind.BadRequest:
                ctx.Response.StatusCode = 400;
                await ctx.Response.WriteAsync("Bad request");
                return;
            case DashboardStaticServer.ResultKind.NotFound:
            case DashboardStaticServer.ResultKind.PassThrough:
            default:
                ctx.Response.StatusCode = 404;
                await ctx.Response.WriteAsync("Not found");
                return;
        }
    }

    private static void TryOpenBrowser(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch { /* user can still open from tray */ }
    }

    private static void ShowFatal(string message)
    {
        try
        {
            MessageBox.Show(message, "SysAdminSuite Dashboard Host",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        catch
        {
            Console.Error.WriteLine(message);
        }
    }
}
