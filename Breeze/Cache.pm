package Breeze::Cache;

use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Breeze::Counter;
use Breeze::Logger;

=head1 NAME

    Breeze::Cache -- Simple cache for module outputs

=head1 DESCRIPTION

=head2 Methods

=over

=item C<new($class)>

Creates an instance of the cache.

=cut

sub new($class) {
    return bless {
        storage => {},
        log     => Breeze::Logger->new("Breeze::Cache"),
    }, $class;
}

=item C<< $cache->log($logger) >>

=item C<< $cache->log >>

Sets or returns the logger.

=cut

sub log($self, $l) {
    $self->{log} = $l if defined $l;
    return $self->{log};
}

=item C<< $cache->get($key) >>

Returns a value stored under the C<$key> and decreases the counter associated
with the value. If there is no such key or the value expired (counter reached
zero), returns C<undef>.

=cut

sub get($self, $key) {
    my $entry = $self->{storage}->{$key};
    return unless defined $entry;

    # if entry was zero, the key expired, delete it and move on
    if (!$entry->[0]--) {
        delete $self->{storage}->{$key};
        return;
    }

    return { $entry->[1]->%* };
}

=item C<< $cache->set($key, $value, $recall = 1) >>

Stores the C<$value> under the given C<$key> with the counter set to C<$recall>.
Does nothing if the value already exists.

To replace a value, you can call this:

    $cache->flush($key);
    $cache->set($key, $value, $recall);

=cut

sub set($self, $key, $value, $recall = 1) {
    return if exists $self->{storage}->{$key} or !$recall;

    $self->{storage}->{$key} = [
        Breeze::Counter->new(current => $recall),
        { %$value },
    ];

    # do not return the entry
    return;
}

=item C<< $cache->flush($self, @keys) >>

Deletes entries for given C<@keys>. If there are no keys specified, i.e.
if the method is called like this:

    $cache->flush;

then B<all> values are removed.

=cut

sub flush($self, @keys) {
    # on total flush, just recreate storage
    if (!@keys) {
        $self->{storage} = {};
    # delete selected keys
    } else {
        delete $self->{storage}->@{@keys};
    }
}

=back

=head1 AUTHOR

Roman Lacko <xlacko1@fi.muni.cz>

=cut

1;
