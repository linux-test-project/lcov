
def enter(s,
          a, b):
    print("lcocalmodule::enter(%s)" % (s))
    # LCOV_EXCL_BR_START
    if a:
        print("this is a branch")
    # LCOV_EXCL_BR_STOP

def unusedFunc():
    print("not called");
    return 1;
