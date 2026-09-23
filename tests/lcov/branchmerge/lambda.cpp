int h(int);
int g(int, int);
int main(int a, char **)
{
    int y = 0;
    auto f = [&](int v) {
        y += v ? 1 : 0; };
    f(1);
    int z = h(y);
    y += g(a &&
           z, 1);
    return z;
}
