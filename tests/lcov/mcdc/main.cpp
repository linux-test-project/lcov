/**
 * @file   main.cpp
 * @author MTK50321 Henry Cox
 * @date   Fri Dec 13 14:34:31 2024
 * 
 * @brief  Check differences between LLVM/GCC regarding MC/DC results.
 *         split into two files to enable more testing
 */

extern void test(int, int, int);


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
