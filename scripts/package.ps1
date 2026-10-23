[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Tag,
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
if ($Tag -notmatch '^v(\d+\.\d+\.\d+\.\d+)$') { throw 'Release tag must be vMAJOR.MINOR.BUILD.REVISION.' }
$version = $Matches[1]
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root 'bin\Release'
if ((Get-Item -LiteralPath (Join-Path $build 'psupdate.exe')).VersionInfo.FileVersion -ne $version) {
    throw 'Tag version does not match psupdate.exe. Update AssemblyInfo.cs and build first.'
}
$commit = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') { throw 'Cannot determine source commit.' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'artifacts' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$staging = Join-Path $OutputDirectory 'package'
if (Test-Path -LiteralPath $staging) { throw 'Package staging directory already exists. Use a clean output directory.' }
New-Item -ItemType Directory -Path $staging -Force | Out-Null
foreach ($name in @('psupdate.exe','psupdate.exe.config','Newtonsoft.Json.dll')) {
    Copy-Item -LiteralPath (Join-Path $build $name) -Destination $staging
}
foreach ($name in @('LICENSE','FORK_NOTES.md')) { Copy-Item -LiteralPath (Join-Path $root $name) -Destination $staging }
$files = @(Get-ChildItem -LiteralPath $staging -File | Sort-Object Name | ForEach-Object {
    [ordered]@{name=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
$manifest = [ordered]@{version=$version;repository='allenyllee/PlexServerAutoUpdater';commit=$commit;files=$files}
$manifestPath = Join-Path $OutputDirectory 'manifest.json'
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 5).Replace("`r`n","`n")+"`n",$utf8)
Copy-Item -LiteralPath $manifestPath -Destination $staging
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$zipPath = Join-Path $OutputDirectory "psupdate-$Tag-windows-net48.zip"
$stream = [IO.File]::Open($zipPath,[IO.FileMode]::CreateNew)
$zip = New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
try {
    foreach ($file in @(Get-ChildItem -LiteralPath $staging -File | Sort-Object Name)) {
        $entry = $zip.CreateEntry($file.Name,[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
        $source = [IO.File]::OpenRead($file.FullName)
        $destination = $entry.Open()
        try { $source.CopyTo($destination) } finally { $source.Dispose(); $destination.Dispose() }
    }
} finally { $zip.Dispose(); $stream.Dispose() }
$checksums = @($zipPath,$manifestPath) | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant(),[IO.Path]::GetFileName($_)
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'),($checksums -join "`n")+"`n",$utf8)
Write-Output "Release package created: $zipPath"
