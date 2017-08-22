package Breeze::Logger::StdErr;

use utf8;
use strict;
use warnings;

use parent      qw(Breeze::Logger);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Carp;
use Time::Format    qw(%strftime);
use Term::ANSIColor;

sub new($class, @args) {
    my $self = $class->SUPER::new(@args);

    $self->{fh} = *STDERR;
    $self->info("logging started");
    return $self;
}

sub time($self) {
    return $strftime{"%Y-%m-%d %H:%M:%S", localtime};
}

sub info($self, @msg) {
    printf { $self->{fh} } "%s %s[%s] %s\n",
        colored($self->time, "ansi145"),
        colored("info", "ansi75"),
        $self->{category},
        colored(join("", @msg), "ansi75");
}

sub error($self, @msg) {
    printf { $self->{fh} } "%s %s[%s] %s\n",
        colored($self->time, "ansi145"),
        colored("fail", "ansi202"),
        $self->{category},
        colored(join("", @msg), "ansi202");
}

sub debug($self, @msg) {
    return unless $self->{debug};
    printf { $self->{fh} } "%s %s[%s] %s\n",
        colored($self->time, "ansi145"),
        colored("debg", "ansi242"),
        $self->{category},
        colored(join("", @msg), "ansi242");
}

# vim: syntax=perl5-24

1;
