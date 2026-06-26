#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

config="$repo_root/Config/dotnet-bootstrap.json"
runtime_script="$repo_root/scripts/ensure-dotnet-runtime.sh"
sdk_script="$repo_root/scripts/ensure-dotnet-sdk.sh"
host_script="$repo_root/scripts/ensure-dashboard-host.sh"
toolbox_writer="$repo_root/scripts/sas-write-toolbox-status.sh"
host_bat="$repo_root/Launch-SysAdminSuiteDashboard.Host.bat"
start_bat="$repo_root/START-HERE-SysAdminSuite-Dashboard.bat"
gitignore="$repo_root/.gitignore"

[[ -f "$config" ]] || fail "missing Config/dotnet-bootstrap.json"
[[ -f "$runtime_script" ]] || fail "missing ensure-dotnet-runtime.sh"
[[ -f "$sdk_script" ]] || fail "missing ensure-dotnet-sdk.sh"
[[ -f "$host_script" ]] || fail "missing ensure-dashboard-host.sh"
[[ -f "$toolbox_writer" ]] || fail "missing toolbox status writer"

grep -Fq 'dotnetcli.blob.core.windows.net/dotnet/release-metadata/8.0/releases.json' "$config" \
  || fail "bootstrap config does not cite official .NET release metadata"
grep -Fq 'aspnetcore-runtime-8.0.28-win-x64.exe' "$config" \
  || fail "bootstrap config missing ASP.NET Core runtime installer"
grep -Fq 'windowsdesktop-runtime-8.0.28-win-x64.exe' "$config" \
  || fail "bootstrap config missing Windows Desktop runtime installer"
grep -Fq 'dotnet-sdk-8.0.422-win-x64.exe' "$config" \
  || fail "bootstrap config missing .NET SDK installer"
grep -Fq 'Microsoft.AspNetCore.App' "$config" \
  || fail "bootstrap config missing ASP.NET Core shared framework check"
grep -Fq 'Microsoft.WindowsDesktop.App' "$config" \
  || fail "bootstrap config missing Windows Desktop shared framework check"
grep -Eq '"sha512": "[0-9a-f]{128}"' "$config" \
  || fail "bootstrap config must pin SHA512 hashes from Microsoft metadata"

for script in "$runtime_script" "$sdk_script"; do
  grep -Fq 'Config/dotnet-bootstrap.json' "$script" \
    || fail "$(basename "$script") does not read bootstrap config"
  grep -Fq 'curl.exe' "$script" \
    || fail "$(basename "$script") does not prefer Windows curl.exe"
  grep -Fq 'certutil.exe' "$script" \
    || fail "$(basename "$script") does not provide Windows-native checksum verification"
  grep -Fq 'cmd.exe /c' "$script" \
    || fail "$(basename "$script") does not run the official installer through Windows"
  grep -Fq -- '--dry-run' "$script" \
    || fail "$(basename "$script") has no dry-run mode"
done

grep -Fq 'ensure-dotnet-runtime.sh' "$host_script" \
  || fail "dashboard host ensure script does not call runtime ensure"
grep -Fq 'ensure-dotnet-sdk.sh' "$host_script" \
  || fail "dashboard host ensure script does not call SDK ensure"
grep -Fq 'publish "$PROJECT"' "$host_script" \
  || fail "dashboard host ensure script does not publish with dotnet"
grep -Fq 'app/bin' "$host_script" \
  || fail "dashboard host ensure script does not publish into ignored app/bin layout"
grep -Fq -- '--self-contained false' "$host_script" \
  || fail "dashboard host ensure script must preserve framework-dependent publish"

grep -Fq 'ensure-dashboard-host.sh' "$host_bat" \
  || fail "host launcher does not call dashboard bootstrap"
grep -Fq 'Git\bin\bash.exe' "$host_bat" \
  || fail "host launcher does not prefer Git Bash"
grep -Fq 'sas-write-toolbox-status.sh' "$host_bat" \
  || fail "host launcher does not write dashboard toolbox status"
grep -Fq 'Microsoft .NET dependencies' "$start_bat" \
  || fail "root launcher does not tell users about Microsoft .NET bootstrap"
grep -Fq 'administrator approval' "$start_bat" \
  || fail "root launcher missing admin/IT bootstrap guidance"

if grep -RIEq '\b(winget|choco|chocolatey)\b' "$runtime_script" "$sdk_script" "$host_script" "$config"; then
  fail "dashboard bootstrap must not use winget/choco"
fi

grep -Fq 'tools/cache/' "$gitignore" \
  || fail "downloaded Microsoft installer cache is not ignored"

bash "$host_script" --dry-run >/dev/null

echo "PASS: dashboard dependency bootstrap contracts"
