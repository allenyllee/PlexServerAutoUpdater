[CmdletBinding()]
param([switch]$Test)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -eq 'Core') { throw 'Run build.ps1 with Windows PowerShell 5.1 (powershell.exe).' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem,System.Windows.Forms
$packages = Join-Path $PSScriptRoot 'packages'
New-Item -ItemType Directory -Path $packages -Force | Out-Null
foreach ($package in @(@('microsoft.net.compilers.toolset','4.8.0'),@('microsoft.netframework.referenceassemblies.net48','1.0.3'),@('newtonsoft.json','13.0.3'))) {
    $id,$version = $package
    $directory = Join-Path $packages "$id.$version"
    if (-not (Test-Path -LiteralPath $directory)) {
        $archive = Join-Path $packages "$id.$version.nupkg"
        & curl.exe --fail --location --silent --show-error --connect-timeout 15 --max-time 180 --output $archive "https://api.nuget.org/v3-flatcontainer/$id/$version/$id.$version.nupkg"
        if ($LASTEXITCODE -ne 0) { throw "Could not download NuGet package $id.$version." }
        [IO.Compression.ZipFile]::ExtractToDirectory($archive,$directory)
    }
}
$compiler = Join-Path $packages 'microsoft.net.compilers.toolset.4.8.0\tasks\net472\csc.exe'
$framework = Join-Path $packages 'microsoft.netframework.referenceassemblies.net48.1.0.3\build\.NETFramework\v4.8'
$json = Join-Path $packages 'newtonsoft.json.13.0.3\lib\net45\Newtonsoft.Json.dll'
$outputDirectory = Join-Path $PSScriptRoot 'bin\Release'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$resources = Join-Path $outputDirectory 'TE.Plex.MainForm.resources'
$reader = New-Object System.Resources.ResXResourceReader((Join-Path $PSScriptRoot 'MainForm.resx'))
$writer = New-Object System.Resources.ResourceWriter($resources)
try { foreach ($entry in $reader) { $writer.AddResource($entry.Key,$entry.Value) }; $writer.Generate() }
finally { $writer.Dispose(); $reader.Dispose() }
[xml]$project = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'PlexServerAutoUpdater.csproj')
$sources = @($project.Project.ItemGroup.Compile | Where-Object Include | ForEach-Object { Join-Path $PSScriptRoot $_.Include })
$references = @('mscorlib','System','System.Core','System.Configuration','System.Data','System.Data.DataSetExtensions','System.Drawing','System.Management','System.Net.Http','System.ServiceProcess','System.Windows.Forms','System.Xml','System.Xml.Linq')
$arguments = @('/nologo','/noconfig','/nostdlib+','/langversion:7.3','/deterministic+','/optimize+','/target:winexe','/platform:x86',('/out:'+(Join-Path $outputDirectory 'psupdate.exe')),('/resource:'+$resources+',TE.Plex.MainForm.resources'))
$arguments += $references | ForEach-Object { '/reference:'+(Join-Path $framework ($_.ToString()+'.dll')) }
$arguments += '/reference:'+$json
& $compiler @arguments @sources
if ($LASTEXITCODE -ne 0) { throw 'Application compilation failed.' }
Copy-Item -LiteralPath $json -Destination $outputDirectory
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'app.config') -Destination (Join-Path $outputDirectory 'psupdate.exe.config')
if ($Test) {
    $testArguments = @('/nologo','/noconfig','/nostdlib+','/langversion:7.3','/target:exe','/platform:x86',('/out:'+(Join-Path $outputDirectory 'RegressionTests.exe')))
    $testArguments += $references | ForEach-Object { '/reference:'+(Join-Path $framework ($_.ToString()+'.dll')) }
    $testArguments += @(('/reference:'+$json),('/reference:'+(Join-Path $outputDirectory 'psupdate.exe')))
    & $compiler @testArguments (Join-Path $PSScriptRoot 'tests\RegressionTests.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed.' }
    & (Join-Path $outputDirectory 'RegressionTests.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Regression tests failed.' }
}
Write-Output "Build complete: $outputDirectory"
