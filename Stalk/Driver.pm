package Stalk::Driver;

use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

=head1 NAME

    Stalk::Driver - the base class for all drivers

=head1 DESCRIPTION

Drivers are used to implement components that display some information
in i3bar.

All drivers should use this class as their parent and override C<invoke>
methods. It is not necessary, but useful, to override event handlers as well.

=head2 Constructor

=over

=item C<< new($class, %args) >>

Creates an instance of the driver. It remembers some of the arguments,
C<name>, C<driver>, C<timeout>, C<refresh>, C<log> and C<theme>.

The driver should override this constructor as this:

    package MyAwesomeDriver;

    use parent qw(Stalk::Driver);

    sub new($class, %args) {
        my $self = $class->SUPER::new(%args);
        # initialize other stuff
        return $self;
    }

=cut

sub new($class, %args) {
    my $self = bless {
        %args{qw(name driver timeout refresh log)},
    }, $class;

    return $self;
}

=back

=head2 Getters

=over

=item C<< $driver->log >>

=item C<< $driver->name >>

=item C<< $driver->timeout >>

=item C<< $driver->refresh >>

=cut

sub log($self)      { $self->{log};     }
sub name($self)     { $self->{name};    }
sub timeout($self)  { $self->{timeout}; }
sub refresh($self)  { $self->{refresh}; }

=back

=head2 Overridable methods

=over

=item C<< $driver->invoke >>

This method will be called when redrawing the i3bar.
It B<must> be overriden in the descendant class, as the default implementation
simply croaks.

Make sure B<not> to call the original method, that is, B<DO NOT DO THIS>
in your implementation of this class:

    package MyAwesomeDriver;

    # ...

    sub invoke($self) {
        # DO NOT DO THIS
        $self->SUPER::invoke;

        # ...
    }

The method B<MUST> return a hashref. For all keys that can be returned
please see the general documentation.

=cut

sub invoke($self) {
    $self->log->fatal("invoke called on Stalk::Driver, perhaps forgotten override?");
}

=item C<< $driver->refresh_on_event >>

If this method evaluates to true, Breeze will throw away any cached
value if it gets an event for this module. This will effectively
cause the module to be redrawn in the next iteration.

=cut

sub refresh_on_event($) { 0; }

=item C<< $driver->on_left_click >>
=item C<< $driver->on_middle_click >>
=item C<< $driver->on_right_click >>
=item C<< $driver->on_wheel_up >>
=item C<< $driver->on_wheel_down >>
=item C<< $driver->on_back >>
=item C<< $driver->on_next >>

Event handlers for various mouse buttons. They can also return a hashref,
which can set or unset some timers. See the documentation in the repository
to see available keys for the hashref.

=cut

sub on_left_click($) {}
sub on_middle_click($) {}
sub on_right_click($) {}
sub on_wheel_up($) {}
sub on_wheel_down($) {}
sub on_back($) {}
sub on_next($) {}

=item C<< $driver->on_event >>

A fallback handler that will be called for an unknown event.
There are some button keys unassigned, or some platforms may use
different numbers for mouse buttons.

=cut

sub on_event($,$) {}

=back

=cut

1;
