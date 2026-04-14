#ifndef IMAGE_IO_H
#define IMAGE_IO_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int width;
    int height;
    unsigned char* data;
} Image;

int read_pgm(const char* filename, Image* image);
int write_pgm(const char* filename, const Image* image);
void free_image(Image* image);

#ifdef __cplusplus
}
#endif

#endif
