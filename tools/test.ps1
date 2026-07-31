[CmdletBinding()]
param(
	[ValidateSet("Changed", "Full")]
	[string]$Profile = "Changed",
	[string]$BaseRef,
	[string[]]$Files,
	[switch]$Plan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
	$PSNativeCommandUseErrorActionPreference = $false
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$map = Import-PowerShellDataFile (Join-Path $repoRoot "tests/test-map.psd1")
if ($map.Version -ne 1) {
	throw "Unsupported test map version: $($map.Version)"
}

$testCatalog = [ordered]@{
	"vzlogger-channels" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_vzlogger_channels.pl"); Path = "tests/test_vzlogger_channels.pl" }
	"vzlogger-generator" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_vzlogger_generator.pl"); Path = "tests/test_vzlogger_generator.pl" }
	"vzlogger-validator" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_vzlogger_validator.pl"); Path = "tests/test_vzlogger_validator.pl" }
	"vzlogger-expert" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_vzlogger_expert.pl"); Path = "tests/test_vzlogger_expert.pl" }
	"language-resources" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_language_resources.pl"); Path = "tests/test_language_resources.pl" }
	"vzlogger-runtime" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_vzlogger_runtime.pl"); Path = "tests/test_vzlogger_runtime.pl" }
	"vzlogger-custom-channels" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_vzlogger_custom_channels.pl"); Path = "tests/test_vzlogger_custom_channels.pl" }
	"vzlogger-config-validation" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_vzlogger_config_validation.pl"); Path = "tests/test_vzlogger_config_validation.pl" }
	"vzlogger-bridge" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_vzlogger_bridge.pl"); Path = "tests/test_vzlogger_bridge.pl" }
	"vzlogger-http" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_vzlogger_http.pl"); Path = "tests/test_vzlogger_http.pl" }
	"obis-status" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_obis_status.pl"); Path = "tests/test_obis_status.pl" }
	"web-security" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_web_security.pl"); Path = "tests/test_web_security.pl" }
	"loxberry-native-integration" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_loxberry_native_integration.pl"); Path = "tests/test_loxberry_native_integration.pl" }
	"lifecycle-v4" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_lifecycle_v4.pl"); Path = "tests/test_lifecycle_v4.pl" }
	"ui-v4" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_ui_v4.pl"); Path = "tests/test_ui_v4.pl" }
	"bridge-service-lifecycle" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_bridge_service_lifecycle.pl"); Path = "tests/test_bridge_service_lifecycle.pl" }
	"recovery" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_recovery.pl"); Path = "tests/test_recovery.pl" }
	"release-metadata" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_release_metadata.pl"); Path = "tests/test_release_metadata.pl" }
	"documentation-links" = @{ Tool = "perl"; Args = @("-I", ".github/ci/perl-lib", "-I", "bin", "tests/test_documentation_links.pl"); Path = "tests/test_documentation_links.pl" }
	"upgrade-2-1" = @{ Tool = "sh"; Args = @("tests/test_upgrade_2_1.sh"); Path = "tests/test_upgrade_2_1.sh" }
	"deploy-line-endings" = @{ Tool = "pwsh"; Args = @("-NoProfile", "-File", "tests/test_deploy_line_endings.ps1"); Path = "tests/test_deploy_line_endings.ps1" }
	"vzlogger-live" = @{ Tool = "node"; Args = @("tests/test_vzlogger_live.js"); Path = "tests/test_vzlogger_live.js" }
	"validate-development-metadata" = @{ Tool = "perl"; Args = @("tools/validate-release-metadata.pl", "--channel", "development"); Path = "tools/validate-release-metadata.pl" }
	"test-runner" = @{ Tool = "pwsh"; Args = @("-NoProfile", "-File", "tests/test_test_runner.ps1"); Path = "tests/test_test_runner.ps1" }
	"chartjs-integrity" = @{ Kind = "Hash"; Path = "webfrontend/htmlauth/vendor/chart.js/chart.umd.min.js" }
}

function Normalize-RepoPath {
	param([Parameter(Mandatory)][string]$Path)
	$fullPath = if ([System.IO.Path]::IsPathRooted($Path)) {
		[System.IO.Path]::GetFullPath($Path)
	} else {
		[System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
	}
	$relative = [System.IO.Path]::GetRelativePath($repoRoot, $fullPath).Replace("\", "/")
	if ($relative -eq ".." -or $relative.StartsWith("../")) {
		throw "Test path is outside the repository: $Path"
	}
	return $relative
}

function Test-PathPattern {
	param([string]$Path, [string]$Pattern)
	$wildcard = $Pattern.Replace("**", "*")
	return $Path -like $wildcard
}

function Invoke-GitLines {
	param([string[]]$Arguments, [switch]$AllowFailure)
	$output = & git @Arguments 2>$null
	$exitCode = $LASTEXITCODE
	if ($exitCode -ne 0 -and !$AllowFailure) {
		throw "git $($Arguments -join ' ') failed with exit code $exitCode"
	}
	if ($exitCode -ne 0) { return @() }
	return @($output | Where-Object { $_ } | ForEach-Object { $_.Trim() })
}

function Get-ChangedFiles {
	$found = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$fallbackReason = $null
	$effectiveBase = if ($BaseRef) { $BaseRef } else { "origin/master" }
	$baseExists = @(Invoke-GitLines @("rev-parse", "--verify", $effectiveBase) -AllowFailure).Count -gt 0
	$mergeBase = @()
	if ($baseExists) { $mergeBase = @(Invoke-GitLines @("merge-base", $effectiveBase, "HEAD") -AllowFailure) }
	if ($BaseRef -and !@($mergeBase).Count) {
		throw "Cannot determine a merge base for explicit -BaseRef '$BaseRef'. Verify that the reference exists and shares history with HEAD."
	}
	if (!$BaseRef -and !@($mergeBase).Count) {
		$fallbackReason = "Automatic base origin/master is unavailable or does not share history with HEAD."
	}
	if (@($mergeBase).Count) {
		Invoke-GitLines @("diff", "--name-only", "--diff-filter=ACMRD", $mergeBase[0], "HEAD") | ForEach-Object { [void]$found.Add((Normalize-RepoPath $_)) }
	}
	Invoke-GitLines @("diff", "--name-only", "--diff-filter=ACMRD") | ForEach-Object { [void]$found.Add((Normalize-RepoPath $_)) }
	Invoke-GitLines @("diff", "--cached", "--name-only", "--diff-filter=ACMRD") | ForEach-Object { [void]$found.Add((Normalize-RepoPath $_)) }
	Invoke-GitLines @("ls-files", "--others", "--exclude-standard") | ForEach-Object { [void]$found.Add((Normalize-RepoPath $_)) }
	return [pscustomobject]@{ Files = @($found | Sort-Object); FallbackReason = $fallbackReason }
}

function Get-AllSyntaxFiles {
	$perl = @(Get-ChildItem -Path $repoRoot -Recurse -File | Where-Object {
		$relative = Normalize-RepoPath $_.FullName
		$relative -notlike "tests/*" -and $_.Extension -in @(".pl", ".pm", ".cgi")
	} | ForEach-Object { Normalize-RepoPath $_.FullName })
	$php = @(Get-ChildItem -Path $repoRoot -Recurse -File -Filter "*.php" | ForEach-Object { Normalize-RepoPath $_.FullName })
	$shellPatterns = @("preinstall.sh", "preroot.sh", "postinstall.sh", "postroot.sh", "preupgrade.sh", "postupgrade.sh", "uninstall/uninstall", "sbin/*.sh", "bin/*.sh")
	$shell = foreach ($pattern in $shellPatterns) {
		Get-ChildItem -Path (Join-Path $repoRoot $pattern) -File -ErrorAction SilentlyContinue | ForEach-Object { Normalize-RepoPath $_.FullName }
	}
	return @{ Perl = @($perl); Php = @($php); Shell = @($shell | Sort-Object -Unique) }
}

$changeSelection = if (!$Files -and $Profile -eq "Changed") { Get-ChangedFiles } else { $null }
$selectedFiles = if ($Files) { @($Files | ForEach-Object { Normalize-RepoPath $_ } | Sort-Object -Unique) } elseif ($changeSelection) { @($changeSelection.Files) } else { @() }
$selectedTests = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$deviceAdvice = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$browserAdvice = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$syntax = @{ Perl = [System.Collections.Generic.HashSet[string]]::new(); Php = [System.Collections.Generic.HashSet[string]]::new(); Shell = [System.Collections.Generic.HashSet[string]]::new() }
$fallbackReason = if ($changeSelection) { $changeSelection.FallbackReason } else { $null }
$fallbackToFull = $Profile -eq "Full" -or $null -ne $fallbackReason

if ($Profile -eq "Changed") {
	foreach ($file in $selectedFiles) {
		$knownTest = $testCatalog.GetEnumerator() | Where-Object { $_.Value.Path -eq $file } | Select-Object -First 1
		if ($file -like "tests/*" -and $file -ne "tests/test-map.psd1") {
			if ($knownTest) { [void]$selectedTests.Add($knownTest.Key) } else { $fallbackToFull = $true }
			continue
		}
		$fileExists = Test-Path -LiteralPath (Join-Path $repoRoot $file) -PathType Leaf
		if ($fileExists -and $file -match '\.(pl|pm|cgi)$') { [void]$syntax.Perl.Add($file) }
		if ($fileExists -and $file -match '\.php$') { [void]$syntax.Php.Add($file) }
		if ($fileExists -and ($file -match '\.sh$' -or $file -eq "uninstall/uninstall")) { [void]$syntax.Shell.Add($file) }

		$matched = $false
		foreach ($rule in $map.Rules) {
			if (@($rule.Patterns | Where-Object { Test-PathPattern $file $_ }).Count) {
				$matched = $true
				foreach ($group in $rule.Groups) {
					foreach ($testId in $map.Groups[$group]) { [void]$selectedTests.Add($testId) }
				}
				if ($rule.Device -and $rule.Device -ne "none") { [void]$deviceAdvice.Add($rule.Device) }
				if ($rule.Browser -and $rule.Browser -ne "none") { [void]$browserAdvice.Add($rule.Browser) }
			}
		}
		if (!$matched -and @($map.RuntimeFallbackPatterns | Where-Object { Test-PathPattern $file $_ }).Count) {
			$fallbackToFull = $true
		}
	}
}

if ($fallbackToFull) {
	$testCatalog.Keys | ForEach-Object { [void]$selectedTests.Add($_) }
	$allSyntax = Get-AllSyntaxFiles
	$allSyntax.Perl | ForEach-Object { [void]$syntax.Perl.Add($_) }
	$allSyntax.Php | ForEach-Object { [void]$syntax.Php.Add($_) }
	$allSyntax.Shell | ForEach-Object { [void]$syntax.Shell.Add($_) }
}

function Write-Selection {
	Write-Output "Profile: $Profile$(if ($fallbackToFull -and $Profile -eq 'Changed') { ' (full fallback)' })"
	if ($fallbackReason) { Write-Output "Fallback: $fallbackReason" }
	Write-Output "Files: $(@($selectedFiles).Count)"
	Write-Output "Tests: $($selectedTests.Count)"
	foreach ($id in @($selectedTests | Sort-Object)) { Write-Output "  TEST $id" }
	foreach ($file in @($syntax.Perl | Sort-Object)) { Write-Output "  SYNTAX perl $file" }
	foreach ($file in @($syntax.Php | Sort-Object)) { Write-Output "  SYNTAX php $file" }
	foreach ($file in @($syntax.Shell | Sort-Object)) { Write-Output "  SYNTAX shell $file" }
	foreach ($item in @($deviceAdvice | Sort-Object)) { Write-Output "  DEVICE $item" }
	foreach ($item in @($browserAdvice | Sort-Object)) { Write-Output "  BROWSER $item" }
}

if ($Plan) {
	Write-Selection
	exit 0
}

function Invoke-NativeCheck {
	param([string]$Id, [string]$Tool, [string[]]$Arguments)
	if (!(Get-Command $Tool -ErrorAction SilentlyContinue)) {
		return [pscustomobject]@{ Id = $Id; State = "INCOMPLETE"; Milliseconds = 0; Output = "Required tool is unavailable: $Tool" }
	}
	$watch = [System.Diagnostics.Stopwatch]::StartNew()
	$output = & $Tool @Arguments 2>&1 | Out-String
	$exitCode = $LASTEXITCODE
	$watch.Stop()
	return [pscustomobject]@{ Id = $Id; State = $(if ($exitCode -eq 0) { "PASS" } else { "FAIL" }); Milliseconds = $watch.ElapsedMilliseconds; Output = $output.TrimEnd() }
}

function Invoke-HashCheck {
	$hashFile = Join-Path $repoRoot "webfrontend/htmlauth/vendor/chart.js/chart.umd.min.js.sha256"
	$parts = (Get-Content -LiteralPath $hashFile -Raw).Trim() -split '\s+', 2
	$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot "webfrontend/htmlauth/vendor/chart.js/chart.umd.min.js")).Hash.ToLowerInvariant()
	$expected = $parts[0].ToLowerInvariant()
	return [pscustomobject]@{ Id = "chartjs-integrity"; State = $(if ($actual -eq $expected) { "PASS" } else { "FAIL" }); Milliseconds = 0; Output = $(if ($actual -eq $expected) { "" } else { "Expected $expected but found $actual" }) }
}

$results = [System.Collections.Generic.List[object]]::new()
Push-Location $repoRoot
try {
	foreach ($file in @($syntax.Perl | Sort-Object)) { $results.Add((Invoke-NativeCheck "perl-syntax:$file" "perl" @("-I", ".github/ci/perl-lib", "-I", "bin", "-c", $file))) }
	foreach ($file in @($syntax.Php | Sort-Object)) { $results.Add((Invoke-NativeCheck "php-syntax:$file" "php" @("-l", $file))) }
	foreach ($file in @($syntax.Shell | Sort-Object)) { $results.Add((Invoke-NativeCheck "shell-syntax:$file" "sh" @("-n", $file))) }
	foreach ($id in @($selectedTests | Sort-Object)) {
		$definition = $testCatalog[$id]
		if ($definition.ContainsKey("Kind") -and $definition.Kind -eq "Hash") {
			$results.Add((Invoke-HashCheck))
		} else {
			$results.Add((Invoke-NativeCheck $id $definition.Tool $definition.Args))
		}
	}
} finally {
	Pop-Location
}

$passed = @($results | Where-Object State -eq "PASS")
$failed = @($results | Where-Object State -eq "FAIL")
$incomplete = @($results | Where-Object State -eq "INCOMPLETE")
$duration = if ($results.Count) { [math]::Round((($results | Measure-Object Milliseconds -Sum).Sum / 1000), 1) } else { 0 }
$overallState = if ($failed.Count) { "FAIL" } elseif ($incomplete.Count) { "INCOMPLETE" } else { "PASS" }
$summaryLine = "$overallState $($passed.Count)/$($results.Count) | ${duration}s"
Write-Output $summaryLine
if ($fallbackReason) { Write-Output "Fallback: $fallbackReason" }
foreach ($result in @($results | Sort-Object Milliseconds -Descending | Select-Object -First 3)) {
	if ($result.Milliseconds -gt 0) { Write-Output ("  SLOW {0} {1:N1}s" -f $result.Id, ($result.Milliseconds / 1000)) }
}
foreach ($result in @($failed + $incomplete)) {
	Write-Output "[$($result.State)] $($result.Id)"
	if ($result.Output) { Write-Output $result.Output }
}
foreach ($item in @($deviceAdvice | Sort-Object)) { Write-Output "DEVICE: $item" }
foreach ($item in @($browserAdvice | Sort-Object)) { Write-Output "BROWSER: $item" }

if ($env:GITHUB_STEP_SUMMARY) {
	$summary = [System.Collections.Generic.List[string]]::new()
	$summary.Add("## SmartMeter test results")
	$summary.Add("")
	$summary.Add("**$summaryLine**")
	if ($failed.Count) { $summary.Add("Failed: " + (($failed | ForEach-Object Id) -join ", ")) }
	if ($incomplete.Count) { $summary.Add("Incomplete: " + (($incomplete | ForEach-Object Id) -join ", ")) }
	foreach ($item in @($deviceAdvice | Sort-Object)) { $summary.Add("Device review: $item") }
	foreach ($item in @($browserAdvice | Sort-Object)) { $summary.Add("Browser review: $item") }
	Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary
}

if ($failed.Count) { exit 1 }
if ($incomplete.Count) { exit 2 }
exit 0
