#include "image_io.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BLOCK_SIZE 16
#define KERNEL_RADIUS 1
#define KERNEL_WIDTH 3
#define BLUR_PASSES 2

#define CUDA_CHECK(call)                                                                      \
    do {                                                                                      \
        cudaError_t err = (call);                                                             \
        if (err != cudaSuccess) {                                                             \
            fprintf(stderr, "CUDA error at %s:%d: %s\n", __FILE__, __LINE__, cudaGetErrorString(err)); \
            return 1;                                                                         \
        }                                                                                     \
    } while (0)

static const float H_GAUSSIAN_3X3[9] = {
    1.0f / 16.0f, 2.0f / 16.0f, 1.0f / 16.0f,
    2.0f / 16.0f, 4.0f / 16.0f, 2.0f / 16.0f,
    1.0f / 16.0f, 2.0f / 16.0f, 1.0f / 16.0f
};

__constant__ float D_GAUSSIAN_3X3[9];

__device__ __forceinline__ int clamp_device(int value, int low, int high) {
    return value < low ? low : (value > high ? high : value);
}

static int clamp_host(int value, int low, int high) {
    if (value < low) {
        return low;
    }
    if (value > high) {
        return high;
    }
    return value;
}

// Basic CUDA kernel: each thread handles one pixel and reads neighbors directly from global memory.
__global__ void gaussianBlurBasic(const unsigned char* input, unsigned char* output, int width, int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;

    if (x >= width || y >= height) {
        return;
    }

    float sum = 0.0f;

    for (int ky = -KERNEL_RADIUS; ky <= KERNEL_RADIUS; ++ky) {
        for (int kx = -KERNEL_RADIUS; kx <= KERNEL_RADIUS; ++kx) {
            int ix = clamp_device(x + kx, 0, width - 1);
            int iy = clamp_device(y + ky, 0, height - 1);
            float weight = D_GAUSSIAN_3X3[(ky + KERNEL_RADIUS) * KERNEL_WIDTH + (kx + KERNEL_RADIUS)];
            sum += weight * input[iy * width + ix];
        }
    }

    output[y * width + x] = (unsigned char)(sum + 0.5f);
}

// Tiled CUDA kernel: each block caches a (BLOCK_SIZE+2)x(BLOCK_SIZE+2) tile in shared memory.
// Shared memory is much faster than global memory, so reuse of neighborhood pixels reduces latency.
// The +2 halo region stores 1-pixel borders needed by the 3x3 convolution window.
__global__ void gaussianBlurTiled(const unsigned char* input, unsigned char* output, int width, int height) {
    __shared__ unsigned char tile[BLOCK_SIZE + 2][BLOCK_SIZE + 2];

    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;

    int tx = threadIdx.x + 1;
    int ty = threadIdx.y + 1;

    int safe_x = clamp_device(x, 0, width - 1);
    int safe_y = clamp_device(y, 0, height - 1);

    // Central loads are coalesced because neighboring threads read neighboring global addresses.
    tile[ty][tx] = input[safe_y * width + safe_x];

    if (threadIdx.x == 0) {
        int halo_x = clamp_device(x - 1, 0, width - 1);
        tile[ty][0] = input[safe_y * width + halo_x];
    }

    if (threadIdx.x == BLOCK_SIZE - 1) {
        int halo_x = clamp_device(x + 1, 0, width - 1);
        tile[ty][BLOCK_SIZE + 1] = input[safe_y * width + halo_x];
    }

    if (threadIdx.y == 0) {
        int halo_y = clamp_device(y - 1, 0, height - 1);
        tile[0][tx] = input[halo_y * width + safe_x];
    }

    if (threadIdx.y == BLOCK_SIZE - 1) {
        int halo_y = clamp_device(y + 1, 0, height - 1);
        tile[BLOCK_SIZE + 1][tx] = input[halo_y * width + safe_x];
    }

    if (threadIdx.x == 0 && threadIdx.y == 0) {
        int halo_x = clamp_device(x - 1, 0, width - 1);
        int halo_y = clamp_device(y - 1, 0, height - 1);
        tile[0][0] = input[halo_y * width + halo_x];
    }

    if (threadIdx.x == BLOCK_SIZE - 1 && threadIdx.y == 0) {
        int halo_x = clamp_device(x + 1, 0, width - 1);
        int halo_y = clamp_device(y - 1, 0, height - 1);
        tile[0][BLOCK_SIZE + 1] = input[halo_y * width + halo_x];
    }

    if (threadIdx.x == 0 && threadIdx.y == BLOCK_SIZE - 1) {
        int halo_x = clamp_device(x - 1, 0, width - 1);
        int halo_y = clamp_device(y + 1, 0, height - 1);
        tile[BLOCK_SIZE + 1][0] = input[halo_y * width + halo_x];
    }

    if (threadIdx.x == BLOCK_SIZE - 1 && threadIdx.y == BLOCK_SIZE - 1) {
        int halo_x = clamp_device(x + 1, 0, width - 1);
        int halo_y = clamp_device(y + 1, 0, height - 1);
        tile[BLOCK_SIZE + 1][BLOCK_SIZE + 1] = input[halo_y * width + halo_x];
    }

    __syncthreads();

    if (x < width && y < height) {
        float sum = 0.0f;

        for (int ky = -KERNEL_RADIUS; ky <= KERNEL_RADIUS; ++ky) {
            for (int kx = -KERNEL_RADIUS; kx <= KERNEL_RADIUS; ++kx) {
                float weight = D_GAUSSIAN_3X3[(ky + KERNEL_RADIUS) * KERNEL_WIDTH + (kx + KERNEL_RADIUS)];
                sum += weight * tile[ty + ky][tx + kx];
            }
        }

        output[y * width + x] = (unsigned char)(sum + 0.5f);
    }
}

static void gaussian_blur_cpu_ref(const unsigned char* input, unsigned char* output, int width, int height) {
    size_t pixel_count = (size_t)width * (size_t)height;
    unsigned char* temp = (unsigned char*)malloc(pixel_count);

    if (temp == NULL) {
        return;
    }

    const unsigned char* current_input = input;
    unsigned char* current_output = temp;

    for (int pass = 0; pass < BLUR_PASSES; ++pass) {
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                float sum = 0.0f;
                for (int ky = -KERNEL_RADIUS; ky <= KERNEL_RADIUS; ++ky) {
                    for (int kx = -KERNEL_RADIUS; kx <= KERNEL_RADIUS; ++kx) {
                        int ix = clamp_host(x + kx, 0, width - 1);
                        int iy = clamp_host(y + ky, 0, height - 1);
                        float weight = H_GAUSSIAN_3X3[(ky + KERNEL_RADIUS) * KERNEL_WIDTH + (kx + KERNEL_RADIUS)];
                        sum += weight * current_input[iy * width + ix];
                    }
                }
                current_output[y * width + x] = (unsigned char)(sum + 0.5f);
            }
        }

        if (pass == 0) {
            current_input = temp;
            current_output = output;
        }
    }

    free(temp);
}

static double compute_mae(const unsigned char* a, const unsigned char* b, size_t n) {
    double acc = 0.0;
    for (size_t i = 0; i < n; ++i) {
        int diff = (int)a[i] - (int)b[i];
        acc += (double)(diff < 0 ? -diff : diff);
    }
    return n > 0 ? acc / (double)n : 0.0;
}

static int is_supported_mode(const char* mode) {
    return strcmp(mode, "gpu_basic") == 0 || strcmp(mode, "gpu_tiled") == 0;
}

int main(int argc, char** argv) {
    const char* mode = NULL;
    const char* input_path = NULL;
    const char* output_path = NULL;
    int verify_output = 0;

    Image input = {0, 0, NULL};
    Image output = {0, 0, NULL};

    unsigned char* d_input = NULL;
    unsigned char* d_temp = NULL;
    unsigned char* d_output = NULL;

    cudaEvent_t start_event = NULL;
    cudaEvent_t stop_event = NULL;

    float elapsed_ms = 0.0f;
    size_t pixel_count = 0;

    if (argc < 4) {
        fprintf(stderr, "Usage: %s <gpu_basic|gpu_tiled> <input.pgm> <output.pgm> [--verify]\n", argv[0]);
        return 1;
    }

    mode = argv[1];
    input_path = argv[2];
    output_path = argv[3];
    verify_output = (argc >= 5 && strcmp(argv[4], "--verify") == 0) ? 1 : 0;

    if (!is_supported_mode(mode)) {
        fprintf(stderr, "Unsupported mode: %s\n", mode);
        return 1;
    }

    if (read_pgm(input_path, &input) != 0) {
        fprintf(stderr, "Failed to read input image: %s\n", input_path);
        return 1;
    }

    pixel_count = (size_t)input.width * (size_t)input.height;

    output.width = input.width;
    output.height = input.height;
    output.data = (unsigned char*)malloc(pixel_count);
    if (output.data == NULL) {
        fprintf(stderr, "Failed to allocate output host buffer.\n");
        free_image(&input);
        return 1;
    }

    CUDA_CHECK(cudaMemcpyToSymbol(D_GAUSSIAN_3X3, H_GAUSSIAN_3X3, sizeof(H_GAUSSIAN_3X3)));
    CUDA_CHECK(cudaMalloc((void**)&d_input, pixel_count));
    CUDA_CHECK(cudaMalloc((void**)&d_temp, pixel_count));
    CUDA_CHECK(cudaMalloc((void**)&d_output, pixel_count));

    CUDA_CHECK(cudaMemcpy(d_input, input.data, pixel_count, cudaMemcpyHostToDevice));

    CUDA_CHECK(cudaEventCreate(&start_event));
    CUDA_CHECK(cudaEventCreate(&stop_event));

    dim3 block(BLOCK_SIZE, BLOCK_SIZE);
    dim3 grid((unsigned int)((input.width + BLOCK_SIZE - 1) / BLOCK_SIZE),
              (unsigned int)((input.height + BLOCK_SIZE - 1) / BLOCK_SIZE));

    CUDA_CHECK(cudaEventRecord(start_event));

    if (strcmp(mode, "gpu_basic") == 0) {
        gaussianBlurBasic<<<grid, block>>>(d_input, d_temp, input.width, input.height);
        CUDA_CHECK(cudaGetLastError());
        gaussianBlurBasic<<<grid, block>>>(d_temp, d_output, input.width, input.height);
    } else {
        gaussianBlurTiled<<<grid, block>>>(d_input, d_temp, input.width, input.height);
        CUDA_CHECK(cudaGetLastError());
        gaussianBlurTiled<<<grid, block>>>(d_temp, d_output, input.width, input.height);
    }

    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaEventRecord(stop_event));
    CUDA_CHECK(cudaEventSynchronize(stop_event));
    CUDA_CHECK(cudaEventElapsedTime(&elapsed_ms, start_event, stop_event));

    CUDA_CHECK(cudaMemcpy(output.data, d_output, pixel_count, cudaMemcpyDeviceToHost));

    if (write_pgm(output_path, &output) != 0) {
        fprintf(stderr, "Failed to write output image: %s\n", output_path);
        cudaEventDestroy(start_event);
        cudaEventDestroy(stop_event);
        cudaFree(d_input);
        cudaFree(d_temp);
        cudaFree(d_output);
        free_image(&output);
        free_image(&input);
        return 1;
    }

    if (verify_output) {
        unsigned char* cpu_ref = (unsigned char*)malloc(pixel_count);
        if (cpu_ref != NULL) {
            double mae = 0.0;
            gaussian_blur_cpu_ref(input.data, cpu_ref, input.width, input.height);
            mae = compute_mae(cpu_ref, output.data, pixel_count);
            printf("VERIFY_MAE=%.6f\n", mae);
            free(cpu_ref);
        }
    }

    printf("MODE=%s\n", mode);
    printf("TIME_MS=%.3f\n", elapsed_ms);

    cudaEventDestroy(start_event);
    cudaEventDestroy(stop_event);
    cudaFree(d_input);
    cudaFree(d_temp);
    cudaFree(d_output);
    free_image(&output);
    free_image(&input);

    return 0;
}
