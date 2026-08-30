[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ExportPath = [IO.Path]::GetFullPath($ExportPath)

$required = @('level1_static', 'bug01', 'gun00')
$optional = @('player', 'armor01')
$results = [Collections.Generic.List[object]]::new()

foreach ($name in @($required + $optional)) {
    $objPath = Join-Path $ExportPath "$name.obj"
    if (-not (Test-Path -LiteralPath $objPath -PathType Leaf)) {
        if ($required -contains $name) {
            throw "Required export is missing: $objPath"
        }
        Write-Warning "Optional export is missing: $objPath"
        continue
    }

    $vertices = 0
    $uvs = 0
    $normals = 0
    $faces = 0
    $materialLibraries = [Collections.Generic.List[string]]::new()
    $usedMaterials = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    foreach ($line in [IO.File]::ReadLines($objPath)) {
        if ($line.StartsWith('v ')) { $vertices++ }
        elseif ($line.StartsWith('vt ')) { $uvs++ }
        elseif ($line.StartsWith('vn ')) { $normals++ }
        elseif ($line.StartsWith('f ')) {
            $faces++
            foreach ($token in $line.Substring(2).Split(' ', [StringSplitOptions]::RemoveEmptyEntries)) {
                $parts = $token.Split('/')
                $vertexIndex = 0
                if (-not [int]::TryParse($parts[0], [ref]$vertexIndex) -or $vertexIndex -lt 1 -or $vertexIndex -gt $vertices) {
                    throw "Invalid vertex index '$token' in '$objPath'."
                }
            }
        }
        elseif ($line.StartsWith('mtllib ')) { $materialLibraries.Add($line.Substring(7).Trim()) }
        elseif ($line.StartsWith('usemtl ')) { [void]$usedMaterials.Add($line.Substring(7).Trim()) }
    }

    if ($vertices -eq 0 -or $faces -eq 0) {
        throw "'$objPath' contains no usable geometry (v=$vertices, f=$faces)."
    }
    if ($materialLibraries.Count -eq 0) {
        throw "'$objPath' does not reference an MTL file."
    }

    $definedMaterials = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($library in $materialLibraries) {
        $mtlPath = Join-Path $ExportPath $library
        if (-not (Test-Path -LiteralPath $mtlPath -PathType Leaf)) {
            throw "Referenced material library is missing: $mtlPath"
        }
        foreach ($line in [IO.File]::ReadLines($mtlPath)) {
            if ($line.StartsWith('newmtl ')) {
                [void]$definedMaterials.Add($line.Substring(7).Trim())
            }
            elseif ($line.StartsWith('map_Kd ')) {
                $texturePath = Join-Path $ExportPath $line.Substring(7).Trim()
                if (-not (Test-Path -LiteralPath $texturePath -PathType Leaf)) {
                    throw "Referenced texture is missing: $texturePath"
                }
            }
        }
    }

    foreach ($material in $usedMaterials) {
        if (-not $definedMaterials.Contains($material)) {
            throw "OBJ '$objPath' uses undefined material '$material'."
        }
    }

    $results.Add([pscustomobject]@{
        Model = $name
        Vertices = $vertices
        Faces = $faces
        UVs = $uvs
        Normals = $normals
        Materials = $usedMaterials.Count
    })
}

$results | Format-Table -AutoSize
$results | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $ExportPath 'validation.json') -Encoding utf8NoBOM
Write-Host "Structural validation passed for $($results.Count) OBJ files."
