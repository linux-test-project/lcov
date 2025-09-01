#include <cstdio>
#include <cstring>
#include <iostream>
#include <string>

int main(int argc, const char *argv[]) // TEST_UNREACH_FUNCTION
{
  bool b = false;
  if (strcmp(argv[1], "1") == 0)
    b = true;

  char *a = nullptr;
  // TEST_BRANCH_START
  if (b) // TEST_BRANCH_LINE
    // TEST_BRANCH_STOP
    printf("Hai\n");
  delete[] a;

  // TEST_OVERLAP_START
  // TEST_OVERLAP_START
  // TEST_UNREACHABLE_START
  std::string str("asdads");
  // TEST_UNREACHABLE_END
  str = "cd";
  // TEST_OVERLAP_END

  //TEST_DANGLING_START
  //TEST_UNMATCHED_END

  std::cout << str << std::endl; // TEST_UNREACHABLE_LINE

  // LCOV_EXCL_START_1
  std::cout << "adding some code to ignore" << std::endl;
  // LCOV_EXCL_STOP_1
  return 0;
}
