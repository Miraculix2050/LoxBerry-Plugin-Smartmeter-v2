[CmdletBinding()]
param(
	[Parameter(Mandatory)][string] $ArchivePath,
	[Parameter(Mandatory)][string] $Tree,
	[Parameter(Mandatory)][string] $PackageRootName,
	[switch] $RequireChecksum
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$archiveFullPath = [System.IO.Path]::GetFullPath($ArchivePath)
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) "smartmeter-verify-$PID"

function Assert-ZipUnixCreatorMetadata([string] $Path, [int] $ExpectedEntries) {
	$bytes = [System.IO.File]::ReadAllBytes($Path)
	$eocd = -1
	for ($offset = $bytes.Length - 22; $offset -ge [Math]::Max(0, $bytes.Length - 65557); $offset--) {
		if ([System.BitConverter]::ToUInt32($bytes, $offset) -eq 0x06054b50) {
			$eocd = $offset
			break
		}
	}
	if ($eocd -lt 0) { throw "ZIP end-of-central-directory record is missing." }
	$entryCount = [System.BitConverter]::ToUInt16($bytes, $eocd + 10)
	$centralSize = [System.BitConverter]::ToUInt32($bytes, $eocd + 12)
	$centralOffset = [System.BitConverter]::ToUInt32($bytes, $eocd + 16)
	if ($entryCount -ne $ExpectedEntries) { throw "ZIP central-directory entry count is invalid." }
	$offset = [int64]$centralOffset
	for ($index = 0; $index -lt $entryCount; $index++) {
		if ($offset + 46 -gt $bytes.Length -or
			[System.BitConverter]::ToUInt32($bytes, [int]$offset) -ne 0x02014b50) {
			throw "Invalid ZIP central-directory entry $index."
		}
		if ($bytes[[int]$offset + 5] -ne 3) {
			throw "Archive entry $index does not declare Unix creator metadata."
		}
		$nameLength = [System.BitConverter]::ToUInt16($bytes, [int]$offset + 28)
		$extraLength = [System.BitConverter]::ToUInt16($bytes, [int]$offset + 30)
		$commentLength = [System.BitConverter]::ToUInt16($bytes, [int]$offset + 32)
		$offset += 46 + $nameLength + $extraLength + $commentLength
	}
	if ($offset -ne [int64]$centralOffset + $centralSize) {
		throw "ZIP central-directory size does not match its entries."
	}
}

try {
	New-Item -ItemType Directory -Path $temporary -Force | Out-Null
	$tarPath = Join-Path $temporary "expected.tar"
	& git -C $repoRoot archive --format=tar --worktree-attributes -o $tarPath $Tree
	if ($LASTEXITCODE -ne 0) { throw "Unable to determine the export manifest for $Tree." }
	$expected = @(& tar -tf $tarPath |
		Where-Object { $_ -and -not $_.EndsWith("/") } |
		ForEach-Object { "$PackageRootName/$_" } |
		Sort-Object)
	if ($LASTEXITCODE -ne 0) { throw "Unable to read the export manifest." }
	$modes = @{}
	foreach ($line in @(& git -C $repoRoot ls-tree -r $Tree)) {
		if ($line -match "^(\d{6})\s+\w+\s+[0-9a-f]+\t(.+)$") {
			$modes[$Matches[2]] = $Matches[1]
		}
	}
	if ($LASTEXITCODE -ne 0) { throw "Unable to read Git file modes." }

	Add-Type -AssemblyName System.IO.Compression
	$archive = [System.IO.Compression.ZipFile]::OpenRead($archiveFullPath)
	try {
		$entries = @($archive.Entries | Where-Object { $_.Name })
		$actual = @($entries.FullName | Sort-Object)
		if (@(Compare-Object $expected $actual).Count -ne 0) {
			throw "Archive entries do not exactly match the Git export contract."
		}
		if ($actual.Count -ne @($actual | Select-Object -Unique).Count) {
			throw "Archive contains duplicate paths."
		}
		$required = @("plugin.cfg", "LICENSE", "README.md", "docs/Readme.md")
		foreach ($name in $required) {
			if ("$PackageRootName/$name" -notin $actual) { throw "Required package entry is missing: $name" }
		}
		foreach ($forbidden in @("release.cfg", "prerelease.cfg", "AGENTS.md")) {
			if ("$PackageRootName/$forbidden" -in $actual) { throw "Forbidden package entry is present: $forbidden" }
		}
		if ($actual | Where-Object { $_ -match "/(?:tests?|tools|docs/development|\.github|\.codex)/" }) {
			throw "Archive contains development-only paths."
		}
		$pluginEntry = $entries | Where-Object FullName -eq "$PackageRootName/plugin.cfg"
		$reader = [System.IO.StreamReader]::new($pluginEntry.Open())
		try { $pluginConfig = $reader.ReadToEnd() } finally { $reader.Dispose() }
		if ($pluginConfig -notmatch "(?m)^VERSION=([0-9]+(?:\.[0-9]+)+)\r?$") {
			throw "Archived plugin.cfg has no valid VERSION."
		}
		foreach ($entry in $entries) {
			if ($entry.LastWriteTime.DateTime -ne [datetime]"2026-01-01T00:00:00") {
				throw "Archive contains a non-canonical timestamp: $($entry.FullName)"
			}
			if ($entry.CompressedLength -ne $entry.Length) {
				throw "Archive entry is not stored canonically: $($entry.FullName)"
			}
			$relative = $entry.FullName.Substring($PackageRootName.Length + 1)
			$expectedMode = if ($modes[$relative] -eq "100755") { 0x81ED } else { 0x81A4 }
			$attributeBytes = [System.BitConverter]::GetBytes($entry.ExternalAttributes)
			$actualMode = [System.BitConverter]::ToUInt32($attributeBytes, 0) -shr 16
			if ($actualMode -ne $expectedMode) {
				throw "Archive entry has a non-canonical Unix mode: $($entry.FullName)"
			}
		}
		Assert-ZipUnixCreatorMetadata -Path $archiveFullPath -ExpectedEntries $entries.Count
	} finally {
		$archive.Dispose()
	}

	if ($RequireChecksum) {
		$sidecar = "$archiveFullPath.sha256"
		if (-not (Test-Path -LiteralPath $sidecar)) { throw "Checksum sidecar is missing." }
		$expectedHash = (Get-FileHash -LiteralPath $archiveFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
		$line = (Get-Content -LiteralPath $sidecar -Raw).Trim()
		if ($line -ne "$expectedHash  $([System.IO.Path]::GetFileName($archiveFullPath))") {
			throw "Checksum sidecar does not match the archive."
		}
	}
	Write-Host "PLUGIN_ARCHIVE=pass $archiveFullPath"
} finally {
	if (Test-Path -LiteralPath $temporary) {
		Remove-Item -LiteralPath $temporary -Recurse -Force
	}
}
