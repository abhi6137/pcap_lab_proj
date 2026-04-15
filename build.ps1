$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir = Join-Path $root "bin"

function Get-MsvcCcbin {
    $candidateRoots = @(
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC"
    )

    foreach ($msvcRoot in $candidateRoots) {
        if (-not (Test-Path $msvcRoot)) {
            continue
        }

        $latest = Get-ChildItem $msvcRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($null -eq $latest) {
            continue
        }

        $ccbin = Join-Path $latest.FullName "bin\Hostx64\x64"
        if (Test-Path (Join-Path $ccbin "cl.exe")) {
            return $ccbin
        }
    }

    return $null
}

function Get-NvccExecutable {
    $nvccCommand = Get-Command nvcc -ErrorAction SilentlyContinue
    if ($null -ne $nvccCommand) {
        return $nvccCommand.Source
    }

    $cudaRoot = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
    if (Test-Path $cudaRoot) {
        $versions = Get-ChildItem $cudaRoot -Directory | Sort-Object Name -Descending
        foreach ($versionDir in $versions) {
            $candidate = Join-Path $versionDir.FullName "bin\nvcc.exe"
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }

    return $null
}

if (-not (Get-Command gcc -ErrorAction SilentlyContinue)) {
    throw "gcc is required but not found in PATH."
}

$nvccExe = Get-NvccExecutable
if ($null -eq $nvccExe) {
    throw "nvcc is required but was not found in PATH or default CUDA installation folders."
}

New-Item -ItemType Directory -Force -Path $binDir | Out-Null

Write-Host "Building CPU executable..."
gcc (Join-Path $root "core/cpu_blur.c") (Join-Path $root "core/image_io.c") -O3 -std=c11 -o (Join-Path $binDir "cpu_blur.exe")
if ($LASTEXITCODE -ne 0) {
    throw "CPU build failed."
}

Write-Host "Building GPU executable..."
$ccbin = Get-MsvcCcbin
if ($null -eq $ccbin) {
    throw "MSVC cl.exe not found. Install Visual Studio Build Tools with the C++ workload."
}

& $nvccExe (Join-Path $root "core/gpu_blur.cu") (Join-Path $root "core/image_io.c") -O3 -ccbin $ccbin -o (Join-Path $binDir "gpu_blur.exe")
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
