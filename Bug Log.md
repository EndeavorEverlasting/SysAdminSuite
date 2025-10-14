Bug Log.md

Bug log (pin these in your repo)

$PSScriptRoot misuse — using $PSScriptRoot outside a running script (e.g., in the console) is invalid. It only exists inside a script/module. Use a context resolver (walk up from $PSCommandPath/editor path) or pass absolute paths.

$Host collision — $Host is a built-in, read-only automatic variable (case-insensitive). Reusing $host as a normal variable/param throws “Cannot overwrite variable Host”. Use $TargetHost instead.

CSV row “Path” fallacy — rows from Import-Csv don’t have .Path. Only Get-ChildItem file objects do. Filter CSV files first, import later.