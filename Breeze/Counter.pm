package Breeze::Counter;

use v5.26;
use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Carp;

sub from($self)     { $self->{from};    }
sub to($self)       { $self->{to};      }
sub cycle($self)    { $self->{cycle};   }
sub step($self)     { $self->{step};    }

sub current($self, $value = undef) {
    if (defined $value) {
        croak "value is not in range $self->{from} - $self->{to}"
            if $value < $self->from || $self->to < $value;
        $self->{current} = $value;
    }

    return $self->{current};
}

sub new($class, %args) {
    # check keys
    foreach my $key (keys %args) {
        carp "unknown attribute '$key' in constructor"
            unless $key =~ m/^(from|to|current|cycle|step)$/;
    }

    my $self = bless {
        # first, defaults
        from    => 0,
        to      => "+Inf",
        current => 0,
        cycle   => 0,
        step    => 1,
        # replace with %args
        %args,
    }, $class;

    $self->{start} = $self->{current};

    if (defined $args{from} && defined $args{to}) {
        croak "from is greater than to"
            if $args{from} > $args{to};
    }

    if (defined $args{step} && $args{step} < 1) {
        croak "step is less than 1";
    }

    # validate using setter
    $self->current($self->{current});

    return $self;
}

sub next($self) {
    if (($self->{current} += $self->{step}) > $self->{to}) {
        $self->{current} = $self->{cycle} ? $self->{from} : $self->{to};
    }

    return $self->{current};
}

sub prev($self) {
    if (($self->{current} -= $self->{step}) < $self->{from}) {
        $self->{current} = $self->{cycle} ? $self->{to} : $self->{from};
    }

    return $self->{current};
}

sub reset($self) {
    return $self->{current} = $self->{start};
}

# vim: syntax=perl5-24

1;
