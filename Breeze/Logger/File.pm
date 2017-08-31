package Breeze::Logger::File;

use utf8;
use strict;
use warnings;

use parent      qw(Breeze::Logger);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Carp;
use IO::Handle;
use Time::Format    qw(%strftime);

=head1 NAME

    Breeze::Logger::File -- log to file

=head1 DESCRIPTION

Logs messages to a file specified in the constructor as the
C<filename> parameter.

The C</debug> method is enabled only if the C<< debug => 1 >> parameter
was passed to the constructor.

=cut

sub new($class, @args) {
    my $self = $class->SUPER::new(@args);

    croak "missing 'filename' argument in constructor"
        unless defined $self->{filename};

    open $self->{fh}, ">:encoding(utf-8)", $self->{filename}
        or croak "$self->{filename}: $!";

    $self->{fh}->autoflush(1);
    $self->info("logging started");
    return $self;
}

sub time($self) {
    return $strftime{"%Y-%m-%d %H:%M:%S", localtime};
}

sub info($self, @msg) {
    printf { $self->{fh} } "%s info[%s] %s\n",
        $self->time, $self->{category}, join("", @msg);
}

sub error($self, @msg) {
    printf { $self->{fh} } "%s fail[%s] %s\n",
        $self->time, $self->{category}, join("", @msg);
}

sub debug($self, @msg) {
    return unless $self->{debug};
    printf { $self->{fh} } "%s debg[%s] %s\n",
        $self->time, $self->{category}, join("", @msg);
}

1;
