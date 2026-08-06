Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

function Assert-True([bool]$Condition, [string]$Message) {
	if (-not $Condition) { throw $Message }
}

$workflow = Get-Content -LiteralPath (Join-Path $root ".github/workflows/release-asset.yml") -Raw
Assert-True ($workflow.Contains("workflow_dispatch:")) "Release workflow must be manual."
Assert-True ($workflow.Contains("github.actor")) "Owner actor guard is missing."
Assert-True ($workflow.Contains("github.repository_owner")) "Repository owner guard is missing."
Assert-True ($workflow.Contains("confirm_release:")) "Release confirmation input is missing."
Assert-True ($workflow.Contains("contents: read")) "Read-only build permission is missing."
Assert-True ($workflow.Contains("contents: write")) "Scoped publish permission is missing."
Assert-True (-not $workflow.Contains("pull_request_target")) "Unsafe pull_request_target trigger found."
Assert-True (-not $workflow.Contains("release.published")) "Release event trigger found."
Assert-True (-not $workflow.Contains("`n  push:")) "Tag or branch push trigger found."
foreach ($action in @(
	"actions/checkout@11d5960a326750d5838078e36cf38b85af677262",
	"actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020",
	"actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
	"actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093"
)) {
	Assert-True ($workflow.Contains($action)) "Action is not pinned: $action"
}

$attributes = Get-Content -LiteralPath (Join-Path $root ".gitattributes") -Raw
Assert-True ($attributes.Contains("release.cfg export-ignore")) "release.cfg must be export-ignored."
Assert-True ($attributes.Contains("prerelease.cfg export-ignore")) "prerelease.cfg must be export-ignored."

$versionLine = Get-Content -LiteralPath (Join-Path $root "plugin.cfg") |
	Where-Object { $_ -match "^VERSION=([0-9]+(?:\.[0-9]+)+)$" }
Assert-True (@($versionLine).Count -eq 1) "plugin.cfg version is not unique."
$versionLine -match "^VERSION=(.+)$" | Out-Null
$version = $Matches[1]
$packageRoot = "LoxBerry-Plugin-Smartmeter-v2-Smartmeter-V$version"
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) "smartmeter-package-test-$PID"
try {
	New-Item -ItemType Directory -Path $temporary -Force | Out-Null
	$first = Join-Path $temporary "first.zip"
	$second = Join-Path $temporary "second.zip"
	& (Join-Path $root "tools/build-package.ps1") -Tree HEAD -OutputPath $first `
		-PackageRootName $packageRoot
	& (Join-Path $root "tools/build-package.ps1") -Tree HEAD -OutputPath $second `
		-PackageRootName $packageRoot
	Assert-True (
		(Get-FileHash $first -Algorithm SHA256).Hash -eq
		(Get-FileHash $second -Algorithm SHA256).Hash
	) "Two builds from the same Git tree differ."
} finally {
	if (Test-Path -LiteralPath $temporary) {
		Remove-Item -LiteralPath $temporary -Recurse -Force
	}
}

Write-Output "release-workflow=pass"
