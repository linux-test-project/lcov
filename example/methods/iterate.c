 /*
 *  methods/iterate.c
 *  
 *  Calculate the sum of a given range of integer numbers.
 *
 *  This particular method of implementation works by way of brute force,
 *  i.e. it iterates over the entire range while adding the numbers to finally
 *  get the total sum. As a positive side effect, we're able to easily detect
 *  overflows, i.e. situations in which the sum would exceed the capacity
 *  of an integer variable.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include "iterate.h"

void test_data_logging(int, int);

int iterate_get_sum (int min, int max)
{
        int i, total;

	test_data_logging(min, max);

        total = 0;

        /* This is where we loop over each number in the range, including
           both the minimum and the maximum number. */

        for (i = min; i <= max; i++)
        {
                /* We can detect an overflow by checking whether the new
                   sum would exceed the maximum integer value. */

                if (total > INT_MAX - i)
                {
                        printf ("Error: sum too large!\n");
                        exit (1);
                }

                /* Everything seems to fit into an int, so continue adding. */

                total += i;
        }

        return total;
}

void
test_data_logging(int min, int max)
{
  (void)min; /* quiet compiler complaints */
  (void)max;
  printf("this is some debug data logging code that gets removed in the final product\n");
}
