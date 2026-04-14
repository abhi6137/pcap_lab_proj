CC ?= gcc
NVCC ?= nvcc
CFLAGS ?= -O3 -std=c11

BIN_DIR := bin
CORE_DIR := core

CPU_SRC := $(CORE_DIR)/cpu_blur.c $(CORE_DIR)/image_io.c
GPU_SRC := $(CORE_DIR)/gpu_blur.cu $(CORE_DIR)/image_io.c

CPU_TARGET := $(BIN_DIR)/cpu_blur
GPU_TARGET := $(BIN_DIR)/gpu_blur

ifeq ($(OS),Windows_NT)
CPU_TARGET := $(BIN_DIR)/cpu_blur.exe
GPU_TARGET := $(BIN_DIR)/gpu_blur.exe
endif

.PHONY: all clean

all: $(CPU_TARGET) $(GPU_TARGET)

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

$(CPU_TARGET): $(CPU_SRC) $(CORE_DIR)/image_io.h | $(BIN_DIR)
	$(CC) $(CFLAGS) $(CPU_SRC) -o $(CPU_TARGET)

$(GPU_TARGET): $(GPU_SRC) $(CORE_DIR)/image_io.h | $(BIN_DIR)
	$(NVCC) -O3 $(GPU_SRC) -o $(GPU_TARGET)

clean:
	rm -f $(BIN_DIR)/cpu_blur $(BIN_DIR)/gpu_blur $(BIN_DIR)/cpu_blur.exe $(BIN_DIR)/gpu_blur.exe
