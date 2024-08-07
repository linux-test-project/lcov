#include <iostream>
#include <string>
#include <unordered_map>

int main()
{
   const std::unordered_map<std::string, double> quotes{
       { "a", 0.011},
       { "b", 0.022},
       { "c", 0.033}
   };

   for (const auto& [s, v] : quotes)
     std::cout << "  >> " << s << ": " << v << "\n";

  return 0;
}
