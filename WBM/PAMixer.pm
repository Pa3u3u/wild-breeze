package WBM::PAMixer;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      qw(WBM::Command);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Breeze::Grad;
use IPC::Run3;

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    $self->log->fatal("missing 'sink' parameter in constructor")
        unless defined $args{sink};

    $self->{sink} = $args{sink};

    my (undef, $stderr, $status) = $self->run_pamixer;
    if ($status == 0) {
        $self->log->info("sink found");
    } else {
        $self->log->fatal("pamixer error: $stderr");
    }

    if ($self->{sink} =~ m/^\d+$/) {
        $self->log->warn("sink argument appears to be an index");
        $self->log->info("indices can change, consider unsing string name");
    }

    if (defined $args{step}) {
        $self->log->fatal("step number is not positive integer")
            unless $args{step} >= 1;
        $self->{step} = $args{step};
    } else {
        $self->{step} = 2;
    }

    $self->{"allow-boost"} = $args{"allow-boost"};

    return $self;
}

sub run_pamixer($self, @args) {
    return $self->run_command(["pamixer", "--sink", $self->{sink}, @args]);
}

sub refresh_on_event($) { 1; }

sub invoke($self) {
    my ($muted,  undef, undef) = $self->run_pamixer("--get-mute");
    my ($volume, undef, undef) = $self->run_pamixer("--get-volume");

    $muted = ($muted eq "true");

    my $ret;
    if ($muted) {
        $ret->{color}       = '%{volume.muted.fg,black}';
        $ret->{background}  = '%{volume.muted.bg,silver}';
    } else {
        $ret->{color} = $volume > 100
            ? "%{volume.overmax,cyan}"
            : $self->theme->grad($volume, '%{volume.@grad,@red-to-green,red yellow green}');

        if (($self->{last} // $volume) != $volume) {
            $ret->{invert} = 1;
        }
    }

    $self->{last} = $volume;
    $ret->{icon} = $volume <=  33 ? "  "
                 : $volume <=  66 ? " "
                 : $volume <= 100 ? ""
                 : "";

    $ret->{text} = sprintf "%3d%%", $volume;
    return $ret;
}

sub on_left_click($self) {
    $self->run_pamixer("--toggle-mute");
    return { reset_all => 1 };
}

sub on_middle_click($self) {
    $self->run_pamixer("--set-volume", 50);
    return { reset_all => 1, invert => 1 };
}


sub on_wheel_up($self) {
    my @args = ("-i", $self->{step});
    push @args, "--allow-boost" if $self->{"allow-boost"};

    $self->run_pamixer(@args);
    return { reset_all => 1, invert => 1 };
}

sub on_wheel_down($self) {
    my @args = ("-d", $self->{step});
    push @args, "--allow-boost" if $self->{"allow-boost"};

    $self->run_pamixer(@args);
    return { reset_all => 1, invert => 1 };
}

# vim: syntax=perl5-24

1;
