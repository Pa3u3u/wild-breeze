package Leaf::ArchCPU;

use utf8;
use strict;
use warnings;

use parent      qw(Stalk::Command);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Breeze::Counter;
use Breeze::Grad;
use List::Util  qw(sum);

sub processors($self) {
    my ($stdout, undef, undef) = $self->run_command(["lscpu"],
        stderr_fatal    => 1,
        status_fatal    => 1,
    );

    my ($cpus) = ($stdout =~ m/CPU\(s\):\s*\b(\d+)\b/);
    $self->log->info("number of cpus: $cpus");
    return $cpus;
}

sub compute_usage($self, %data) {
    my $idle    = sum @data{qw(idle iowait)};
    my $nonidle = sum @data{qw(user nice system irq softirq steal)};
    my $total   = $idle + $nonidle;

    if (!defined $self->{prev}) {
        $self->{prev} = { total => $total, idle => $idle };
        return 0;
    }

    my $d_total = $total - $self->{prev}->{total};
    my $d_idle  = $idle  - $self->{prev}->{idle};

    $self->{prev}->@{qw(total idle)} = ($total, $idle);
    return 100 * ($d_total - $d_idle) / $d_total;
}

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);
    $self->{cpus}     = $self->processors;
    $self->{warning}  = $args{warning}  // "+inf";
    $self->{critical} = $args{critical} // "+inf";

    $self->{step} = Breeze::Counter->new(
        from    => -1,
        current => -1,
        to      => ($self->{cpus} > 1 ? $self->{cpus} - 1 : -1),
        cycle   => 1,
    );

    return $self;
}

sub invoke($self) {
    my $srch = int $self->{step} == -1 ? "cpu" : ("cpu" . int $self->{step});

    open my $fh, "<:encoding(utf-8)", "/proc/stat"
        or $self->log->fatal("/proc/stat: $!");

    my $line;
    while ($line = <$fh>) {
        chomp $line;
        last if ($line =~ m/^$srch\b/);
    }

    close $fh;

    $self->log->fatal("could not find stat for $srch")
        unless defined $line;

    my ($cpu, %data);
    ($cpu, @data{qw(user nice system idle iowait irq softirq steal)}, undef)
        = split /\s+/, $line, 10;

    my $ncpu = int $self->{step} == -1 ? "A" : int $self->{step};
    my $util = $self->compute_usage(%data);

    my $ret = {
        text        => sprintf("$ncpu %3d%%", $util),
        icon        => "",
        color_grad  => [
                $util,
                '%{archcpu.@grad,cpu.@grad,@green-to-red,green yellow red}',
            ],
    };

    $ret->{invert} = $self->refresh if $util >= $self->{warning};
    $ret->{blink}  = $self->refresh if $util >= $self->{critical};
    return $ret;
}

sub refresh_on_event($) { 1; }

sub on_next($self) {
    delete $self->{prev};
    ++$self->{step};
}

sub on_back($self) {
    delete $self->{prev};
    --$self->{step};
}

sub on_middle_click($self) {
    delete $self->{prev};
    $self->{step}->reset;
}

1;
