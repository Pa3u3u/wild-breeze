package Stalk::Driver;

use v5.26;
use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

sub new($class, %args) {
    my $self = bless {
        %args{qw(name driver timeout refresh log theme)},
    }, $class;

    delete @args{qw(name driver timeout refresh log theme)};
    return $self;
}

sub log($self)      { $self->{log};   }
sub name($self)     { $self->{name};  }
sub theme($self)    { $self->{theme}; }

sub refresh_on_event($) { 0; }

sub invoke($self) {
    $self->log->fatal("invoke called on Stalk::Driver, perhaps forgotten override?");
}

sub on_left_click($) {}
sub on_middle_click($) {}
sub on_right_click($) {}
sub on_wheel_up($) {}
sub on_wheel_down($) {}
sub on_back($) {}
sub on_next($) {}
sub on_event($) {}

# vim: syntax=perl5-24

1;
