#include <stdio.h>
#include <stdlib.h>
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

int main(void)
{
    volatile uint64_t x = 1;
    double best = 1e9;
    for (int r = 0; r < 5; r++)
    {
        double t0 = now_sec();
        for (uint64_t i = 1; i <= 200000000ull; i++)
            x = x * 6364136223846793005ull + 1442695040888963407ull;
        double dt = now_sec() - t0;
        if (dt < best) best = dt;
    }
    printf("cpu-loop 2e8 iters best: %.4f s (x=%llu)\n", best, (unsigned long long)x);
    return 0;
}
