package Breeze::Logger;

use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Carp;

=head1 NAME

    Breeze::Logger -- logging facility for Breeze

=head1 DESCRIPTION

This class represents a base logger for the Breeze that does nothing
with messages passed to it.

=head2 Methods

=over

=item C<< new($category, %args) >>

Returns a new logger. The category should be used to differentiate
between different components of the system, e.g. category C<core> chould
be used for messages from the core, C<cache> from the caching service etc.

Other C<%args> are not really used here, it should be used to pass
additional parameters to descendand classes.

=cut

sub new($class, $category, %args) {
    return bless { %args, category => $category }, $class;
}

=item C<< $logger->clone(%override) >>

Returns a copy of the logger. The C<%override> hash will be used to replace
values of the new logger, if used.

The intended usage is, usually, only to override the category, like this:

    my $clone = $logger->clone(category => "new_category");

=cut

sub clone($self, %override) {
    return bless { %$self, %override }, ref $self;
}

=item C<< $logger->info(@message) >>

=item C<< $logger->error(@message) >>

=item C<< $logger->debug(@message) >>

These methods log the given message with different level.
If C<@message> consists of more than 1 string, it is joined to a single string
without spaces (i.e. C<< join "", @message >>).

=cut

sub info($, @) {}
sub error($, @) {}
sub debug($, @) {}

=item C<< $logger->warn(@message) >>

Logs the message using the L</error> method and calls L<Carp/carp>
with the same text.

=cut

sub warn($self, @msg) {
    my $text = join("", @msg);
    $self->error($text);
    $Carp::CarpLevel = 1;
    carp $text;
}

=item C<< $logger->fatal(@message) >>

Logs the message using L</error> method and calls L<Carp/croak>
with the same text.

=cut

sub fatal($self, @msg) {
    my $text = join("", @msg);
    $self->error($text);
    $Carp::CarpLevel = 1;
    croak $text;
}

=back

=cut

1;
