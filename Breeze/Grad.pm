package Breeze::Grad;

use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

=head1 NAME

    Breeze::Grad -- computes percentual gradient of colors

=head1 SYNOPSIS

    my $color = Breeze::Grad::get($percent, qw(000000 333333 777777 ffffff));

=head1 DESCRIPTION

=over

=cut

use Carp;
use Math::Gradient  qw(multi_array_gradient);

sub _rgb2array($col) {
    return [ map { hex $_ } ($col =~ m![\$#]?(..)(..)(..)!) ];
}

sub _array2rgb($arr) {
    return join("", map { sprintf("%02X", $_) } (@$arr));
}

=item C<< Breeze::Grad::get($p, @points) >>

Returns a color from the scale described by a sequence of points.
It first creates a multi-array, computes a multi-array gradient
of 101 points (0 to 100 percent) using L<Math::Gradient::multi_array_gradient>.
Then, returns the color at index C<$p>.

This function only has sense for at least two colors.

The colors given in C<@points> are spread evenly, that is,

    get($p, qw(A B))
    # 0% -> A, 100% -> B

    get($p, qw(A B C))
    # 0% -> A, 50% -> B, 100% -> C

    get($p, qw(A B C D))
    # 0% -> 1, 33% -> B, 67% -> C, 100% -> D

=cut

sub get($p, @points) {
    croak "at least two colors are required"
        unless @points >= 2;

    my @colors  = map { _rgb2array($_) } (@points);
    my @grad    = multi_array_gradient(101, @colors);

    return _array2rgb($grad[$p]);
}

=back

=cut

1;
