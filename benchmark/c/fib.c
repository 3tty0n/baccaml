#include <stdio.h>
#include "time.h"

int fib(int n) {
  if (n < 2) {
    return 1;
  } else {
    return fib(n - 1) + fib(n - 2);
  }
}

int main() {
  int x, i, start, end, iter;
  iter = 10;
  i = 0;
  start = get_micro_time();
  while(i < iter) {
    x = fib(28);
    i++;
  }
  end = get_micro_time();
  printf("execution time: %f s\n", (end - start) / (float)iter / (float)100000);
  return 0;
}