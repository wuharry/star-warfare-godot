[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [string]$SourceProject = (Join-Path $PSScriptRoot '..\..\..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceProject = [IO.Path]::GetFullPath($SourceProject)
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$sourceAssets = Join-Path $SourceProject 'Assets'

if (-not (Test-Path -LiteralPath (Join-Path $sourceAssets 'Scenes\Level1.unity') -PathType Leaf)) {
    throw "The legacy Unity project was not found at '$SourceProject'."
}

$targetAssets = Join-Path $ProjectPath 'Assets'
$legacyAssets = Join-Path $targetAssets 'Legacy'
$editorAssets = Join-Path $targetAssets 'Editor'
$projectSettings = Join-Path $ProjectPath 'ProjectSettings'
$packages = Join-Path $ProjectPath 'Packages'

@($legacyAssets, $editorAssets, $projectSettings, $packages) | ForEach-Object {
    [IO.Directory]::CreateDirectory($_) | Out-Null
}

# These are the only authored roots. Everything else is found by following Unity GUIDs.
$rootAssets = @(
    'Scenes\Level1.unity',
    'Resources\enemy\bug01.prefab',
    'Resources\weapon\gun00.prefab',
    'Resources\weapon\gun22.prefab',
    'Resources\weapon\gun23.prefab',
    'Resources\weapon\gun36.prefab',
    'Resources\weapon\gun37.prefab',
    'Resources\avatar\Player.prefab',
    'Resources\avatar\01\Body.prefab',
    'Resources\avatar\01\Hand.prefab',
    'Resources\avatar\01\Foot.prefab',
    'Resources\avatar\01\Head.prefab',
    'Resources\avatar\01\Bag.prefab'
)

$guidIndex = @{}
Get-ChildItem -LiteralPath $sourceAssets -Filter '*.meta' -File -Recurse | ForEach-Object {
    $metaText = [IO.File]::ReadAllText($_.FullName)
    $match = [regex]::Match($metaText, '(?m)^guid:\s*([0-9a-fA-F]{32})\s*$')
    if ($match.Success) {
        $assetPath = $_.FullName.Substring(0, $_.FullName.Length - 5)
        if (Test-Path -LiteralPath $assetPath -PathType Leaf) {
            $guidIndex[$match.Groups[1].Value.ToLowerInvariant()] = $assetPath
        }
    }
}

$excludedExtensions = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@('.cs', '.js', '.boo', '.dll', '.pdb', '.mdb', '.asmdef', '.asmref', '.shader', '.cginc', '.compute', '.aar', '.jar', '.so', '.bundle') |
    ForEach-Object { [void]$excludedExtensions.Add($_) }

$textExtensions = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@('.unity', '.prefab', '.asset', '.mat', '.anim', '.controller', '.overrideController', '.mask', '.playable', '.renderTexture', '.physicMaterial', '.physicsMaterial2D', '.guiskin', '.fontsettings', '.meta') |
    ForEach-Object { [void]$textExtensions.Add($_) }

$queue = [Collections.Generic.Queue[string]]::new()
foreach ($relativePath in $rootAssets) {
    $fullPath = Join-Path $sourceAssets $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Required source asset is missing: Assets/$($relativePath.Replace('\', '/'))"
    }
    $queue.Enqueue([IO.Path]::GetFullPath($fullPath))
}

$visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$copied = [Collections.Generic.List[string]]::new()
$skipped = [Collections.Generic.List[string]]::new()

function Add-GuidDependencies {
    param([string]$Text)

    foreach ($match in [regex]::Matches($Text, 'guid:\s*([0-9a-fA-F]{32})')) {
        $guid = $match.Groups[1].Value.ToLowerInvariant()
        if ($guidIndex.ContainsKey($guid)) {
            $queue.Enqueue($guidIndex[$guid])
        }
    }
}

while ($queue.Count -gt 0) {
    $sourcePath = [IO.Path]::GetFullPath($queue.Dequeue())
    if (-not $visited.Add($sourcePath)) {
        continue
    }

    $extension = [IO.Path]::GetExtension($sourcePath)
    if ($excludedExtensions.Contains($extension)) {
        $skipped.Add($sourcePath.Substring($sourceAssets.Length + 1).Replace('\', '/'))
        continue
    }

    $relativePath = $sourcePath.Substring($sourceAssets.Length + 1)
    $destinationPath = Join-Path $legacyAssets $relativePath
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destinationPath)) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force

    $sourceMeta = "$sourcePath.meta"
    if (Test-Path -LiteralPath $sourceMeta -PathType Leaf) {
        Copy-Item -LiteralPath $sourceMeta -Destination "$destinationPath.meta" -Force
    }
    $copied.Add($relativePath.Replace('\', '/'))

    if ($textExtensions.Contains($extension)) {
        try {
            Add-GuidDependencies -Text ([IO.File]::ReadAllText($sourcePath))
        }
        catch {
            Write-Warning "Could not scan GUIDs in '$relativePath': $($_.Exception.Message)"
        }
    }
    if (Test-Path -LiteralPath $sourceMeta -PathType Leaf) {
        Add-GuidDependencies -Text ([IO.File]::ReadAllText($sourceMeta))
    }
}

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'LegacyObjBatchExporter.cs') -Destination (Join-Path $editorAssets 'LegacyObjBatchExporter.cs') -Force

@'
m_EditorVersion: 6000.1.10f1
m_EditorVersionWithRevision: 6000.1.10f1 (3c681a6c22ff)
'@ | Set-Content -LiteralPath (Join-Path $projectSettings 'ProjectVersion.txt') -Encoding utf8NoBOM

@'
{
  "dependencies": {}
}
'@ | Set-Content -LiteralPath (Join-Path $packages 'manifest.json') -Encoding utf8NoBOM

$manifest = [ordered]@{
    source_project = $SourceProject
    generated_utc = [DateTime]::UtcNow.ToString('o')
    copied_count = $copied.Count
    skipped_code_count = $skipped.Count
    roots = $rootAssets | ForEach-Object { $_.Replace('\', '/') }
    copied = @($copied | Sort-Object)
    skipped_code_and_shaders = @($skipped | Sort-Object)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $ProjectPath 'isolated-copy-manifest.json') -Encoding utf8NoBOM

Write-Host "Prepared isolated Unity project: $ProjectPath"
Write-Host "Copied $($copied.Count) GUID-linked assets; skipped $($skipped.Count) code/shader binaries."
