sub f
{
    my %rows;
    my $winner = shift;
    foreach
        my $row (sort({ $a->[0] cmp $b->[0] } @{$rows{$winner} // []}))
    {
        my (undef, @caller) = @$row;
    }
    my $x = $winner /
        2;
    my $y = $winner =~
        /abc/;
    return $x;
}
