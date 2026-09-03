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

#define ITERS 200000

int main(void)
{
    double best = 1e9;
    void *keep = 0;
    for (int r = 0; r < 5; r++)
    {
        double t0 = now_sec();
        for (int i = 0; i < ITERS; i++)
        {
            void *p = malloc(4096);
            if (i == ITERS / 2) keep = p;
            free(p);
        }
        double dt = now_sec() - t0;
        if (dt < best) best = dt;
    }
    printf("alloc/free x%d best: %.4f s (keep=%p)\n", ITERS, best, keep);
    return 0;
}
