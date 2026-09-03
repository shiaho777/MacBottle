#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
static double now_sec(void)
{
    LARGE_INTEGER f, t;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart / (double)f.QuadPart;
}
#else
#include <time.h>
static double now_sec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}
#endif

#define BLOCKS 16384
#define BLOCK_SIZE 8192

static unsigned char *blocks[BLOCKS];

int main(void)
{
    double t_alloc = 0, t_memset = 0, t_walk = 0, t_free = 0;
    unsigned long long sum = 0;

    for (int r = 0; r < 8; r++)
    {
        double t;
        unsigned long long sum = 0;

        t = now_sec();
        for (int i = 0; i < BLOCKS; i++)
            blocks[i] = (unsigned char *)malloc(BLOCK_SIZE);
        t_alloc += now_sec() - t;

        t = now_sec();
        for (int i = 0; i < BLOCKS; i++)
            memset(blocks[i], (unsigned char)i, BLOCK_SIZE);
        t_memset += now_sec() - t;

        t = now_sec();
        for (int i = 0; i < BLOCKS; i++)
            for (int j = 0; j < BLOCK_SIZE; j += 64)
                sum += blocks[i][j];
        t_walk += now_sec() - t;

        t = now_sec();
        for (int i = 0; i < BLOCKS; i++)
            free(blocks[i]);
        t_free += now_sec() - t;
    }

    printf("alloc=%.4f memset=%.4f walk=%.4f free=%.4f (sum=%llu)\n",
           t_alloc / 8, t_memset / 8, t_walk / 8, t_free / 8, sum);
    return 0;
}
