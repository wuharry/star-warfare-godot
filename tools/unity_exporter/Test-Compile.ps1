[CmdletBinding()]
param(
    [string]$UnityDataPath = 'C:\Program Files\Unity\Hub\Editor\6000.1.10f1\Editor\Data'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$UnityDataPath = [IO.Path]::GetFullPath($UnityDataPath)
$compiler = Join-Path $UnityDataPath 'DotNetSdkRoslyn\csc.dll'
$netStandard = Join-Path $UnityDataPath 'NetStandard\ref\2.1.0'
$managed = Join-Path $UnityDataPath 'Managed'

if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "Unity Roslyn compiler was not found below '$UnityDataPath'."
}
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'dotnet is required for the license-independent compile check.'
}

$references = @(
    Get-ChildItem -LiteralPath $netStandard -Filter '*.dll' -File | ForEach-Object { $_.FullName }
) + @(
    (Join-Path $managed 'UnityEngine.dll'),
    (Join-Path $managed 'UnityEditor.dll')
) + @(
    Get-ChildItem -LiteralPath (Join-Path $managed 'UnityEngine') -Filter '*.dll' -File | ForEach-Object { $_.FullName }
)

$outputAssembly = Join-Path ([IO.Path]::GetTempPath()) ("LegacyObjBatchExporter-compilecheck-{0}.dll" -f [Guid]::NewGuid().ToString('N'))
$arguments = @(
    $compiler,
    '/nologo',
    '/target:library',
    '/langversion:latest',
    '/nostdlib+',
    "/out:$outputAssembly"
) + @($references | ForEach-Object { "/reference:$_" }) + @(
    (Join-Path $PSScriptRoot 'LegacyObjBatchExporter.cs')
)

try {
    & dotnet @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "C# compile check failed with exit code $LASTEXITCODE."
    }
    Write-Host 'LegacyObjBatchExporter.cs compiled successfully against the Unity 6000.1.10f1 editor assemblies.'
}
finally {
    if (Test-Path -LiteralPath $outputAssembly -PathType Leaf) {
        Remove-Item -LiteralPath $outputAssembly -Force
    }
}
