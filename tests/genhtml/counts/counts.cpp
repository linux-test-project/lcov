#include <cstdio>
#include <stdexcept>

int classify(int x) {
    if (x > 0) {
        if (x % 2 == 0) {
            return 1;
        } else {
            return 2;
        }
    } else if (x < 0) {
        return (x < -10) ? 3 : 4;
    } else {
        throw std::runtime_error("zero");
    }
}

int main(int argc, char** argv) {
    int vals[] = {2, 3, -20, -1};
    int mode = argc > 1 ? argv[1][0] - '0' : 0;
    for (int i = 0; i < 4; i++) {
        try {
            if (mode == 0 || i % 2 == mode % 2) {
                printf("%d -> %d\n", vals[i], classify(vals[i]));
            }
        } catch (...) {
            printf("caught\n");
        }
    }
    return 0;
}
