<# Unblock every file in and below the repo. Safe to re-run. #>
param(
  [string]$Path = (Get-Location).Path
)

$files = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue
foreach ($f in $files) {
  try { Unblock-File -Path $f.FullName -ErrorAction Stop } catch {}
}
# Older PS sometimes leaves Zone.Identifier on a few files; nuke via streams:
$withStreams = Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
  Where-Object { (Get-Item $_.FullName -Stream * -ErrorAction SilentlyContinue | Where-Object Stream -eq 'Zone.Identifier') }
foreach ($f in $withStreams) {
  try { Remove-Item -Path $f.FullName -Stream Zone.Identifier -Force -ErrorAction Stop } catch {}
}
Write-Host "Unblock complete."
