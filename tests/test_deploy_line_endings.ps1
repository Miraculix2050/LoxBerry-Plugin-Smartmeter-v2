$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\tools\TestDeviceFileTransfer.ps1")

function Assert-BytesEqual {
	param(
		[byte[]] $Actual,
		[byte[]] $Expected,
		[string] $Message
	)

	if (-not [System.Linq.Enumerable]::SequenceEqual[byte]($Actual, $Expected)) {
		throw "$Message`nExpected: $($Expected -join ',')`nActual:   $($Actual -join ',')"
	}
}

$crlfScript = [Text.Encoding]::UTF8.GetBytes("#!/usr/bin/perl`r`nprint qq(ok);`r`n")
$lfScript = [Text.Encoding]::UTF8.GetBytes("#!/usr/bin/perl`nprint qq(ok);`n")
Assert-BytesEqual (ConvertTo-LfLineEndings $crlfScript) $lfScript "CRLF scripts must be normalized to LF"

$standaloneCr = [byte[]](65, 13, 66, 10)
Assert-BytesEqual (ConvertTo-LfLineEndings $standaloneCr) $standaloneCr "Standalone CR bytes must be preserved"

$utf8Bom = [byte[]](239, 187, 191, 65, 13, 10)
$expectedBom = [byte[]](239, 187, 191, 65, 10)
Assert-BytesEqual (ConvertTo-LfLineEndings $utf8Bom) $expectedBom "UTF-8 BOM bytes must remain unchanged"

$remoteCommand = "set -u`r`nprintf 'ok\n'`r`n"
$expectedRemoteCommand = "set -u`nprintf 'ok\n'`n"
if ((ConvertTo-LfTextLineEndings $remoteCommand) -cne $expectedRemoteCommand) {
	throw "Remote commands must be normalized from CRLF to LF"
}

$standaloneCrText = "set -u`rprintf 'ok\n'"
$expectedStandaloneCrText = "set -u`nprintf 'ok\n'"
if ((ConvertTo-LfTextLineEndings $standaloneCrText) -cne $expectedStandaloneCrText) {
	throw "Standalone CR characters in remote commands must be normalized to LF"
}

Write-Output "Test-device line-ending normalization tests passed."
