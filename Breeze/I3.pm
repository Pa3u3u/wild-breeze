package Breeze::I3;

use v5.26;
use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Devel::Peek;
use JSON;

sub new($class) {
    return bless {
        json    => JSON->new->utf8(0)->pretty(0),
    }, $class;
}

sub json($self) { $self->{json}; }

sub start($self) {
    print $self->json->encode({
        version         => 1,
        click_events    => JSON::XS::true,
    }), "\n";

    print "[\n";
}

sub next($self, $data) {
    print $self->json->encode($data), ",\n";
}

sub DESTROY($self) {
    print "]\n";
}

# vim: syntax=perl5-24

1;
