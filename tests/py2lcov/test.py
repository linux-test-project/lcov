#!/usr/bin/env python3

import localmodule

def main():

    print("entering main");
    localmodule.enter("hello world", 1, 2)

    def localfunc():

        def nested1():
            def nested2():
                print('also nested');

            print('nested')

        return 1

# LCOV_EXCL_START
if __name__ == '__main__':
    main()
# LCOV_EXCL_STOP
