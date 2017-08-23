package Breeze::Grad;

use utf8;
use strict;
use warnings;

use Math::Gradient  qw|multi_array_gradient|;

sub _rgb2array {
    my ($col) = @_;
    return [ map { hex $_ } ($col =~ m!(..)(..)(..)!) ];
}

sub _array2rgb {
    my ($arr) = @_;
    return join("", map { sprintf("%02X", $_) } (@$arr));
}

sub get {
    my $p       = shift(@_);
    my @colors  = map { _rgb2array($_) } (@_);
    my @grad    = multi_array_gradient(101, @colors);

    return _array2rgb($grad[$p]);
}

1;
