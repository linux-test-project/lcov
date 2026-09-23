sub f {
    my ($a, $b) = @_;
    my $r = $a &&
        $b;
    my $s = ($a =~
        /x/);
    return $r;
}
