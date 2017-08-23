package WBM::Fail;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      qw(WBM::Driver);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    $self->log->fatal("missing 'text' parameter in constructor")
        unless defined $args{text};

    $self->{text}   = $args{text};
    $self->{first}  = 1;
    return $self;
}

sub refresh_on_event($self) { 1; }
sub on_left_click($self)    { $self->{dismissed} = 1; }
sub on_middle_click($self)  { $self->{dismissed} = 1; }
sub on_right_click($self)   { $self->{dismissed} = 1; }

sub invoke($self) {
    my $ret = {
        text    => $self->{text},
        icon    => "",
        color   => "dc322f",
        cache   => "+inf",
    };

    if ($self->{first}) {
        $ret->{blink}       = 6;
        $self->{first}      = 0;
    }

    if (!$self->{dismissed}) {
        $ret->{invert}      = "+inf";
    }

    return $ret;
}

# vim: syntax=perl5-24

1;
