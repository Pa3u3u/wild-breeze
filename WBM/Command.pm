package WBM::Command;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      qw(WBM::Driver);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use IPC::Run3   qw(run3);

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    $self->@{qw(stderr_fatal status_fatal)} = @args{qw(stderr_fatal status_fatal)};
    return $self;
}

sub run3opt($self) {
    return {
        binmode_stdout => ":encoding(utf-8)",
        binmode_stderr => ":encoding(utf-8)",
    };
}

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
    binmode STDIN;  binmode STDIN,  ":encoding(utf-8)";
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

# vim: syntax=perl5-24

1;
