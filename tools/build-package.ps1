[CmdletBinding()]
param(
	[Parameter(Mandatory)][string] $Tree,
	[Parameter(Mandatory)][string] $OutputPath,
	[Parameter(Mandatory)][string] $PackageRootName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$output = [System.IO.Path]::GetFullPath($OutputPath)
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) "smartmeter-package-$PID"

function Set-ZipUnixCreatorMetadata([string] $Path) {
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
	$offset = [int64]$centralOffset
	for ($index = 0; $index -lt $entryCount; $index++) {
		if ($offset + 46 -gt $bytes.Length -or
			[System.BitConverter]::ToUInt32($bytes, [int]$offset) -ne 0x02014b50) {
			throw "Invalid ZIP central-directory entry $index."
		}
		# The high byte of "version made by" is the creator system: 3 means Unix.
		$bytes[[int]$offset + 5] = 3
		$nameLength = [System.BitConverter]::ToUInt16($bytes, [int]$offset + 28)
		$extraLength = [System.BitConverter]::ToUInt16($bytes, [int]$offset + 30)
		$commentLength = [System.BitConverter]::ToUInt16($bytes, [int]$offset + 32)
		$offset += 46 + $nameLength + $extraLength + $commentLength
	}
	if ($offset -ne [int64]$centralOffset + $centralSize) {
		throw "ZIP central-directory size does not match its entries."
	}
	[System.IO.File]::WriteAllBytes($Path, $bytes)
}

try {
	New-Item -ItemType Directory -Path $temporary -Force | Out-Null
	$tarPath = Join-Path $temporary "source.tar"
	$content = Join-Path $temporary "content"
	New-Item -ItemType Directory -Path $content -Force | Out-Null
	& git -C $repoRoot archive --format=tar --worktree-attributes -o $tarPath $Tree
	if ($LASTEXITCODE -ne 0) { throw "git archive failed." }
	& tar -xf $tarPath -C $content
	if ($LASTEXITCODE -ne 0) { throw "Unable to extract the Git archive." }

	$modes = @{}
	foreach ($line in @(& git -C $repoRoot ls-tree -r $Tree)) {
		if ($line -match "^(\d{6})\s+\w+\s+[0-9a-f]+\t(.+)$") {
			$modes[$Matches[2]] = $Matches[1]
		}
	}
	if ($LASTEXITCODE -ne 0) { throw "Unable to read Git file modes." }

	$parent = Split-Path -Parent $output
	New-Item -ItemType Directory -Path $parent -Force | Out-Null
	if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
	Add-Type -AssemblyName System.IO.Compression
	$stream = [System.IO.File]::Open($output, [System.IO.FileMode]::CreateNew)
	try {
		$zip = [System.IO.Compression.ZipArchive]::new(
			$stream, [System.IO.Compression.ZipArchiveMode]::Create, $false
		)
		try {
			$files = @(Get-ChildItem -LiteralPath $content -File -Recurse |
				Sort-Object { [System.IO.Path]::GetRelativePath($content, $_.FullName).Replace("\", "/") })
			foreach ($file in $files) {
				$relative = [System.IO.Path]::GetRelativePath($content, $file.FullName).Replace("\", "/")
				$entry = $zip.CreateEntry(
					"$PackageRootName/$relative",
					[System.IO.Compression.CompressionLevel]::NoCompression
				)
				$entry.LastWriteTime = [DateTimeOffset]::new(2026, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
				$unixMode = if ($modes[$relative] -eq "100755") { 0x81ED } else { 0x81A4 }
				$attributes = [int64]$unixMode * 65536
				if ($attributes -gt [int]::MaxValue) { $attributes -= 4294967296 }
				$entry.ExternalAttributes = [int]$attributes
				$input = [System.IO.File]::OpenRead($file.FullName)
				$target = $entry.Open()
				try { $input.CopyTo($target) } finally { $target.Dispose(); $input.Dispose() }
			}
		} finally {
			$zip.Dispose()
		}
	} finally {
		$stream.Dispose()
	}
	Set-ZipUnixCreatorMetadata -Path $output
	$hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
	[System.IO.File]::WriteAllText(
		"$output.sha256",
		"$hash  $([System.IO.Path]::GetFileName($output))`n",
		[System.Text.Encoding]::ASCII
	)
	& (Join-Path $PSScriptRoot "verify-package.ps1") -ArchivePath $output -Tree $Tree `
		-PackageRootName $PackageRootName -RequireChecksum
	if ($LASTEXITCODE -ne 0) { throw "Package verification failed." }
	Write-Host "SHA-256: $hash"
} finally {
	if (Test-Path -LiteralPath $temporary) {
		Remove-Item -LiteralPath $temporary -Recurse -Force
	}
}
