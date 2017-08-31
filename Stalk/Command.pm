package Stalk::Command;

use utf8;
use strict;
use warnings;

use parent      qw(Stalk::Driver);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use IPC::Run3   qw(run3);

=head1 NAME

    Stalk::Command -- a base class for drivers with IPC::Run3

=head1 DESCRIPTION

This "stalk" should serve as a base class for drivers that want to call
external programs. It inherits from L<Stalk::Driver>.

=head2 Constructor

=over

=item C<< new(%args) >>

Creates a new instance of the driver.
It recognizes the following arguments:

=over

=item stderr_fatal

croak if the command writes something to its standard error output

=item status_fatal

croak if the command exits with a non-zero code

=back

=cut

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    $self->@{qw(stderr_fatal status_fatal)} = @args{qw(stderr_fatal status_fatal)};
    return $self;
}

=item C<< $driver->run3opt >>

Returns default options for L<IPC::Run3::run3> command.

=cut

sub run3opt($self) {
    return {
        binmode_stdout => ":encoding(utf-8)",
        binmode_stderr => ":encoding(utf-8)",
    };
}

=item C<< $driver->run_command($cmd, %opt) >>

Runs a command specified in the arrayref C<$cmd> with some additional
options.

The options C<stderr_fatal> and C<status_fatal> are same as for the contructor,
and C<input> option can be used to feed some data to the program.

The method returns a list of three items, C<stdout>, C<stderr> and C<status>.
If you don't care about these, you can call the method like this:

    my $command = [qw(pamixer --sink 0 --get-volume)];
    my ($out, undef, undef) = $self->run_command($command);

=cut

sub run_command($self, $cmd, %opt) {
    my ($stdin, $stdout, $stderr) = ($opt{stdin}, "","");

    if (!run3($cmd, \$stdin, \$stdout, \$stderr, $self->run3opt)) {
        # some fucked up commands, like pamixer, output \n\n after the command.
        $stdout =~ s/(^\s*|\s*$)//g;
        $stderr =~ s/(^\s*|\s*$)//g;
        $self->log->info("when running '", join(" ", @$cmd), "'");
        $self->log->fatal("run3 crashed");
    }

    my $status = $?;
    # IPC::Run3 does not restore encoding layers, reset them manually
    # https://rt.cpan.org/Public/Bug/Display.html?id=69011

    # Except STDIN, see 'wild-breeze' script for explanation
    # binmode STDIN;  binmode STDIN,  ":encoding(utf-8)";
    binmode STDOUT; binmode STDOUT, ":encoding(utf-8)";
    binmode STDERR; binmode STDOUT, ":encoding(utf-8)";

    $stdout =~ s/(^\s*|\s*$)//g;
    $stderr =~ s/(^\s*|\s*$)//g;

    if ($? == -1) {
        $self->log->info("when running '", join(" ", @$cmd), "'");
        $self->log->fatal("system command failed: errno=$!");
    } elsif ($? & 127) {
        $self->log->info("when running '", join(" ", @$cmd), "'");
        $self->log->fatal("command died on signal: signo=$?, ",
            "stdout='$stdout', stderr='$stderr'");
    } elsif (($? >> 8) && ($opt{status_fatal} // $self->{status_fatal})) {
        $self->log->info("when running '", join(" ", @$cmd), "'");
        $self->log->fatal("command failed: status=", ($? >> 8), " ",
            "stdout='$stdout', stderr='$stderr'");
    }

    if (($stderr ne "") && ($opt{stderr_fatal} // $self->{stderr_fatal})) {
        $self->log->info("while running '", join(" ", @$cmd), "'");
        $self->log->fatal("command write to stderr='$stderr'");
    }

    return ($stdout, $stderr, $status);
}

=back

=cut

1;
