param(
    [switch]$Editor
)

$ErrorActionPreference = "Stop"
$projectPath = $PSScriptRoot
$portableGodot = Join-Path $PSScriptRoot ".tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"

if (Test-Path -LiteralPath $portableGodot) {
    $godot = $portableGodot
} else {
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "Godot 4.7.2 was not found. Install Godot 4.7+ or place it at $portableGodot"
    }
    $godot = $command.Source
}

$godotVersion = (& $godot --version | Select-Object -First 1).Trim()
if (-not $godotVersion.StartsWith("4.7.")) {
    throw "This restoration is pinned to Godot 4.7.x, but '$godot' is $godotVersion. Run UPGRADE_TO_GODOT_4_7.bat first."
}

if ($Editor) {
    & $godot --editor --path $projectPath
} else {
    & $godot --path $projectPath
}
