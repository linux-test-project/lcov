template<class F> int call_if(bool b, F f) { return b ? f() : 0; }

int main(int argc, char**)
{
  return argc > 1 ? 2 : call_if(false, [] { return 1; });
}
