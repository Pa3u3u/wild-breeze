package Leaf::Touchpad;

use utf8;
use strict;
use warnings;

use parent "Stalk::Command";

use feature  "signatures";
no  warnings "experimental::signatures";

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    $self->{icon} = $args{icon} // "";
    $self->{stderr_fatal} = 1;
    $self->{status_fatal} = 1;
    return $self;
}

sub invoke($self) {
    my ($out, undef, undef) = $self->run_command(["synclient"]);

    my %data;
    foreach my $line (split /\n/, $out) {
        if (my ($k,$v) = ($line =~ m/^\s*(\S+)\s*=\s*(\S+)\s*$/)) {
            $data{$k} = $v;
        }
    }

    my $ret = {
        icon    => $self->{icon},
        text    => $data{TouchpadOff} ? "Off" : "On ",
        color   => $data{TouchpadOff}
            ? "%{touchpad.off,aluminum,gray}"
            : "%{touchpad.on,green}",
    };

    if (($self->{last} // $data{TouchpadOff}) ne $data{TouchpadOff}) {
        $ret->{invert} = 0;
    }

    $self->{last} = $data{TouchpadOff};

    return $ret;
}

sub on_left_click($self) {
    my $new = int !$self->{last};

    $self->run_command(["synclient", "TouchpadOff=$new"]);
}

1;
