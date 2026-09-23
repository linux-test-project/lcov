int f(int a, int b)
{
    int r = 0;
    if (a &&
        b)
        r = 1;
    r += a ? 2 :
         3;
    return r;
}
int main(int argc, char **argv)
{
    return f(argc > 1, argc > 2) + f(0, 1) - 3;
}
