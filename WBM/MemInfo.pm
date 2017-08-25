package WBM::MemInfo;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      qw(WBM::Driver);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Breeze::Counter;
use Breeze::Grad;
use Data::Dumper;
use Linux::MemInfo;

sub new($class,%args) {
    my $self = $class->SUPER::new(%args);

    $self->{stopped}    = 0;
    $self->{refresh}    = $args{-refresh};
    $self->{unit}       = $args{unit}   // "MB";
    $self->{prec}       = $args{prec}    // "%4d";
    $self->{display}    = $args{display} // [
        {
            icon    => "",
            format  => '%{MemUsed}/%{MemTotal} (%{MemUsedPercent})',
            style   => "MemUsedPercent",
            more    => "worse",
        },
        {
            icon    => "",
            format  => '%{SwapUsed}/%{SwapTotal} (%{SwapUsedPercent})',
            style   => "SwapUsedPercent",
            more    => "worse",
        },
    ];

    $self->{warning}    = $args{warning}    // 80;
    $self->{critical}   = $args{critical}   // 90;
    $self->{step}       = Breeze::Counter->new(
        from    => 0,
        to      => $self->{display}->$#*,
        cycle   => 1,
    );

    if (defined $args{switch}) {
        $self->log->fatal("argument 'switch' is not positive integer")
            unless $args{switch} >= 1;
        $self->{switch} = Breeze::Counter->new(
            to      => $args{switch},
            cycle   => 1,
            current => $args{switch},
        );
    }

    return $self;
}

sub u($self, $name) {
    return {
        "kb" => 1024,
        "mb" => 1024 * 1024,
        "gb" => 1024 * 1024 * 1024,
        "tb" => 1024 * 1024 * 1024 * 1024,
    }->{lc $name};
}

sub populate_percent($self, $data) {
    $data->{MemUsed}    = $data->{MemTotal}  - $data->{MemAvailable};
    $data->{SwapUsed}   = $data->{SwapTotal} - $data->{SwapFree};
    $data->{MemUsedUnit}  = $data->{MemTotalUnit};
    $data->{SwapUsedUnit} = $data->{SwapTotalUnit};

    my $cookbook = [
        [qw(Mem     Free    Total)],
        [qw(Mem     Used    Total)],
        [qw(Swap    Free    Total)],
        [qw(Swap    Used    Total)],
    ];

    foreach my $rec (@$cookbook) {
        my ($a, $b, $c) = @$rec;
        $data->{$a . $b . "Percent"} = int((100 * $data->{$a . $b}) / $data->{$a . $c});
    }
}

sub invoke($self) {
    my %data = get_mem_info;
    $self->populate_percent(\%data);

    my $fmt = $self->{display}->[int $self->{step}];
    my $str = $fmt->{format};

    my %replaced;
    foreach my $var ($fmt->{format} =~ m/%\{(.*?)\}/g) {
        next if exists $replaced{$var};
        my $val;
        if (lc $var eq "unit") {
            $val = $self->{unit};
        } else {
            $self->log->fatal("no such key '$var'")
                if !defined $data{$var};
            $val = $data{$var};

            if (defined($data{$var . "Unit"}) && ($data{$var . "Unit"} ne $self->{unit})) {
                $val = int($val * $self->u($data{$var . "Unit"}) / $self->u($self->{unit}));
            }
        }

        $str =~ s/%\{$var\}/$val/g;
        $replaced{$var} = undef;
    }

    my $watch = $data{$fmt->{watch}};
    my $color = $fmt->{more} eq "better"
        ? $self->theme->grad($watch, '%{meminfo.@better,@red-to-green,red yellow green}')
        : $self->theme->grad($watch, '%{meminfo.@worse,@green-to-red,green yellow red}');

    my $ret = {
        icon    => $fmt->{icon},
        text    => $str,
        color   => $color,
        reset_all   => 1,
    };

    if ($fmt->{more} eq "worse") {
        $ret->{blink}   = "+inf" if $watch >= $self->{critical};
        $ret->{invert}  = "+inf" if $watch >= $self->{warning};
    } else {
        $ret->{blink}   = "+inf" if $watch <= (100 - $self->{critical});
        $ret->{invert}  = "+inf" if $watch <= (100 - $self->{warning});
    }

    if (!$self->{stopped} && defined $self->{switch} && int(--$self->{switch}) == 0) {
        ++$self->{step};
    }

    return $ret;
}

sub refresh_on_event($) { 1; }

sub on_middle_click($self) {
    $self->{stopped} = !$self->{stopped};
}

sub on_wheel_up($self) {
    ++$self->{step};
    return { reset_all => 1 };
}

sub on_wheel_down($self) {
    --$self->{step};
    return { reset_all => 1 };
}

1;
