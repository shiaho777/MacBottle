#include <stdio.h>
#include <stdint.h>
#ifdef _WIN32
#include <windows.h>
static double now_sec(void){ LARGE_INTEGER f,t; QueryPerformanceFrequency(&f); QueryPerformanceCounter(&t); return (double)t.QuadPart/f.QuadPart; }
#else
#include <time.h>
#include <stdlib.h>
static double now_sec(void){ struct timespec ts; clock_gettime(CLOCK_MONOTONIC,&ts); return ts.tv_sec+ts.tv_nsec/1e9; }
#endif
int main(void){
    uint64_t x=1;
    double tb=1e9;
#ifdef _WIN32
    volatile uint64_t *slot = (volatile uint64_t *)VirtualAlloc(NULL, 65536, MEM_COMMIT, PAGE_READWRITE);
#else
    volatile uint64_t *slot = (volatile uint64_t *)malloc(65536);
#endif
    for(int r=0;r<5;r++){
        double t0=now_sec();
        for(uint64_t i=1;i<=200000000ull;i++){
            x = x*6364136223846793005ull+1442695040888963407ull;
            *slot = x;
        }
        double dt=now_sec()-t0;
        if(dt<tb) tb=dt;
    }
    printf("store-to-heap/VirtualAlloc best: %.4f s (x=%llu)\n", tb, (unsigned long long)x);
    return 0;
}
