class J {
    void m(java.util.List<Integer> l) {
        l.forEach(x -> {
            go(x); });
        boolean b = l.isEmpty() &&
                    l.size() > 1;
        int n = l.size();
    }
}
