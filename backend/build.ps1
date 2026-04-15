$ErrorActionPreference = "Stop"

$rootBuildScript = Join-Path $PSScriptRoot "..\build.ps1"

if (-not (Test-Path $rootBuildScript)) {
    throw "Could not find root build script at $rootBuildScript"
}

& $rootBuildScript