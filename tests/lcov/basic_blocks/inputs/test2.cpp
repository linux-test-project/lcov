template<typename T>
int a (T x) { return x + static_cast<T>(1); }

int main () {
    return a(1) + a(2.0);
}
