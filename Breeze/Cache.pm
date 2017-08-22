package Breeze::Cache;

use v5.26;
use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Breeze::Counter;
use Data::Dumper;

sub new($class, %args) {
    return bless {
        storage => {},
    }, $class;
}

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

sub set($self, $key, $value, $recall = 1) {
    return if exists $self->{storage}->{$key};

    $self->{storage}->{$key} = [
        Breeze::Counter->new(current => $recall),
        { %$value },
    ];

    print STDERR "cache stored ", Dumper($value);
    # do not return entry
    return;
}

sub flush($self, @keys) {
    # on total flush, just recreate storage
    if (!@keys) {
        $self->{storage} = {};
    # delete selected keys
    } else {
        delete $self->{storage}->@{@keys};
    }
}

# vim: syntax=perl5-24

1;
