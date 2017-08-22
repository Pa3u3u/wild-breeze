package WBM::Time;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      qw(WBM::Driver);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

sub new($class, %args) {
    return bless {}, $class;
}

# vim: syntax=perl5-24

1;
