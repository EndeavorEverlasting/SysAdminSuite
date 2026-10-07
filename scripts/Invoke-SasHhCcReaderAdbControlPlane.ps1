# Allowlisted read-only Android debug workflow. Never subnet-scan.
# Exact-IP tcpip 5555 is a bounded transaction with USB revert.
# Do not add bootloader flashing or global settings mutation into this wrapper.
param(
    [string]$Mode = "probe",
    [string]$Fixture,
    [string]$OutputDir,
    [string]$ExpectedMac,
    [switch]$AllowInstall,
    [switch]$OtgConfirmed
)
$Root = Split-Path -Parent $PSScriptRoot
$Py = Join-Path $Root "harness\api\hh_cc_reader_adb_control_plane.py"
$exe = "python"
if (Get-Command py -ErrorAction SilentlyContinue) { $exe = "py" }
$args = @()
if ($exe -eq "py") { $args += "-3" }
$args += $Py
if ($Fixture) {
    $args += @("--input", $Fixture)
} else {
    $args += @("--live", $Mode)
    if ($AllowInstall) { $args += "--allow-install" }
    if ($ExpectedMac) { $args += @("--expected-mac", $ExpectedMac) }
}
if ($OtgConfirmed) { $args += "--otg-confirmed" }
if ($OutputDir) { $args += @("--output-dir", $OutputDir) }
& $exe @args
exit $LASTEXITCODE
