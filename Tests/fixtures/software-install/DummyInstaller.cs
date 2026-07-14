using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

internal static class Program
{
    private const string DefaultPackageName = "SysAdminSuite Fixture Package";
    private const string DefaultVersion = "1.0.0";
    private const string DefaultDummyRelativePath =
        @"InstalledPackages\SysAdminSuiteFixturePackage\dummy-installed.txt";

    private static int Main(string[] args)
    {
        Dictionary<string, string> options = ParseArguments(args);
        string logPath = null;

        try
        {
            string targetRoot = Require(options, "target-root");
            string packageName = Get(options, "package-name", DefaultPackageName);
            string version = Get(options, "version", DefaultVersion);
            string dummyRelativePath = Get(
                options,
                "dummy-relative-path",
                DefaultDummyRelativePath
            );
            logPath = Require(options, "log-path");

            targetRoot = Path.GetFullPath(targetRoot);
            ValidateRelativePath(dummyRelativePath, "dummy-relative-path");

            string packageRoot = Path.Combine(
                targetRoot,
                "InstalledPackages",
                "SysAdminSuiteFixturePackage"
            );
            string manifestPath = Path.Combine(packageRoot, "manifest.json");
            string dummyPath = Path.GetFullPath(Path.Combine(targetRoot, dummyRelativePath));
            logPath = Path.GetFullPath(logPath);

            EnsureUnderRoot(targetRoot, manifestPath, "manifest");
            EnsureUnderRoot(targetRoot, dummyPath, "dummy file");
            EnsureUnderRoot(targetRoot, logPath, "installer log");

            Directory.CreateDirectory(packageRoot);
            Directory.CreateDirectory(Path.GetDirectoryName(dummyPath));
            Directory.CreateDirectory(Path.GetDirectoryName(logPath));

            string timestamp = DateTime.UtcNow.ToString("o");
            File.WriteAllText(
                dummyPath,
                "SysAdminSuite dummy installation completed at " + timestamp + Environment.NewLine,
                new UTF8Encoding(false)
            );

            string manifest = "{" +
                "\"schema_version\":\"sas-fixture-installed-package/v2\"," +
                "\"package_name\":\"" + JsonEscape(packageName) + "\"," +
                "\"version\":\"" + JsonEscape(version) + "\"," +
                "\"installed_at_utc\":\"" + JsonEscape(timestamp) + "\"," +
                "\"installer\":\"sysadminsuite-dummy-installer.exe\"," +
                "\"dummy_file\":\"" + JsonEscape(ToForwardSlashes(dummyRelativePath)) + "\"" +
                "}";
            File.WriteAllText(manifestPath, manifest, new UTF8Encoding(false));

            string logEntry = "{" +
                "\"timestamp_utc\":\"" + JsonEscape(timestamp) + "\"," +
                "\"event\":\"dummy_install_completed\"," +
                "\"package_name\":\"" + JsonEscape(packageName) + "\"," +
                "\"version\":\"" + JsonEscape(version) + "\"," +
                "\"dummy_file\":\"" + JsonEscape(ToForwardSlashes(dummyRelativePath)) + "\"," +
                "\"manifest_path\":\"" + JsonEscape(manifestPath) + "\"" +
                "}";
            File.AppendAllText(logPath, logEntry + Environment.NewLine, new UTF8Encoding(false));

            Console.WriteLine(logEntry);
            return 0;
        }
        catch (Exception ex)
        {
            string timestamp = DateTime.UtcNow.ToString("o");
            string errorEntry = "{" +
                "\"timestamp_utc\":\"" + JsonEscape(timestamp) + "\"," +
                "\"event\":\"dummy_install_failed\"," +
                "\"error\":\"" + JsonEscape(ex.Message) + "\"" +
                "}";
            Console.Error.WriteLine(errorEntry);
            TryAppendFailure(logPath, errorEntry);
            return 40;
        }
    }

    private static Dictionary<string, string> ParseArguments(string[] args)
    {
        Dictionary<string, string> options =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        foreach (string raw in args)
        {
            if (String.IsNullOrWhiteSpace(raw))
            {
                continue;
            }

            int separator = raw.IndexOf('=');
            if (separator <= 2)
            {
                throw new ArgumentException(
                    "Arguments must use --name=value form. Received: " + raw
                );
            }

            string key = raw.Substring(0, separator).TrimStart('-').Trim();
            string value = raw.Substring(separator + 1).Trim().Trim('"');
            if (String.IsNullOrWhiteSpace(key) || String.IsNullOrWhiteSpace(value))
            {
                throw new ArgumentException("Argument name and value are required: " + raw);
            }

            options[key] = value;
        }

        return options;
    }

    private static string Require(Dictionary<string, string> options, string key)
    {
        string value;
        if (!options.TryGetValue(key, out value) || String.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException("Missing required argument --" + key + "=<value>");
        }

        return value;
    }

    private static string Get(
        Dictionary<string, string> options,
        string key,
        string defaultValue
    )
    {
        string value;
        return options.TryGetValue(key, out value) ? value : defaultValue;
    }

    private static void ValidateRelativePath(string path, string label)
    {
        if (Path.IsPathRooted(path))
        {
            throw new ArgumentException(label + " must be relative.");
        }

        string normalized = path.Replace('/', '\\');
        string[] parts = normalized.Split(new[] { '\\' }, StringSplitOptions.RemoveEmptyEntries);
        foreach (string part in parts)
        {
            if (part == "..")
            {
                throw new ArgumentException(label + " cannot contain parent traversal.");
            }
        }
    }

    private static void EnsureUnderRoot(string root, string candidate, string label)
    {
        string fullRoot = Path.GetFullPath(root)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) +
            Path.DirectorySeparatorChar;
        string fullCandidate = Path.GetFullPath(candidate);

        if (!fullCandidate.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(label + " escaped the fixture target root.");
        }
    }

    private static string ToForwardSlashes(string value)
    {
        return value.Replace('\\', '/');
    }

    private static string JsonEscape(string value)
    {
        if (value == null)
        {
            return String.Empty;
        }

        StringBuilder builder = new StringBuilder();
        foreach (char character in value)
        {
            switch (character)
            {
                case '\\':
                    builder.Append("\\\\");
                    break;
                case '"':
                    builder.Append("\\\"");
                    break;
                case '\r':
                    builder.Append("\\r");
                    break;
                case '\n':
                    builder.Append("\\n");
                    break;
                case '\t':
                    builder.Append("\\t");
                    break;
                default:
                    if (character < 32)
                    {
                        builder.Append("\\u");
                        builder.Append(((int)character).ToString("x4"));
                    }
                    else
                    {
                        builder.Append(character);
                    }
                    break;
            }
        }

        return builder.ToString();
    }

    private static void TryAppendFailure(string logPath, string entry)
    {
        if (String.IsNullOrWhiteSpace(logPath))
        {
            return;
        }

        try
        {
            string fullLogPath = Path.GetFullPath(logPath);
            string parent = Path.GetDirectoryName(fullLogPath);
            if (!String.IsNullOrWhiteSpace(parent))
            {
                Directory.CreateDirectory(parent);
            }
            File.AppendAllText(
                fullLogPath,
                entry + Environment.NewLine,
                new UTF8Encoding(false)
            );
        }
        catch
        {
            // The process exit code and stderr remain the authoritative failure evidence.
        }
    }
}
