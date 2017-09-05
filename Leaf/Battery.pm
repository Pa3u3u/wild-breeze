package Leaf::Battery;

use utf8;
use strict;
use warnings;

use parent      "Stalk::Command";
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use File::Slurp;

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    if (!defined $args{battery}) {
        $self->log->fatal("missing 'battery' option in arguments");
    }

    $self->{bat}        = $args{battery};
    $self->{warning}    = $args{warning}    // 20;
    $self->{critical}   = $args{critical}   // 10;
    $self->{estimate}   = $args{estimate};

    if (defined $self->{estimate} && $self->{estimate} < 2) {
        $self->{estimate} = 2;
    }

    return $self;
}

sub estimate($self, $t, $e) {
    push $self->{est_tab}->@*, [ $t, $e ];
    return unless scalar $self->{est_tab} >= 2;

    my $float_delta = 0.0000001;
    # use linear regression to compute A,B in e = A + Bt

    # compute averages
    my ($avg_t, $avg_e) = (0, 0);

    foreach my $p ($self->{est_tab}->@*) {
        $avg_t += $p->[0];
        $avg_e += $p->[1];
    }

    $avg_t /= (1.0 * scalar $self->{est_tab}->@*);
    $avg_e /= (1.0 * scalar $self->{est_tab}->@*);

    # compute var(t) and cov(t,e)
    my ($var_t, $cov_te) = (0.0, 0.0);
    foreach my $p ($self->{est_tab}->@*) {
        $var_t  += ($p->[0] - $avg_t) ** 2;
        $cov_te += ($p->[0] - $avg_t) * ($p->[1] - $avg_e);
    }

    return unless abs($var_t) > $float_delta;

    # compute B
    my $B = $cov_te / $var_t;

    # compute A
    my $A = $avg_e - $B * $avg_t;

    return unless abs($B) >= $float_delta;
    # finally, compute t0 where e0 == 0
    my $t0 = - $A / $B;

    # t0 is now the time WHEN the power will reach 0, get the
    # difference and format it to HH:MM
    my $diff = $t0 - $t;

    # do not estimate if estimate is negative (charging?)
    # or more than 24 hours
    return if ($diff < 0 || $diff > 86400);

    my $h = int ($diff / (60 * 60));
    my $m = int (($diff - 60 * 60 * $h) / 60);

    return sprintf("%02d:%02d", $h, $m);
}

sub invoke($self) {
    my $path = "/sys/class/power_supply/$self->{bat}";

    my $max     = read_file("$path/energy_full")
        or $self->log->fatal("$path/energy_full: $!");
    my $current = read_file("$path/energy_now")
        or $self->log->fatal("$path/energy_now: $!");
    my $state   = read_file("$path/status")
        or $self->log->fatal("$path/status: $!");

    chomp ($max, $current, $state);
    my $p = int (100 * $current / $max);

    my $icon = lc $state eq "charging" ? ""
             : $p >= 80 ? ""
             : $p >= 60 ? ""
             : $p >= 40 ? ""
             : $p >= 20 ? ""
             : "";

    my $ret = {
        text        => sprintf("%3d%%", $p),
        icon        => $icon,
        color_grad  => [ $p, '%{battery.@grad,@red-to-green,red yellow green}' ],
    };

    if (lc $state eq "charging") {
        delete $self->{est_tab} if $self->{estimate};
        return $ret;
    }

    if ($self->{estimate}) {
        if (defined(my $estimate = $self->estimate(time, $current / 1000))) {
            $ret->{text} .= " $estimate";
        }
    }

    if ($p < $self->{critical}) {
        $ret->{blink} = $self->refresh;
    } elsif ($p < $self->{warning}) {
        $ret->{invert} = $self->refresh;
    }

    return $ret;
}

1;
