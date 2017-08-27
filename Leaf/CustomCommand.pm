package Leaf::CustomCommand;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      qw(Stalk::Command);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Breeze::Counter;

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);
    $self->{$_} = $args{$_} foreach keys %args;

    $self->log->fatal("missing 'commands' arrayref in constructor")
        unless defined $self->{commands} && $self->{commands}->@* >= 1;

    if ($self->{commands}->@* >= 2) {
        $self->{ix} = Breeze::Counter->fixed($self->{commands}->@*);
    }

    return $self;
}

sub invoke($self) {
    my $ix  = defined $self->{ix} ? int $self->{ix} : 0;
    my $cmd = $self->{commands}->[$ix];

    my ($out, undef, undef) = $self->run_command($cmd,
        stderr_fatal => 1,
        status_fatal => 1,
    );

    my $ret = {
        text    => $out,
    };

    foreach (qw(icon color background)) {
        $ret->{$_} = $self->{$_} if defined $self->{$_};
    }

    if (defined $self->{invert_on_change} && ($self->{last} // $out) ne $out) {
        $ret->{invert} = $self->{invert_on_change};
    }

    $self->{last} = $out;
    return $ret;
}

sub proc_event($self, $e) {
    return unless defined $self->{events};

    my $cmd = $self->{events}->{$e};
    return unless defined $cmd;

    $self->run_command($cmd, stderr_fatal => 1, status_fatal => 1);
}

sub on_left_click($s)   { $s->proc_event("left_click");   undef; }
sub on_middle_click($s) { $s->proc_event("middle_click"); undef; }
sub on_right_click($s)  { $s->proc_event("right_click");  undef; }
sub on_wheel_up($s)     { $s->proc_event("wheel_up");     undef; }
sub on_wheel_down($s)   { $s->proc_event("wheel_down");   undef; }

sub on_back($s) {
    --$s->{ix} if defined $s->{ix};
    undef;
}
sub on_next($s) {
    ++$s->{ix} if defined $s->{ix};
    undef;
}

# vim: syntax=perl5-24

1;
