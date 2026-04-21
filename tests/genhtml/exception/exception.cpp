#include <exception>

struct Throw {Throw () {throw std::exception();}};
struct NoThrow {NoThrow () {}};

static int a;

template<typename T>
bool test()
{
  return new T() && a > 0 ? 1 : 0; // <-- this is the line lcov is complaining about
}

int main()
{
#ifdef DO_THROW
  try {test<Throw>();} catch (...) {}
#endif
#ifdef NO_THROW
  test<NoThrow>();
#endif
}
