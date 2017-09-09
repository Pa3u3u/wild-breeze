package Leaf::IPAddr;

use utf8;
use strict;
use warnings;

use parent      "Stalk::Command";
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    $self->log->fatal("missing 'device' parameter in the constructor")
        unless defined $args{device};
    $self->{device}     = $args{device};
    $self->{hidden}     = $args{hidden} // 1;
    $self->{icon}       = $args{icon} // $args{device};
    $self->{cmdargs}    = { stderr_fatal => 1, status_fatal => 1 };

    $self->{last}       = "INIT";
    # try to run "ip addr" just to see if it works
    $self->run_command([qw(ip addr show), $self->{device}], $self->{cmdargs}->%*);
    return $self;
}

sub invoke($self, %args) {
    my ($out, undef, undef) = $self->run_command([qw(ip addr show), $self->{device}],
        $self->{cmdargs}->%*
    );

    my @lines   = split /\n/, $out;
    my $header  = shift @lines;
    my $new;

    my $ret     = {
        icon    => $self->{icon},
    };

    if ($header =~ m/\bstate DOWN\b/) {
        $ret->{color} = "%{ipaddr.down,aluminum,gray}";
        $new = "DOWN,0";
    } elsif ($header =~m/\bstate UP/) {
        my @addrlines = grep { /\bscope global\b/ } (@lines);
        my @addresses = map { /\binet6?\s+([\da-f:.]+)\// } @addrlines;

        if (!@addrlines) {
            $ret->{color} = "%{ipaddr.no_ip,orange,yellow}";
            $ret->{text}  = "no IP";
            $new = "UP,0";
        } else {
            $ret->{color} = "%{ipaddr.up,green}";
            $ret->{text}  = "UP";

            my ($essid, undef, $status) = $self->run_command(
                ["iwgetid", "--raw", $self->{device}],
                stderr_fatal => 0, status_fatal => 0
            );

            if ($status eq 0) {
                chomp $essid;
                unshift @addresses, $essid;
            }

            $new = "UP|" . join("|", @addresses);

            if ($new ne $self->{last}) {
                $self->{hidden} = !defined $essid;
                $self->{ix}     = Breeze::Counter->fixed($#addresses);
            }

            my $addr = $addresses[int ($self->{ix} // 0)];
            $ret->{text} = $addr;

            if (@addresses > 1) {
                $ret->{text} .= sprintf(" %d/%d", int($self->{ix}) + 1, scalar @addresses);
            }
        }
    } else {
        $ret->{color} = "%{ipaddr.unknown,orange,yellow}";
        $new = "UNKNOWN,0";
    }

    if ($self->{last} ne $new && $self->{last} ne "INIT") {
        if (defined $self->{invert_on_change}) {
            $ret->{invert} = $self->{invert_on_change};
        }

        # try to get ESSID
        my ($out, undef, $stat) = $self->run_command([qw(iwgetid --raw), $self->{device}],
            stderr_fatal => 0, status_fatal => 0
        );
    }

    $self->{last} = $new;
    delete $ret->{text} if $self->{hidden};

    return $ret;
}

sub on_next($s) { ++$s->{ix} if defined $s->{ix}; undef; }
sub on_back($s) { --$s->{ix} if defined $s->{ix}; undef; }

sub on_left_click($s) { $s->{hidden} = !$s->{hidden}; }

1;
