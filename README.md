# Gaussian Blur Using CUDA with Tiling Optimization and Web Interface

This mini project demonstrates three implementations of Gaussian blur:

1. CPU Gaussian blur in C (sequential)
2. CUDA Gaussian blur using global memory (basic GPU)
3. CUDA Gaussian blur using shared-memory tiling with halo region (optimized GPU)

The project also includes a web interface and backend API to run each mode and compare performance.

The image processing pipeline applies the 3x3 Gaussian blur twice, which keeps the blur Gaussian in shape while producing a more noticeable result.

## Project Structure

core/
- cpu_blur.c
- gpu_blur.cu
- image_io.c
- image_io.h

backend/
- server.js
- package.json

frontend/
- index.html
- styles.css
- app.js

Other files:
- build.ps1 (Windows build helper)
- Makefile (Linux/macOS build helper)

## CUDA Tiling Summary

- Block size: 16x16
- Convolution kernel: 3x3 Gaussian, applied twice for stronger blur
- Shared tile size: (BLOCK_SIZE + 2) x (BLOCK_SIZE + 2)
- Extra border is the halo region required by neighboring pixels
- __syncthreads() ensures all tile and halo values are available before convolution

Why this helps:
- Shared memory has much lower latency than global memory.
- Each pixel neighborhood is reused by nearby threads inside the block.
- Central global loads are coalesced across adjacent threads.

## Build Instructions

### Windows (PowerShell)

From project root:

1. Run `./build.ps1`

This builds:
- bin/cpu_blur.exe
- bin/gpu_blur.exe

And installs backend dependencies in backend/node_modules.

### Linux/macOS

From project root:

1. Run `make`
2. Install backend dependencies:
   `cd backend && npm install`

## Run Backend + Frontend

From project root:

1. Start server:
   `cd backend && npm start`
2. Open browser:
   `http://localhost:3000`

Frontend and backend are served by the same Express app.

## Command-Line Core Testing

From project root:

CPU:
- `bin/cpu_blur.exe input.pgm out_cpu.pgm`

GPU Basic:
- `bin/gpu_blur.exe gpu_basic input.pgm out_basic.pgm --verify`

GPU Tiled:
- `bin/gpu_blur.exe gpu_tiled input.pgm out_tiled.pgm --verify`

Printed output includes:
- MODE
- TIME_MS
- VERIFY_MAE (when --verify is used)

## Backend API

### POST /api/blur

Form fields:
- image: uploaded PGM image file
- mode: cpu | gpu_basic | gpu_tiled

Returns:
- output image pixels
- execution time
- CPU baseline time
- speedup vs CPU

### POST /api/benchmark

Form fields:
- image: uploaded PGM image file

Returns:
- CPU time
- GPU basic time
- GPU tiled time
- speedups (CPU/GPU)
- MAE quality checks vs CPU reference
- whether tiled is faster than basic for the tested image

## Output Similarity and Performance Checks

The benchmark endpoint verifies correctness and performance by:

1. Running CPU, GPU Basic, and GPU Tiled
2. Computing MAE between CPU output and each GPU output
3. Reporting speedups:
   - Speedup basic = CPU / GPU_basic
   - Speedup tiled = CPU / GPU_tiled

For larger images, the tiled kernel should typically outperform the basic GPU kernel.
