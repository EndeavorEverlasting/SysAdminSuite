∩╗┐Bug Log.md

Bug log (pin these in your repo)

$PSScriptRoot misuse ΓÇö using $PSScriptRoot outside a running script (e.g., in the console) is invalid. It only exists inside a script/module. Use a context resolver (walk up from $PSCommandPath/editor path) or pass absolute paths.

$Host collision ΓÇö $Host is a built-in, read-only automatic variable (case-insensitive). Reusing $host as a normal variable/param throws ΓÇ£Cannot overwrite variable HostΓÇ¥. Use $TargetHost instead.

CSV row ΓÇ£PathΓÇ¥ fallacy ΓÇö rows from Import-Csv donΓÇÖt have .Path. Only Get-ChildItem file objects do. Filter CSV files first, import later.