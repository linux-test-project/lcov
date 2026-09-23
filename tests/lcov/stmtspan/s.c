int f(int a, int b, int c)
{
  int x = a +
          b * 2 +
          c;
  int y = a +
          b * 3;
  int z = a ? b :
          c * 4;
  int w = b +
          c * 5;
  for (int i = 0;
       i < a;
       i += 2)
    x += i;
  int u = a +
          b;
  int v = a +
          c;
  int t = a -
          b;
  return x + y + z + w + u + v + t + 0;
}
