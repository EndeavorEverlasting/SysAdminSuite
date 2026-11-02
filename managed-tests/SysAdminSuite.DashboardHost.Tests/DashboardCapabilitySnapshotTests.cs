using System;
using System.IO;
using System.Net;
using System.Text.Json;
using SysAdminSuite.DashboardHost;
using Xunit;

namespace SysAdminSuite.DashboardHost.Tests;

public sealed class DashboardCapabilitySnapshotTests : IDisposable
{
    private readonly string _repo;
    private readonly string _dashboard;
    private readonly string _registry;

    public DashboardCapabilitySnapshotTests()
    {
        _repo = Path.Combine(Path.GetTempPath(), "sas-capability-test-" + Guid.NewGuid().ToString("N"));
        _dashboard = Path.Combine(_repo, "dashboard");
        _registry = Path.Combine(_repo, "harness", "api");
        Directory.CreateDirectory(_dashboard);
        Directory.CreateDirectory(_registry);
        File.WriteAllText(Path.Combine(_repo, "Inspect-Reader.cmd"), "@echo off");
        File.WriteAllText(Path.Combine(_registry, "reader.py"), "# test");
        File.WriteAllText(Path.Combine(_registry, "harness-command-registry.json"),
            "{\"commands\":[{\"id\":\"hh-cc-reader-probe\",\"command\":\"Inspect-Reader.cmd TEST\",\"purpose\":\"Read-only inspection\",\"mutation\":\"none\",\"source_of_truth\":\"harness/api/reader.py\"}]}");
        File.WriteAllText(Path.Combine(_registry, "harness-outcome-registry.json"),
            "{\"contracts\":[{\"command_id\":\"hh-cc-reader-probe\",\"success_artifact_id\":\"hh-cc-reader-probe-result\"}]}");
        File.WriteAllText(Path.Combine(_registry, "harness-artifact-registry.json"),
            "{\"artifacts\":[{\"id\":\"hh-cc-reader-probe-result\",\"path\":\"survey/output/hh-cc-reader/reader-<timestamp>.json\"}]}");
    }

    public void Dispose()
    {
        try { Directory.Delete(_repo, recursive: true); } catch { }
    }

    [Theory]
    [InlineData("127.0.0.1", "localhost", true)]
    [InlineData("::1", "::1", true)]
    [InlineData("::ffff:127.0.0.1", "127.0.0.1", true)]
    [InlineData("192.0.2.9", "localhost", false)]
    [InlineData("127.0.0.1", "malicious.example", false)]
    [InlineData("127.0.0.1", "localhost.evil", false)]
    public void RequestsMustBeOnLoopbackWithAnExplicitLocalHost(string remote, string host, bool expected)
    {
        Assert.Equal(expected, DashboardCapabilitySnapshot.IsLocalRequest(IPAddress.Parse(remote), host));
    }

    [Fact]
    public void EnumeratesRealRegistryWithoutFabricatingHostProof()
    {
        var json = JsonSerializer.Serialize(DashboardCapabilitySnapshot.Build(_dashboard));
        using var parsed = JsonDocument.Parse(json);
        var root = parsed.RootElement;
        Assert.True(root.GetProperty("registry_loaded").GetBoolean());
        Assert.Equal(1, root.GetProperty("registered_count").GetInt32());
        Assert.Equal(1, root.GetProperty("entrypoint_present_count").GetInt32());
        Assert.Equal(0, root.GetProperty("local_receipt_count").GetInt32());
        var entry = root.GetProperty("capabilities")[0];
        Assert.Equal("CC readers", entry.GetProperty("domain").GetString());
        Assert.Equal("REPOSITORY_ONLY", entry.GetProperty("proof_ceiling").GetString());
        Assert.False(entry.GetProperty("local_receipt_observed").GetBoolean());
    }

    [Fact]
    public void PrivateReceiptNeverLeaksIdentityOrPromotesUnreviewedSuccess()
    {
        var directory = Path.Combine(_repo, "survey", "output", "hh-cc-reader");
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "reader-20261102.json"),
            "{\"state\":\"ADB_DEVICE_READY\",\"serial\":\"PRIVATE-SERIAL-123\",\"secret\":\"SECRET-TOKEN\",\"ip\":\"10.1.2.3\"}");
        var json = JsonSerializer.Serialize(DashboardCapabilitySnapshot.Build(_dashboard));
        using var doc = JsonDocument.Parse(json);
        var cap = doc.RootElement.GetProperty("capabilities")[0];
        Assert.Equal(1, doc.RootElement.GetProperty("local_receipt_count").GetInt32());
        Assert.Equal("ADB_DEVICE_READY", cap.GetProperty("last_allowlisted_state").GetString());
        Assert.Equal("LOCAL_RECEIPT_PRESENT_NOT_LIVE_CERTIFIED", cap.GetProperty("proof_ceiling").GetString());
        Assert.DoesNotContain("PRIVATE-SERIAL-123", json);
        Assert.DoesNotContain("SECRET-TOKEN", json);
        Assert.DoesNotContain("10.1.2.3", json);
        Assert.DoesNotContain(directory, json);
    }

    [Fact]
    public void UnrecognizedReceiptStatusNeverLeaksUntrustedValues()
    {
        var directory = Path.Combine(_repo, "survey", "output", "hh-cc-reader");
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "reader-20261102.json"),
            "{\"state\":\"CLIENT_ACCOUNT_PASSWORD_98765\",\"serial\":\"PRIVATE-SERIAL-123\"}");
        var json = JsonSerializer.Serialize(DashboardCapabilitySnapshot.Build(_dashboard));
        Assert.DoesNotContain("CLIENT_ACCOUNT_PASSWORD_98765", json);
        Assert.DoesNotContain("PRIVATE-SERIAL-123", json);
        using var doc = JsonDocument.Parse(json);
        Assert.Equal(JsonValueKind.Null, doc.RootElement.GetProperty("capabilities")[0].GetProperty("last_allowlisted_state").ValueKind);
    }

    [Fact]
    public void RuntimeDispatchDoesNotBecomeFalseEntrypointMissingClaim()
    {
        File.WriteAllText(Path.Combine(_registry, "harness-command-registry.json"),
            "{\\"commands\\":[{\\"id\\":\\"harness-validate\\",\\"command\\":\\"python tool.py\\",\\"source_of_truth\\":\\"harness/api/reader.py\\"}]}");
        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(DashboardCapabilitySnapshot.Build(_dashboard)));
        var cap = doc.RootElement.GetProperty("capabilities")[0];
        Assert.Equal("RUNTIME_DISPATCH_NOT_PROBED", cap.GetProperty("entrypoint_status").GetString());
        Assert.False(cap.GetProperty("entrypoint_present").GetBoolean());
        Assert.True(cap.GetProperty("source_present").GetBoolean());
    }

    [Fact]
    public void MissingRegistryFailsClosedInsteadOfPresentingEmptySuccess()
    {
        File.Delete(Path.Combine(_registry, "harness-command-registry.json"));
        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(DashboardCapabilitySnapshot.Build(_dashboard)));
        Assert.False(doc.RootElement.GetProperty("registry_loaded").GetBoolean());
    }
}
