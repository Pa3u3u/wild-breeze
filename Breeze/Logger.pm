package Breeze::Logger;

use v5.26;
use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Carp;

sub new($class, $category, %args) {
    croak "missing 'category' argument in constructor"
        unless defined $category;

    return bless { %args, category => $category }, $class;
}

sub clone($self, %override) {
    return bless { %$self, %override }, ref $self;
}

sub info($, @) {}
sub error($, @) {}
sub debug($, @) {}

sub fatal($self, @msg) {
    my $text = join("", @msg);
    $self->error($text);
    $Carp::CarpLevel = 1;
    croak $text;
}

sub warn($self, @msg) {
    my $text = join("", @msg);
    $self->error($text);
    $Carp::CarpLevel = 1;
    carp $text;
}

# vim: syntax=perl5-24

1;
