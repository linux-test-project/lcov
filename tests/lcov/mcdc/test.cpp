/**
 * @file   test.cpp
 * @author MTK50321 Henry Cox
 * @brief  Check differences between LLVM/GCC regarding MC/DC results.
 */

#include <stdio.h>

void test(int a, int b, int c)
{
  if (a && (b || c)) {
    printf("%d && (%d || %d)\n", a, b, c);
  } else {
    printf("not..\n");
  }
}
