[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Tag,[Parameter(Mandatory=$true)][string]$AssetDirectory)
$ErrorActionPreference = 'Stop'
if ($Tag -notmatch '^v\d+\.\d+\.\d+\.\d+$') { throw 'Invalid release tag.' }
if (-not $env:GITHUB_REPOSITORY -or -not $env:GH_TOKEN) { throw 'GitHub repository and token are required.' }
function Invoke-Gh([string[]]$GhArguments) {
    $output = & gh @GhArguments
    if ($LASTEXITCODE -ne 0) { throw ('GitHub CLI failed: '+($GhArguments[0..1] -join ' ')) }
    $output
}
$repository = $env:GITHUB_REPOSITORY
$assets = @(
    (Join-Path $AssetDirectory "psupdate-$Tag-windows-net48.zip"),
    (Join-Path $AssetDirectory 'SHA256SUMS.txt'),
    (Join-Path $AssetDirectory 'manifest.json')
)
foreach ($asset in $assets) { if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) { throw "Missing release asset: $asset" } }
$releaseJson = & gh release view $Tag --repo $repository --json assets,isDraft 2>$null
if ($LASTEXITCODE -ne 0) {
    Invoke-Gh -GhArguments @('release','create',$Tag,'--repo',$repository,'--verify-tag','--draft','--title',"Plex Server Auto Updater $Tag",'--generate-notes') | Out-Null
    $releaseJson = Invoke-Gh -GhArguments @('release','view',$Tag,'--repo',$repository,'--json','assets,isDraft')
}
$release = ($releaseJson -join "`n") | ConvertFrom-Json
foreach ($asset in $assets) {
    $name = [IO.Path]::GetFileName($asset)
    if (@($release.assets | Where-Object name -eq $name).Count -gt 0) {
        $comparison = Join-Path ([IO.Path]::GetTempPath()) ('plex-release-'+[guid]::NewGuid())
        New-Item -ItemType Directory -Path $comparison | Out-Null
        Invoke-Gh -GhArguments @('release','download',$Tag,'--repo',$repository,'--pattern',$name,'--dir',$comparison) | Out-Null
        if ((Get-FileHash -LiteralPath $asset).Hash -ne (Get-FileHash -LiteralPath (Join-Path $comparison $name)).Hash) {
            throw "Published asset differs: $name. Publish a new version rather than overwrite it."
        }
        Write-Output "Verified existing release asset: $name"
    } else {
        Invoke-Gh -GhArguments @('release','upload',$Tag,$asset,'--repo',$repository) | Out-Null
    }
}
if ($release.isDraft) { Invoke-Gh -GhArguments @('release','edit',$Tag,'--repo',$repository,'--draft=false') | Out-Null }
Write-Output "Release verified: https://github.com/$repository/releases/tag/$Tag"
