package WBM::LED;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      qw(WBM::Command);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

my %keys = (
    CapsLock    => 0,
    NumLock     => 1,
    ScrollLock  => 2,
);

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    $self->log->fatal("missing 'key' argument in constructor")
        unless defined $args{key};

    $self->log->fatal("unknown LED '$args{key}'")
        unless defined $keys{$args{key}};

    $self->{key}            = $args{key};
    $self->{watch_state}    = $args{watch_state};
    $self->{text}           = $args{text} // $keys{$self->{key}};
    $self->{icon}           = $args{icon};

    return $self;
}

sub invoke($self) {
    my ($stdout, undef, undef) = $self->run_command([qw(xset -q)],
        stderr_fatal => 1, state_fatal => 1);

    my ($mask) = ($stdout =~ m/LED mask:\s*([\da-f]{4,8})\b/);
    $self->log->fatal("could not obtain LED mask from xset's output")
        unless defined $mask;

    my $status = hex $mask;
    my $code   = ($status & (1 << $keys{$self->{key}}));
    my $color  = $code ? "%{led.on,green}" : "%{led.off,red}";

    my $ret = {
        icon    => $self->{icon},
        text    => $self->{text},
        color   => $color,
    };

    if (defined $self->{watch_state} && ($self->{watch_state} xor $code)) {
        $ret->{invert} = 0;
    }

    return $ret;
}

1;
