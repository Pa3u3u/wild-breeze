package Leaf::Time;

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

    $self->{format} = $args{format} // "%a %F %T";
    $self->{icon}   = $args{icon}   // "";
    return $self;
}

sub invoke($self) {
    return {
        text    => $strftime{$self->{format}, localtime},
        icon    => $self->{icon},
        color   => "%{time.color,silver,white}",
    };
}

1;
