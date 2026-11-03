using System;
using System.IO;
using System.Linq;
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
        Assert.Equal("NOT_PROBED", entry.GetProperty("executable_availability").GetString());
        Assert.Equal("NOT_VERIFIED", entry.GetProperty("real_world_outcome").GetString());
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
        Assert.Equal("NOT_PROBED", cap.GetProperty("executable_availability").GetString());
        Assert.Equal("NOT_VERIFIED", cap.GetProperty("real_world_outcome").GetString());
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
            "{\"commands\":[{\"id\":\"harness-validate\",\"command\":\"python tool.py\",\"source_of_truth\":\"harness/api/reader.py\"}]}");
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

    [Theory]
    [InlineData(null, "NO_INDEXED_RECEIPT")]
    [InlineData("", "NO_INDEXED_RECEIPT")]
    [InlineData("survey/output/hh-cc-reader/reader-<timestamp>.json", "SURVEY_OUTPUT_PATTERN")]
    [InlineData("%LOCALAPPDATA%/SysAdminSuite/operator-session.json", "KNOWN_LOCALAPPDATA_NOT_QUERIED")]
    [InlineData("%TEMP%/hh-cc-p5-packet-fill.json", "TEMP_NOT_QUERIED")]
    [InlineData("console output or CI log from harness/validators/validate-harness-registries.py", "CONSOLE_OR_CI_NOT_QUERIED")]
    [InlineData("tools/publish/SysAdminSuite.DashboardHost/", "BUILD_OUTPUT_NOT_PROBED")]
    [InlineData("<approved-runtime-evidence-directory>/runtime-proof.json", "APPROVED_RUNTIME_HOME_NOT_QUERIED")]
    [InlineData("docs/HARNESS_STATUS.md", "OTHER_SOURCE_NOT_QUERIED")]
    public void ClassifyReceiptSourceSeparatesFamiliesWithoutResolvingHomes(string? path, string expected)
    {
        Assert.Equal(expected, DashboardCapabilitySnapshot.ClassifyReceiptSource(path));
    }

    [Fact]
    public void BuildExposesSourceClassesAndSeparatesUnmappedFromUnqueriedHomes()
    {
        File.WriteAllText(Path.Combine(_registry, "harness-command-registry.json"),
            "{\"commands\":["
            + "{\"id\":\"hh-cc-reader-probe\",\"command\":\"Inspect-Reader.cmd TEST\",\"purpose\":\"Survey\",\"mutation\":\"none\",\"source_of_truth\":\"harness/api/reader.py\"},"
            + "{\"id\":\"operator-session\",\"command\":\"sas context\",\"purpose\":\"Session\",\"mutation\":\"none\",\"source_of_truth\":\"harness/api/reader.py\"},"
            + "{\"id\":\"harness-validate\",\"command\":\"python tool.py\",\"purpose\":\"CI\",\"mutation\":\"none\",\"source_of_truth\":\"harness/api/reader.py\"},"
            + "{\"id\":\"unmapped-command\",\"command\":\"Inspect-Reader.cmd X\",\"purpose\":\"Gap\",\"mutation\":\"none\",\"source_of_truth\":\"harness/api/reader.py\"}"
            + "]}");
        File.WriteAllText(Path.Combine(_registry, "harness-outcome-registry.json"),
            "{\"contracts\":["
            + "{\"command_id\":\"hh-cc-reader-probe\",\"success_artifact_id\":\"hh-cc-reader-probe-result\"},"
            + "{\"command_id\":\"operator-session\",\"success_artifact_id\":\"operator-session-state\"},"
            + "{\"command_id\":\"harness-validate\",\"success_artifact_id\":\"harness-completeness-result\"}"
            + "]}");
        File.WriteAllText(Path.Combine(_registry, "harness-artifact-registry.json"),
            "{\"artifacts\":["
            + "{\"id\":\"hh-cc-reader-probe-result\",\"path\":\"survey/output/hh-cc-reader/reader-<timestamp>.json\"},"
            + "{\"id\":\"operator-session-state\",\"path\":\"%LOCALAPPDATA%/SysAdminSuite/operator-session.json\"},"
            + "{\"id\":\"harness-completeness-result\",\"path\":\"console output or CI log from Tests/survey/test_operational_harness_completeness_contracts.py\"}"
            + "]}");

        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(DashboardCapabilitySnapshot.Build(_dashboard)));
        var root = doc.RootElement;
        Assert.Equal(4, root.GetProperty("registered_count").GetInt32());
        Assert.Equal(2, root.GetProperty("receipt_home_not_queried_count").GetInt32());
        Assert.Equal(1, root.GetProperty("no_indexed_receipt_count").GetInt32());
        Assert.Equal(1, root.GetProperty("receipt_source_class_counts").GetProperty("SURVEY_OUTPUT_PATTERN").GetInt32());
        Assert.Equal(1, root.GetProperty("receipt_source_class_counts").GetProperty("KNOWN_LOCALAPPDATA_NOT_QUERIED").GetInt32());
        Assert.Equal(1, root.GetProperty("receipt_source_class_counts").GetProperty("CONSOLE_OR_CI_NOT_QUERIED").GetInt32());
        Assert.Equal(1, root.GetProperty("receipt_source_class_counts").GetProperty("NO_INDEXED_RECEIPT").GetInt32());

        var byId = root.GetProperty("capabilities").EnumerateArray()
            .ToDictionary(x => x.GetProperty("id").GetString()!, x => x);
        Assert.Equal("SURVEY_OUTPUT_PATTERN", byId["hh-cc-reader-probe"].GetProperty("receipt_source_class").GetString());
        Assert.Equal("KNOWN_LOCALAPPDATA_NOT_QUERIED", byId["operator-session"].GetProperty("receipt_source_class").GetString());
        Assert.Equal("OTHER_PRIVATE_RECEIPT_HOME_NOT_QUERIED", byId["operator-session"].GetProperty("receipt_coverage").GetString());
        Assert.Equal("NO_INDEXED_RECEIPT", byId["unmapped-command"].GetProperty("receipt_coverage").GetString());
        Assert.Equal("NO_INDEXED_RECEIPT", byId["unmapped-command"].GetProperty("receipt_source_class").GetString());
        Assert.DoesNotContain("%LOCALAPPDATA%", JsonSerializer.Serialize(root));
        Assert.DoesNotContain("operator-session.json", JsonSerializer.Serialize(root));
    }
}
