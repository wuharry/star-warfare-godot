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

if ($Editor) {
    & $godot --editor --path $projectPath
} else {
    & $godot --path $projectPath
}
