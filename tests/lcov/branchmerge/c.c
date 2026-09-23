int f(int a, int b, int c, int d, int e)
{
    int r = 0;
    if (a &&
        b &&
        c)
        r = 1;
    r += a ||
         b;
    r += c ? d
           : e;
    r +=
        (a && b);
#define X 1
    r += (a &&
#if X
          b);
#endif
    r += (a && /* a comment
          which continues */ b);
    r = 1; r += (a &&
                 b);
    if (a)
        r += g(b,
               c ? 1 : 2);
    r += (a &&
          b &&
          c &&
          d);
    r += (c &&
          d);
    r += (a &&  // LCOV_EXCL_BR_LINE
          e);
    r += a;
    r += b;
    return r;
}
int g2(int a, int b, int i)
{
    if (a)
        i = 1;
    else if (a &&
             b)
        i = 2;
    for (i = 0; i < a &&
         i < b; ++i)
        ;
    if (int t = a; t &&
        b)
        i = 3;
    while (a &&
           b) {
        i = 4;
    } i += (a ||
            b);

    i += (a ||
          b);
    g(a ||
      b) }
    return i;
}
