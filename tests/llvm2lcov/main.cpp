#include "test.h"

#define macro_1(expr)                   \
  do                                    \
  {                                     \
  } while (expr)

#define macro_2(i, expr1, expr2)        \
    do {                                \
        ++(i);                          \
        if (!(expr1))                   \
            ++(i);                      \
        if (!(expr2))                   \
            ++(i);                      \
    } while((expr1) && (expr2));

#define macro_3(expr) macro_1((expr))

void foo(char a)
{
        if (a)
        /* comment

         */ return;
}

int main() {
    int a[] = {3, 12}; /* comment */
    int i; /* comment
              comment
    comment */ i = 0;
    macro_1(i < 0);
    macro_1 (
        BOOL(i < 0 && i % 2 == 0))
        ;
    macro_2(i, i < 10, i > 0);
    i = 0;
    macro_3(i < 0);
    macro_4(i > 0 && i < 10);
    if (BOOL(i > 0) ||
        i <= 0)
        ;

    if (BOOL(i > 0)
        && BOOL(i < 0))
    {
        ;
    }

    for (; i < sizeof(a) / sizeof(*a); ++i)

    {
        if ((a[i] % 4
                    == 0)
                &&
                (a[i] % 3
                    == 0))
        {
            ;
        }
        if (a[i] < 10)
            ;
        foo(a[i] && i < 1);
    }
    /* i == 2
    */
    do {
        --i;
    } while (i);
    while(i < 2 && i < 3 && i < 4) { ++i; } for(i = 0; i < 5 && i < 4; ++i) { (void)i; }
    return 0;
}
