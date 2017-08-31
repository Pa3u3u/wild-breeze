package Breeze::Separator;

use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

=head1 NAME

    Breeze::Separator -- a simple class that only represents separators

=head1 DESCRIPTION

=head2 Methods

=over

=item C<< new >>

Returns a new separator.

=cut

sub new($class) {
    return bless {}, $class;
}

=item C<< $sep->is_separator >>

Returns C<1>. This method is used to differentiate between modules and
separators (see L<Breeze::Module>).

=cut

sub is_separator($) { 1; }

=back

=cut

1;
