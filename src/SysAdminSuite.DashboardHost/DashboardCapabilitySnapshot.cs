using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SysAdminSuite.DashboardHost;

/// <summary>
/// Read-only, allowlisted projection of repository capability and local receipt metadata.
/// Never returns raw field evidence, receipt paths, host identity, target identifiers or secrets.
/// A receipt's existence is NOT proof of success or live device acceptance.
/// </summary>
public static class DashboardCapabilitySnapshot
{
    private static readonly HashSet<string> SafeStates = new(StringComparer.Ordinal)
    {
        "SUCCESS", "PASS", "PASSED", "FAIL", "FAILED", "BLOCKED", "INCOMPLETE",
        "READY", "UNKNOWN", "NOT_YET_TESTED", "PROVEN_NEGATIVE",
        "ADB_HOST_NOT_INSTALLED", "ADB_HOST_READY", "ADB_DEVICE_UNAUTHORIZED",
        "ADB_DEVICE_OFFLINE", "ADB_DEVICE_READY", "USB_DEVICE_NOT_ENUMERATED",
        "USB_DEVICE_ENUMERATED_NO_ADB_INTERFACE", "USB_DRIVER_OR_INTERFACE_UNRESOLVED",
        "BASELINE_INCOMPLETE", "BASELINE_LOCKED", "NETWORK_ADB_REVERT_FAILED",
        "QUALIFICATION_AUTHORITY_REQUIRED", "ADMINBOX_PROFILE_AUTHORITY_REQUIRED",
        "SOURCE_AUTHORITY_REQUIRED", "AUTHORITY_GATE", "CREDENTIAL_GATE",
        "POLICY_REJECTED", "DEFERRED_TOPOLOGY_UNAVAILABLE",
        "DEFERRED_OPERATOR_PRESENCE_REQUIRED", "INCONCLUSIVE_ATTENDED_GATE",
        "VERSION_DOMAIN_UNRESOLVED", "AWAITING_FIELD_OBSERVATION",
        "HOME_LAB_EXACT_MAC_NOT_FOUND_AFTER_REACQUISITION"
    };

    public static bool IsLocalRequest(IPAddress? remote, string? host)
    {
        if (remote is null || string.IsNullOrWhiteSpace(host)) return false;
        var client = remote.IsIPv4MappedToIPv6 ? remote.MapToIPv4() : remote;
        var normalized = host.Trim('[', ']').ToLowerInvariant();
        return IPAddress.IsLoopback(client)
            && (normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1");
    }

    private static string Domain(string id) =>
        id.StartsWith("hh-cc-reader-", StringComparison.Ordinal) ? "CC readers" :
        id.StartsWith("android-", StringComparison.Ordinal) ? "Android / ADB" :
        id.StartsWith("autologon-", StringComparison.Ordinal) ? "Autologon" :
        id.StartsWith("cybernet-", StringComparison.Ordinal) ? "Cybernet" :
        id.StartsWith("dashboard-", StringComparison.Ordinal) ? "Dashboard" :
        id.StartsWith("harness-", StringComparison.Ordinal) ? "Harness" :
        id.StartsWith("operator-", StringComparison.Ordinal) ? "Operator" :
        "Other SAS operations";

    private static JsonElement ReadRoot(string path)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        return doc.RootElement.Clone();
    }

    private static string ReadString(JsonElement row, string key)
    {
        return row.ValueKind == JsonValueKind.Object
            && row.TryGetProperty(key, out var value)
            && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? string.Empty : string.Empty;
    }

    private static JsonElement[] Rows(JsonElement root, string key) =>
        root.TryGetProperty(key, out var val) && val.ValueKind == JsonValueKind.Array
            ? val.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Object).ToArray()
            : Array.Empty<JsonElement>();

    private static string? SafeReceiptState(string path)
    {
        try
        {
            if (new FileInfo(path).Length > 512 * 1024) return null;
            var obj = ReadRoot(path);
            if (obj.ValueKind != JsonValueKind.Object) return null;
            foreach (var key in new[] { "state", "result", "status" })
            {
                var value = ReadString(obj, key);
                if (SafeStates.Contains(value)) return value;
            }
        }
        catch (Exception) { /* Unreadable evidence is never treated as success. */ }
        return null;
    }

    private static (bool observed, string? observedAt, string? state) ReceiptSummary(
        string repoRoot, string artifactPath)
    {
        // Only existing, locally ignored survey receipts. Never follow a registry entry to
        // external locations, other users, UNC shares or arbitrary client content.
        var normalized = artifactPath.Replace('\\', '/');
        if (!normalized.StartsWith("survey/output/", StringComparison.Ordinal)
            || normalized.Contains("..", StringComparison.Ordinal)) return (false, null, null);
        var slash = normalized.LastIndexOf('/');
        if (slash < 0) return (false, null, null);
        var dir = Path.GetFullPath(Path.Combine(repoRoot, normalized[..slash].Replace('/', Path.DirectorySeparatorChar)));
        var privateRoot = Path.GetFullPath(Path.Combine(repoRoot, "survey", "output"))
            .TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!dir.StartsWith(privateRoot, StringComparison.OrdinalIgnoreCase)
            || !Directory.Exists(dir)) return (false, null, null);
        var filePattern = Regex.Replace(normalized[(slash + 1)..], @"<[^>]+>", "*");
        if (!filePattern.EndsWith(".json", StringComparison.OrdinalIgnoreCase)
            || filePattern.IndexOfAny(new[] { '/', '\\' }) >= 0) return (false, null, null);
        try
        {
            var latest = Directory.EnumerateFiles(dir, filePattern, SearchOption.TopDirectoryOnly)
                .Where(p => !File.GetAttributes(p).HasFlag(FileAttributes.ReparsePoint))
                .OrderByDescending(File.GetLastWriteTimeUtc)
                .FirstOrDefault();
            if (latest is null) return (false, null, null);
            return (true, File.GetLastWriteTimeUtc(latest).ToString("O"), SafeReceiptState(latest));
        }
        catch (Exception) { return (false, null, null); }
    }

    public static object Build(string dashboardRoot)
    {
        var generated = DateTimeOffset.UtcNow.ToString("O");
        var repoRoot = Directory.GetParent(Path.GetFullPath(dashboardRoot))?.FullName;
        if (repoRoot is null) return new { schema = "sas-capability-cockpit/v1", registry_loaded = false, generated_at = generated, capabilities = Array.Empty<object>() };
        try
        {
            var root = Path.Combine(repoRoot, "harness", "api");
            var cmds = Rows(ReadRoot(Path.Combine(root, "harness-command-registry.json")), "commands");
            var contracts = Rows(ReadRoot(Path.Combine(root, "harness-outcome-registry.json")), "contracts")
                .ToDictionary(x => ReadString(x, "command_id"), x => ReadString(x, "success_artifact_id"));
            var artifacts = Rows(ReadRoot(Path.Combine(root, "harness-artifact-registry.json")), "artifacts")
                .ToDictionary(x => ReadString(x, "id"), x => ReadString(x, "path"));
            var entries = cmds.Select(command =>
            {
                var id = ReadString(command, "id");
                var entry = ReadString(command, "command").Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
                var source = ReadString(command, "source_of_truth");
                var entryExists = entry.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase)
                    || entry.EndsWith(".bat", StringComparison.OrdinalIgnoreCase)
                    ? File.Exists(Path.Combine(repoRoot, entry)) : false;
                var sourceExists = !string.IsNullOrEmpty(source) && !Path.IsPathRooted(source)
                    && !source.Contains("..", StringComparison.Ordinal)
                    && File.Exists(Path.Combine(repoRoot, source.Replace('/', Path.DirectorySeparatorChar)));
                var receipt = contracts.TryGetValue(id, out var aid) && artifacts.TryGetValue(aid, out var path)
                    ? ReceiptSummary(repoRoot, path) : (observed: false, observedAt: (string?)null, state: (string?)null);
                return new
                {
                    id,
                    domain = Domain(id),
                    command = ReadString(command, "command"),
                    purpose = ReadString(command, "purpose"),
                    mutation_class = ReadString(command, "mutation"),
                    entrypoint_present = entryExists,
                    source_present = sourceExists,
                    local_receipt_observed = receipt.observed,
                    last_receipt_at = receipt.observedAt,
                    last_allowlisted_state = receipt.state,
                    proof_ceiling = receipt.observed ? "LOCAL_RECEIPT_PRESENT_NOT_LIVE_CERTIFIED" : "REPOSITORY_ONLY"
                };
            }).ToArray();
            return new
            {
                schema = "sas-capability-cockpit/v1",
                registry_loaded = true,
                generated_at = generated,
                host = "LOCAL_DASHBOARD_PROCESS_NOT_TARGET",
                evidence_policy = "READ_ONLY_SANITIZED_METADATA_NO_TARGET_CONTACT",
                registered_count = entries.Length,
                entrypoint_present_count = entries.Count(x => x.entrypoint_present),
                local_receipt_count = entries.Count(x => x.local_receipt_observed),
                capabilities = entries
            };
        }
        catch (Exception)
        {
            // No stack traces, machine paths, malformed private data or fake empty success.
            return new { schema = "sas-capability-cockpit/v1", registry_loaded = false, generated_at = generated, capabilities = Array.Empty<object>() };
        }
    }
}
