package Leaf::Time;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      qw(Stalk::Driver);
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
    return $self;
}

sub invoke($self) {
    return {
        text    => $strftime{$self->{format}, localtime},
        icon    => $self->{icon},
        color   => "%{time.color}",
    };
}

# vim: syntax=perl5-24

1;
