package Breeze::I3;

use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use JSON;

=head1 NAME

    Breeze::I3 -- i3bar protocol implementation

=head1 DESCRIPTION

=head2 Methods

=over

=item C<< new >>

Creates a new instance.

=cut

sub new($class) {
    return bless {
        json    => JSON->new->utf8(0)->pretty(0),
        evh     => 0,
        queue   => [],
    }, $class;
}

=item C<< $i3->json >>

Returns an instance of the L<JSON> object.

=cut

sub json($self)     { $self->{json};    }

=item C<< $i3->finished >>

Returns true if the event parser encountered the ending ']' of the event list.

=cut

sub finished($self) { $self->{ev_stop}; }

=item C<< $i3->start >>

Prints version header and initial '[' of the i3bar protocol.

    {"version":1,"click_events":true}
    [

=cut

sub start($self) {
    print $self->json->encode({
        version         => 1,
        click_events    => JSON::true,
    }), "\n";

    print "[\n";
}

=item C<< $i3->next($data) >>

Encodes i3bar data from the current iteration into JSON and prints it
to standard output.

=cut

sub next($self, $data) {
    print $self->json->encode($data), ",\n";
}

=item C<< $i3->init_msg($message) >>

Prints an informational message to the bar.
This method is intended to write information like C<"starting">.

=cut

sub init_msg($self, @message) {
    $self->next([
        {
            full_text   => "",
            color       => '$002b36',
            separator   => JSON::false,
            separator_block_width => 0,
        },
        {
            full_text   => " " . join("", @message),
            color       => '$1e90ff',
            background  => '$002b36',
            name        => "msg",
            entry       => "msg",
            separator   => JSON::false,
            separator_block_width => 0,
        },
        {
            full_text   => "",
            background  => '$002b36',
            color       => '$000000',
            separator   => JSON::false,
            separator_block_width => 0,
        }
    ]);
}

=item C<< $i3->stop >>

Prints the closing ']' after the last array of components to be shown
on i3bar.

This should be the B<last> method called on an instance of L<Breeze::I3>.

=cut

sub stop($self) {
    print "]\n";
}

=item C<< $i3->input($data) >>

Adds the C<$data>, which should be read from the standard input (from the
i3bar) to the JSON parser.

Returns 1 if the parser can be asked to parse events. This, however,
does B<not> imply that there are some events waiting. In other words,
if this method does B<not> return 1, then the parser is B<definitely>
not able to parse events.

=cut

sub input($self, $data) {
    # add data to the parser
    $self->json->incr_parse($data);

    # first, get rid of leading '['
    if (!$self->{ev_started} && $self->json->incr_text =~ s/^\s*\[//) {
        $self->{ev_started} = 1;
    } elsif (!$self->{ev_started}) {
        return;
    }

    # stop if we encounter ']'
    if ($self->json->incr_text =~s/^\s*\]//) {
        $self->{ev_stop} = 1;
        return;
    }

    # parse events and add them to a queue
    while (my $event = $self->_next_event) {
        push $self->{queue}->@*, $event;
    }

    return 1;
}

=item C<< $i3->_next_event >>

If the parser is ready to parse events, this method returns the next
event or C<undef> if there are no events waiting.

=cut

sub _next_event($self) {
    $self->json->incr_text =~ s/^\s*,\s*//;
    return $self->json->incr_parse;
}

=item C<< $i3->next_event >>

Retrieves events from the queue.

=cut

sub next_event($self) {
    shift $self->{queue}->@*;
}

=back

=cut

1;
