$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$runner = Join-Path $repoRoot "tools/test.ps1"
$checks = 0

function Invoke-Plan {
	param([string[]]$Files, [string]$BaseRef)
	$arguments = @("-NoProfile", "-File", $runner, "-Profile", "Changed", "-Plan")
	if ($Files) { $arguments += @("-Files") + $Files }
	if ($BaseRef) { $arguments += @("-BaseRef", $BaseRef) }
	$output = & pwsh @arguments 2>&1 | Out-String
	if ($LASTEXITCODE -ne 0) {
		throw "Runner plan failed with exit code $LASTEXITCODE`n$output"
	}
	return $output
}

function Assert-Match {
	param([string]$Actual, [string]$Pattern, [string]$Message)
	$script:checks++
	if ($Actual -notmatch $Pattern) { throw "$Message`nPattern: $Pattern`nOutput:`n$Actual" }
}

function Assert-NotMatch {
	param([string]$Actual, [string]$Pattern, [string]$Message)
	$script:checks++
	if ($Actual -match $Pattern) { throw "$Message`nUnexpected pattern: $Pattern`nOutput:`n$Actual" }
}

function Assert-Equal {
	param($Actual, $Expected, [string]$Message)
	$script:checks++
	if ($Actual -ne $Expected) { throw "$Message`nExpected: $Expected`nActual: $Actual" }
}

Push-Location $repoRoot
try {
	$docs = Invoke-Plan -Files @("docs/development/test-strategy.md")
	Assert-Match $docs "TEST documentation-links" "Documentation changes select documentation checks."
	Assert-NotMatch $docs "(?:DEVICE|BROWSER) " "Developer documentation does not request device or browser checks."

	$module = Invoke-Plan -Files @("bin/SmartMeterVZLoggerChannels.pm")
	Assert-Match $module "SYNTAX perl bin/SmartMeterVZLoggerChannels\.pm" "Perl modules receive a changed-file syntax check."
	Assert-Match $module "TEST vzlogger-channels" "Channel modules select channel regression tests."
	Assert-NotMatch $module "Profile: Changed \(full fallback\)" "Known modules do not fall back to the full suite."

	$ui = Invoke-Plan -Files @("webfrontend/htmlauth/smartmeter-v4.css")
	Assert-Match $ui "BROWSER .*full matrix" "Shared CSS reports the risk-based full-matrix decision."
	$template = Invoke-Plan -Files @("templates/settings.html")
	Assert-NotMatch $template "Profile: Changed \(full fallback\)" "Known root templates use targeted UI checks."
	Assert-Match $template "TEST ui-v4" "Known root templates select UI regressions."

	$lifecycle = Invoke-Plan -Files @("postroot.sh")
	Assert-Match $lifecycle "SYNTAX shell postroot\.sh" "Lifecycle shell files receive syntax checks."
	Assert-Match $lifecycle "DEVICE .*lifecycle scenarios" "Lifecycle changes report targeted device evidence."

	$fallback = Invoke-Plan -Files @("bin/new_runtime.pl")
	Assert-Match $fallback "Profile: Changed \(full fallback\)" "Unknown runtime files fall back to the full suite."
	Assert-Match $fallback "TEST test-runner" "The full fallback includes runner self-tests."

	$base = Invoke-Plan -BaseRef "HEAD"
	Assert-Match $base "Profile: Changed" "An explicit base reference is accepted."

	$emptyOutput = & pwsh -NoProfile -File $runner -Profile Changed -Files LICENSE 2>&1 | Out-String
	$emptyExit = $LASTEXITCODE
	Assert-Equal $emptyExit 0 "A valid empty selection exits successfully."
	Assert-Match $emptyOutput "PASS 0/0" "A valid empty selection reports an explicit pass."

	$missingBase = "0000000000000000000000000000000000000000"
	$invalidBaseOutput = & pwsh -NoProfile -File $runner -Profile Changed -Plan -BaseRef $missingBase 2>&1 | Out-String
	$invalidBaseExit = $LASTEXITCODE
	Assert-Equal $invalidBaseExit 1 "An invalid explicit base reference fails."
	Assert-Match $invalidBaseOutput "Cannot determine a merge base for explicit -BaseRef" "An invalid explicit base reference reports the cause."

	$environment = Get-Content -Raw (Join-Path $repoRoot ".codex/environments/environment.toml")
	Assert-Match $environment '(?ms)^\[setup\]\r?\nscript = ""\r?$' "The shared environment keeps setup empty."
	Assert-Match $environment '(?m)^name = "Changed tests"\r?$' "The shared environment exposes the Changed tests action."
	Assert-Match $environment '(?m)^icon = "test"\r?$' "The Changed tests action uses the test icon."
	Assert-Match $environment '(?m)^command = "pwsh -NoProfile -File tools/test\.ps1 -Profile Changed"\r?$' "The Changed tests action invokes the repository runner."
	$runnerSource = Get-Content -Raw $runner
	Assert-Match $runnerSource '"upgrade-2-1".*?Args = @\("-lc", "sh tests/test_upgrade_2_1\.sh"\)' "Shell integration tests use a login shell so Git for Windows exposes its POSIX tools and invoke the non-executable script explicitly through sh."
} finally {
	Pop-Location
}

Write-Output "Test-runner selection tests passed ($checks checks)."
