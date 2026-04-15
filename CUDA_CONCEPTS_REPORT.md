# CUDA Concepts Used in This Project

This document lists the CUDA concepts implemented in this project, where they appear, and why they were used.

## 1) CUDA Kernel Functions (`__global__`)
- Where used:
  - `core/gpu_blur.cu:46` (`gaussianBlurBasic`)
  - `core/gpu_blur.cu:71` (`gaussianBlurTiled`)
- Why used:
  - Kernel functions run on the GPU and are launched from CPU code.
  - Each thread computes one output pixel, enabling massive data-parallel execution of Gaussian blur.

## 2) Thread Hierarchy and Launch Configuration (`dim3`, `blockIdx`, `threadIdx`, `blockDim`)
- Where used:
  - `core/gpu_blur.cu:47-48` and `core/gpu_blur.cu:74-75` (pixel coordinates from block/thread indices)
  - `core/gpu_blur.cu:255-257` (`dim3 block`, `dim3 grid`)
  - `core/gpu_blur.cu:262`, `core/gpu_blur.cu:264`, `core/gpu_blur.cu:266`, `core/gpu_blur.cu:268` (kernel launches)
- Why used:
  - Maps image pixels to CUDA threads in a 2D layout.
  - Grid/block sizing ensures the whole image is covered efficiently.

## 3) Device Function (`__device__`) and Inlining (`__forceinline__`)
- Where used:
  - `core/gpu_blur.cu:31` (`clamp_device`)
- Why used:
  - Reusable helper for boundary-safe indexing on the GPU.
  - Inlining reduces function-call overhead inside kernels.

## 4) Constant Memory (`__constant__`) + `cudaMemcpyToSymbol`
- Where used:
  - `core/gpu_blur.cu:29` (`D_GAUSSIAN_3X3` in constant memory)
  - `core/gpu_blur.cu:245` (`cudaMemcpyToSymbol`)
- Why used:
  - The 3x3 Gaussian weights are read-only and shared by all threads.
  - Constant memory is efficient for broadcasting small read-only data.

## 5) Shared Memory Tiling (`__shared__`) with Halo Region
- Where used:
  - `core/gpu_blur.cu:72` (shared tile declaration)
  - `core/gpu_blur.cu:86-128` (center + halo loads)
- Why used:
  - Reduces repeated global-memory reads for neighboring pixels.
  - Halo stores border neighbors required by 3x3 convolution.
  - Improves performance by reusing data within a block.

## 6) Intra-block Synchronization (`__syncthreads()`)
- Where used:
  - `core/gpu_blur.cu:130`
- Why used:
  - Ensures all threads finished loading tile/halo values before convolution starts.
  - Prevents race conditions and incorrect reads from shared memory.

## 7) CUDA Global Memory Allocation (`cudaMalloc`) and Cleanup (`cudaFree`)
- Where used:
  - `core/gpu_blur.cu:246-248` (`d_input`, `d_temp`, `d_output`)
  - `core/gpu_blur.cu:282-284`, `core/gpu_blur.cu:306-308` (cleanup)
- Why used:
  - Device buffers are required for GPU computation.
  - Separate temp/output buffers support two blur passes.

## 8) Host-Device Data Transfers (`cudaMemcpy`)
- Where used:
  - `core/gpu_blur.cu:250` (Host to Device input copy)
  - `core/gpu_blur.cu:276` (Device to Host output copy)
- Why used:
  - Input image must be copied to GPU memory before kernel execution.
  - Final blurred image must be copied back for file output and API response.

## 9) GPU Timing with CUDA Events (`cudaEventCreate`, `cudaEventRecord`, `cudaEventSynchronize`, `cudaEventElapsedTime`)
- Where used:
  - `core/gpu_blur.cu:208-209` (event handles)
  - `core/gpu_blur.cu:252-253` (event creation)
  - `core/gpu_blur.cu:259` and `core/gpu_blur.cu:272` (start/stop record)
  - `core/gpu_blur.cu:273-274` (synchronize and elapsed time)
- Why used:
  - Measures GPU execution time accurately on-device.
  - Needed for performance comparison (CPU vs GPU modes).

## 10) Runtime Error Checking (`cudaGetLastError`, `cudaGetErrorString`) via macro
- Where used:
  - `core/gpu_blur.cu:14-21` (`CUDA_CHECK` macro)
  - `core/gpu_blur.cu:263`, `core/gpu_blur.cu:267`, `core/gpu_blur.cu:271` (post-launch checks)
- Why used:
  - Detects API and kernel launch/runtime failures early.
  - Provides readable diagnostics for debugging and grading reliability.

## 11) Basic vs Optimized GPU Modes (Conceptual CUDA Optimization Study)
- Where used:
  - `core/gpu_blur.cu:46` (basic global-memory kernel)
  - `core/gpu_blur.cu:71` (tiled shared-memory kernel)
  - `backend/server.js:29` (mode options), `backend/server.js:299-300` (benchmark runs)
- Why used:
  - Demonstrates CUDA optimization progression.
  - Enables measurable comparison between naive and optimized GPU memory access patterns.

## 12) CUDA Toolchain Integration (`nvcc`) in Build System
- Where used:
  - `build.ps1:31-57` (find and validate `nvcc`)
  - `build.ps1:74` (compile CUDA target)
  - `Makefile:2`, `Makefile:29-30` (`NVCC` and GPU target build rule)
- Why used:
  - `nvcc` is required to compile `.cu` CUDA source.
  - Makes the CUDA executable reproducible across environments.

## CUDA Concepts Not Used (Useful to Mention to Professor)
These are common CUDA topics but they are not implemented in this project:
- CUDA streams / asynchronous overlap (`cudaMemcpyAsync`, multiple streams)
- Unified memory (`cudaMallocManaged`)
- Pinned host memory
- Texture/surface memory
- Atomics and reductions
- Multi-GPU execution

This is acceptable because the project goal is focused on single-image blur acceleration and shared-memory tiling optimization fundamentals.
