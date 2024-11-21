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


int main(int ac, char ** av)
{
  test(1,1,0);
#ifdef SENS1
  test(1,0,0);
#endif
#ifdef SENS2
  test(0,1,0);
#endif
  return 0;
}
