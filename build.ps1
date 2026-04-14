$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir = Join-Path $root "bin"

if (-not (Get-Command gcc -ErrorAction SilentlyContinue)) {
    throw "gcc is required but not found in PATH."
}

if (-not (Get-Command nvcc -ErrorAction SilentlyContinue)) {
    throw "nvcc is required but not found in PATH."
}

New-Item -ItemType Directory -Force -Path $binDir | Out-Null

Write-Host "Building CPU executable..."
gcc (Join-Path $root "core/cpu_blur.c") (Join-Path $root "core/image_io.c") -O3 -std=c11 -o (Join-Path $binDir "cpu_blur.exe")
if ($LASTEXITCODE -ne 0) {
    throw "CPU build failed."
}

Write-Host "Building GPU executable..."
nvcc (Join-Path $root "core/gpu_blur.cu") (Join-Path $root "core/image_io.c") -O3 -o (Join-Path $binDir "gpu_blur.exe")
if ($LASTEXITCODE -ne 0) {
    throw "GPU build failed."
}

Write-Host "Installing backend dependencies..."
Push-Location (Join-Path $root "backend")
npm install
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "npm install failed in backend/."
}
Pop-Location

Write-Host "Build completed successfully."
