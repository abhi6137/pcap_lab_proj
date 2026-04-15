#include "image_io.h"

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static const float GAUSSIAN_3X3[9] = {
    1.0f / 16.0f, 2.0f / 16.0f, 1.0f / 16.0f,
    2.0f / 16.0f, 4.0f / 16.0f, 2.0f / 16.0f,
    1.0f / 16.0f, 2.0f / 16.0f, 1.0f / 16.0f
};

static int clamp_int(int value, int low, int high) {
    if (value < low) {
        return low;
    }
    if (value > high) {
        return high;
    }
    return value;
}

static void gaussian_blur_pass(const unsigned char* input, unsigned char* output, int width, int height) {
    int y = 0;
    int x = 0;

    for (y = 0; y < height; ++y) {
        for (x = 0; x < width; ++x) {
            float sum = 0.0f;
            int ky = 0;
            int kx = 0;

            for (ky = -1; ky <= 1; ++ky) {
                for (kx = -1; kx <= 1; ++kx) {
                    int ix = clamp_int(x + kx, 0, width - 1);
                    int iy = clamp_int(y + ky, 0, height - 1);
                    float weight = GAUSSIAN_3X3[(ky + 1) * 3 + (kx + 1)];
                    sum += weight * input[iy * width + ix];
                }
            }

            output[y * width + x] = (unsigned char)(sum + 0.5f);
        }
    }
}

void gaussian_blur_cpu(const unsigned char* input, unsigned char* output, int width, int height) {
    size_t pixel_count = (size_t)width * (size_t)height;
    unsigned char* temp = (unsigned char*)malloc(pixel_count);

    if (temp == NULL) {
        return;
    }

    gaussian_blur_pass(input, temp, width, height);
    gaussian_blur_pass(temp, output, width, height);

    free(temp);
}

int main(int argc, char** argv) {
    Image input = {0, 0, NULL};
    Image output = {0, 0, NULL};
    size_t pixel_count = 0;
    clock_t start_clock = 0;
    clock_t end_clock = 0;
    double elapsed_ms = 0.0;

    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input.pgm> <output.pgm>\n", argv[0]);
        return 1;
    }

    if (read_pgm(argv[1], &input) != 0) {
        fprintf(stderr, "Failed to read input image: %s\n", argv[1]);
        return 1;
    }

    output.width = input.width;
    output.height = input.height;
    pixel_count = (size_t)input.width * (size_t)input.height;
    output.data = (unsigned char*)malloc(pixel_count);

    if (output.data == NULL) {
        fprintf(stderr, "Failed to allocate output image buffer.\n");
        free_image(&input);
        return 1;
    }

    start_clock = clock();
    gaussian_blur_cpu(input.data, output.data, input.width, input.height);
    end_clock = clock();

    elapsed_ms = 1000.0 * (double)(end_clock - start_clock) / (double)CLOCKS_PER_SEC;

    if (write_pgm(argv[2], &output) != 0) {
        fprintf(stderr, "Failed to write output image: %s\n", argv[2]);
        free_image(&output);
        free_image(&input);
        return 1;
    }

    printf("MODE=cpu\n");
    printf("TIME_MS=%.3f\n", elapsed_ms);

    free_image(&output);
    free_image(&input);
    return 0;
}
