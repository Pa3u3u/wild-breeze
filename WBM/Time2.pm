package WBM::Time2;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      qw(WBM::Driver);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Carp;
use Time::Format    qw(%strftime);

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    croak "missing 'format' parameter in constructor"
        unless defined $args{format};

    croak "missing 'icon' parameter in constructor"
        unless defined $args{icon};

    $self->{format} = $args{format};
    $self->{icon}   = $args{icon};
    $self->{first}  = 1;
    return $self;
}

sub invoke($self) {
    my $ret = {
        text        => $strftime{$self->{format}, localtime},
        icon        => $self->{icon},
        color       => 'fabd2f',
    };

    $ret->{invert} = 8 if $self->{first};
    delete $self->{first};
    return $ret;
}

# vim: syntax=perl5-24

1;
