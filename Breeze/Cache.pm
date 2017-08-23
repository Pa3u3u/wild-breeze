package Breeze::Cache;

use v5.26;
use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Breeze::Counter;
use Breeze::Logger;
use Data::Dumper;

sub new($class, %args) {
    return bless {
        storage => {},
        log     => Breeze::Logger->new("Breeze::Cache"),
    }, $class;
}

sub log($self) { return $self->{log}; }

sub set_logger($self, $logger) {
    $self->{log} = $logger;
}

sub get($self, $key) {
    my $entry = $self->{storage}->{$key};
    return unless defined $entry;

    # if entry was zero, the key expired, delete it and move on
    if (!$entry->[0]--) {
#       $self->log->debug("cached key for '", $key, "' expired upon request");
        delete $self->{storage}->{$key};
        return;
    }

#   $self->log->debug("returning cached value for '", $key, "'");
    return { $entry->[1]->%* };
}

sub set($self, $key, $value, $recall = 1) {
    return if exists $self->{storage}->{$key};

#   $self->log->debug("setting a new entry for '", $key, "'");
    $self->{storage}->{$key} = [
        Breeze::Counter->new(current => $recall),
        { %$value },
    ];

    # do not return entry
    return;
}

sub flush($self, @keys) {
    # on total flush, just recreate storage
    if (!@keys) {
#       $self->log->debug("flushing all entries");
        $self->{storage} = {};
    # delete selected keys
    } else {
#       $self->log->debug("flushing keys '", join(",", @keys), "'");
        delete $self->{storage}->@{@keys};
    }
}

# vim: syntax=perl5-24

1;
