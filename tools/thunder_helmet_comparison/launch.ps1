param([ValidateSet('sw2', 'prototype')][string]$Helmet = 'sw2')
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$godotBinary = Join-Path $projectRoot '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godotBinary)) { throw "Godot not found: $godotBinary" }
& $godotBinary --path $projectRoot -- "--thunder-helmet=$Helmet"
exit $LASTEXITCODE
