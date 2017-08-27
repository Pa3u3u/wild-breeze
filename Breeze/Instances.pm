use v5.26;
use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

package Breeze::Instances;

# empty

#-------------------------------------------------------------------------------

package Breeze::Module;

use Breeze::Counter;
use Carp;
use Module::Load;
use Time::Out;

sub new($class, $name, $def, $attrs) {
    my $self = bless {
        name    => $name,
        def     => $def,
    }, $class;

    # check for required parameters
    croak "missing 'driver' in module description"
        unless defined $def->{driver};

    $self->{log}    = $attrs->{log}->clone(category => $self->name_canon);

    $self->initialize($attrs->{theme});
    $self->init_timers($attrs);

    return $self;
}

sub initialize($self, $theme) {
    load $self->driver;

    my %args = (
        name    => $self->name,
        log     => $self->log,
        theme   => $theme,
        $self->{def}->%*
    );

    # create instance
    $self->{module} = (scalar $self->driver)->new(%args);
}

sub init_timers($self, $attrs) {
    $self->{timers} = {
        timeout => Breeze::Counter->countdown($attrs->{timeouts}),
        fail    => Breeze::Counter->countdown($attrs->{failures}),
    };
}

sub log($s)     { $s->{log};  }
sub name($s)    { $s->{name}; }
sub driver($s)  { $s->{def}->{driver};  }
sub timeout($s) { $s->{def}->{timeout}; }
sub refresh($s) { $s->{def}->{refresh}; }
sub timers($s)  { $s->{timers}; }
sub module($s)  { $s->{module}; }

sub name_canon($s) { sprintf "'%s'(%s)", $s->name, $s->driver; }
sub refresh_on_event($s) { $s->module->refresh_on_event; }

# timer manipulation

sub get_timer($self, $key) {
    my $tmrref = \$self->timers->{$key};
    return $tmrref if defined $$tmrref;
    return;
}

sub set_timer($self, $timer, $ticks) {
    croak "Ticks or timer invalid"
        unless defined $timer && defined $ticks && $ticks >= 0;

    $self->log->debug($self->name, "->set_timer($timer,$ticks)");
    # optimization: do not store counter for only one cycle,
    # use local variable instead
    if ($ticks == 0) {
        my $temp = 0;
        return \$temp;
    }

    $self->timers->{$timer} = Breeze::Counter->countdown($ticks);

    # return a reference to the timer
    return \$self->timers->{$timer};
}

sub get_or_set_timer($self, $timer, $ticks = undef) {
    $self->log->debug($self->name, "->get_or_set_timer($timer,", ($ticks // "undef"), ")");
    my $tmref = $self->get_timer($timer);

    if (!defined $$tmref && defined $ticks && $ticks >= 0) {
        $tmref = $self->set_timer($timer, $ticks);
    }

    return $tmref if defined $$tmref;
    return;
}

sub delete_timer($self, $timer) {
    $self->log->debug($self->name, "->delete_timer($timer)");
    delete $self->timers->{$timer};
}

sub fail($self) {
    $self->{module} = Leaf::Fail->new(
        name    => $self->name,
        log     => $self->log,
        text    => $self->canon_name,
    );
}

sub run($self, $event) {
    return try {
        my $tmp = Time::Out::timeout($self->timeout => sub {
            $self->module->$event;
        });

        if ($@) {
            $self->log->error("timeouted");
            return { timeout => 1 };
        } elsif ($event eq "invoke") {
            if (!defined $tmp || ref $tmp ne "HASH") {
                $self->log->error(sprintf("returned '%s' instead of HASH", (ref($tmp) || "undef")));
                return { fatal   => 1 };
            }

            $tmp->@{qw(name instance)} = ($self->name, $self->name);
        }

        return { ok => 1, content => $tmp };
    } catch {
        chomp $_;
        $self->log->error($_);
        return { fatal => 1 };
    };
}

sub is_separator($) { 0; }

#-------------------------------------------------------------------------------

package Breeze::Separator;

sub new($class) {
    return bless {}, $class;
}

sub is_separator($) { 1; }

#-------------------------------------------------------------------------------

# vim: syntax=perl5-24

1;
