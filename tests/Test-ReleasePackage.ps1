[CmdletBinding()]
param([string]$Tag='v0.2.2.0',[string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'artifacts' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$manifest = Get-Content -LiteralPath (Join-Path $OutputDirectory 'manifest.json') -Raw | ConvertFrom-Json
$archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $OutputDirectory "psupdate-$Tag-windows-net48.zip"))
try {
    $names = @($archive.Entries | ForEach-Object FullName | Sort-Object)
    $expected = @('psupdate.exe','psupdate.exe.config','Newtonsoft.Json.dll','LICENSE','FORK_NOTES.md','manifest.json') | Sort-Object
    if (@(Compare-Object $names $expected).Count) { throw 'ZIP contents do not match the deployable package.' }
    if (@($archive.Entries | Where-Object { $_.Length -eq 0 }).Count) { throw 'Empty release file.' }
    if (@($archive.Entries | Where-Object { $_.LastWriteTime.Year -ne 2000 }).Count) { throw 'Non-deterministic ZIP timestamp.' }
    foreach ($file in $manifest.files) {
        $entry = $archive.GetEntry($file.name)
        if ($null -eq $entry) { throw 'Manifest names a missing package file.' }
        $stream = $entry.Open()
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
        finally { $algorithm.Dispose(); $stream.Dispose() }
        if ($hash -ne $file.sha256) { throw 'Packaged file differs from its manifest hash.' }
    }
} finally { $archive.Dispose() }
if ('v'+$manifest.version -ne $Tag -or $manifest.commit -notmatch '^[a-f0-9]{40}$') { throw 'Invalid source/version manifest.' }
foreach ($line in Get-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt')) {
    if ($line -notmatch '^([a-f0-9]{64})  ([a-zA-Z0-9_.-]+)$') { throw 'Malformed checksum entry.' }
    if ((Get-FileHash -LiteralPath (Join-Path $OutputDirectory $Matches[2]) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Matches[1]) { throw 'Release checksum mismatch.' }
}
$mismatchRejected = $false
try { & (Join-Path $root 'scripts\package.ps1') -Tag v99.99.99.99 -OutputDirectory (Join-Path $OutputDirectory 'wrong-version') }
catch { $mismatchRejected = $_.Exception.Message -like 'Tag version does not match*' }
if (-not $mismatchRejected) { throw 'Mismatched tag version was accepted.' }
$invalidRejected = $false
try { & (Join-Path $root 'scripts\package.ps1') -Tag 'not-a-version' -OutputDirectory (Join-Path $OutputDirectory 'invalid-version') }
catch { $invalidRejected = $_.Exception.Message -like 'Release tag must be*' }
if (-not $invalidRejected) { throw 'Invalid tag was accepted.' }
$repeat = Join-Path ([IO.Path]::GetTempPath()) ('plex-package-repeat-'+[guid]::NewGuid())
& (Join-Path $root 'scripts\package.ps1') -Tag $Tag -OutputDirectory $repeat
if ((Get-FileHash -LiteralPath (Join-Path $OutputDirectory "psupdate-$Tag-windows-net48.zip")).Hash -ne (Get-FileHash -LiteralPath (Join-Path $repeat "psupdate-$Tag-windows-net48.zip")).Hash) { throw 'Repeated packaging produced different ZIP bytes.' }
Write-Output 'PASS: release contents, dependencies, file hashes, source version, SHA-256 checksums, invalid-version rejection, and reproducible ZIP bytes.'
