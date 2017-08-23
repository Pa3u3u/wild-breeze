package WBM::Time;

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
    return $self;
}

sub invoke($self) {
    if (rand(100) < 30) {
        sleep 60;
    }

    return {
        text    => $strftime{$self->{format}, localtime},
        icon    => $self->{icon},
    };
}

# vim: syntax=perl5-24

1;
