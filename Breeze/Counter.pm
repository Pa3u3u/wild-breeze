package Breeze::Counter;

use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Carp;

=head1 NAME

    Breeze::Counter -- simple counter for Breeze

=head1 SYNOPSIS

    my $counter = Breeze::Counter->cycle(1);
    print int($counter++);    # 0
    print int($counter++);    # 1
    print int($counter++);    # 0

=head1 DESCRIPTION

=head2 Operator overloads

The following operators are available on instances of L<Breeze::Counter>:

=over

=item C<< $a + $scalar >>

=item C<< $a - $scalar >>

=item C<< $a += $scalar >>

=item C<< $a -= $scalar >>

Addition and subtraction from the counter.
Note that the value of counter is incremented by the step parameter, not
simply by 1. That is, the following code

    my $c = Breeze::Counter->new(to => 4, step => 2);
    $c += 1;

will cause C<$c> to have the value of C<2>, not C<1>.

=item C<< if ($a) >>

Boolean overload, the test is false only if the countes is on its
initial value.

=item C<< scalar $a >>, C<< "$a" >>, C<< 0+$a >>, C<< int $a >>

In scalar context, the counter simply returns its current value.

=item C<< $a <=> $b >>, C<< $a < $b >>, ...

Comparison operators compare the current value of the counter.

=cut

use overload
    "+="    => \&op_peq,
    "-="    => \&op_meq,
    "="     => \&op_assign,
    "bool"  => \&op_bool,
    "int"   => \&op_scalar,
    '""'    => \&op_scalar,
    "0+"    => \&op_scalar,
    "<=>"   => \&op_cmp;

=back

=head2 Constructors

=over

=item C<< new(%args) >>

Creates a counter from C<0> to infinity, incrementing or decrementing by 1.
Decrement below the starting value or increment above the final value
will leave the counter unchanged.
This behaviour can be changed by the constructor parameters:

=over

=item C<< to => number >>

Last (final) value of the counter.

=item C<< from => number >>

First value of the counter.

=item C<< current => number >>

Initial value, must be between C<to> and C<from>.
Default is 0. If setting C<from> greater than 0, this argument
B<must> be specified.

=item C<< cycle => 1 >>

Turn on cycling. Decrement below first or increment after last value
will cause the counter to wrap around the interval.

=item C<< step => positive_number >>

The number added or subtracted from the current value when incrementing
or decrementing respectively.
Defaults to C<1>.

=back

While it is theoretically possible to use floating numbers, for intervals
and even for steps, it is not recommended as it this use of the class
has never been fully tested.

=cut

sub new($class, %args) {
    # check keys
    foreach my $key (keys %args) {
        carp "unknown attribute '$key' in constructor"
            unless $key =~ m/^(from|to|current|cycle|step)$/;
    }

    my $self = bless {
        # first, defaults
        from    => 0,
        to      => "+Inf",
        current => 0,
        cycle   => 0,
        step    => 1,
        # replace with %args
        %args,
    }, $class;

    $self->{start} = $self->{current};

    if (defined $args{from} && defined $args{to}) {
        croak "from is greater than to"
            if $args{from} > $args{to};
    }

    if (defined $args{step} && $args{step} < 1) {
        croak "step is less than 1";
    }

    # validate using setter
    $self->current($self->{current});

    return $self;
}

=item C<< fixed($maximum) >>

Creates a "fixed" counter that starts from 0 and goes to C<$maximum>
with cycling. Essentially equivalent to

    Breeze::Counter->new(to => $maximum, cycle => 1)

=cut

sub fixed($class, $to) {
    return $class->new(to => $to, cycle => 1);
}

=item C<< countdown($from) >>

Creates a "countdown" counter that starts from C<$from> and goes to 0
(when decremented, of course) without cycling. Essentially equivalent to

    Breeze::Counter->new(to => $from, current => $from);

=cut

sub countdown($class, $from) {
    return $class->new(to => $from, current => $from);
}

=back

=head2 Methods

=over

=item C<< $c->from >>

=item C<< $c->to >>

=item C<< $c->cycle >>

=item C<< $c->step >>

Getters for starting and final value, cycle flag and number of steps
respectively.

=cut

sub from($self)     { $self->{from};    }
sub to($self)       { $self->{to};      }
sub cycle($self)    { $self->{cycle};   }
sub step($self)     { $self->{step};    }

=item C<< $c->current >>

=item C<< $c->current($value) >>

Gets or sets the current counter's value.
The value must be between C<< $c->from >> and C<< $c->to >>, otherwise
this method croaks.

=cut

sub current($self, $value = undef) {
    if (defined $value) {
        croak "value is not in range $self->{from} - $self->{to}"
            if $value < $self->from || $self->to < $value;
        $self->{current} = $value;
    }

    return $self->{current};
}

=item C<< $c->next >>

Increments the value of the counter, similarly to C<++$c>.
If C<< $c->cycle >> is enabled, wraps the value and starts from
C<< $c->from >>.

=cut

sub next($self) {
    if (($self->{current} += $self->{step}) > $self->{to}) {
        $self->{current} = $self->{cycle} ? $self->{from} : $self->{to};
    }

    return $self->{current};
}

=item C<< $c->prev >>

Decrements the value of the counter, similarly to C<--$c>.
If C<< $c->cycle >> is enabled, wraps the value and starts from
C<< $c->to >>.

=cut

sub prev($self) {
    if (($self->{current} -= $self->{step}) < $self->{from}) {
        $self->{current} = $self->{cycle} ? $self->{to} : $self->{from};
    }

    return $self->{current};
}

=item C<< $c->reset >>

Sets the current value to one that was passed as C<current> argument
to the constructor. This will B<not> set the value to C<< $c->from >>!
It may seem weird at first, but it allows the following statements to make
sense:

    my $cnt = Breeze::Counter->countdown(5);
    # ...
    $cnt->reset;

Which would be useless if it set the value to 0.
To set the value to the minimum value, use this:

    $c->current($c->from);

=cut

sub reset($self) {
    return $self->{current} = $self->{start};
}

=item C<< $c->clone >>

Returns the exact copy of the counter.

=cut

sub clone($self) {
    my %attrs = %$self;
    delete $attrs{start};
    my $clone = __PACKAGE__->new(%attrs);
    $clone->{start} = $self->{start};
    return $clone;
}

=back

=head2 Operator implementations

=over

=item C<< $c->op_bool >>

=item C<< $c->op_scalar >>

=item C<< $c->op_peq($other, $swap) >>

=item C<< $c->op_meq($other, $swap) >>

=item C<< $c->op_assign >>

=item C<< $c->op_cmp($other, $swap) >>

=cut

# operators
sub op_bool($self, $, $) {
    return $self->{current} != $self->{from};
}

sub op_scalar($self, $, $) {
    return $self->{current};
}

sub op_peq($self, $o, $swap) {
    $self->next foreach (1..$o);
    return $self;
}

sub op_meq($self, $o, $swap) {
    $self->prev foreach (1..$o);
    return $self;
}

sub op_assign($self, $, $) {
    return $self->clone;
}

sub op_cmp($self, $o, $swp) {
    my $a = $self->current;
    my $b = ref $o eq __PACKAGE__ ? $o->current : $o;
    return $swp ? $b - $a : $a - $b;
}

=back

=cut

1;
