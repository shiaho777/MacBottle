/* HeapTouch3-equivalent: heap allocate + touch + walk, measuring the
   memory-subsystem cost that dominates JVM startup workload.
   Same source builds as (a) macOS native arm64, (b) aarch64-windows PE. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

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

#define ROUNDS 12
#define BLOCKS 16384
#define BLOCK_SIZE 8192

int main(void)
{
    static unsigned char *blocks[BLOCKS];
    double best = 1e9;
    unsigned long sum = 0;

    for (int r = 0; r < ROUNDS; r++)
    {
        double t0 = now_sec();
        sum = 0;
        for (int i = 0; i < BLOCKS; i++)
        {
            blocks[i] = (unsigned char *)malloc(BLOCK_SIZE);
            if (!blocks[i]) return 1;
            memset(blocks[i], (unsigned char)i, BLOCK_SIZE);
        }
        for (int i = 0; i < BLOCKS; i++)
            for (int j = 0; j < BLOCK_SIZE; j += 64)
                sum += blocks[i][j];
        for (int i = 0; i < BLOCKS; i++) free(blocks[i]);
        double dt = now_sec() - t0;
        if (dt < best) best = dt;
    }
    printf("heap-touch best of %d: %.4f s (sum %lu)\n", ROUNDS, best, sum);
    return 0;
}
