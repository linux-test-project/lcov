int f(int a, int b, int c)
{
  int x = a +
          b +
          c;
  int y = a +
          b;
  int z = a ? b :
          c;
  int w = b +
          c;
  for (int i = 0;
       i < a;
       ++i)
    x += i;
  int u = a +
          b;
  int v = a +
          b +
          c;
  int t = a -
          b;
  return x + y + z + w + u + v + t;
}
