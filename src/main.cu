#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
#include "nfd.h"
#include <iostream>
#include <string>

__global__ void grayscaleConversion(unsigned char *inputImage, unsigned char *outputImage, int width, int height, int channels)
{
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;

    if (x < width && y < height)
    {
        int index = y * width + x;
        unsigned char r = inputImage[channels * index];
        unsigned char g = inputImage[channels * index + 1];
        unsigned char b = inputImage[channels * index + 2];
        outputImage[index] = 0.299f * r + 0.587f * g + 0.114f * b;
    }
}

void checkCudaErrors(cudaError_t err, const char *message)
{
    if (err != cudaSuccess)
    {
        std::cerr << "CUDA error: " << message << " : " << cudaGetErrorString(err) << std::endl;
        exit(-1);
    }
}

int main()
{
    NFD_Init();

    nfdchar_t *outPath;
    nfdfilteritem_t filterItem[1] = {{"Image", "png,jpg,jpeg"}};
    nfdresult_t result = NFD_OpenDialog(&outPath, filterItem, 1, NULL);
    if (result == NFD_ERROR)
    {
        std::cerr << "Error: " << NFD_GetError() << std::endl;
        NFD_Quit();
        return -1;
    }

    if (result == NFD_CANCEL)
    {
        NFD_Quit();
        return -1;
    }

    int width, height, channels;
    unsigned char *image_data = stbi_load(outPath, &width, &height, &channels, 0);

    if (!image_data)
    {
        std::cerr << "Failed to load image: " << outPath << std::endl;
        NFD_Quit();
        return -1;
    }

    NFD_FreePath(outPath);

    std::cout << "Loaded image with dimensions: " << width << "x" << height << " and " << channels << " channels." << std::endl;

    unsigned char *gray_output_img = new unsigned char[width * height];

    // Allocate memory on GPU
    unsigned char *d_inputImage, *d_outputImage;
    cudaMalloc(&d_inputImage, width * height * 3 * sizeof(unsigned char));
    cudaMalloc(&d_outputImage, width * height * sizeof(unsigned char));

    // Transfer input image data to GPU
    cudaMemcpy(d_inputImage, image_data, width * height * channels * sizeof(unsigned char), cudaMemcpyHostToDevice);

    stbi_image_free(image_data);

    // Define block and grid dimensions
    dim3 blockSize(16, 16);
    dim3 gridSize((width + blockSize.x - 1) / blockSize.x, (height + blockSize.y - 1) / blockSize.y);

    // Launch kernel
    grayscaleConversion<<<gridSize, blockSize>>>(d_inputImage, d_outputImage, width, height, channels);
    checkCudaErrors(cudaGetLastError(), "Kernel launch failed");
    checkCudaErrors(cudaDeviceSynchronize(), "Kernel execution failed");


    // Transfer output image data to CPU
    cudaMemcpy(gray_output_img, d_outputImage, width * height * sizeof(unsigned char), cudaMemcpyDeviceToHost);

    result = NFD_SaveDialogU8(&outPath, filterItem, 1, NULL, "gray_scaled");
    if (result == NFD_ERROR)
    {
        std::cerr << "Error: " << NFD_GetError() << std::endl;
        NFD_Quit();
        return -1;
    }

    // Write the image
    if (stbi_write_png(outPath, width, height, 1, gray_output_img, width))
    {
        std::cout << "Grayscale image written successfully: " << outPath << std::endl;
    }
    else
    {
        std::cerr << "Failed to write grayscale image." << std::endl;
    }

    NFD_FreePath(outPath);

    delete[] gray_output_img;

    cudaFree(d_inputImage);
    cudaFree(d_outputImage);

    NFD_Quit();

    return 0;
}