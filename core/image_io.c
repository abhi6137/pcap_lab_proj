#include "image_io.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int read_next_token(FILE* fp, char* buffer, size_t buffer_size) {
    int c = 0;
    size_t idx = 0;

    if (fp == NULL || buffer == NULL || buffer_size == 0) {
        return 0;
    }

    while ((c = fgetc(fp)) != EOF) {
        if (isspace(c)) {
            continue;
        }

        if (c == '#') {
            while ((c = fgetc(fp)) != EOF && c != '\n') {
            }
            continue;
        }

        break;
    }

    if (c == EOF) {
        return 0;
    }

    do {
        if (idx + 1 < buffer_size) {
            buffer[idx++] = (char)c;
        }
        c = fgetc(fp);
    } while (c != EOF && !isspace(c) && c != '#');

    if (c == '#') {
        while ((c = fgetc(fp)) != EOF && c != '\n') {
        }
    }

    buffer[idx] = '\0';
    return idx > 0;
}

int read_pgm(const char* filename, Image* image) {
    FILE* fp = NULL;
    char token[64];
    int width = 0;
    int height = 0;
    int maxval = 0;
    size_t pixel_count = 0;

    if (filename == NULL || image == NULL) {
        return -1;
    }

    image->width = 0;
    image->height = 0;
    image->data = NULL;

    fp = fopen(filename, "rb");
    if (fp == NULL) {
        return -1;
    }

    if (!read_next_token(fp, token, sizeof(token)) || strcmp(token, "P5") != 0) {
        fclose(fp);
        return -1;
    }

    if (!read_next_token(fp, token, sizeof(token))) {
        fclose(fp);
        return -1;
    }
    width = atoi(token);

    if (!read_next_token(fp, token, sizeof(token))) {
        fclose(fp);
        return -1;
    }
    height = atoi(token);

    if (!read_next_token(fp, token, sizeof(token))) {
        fclose(fp);
        return -1;
    }
    maxval = atoi(token);

    if (width <= 0 || height <= 0 || maxval <= 0 || maxval > 255) {
        fclose(fp);
        return -1;
    }

    pixel_count = (size_t)width * (size_t)height;
    image->data = (unsigned char*)malloc(pixel_count);
    if (image->data == NULL) {
        fclose(fp);
        return -1;
    }

    if (fread(image->data, 1, pixel_count, fp) != pixel_count) {
        free(image->data);
        image->data = NULL;
        fclose(fp);
        return -1;
    }

    image->width = width;
    image->height = height;
    fclose(fp);
    return 0;
}

int write_pgm(const char* filename, const Image* image) {
    FILE* fp = NULL;
    size_t pixel_count = 0;

    if (filename == NULL || image == NULL || image->data == NULL || image->width <= 0 || image->height <= 0) {
        return -1;
    }

    fp = fopen(filename, "wb");
    if (fp == NULL) {
        return -1;
    }

    if (fprintf(fp, "P5\n%d %d\n255\n", image->width, image->height) < 0) {
        fclose(fp);
        return -1;
    }

    pixel_count = (size_t)image->width * (size_t)image->height;
    if (fwrite(image->data, 1, pixel_count, fp) != pixel_count) {
        fclose(fp);
        return -1;
    }

    fclose(fp);
    return 0;
}

void free_image(Image* image) {
    if (image == NULL) {
        return;
    }

    if (image->data != NULL) {
        free(image->data);
        image->data = NULL;
    }

    image->width = 0;
    image->height = 0;
}
