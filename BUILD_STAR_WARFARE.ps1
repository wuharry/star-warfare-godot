param(
    [ValidateSet("All", "Windows", "Android")]
    [string]$Target = "All"
)

$ErrorActionPreference = "Stop"
$projectPath = $PSScriptRoot
$godot = Join-Path $PSScriptRoot ".tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"
$androidSdk = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".tools\android-sdk"))

if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot 4.7.2 portable editor was not found at $godot"
}

# Finish source texture and model reimports before tests or exports consume the
# generated cache. This is especially important after replacing many assets at
# once, as an export should never mix old .ctex data with new source PNG files.
& $godot --headless --path $projectPath --import
if ($LASTEXITCODE -ne 0) { throw "Godot resource import failed with exit code $LASTEXITCODE" }

if ($Target -in @("All", "Windows")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $projectPath "builds\windows") | Out-Null
    & $godot --headless --path $projectPath --export-release "Windows Desktop" "builds/windows/StarWarfare.exe"
    if ($LASTEXITCODE -ne 0) { throw "Windows export failed with exit code $LASTEXITCODE" }
}

if ($Target -in @("All", "Android")) {
    if (-not (Test-Path -LiteralPath (Join-Path $androidSdk "platform-tools\adb.exe"))) {
        throw "Local Android SDK was not found at $androidSdk"
    }
    if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        throw "JAVA_HOME must point to JDK 17 or newer"
    }
    $env:STAR_WARFARE_ANDROID_SDK = $androidSdk
    $env:STAR_WARFARE_JAVA_SDK = $env:JAVA_HOME
    $env:STAR_WARFARE_CONFIGURE_ONLY = "1"
    & $godot --headless --editor --path $projectPath
    if ($LASTEXITCODE -ne 0) { throw "Godot Android editor setup failed with exit code $LASTEXITCODE" }
    Remove-Item Env:STAR_WARFARE_CONFIGURE_ONLY -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Join-Path $projectPath "builds\android") | Out-Null
    & $godot --headless --path $projectPath --export-debug "Android" "builds/android/StarWarfare.apk"
    if ($LASTEXITCODE -ne 0) { throw "Android export failed with exit code $LASTEXITCODE" }
}

Write-Output "Build complete: $projectPath\builds"
