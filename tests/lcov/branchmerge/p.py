def f(a, b):
    r = (a and
         b)
    s = a or \
        b
    t = """x
""" if a else b
    u = (a,
         b,
         a)
    return r
def g(a):
    v = (a,  # (
         ')', a)
    return v
