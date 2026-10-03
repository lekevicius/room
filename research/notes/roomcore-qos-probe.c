// Diagnostic only: the native operation at the sampled Chromium ThreadFunc.
// cc -O2 -Wall -Wextra -pthread roomcore-qos-probe.c -o /tmp/roomcore-qos-probe
#include <pthread.h>
#include <pthread/qos.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

typedef struct { qos_class_t qos; double milliseconds; int status; } Result;
static double now(void) {
  struct timespec time;
  clock_gettime(CLOCK_MONOTONIC, &time);
  return time.tv_sec + time.tv_nsec / 1e9;
}
static void* worker(void* context) {
  Result* result = context;
  double start = now();
  result->status = pthread_set_qos_class_self_np(result->qos, 0);
  result->milliseconds = (now() - start) * 1000;
  return NULL;
}
int main(void) {
  alarm(15);  // A stall remains a failure, never an unbounded diagnostic.
  for (int batch = 0; batch < 2; ++batch) {
    pthread_t threads[32]; Result results[32];
    for (int i = 0; i < 32; ++i) {
      results[i] = (Result){.qos = batch ? QOS_CLASS_BACKGROUND : QOS_CLASS_USER_INITIATED};
      int status = pthread_create(&threads[i], NULL, worker, &results[i]);
      if (status) { fprintf(stderr, "pthread_create=%d\n", status); return 1; }
    }
    for (int i = 0; i < 32; ++i) {
      pthread_join(threads[i], NULL);
      printf("{\"qos\":\"%s\",\"thread\":%d,\"milliseconds\":%.6f,\"status\":%d}\n",
             batch ? "background" : "user-initiated", i, results[i].milliseconds, results[i].status);
      if (results[i].status) return 2;
    }
    fflush(stdout);
  }
  alarm(0);
  return 0;
}
