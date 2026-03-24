Fix the following issues. The issues can be from different files or can overlap on same lines in one file.

- Verify each finding against the current code and only fix it if needed.

In @ActiveDirectory/Add-Computers-To-PrintingGroup.ps1 at line 154, The restore script is generating irrelevant Move-ADObject commands via the $restore.Add call; instead generate Remove-ADGroupMember commands to undo group additions. Replace the Move-ADObject string being added with an appropriately formed Remove-ADGroupMember invocation that removes the computer (use $c.SamAccountName or $c.DistinguishedName as needed) from the target group ($row.GroupName or the variable used for the group), and update the related variable/file names from $restorePs1/Restore-OU.ps1 to $undoPs1/Undo-GroupMembership.ps1 (also update any writes or saves that reference those names, e.g. the code around where $restorePs1 is written out).

- Verify each finding against the current code and only fix it if needed.

In @ActiveDirectory/Add-Computers-To-PrintingGroup.ps1 around lines 22 - 24, The numeric parameters ChunkSize, RetryCount and RetryDelaySeconds currently lack validation and can be zero or negative; add parameter validation attributes in the param block (e.g., [ValidateRange(1, [int]::MaxValue)]) for ChunkSize, RetryCount and RetryDelaySeconds so each must be a positive integer (>=1), and update any default values if necessary; reference the parameter names ChunkSize, RetryCount and RetryDelaySeconds and the param block that feeds the chunking/retry logic when applying this change.

- Verify each finding against the current code and only fix it if needed.

In @ActiveDirectory/hosts.txt around lines 1 - 4, The file ActiveDirectory/hosts.txt is missing a trailing newline; open hosts.txt and ensure the last line (e.g., "WLS111WCC094") is terminated with a single newline character (POSIX EOL) so the file ends with a newline to satisfy line-based tools and version control checks.

- Verify each finding against the current code and only fix it if needed.

In @ActiveDirectory/hosts.txt at line 1, The file hosts.txt begins with a UTF-8 BOM causing parsing issues; remove the BOM character by re-saving hosts.txt as "UTF-8 without BOM" (or use an editor command such as Vim's :set nobomb then :w, or a tool like dos2unix/sed to strip the BOM) so the first token "WLS111WCC091" is the very first byte in the file.

- Verify each finding against the current code and only fix it if needed.

In @Bug-Log.md at line 1, Remove the stray BOM and filename text from the top of Bug-Log.md by deleting the entire first line that contains the characters "∩╗┐Bug Log.md" (i.e., strip any leading UTF-8 BOM and remove the filename from the file content), ensure the file begins with the intended document content (no BOM or filename embedded), and save the file without a BOM.

- Verify each finding against the current code and only fix it if needed.

In @Bug-Log.md around lines 5 - 9, The documentation contains widespread character-encoding corruption (e.g., "ΓÇö" instead of "—", "ΓÇ£"/"ΓÇ¥" instead of quotes, "ΓÇÖ" instead of apostrophes); fix by re-saving or converting the file to UTF-8 and replacing corrupted sequences with correct Unicode characters, then verify and normalize variable/identifier mentions: ensure references to $PSScriptRoot and $PSCommandPath are accurate and advise using a context resolver or passing absolute paths, rename any reuse of $host to $TargetHost to avoid collision with the automatic $Host variable, and correct the CSV guidance to distinguish Import-Csv rows (no .Path) from Get-ChildItem file objects (which have .Path) and update examples accordingly.

- Verify each finding against the current code and only fix it if needed.

In @Config/Build-FetchMap.ps1 at line 12, The default $RepoRoot variable currently contains a hardcoded internal UNC (\\LPW003ASI037\C$\SoftwareRepo); replace that with a non-sensitive, environment-aware default and allow overrides (e.g., read from an environment variable like REPO_ROOT, fall back to a relative path such as $PSScriptRoot\SoftwareRepo or an empty string, or prompt the user). Update the declaration of $RepoRoot in Config/Build-FetchMap.ps1 to remove the hardcoded server, implement the env-var fallback logic and ensure downstream code that uses $RepoRoot still works with the new default.

- Verify each finding against the current code and only fix it if needed.

In @Config/Build-FetchMap.ps1 around lines 81 - 83, Validate that a version value is present before substituting {{version}}: check if $tmpl (the URL template) or $r.FileNameTemplate contains the literal '{{version}}' and if $ver (or $resolvedVer) is null/empty (use [string]::IsNullOrEmpty($ver) or equivalent), then fail early with a clear error/exception instead of performing the replacement; otherwise proceed to set $resolvedVer = $ver and perform the -replace substitutions for $url and $file as currently written. Ensure the same validation is applied to $r.FileNameTemplate when present to avoid producing an empty filename.

- Verify each finding against the current code and only fix it if needed.

In @Config/Fetch-DRYRUN.ps1 around lines 12 - 15, $current script may leave $repoHost null if $env:REPO_HOST is unset and RepoHost.txt is missing/empty; update the logic around $repoHost/$hostFile to validate and handle that case before invoking the tools script (the ". $tools -RepoHost $repoHost" call). Specifically, after reading HostFile (Join-Path $here 'RepoHost.txt') and assigning $repoHost, check if $repoHost is null/empty and either set a sensible default or throw/exit with a clear error message; ensure the validation references the same symbols ($repoHost, $hostFile, $tools) so the tools script never receives an empty RepoHost value.

- Verify each finding against the current code and only fix it if needed.

In @Config/Fetch-Installers.ps1 around lines 133 - 136, The WebClient instance created with "New-Object System.Net.WebClient" (stored in $wc) can leak if $wc.DownloadFile($item.Url, $tmp) throws; wrap the creation and download in a try/finally so that $wc.Dispose() is executed in the finally block (or use PowerShell's using scope) to guarantee disposal on both success and failure, leaving the existing DownloadFile call and $wc variable names intact.

- Verify each finding against the current code and only fix it if needed.

In @Config/Fetch-Installers.ps1 around lines 1 - 2, The script header contains garbled characters ("∩╗┐" and "ΓÇö") caused by a BOM/encoding mismatch; open the file in UTF-8 without BOM (or re-save as UTF-8 no-BOM) and replace the corrupted sequences so the header comment reads correctly (e.g., replace "ΓÇö" with a proper dash/hyphen in the comment "ΓÇö vendor-only fetcher with backbone."), and also fix the other occurrence of "ΓÇö" later in the file; ensure the file is saved in UTF-8 without BOM to prevent reintroduction.

- Verify each finding against the current code and only fix it if needed.

In @Config/Fetch-Installers.ps1 around lines 66 - 77, The function Check-AllowList assigns to $host which shadows PowerShell's automatic $Host; rename the local variable (e.g., $uriHost or $parsedHost) used to store ([uri]$url).Host and update every reference in Check-AllowList (the assignment, the comparisons with $d and the Fail message) to use the new name so the automatic $Host is no longer shadowed while preserving the existing logic.

- Verify each finding against the current code and only fix it if needed.

In @Config/Fetch-Installers.ps1 around lines 110 - 111, The param($item) declaration inside the ForEach-Object -Parallel scriptblock is dead and $item is never populated; replace usages of $item (e.g. $item.Name) with the pipeline variable ($_, or $PSItem) inside the -Parallel scriptblock or remove the param(...) entirely and reference $_/$PSItem consistently in the ForEach-Object -Parallel scriptblock to ensure the correct input object is used.

- Verify each finding against the current code and only fix it if needed.

In @Config/GoLiveTools.ps1 around lines 395 - 410, The empty catch block after the COM shortcut processing swallows exceptions; replace it with error handling that logs or records failures including the exception and context (e.g., $root, $_.FullName, $OldDir) so permission/COM errors aren't lost—inside the catch capture the automatic $_ or $Error[0] and call Write-Error or append a failure entry to $edited (include Shortcut, Error, Root, OldTarget) and ensure the script continues processing other shortcuts; keep the existing logic that updates $lnk.TargetPath/$lnk.Save() and returns $edited.

- Verify each finding against the current code and only fix it if needed.

In @Config/GoLiveTools.ps1 around lines 242 - 247, The code assigns to the automatic PowerShell variable $args which shadows the built-in and is confusing; rename that local array (e.g., $invokeArgs or $fetchArgs) where it’s declared and update the splatting call (& $script @args) to use the new name so you build the argument list from '-RepoRoot', $RepoRoot, '-MaxParallel', $MaxParallel, conditionally append '-DryRun' when $DryRun is true, and then invoke & $script @fetchArgs (or your chosen name) instead of using $args; ensure changes are made in the block that references $script and Fetch-Installers.ps1 in GoLiveTools.ps1.

- Verify each finding against the current code and only fix it if needed.

In @Config/GoLiveTools.ps1 around lines 364 - 376, The empty catch after the shortcut scan swallows all exceptions; replace it with a catch that logs the error including exception details so failures creating the COM object or enumerating shortcuts are visible (e.g., in the block that creates $W via New-Object -ComObject WScript.Shell and iterates foreach($root in $roots) / Get-ChildItem ... | ForEach-Object, change the empty catch{} to emit a descriptive error using Write-Error or Write-Host and include the exception message and stack/inner exception from $_ or $PSItem so debugging information is preserved).

- Verify each finding against the current code and only fix it if needed.

In @Config/GoLiveTools.ps1 around lines 321 - 332, The Test-Path check inside the Start-ThreadJob scriptblock is using an invalid UNC root ("\\$comp\") and should instead verify an actual share on the remote host (for example the admin share or the target share) — replace the Test-Path argument with a valid UNC such as the admin share for the target drive or construct it from $dst/$TargetPath (e.g., "\\$comp\C$" or the drive/share part of $dst) so the host reachability check is meaningful; also avoid shadowing the built-in $args by renaming the robocopy argument array (e.g., change $args to $robocopyArgs) inside the scriptblock and update the Start-Process -ArgumentList reference to use that new name so you don’t hide the automatic $args variable used by PowerShell functions like Invoke-Fetch.

- Verify each finding against the current code and only fix it if needed.

In @Config/ImpactS-FixShortcuts.ps1 at line 1, The file ImpactS-FixShortcuts.ps1 contains corrupted BOM characters ("∩╗┐") at the start; open the file in an editor or use a tool to re-save it as UTF-8 without BOM (or strip the BOM bytes EF BB BF), then commit the cleaned file so the script header no longer contains the garbled characters and PowerShell/parsers read it correctly.

- Verify each finding against the current code and only fix it if needed.

In @Config/ImpactS-FixShortcuts.ps1 around lines 12 - 15, The code does not validate $repoHost before passing it to the dot-sourced tools invocation (. $tools -RepoHost $repoHost); ensure $repoHost is non-empty by checking the variables used to populate it ($env:REPO_HOST, $hostFile/Test-Path, Get-Content) and if still null/empty emit a clear error/warning and stop execution (throw or exit) before calling . $tools -RepoHost, so GoLiveTools.ps1 never receives an unexpected null value.

- Verify each finding against the current code and only fix it if needed.

In @Config/ImpactS-Paths.psd1 at line 1, The file contains corrupted BOM characters ("∩╗┐") before the PowerShell hashtable start symbol @{ which prevents parsing; open the file containing the visible characters before "@{" (the impacted file's top-of-file content) and remove those stray characters, then re-save the file with proper UTF-8 encoding (either UTF-8 without BOM or a correctly written UTF-8 BOM so it is not visible) so the first character in the file is "{" preceded by "@", and verify the file now begins with "@{".

- Verify each finding against the current code and only fix it if needed.

In @Config/Inventory-Software.ps1 at line 78, Replace the global silencing of errors via $ErrorActionPreference='SilentlyContinue' with targeted error handling: remove or avoid setting $ErrorActionPreference to SilentlyContinue, wrap each risky operation (e.g., registry or file reads inside functions like any Collect- or Get-Inventory* routines) in try/catch blocks, call Write-Warning or Write-Error inside the catch to record the specific exception, increment a shared counter (e.g., $global:InventoryErrorCount) for each caught error, and ensure the script returns or logs that error count at the end so callers can detect partial failures.

- Verify each finding against the current code and only fix it if needed.

In @Config/Inventory-Software.ps1 around lines 100 - 107, The pipeline assumes $data yields results and $norm (result of Normalize-Row) may be $null leading to failures or misleading counts; add defensive checks after assigning $data and after $norm to handle $null/empty collections: if $data is $null or empty skip Normalize-Row and set $norm = @() (empty array) or ensure Normalize-Row returns an empty collection, then guard downstream uses of $norm with conditional logic before calling Sort-Object/Export-Csv/ConvertTo-Html and when computing $norm.Count; update the logic around the variables $data, $norm, the Normalize-Row call, Export-Csv/ConvertTo-Html pipelines and the Write-Host report to operate safely on empty collections.

- Verify each finding against the current code and only fix it if needed.

In @Config/Inventory-Software.ps1 around lines 56 - 60, Pick-Best can be called with an empty $Rows causing $Rows[0] to be $null; add a defensive guard at the start of the Pick-Best function to handle empty input (check if -not $Rows or $Rows.Count -eq 0) and either throw a clear error or return a documented sentinel (e.g., $null) so callers know the result is missing; update callers of Pick-Best (places using Group-Object output) if needed to handle the new behavior; reference the Pick-Best function and TryVersion parsing logic when making the change.

- Verify each finding against the current code and only fix it if needed.

In @Config/Run-Preflight.ps1 around lines 19 - 21, The script currently calls Preflight-Repo then Stop-Transcript directly so a terminating error (e.g. with $ErrorActionPreference='Stop') can exit before Stop-Transcript runs; wrap the invocation of Preflight-Repo and the subsequent Write-Host in a try/finally block so Stop-Transcript is always executed in the finally; ensure any logging (Write-Host "Preflight complete. Logs: $log") remains in the try (or adjust to report failures) and that Stop-Transcript is called unconditionally in the finally to release the transcript file even if Preflight-Repo throws.

- Verify each finding against the current code and only fix it if needed.

In @Config/Run-Preflight.ps1 around lines 14 - 17, The code reads RepoHost.txt into $repoHost using (Get-Content $hostFile | Select-Object -First 1).Trim(), which will throw if the file is empty; change this to read the first non-blank line safely (e.g., filter out empty/whitespace lines with Where-Object or assign the raw first line to a variable and check for $null/empty before calling .Trim()), then only pass the resulting non-empty $repoHost to the tools invocation (. $tools -RepoHost $repoHost); ensure you handle the case where no valid host is found (leave $repoHost null or set a default) so .Trim() is never called on a null value.

- Verify each finding against the current code and only fix it if needed.

In @Config/Runbook-Inventory.ps1 around lines 1 - 2, The file header in Runbook-Inventory.ps1 contains encoding-garbled characters (e.g. "∩╗┐" and "ΓåÆ") indicating a BOM/mis-encoded save; open Runbook-Inventory.ps1, re-save it as UTF-8 without BOM, remove or replace the garbled symbols in the initial comment line (the "∩╗┐<# Runbook-Inventory.ps1" and "ΓåÆ" fragments) with the intended plain ASCII/unicode text (e.g., standard arrows/checkmarks or simple ASCII) so the file header comment is clean and consistently encoded.

- Verify each finding against the current code and only fix it if needed.

In @Config/Runbook-Inventory.ps1 around lines 43 - 52, The output verification only checks files for the first host because $paths is built using $ComputerName[0]; modify the logic to iterate each computer in $ComputerName and build/validate paths per-host (use the existing $invRoot and the $paths/ForEach-Object logic but inside a loop over $ComputerName), ensuring you check both CSV and HTML for every host, and replace the garbled character "Γ£ô" with the correct checkmark "✓" in the Write-Host message.

- Verify each finding against the current code and only fix it if needed.

In @Config/Runbook-Inventory.ps1 around lines 26 - 35, The current code mutates the source inventory script on disk by editing $inv via Get-Content/Set-Content which is fragile (race conditions, encoding/BOM differences, VCS noise); instead detect and perform the interpolation fix into a separate temp file and execute that, e.g. read $inv into $raw, perform the -replace as now, then write the patched contents to a temporary path (use New-TemporaryFile or [IO.Path]::GetTempFileName()) rather than overwriting $inv, update any downstream invocation to use the temp path (reference variables/functions: $inv, $raw, Inventory-Software.patched.ps1/Inventory-Software.ps1, Get-Content, Set-Content) so runtime patching has no side effects on the source file.

- Verify each finding against the current code and only fix it if needed.

In @Config/Stage-To-Clients.ps1 around lines 20 - 21, The script reads client names into $pcs then calls Copy-SoftwareToClients without checking for an empty list; update the logic around the Get-Content → $pcs assignment to validate that $pcs contains at least one non-empty entry and bail out (or log and exit) if it's empty before calling Copy-SoftwareToClients. Specifically, after building $pcs (the result of Get-Content | Where-Object | ForEach-Object) add a check (e.g., if (-not $pcs -or $pcs.Count -eq 0) { write-error or write-host and exit/return }) so Copy-SoftwareToClients is only invoked when $pcs has targets. Ensure messages reference $pcs so operators know why the run stopped.

- Verify each finding against the current code and only fix it if needed.

In @Config/Stage-To-Clients.ps1 around lines 4 - 22, Start the transcript as you do now with Start-Transcript, then wrap the main work (reading Clients.txt, building $pcs and calling Copy-SoftwareToClients) in a try/finally so Stop-Transcript always runs; e.g., after Start-Transcript open a try { ... } block containing the existing logic that references $clientsPath, $pcs and calls Copy-SoftwareToClients -RepoRoot $RepoRoot -ComputerName $pcs -MaxParallel 8, and put Stop-Transcript | Out-Null in the finally block to ensure the transcript is closed even if an exception is thrown.

- Verify each finding against the current code and only fix it if needed.

In @Config/Test-Links.ps1 around lines 18 - 21, Wrap the block that calls Test-FetchMap and the subsequent pipeline ($r = Test-FetchMap -RepoRoot $RepoRoot -HeadOnly; $r.Results | Sort-Object ...; $r.Results | Export-Csv ...) in a try/finally so Stop-Transcript always runs; move Stop-Transcript into the finally block and keep the existing logic in try, ensuring any thrown errors (with $ErrorActionPreference='Stop') will still trigger Stop-Transcript cleanup. Use the existing symbols Test-FetchMap, $r, $r.Results, Export-Csv and Stop-Transcript to locate where to add try/finally.

- Verify each finding against the current code and only fix it if needed.

In @Config/archive/Inventory-Software.v1.0.0-legacy.ps1 around lines 55 - 57, The sorting uses string comparison for DisplayVersion which misorders versions (e.g., "9.0" > "10.0"); update the pipeline around $rows | Sort-Object DisplayName, DisplayVersion -Descending | Group-Object DisplayName | ForEach-Object to sort by a parsed Version value instead: add a calculated property that converts DisplayVersion to a [version] (with a safe fallback for non-semver strings) and Sort-Object by DisplayName then the parsed version descending before Group-Object so Select-Object -First 1 picks the true latest version.

- Verify each finding against the current code and only fix it if needed.

In @Config/archive/Inventory-Software.v1.0.0-legacy.ps1 at line 1, The file Inventory-Software.v1.0.0-legacy.ps1 contains visible BOM characters (shown as "∩╗┐") at the start of the file; open Inventory-Software.ps1, remove the UTF-8 BOM or re-save the file using "UTF-8 without BOM" encoding (or ensure the file reader strips/handles BOM) so the first line no longer includes those characters and scripts/tools consuming the file see clean text.

- Verify each finding against the current code and only fix it if needed.

In @EnvSetup/Deploy-Shortcuts.bat around lines 17 - 30, The loop currently unconditionally strips the first character from ARG (see variables ARG and KV) which mangles keys if the user omits the leading "/" — add validation to reject or normalize arguments before stripping: check the first character of ARG is "/" (or call a parsing subroutine like :ParseArg from inside the for loop) and if it is missing, emit an error message and skip/exit; only then set KV by removing the leading char and continue extracting K and V and assigning SOURCEDIR, PREFIX, START, END, LIST, WHATIF. Ensure the fix uses the existing variable names (ARG, KV, K, V) and avoids using goto inside the for by employing call :ParseArg if needed.

- Verify each finding against the current code and only fix it if needed.

In @EnvSetup/Deploy-Shortcuts.bat around lines 218 - 225, The CsvLog batch routine (:CsvLog) currently inverts CSV escaping and inconsistently quotes fields; update the logic to double any existing double-quotes in input fields (replace " with "") for each field used (%~1, %~2, %~4) and then wrap every output field in double quotes when writing to %LOGCSV% so commas inside HOST, STATUS, or DETAIL don't break the CSV; apply this transformation to the variables used in the echo (e.g., produce sanitized versions of %~1, %~2, and %~4) and write: "timestamp","host","file","status","detail" consistently.

- Verify each finding against the current code and only fix it if needed.

In @EnvSetup/Deploy-Shortcuts.bat around lines 63 - 67, The nested FOR logic is incorrect and SRC1SIZE is never used; either remove the unused size code or correctly capture the file size. If you want the size, replace the nested loops with a single FOR that iterates the SRC1 path and uses the size modifier (use the same loop variable, e.g., %%Z with %%~zZ) to set SRC1SIZE and then use it where needed; otherwise delete the FOR lines that set SRC1SIZE and keep only the call to :LogLine using SRC1NAME. Ensure references to SRC1, SRC1SIZE and SRC1NAME are updated accordingly.

- Verify each finding against the current code and only fix it if needed.

In @EnvSetup/Deploy-Shortcuts.ps1 around lines 282 - 308, There’s a TOCTOU between Test-Path and Copy-Item around $dstPath/$publicDesktop; to prevent overwrites, perform the copy inside the try block with Copy-Item -NoClobber (or equivalent) and handle the resulting exception instead of assuming Test-Path -> Copy; update the try/catch around Copy-Item (the block using $WhatIf, $srcPath, $dstPath and Copy-Item) to catch an "already exists" error, log an explicit "EXISTS" or "VERIFY_FAIL" via LogLine/CsvLog, increment $stats.Fail, and only proceed to Get-SafeHash verification when the copy actually succeeded; alternatively implement a file-locking check before overwrite if strict locking is required.

- Verify each finding against the current code and only fix it if needed.

In @EnvSetup/Deploy-Shortcuts.ps1 around lines 85 - 91, The function Invoke-NetUseIpc is using the reserved automatic variable $args which shadows PowerShell's built-in; rename that local variable (e.g., to $netArgs) and update its declaration and every usage (change $args -> $netArgs and the call & net.exe $args -> & net.exe $netArgs) so the function no longer interferes with PowerShell's automatic $args variable while preserving the same argument array and return behavior.

- Verify each finding against the current code and only fix it if needed.

In @EnvSetup/Deploy-Shortcuts.ps1 around lines 45 - 50, The CsvLog function currently only quotes $file and $detail, so if $hostName or $status contain commas or quotes the CSV will break; update CsvLog to escape quotes for all fields ($hostName, $file, $status, $detail) (e.g. replace " with "" for each), and wrap each field in double quotes when constructing $line (use the same escaping logic applied to $detail), ensuring $logCsv is written with the new fully-quoted $line.

- Verify each finding against the current code and only fix it if needed.

In @EnvSetup/Deploy-Shortcuts.ps1 around lines 93 - 98, The function Remove-NetUse declares a local variable named $args which shadows PowerShell's automatic $Args variable; rename that variable (e.g., to $netArgs or $cmdArgs) everywhere inside Remove-NetUse and update the invocation (& net.exe ...) to use the new name so the automatic variable is not unintentionally overridden.

- Verify each finding against the current code and only fix it if needed.

In @EnvSetup/ImpactS-FixShortcuts.ps1 around lines 17 - 19, The script ensures Clients.txt exists but doesn't validate its contents; after trimming lines $pcs may be empty and will cause Fix-ImpactSShortcuts to run with no targets. After building $pcs (the Get-Content | Where-Object | ForEach-Object pipeline), add a check that $pcs contains at least one non-empty entry (e.g., test if $pcs.Count -gt 0 or if ($pcs) ), and if it is empty throw a clear error referencing $clientsPath and that no valid client names were found so the script stops before calling Fix-ImpactSShortcuts.

- Verify each finding against the current code and only fix it if needed.

In @EnvSetup/ImpactS-FixShortcuts.ps1 around lines 12 - 15, The script may pass a null/empty $repoHost to the external tool invocation ". $tools -RepoHost $repoHost"; validate $repoHost before that call by checking whether $repoHost is null/empty (variable $repoHost) and, if missing, either set a sensible default or emit a clear error and stop execution (e.g., Write-Error/exit) so the invocation of $tools (the sourcing of GoLiveTools via ". $tools -RepoHost $repoHost") never receives an empty value.

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/Get-MachineInfo.ps1 around lines 58 - 68, The catch block that returns a [pscustomobject] for failed WMI queries currently hardcodes Status = 'Firewall Blocked'; update the catch to capture the actual error (use $_ or $_.Exception.Message) and replace the hardcoded status with either a generic message like 'Query Failed' plus an ErrorMessage property containing the captured error, or set Status to the captured error when concise; ensure you still populate Timestamp, HostName ($Computer), and other fields as before and reference the catch block that builds the [pscustomobject] to make the change.

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/Get-MachineInfo.ps1 around lines 7 - 12, Before calling Get-Content, check that the path in $ListPath exists using Test-Path and throw a clear error if it does not; specifically, add a pre-check that verifies Test-Path $ListPath and throws a descriptive message (e.g., "List file not found: $ListPath") before the pipeline that populates $Computers so the Get-Content call in the $Computers assignment and the later if (-not $Computers) check won't raise a generic error.

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/Get-MachineInfo.ps1 around lines 94 - 95, The code uses Split-Path -Parent on $OutputPath to set $dir and then calls Test-Path/New-Item, but Split-Path returns an empty string when $OutputPath has no directory (e.g., "MachineInfo.csv"); update the logic around $dir (the variable set from Split-Path) so that if Split-Path -Parent yields null/empty you substitute a valid directory (for example the current directory via $PWD or Get-Location) before calling Test-Path and New-Item; modify the block that assigns $dir and the subsequent Test-Path/New-Item calls (refer to variables/commands: $OutputPath, $dir, Split-Path, Test-Path, New-Item) to ensure New-Item is never called with an empty path.

- 

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/Get-MonitorInfo.psm1 around lines 40 - 44, The WMI filter is vulnerable to unescaped $InstanceName and errors are silently swallowed; update the Get-CimInstance call that queries Win32_PnPEntity to escape $InstanceName for WMI filters (e.g., replace backslashes and single quotes in $InstanceName before embedding it) and replace the empty catch {} with a minimal logging action (e.g., Write-Verbose/Write-Warning or processLogger call) that includes the caught exception ($_ / $_.Exception.Message) so failures are visible while preserving behavior of checking $locationInfo.

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/Get-MonitorInfo.psm1 around lines 5 - 6, The WMI filter using $InstanceName can break if the value contains backslashes or single quotes; before calling Get-CimInstance for WmiMonitorDescriptorMethods, sanitize $InstanceName by escaping backslashes and single quotes (e.g., replace '\' with '\\' and "'" with "''") and then use that escaped value in the -Filter string for Get-CimInstance so the query remains valid when $InstanceName contains special characters.

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/Get-PrinterMacSerial.ps1 at line 254, The log uses incorrect subexpression interpolation in the Write-Log call; replace the `${($targets -join ', ')}` subexpression with the correct PowerShell form `$(...)` so the Write-Log invocation that references $targets (the Write-Log "----- Run start: ... -----" line) uses $( $targets -join ', ' ) for proper output formatting.

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/Get-PrinterMacSerial.ps1 around lines 89 - 92, The regex that matches Hex-STRING is using `\h`, which .NET treats as literal 'h' and will miss hex bytes with spaces; update the pattern used in the Hex-STRING match (the if block that checks $line for 'Hex-STRING:') to allow whitespace correctly (e.g., replace `\h` with `\s` or include `\s` in the character class such as `[0-9A-Fa-f\s:]+`) so the capture group correctly includes hex bytes separated by spaces or colons, leaving the subsequent -replace calls as-is to strip spaces/colons.

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/Get-PrinterMacSerial.ps1 at line 105, In Get-PrinterMacSerial.ps1 the if condition that checks $val uses a malformed regex '^00(:?[:]?00){5}$' — change the non-capturing group syntax to '(?:' so the pattern becomes '^00(?:[:]?00){5}$' and ensure the same fix is applied to the other occurrence noted (around line 120); alternatively replace the regex with a simple string comparison for all-zero MACs using $val -ne '00:00:00:00:00:00' (or normalized variant) to make the check clearer.

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/QueueInventory.ps1 at line 12, The default $OutputPath ("C:\Temp\QueueInventory.csv") may reference a non-existent directory causing Export-Csv to fail; update the script to validate and create the target directory before writing by deriving the directory path from $OutputPath (using Split-Path or similar), checking Test-Path on that directory, and calling New-Item -ItemType Directory -Force when missing, then proceed to call Export-Csv with $OutputPath as before; ensure this logic runs in the same scope where Export-Csv is invoked so $OutputPath is used unchanged.

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/QueueInventory.ps1 around lines 49 - 50, Replace the hardcoded SNMP community string "public" used in the snmpget calls that set $macRaw and $serialRaw by parameterizing the community value (e.g., add a script-level parameter or function parameter named $Community or read from an environment/credential store) and update the snmpget invocations to use that variable instead of the literal; also consider switching to or allowing SNMPv3 by making the version configurable (reference the snmpget calls that use $macOID and $serialOID so you update all places consistently).

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/ZebraPrinterTest.ps1 at line 1, The leading comment "Importing your previous SNMP/WMI/Live Check logic" is misleading because there is no import in this script; update the top-of-file comment in ZebraPrinterTest.ps1 (the existing comment string) to accurately reflect the script's behavior or remove it entirely so it doesn't claim imports that don't exist—ensure the new comment either describes what this script actually does (e.g., runs SNMP/WMI/Live checks) or simply remove the line.

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/ZebraPrinterTest.ps1 around lines 27 - 29, The regex used to extract the MAC from $macRaw in the $mac assignment only matches uppercase A-F and lower-case 'x', so it will miss lowercase hex letters; update the pattern used in the if ($macRaw -match "...") to accept both cases (e.g., expand the character class to include a-f and x/X or use a case-insensitive flag like (?i)Hex-STRING) so ($matches[1] -split ' ') produces a correct full MAC; target the $macRaw -match expression and the $matches[1] extraction in this block.

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/ZebraPrinterTest.ps1 around lines 54 - 65, The comment and hardcoded list are out of sync and expose internal IPs: update the header comment in ZebraPrinterTest.ps1 to reflect that multiple printers are supported (not "two Zebra printers"), remove the inline array assigned to $zebraIPs, and load the addresses from an external source (e.g., a config/JSON/CSV file or a script parameter such as a path or an environ var) with validation (ensure non-empty, valid IPs) and a safe fallback; also ensure sensitive IPs are not committed to the repo by documenting the required config file and excluding it via .gitignore or using environment-based injection.

- Verify each finding against the current code and only fix it if needed.

In @GetInfo/ZebraPrinterTest.ps1 around lines 24 - 25, The script uses SNMPv1 with the hardcoded community string "public" in the snmpget calls ($macRaw and $serialRaw), which is insecure; update the script to accept a community string parameter (e.g., $Community) and replace literal "public" in the snmpget invocations with that variable, validate the parameter is provided, and document it; ideally add support for SNMPv3 by introducing optional parameters for SNMPv3 credentials (username, auth/proto, priv/proto) and call snmpget with -v3 when those are supplied to enable authenticated/encrypted queries (fall back to the parameterized community only if SNMPv3 credentials are absent).

- Verify each finding against the current code and only fix it if needed.

In @OCR/build_host_unc_csv.py at line 31, The Host column assignment currently does df["Host"] = df["WorkstationID"].apply(lambda n: f"{args.host_prefix}{int(n)}) which will throw on NaN or non-numeric WorkstationID values; modify the logic to first filter or coerce invalid WorkstationID entries (e.g., drop or mask NaNs/non-numeric) before applying the conversion, or change the lambda used in df["WorkstationID"].apply to safely handle bad values (check for pandas.isna(n) or use pd.to_numeric with errors='coerce' and skip/raise as appropriate) so that the creation of df["Host"] (and the subsequent dropna()) never attempts int() on invalid data; locate the Host assignment and the nearby dropna() usage to implement the safe conversion.

- Verify each finding against the current code and only fix it if needed.

In @OCR/locus_mapping_ocr.py around lines 91 - 94, Replace the bare except in the try/except around converting txt to int so it only catches ValueError; specifically in the block where you do "try: num = int(txt) except: continue" change the except to "except ValueError:" to avoid swallowing KeyboardInterrupt/SystemExit and other unrelated exceptions while still handling invalid integer parsing for the txt -> num conversion.

- Verify each finding against the current code and only fix it if needed.

In @OCR/locus_mapping_ocr.py around lines 129 - 140, The nearest(ws_points, pr_points) function doesn't handle an empty pr_points list so best_pid stays None and best_d remains 1e18; modify nearest to return an empty list immediately when pr_points is empty (e.g., if not pr_points: return []), or alternatively for each ws entry skip/emit no match instead of appending (wid, None, 1e18); update references to nearest in callers to expect an empty result if no printers are detected (or handle skipped matches) so the CSV never contains the sentinel 1e18 value.

- Verify each finding against the current code and only fix it if needed.

In @OCR/locus_mapping_ocr.py at line 1, Remove the leading Unicode BOM (U+FEFF) at the very start of the OCR/locus_mapping_ocr.py file so the first byte is the expected shebang or Python code; open the file in a text editor that can show/strip BOM or re-save it as UTF-8 without BOM and verify the module name locus_mapping_ocr.py no longer starts with an invisible character.

- Verify each finding against the current code and only fix it if needed.

In @Tests/Pester/GetInfo.Tests.ps1 around lines 69 - 82, The test currently reads the file in BeforeAll (the Get-Content call in the Describe 'QueueInventory.ps1 — script-level checks') before the "Script file exists" It runs, making the existence test unreachable if the file is missing; fix by changing the setup so $queuePath is set in the top-level BeforeAll but do NOT call Get-Content there—keep the It 'Script file exists' which checks (Join-Path $repoRoot 'GetInfo\QueueInventory.ps1') | Should -Exist, and only read $script:queueContent with Get-Content in a SECONDARY setup that runs after the existence check (e.g., a nested BeforeAll/Context that calls Get-Content -Raw -ErrorAction Stop guarded by Test-Path $queuePath or placed after the existence It); this ensures the existence test runs before attempting to read the file while preserving the later test that matches 'Win32_Printer|Get-Printer'.

- Verify each finding against the current code and only fix it if needed.

In @Tests/Pester/GetInfo.Tests.ps1 around lines 50 - 58, The BeforeAll block currently calls Get-Content with -ErrorAction Stop so a missing file aborts setup and prevents the "Module file exists" test from running; modify the test setup by first asserting the file exists using the same $modulePath (or move the It 'Module file exists' check before the BeforeAll file read), then only call Get-Content (or keep -ErrorAction Stop) to load $script:moduleContent if the existence assertion passes; alternatively remove -ErrorAction Stop and add explicit handling around Get-Content in the BeforeAll to skip or fail gracefully so tests don't error out before the existence test runs.

- Verify each finding against the current code and only fix it if needed.

In @Tests/Pester/Utilities.Tests.ps1 around lines 29 - 37, The Mock for Test-Connection in the Test-Network spec is incorrect for Pester 5; remove the -ModuleName '' and -Verifiable parameters and simply declare Mock Test-Connection { $true } so the mock applies in the caller's scope and the Test-Network invocation uses the mocked Test-Connection; keep the rest of the assertions unchanged (reference symbols: Mock Test-Connection, Test-Network).

- Verify each finding against the current code and only fix it if needed.

In @Tests/Preflight.ps1 around lines 76 - 81, Get-TokenGroups currently calls $id.Groups.Translate([System.Security.Principal.NTAccount]) which throws IdentityNotMappedException if any SID is unresolved; change Get-TokenGroups to translate each SID individually (iterate $id.Groups, call .Translate([System.Security.Principal.NTAccount]) inside a per-item try/catch or use a safe conversion method), skip or ignore groups that fail translation, and return the remaining account name strings so orphaned/deleted SIDs do not abort the pipeline.

- Verify each finding against the current code and only fix it if needed.

In @Tests/Preflight.ps1 around lines 96 - 99, The ACL identity comparison uses mixed types: $sid is a SecurityIdentifier object while $_.IdentityReference and entries from Get-TokenGroups are strings/NTAccount, so the equality check can fail; update the filtering that builds $rules (the Where-Object over $acl.Access) to normalize both sides to the same string form (for example call $_.IdentityReference.Value or translate $sid to an NTAccount string) and compare strings, and likewise ensure $groups contains comparable string values from Get-TokenGroups before checking membership (affects $sid, $groups, Get-TokenGroups, $acl.Access, $rules, and $hasWriteMembers).

- Verify each finding against the current code and only fix it if needed.

In @Tests/Preflight.ps1 at line 145, The current line uses Tee-Object which writes stringified table output, not proper CSV; change the pipeline so the sorted $script:Report is exported with Export-Csv (e.g. $sorted = $script:Report | Sort-Object Area,Target,Check; $sorted | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8) and then, if console output is still desired, write the same $sorted to the host (e.g. $sorted | Format-Table | Out-Host or Write-Output) instead of relying on Tee-Object; update the line that references Tee-Object to use these steps so the file is a valid CSV while preserving console output.

- Verify each finding against the current code and only fix it if needed.

In @Tests/Preflight.ps1 at line 26, The script currently hardcodes a domain-specific default in the $TargetOU variable which breaks other environments; change $TargetOU into a proper script parameter (e.g., add it to the Param() block) and make it mandatory or set a neutral default (empty string or a generic placeholder like "OU=YourOU,DC=example,DC=com") and validate at startup (throw a clear error and exit if not overridden). Update any usage of $TargetOU in functions/logic to rely on the parameter and add a short comment or README note instructing users to provide their environment-specific OU.

- Verify each finding against the current code and only fix it if needed.

In @Tests/Preflight.ps1 around lines 117 - 122, The OU ACL check is comparing mismatched types: $_.IdentityReference (an IdentityReference object) against $groups (strings) and $sid (a SecurityIdentifier), causing false negatives; convert IdentityReference and sid to consistent strings before comparison or compare their Value properties instead. Update the Where-Object that builds $rules to compare [string]$_.IdentityReference (or $_.IdentityReference.Value/Translate([System.Security.Principal.SecurityIdentifier]).Value) against the string list from Get-TokenGroups and against $sid.Value (or cast $sid to string) so $rules and subsequently $hasWrite correctly detect CreateChild/WriteProperty Allow entries.

- Verify each finding against the current code and only fix it if needed.

In @Tests/Preflight.ps1 around lines 89 - 106, The script lacks an else branch when the ActiveDirectory module is not available for the AD group checks; add an else to the if (Get-Module -ListAvailable -Name ActiveDirectory) block that calls Add-Result for each item in $ADGroupsToModify (or a single summary entry) with Area 'AD / Rights', Check 'Write members (hint)', Result 'Info' and a Detail like "ActiveDirectory module not available; skipping group checks" (use the same reference key 'ADPrivGroups') so users see why no group results appear; update the block surrounding ADGroupsToModify/Get-Module/Import-Module to include this fallback.

- Verify each finding against the current code and only fix it if needed.

In @Utilities/Invoke-FileShare.ps1 at line 20, The parameter default for SharePath ([string]$SharePath) hardcodes an internal server name; remove the literal '\\LPW003ASI037\C$' by either making the parameter mandatory (no default), deriving a default from an environment variable or config (e.g., $env:FILE_SHARE_PATH), or replacing it with a placeholder like '\\<HOSTNAME>\C$'; also add [ValidateNotNullOrEmpty()] to the SharePath parameter declaration to prevent empty values and update any help text to document the new behavior.

- Verify each finding against the current code and only fix it if needed.

In @Utilities/Take-Screenshot.ps1 around lines 9 - 15, Wrap the screen-capture sequence in a try/finally so $graphics and $bitmap are always disposed even if CopyFromScreen or $bitmap.Save throws; specifically, allocate $bitmap and $graphics before the try, perform CopyFromScreen and $bitmap.Save inside the try block, and call $graphics.Dispose() and $bitmap.Dispose() in the finally block (referencing the existing $bitmap, $graphics, CopyFromScreen and Save symbols to locate where to insert the try/finally).

- Verify each finding against the current code and only fix it if needed.

In @Utilities/Test-Network.ps1 around lines 5 - 7, The DESCRIPTION is inaccurate: the Test-Network function does not return simple booleans but a [pscustomobject] per host containing ComputerName and Reachable properties; update the .DESCRIPTION text to state that Test-Network returns an object (or array of objects) with ComputerName and Reachable (boolean) for each target, or alternatively change the implementation to return plain booleans if you prefer that behavior—refer to the Test-Network function and its ComputerName/Reachable properties when making the change.

- Verify each finding against the current code and only fix it if needed.

In @Utilities/Unblock-All.ps1 at line 1, The file contains stray encoding artifacts ("∩╗┐") at the start of the script comment; remove those characters from the opening line (the leading characters before "<# Unblock every file... #>") and re-save Utilities/Unblock-All.ps1 as UTF-8 without BOM so the script starts with a clean comment token and parses correctly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Controller.ps1 around lines 81 - 86, The two cmd /c invocations that call schtasks (the lines creating and running the SysAdminSuite_MapFromFile task using variables $c, $start, $tr) currently pipe output to Out-Null and do not check process exit codes; update both to capture the command's exit status (e.g., run via Start-Process -PassThru or capture $LASTEXITCODE after & cmd /c) and verify it is 0, logging an error with Write-Error (including the command and $LASTEXITCODE or stderr) and exiting non-zero (or throwing) if it failed so task creation or execution errors are not ignored.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Controller.ps1 around lines 33 - 36, Replace the hardcoded user-specific OneDrive path assigned to $localRoot and the joined $localScript/$localCsv with a portable, script-relative resolution: use the script's directory (via $PSScriptRoot or Split-Path -Parent $MyInvocation.MyCommand.Definition) or accept a parameter/env var for the root, then build Map-MachineWide-FromFile.ps1 and wcc_printers.csv paths from that; update references to $localRoot, $localScript, and $localCsv accordingly so the script no longer contains the username or OneDrive-specific path.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Deploy-AllPrinters.ps1 around lines 17 - 25, The New-RemoteTask function currently creates scheduled tasks using "/RU SYSTEM" which installs printers into the SYSTEM account; change the task creation to run in the interactive user's context by using the actual target user credentials when available: modify New-RemoteTask to accept or derive the target interactive username/password (use $AltUser/$AltPass or a provided $TargetUser/$TargetPass) and build the $create and $run argument arrays with "/RU", "<user>", and "/RP" or "/P" (as appropriate) instead of always using "/RU SYSTEM"; ensure when $AltUser is not provided you fallback to creating the task with the target's user (or switch to a different mechanism such as invoking a logon script or Group Policy Preferences) so that the printui.dll /in command executes in the logged-in user's profile rather than SYSTEM.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Deploy-AllPrinters.ps1 around lines 21 - 24, Check the exit status after calling schtasks for both the creation and the run steps: after executing "schtasks @create | Out-Null" and after "schtasks @run | Out-Null" inspect $LASTEXITCODE and if non-zero log the failure (including stdout/stderr) and exit/non-zero return so failures aren't silently ignored; update the block that constructs $run (and the create invocation) to capture output if needed and ensure the script fails fast when schtasks returns an error.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Deploy-AllPrinters.ps1 around lines 46 - 54, The finally blocks delete the scheduled task immediately after starting it (New-RemoteTask + schtasks /Run / rundll32), which can remove the task before execution finishes; modify the cleanup so that before calling Remove-RemoteTask for both $Target and $fqdn you call Wait-TaskComplete (or an equivalent wait/timeout function) for the specific $task on that host to ensure the task has finished (handle timeout/error paths and still remove the task afterwards); update the blocks around New-RemoteTask, the inner catch/finally (fqdn) and the outer finally (Target) to call Wait-TaskComplete($Target, $task) / Wait-TaskComplete($fqdn, $task) prior to Remove-RemoteTask.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Deploy-AllPrinters.ps1 around lines 4 - 5, The AltPass parameter is a plaintext string and is being passed to schtasks.exe exposing credentials; change the parameter design to accept a PSCredential (e.g., replace [string]$AltUser/[string]$AltPass with [PSCredential]$Credential or make $AltPass a [SecureString]) and update all call sites (notably where schtasks.exe is invoked) to extract the username/password only when required using $Credential.UserName and $Credential.GetNetworkCredential().Password, and preferably switch the scheduled-task creation to the ScheduledTasks/TaskScheduler APIs or Register-ScheduledTask which accept SecureString/PSCredential so you never pass the plaintext password on the command line.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/ENT_Printer_Mapping via Queue.vbs at line 1, Remove the global "ON ERROR RESUME NEXT" which hides all failures; instead use localized error handling around risky operations (e.g., COM creation or printer mapping calls) by temporarily enabling "On Error Resume Next" only just before the call, immediately checking "Err.Number" after the operation, logging/echoing the error and exiting or retrying as appropriate, then restoring normal handling with "On Error GoTo 0"; reference the global "ON ERROR RESUME NEXT" to remove it and use checks against "Err" and explicit logging (for example via WScript.Echo or your existing logging routine) around CreateObject("WScript.Network") and the printer mapping routine.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/ENT_Printer_Mapping.vbs at line 5, Replace the hard-coded IP in the printer connection call so the script uses a DNS hostname instead: update the call to objNetwork.AddWindowsPrinterConnection "\\printserver.domain.com\WL244-ENT06X" (replace printserver.domain.com with the actual printer server hostname) so AddWindowsPrinterConnection references the server by name rather than "10.137.67.158".

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/ENT_Printer_Mapping.vbs around lines 1 - 2, Remove the global "ON ERROR RESUME NEXT" and instead use localized error handling around the WScript.CreateObject call: place "On Error Resume Next" immediately before Set objNetwork = WScript.CreateObject("WScript.Network"), then check Err.Number (and Err.Description) after that call to detect failure, emit a clear error message (e.g., via WScript.Echo or appropriate logger) and call WScript.Quit with a non‑zero exit code on failure; finally call Err.Clear and "On Error GoTo 0" to re-enable normal error handling. Ensure you reference the objNetwork creation site and the Err object when implementing these checks.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Get-MachineInfo.ps1 around lines 58 - 68, The catch block in Get-MachineInfo.ps1 currently returns a pscustomobject with Status = 'Firewall Blocked', which mislabels all exceptions; update the catch in the function (the pscustomobject created in the catch) to capture the actual error (use $_ or $PSItem and its .Exception.Message or full .ToString()) and include that text in the returned object (e.g., set Status to the captured message or add an ErrorMessage field) while preserving the other properties (Timestamp, HostName/Serial/IPAddress/MACAddress/MonitorSerials) so callers can see the real failure cause.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Get-MachineInfo.ps1 around lines 94 - 96, Split-Path -Parent can return an empty string for a bare filename, causing New-Item -Path "" to fail; update the block around $dir, $OutputPath, Split-Path, Test-Path and New-Item so you first check that $dir is not null/empty (e.g. if (-not [string]::IsNullOrWhiteSpace($dir)) { if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null } }) and only attempt to create the directory when $dir contains a valid path; leave the Export-Csv $OutputPath line unchanged.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Get-MachineInfo.ps1 around lines 85 - 86, The loop currently uses Get-Job -State Running (which returns all session jobs); restrict throttling to only jobs created by this script by filtering by a known job name prefix or stored job objects: replace Get-Job -State Running with a filtered set (e.g., Get-Job -State Running | Where-Object Name -like "$JobPrefix*" or use a tracked array like $CreatedJobs | Where-Object State -eq 'Running') and pass that filtered collection to both the count check and Wait-Job -Any so only your script's jobs (not unrelated session jobs) affect $Throttle and waiting.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-EL082-All-deprecated.vbs around lines 16 - 20, The script currently uses "On Error Resume Next" around the loop that calls net.AddWindowsPrinterConnection Q(i), which silences failures and leaves no trace before the script self-deletes; change this by checking Err.Number immediately after each net.AddWindowsPrinterConnection call (and using Err.Clear after handling), record any failures (e.g., append printer name and Err.Number/Err.Description to a log via WScript.Echo or write to a simple file), continue the loop for remaining Q entries, and ensure you emit or persist a summary of successes/failures before the script deletes itself so failed mappings are visible; keep the loop around Q and the same function name net.AddWindowsPrinterConnection but add the Err.Number checks and logging logic.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-EL082-All-deprecated.vbs around lines 25 - 26, The unconditional self-delete call using CreateObject("Scripting.FileSystemObject").DeleteFile WScript.ScriptFullName, True should be removed or gated so the script only deletes itself when all printer mapping operations succeeded; locate the DeleteFile call and any use of On Error Resume Next and introduce a success flag (e.g., set mappingSuccess = True/False within the mapping function or after each mapping) and only call DeleteFile when mappingSuccess is True (and optionally log success), otherwise skip self-deletion to allow rerun and avoid AV/EDR triggers.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-EL082-All.vbs around lines 93 - 110, The TailNumber function can throw on empty or non-numeric inputs; add a defensive guard at the start to return -1 when Len(s)=0, and before each CInt call (the CInt(Mid(s, i+1)) branch and the final CInt(s) branch) verify IsNumeric(...) on the substring and return -1 if not numeric so CInt is never called on an empty/non-numeric string.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-FromCsv-PerUser.ps1 at line 8, The assignment to $default can return an array when multiple rows match; change the selection to pick a single Queue value (e.g., the first match) so $default is always a scalar. Update the pipeline that uses $rows | Where-Object { $_.Default -match '^(y|yes|true|1)$' } to expand and return only one Queue (use Select-Object -First 1 -ExpandProperty Queue or equivalent) before using $default later in the script (the variable $default and the Where-Object filter on the Default property identify the location).

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-FromCsv-PerUser.ps1 at line 4, Check that the CSV exists and is readable and wrap the Import-Csv call (where $rows is assigned from $CsvPath) in a try/catch; if Test-Path $CsvPath fails or Import-Csv throws, write a clear error via Write-Error (or Write-Host) and exit with non-zero status. After successful import validate that each required column name ("Queue" and "Default") exists in $rows[0].psobject.properties.name (or via $rows | Get-Member -MemberType NoteProperty); if a required column is missing, emit a descriptive error and exit. Ensure the catch block surfaces the caught exception message for troubleshooting.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-FromCsv-PerUser.ps1 around lines 9 - 14, The foreach loop that calls Start-Process rundll32.exe to add printers and the subsequent Start-Process that sets $default need error handling: wrap each Start-Process invocation inside a try/catch (or capture the process object and check ExitCode) around the foreach ($r in $rows) and the if ($default) block, and on failure emit a clear Write-Error/Write-Warning including the printer name ($r.Queue or $default) and the exception message; optionally stop execution or collect failures into a list for summary at the end so mapping failures are visible to the user.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-Printer-PerUser.vbs around lines 8 - 9, Limit the On Error Resume Next to only the registry write by placing it immediately before the RegWrite call and restore normal error handling with On Error GoTo 0 right after; then check Err.Number (or Err.Clear) to detect RegWrite failures and handle/log them. Also ensure subsequent calls AddWindowsPrinterConnection and SetDefaultPrinter run under normal error handling and that their failures are checked (using Err.Number or return values) so the script can exit with a non-zero code on error. Use the identifiers RegWrite, AddWindowsPrinterConnection, SetDefaultPrinter, Err.Number, and On Error GoTo 0 to locate and update the code.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-Run-Controller-CloseButNo.ps1 at line 40, The $PlanOnly switch is declared but never used to skip actual execution; update the main scheduling/execution block that creates tasks and calls Invoke-Command (the loop that schedules/runs the worker on remote hosts) to check $PlanOnly and, when set, skip performing remote execution and task creation, instead logging or outputting the planned actions; leave the existing Mode output intact so it still shows the plan-only state and ensure any post-run cleanup/summary respects $PlanOnly by not attempting to process results or wait for jobs when in plan-only mode.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-Run-Controller-CloseButNo.ps1 at line 110, The throw uses the automatic $Host because the script also declares a local variable named $host (shadowing $Host); rename the local variable (e.g., change the declared $host at its assignment to $rowHost or $hostEntry) and update all uses including the throw line to reference that new name (replace $host in the throw with $rowHost/$hostEntry) so the message prints the intended host value rather than the automatic $Host object.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-Run-Controller-CloseButNo.ps1 at line 234, The Copy-Item call using Join-Path $latest.FullName '*.*' misses files without extensions; change the wildcard to '*' so all files are matched and copied (update the Copy-Item invocation that references $latest.FullName and $hostOut to use Join-Path $latest.FullName '*' and keep -Destination $hostOut -Force -ErrorAction SilentlyContinue).

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-Run-Controller-CloseButNo.ps1 at line 210, The schtasks invocation interpolates the hostname variable $c directly into the command ($create assignment), risking command injection; validate $c against a strict hostname pattern (e.g., letters/digits/hyphen/dot only) and reject or sanitize any input that doesn't match, and avoid raw string interpolation when building the /S and /TR arguments — instead construct the arguments safely (or use Start-Process with an ArgumentList or PowerShell parameterized invocation) for $psCmd/$pwsh/$taskName so special characters in $c cannot break the command.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-Run-Controller-CloseButNo.ps1 around lines 59 - 70, The Get-HostRows function declares a parameter named $Host (and uses a local $host) which shadows PowerShell's automatic $Host; rename the parameter and its local usage to a non-conflicting identifier (e.g. $TargetHost or $HostName) and update all references inside the function (including the Where-Object filter and any assignments that set $host/$Host) to use the new name to avoid clobbering the automatic $Host variable.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Map-Run-Controller-CloseButNo.ps1 around lines 201 - 203, The hardcoded US date format for $stDate will break on non-US locales; change the assignment of $stDate (which is derived from $when alongside $stTime) to use the current culture's short date pattern (e.g., use the culture-aware short date format or ToShortDateString()) so schtasks receives a date in the machine's expected format; update the $stDate creation to use Get-Culture().DateTimeFormat.ShortDatePattern (or $when.ToShortDateString()) instead of 'MM/dd/yyyy' and keep $stTime as-is.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/MapWL244_ENT06X-IPP_Driver.vbs around lines 35 - 39, The SelfDeleteAndQuit sub calls sh.DeleteFile but sh is a WScript.Shell (which has no DeleteFile), causing a runtime error; change the deletion to use a Scripting.FileSystemObject instance (create or reuse an FSO object and call its DeleteFile method with WScript.ScriptFullName) and then quit; reference SelfDeleteAndQuit, the sh variable, and use FileSystemObject.DeleteFile to fix the runtime error.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/MapWL244_ENT06X-IPP_Driver.vbs at line 5, The Const declaration using concatenation is invalid: replace the Const PORT = "IP_" & IP with a normal variable assignment (e.g., declare PORT via Dim and assign PORT = "IP_" & IP) after IP is defined/after objects are initialized (move it below the initialization block referenced in the file) so PORT is set at runtime; update any references to PORT unchanged.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/MapWL244_ENT06X-IPP_Driver.vbs around lines 17 - 26, After calling the WMI port creation method p.Put_ (the Win32_TCPIPPrinterPort instance), check Err.Number and Err.Description immediately to detect failures (e.g., port exists or permission denied) and handle them before proceeding to printer installation; update the block that creates the port (variables svc, p and the p.Put_ call) to inspect Err.Number right after p.Put_, log a clear error via your logging mechanism or WScript.Echo including Err.Number/Err.Description, and abort or skip the subsequent installation steps when an error is present.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/MapWL244_ENT06X-PlainJane.vbs around lines 3 - 6, The PORT Const uses an expression ("IP_" & IP) which VBScript disallows; change PORT from a Const to a regular variable by declaring it (e.g., Dim or just assign) after the literal Consts QUEUE and IP are defined, and assign PORT = "IP_" & IP so the concatenation happens at runtime; leave QUEUE, IP and PRN as Consts and only convert PORT to a variable.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/MapWL244_ENT06X-PlainJane.vbs around lines 16 - 22, Check the return codes from the fallback sh.Run calls that add the TCP/IP port and install the printer (the two sh.Run invocations using prnport.vbs and rundll32/PrintUIEntry) and handle failures by logging the Err.Description or return code and then exit with a non-zero code via WScript.Quit; specifically, after each sh.Run capture its numeric return, if it is non-zero set Err.Description/a custom message including PORT, IP or PRN, write that to the log (or Err object) and call WScript.Quit with a non-zero value so callers know the fallback failed.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/MapWL244_ENT06X.vbs around lines 25 - 33, After calling p.Put_ (the Win32_TCPIPPrinterPort SpawnInstance_ created via svc.Get), check Err.Number immediately and handle failures: if Err.Number <> 0, log a descriptive error including Err.Number, Err.Description and the port name (PORT), then abort further actions (e.g., call WScript.Quit with non‑zero) to avoid proceeding to printer install; also consider clearing Err (Err.Clear) before retrying or returning. Ensure this check sits directly after p.Put_ so any creation failure is caught before the rundll32 installation step.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/MapWL244_ENT06X.vbs around lines 6 - 10, The PORT constant uses an expression ("PORT  = ""IP_"" & IP") which is invalid in VBScript; change PORT from a Const to a runtime variable by replacing the Const declaration with a Dim (or use a regular variable) and assign its value after IP is defined (e.g., Dim PORT followed by PORT = "IP_" & IP), leaving QUEUE, IP, PRN, and DRV as Consts if they are literal; update any references to PORT accordingly so the script parses and runs.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/MapWL244_ENT06X.vbs around lines 44 - 48, The SelfDeleteAndQuit sub currently calls sh.DeleteFile but sh is a WScript.Shell and has no DeleteFile method; replace that call to use a FileSystemObject: create a Scripting.FileSystemObject via CreateObject, call its DeleteFile method with WScript.ScriptFullName (e.g., fso.DeleteFile WScript.ScriptFullName), keep or reapply error handling around the deletion, and then call WScript.Quit 0; update references in SelfDeleteAndQuit (and any creation of sh if needed) to ensure the deletion uses the FSO object rather than sh.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/MapWL244_ENT06X.vbs around lines 38 - 41, Capture the return code from the sh.Run call that executes rundll32 (replace the current bare sh.Run invocation with an assignment like rc = sh.Run(..., 0, True)), then conditionally call SelfDeleteAndQuit only if rc indicates success (e.g., rc = 0); if rc is non‑zero, do not self-delete and instead write an error message (via WScript.Echo or your existing logging mechanism) including the rc and relevant variables (PRN, PORT, DRV) so failure details are preserved for troubleshooting — locate the sh.Run invocation and the subsequent SelfDeleteAndQuit call to implement this check.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/MapXeroxPrinter.vbs around lines 7 - 11, The CONST declaration for PORT ("PORT = "IP_" & IP") is invalid because VBScript Const cannot use expressions; change PORT to a runtime variable: keep QUEUE, IP, PRNNAME, DRIVER as Const, then declare PORT with Dim (or a regular variable) and assign PORT = "IP_" & IP immediately after the Const block so PORT is computed at runtime; update any references to PORT accordingly (references: QUEUE, IP, PORT, PRNNAME, DRIVER).

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/MapXeroxPrinter.vbs around lines 37 - 43, The sh.Run call's exit code is being discarded and Err.Number is not reliable for command failures; change the call to capture its return value (e.g., assign the result of sh.Run to a variable) and then check that variable for a non-zero exit code before calling GoSub SetExtras (use a zero check: if returnValue = 0 then GoSub SetExtras else handle/log the non-zero exit code). Update the code around the sh.Run invocation and the If Err.Number use so it checks the captured returnValue instead of Err.Number; reference the existing sh.Run invocation, the SetExtras GoSub, and symbols PRNNAME/PORT/DRIVER when locating where to modify.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/MapXeroxPrinter.vbs around lines 31 - 32, The call in MapXeroxPrinter.vbs hardcodes the en-US path and ignores the sh.Run return code; change the script to locate a locale-independent prnport.vbs (e.g., use "%windir%\System32\spool\tools\prnport.vbs" or search for "printing_admin_scripts" subfolders and pick the existing one) instead of "%windir%\System32\printing_admin_scripts\en-US\prnport.vbs", then call sh.Run with a capture of the return value (assign the result of sh.Run to a variable) and check it (log or exit) if non-zero; reference PORT and IP variables and the sh.Run invocation so you update the exact call site.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Printer script.vbs around lines 25 - 29, The startup-deploy VBScript (references to objNetwork.AddWindowsPrinterConnection and the non-existent SetDefaultPrinter) poses security/operational risks: stop auto-execution and add checks; remove or archive the file if it's no longer used, and add validation, logging and rollback if you intend to keep it. Specifically, replace blind Startup-folder deployment with an enterprise method (GPO) or gate the script with machine/user validation (check hostname/AD group or user SID) before running any objNetwork.AddWindowsPrinterConnection calls, implement logging of each AddWindowsPrinterConnection attempt and errors, add a rollback path to remove added printers on failure, and either update or remove the misleading SetDefaultPrinter reference and move the file out of "Archive" if still active.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Printer script.vbs around lines 16 - 20, The comment block references a SetDefaultPrinter statement that does not exist (only wscript.echo "Done!" is present); either remove or update the misleading lines to reflect current behavior, or if intended, add the missing SetDefaultPrinter call: ensure the comment refers to the actual action performed (wscript.echo) and, if you add a printer change, implement a SetDefaultPrinter invocation with the proper print server/queue and document it; search for the string wscript.echo "Done!" and the term SetDefaultPrinter to locate where to edit so the comment and code match.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/Printer script.vbs at line 1, Remove the blanket "ON ERROR RESUME NEXT" and replace it with explicit error handling: delete the "ON ERROR RESUME NEXT" statement and the now-obsolete lines 5-13, and add an error handler (e.g., "On Error GoTo ErrorHandler") that checks Err.Number/Err.Description after printer connection attempts, logs or MsgBox's a clear error message with Err.Number and Err.Description, and performs cleanup/exit in an ErrorHandler label; reference the existing printer connection loop (the loop mentioned in the review) to handle retries/failures instead of suppressing all errors.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/PrinterConfig.vbs around lines 82 - 95, Sub SetDefaultPrinter uses "On Error Resume Next" but doesn't clear prior errors; insert "Err.Clear" immediately after the "On Error Resume Next" line in SetDefaultPrinter so Err.Number reflects only errors from networkObj.SetDefaultPrinter, mirroring the fix applied in AddNetworkPrinter and ensuring the subsequent Err.Number/Err.Description checks are accurate.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/PrinterConfig.vbs around lines 65 - 80, The AddNetworkPrinter function can report a false failure because Err may contain a prior error; call Err.Clear before attempting networkObj.AddWindowsPrinterConnection and again after handling the result so Err.Number reflects only this operation; update the function AddNetworkPrinter to invoke Err.Clear prior to WScript.Echo "Adding printer..."/networkObj.AddWindowsPrinterConnection and ensure Err.Clear is used appropriately after reading Err.Number/Err.Description so future checks are not affected.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/SANDBOX_FIX_DOCUMENTATION.md around lines 38 - 67, Update the documentation to clearly state the relationship and sequence between Option 1 and Option 2: explicitly say that Option 1 (modifying Run-EL082-Sandbox.ps1 by removing -SandboxRoot) was a quick fix applied first to restore remote-only deployment, and Option 2 (introducing Publish-EL082-Pack-Sandbox.ps1) was subsequently implemented to provide full sandbox support; also clarify whether Run-EL082-Sandbox.ps1 now points to or is replaced by the new sandbox-aware Publish-EL082-Pack-Sandbox.ps1 and adjust the lines referencing Run-EL082-Sandbox.ps1 (58-59) to reflect that Option 1 was temporary and Option 2 is the long-term solution so readers understand these are sequential/related changes, not two competing alternatives.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/implementation.ps1 around lines 1 - 12, The file implementation.ps1 currently contains only commented example invocations and therefore does nothing; decide whether it should be executable or remain documentation: if it is documentation/usage, rename it to README.md or USAGE.txt and move the examples there; if it is a template add a header comment explaining users must uncomment one of the Publish-EL082-Pack.ps1 invocations (e.g., the -MapNow / -InstallDefaultAtLogon / -PauseAtEnd options) and keep them commented, or if it should run by default uncomment and/or implement minimal argument parsing logic in implementation.ps1 to dispatch to Publish-EL082-Pack.ps1 based on provided flags (e.g., support -MapNow and -InstallDefaultAtLogon), and finally confirm the Archive folder is the intended location for an active dispatcher and move the script out of Archive if it must be live.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/EL082_Deployment_Results_Guide.md at line 128, Remove the trailing whitespace at the end of the line containing "Use sandbox mode to isolate issues" in EL082_Deployment_Results_Guide.md (the line flagged in the diff); edit that line in the mapping/Archive/jackson heights/EL082_Deployment_Results_Guide.md file to delete any trailing spaces so the line ends immediately after the final word and re-save the file.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/EL082_Troubleshooting_Guide.md at line 119, The summary section in EL082_Troubleshooting_Guide.md contains a hardcoded user path with PII; replace that specific hardcoded path text in the summary (and the repeated occurrences around the same area) with a generic placeholder such as "/home/USER/ORG/..." or "<USER_PATH>" to remove username and organization details, ensuring all repeated instances (the summary and the lines referenced near the same block) are updated consistently.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/EL082_Troubleshooting_Guide.md at line 8, In EL082_Troubleshooting_Guide.md update the example error line that currently starts with "Missing required file:" to remove the hardcoded PII path and replace it with a generic placeholder (e.g. "Missing required file: <REPO_ROOT>/mapping/el082_printers.csv" or "Missing required file: C:\\Users\\<username>\\mapping\\el082_printers.csv"); ensure the literal string shown in the file is sanitized and does not contain the username "pa_rperez26" or the organization "Northwell Health" so future commits don’t leak PII.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/EL082_Troubleshooting_Guide.md at line 115, Remove the stray closing markdown code fence (an isolated "```" backtick fence) that was left after the Test-Connection example; locate the orphaned closing fence token and delete it so the code block that starts at the earlier fence remains properly closed (remove the extra "```" after the example).

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/Map-EL082-MachineWide.ps1 at line 81, The empty catch {} silently swallows failures (e.g., Get-Printer/permission errors); replace the empty catch with handling that logs the error and context and rethrows or returns a non-success status as appropriate. Specifically, in the try/catch surrounding the printer/mismatch logic (the catch {} after the Get-Printer block), use the catch block to write the exception details (e.g., Write-Error or Write-EventLog with $_ / $PSItem or $error[0]) and include identifying context (machine name or the operation) and decide whether to throw; do not leave the catch empty.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/Map-EL082-MachineWide.ps1 at line 12, The script currently ignores the user-supplied $PrintersCsv when -Simulate is set because $CsvPath is hardcoded to _Join $RemoteRoot 'ProgramData\EL082\el082_printers.csv' whenever $Simulate is true; change the logic that sets $CsvPath so that when $Simulate is true it first checks whether $PrintersCsv has been provided (non-empty) and uses that, falling back to _Join $RemoteRoot 'ProgramData\EL082\el082_printers.csv' only if $PrintersCsv is null/empty; update the assignment that references $CsvPath (and any use of _Join, $Simulate, $RemoteRoot, $PrintersCsv) so simulate mode respects the $PrintersCsv parameter.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/Map-EL082-MachineWide.ps1 around lines 70 - 79, The prune loop incorrectly uses $rows[0].Server for every printer and compares $name to the UNC's last segment which can differ; update the logic to look up the corresponding CSV row for each $name (e.g., find the row in $rows where the printer identifier/share or a dedicated column matches $name) and use that row's Server value when building the UNC (use the server from the matched row rather than $rows[0].Server); also make the matching against $targets robust by comparing the actual share identifier used in the CSV (or full UNC) instead of only the UNC.Split('\')[-1] value so the decision to prune is accurate.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/Publish-EL082-Pack-Sandbox.ps1 around lines 153 - 159, The schtasks invocations currently pipe output to Out-Null and ignore exit codes, so failures still set $row.MapTask = $true; instead capture the exit code and/or output from the two commands that build $tr and call cmd /c "schtasks /Create ..." and cmd /c "schtasks /Run ...", check each result for non-zero exit status (or error text), log or throw an error on failure, and only set $row.MapTask = $true when both commands succeed; reference the variables $tr and $remoteMap and the existing cmd /c "schtasks /Create ..." and cmd /c "schtasks /Run ..." invocations to locate where to add the checks and logging.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/Publish-EL082-Pack.ps1 around lines 57 - 68, The Test-Path call in function _CopyIfChanged is inconsistent: it uses Test-Path $dst without -LiteralPath while Copy-Item and Get-FileHash use -LiteralPath; update the Test-Path invocation inside _CopyIfChanged to use Test-Path -LiteralPath $dst so wildcard characters in paths are treated literally and behavior matches Copy-Item/Get-FileHash, leaving the rest of the function (Get-FileHash, Copy-Item, and the catch path) unchanged.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/Publish-EL082-Pack.ps1 at line 96, Replace the Test-Path call that checks $pd to use the -LiteralPath switch (i.e., change Test-Path $pd to Test-Path -LiteralPath $pd) and likewise update the other Test-Path usage later in the file; also update New-Item to use -LiteralPath $pd (instead of -Path) to ensure UNC paths and literal wildcard characters are handled correctly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/Publish-EL082-Pack.ps1 around lines 116 - 117, The schtasks invocations for creating and running EL082_MapAll are vulnerable and lack error handling; update the code to call schtasks.exe directly (not via cmd /c), validate/sanitize the target computer name variable $c (reject or escape unsafe characters), capture and check the Create command's result/output (the Process/ExitCode or returned output) before attempting to Run, and log or handle failures (including the Create error) instead of discarding output with Out-Null; reference the existing use of $c, $tr, the /Create /TN EL082_MapAll call and the subsequent /Run /TN EL082_MapAll when adding these checks and validations.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/Run-EL082-Sandbox.ps1 at line 10, Replace the relative invocation ".\Publish-EL082-Pack-Sandbox.ps1" in Run-EL082-Sandbox.ps1 with a path rooted to the script's location so it always runs from the script directory (use the $PSScriptRoot variable when constructing the path to Publish-EL082-Pack-Sandbox.ps1 to match the other calls that use $PSScriptRoot).

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/jackson heights/Set-EL082-Default-FromCSV.vbs around lines 22 - 24, The line uses Split(line, ",") which fails for quoted fields with commas; replace this with a robust CSV parsing routine (e.g., implement a ParseCSVLine function that scans the string and splits on commas only when not inside double-quotes, unescaping paired quotes) and call parts = ParseCSVLine(line) instead of Split(...), then keep the existing assignments to h and s (h = UCase(Trim(parts(0))) and s = Trim(parts(1))) so quoted values and embedded commas are handled correctly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/map_via_IP_UNC_Path.vbs around lines 11 - 17, The AddWindowsPrinterConnection call (objNetwork.AddWindowsPrinterConnection, objPrinterPath) can hang if the target is unreachable—before calling it, perform a quick connectivity check (e.g., ping the printer IP with objShell.Run or WshShell.Run using a short timeout) and only proceed if reachable; if the ping fails or times out, skip the AddWindowsPrinterConnection call and show a clear objShell.Popup error including Err.Number and Err.Description (or a custom timeout message). Implement a maximum wait (e.g., try ping 1–2 times with a small -w timeout) and bail out to avoid blocking, so Replace the direct AddWindowsPrinterConnection call with: connectivity check -> conditional AddWindowsPrinterConnection -> handle Err.Number/Err.Description or show timeout popup.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/map_via_IP_UNC_Path.vbs around lines 14 - 16, Replace the Unicode emoji in the objShell.Popup calls with plain ASCII text to avoid rendering issues; update the two Popup invocations that reference objPrinterPath and Err.Description (the failure case using Err.Description and the success case) to use standard markers like "[ERROR]" and "[OK]" or explicit words ("Mapping failed", "Mapping succeeded") so messages remain legible across Windows versions and locales.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/printer_mapping_quick_checks.ps1 around lines 8 - 9, Replace the plaintext credential example in the Deploy-AllPrinters.ps1 invocation with guidance to use secure credential mechanisms: remove the -AltUser 'YOURDOMAIN\YourAdmin' and -AltPass 'Secret' example and instead instruct callers to use Get-Credential or secure prompting (e.g., Read-Host -AsSecureString) or a system credential store; update the comment line and any README examples to reference using Get-Credential and secure storage rather than embedding secrets, and ensure references to the -AltUser and -AltPass parameters indicate they accept PSCredential or secure strings rather than plain text.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/remote_printer-map_startup.ps1 around lines 1 - 3, Update the startup instructions to avoid using an insecure execution policy: change the guidance that currently tells users to run Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass to recommend Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned, and keep the note about running in an elevated PowerShell; update any related comments in remote_printer-map_startup.ps1 so the instruction reflects RemoteSigned instead of Bypass.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/remote_printer-map_startup.ps1 at line 7, The script sets $File (".\Map-EL082-All.vbs") but never verifies it exists before Copy-Item; add a pre-check using Test-Path on the $File variable and if it does not exist, write an error via your logging function or Write-Error and stop further copy attempts (exit or return) so the Copy-Item calls that reference $File are not executed against missing source files; update any loop or function that calls Copy-Item to assume $File is valid after this early guard.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/remote_printer-map_startup.ps1 around lines 8 - 11, Add error handling around the Copy-Item call so failures against each host in $Hosts are detected and reported: for each iteration that computes $startup, call Copy-Item with -ErrorAction Stop and wrap it in a try/catch; on success write a success message (including the host $h and target $startup) and on failure write an error message (including $h, $startup and the caught exception) and optionally append results to a log file for later review. Ensure you reference the existing loop variables ($Hosts, $h, $startup) and the Copy-Item invocation (and the catch exception variable) so all failures are clearly reported per-host.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/remote_printer-map_startup.ps1 around lines 8 - 11, The loop that copies $File to each remote user's Startup folder (variables $Hosts, $startup and the Copy-Item call) is security-sensitive and needs user validation and confirmation: add pre-checks (e.g., verify each host is reachable and the target path exists using Test-Connection/Test-Path) and present a clear interactive confirmation (prompt via Read-Host or Confirm switch) listing affected hosts before performing the Copy-Item; also implement an option to run in a dry-run mode (use -WhatIf or simulate) and bail out if the user declines.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/remote_printer-map_startup_fixed.ps1 around lines 15 - 16, The Copy-Item call currently uses -ErrorAction Stop which will abort the whole script on the first failure; modify the block around Copy-Item ($File -> $startup) to use a try-catch: perform Copy-Item -ErrorAction Stop inside try, keep the success log Write-Host "OK -> $h" in the try on success, and in the catch log the error (including $h and $_.Exception.Message or $_) with Write-Error or Write-Host so the script continues to the next host; ensure the catch does not rethrow so remaining hosts are processed.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/remote_printer-map_startup_fixed.ps1 at line 4, The script sets $File = Join-Path $PSScriptRoot 'Map-EL082-All.vbs' but never validates that $PSScriptRoot or the target file exists before using Copy-Item; add an early guard before any iteration/Copy-Item that checks $PSScriptRoot is non-empty and Test-Path $File returns true, and if not, emit a clear error (Write-Error or throw) and exit/return so subsequent Copy-Item calls don't fail with confusing errors; reference the $File variable, $PSScriptRoot and the Map-EL082-All.vbs filename when building the error message.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST051/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 67 - 81, The catch block after the pruning try currently swallows all exceptions; update the catch to capture the exception (use the automatic $_ or $PSItem variable) and log a helpful message including context (e.g., the $PrunePrefix, which printer name or $server, and the exception message) via Write-Error or Write-EventLog, and then either rethrow or exit with a non-zero status if appropriate; locate the try/catch surrounding the Get-Printer -> $installed loop and replace the empty catch with this logging/propagation logic so failures in Get-Printer, Start-Process, or any other step aren't silently ignored.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST051/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 76 - 77, The pruning step incorrectly uses $rows[0].Server for every printer, causing deletions on the wrong server; update the logic in the block that calls Start-Process (the line using $server, $rows, $name and Start-Process cmd.exe "/c rundll32 printui.dll,PrintUIEntry ...") to determine the correct server for the current $name instead of $rows[0].Server—either by building a server-to-printer mapping when parsing CSV or by finding the matching row (e.g., where .Name -eq $name) and using that row's .Server value before invoking Start-Process. Ensure the chosen lookup handles duplicate names and multi-server CSVs.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST051/C$/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/Set-EL082-Default-FromCSV.vbs around lines 19 - 30, The loop currently uses Split(line, ",") which fails on quoted fields/commas and also may leak the file handle since ts.Close is not guaranteed on error; replace the inline Split usage with a proper CSV parser function (e.g., ParseCSVLine or ParseCsvFields) that handles quoted fields and embedded commas and use its returned array instead of parts, keep existing logic with UCase/Trim on elements (host, wantShare, s), and wrap the reading loop in error-handling/finalization so ts.Close is always called (for example implement an error handler or a Try/Finally-style pattern in VBScript that ensures ts.Close runs even if ParseCSVLine or ts.ReadLine throws).

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST051/EL082_MapAll_Task.txt at line 3, The scheduled task command uses the /Z flag which causes EL082_MapAll to auto-delete after run; remove the /Z flag from the schtasks invocation (the line containing EL082_MapAll and the TR calling Map-EL082-MachineWide.ps1) during testing so the task persists for post-mortem, or if you must keep /Z add explicit logging/output capture inside Map-EL082-MachineWide.ps1 (or write logs to a stable location before exit) and add a comment documenting the auto-delete behavior for future maintainers.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST051/EL082_MapAll_Task.txt at line 3, The scheduled task command uses high-risk options (schtasks with /RU SYSTEM, /RL HIGHEST and PowerShell -ExecutionPolicy Bypass for "Map-EL082-MachineWide.ps1"); change to run with least privilege required (avoid /RU SYSTEM and /RL HIGHEST unless absolutely necessary), remove or replace -ExecutionPolicy Bypass by enforcing signed scripts or an appropriate Group Policy execution policy, ensure Map-EL082-MachineWide.ps1 is code-reviewed and digitally signed, and restrict task scope/permissions (limit machine accounts or set a dedicated service account) before promoting to production.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST051/EL082_MapAll_Task.txt at line 3, The schtasks command's /TR parameter contains nested unescaped double quotes causing parsing errors; fix the /TR value in the line that builds the scheduled task (the schtasks /Create command) by escaping the inner quotes or by removing/alternating them (e.g., use single quotes for the PowerShell -File argument or omit inner quotes around C:\ProgramData\EL082\Map-EL082-MachineWide.ps1) so the entire /TR string is a correctly quoted single argument to schtasks.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST055/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 at line 81, The empty catch block silently swallows errors; update the catch {} that follows the prune operation to log the failure instead of ignoring it — call a PowerShell logging method (e.g., Write-Error or Write-Warning) inside the catch and include the exception details (use $_ or $_.Exception/$_ | Out-String) so the message contains "Prune failed" and the actual error text; ensure the catch still returns/continues as intended after logging.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST055/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 73 - 77, The prune logic uses $rows[0].Server and builds an invalid UNC with extra backslashes; fix by identifying the correct row for each printer (match by both share name and server instead of only comparing $unc.Split('\')[-1] to $name), obtain the Server from that matched row (not $rows[0]) and construct the UNC as "\\$server\$name" using PowerShell string escaping or Join-Path-like concatenation so you get exactly two leading backslashes; update the block that sets $match, $server and the Start-Process call (references: $unc, $name, $rows, $server, Start-Process cmd.exe "/c rundll32 printui.dll,PrintUIEntry /gd /q /n ...") to use the matched row's Server and the corrected UNC format.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST055/C$/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/Set-EL082-Default-FromCSV.vbs around lines 16 - 18, The code opens the CSV with Set ts = fso.OpenTextFile(csv, 1) without error handling; wrap the OpenTextFile call with VBScript error handling (e.g., use On Error Resume Next before Set ts and On Error GoTo 0 after) then check Err.Number and whether ts was set (ts is Nothing) before proceeding; if an error occurred or ts is Nothing, log or silently exit consistent with the script’s pattern (same behavior as when file not found) so subsequent calls (ts.AtEndOfStream, ts.ReadLine) are never invoked on a failed open.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST057/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 66 - 81, The prune loop is using $rows[0].Server and comparing printer display names to UNC tails, and it swallows all errors; change it so each $name is matched against the actual UNC/share tail from the $targets list (not the display Name) to find the corresponding row and use that row's Server when building the UNC for Start-Process, skip and log if no matching UNC is found, and replace the empty catch {} with a catch that writes an error (or rethrows) so failures are visible; reference symbols: $PrunePrefix, $installed, $targets, $rows, $name, $server, Start-Process cmd.exe.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST057/C$/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/Set-EL082-Default-FromCSV.vbs around lines 16 - 30, The CSV splitting using Split(line, ",") in this script (see the loop reading ts, the Split(line, ",") call and the wantShare/parts logic) is brittle and must be replaced with a CSV-aware parser: implement a simple CSV field extractor that respects quoted fields and escaped quotes (or use a library if available), trim whitespace from unquoted fields, validate the number of columns before using parts(0)/parts(1), and log or skip malformed lines instead of silently returning incorrect values; ensure the code that sets h = UCase(Trim(parts(0))) and s = Trim(parts(1)) only runs after successful parse/validation so wildcard fallback (h = "*" and wantShare = "") still works reliably.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST057/C$/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/Set-EL082-Default-FromCSV.vbs around lines 9 - 11, The registry write is wrapped with "On Error Resume Next" then "On Error GoTo 0" so any failure of sh.RegWrite is swallowed; update the block around sh.RegWrite to check Err.Number after the call and emit a diagnostic (e.g., via WScript.Echo or WshShell.LogEvent) including Err.Number and Err.Description, and handle the failure (exit non‑zero or raise) instead of continuing silently; specifically locate the sh.RegWrite call and the surrounding On Error Resume Next / On Error GoTo 0 and add the Err check+logging and appropriate exit/raise behavior.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST057/C$/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/Set-EL082-Default-FromCSV.vbs around lines 32 - 36, Validate the target printer/share before attempting to set it and check the result of the SetDefaultPrinter call: build the display name from wantShare and svr (variables wantShare and svr), query available printers via the network/printer object (or enumerate net.EnumPrinterConnections if available) to confirm the display exists and is reachable, then call net.SetDefaultPrinter display without swallowing errors (remove global On Error Resume Next) or catch the error and inspect Err.Number/Err.Description immediately after the call to determine success; log or WScript.Echo a clear success or failure message including the display name and any error details so callers get actionable feedback.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST057/EL082_MapAll_Task.txt around lines 1 - 6, Document that the simulated schtasks command (symbols: schtasks, /RU SYSTEM, /RL HIGHEST, -ExecutionPolicy Bypass, and the target path C:\ProgramData\EL082\Map-EL082-MachineWide.ps1) presents a dangerous privilege escalation pattern; update the sandbox file to include an explicit security warning about running as SYSTEM with HIGHEST rights and using ExecutionPolicy Bypass, require verification steps that the directory ACLs restrict write access to administrators only, recommend using a least-privilege service account and safer PowerShell policies (RemoteSigned/AllSigned) instead of Bypass, and add a short checklist to confirm whether this archived template is still referenced and that the target script path has appropriate file permissions.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST058/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 at line 81, The empty catch {} in Map-EL082-MachineWide.ps1 silently swallows prune errors—replace the empty catch with a handler that logs the exception details (use $_ / $_.Exception.Message and $_.Exception.StackTrace for full context) and include a clear message like "Prune failed" so failures are visible; optionally rethrow or return a non-zero exit code after logging if the calling flow must know the operation failed.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST058/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 70 - 79, The prune loop incorrectly always uses $rows[0].Server and assumes installed $name equals the share name; build a lookup map from each CSV row ($rows) mapping both the share name (last element of Path) and the full UNC ("\\<Server>\<Share>") to its Server, then in the foreach ($name in $installed) check against both forms (share-only and full-UNC) by looking up the server in that map (instead of $rows[0].Server), and pass the resolved server when constructing the UNC for Start-Process (Start-Process cmd.exe ... "\\$server\$name"), so deletions target the correct server for multi-server scenarios.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST058/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 62 - 64, The current Start-Process invocation interpolates $unc into a cmd.exe string which allows shell interpretation and possible command injection; change it to call rundll32 directly via Start-Process with FilePath 'rundll32' and a safe ArgumentList (pass 'printui.dll,PrintUIEntry', '/ga', '/q', '/n', and the $unc value as a separate argument) so PowerShell will not invoke cmd.exe or perform shell parsing of $unc; update the foreach block that references $unc and Start-Process to use this direct invocation pattern and ensure $unc is used as a single argument element.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST058/C$/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/Set-EL082-Default-FromCSV.vbs around lines 9 - 11, The RegWrite to "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows\LegacyDefaultPrinterMode" can fail silently; after the RegWrite call (the line containing sh.RegWrite) check Err.Number and, if non-zero, log the error (via WScript.Echo or event/logging routine used in this script), optionally include Err.Description and Err.Number, clear or handle the error, and exit or set a failure flag before continuing to the SetDefaultPrinter logic so you don't proceed when the required registry change failed.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST058/C$/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/Set-EL082-Default-FromCSV.vbs around lines 16 - 18, Wrap the fso.OpenTextFile call in VBScript error handling: add On Error Resume Next before Set ts = fso.OpenTextFile(csv, 1), check Err.Number (or whether ts is Nothing) immediately after and handle the failure (log a descriptive error including Err.Description and exit the script or skip processing), then clear error with On Error GoTo 0; also ensure any opened ts is closed (ts.Close) in the normal and error paths and reference the variables ts, fso, csv, AtEndOfStream and ReadLine when making these checks.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST058/C$/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/Set-EL082-Default-FromCSV.vbs around lines 34 - 36, The script currently silences errors around net.SetDefaultPrinter by using On Error Resume Next; change this to detect and log failures: keep On Error Resume Next around the net.SetDefaultPrinter call but immediately after check Err.Number (and Err.Description) and, if non-zero, write a clear message including Err.Number/Err.Description and the attempted printer name using a logging mechanism (e.g., WScript.Echo and/or WScript.CreateObject("WScript.Shell").LogEvent) and then clear Err and restore normal error handling with On Error GoTo 0; reference the net.SetDefaultPrinter call, the surrounding On Error Resume Next / On Error GoTo 0, and Err.Number/Err.Description to implement the check-and-log.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST058/EL082_MapAll_Task.txt around lines 3 - 6, Add a short security note to the EL082_MapAll task documentation that calls out the risky parameters used in the schtasks lines (the scheduled task name EL082_MapAll, the script Map-EL082-MachineWide.ps1 and the flags -ExecutionPolicy Bypass, /RU SYSTEM, /RL HIGHEST), explain the risks of bypassing execution policy and running as SYSTEM, provide a justification for why these privileges are required in this sandbox use-case, and add guidance on safer alternatives or warnings that these settings are not recommended for production deployments.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST061/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 71 - 74, The current foreach loop that sets $match by comparing $unc.Split('\')[-1] to $name is fragile because it only compares the UNC share suffix; instead retrieve the full connection path from the printer object and compare that to entries in $targets (or normalize both sides) — update the loop that iterates $targets/$unc to obtain each printer's full connection string (from the printer object property used in this script, e.g., the Win32_Printer/Get-Printer connection or ShareName/PortName fields) and compare the full path rather than only the split(-1) name so that $match correctly reflects printers whose display name differs from the share name.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST061/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 at line 81, The empty catch block in Map-EL082-MachineWide.ps1 silently swallows errors (the lone "catch {}"); replace it with error reporting that logs the exception and context instead of doing nothing — capture the automatic error variable ($_ or $PSItem) and call Write-Warning or Write-Error (or append to an error log) with a clear message like "prune operation failed" plus the exception message and stack trace; ensure this change is applied where the prune-related try/catch is implemented so failures are visible for debugging.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST061/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 76 - 77, The prune code currently uses $rows[0].Server which hardcodes the first CSV row's server for all deletions; update the logic so each prune uses the server tied to the specific printer row (e.g., use the current loop variable's Server property instead of $rows[0].Server or parse the server from the printer UNC for that row), and pass that derived server into the Start-Process rundll32 PrintUIEntry call that currently builds the UNC with $name; ensure the change is applied to the block containing $server, $rows and the Start-Process invocation so each row targets its own server rather than the first CSV entry.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST061/C$/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/Set-EL082-Default-FromCSV.vbs around lines 33 - 36, The script builds the printer name as "ShareName on ServerName" (variable display) but WScript.Network.SetDefaultPrinter expects the actual printer name/UNC path; change the display construction to the UNC form (e.g., "\\" & svr & "\" & wantShare) before calling net.SetDefaultPrinter, and after net.SetDefaultPrinter check Err.Number (or clear/suppress errors appropriately) so failures are not silently ignored; update references to display, wantShare, svr, and net.SetDefaultPrinter accordingly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST061/EL082_MapAll_Task.txt around lines 1 - 6, Confirm and document that the privileged pattern in EL082_MapAll_Task.txt (the schtasks invocation with /RU SYSTEM, /RL HIGHEST and the PowerShell flag -ExecutionPolicy Bypass) is strictly sandbox-only and never used in production; update the file comments to state that explicitly, reference the script name Map-EL082-MachineWide.ps1 and add a note that it has completed a security review (or link to the review/approval ticket), and change the simulated command guidance to include safer defaults (remove/avoid -ExecutionPolicy Bypass and avoid /RU SYSTEM+/RL HIGHEST) or add a clear guard (e.g., a prominent WARNING and a config flag that prevents copying this exact command into production) so reviewers cannot accidentally reuse the high-privilege pattern.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST063/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 at line 83, The Start-Process invocation currently runs "net stop spooler & net start spooler" which will always run the start regardless of stop success; update the command to ensure start only runs if stop succeeds by replacing the inline "&" with conditional execution (use "&&") or, better, call the PowerShell service cmdlet Restart-Service -Name Spooler -Force (or explicitly Stop-Service/Start-Service with status checks) so the Spooler restart logic in the Start-Process invocation handles failures correctly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST063/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 66 - 81, The prune block incorrectly assumes one server and uses fragile matching/escaping and a silent catch; fix by building a lookup from the input CSV rows ($rows/$targets) mapping the share name or PortName to its server and full UNC, normalize installed names ($installed) by removing $PrunePrefix (or normalize the CSV share name) and use that normalized key to find the corresponding row instead of comparing raw $unc.Split('\')[-1] to $name, then call Start-Process with a properly quoted ArgumentList (e.g. pass cmd.exe and the "/c", "rundll32 printui.dll,PrintUIEntry /gd /q /n \"\\\\$server\\$share\"" parts as separate arguments to avoid backtick escapes) using the server/share from the lookup, and replace the empty catch {} with a catch that logs the error (Write-Error or processLogger.Error) and continues so failures are visible.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST063/C$/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/Set-EL082-Default-FromCSV.vbs around lines 16 - 30, The CSV parsing uses Split(line, ",") which fails for quoted fields with commas and the OpenTextFile(csv, 1) call has no error handling; update the logic around OpenTextFile to trap file-open errors (use On Error Resume Next / Err handling, check Err.Number, and fail gracefully) when creating ts, and replace the naive Split(line, ",") parsing with a simple quoted-field-aware parser (e.g., iterate characters building fields, respect quotes and escaped quotes) so that parts, h, s and the host match logic (UCase(Trim(parts(0))) / Trim(parts(1))) still work correctly and wantShare selection remains unchanged.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST063/EL082_MapAll_Task.txt around lines 1 - 4, Update the sandbox task documentation to include a security justification for the privileged execution choices: explicitly state the business need for running the scheduled task as SYSTEM and with /RL HIGHEST for the EL082_MapAll job, explain why -ExecutionPolicy Bypass is required for running Map-EL082-MachineWide.ps1 (or, if unnecessary, require signing instead), describe the controls that prevent modification of the target script (file integrity, ACLs, deployment process, monitoring), and note the audit/compliance implications of using the /Z auto-delete flag and whether it should be changed or compensated by logging/retention controls; reference the schtasks command, EL082_MapAll task name, Map-EL082-MachineWide.ps1, SYSTEM, /RL HIGHEST, -ExecutionPolicy Bypass, and /Z when adding these justifications.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST066/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 67 - 81, The empty catch block after the pruning try-block silently swallows errors; modify the catch in the block containing PrunePrefix logic (around Get-Printer, the foreach over $installed, and Start-Process cmd.exe invocation) to log or write the exception details instead of ignoring them — for example capture the automatic $_ or $error[0] and emit a descriptive message using Write-Error or Write-EventLog (including context like $PrunePrefix and $server/$name) so failures during the pruning loop are visible for debugging.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST066/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 70 - 79, The loop that prunes printers uses a single server value ($rows[0].Server) and a broken escaped UNC string when calling Start-Process, which can target the wrong server and produce an invalid path; update the logic so you resolve the correct server for each $name (e.g. look up the matching row in $rows or call Get-Printer -Name $name to get the printer’s ComputerName/port) and construct the UNC using proper string interpolation for each printer (use "\\$($printerServer)\$name" or equivalent) before passing it to Start-Process (refer to the foreach over $installed, the $rows collection, $name, and the Start-Process invocation).

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST066/C$/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/Set-EL082-Default-FromCSV.vbs around lines 16 - 18, Wrap the fso.OpenTextFile(csv, 1) call in VBScript error handling: use On Error Resume Next before calling OpenTextFile, attempt to set ts, then check Err.Number (and that ts is not Nothing) and handle the failure (log/exit/skip) before proceeding to read the header; clear the error (Err.Clear) and restore normal error handling with On Error GoTo 0 afterwards. This will protect the OpenTextFile call (referenced by fso.OpenTextFile and variable ts) from race conditions or access/permission errors when opening csv.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST066/EL082_MapAll_Task.txt at line 3, Review the scheduled task definition for EL082_MapAll (schtasks /Create ... /TN EL082_MapAll) which currently runs as SYSTEM (/RU SYSTEM), with highest privileges (/RL HIGHEST) and launches PowerShell with -ExecutionPolicy Bypass; confirm each high-privilege setting is strictly required for the Map-EL082-MachineWide.ps1 workload, document the security justification for running as SYSTEM, the need for HIGHEST run level, and why bypassing the PowerShell execution policy is necessary, and if any of these can be reduced (e.g., use a least-privileged service account, drop HIGHEST, remove Bypass) update the task configuration accordingly and add the justification notes to the change log or security documentation.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST066/EL082_MapAll_Task.txt at line 3, The /TR parameter contains nested unescaped double quotes around the PowerShell -File path causing a syntax error; update the scheduled task creation string (EL082_MapAll /TR) to avoid nested double quotes—e.g., keep the outer double quotes for /TR but change the inner file path quotes to single quotes or otherwise escape them so the command becomes: /TR "powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\ProgramData\EL082\Map-EL082-MachineWide.ps1'"; ensure you update the EL082_MapAll command string that references Map-EL082-MachineWide.ps1 accordingly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST067/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 at line 81, The empty catch block "catch {}" in Map-EL082-MachineWide.ps1 silently swallows any errors from Get-Printer or the pruning logic; replace that empty catch with error logging that surfaces the exception and context (e.g., use Write-Warning or Write-Error) and include the caught exception ($_) and a short message like "Prune printers failed" so failures are recorded and can be diagnosed; ensure the catch still does not rethrow if you want to continue but always log the error and which operation (Get-Printer/prune) failed.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST067/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 62 - 64, The Start-Process call inside the foreach over $targets currently launches cmd.exe to run rundll32 but ignores the utility's exit code; modify the loop so you call Start-Process with -PassThru and -Wait (e.g., capture the returned process object), then inspect its ExitCode after it finishes and handle non-zero results (log/report/throw) for the specific $unc entry; alternatively invoke cmd.exe and after Start-Process completes read $LASTEXITCODE or use Start-Process with -NoNewWindow -PassThru and check the returned process's ExitCode to surface failures when adding the printer for $unc.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST067/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 around lines 70 - 79, The prune loop assumes every printer lives on the same server by using $rows[0].Server; change it to find the specific CSV row for each $name (e.g., $row = $rows | Where-Object { $_.Name -eq $name }) and use that row's Server field when building the UNC for Start-Process, or if the installed printer Name already contains the full UNC, use that directly instead of reconstructing it; update the code paths that reference $rows[0].Server and $name so the UNC is constructed from the matched row's Server and Name (or from the preserved UNC) before calling Start-Process.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST067/C$/ProgramData/EL082/Map-EL082-MachineWide.ps1 at line 12, The Simulate branch currently ignores the -PrintersCsv parameter; update the logic that sets $CsvPath so when $Simulate is true it first checks whether $PrintersCsv has been supplied/has a value and uses that, otherwise falls back to constructing the path from $RemoteRoot; modify the expression that assigns $CsvPath (referencing $CsvPath, $Simulate, $PrintersCsv, and $RemoteRoot) to prefer a provided $PrintersCsv in simulate mode.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Archive/sandbox/WEL082MST067/C$/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/Set-EL082-Default-FromCSV.vbs around lines 16 - 30, The current parsing using Split(line, ",") in the loop that sets wantShare (variables/functions: Split, parts, h, s, wantShare, host, csv, ts) fails for quoted fields containing commas; replace the naive Split with a robust CSV field extractor (or switch to a delimiter guaranteed not to appear, e.g., tab) that correctly handles quoted fields and escaped quotes before assigning h and s, and keep existing logic (compare UCase(Trim(parts(0))) to host and handle "*" wildcard). Also add a simple logging/stderr write when the loop finishes with wantShare still empty so the startup script surfaces missing matches instead of silently exiting.

- Verify each finding against the current code and only fix it if needed.

In @mapping/CHANGELOG.md at line 1, The file begins with a UTF-8 BOM character before the header ("﻿# CHANGELOG"); remove the BOM so the file starts directly with the '#' header, then re-save the file as UTF-8 without BOM (e.g., via your editor's "UTF-8" encoding or using a no-BOM write like `:set nobomb` in vim), and verify the first bytes now are the ASCII '#' (no hidden BOM) to avoid parser/version-control issues.

- Verify each finding against the current code and only fix it if needed.

In @mapping/CHANGELOG.md at line 3, Replace the corrupted encoding sequence "ΓÇö" in the changelog header string "## v0.1.1-annotated ΓÇö 2025-09-29 19:44:36" with a proper ASCII-safe character (preferably a hyphen "-") or a correct em dash "—" to fix encoding/readability; update the header line in mapping/CHANGELOG.md (the "## v0.1.1-annotated ..." header) so it reads either "## v0.1.1-annotated - 2025-09-29 19:44:36" or "## v0.1.1-annotated — 2025-09-29 19:44:36" and ensure the file is saved with UTF-8 encoding.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Config/hosts.txt at line 164, The file ends without a trailing newline (contains the final token "WLS111WCC164" with no EOL); update the hosts.txt file so the last line ("WLS111WCC164") is terminated with a newline character by adding a trailing newline at end-of-file to comply with POSIX text file conventions.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Config/hosts.txt at line 1, The first line of mapping/Config/hosts.txt contains corrupted BOM characters (﻿∩╗┐) prefixed to the hostname string "WLS111WCC001"; remove the BOM so the line reads exactly "WLS111WCC001" and resave the file as UTF-8 without BOM (or use an editor/utility to strip the BOM) to prevent parsing the hostname with hidden characters.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Config/hosts_smoke.txt at line 1, The file begins with a UTF-8 BOM character immediately before the hostname token "WLS111WCC091", which makes the first string start with an invisible character; remove the leading BOM so the line begins exactly with WLS111WCC091 and re-save the file as UTF-8 without BOM (use your editor's "Save without BOM" or run a tool to strip the U+FEFF marker) to ensure parsers and scripts read the hostname correctly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Config/runs/breast_checkin.txt at line 1, The file starts with a BOM (U+FEFF) before the identifier "WLS111WCC031", which can break parsers; remove the leading BOM so the file begins exactly with the identifier "WLS111WCC031" (e.g., open the file in an editor and re-save as "UTF-8 without BOM" or strip the BOM programmatically) and verify the first character is 'W' not U+FEFF.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Config/runs/breast_checkout.txt at line 1, The file starts with a UTF-8 BOM before the identifier WLS111WCC024 causing the first token to be "﻿WLS111WCC024"; remove the BOM so the file begins with the ASCII 'W' and save the file as UTF-8 without BOM (use your editor's "UTF-8 without BOM" or "Save without BOM" option) so the entry reads exactly WLS111WCC024.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Config/runs/breast_checkout.txt at line 3, The file ends with the single entry "WLS111WCC026" but lacks a trailing newline; open mapping/Config/runs/breast_checkout.txt and add a newline character after the final entry (ensure the file ends with "\n") so the last line "WLS111WCC026" is properly terminated per POSIX text-file conventions.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Config/runs/obgyn_checkin.txt at line 5, The file ends with the identifier "WLS111WCC083" but lacks a trailing newline; update the file containing "WLS111WCC083" to terminate the file with a single newline character so the last line ends with '\n' (i.e., add an empty line after "WLS111WCC083").

- Verify each finding against the current code and only fix it if needed.

In @mapping/Config/runs/obgyn_checkin.txt at line 1, The first line contains a leading UTF-8 BOM character before the identifier WLS111WCC079 which can break parsers; open the file and remove the invisible BOM character so the line begins exactly with WLS111WCC079 (or re-save the file as "UTF-8 without BOM") and re-run validation to ensure the identifier is recognized.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Config/runs/obgyn_checkout.txt at line 1, Remove the UTF-8 BOM from the start of the file so the identifier "WLS111WCC091" is the first character sequence; open the file containing the line that begins with "WLS111WCC091", re-save it as UTF-8 without BOM (e.g., Editor: Save with Encoding → UTF-8 / Encode in UTF-8 without BOM) or delete the leading \uFEFF character so string comparisons and lookups see "WLS111WCC091" exactly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Config/runs/obgyn_checkout.txt at line 4, The file ends with the line "WLS111WCC094" but is missing a trailing newline; update the file so that the final line is terminated with a single newline character (i.e., ensure there's an empty line break after "WLS111WCC094") to satisfy POSIX/Unix conventions and avoid VCS/tool warnings.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/Enforce-SingleHost.ps1 around lines 1 - 7, The header comment in Enforce-Mapping-SingleHost.ps1 contains a corrupted arrow sequence ("ΓåÆ") caused by incorrect file encoding; open the file in an editor that supports encoding selection and re-save it using UTF-8 (with BOM if your Windows tools expect it) or convert the file encoding to UTF-8 and replace the corrupted sequence with the correct character ("→") in the header comment, ensuring the file retains consistent UTF-8 encoding for all comments and metadata.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/Enforce-SingleHost.ps1 at line 88, The Copy-Item call using the glob '*.*' will skip extensionless files; update the Copy-Item invocation that references (Join-Path $latest.FullName '*.*') and $hostOut to use a pattern that includes files without extensions (for example '*' instead of '*.*') or otherwise explicitly include extensionless artifacts so all expected files are copied; keep the existing -Force and -ErrorAction SilentlyContinue behavior intact.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/Enforce-SingleHost.ps1 around lines 40 - 51, The here-string contains unescaped PowerShell variables that are being evaluated at controller time; update the here-string so all runner-time variables are escaped with backticks (e.g. escape $_.Name inside the Where-Object, escape $null assignment to `$null, and escape $src, $PSScriptRoot, and $outRoot wherever they appear) so Get-Printer | Where-Object { `$_.Name -eq 'LS111-WCC65' } sets `$present correctly and the `$src path (Join-Path `$PSScriptRoot 'Map-Remote-MachineWide-Printers.ps1') remains intact for the runner to find the worker script. Ensure every $ that should be preserved for the remote runner is prefixed with a backtick in the here-string, including uses in Start-Process arguments and the powershell.exe invocation.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/Enforce-SingleHost.ps1 around lines 59 - 69, The schtasks invocations currently store output in $create and $run but do not check success and use a US-only date format; update to run schtasks via Start-Process (or otherwise capture the process ExitCode) for both the create and run steps (referencing $create, $run, $taskName, $shareName, $tr) and immediately check ExitCode: on non-zero log the captured stdout/stderr and fail/exit with clear messages; also change $stDate generation from $when.ToString('MM/dd/yyyy') to a locale-independent ISO format like $when.ToString('yyyy-MM-dd') (keep $stTime from $when.ToString('HH:mm')) so schtasks receives a consistent date format.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/Map-Run-Controller.ps1 around lines 91 - 96, The current use of Register-EngineEvent with the source identifier Console_CancelKeyPress is invalid and never fires; replace it by registering the .NET Console CancelKeyPress event (use Register-ObjectEvent against [Console]::CancelKeyPress) and in the event action set $Event.SourceEventArgs.Cancel = $true, set $script:StopRequested = $true, and append the same message to $ControllerLog and Write-Host so the script performs a graceful shutdown after the current host; update references to Register-EngineEvent and Console_CancelKeyPress in the file accordingly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/Map-Run-Controller.ps1 around lines 98 - 102, The Join-AdminShare function is suffering from operator precedence: the trailing -replace is applied to the formatted UNC string and strips the leading "\\"; wrap the entire second argument to -f so both -replace operations run on $SubPath before formatting. Update Join-AdminShare to apply ($SubPath -replace '^[cC]:\\', '') -replace '^[\\]+','' as a single parenthesized expression passed as the second argument to the -f operator so the formatted UNC path retains its leading backslashes.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/Map-Run-Controller.ps1 around lines 228 - 237, The loop increments $success even when Invoke-Host handled failures internally, so change Invoke-Host to return a boolean success value and update its early-return paths (the return statements inside Invoke-Host's folder creation/copy/error handling branches) to return $false on failure and $true on complete success; then modify the main loop that calls Invoke-Host (the foreach over $Computers) to capture the return value, increment $success only when Invoke-Host returns $true and $fail when it returns $false, and keep existing Write-Log calls for per-host fatal messages.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/Map-Run-Controller.ps1 around lines 145 - 162, The hardcoded US date format for $stDate breaks on non-US locales; replace the fixed 'MM/dd/yyyy' with a system-aware format by building $stDate from the current culture's short date pattern (e.g. $pattern = [System.Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.ShortDatePattern; $stDate = $when.ToString($pattern)) so the /SD parameter matches the host locale, or alternatively switch to using schtasks /XML with an XML task definition to avoid locale dependence entirely; update uses of $stDate and the /SD argument accordingly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/RPM-Recon.ps1 around lines 1 - 7, The file RPM-Recon.ps1 contains a corrupted UTF-8 BOM and mojibaked characters (e.g., the leading "﻿∩╗┐" and sequences like "ΓÇö" and "ΓåÆ"); open RPM-Recon.ps1 in a text editor that supports encoding selection and re-save it as UTF-8 (without inserting an incorrect BOM) or as UTF-8 with BOM if your environment expects one, replacing the garbled sequences with the correct Unicode characters (e.g., em dash —, arrows →) so all string literals and comments display properly; commit the re-encoded file so the repository stores the correct UTF-8 content.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/RPM-Recon.ps1 around lines 59 - 62, The timer's Elapsed handler uses PowerShell variables ($drain, $queue, $ctrlLog) on a .NET ThreadPool thread which is not runspace-safe and can cause concurrent Add-Content/file-write contention; change the implementation to marshal the callback back into the PowerShell runspace (e.g., replace System.Timers.Timer + add_Elapsed with Register-ObjectEvent on the Timer object or use a runspace-safe invocation) so the callback executes in the runspace before calling the drain function and Add-Content, ensuring only runspace-threaded access to $queue, $drain and $ctrlLog and avoiding concurrent file writes.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/RPM-Recon.ps1 around lines 202 - 204, The Copy-Item invocation using Join-Path $latest.FullName '*.*' will skip files without extensions; update that call to use '*' (i.e., change the Join-Path pattern from '*.*' to '*') so all files in $latest.FullName (including those without extensions) are copied to $hostOut; keep the existing -Force and -ErrorAction settings unchanged and verify the related Remove-Item/Get-ChildItem logic (Get-ChildItem -Path $latest.FullName -File and subsequent Remove-Item) still behaves as expected.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/RPM-Recon.ps1 around lines 173 - 175, The code currently hardcodes $stDate = $when.ToString('MM/dd/yyyy'), which is locale-dependent and will break schtasks on non-US systems; change it to use the system culture's short date pattern (e.g. $dateFmt = [System.Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.ShortDatePattern) and format $when with that pattern (use $when.ToString($dateFmt)) so $stDate is produced in the locale schtasks expects; keep $when and $stTime unchanged but reference $dateFmt when creating $stDate.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/RPM-Recon.ps1 around lines 216 - 221, The string interpolation uses invalid `${($sw.Elapsed)}` syntax; replace those occurrences in the EnqRun calls (both the SUMMARY line and the ERROR line in the catch block) with a valid PowerShell subexpression or direct property reference such as $($sw.Elapsed) or $sw.Elapsed (e.g., update the EnqRun invocations that reference $sw.Elapsed to use $($sw.Elapsed) instead of `${($sw.Elapsed)}` so the elapsed time is evaluated correctly).

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/RPM-Recon.ps1 around lines 70 - 117, The block that builds and enqueues scheduler commands is orphaned and references undefined symbols ($remoteRoot, $target, EnqRun, $schedTarget) outside the ForEach-Object -Parallel / try scope; remove this duplicate/out-of-scope section (the schtasks creation/query/run and remote logs check) or relocate it inside the existing parallel/try block where $remoteRoot, $target, EnqRun and $schedTarget are defined so there are no undefined references; specifically remove or move the code that defines $remoteWorker, $psArgs, $tr, $when/$stTime/$stDate, the Create/Run/Query schtasks calls, extraction of $actionLine/$lastRunRes, and the $remoteLogs Test-Path block.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/Run-WCC-Mapping.ps1 around lines 1 - 5, The file contains UTF-8 BOM and mis-encoded characters (e.g., "∩╗┐", "ΓåÆ", "ΓÇô") in the header comment; open Run-WCC-Mapping.ps1, remove the invalid sequences, restore the intended text in the file header (the "<# Run-WCC-Mapping.ps1" block and the referenced line ".\Map-Remote-MachineWide-Printers.v5Compat.ps1"), and re-save the file as UTF-8 (preferably UTF-8 without BOM) so the en-dashes and arrows render correctly and no mangled characters remain.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/Run-WCC-Mapping.ps1 at line 58, The output message in the Write-Host call contains a typo ("VERFIY"); update the string in the Write-Host invocation that prints "All groups processed. Review VERFIY outputs above for each host." to replace "VERFIY" with "VERIFY" so the message reads "All groups processed. Review VERIFY outputs above for each host."

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/Run-WCC-Mapping.ps1 at line 8, The script hardcodes a user-specific absolute path in the Set-Location call in Run-WCC-Mapping.ps1 which breaks portability; replace the literal "C:\Users\..." with a script-relative path using $PSScriptRoot (or Join-Path/Resolve-Path with $PSScriptRoot) so Set-Location targets the mapping folder relative to the script location rather than a specific user's OneDrive folder.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Controllers/Run-WCC-Mapping.ps1 around lines 46 - 49, The script currently writes potentially empty host-group files ($obgyn_checkout, $obgyn_checkin, $breast_checkout, $breast_checkin) and proceeds to call the mapper even when groups have no hosts; add validation before writing/processing: for each of these variables check that it contains at least one host (e.g., non-empty string or Count -gt 0) and only call Set-Content and invoke the mapping step for groups that pass the check; for empty groups emit a clear warning log message and skip the mapper for that group (or abort overall if that is desired) so you don't feed empty files into the mapping stage.

- Verify each finding against the current code and only fix it if needed.

In @mapping/DROPINS_README.txt around lines 2 - 3, The README contains UTF-8 mojibake sequences "ΓÇö" and "ΓåÆ" in the listed lines; locate the entries containing "RPM-Recon.annotated.ps1 ΓÇö controller" and "Enforce-Mapping-SingleHost.ps1 ΓÇö one-off enforcer for WLS111WCC094 ΓåÆ \\SWBPNHPHPS01V\LS111-WCC65" and replace the corrupted sequences with the intended characters (e.g., replace "ΓÇö" with an em-dash "—" or a right arrow "→" as appropriate, and replace "ΓåÆ" with the intended symbol or plain ASCII backslash sequence), ensuring the file is saved with UTF-8 encoding so the characters persist correctly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.NoWinRM.ps1 around lines 109 - 121, The scheduled task currently registers as NT AUTHORITY\SYSTEM (Register-ScheduledTask -TaskName 'SetDefaultPrinterOnce' ... -User 'NT AUTHORITY\SYSTEM'), which cannot set a per-user default printer; change the task principal so it runs in the interactive/logged-on user context (for example, remove the -User 'NT AUTHORITY\SYSTEM' and instead create a principal via New-ScheduledTaskPrincipal -UserId 'BUILTIN\Users' (or the specific user SID) with an appropriate -LogonType (Interactive or S4U) and use that principal when calling Register-ScheduledTask for TaskName 'SetDefaultPrinterOnce', ensuring the action ($ps) runs under the logging-on user's profile so SetDefaultPrinter succeeds.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.NoWinRM.ps1 at line 1, Remove the corrupted header characters "﻿∩╗┐" from the top of the file and re-save the file with proper UTF-8 encoding (either UTF-8 without BOM or a single valid BOM), ensuring the first bytes are the correct BOM (or none) so the PowerShell script starts with a valid comment "<#" on line 1; this will eliminate the double-encoded artifact that causes parsing issues.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.NoWinRM.ps1 around lines 176 - 180, The schtasks.exe invocation ($q = & schtasks.exe /Query /S $fqdn0 /FO LIST 2>$null) won't raise a PowerShell exception, so the current try/catch is ineffective; after running that native command check $LASTEXITCODE and handle non-zero values (emit the Write-Warning about RPC being blocked and proceed) instead of relying on catch. Update the block around the schtasks.exe call to capture its output into $q, then test if $LASTEXITCODE -ne 0 and run the existing warning message (or alternate error handling) so failures are detected correctly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.NoWinRM.ps1 around lines 90 - 102, The Start-Process calls in the foreach loops over $queuesRemove and $queuesAdd currently ignore rundll32.exe exit codes; change the Start-Process calls (the ones invoking 'printui.dll,PrintUIEntry' with '/gd' and '/ga') to use -PassThru, capture the returned process object (e.g., $p), WaitForExit (or rely on -Wait) and then inspect $p.ExitCode; if ExitCode is non-zero, log a failure with the exit code and treat the operation as failed (same places that currently write "REMOVE FAIL $q" / "ADD FAIL $q" should include the exit code and not assume success). Ensure both the remove loop and add loop implement this check.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.NoWinRM.ps1 around lines 112 - 116, The embedded PowerShell here-string interpolates $defaultQ into commands (Add-Printer, Get-CimInstance -Filter, Invoke-CimMethod) without sanitization, allowing injection; fix by sanitizing/escaping $defaultQ before building $ps (e.g., create an escaped variable like $escapedDefaultQ = $defaultQ -replace "'","''" -replace "\\","\\\\") and use that escaped value when constructing the here-string or, even better, avoid interpolation by passing the printer name as a parameter or via a safe API call instead of embedding it in a command string.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.ps1 at line 191, The current $logFrag assignment uses [System.Web.HttpUtility]::HtmlEncode which isn't available in PowerShell Core/7+; change the HtmlEncode call to [System.Net.WebUtility]::HtmlEncode so it works in both Windows PowerShell and PowerShell 7+, e.g. update the expression in the $logFrag construction (the HtmlEncode invocation on the Get-Content result) to use System.Net.WebUtility::HtmlEncode instead of System.Web.HttpUtility::HtmlEncode.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.ps1 at line 1, The file Map-MachineWide.ps1 contains a visible BOM and garbled Unicode sequences; re-save the file using consistent UTF-8 encoding (prefer UTF-8 without BOM) and remove the leading BOM characters (the visible "∩╗┐") and any garbled sequences (e.g., "ΓÇó", "ΓåÆ") so PowerShell reads plain ASCII/Unicode text; use your editor or a conversion tool (e.g., save-as UTF-8 without BOM or run a file-encoding conversion) to normalize the file and then verify the script loads/runs correctly in PowerShell with correct characters.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.ps1 at line 85, The variable $args in Map-MachineWide.ps1 shadows PowerShell's automatic $args which can cause unexpected behavior; rename this variable (e.g., to $printArgs or $argList) wherever it's defined and referenced (the assignment currently "$args = @('printui.dll,PrintUIEntry','/ga','/n',"$unc")" and any subsequent uses) and update all call sites in the script to use the new name to avoid clobbering the automatic variable.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.ps1 around lines 106 - 125, The scheduled task created by Register-SetDefaultPrinterOnce (TaskName 'SetDefaultPrinterOnce') never removes itself; modify the $cmd payload built in Register-SetDefaultPrinterOnce to, after setting the default printer, remove the scheduled task (e.g., call Unregister-ScheduledTask -TaskName 'SetDefaultPrinterOnce' -Confirm:$false or use schtasks /Delete /TN "SetDefaultPrinterOnce" /F) inside the try block so the task deletes itself on success (keep existing error handling), and ensure the self-unregister runs under the same SYSTEM context and does not prompt for confirmation.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.ps1 at line 92, In Remove-UNC the script reuses the automatic PowerShell variable $args which shadows built-in args; rename that local argument array to a distinct identifier (e.g., $printuiArgs or $removeArgs) and update any invocations that reference it (the array initialized at the line with 'printui.dll,PrintUIEntry','/gd','/n',"$unc") so the function no longer clobbers automatic $args; ensure the new variable is used when invoking the process (same pattern as the other fix you applied).

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.v5Compat.ps1 around lines 1 - 3, The header contains visible encoding artifacts (e.g., "∩╗┐" and "ΓåÆ") caused by a UTF-8 BOM or inconsistent encoding in the comment block (seen in the script name Map-Remote-MachineWide-Printers.v5Compat.ps1 / Map-MachineWide.v5Compat.ps1); open the file in an editor that shows encoding, remove the stray characters from the top comment, and re-save the file as UTF-8 without BOM (or as UTF-8 consistently) so the header comment and script name render correctly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.v5Compat.ps1 around lines 153 - 173, Inside the ForEach-Object -Parallel scriptblock, the external ConcurrentBag ($bag) must be referenced with $using:, and the local variable $args shadows PowerShell's automatic $args; change all in-block usages of $bag.Add to $using:bag.Add (and any other accesses like $using:bag) and rename the local $args variable (e.g. to $argList) and pass -ArgumentList $argList (initialized from $using:Args) so you don't shadow the automatic variable; update Invoke-Command to use the new name and leave the final $bag.ToArray() outside the scriptblock as-is.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.v5Compat.ps1 around lines 88 - 99, The $sbAdd scriptblock currently appends each queue to $added unconditionally because Start-Process -Wait does not throw on non-zero exits; change the Start-Process invocation in the foreach (in $sbAdd) to use -PassThru, capture the returned process object, call WaitForExit or wait on it, then check its ExitCode (or $LASTEXITCODE) and only add $q to $added when exit code is zero; on non-zero exit, write an error including the process ExitCode and exception/message. Ensure gpupdate still runs in its try block after processing all queues.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.v5Compat.ps1 at line 137, The empty-array check can misbehave when Get-HostList returns a single string because $hosts becomes a string and .Count reports character length; change the assignment where $hosts is populated (from Get-HostList) to coerce it to an array (use the array subexpression @() around the call) so $hosts is always an array, then keep the existing check if (-not $hosts.Count) { throw "No hosts in $HostsPath" } to correctly detect zero hosts; reference the $hosts variable and the Get-HostList call when applying the fix.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.v5Compat.ps1 around lines 114 - 127, The scheduled-task code in $sbDefaultOnce and the task named 'SetDefaultPrinterOnce' currently injects $Queue directly into a command string and registers the task as NT AUTHORITY\SYSTEM; fix it by validating/sanitizing $Queue (allow only expected chars like letters, digits, spaces, -, _, and backslash) and stop embedding it via string interpolation—pass the queue as a safe argument (e.g., use a temp script file or New-ScheduledTaskAction with an Argument/ArgumentList that receives the queue value instead of inlining), and register the task for the interactive user context (do not use -User 'NT AUTHORITY\SYSTEM' for Register-ScheduledTask; register per-user at logon so SetDefaultPrinter runs in the actual user's HKCU) while keeping the task name SetDefaultPrinterOnce and using New-ScheduledTaskAction/Register-ScheduledTask to create the action/trigger.

- Verify each finding against the current code and only fix it if needed.

In @mapping/Workers/Map-MachineWide.v5Compat.ps1 around lines 65 - 73, The code defines a hashtable named $args which shadows PowerShell's automatic $args; rename this variable (e.g., $wsmanArgs or $sessionArgs) everywhere it's used in Map-MachineWide.v5Compat.ps1 to avoid masking the built-in variable, and update any subsequent references that pass this hashtable to functions/cmdlets (such as New-PSSessionOption or New-PSSession/Invoke-Command callers that use $args) so the new name is consistently used.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md at line 75, The README contains a corrupted hyphen in the sentence "Flushes any inΓÇæmemory progress." Replace the corrupted sequence "inΓÇæmemory" with the correct "in-memory" so the line reads "Flushes any in-memory progress." and ensure the file encoding is UTF-8 to prevent recurrence.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md at line 106, The heading string "Troubleshooting OneΓÇæLiners" contains a corrupted hyphen sequence; update the heading in README-original.md by replacing "Troubleshooting OneΓÇæLiners" with the correct text "Troubleshooting One-Liners" (or "Troubleshooting One‑Liners" if you prefer a non-breaking hyphen) so the hyphen renders properly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md at line 60, Replace the corrupted character sequence "PerΓÇæhost" in the README entry for "-MaxWaitSeconds <int>" with the correct "Per-host" so the line reads "`-MaxWaitSeconds <int>`: Per-host polling budget (default `60`). Locate the markdown line containing the literal token "-MaxWaitSeconds <int>" and edit the description text to remove the bad encoding and use the plain hyphenated phrase "Per-host".

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md around lines 121 - 125, The markdown contains corrupted hyphen characters (e.g., "perΓÇæhost", "readΓÇæonly", "singleΓÇæfile") in the "Output Contract" section; open README-original.md and replace those corrupted sequences with proper hyphens (e.g., "per-host", "read-only", "single-file") so the lines for CentralResults.csv, Results.csv, Controller.log and index.html read correctly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md around lines 42 - 52, Replace the corrupted encoding artifacts in the pipeline section by substituting "ΓåÆ" with a proper arrow "→" and all "ΓÇæ" occurrences with an en-dash or hyphen as appropriate (e.g., "oneΓÇætime" → "one-time", "autoΓÇædelete" → "auto-delete", "RollΓÇæup" → "Roll‑up", "bestΓÇæeffort" → "best-effort"), preserve surrounding text like "Resolve host", "Stage worker", "Schedule", "Kick & poll", "Collect", "Roll-up", "Report", and "Cleanup" to ensure readability, and save the file with UTF-8 encoding so the replacements persist in README-original.md.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md around lines 112 - 116, Replace the ambiguous "when policy allows NTLM" line with a clear security note: remove encouragement of NTLM and add a warning that NTLM is deprecated and insecure, recommend using Kerberos or domain-based authentication where possible, and suggest authenticating with Get-Credential and mapping with New-PSDrive (and cleaning up with Remove-PSDrive) only when necessary under secure conditions; reference Get-Credential, New-PSDrive, and Remove-PSDrive in the note so readers can locate the related example.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md around lines 5 - 6, The README contains corrupted dash characters (e.g., "readΓÇæonly", "oneΓÇæpage", "oneΓÇætime"); open the affected README-original.md and replace each corrupted sequence (ΓÇæ) with the correct hyphen or en-dash as appropriate (use "-" for simple hyphenation like "read-only" and "one-page" or "–" if you prefer an en-dash for ranges/phrasing), ensuring all occurrences of "readΓÇæonly", "oneΓÇæpage", "oneΓÇætime" are corrected and run a quick pass to catch any other ΓÇæ artifacts in the file.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md around lines 136 - 144, Replace the corrupted smart-quote and dash sequences in the README FAQ text with proper ASCII/Unicode punctuation: change "ΓÇ£Central CSV: none.ΓÇ¥" to “Central CSV: none.” (or plain "Central CSV: none."), "ΓÇö" to "—" or "-" in the sentence about raising `-MaxWaitSeconds`, "ΓÇÖm" to "I'm" in the Windows PowerShell question, and "ΓÇæonly" to "only" (or "only" with appropriate punctuation) in the `-Parallel` answer; update the exact FAQ lines (the question text "The HTML shows ΓÇ£Central CSV: none.ΓÇ¥..." and answers mentioning `-MaxWaitSeconds`, `-Parallel`, and "PS7") to use the corrected characters throughout.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md around lines 154 - 155, The "## License" section contains a corrupted em-dash sequence ("Internal tooling ΓÇö adapt as needed.") and the file is missing a trailing newline; replace "ΓÇö" with a proper em-dash or hyphen (e.g., "—" or "-") in the "Internal tooling ΓÇö adapt as needed." line and ensure README-original.md ends with a single newline character so the file terminates cleanly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md around lines 1 - 3, Remove the UTF-8 BOM and fix corrupted dash characters in the README header: open the text (containing the string "RPM Recon ΓÇö ZeroΓÇæRisk Printer Mapping Inventory" and the "Version: v0.1.0 (Recon Alpha) ΓÇö generated ..." line), save the file as UTF-8 without BOM, and replace corrupted sequences (e.g., "ΓÇö" → em-dash "—", "ΓÇæ" → en-dash "–") so the header reads "RPM Recon — Zero–Risk Printer Mapping Inventory" and the version line uses proper dashes; verify the whole file uses UTF-8 encoding and no BOM remains.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md around lines 129 - 132, Fix the corrupted characters in the "## Safety Notes" section: replace "bestΓÇæeffort" with "best-effort", "donΓÇÖt" with "don't", and "rollΓÇæup" with "roll-up" so the lines read "Remote artifacts are cleaned after collection (best-effort; failures are logged)." and "Partial successes are always preserved; failed hosts don't prevent roll-up." Update the three corrupted tokens in that block (look for the paragraph under the "## Safety Notes" heading) to restore proper hyphens and the apostrophe.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md around lines 94 - 102, The README contains encoding artifacts: corrupted arrows ("ΓåÆ") and smart-quote sequences ("ΓÇ£", "ΓÇ¥"); update the "Known Quirks" section so those tokens are replaced with standard ASCII characters—use a normal arrow or dash for the bullet continuations after each quirk and replace the smart quotes around "Target account name is incorrect." with standard double quotes; ensure occurrences near the examples referencing `/Z`, `/TR`, `-Parallel`, `$using:`, `\share`, and `/S` are corrected so the lines read with plain ASCII (e.g., "This controller avoids `/Z`...", "Kerberos \"Target account name is incorrect.\"").

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md at line 25, The section heading contains a corrupted em-dash sequence "ΓÇÖ" in the string "## Quickstart (Controller box ΓÇÖ PowerShell 7, elevated)"; replace that substring with a proper em-dash (or en-dash) so the heading reads e.g. "## Quickstart (Controller box — PowerShell 7, elevated)", then save the README-original.md as UTF-8 (no mojibake) to prevent reintroduction of the corrupted characters.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md around lines 148 - 150, The changelog contains corrupted hyphen characters in the phrase "endΓÇæofΓÇærun"; open the "Changelog (this version)" section in README-original.md and replace the broken sequence (endΓÇæofΓÇærun) with the correct text "end-of-run" (also check and correct any similar garbled sequences), save the file as UTF-8 to prevent reintroduction of encoding artifacts, and verify the surrounding lines (the CentralResults.csv link note and logging polish line) render correctly.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md at line 38, Replace the corrupted apostrophe sequence "ΓÇÖ" in the README sentence "The HTML report **only shows a download for CentralResults.csv if the file exists** (so you wonΓÇÖt see a broken link when no hosts produced artifacts)." with a proper apostrophe (e.g., "won't" or "won’t") so the parenthetical reads "(so you won't see a broken link when no hosts produced artifacts)"; update the string in the README-original.md where that sentence appears.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/README-original.md around lines 10 - 19, The README-original.md directory tree contains mojibake box-drawing characters; replace them with clean ASCII or proper Unicode box-drawing characters so the tree renders correctly—update the lines that contain "RPM-Recon.ps1", "Map-Remote-MachineWide-Printers.ps1", "csv/ -> hosts.txt" and "logs/ -> recon-YYYYMMDD-HHmmss/" to use a consistent ASCII tree (e.g., ├──, └──, │) or simple ASCII equivalents (e.g., |--, `--) throughout the block; ensure indentation and whitespace are preserved so the visual structure remains clear.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/Runbook-WCC-R164.md around lines 13 - 14, The runbook step referencing Run-164.ps1 lacks a source; update mapping/docs/Runbook-WCC-R164.md to add a clear download location and acquisition instructions for Run-164.ps1 (e.g., an internal repo URL, artifact storage link, or path within this repo), and optionally a fallback: how to generate or request the script; ensure the step still tells users to save Run-164.ps1 next to mapping/ and include the exact URL or repo path and any required access notes.

- Verify each finding against the current code and only fix it if needed.

In @mapping/docs/Runbook-WCC-R164.md at line 2, The document title "Runbook ΓÇö Implement Recon Across 164 Devices (No config changes)" and other occurrences contain mangled Unicode sequences ("ΓÇö", "ΓÇª", "ΓåÆ"); open the markdown and replace "ΓÇö" with an em-dash or ASCII "--" in the header and elsewhere, replace "ΓÇª" with "..." (ellipsis), and replace "ΓåÆ" with "→" or "=>" as appropriate; ensure the file is saved with UTF-8 encoding after the replacements and run a quick search for any remaining "ΓÇ" or "Γå" sequences to clean all occurrences.