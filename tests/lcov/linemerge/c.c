int f(int a, int b, int c)
{
  int x = a +
          b +
          c;
  if (a &&
      b)
    x = 1;
  int y = a,
      z = b;
  x += y +
       z;
  return x;
}

static int g(int a,
             int b)
{
  int x = a + /* LCOV_EXCL_BR_LINE */
          b;
  x = a ?
      b : 2;
  return x;
}

static int h(int a, int b)
{
  int x = g(a,
            b);
  x += g(b,
         a ? 1 : 2);
  x += g(a,
         b);
  return x;
}

static int k(int n)
{
  int s = 0;
  for (int i = 0;
       i < n;
       ++i)
    s += i;
  return s;
}
