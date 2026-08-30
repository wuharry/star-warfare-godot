[CmdletBinding()]
param(
    [string]$SourceProject = (Join-Path $PSScriptRoot '..\..\..'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\..\assets\models\legacy_unity'),
    [string]$UnityPath = 'C:\Program Files\Unity\Hub\Editor\6000.1.10f1\Editor\Unity.exe',
    [switch]$KeepTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceProject = [IO.Path]::GetFullPath($SourceProject)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)

if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) {
    throw "Unity 6000.1.10f1 was not found at '$UnityPath'. Pass -UnityPath explicitly."
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$workPath = Join-Path $tempBase ("star-warfare-unity-exporter-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString('N'))
$tempExport = Join-Path $workPath 'Export'
$logDirectory = Join-Path $PSScriptRoot 'logs'
[IO.Directory]::CreateDirectory($logDirectory) | Out-Null
$logPath = Join-Path $logDirectory ("unity-export-{0}.log" -f [DateTime]::Now.ToString('yyyyMMdd-HHmmss'))

try {
    & (Join-Path $PSScriptRoot 'Prepare-IsolatedProject.ps1') -ProjectPath $workPath -SourceProject $SourceProject

    $unityArguments = @(
        '-batchmode',
        '-nographics',
        '-quit',
        '-projectPath', $workPath,
        '-executeMethod', 'LegacyObjBatchExporter.ExportAll',
        '-exportOutput', $tempExport,
        '-logFile', $logPath
    )

    Write-Host "Running isolated Unity export. Log: $logPath"
    $unityProcess = Start-Process -FilePath $UnityPath -ArgumentList $unityArguments -PassThru -Wait -WindowStyle Hidden
    if ($unityProcess.ExitCode -ne 0) {
        throw "Unity batch export failed with exit code $($unityProcess.ExitCode). See '$logPath'."
    }

    & (Join-Path $PSScriptRoot 'Validate-Exports.ps1') -ExportPath $tempExport

    [IO.Directory]::CreateDirectory($OutputPath) | Out-Null
    Copy-Item -Path (Join-Path $tempExport '*') -Destination $OutputPath -Recurse -Force
    & (Join-Path $PSScriptRoot 'Validate-Exports.ps1') -ExportPath $OutputPath
    Write-Host "Export completed: $OutputPath"
}
finally {
    if ($KeepTemp) {
        Write-Host "Kept isolated Unity project: $workPath"
    }
    elseif (Test-Path -LiteralPath $workPath) {
        $resolvedWork = [IO.Path]::GetFullPath($workPath)
        $safePrefix = "$tempBase\star-warfare-unity-exporter-"
        if (-not $resolvedWork.StartsWith($safePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unexpected temporary path '$resolvedWork'."
        }
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    }
}
