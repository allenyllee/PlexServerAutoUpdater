[CmdletBinding()]
param([string]$Tag='v0.2.2.0',[string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'artifacts' }
$assetNames = @("psupdate-$Tag-windows-net48.zip",'SHA256SUMS.txt','manifest.json')
$oldRepository,$oldToken = $env:GITHUB_REPOSITORY,$env:GH_TOKEN
$env:GITHUB_REPOSITORY = 'test/repository'
$env:GH_TOKEN = 'test-only-not-a-credential'
$global:releasePublisherTest = [pscustomobject]@{calls=(New-Object 'Collections.Generic.List[string]');mode='new';created=$false;assets=$assetNames;directory=$OutputDirectory}
function gh {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$GhArgs)
    $global:releasePublisherTest.calls.Add(($GhArgs -join ' '))
    $global:LASTEXITCODE = 0
    switch ($GhArgs[1]) {
        'view' {
            if ($global:releasePublisherTest.mode -eq 'new' -and -not $global:releasePublisherTest.created) { $global:LASTEXITCODE=1; return }
            $assets = @()
            if ($global:releasePublisherTest.mode -ne 'new') { $assets = @($global:releasePublisherTest.assets | ForEach-Object { @{name=$_} }) }
            @{assets=$assets;isDraft=($global:releasePublisherTest.mode -eq 'new')} | ConvertTo-Json -Depth 4 -Compress
        }
        'create' { $global:releasePublisherTest.created = $true }
        'download' {
            $name = $GhArgs[[Array]::IndexOf($GhArgs,'--pattern')+1]
            $directory = $GhArgs[[Array]::IndexOf($GhArgs,'--dir')+1]
            Copy-Item -LiteralPath (Join-Path $global:releasePublisherTest.directory $name) -Destination $directory
            if ($global:releasePublisherTest.mode -eq 'mismatch') { Add-Content -LiteralPath (Join-Path $directory $name) -Value 'changed' }
        }
        'upload' { if ($GhArgs -contains '--clobber') { throw 'Existing assets must not be overwritten.' } }
        'edit' { if ($GhArgs -notcontains '--draft=false') { throw 'Expected publication after uploads.' } }
        default { throw 'Unexpected GitHub CLI command.' }
    }
}
try {
    & (Join-Path $root 'scripts\publish-release.ps1') -Tag $Tag -AssetDirectory $OutputDirectory
    $uploads = @($global:releasePublisherTest.calls | Where-Object { $_ -like 'release upload *' })
    if ($uploads.Count -ne 3 -or $global:releasePublisherTest.calls[$global:releasePublisherTest.calls.Count-1] -notlike 'release edit *--draft=false') { throw 'Draft release did not upload all assets before publication.' }
    Write-Output 'PASS: new release verifies tag, uploads three assets, then publishes.'
    $global:releasePublisherTest.calls.Clear()
    $global:releasePublisherTest.mode = 'existing'
    & (Join-Path $root 'scripts\publish-release.ps1') -Tag $Tag -AssetDirectory $OutputDirectory
    if (@($global:releasePublisherTest.calls | Where-Object { $_ -like 'release upload *' -or $_ -like 'release edit *' }).Count) { throw 'Rerun modified an existing matching release.' }
    Write-Output 'PASS: matching release rerun only verifies existing assets.'
    $global:releasePublisherTest.mode = 'mismatch'
    $rejected = $false
    try { & (Join-Path $root 'scripts\publish-release.ps1') -Tag $Tag -AssetDirectory $OutputDirectory }
    catch { $rejected = $_.Exception.Message -like 'Published asset differs:*' }
    if (-not $rejected) { throw 'Changed published binaries were not rejected.' }
    Write-Output 'PASS: differing published assets are rejected without overwrite.'
} finally {
    $env:GITHUB_REPOSITORY,$env:GH_TOKEN = $oldRepository,$oldToken
    Remove-Variable releasePublisherTest -Scope Global -ErrorAction SilentlyContinue
}
