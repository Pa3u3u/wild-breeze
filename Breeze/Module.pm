package Breeze::Module;

use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Carp;
use Module::Load;
use Scalar::Util    qw(blessed);
use Stalk::Fail;
use Time::Out;
use Try::Tiny;

use Breeze::Counter;

=head1 NAME

    Breeze::Module -- wrapper around leaves

=head1 DESCRIPTION

=head2 Methods

=over

=item C<< new($name, $def, $attrs) >>

Creates a wrapper around module with name C<$name>. The module description
C<$def> should be parsed from the configuration file.
Additional attributes are passed in hashref C<attrs>.

The required attribute in C<$def> is C<driver>.

Required attributes in C<$attr> are C<log>, C<theme>, C<timeouts> and
C<failures>, the latter two should be parsed from the configuration file.

=cut

sub new($class, $name, $def, $attrs) {
    my $self = bless {
        name    => $name,
        def     => $def,
    }, $class;

    # check for required parameters
    croak "missing 'driver' in module description"
        unless defined $def->{driver};

    $self->{log}    = $attrs->{log}->clone(category => $self->name_canon);

    $self->initialize($attrs);

    return $self;
}

=item C<< $mod->initialize($attrs) >>

Helper method to be called from the constructor.
Loads the class defined in C<< $def->{driver} >> and calls its constructor.

=cut

sub initialize($self, $attrs) {
    load $self->driver;

    my %args = (
        name    => $self->name,
        log     => $self->log,
        theme   => $attrs->{theme},
        $self->{def}->%*
    );

    $args{refresh} = 0 unless defined $args{refresh};

    # create instance
    $self->{module} = (scalar $self->driver)->new(%args);
    if (!defined $self->{module} || !blessed($self->{module})) {
        $self->log->fatal("driver constructor finished but did not return a blessed object");
    }

    # initialize timers
    $self->{timers} = {
        timeout => Breeze::Counter->countdown($attrs->{timeouts}),
        fail    => Breeze::Counter->countdown($attrs->{failures}),
    };
}

=item C<< $mod->log >>
=item C<< $mod->name >>
=item C<< $mod->driver >>
=item C<< $mod->timeout >>
=item C<< $mod->refresh >>
=item C<< $mod->timers >>

Getters for various attributes of the wrapper.

=cut

sub log($s)     { $s->{log};  }
sub name($s)    { $s->{name}; }
sub driver($s)  { $s->{def}->{driver};  }
sub timeout($s) { $s->{def}->{timeout}; }
sub refresh($s) { $s->{def}->{refresh}; }
sub timers($s)  { $s->{timers}; }

=item C<< $mod->name_canon >>

Returns the name of the module in some canonical form. Currently,
this form is

    'name'(driver)

There is no significance in this form and can be changed if necessary.
Its only purpose is to have some human-readable string to identify
the module.

=cut

sub name_canon($s) { sprintf "'%s'(%s)", $s->name, $s->driver; }

=item C<< $mod->module >>

Returns an instance of the driver created in the constructor.

=cut

sub module($s)  { $s->{module}; }

=item C<< $mod->refresh_on_event >>

Convenience getter, calls the same method on the wrapped iinstance
of the leaf.

=cut

sub refresh_on_event($s) { $s->module->refresh_on_event; }

=item C<< $mod->get_timer($key) >>

Returns a timer (counter) with name C<$key> or C<undef> if no such
timer exists.

=cut

sub get_timer($self, $key) {
    my $tmrref = \$self->timers->{$key};
    return $tmrref if defined $$tmrref;
    return;
}

=item C<< $mod->set_timer($timer, $ticks) >>

Creates a timer with name C<$timer> with value of C<$ticks>.
Replaces any existing timer with the same name.
Usually you should use L<</get_or_set_timer>>.

=cut

sub set_timer($self, $timer, $ticks) {
    croak "Ticks or timer invalid"
        unless defined $timer && defined $ticks && $ticks >= 0;

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

=item C<< $mod->get_or_set_timer($timer) >>

=item C<< $mod->get_or_set_timer($timer, $ticks) >>

Combines L</get_timer> with L</set_timer>, i.e. returns a timer or creates
a new one if there is none

No timer is created if C<$ticks> is undefined.

If there is a existing timer, it will not be replaced or modified even if
C<$ticks> is different than the current value of the timer.

=cut

sub get_or_set_timer($self, $timer, $ticks = undef) {
    my $tmref = $self->get_timer($timer);

    if (!defined $$tmref && defined $ticks && $ticks >= 0) {
        $tmref = $self->set_timer($timer, $ticks);
    }

    return $tmref if defined $$tmref;
    return;
}

=item C<< $mod->delete_timer($timer) >>

Deletes the timer with the name C<$timer>.

=cut

sub delete_timer($self, $timer) {
    delete $self->timers->{$timer};
}

=item C<< $mod->fail >>

Replaces instance of the leaf with a new instance of the L<Stalk::Fail>
component. This is an irreversible operation, use with caution.

=cut

sub fail($self) {
    $self->{module} = Stalk::Fail->new(
        name    => $self->name,
        log     => $self->log,
        text    => $self->name_canon,
    );
}

=item C<< $mod->run($event, @extra) >>

Runs a method C<$event> on the instance with a timeout and catches
all exceptions that could be thrown by the invokation.

This is used to call C<invoke> and C<on_*> methods on the wrapper.

Extra arguments C<@extra> are passed to the method.

=over

=item C<< { timeout => 1 } >>

if the handler timed out

=item C<< { fatal => 1 } >>

if an error occured

=item C<< { ok => 1, content => $object } >>

if the invocation was successful, the C<content> value stores whatever
the method returned

=back

Note that the C<invoke> method is supposed to return a hashref, so it is
considered to be an error if that does not happen.

=cut

sub run($self, $event, @extra) {
    return try {
        my $tmp = Time::Out::timeout($self->timeout => sub {
            $self->module->$event(@extra);
        });

        if ($@) {
            $self->log->error("timeouted");
            return { timeout => 1 };
        } elsif ($event eq "invoke") {
            if (!defined $tmp || ref $tmp ne "HASH") {
                $self->log->error(sprintf("returned '%s' instead of HASH", (ref($tmp) || "undef")));
                return { fatal   => 1 };
            }

            $tmp->@{qw(name instance)} = ($self->driver, $self->name);
        }

        return { ok => 1, content => $tmp };
    } catch {
        chomp $_;
        $self->log->error("when running $event");
        $self->log->error($_);
        return { fatal => 1 };
    };
}

=item C<< $mod->is_separator >>

Return C<0>. This method is used to differentiate modules from separators
(see L<Breeze::Separator>). In development version there was a parent
class for both modules and separators that prescribed this method.

=cut

sub is_separator($) { 0; }

=back

=cut

1;
