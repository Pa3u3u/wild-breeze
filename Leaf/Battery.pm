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
    return $self;
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
    my $color = $self->theme->grad($p, '%{battery.@grad,@red-to-green,red yellow green}');

    my $icon = lc $state eq "charging" ? ""
             : $p >= 80 ? ""
             : $p >= 60 ? ""
             : $p >= 40 ? ""
             : $p >= 20 ? ""
             : "";

    my $ret = {
        text    => sprintf("%3d%%", $p),
        icon    => $icon,
        color   => $color,
    };

    if ($p < $self->{critical}) {
        $ret->{blink} = $self->refresh;
    } elsif ($p < $self->{warning}) {
        $ret->{invert} = $self->refresh;
    }

    return $ret;
}

1;
