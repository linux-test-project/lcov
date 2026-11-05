template<class F> int call_if(bool b, F f) { return b ? f() : 0; }

int main(int argc, char**)
{
  int r = call_if(argc > 1, [] {
      return 1; }) + call_if(true, [] { return 2; });
  return r - 2;
}
