package Leaf::Fail;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      qw(Stalk::Driver);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    $self->log->fatal("missing 'text' parameter in constructor")
        unless defined $args{text};

    $self->{text}   = $args{text};
    $self->{tc}     = 0;
    return $self;
}

sub refresh_on_event($self) { 1; }

sub invoke($self) {
    my $ret = {
        text    => $self->{text},
        icon    => "",
        color   => "%{fail.color,red}",
        cache   => "+inf",
    };

    if ($self->{tc} == 0) {
        $ret->{blink}       = 30;
        $ret->{invert}      = "+inf";
    } elsif ($self->{tc} == 1) {
        $ret->{reset_all} = 1;
    } else {
        delete $ret->{text};
    }

    ++$self->{tc};
    return $ret;
}

# vim: syntax=perl5-24

1;
