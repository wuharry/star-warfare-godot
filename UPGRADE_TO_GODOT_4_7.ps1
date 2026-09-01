param(
    [switch]$NoEditor
)

$ErrorActionPreference = "Stop"
$projectPath = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$godot = Join-Path $projectPath ".tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"

if (-not (Test-Path -LiteralPath $godot)) {
    throw "The bundled Godot 4.7.2 editor was not found at $godot"
}

# Import caches are engine-version-specific. Refuse to move the cache while a
# 4.5/4.7 editor or game process still has this project open.
$runningProjectEngines = @(
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^(godot|godot_v.*|starwarfare)\.exe$' -and
            -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
            (($_.CommandLine -replace '/', '\') -like "*$projectPath*")
        }
)
if ($runningProjectEngines.Count -gt 0) {
    $processList = ($runningProjectEngines | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" }) -join ", "
    throw "Close every Godot editor/game window for this project, then run this upgrader again. Still open: $processList"
}

$godotVersion = (& $godot --version | Select-Object -First 1).Trim()
if (-not $godotVersion.StartsWith("4.7.")) {
    throw "Expected Godot 4.7.x, found $godotVersion"
}

$cachePath = [IO.Path]::GetFullPath((Join-Path $projectPath ".godot"))
if ([IO.Path]::GetDirectoryName($cachePath).TrimEnd('\') -ne $projectPath) {
    throw "Refusing to move an import cache outside the project: $cachePath"
}

if (Test-Path -LiteralPath $cachePath) {
    $backupPath = [IO.Path]::GetFullPath((Join-Path $projectPath (".godot-4.5-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))))
    if ([IO.Path]::GetDirectoryName($backupPath).TrimEnd('\') -ne $projectPath) {
        throw "Refusing to create a cache backup outside the project: $backupPath"
    }
    Move-Item -LiteralPath $cachePath -Destination $backupPath
    Write-Output "Previous import cache moved to: $backupPath"
}

& $godot --headless --path $projectPath --import
if ($LASTEXITCODE -ne 0) {
    throw "Godot 4.7 resource import failed with exit code $LASTEXITCODE"
}

Write-Output "Godot 4.7.2 upgrade/import complete. Player and enemy animations were rebuilt with one engine version."
if (-not $NoEditor) {
    $editor = Join-Path $projectPath ".tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
    Start-Process -FilePath $editor -ArgumentList @("--editor", "--path", $projectPath)
}
