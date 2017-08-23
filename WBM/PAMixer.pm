package WBM::PAMixer;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      qw(WBM::Driver);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Breeze::Grad;
use IPC::Run3;

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    $self->log->fatal("missing 'sink' parameter in constructor")
        unless defined $args{sink};

    $self->{sink} = $args{sink};

    if (defined $self->run_pamixer()) {
        $self->log->info("sink found");
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

sub run3opt($self) {
    return {
        binmode_stdout => ":encoding(utf-8)",
        binmode_stderr => ":encoding(utf-8)",
        return_if_system_error => 1,
    };
}

sub run_command($self, @cmd) {
    my ($stdout, $stderr) = ("","");

    if (!run3 \@cmd, \undef, \$stdout, \$stderr, $self->run3opt) {
        chomp($stdout, $stderr);
        $self->log->info("when running '", join(" ", @cmd), "'");

        if ($? == -1) {
            $self->log->error("system command failed: errno=$!");
        } elsif ($? & 127) {
            $self->log->error("command died on signal: signo=$?, ",
                "stdout='$stdout', stderr='$stderr'");
        } elsif ($? >> 8) {
            $self->log->error("command failed: status=", ($? >> 8), ", ",
                "stdout= $stdout', stderr='$stderr'");
        } else {
            $self->log->error("command succeeded (wtf?): stdout='$stdout', ",
                "stderr='$stderr'");
        }

        $self->log->fatal("this is a fatal error");
    }

    # IPC::Run3 does not restore encoding layers
    # https://rt.cpan.org/Public/Bug/Display.html?id=69011
    binmode STDIN;  binmode STDIN, ":encoding(utf-8)";
    binmode STDOUT; binmode STDOUT, ":encoding(utf-8)";
    binmode STDERR; binmode STDOUT, ":encoding(utf-8)";

    chomp($stdout, $stderr);

    if ($stderr ne "") {
        $self->log->info("while running '", join(" ", @cmd), "'");
        $self->log->error("stderr='$stderr'");
    }

    return $stdout;
}

sub run_pamixer($self, @args) {
    $self->run_command("pamixer", "--sink", $self->{sink}, @args);
}

sub refresh_on_event($) { 1; }

sub invoke($self) {
    my $muted  = $self->run_pamixer("--get-mute")   eq "true";
    my $volume = $self->run_pamixer("--get-volume");

    my $ret;
    if ($muted) {
        $ret->@{qw(color background)} = qw(002b36 93a1a1);
    } else {
        $ret->{background} = "073642";
        $ret->{color}      = $volume > 100 ? "238bd2"
                           : Breeze::Grad::get($volume, qw(dc322f b58900 859900));

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
    return { reset_all => 1, reset_invert => 1, blink => 4 };
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
