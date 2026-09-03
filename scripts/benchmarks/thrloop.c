#include <stdio.h>
#include <stdint.h>
#include <pthread.h>
#ifdef _WIN32
#include <windows.h>
static double now_sec(void){ LARGE_INTEGER f,t; QueryPerformanceFrequency(&f); QueryPerformanceCounter(&t); return (double)t.QuadPart/f.QuadPart; }
#define THREAD_RET void*
#define THREAD_RETVAL 0
#else
#include <time.h>
static double now_sec(void){ struct timespec ts; clock_gettime(CLOCK_MONOTONIC,&ts); return ts.tv_sec+ts.tv_nsec/1e9; }
#define THREAD_RET void*
#define THREAD_RETVAL NULL
#endif
static void *worker(void *arg){
    uint64_t x=1; double tb=1e9;
    for(int r=0;r<5;r++){
        double t0=now_sec();
        for(uint64_t i=1;i<=200000000ull;i++){
            x = x*6364136223846793005ull+1442695040888963407ull;
            *(volatile uint64_t *)&x = x; /* keep store: volatile via temp */
        }
        double dt=now_sec()-t0;
        if(dt<tb) tb=dt;
    }
    *(volatile uint64_t *)arg = x;
    printf("pthread-secondary-thread stack loop best: %.4f s (x=%llu)\n", tb, (unsigned long long)x);
    return THREAD_RETVAL;
}
int main(void){
    static volatile uint64_t sink;
    pthread_t t;
    pthread_create(&t, NULL, worker, (void *)&sink);
    pthread_join(t, NULL);
    return 0;
}
