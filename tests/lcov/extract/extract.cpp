#include <cstdio>
#include <cstring>
#include <iostream>
#include <string>

int main(int argc, const char *argv[])
{
  bool b = false;
  if (strcmp(argv[1], "1") == 0)
    b = true;

  char *a = nullptr;
  if (b)
    printf("Hai\n");
  delete[] a;

  std::string str("asdads");
  str = "cd";

  std::cout << str << std::endl;
  return 0;
}
