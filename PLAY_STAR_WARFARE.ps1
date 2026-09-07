param(
    [switch]$Editor
)

$ErrorActionPreference = "Stop"
$projectPath = $PSScriptRoot
$portableGodot = Join-Path $PSScriptRoot ".tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$portableGodotConsole = Join-Path $PSScriptRoot ".tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"

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
    # Finish imports before the GUI starts. Godot can otherwise try to build
    # previews while the initial reimport is still changing texture settings,
    # which has caused repeatable access-violation crashes in this large project.
    $importer = if (Test-Path -LiteralPath $portableGodotConsole) { $portableGodotConsole } else { $godot }
    & $importer --headless --path $projectPath --import
    if ($LASTEXITCODE -ne 0) {
        throw "Godot resource import failed with exit code $LASTEXITCODE"
    }

    $editorArgs = @("--editor", "--path", $projectPath)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        if ([System.Windows.Forms.Screen]::AllScreens.Count -eq 1) {
            # A floating game view saved on a disconnected second monitor makes
            # Godot 4.7 query screen 1 even when Windows only exposes screen 0.
            $layoutPath = Join-Path $projectPath ".godot\editor\editor_layout.cfg"
            if (Test-Path -LiteralPath $layoutPath) {
                $layout = [IO.File]::ReadAllText($layoutPath)
                $repairedLayout = $layout -replace '(?m)^floating_window_screen=\d+$', 'floating_window_screen=0'
                if ($repairedLayout -ne $layout) {
                    [IO.File]::WriteAllText($layoutPath, $repairedLayout)
                }
            }
            $editorArgs += @("--screen", "0", "--single-window")
        }
    } catch {
        Write-Warning "Could not validate the saved editor monitor layout: $($_.Exception.Message)"
    }

    & $godot @editorArgs
} else {
    & $godot --path $projectPath
}
