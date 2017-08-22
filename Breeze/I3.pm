package Breeze::I3;

use v5.26;
use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use JSON::XS;

sub new($class) {
    return bless {
        first   => 1,
        json    => JSON::XS->new->utf8(0)->pretty(0),
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
    if ($self->{first}) {
        $self->{first} = 0;
    } else {
        print ",";
    }

    print $self->json->encode($data), "\n";
}

sub DESTROY($self) {
    print "]\n";
}

# vim: syntax=perl5-24

1;
