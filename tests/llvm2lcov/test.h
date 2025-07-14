static inline void bar()
{
  return;
}

#define macro_4(expr) ((expr) ? ((void) 0) : bar())

#define BOOL(x) (!!(x))
