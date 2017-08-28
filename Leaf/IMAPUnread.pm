package Leaf::IMAPUnread;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      qw(Stalk::Command);
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Async;
use Breeze::Counter;
use IO::Socket;
use IO::Socket::SSL;
use Mail::IMAPClient;

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    foreach my $key (qw(muttrc server port)) {
        $self->log->fatal("missing '$key' in arguments")
            unless defined $args{$key};
        $self->{$key} = $args{$key};
    }

    $self->{check}  = $args{check}  // 60;
    $self->{filter} = $args{filter} // '^.*$';
    $self->{notify} = $args{notify} // 10;
    $self->{last}   = "0";
    $self->{hgi}    = [qw(  )],
    $self->{hg}     = Breeze::Counter->fixed($self->{hgi}->$#*);
    $self->get_login;
    return $self;
}

sub get_login($self) {
    $self->{muttrc} =~ s/%\{HOME\}/$ENV{HOME}/g;

    open my $mfh, "<:encoding(utf-8)", $self->{muttrc}
        or $self->log->fatal("$self->{muttrc}: $!");

    my ($user, $pass);
    while (my $line = <$mfh>) {
        chomp $line;
        next if $line =~ m/^#/ or $line =~ m/^\s*$/;

        if ($line =~ m/\bimap_user\b/) {
            ($user) = ($line =~ m/imap_user\s*=\s*["'](.*)["']/);

            if (!$user) {
                $self->log->fatal("$self->{muttrc}:$.: failed to read imap_user");
            }
        }

        if ($line =~ m/\bimap_pass\b/) {
            ($pass) = ($line =~ m/imap_pass\s*=\s*["'](.*)["']/);
    
            if (!$pass) {
                $self->log->fatal("$self->{muttrc}:$.: failed to read imap_pass\n");
            }
        }

        last if $user && $pass;
    }

    close $mfh;

    if (!defined $user || !defined $pass) {
        $self->log->fatal("$self->{muttrc}: failed to obtain imap user and password");
    }

    $self->@{qw(user pass)} = ($user, $pass);
}

sub invoke($self) {
    if (!defined $self->{job}) {
        $self->{job} = Async->new(sub { $self->get_mail; });
    }

    if (!$self->{job}->ready) {
        $self->log->debug("not ready yet");

        return {
            text    => $self->{last},
            icon    => $self->{hgi}->[int ($self->{hg}++)],
            color   => "%{imapunread.checking,aluminum,gray}",
        };
    }

    if (my $error = $self->{job}->error) {
        chomp $error;
        $self->log->error("failed to get e-mail count");
        $self->log->error($error);

        delete $self->{job};
        return {
            text    => "$self->{last}?",
            icon    => "",
            color   => "%{imapunread.error,orange,red}",
            cache   => $self->{check},
        };
    }

    my $result = $self->{job}->result;
    delete $self->{job};

    if (!defined $result || $result !~ m/^(ok:\d+|connfail)$/) {
        $self->log->error("failed to obtain result from child: ", ($result // "<undef>"));
        return {
            text    => "$self->{last}?",
            icon    => "",
            color   => "%{imapunread.error,orange,red}",
            cache   => $self->{check},
        };
    }

    if ($result eq "connfail") {
        $self->log->error("child failed to connect");

        return {
            text    => "$self->{last}?",
            icon    => "",
            color   => "%{imapunread.disconnected,red}",
            cache   => $self->{check},
        };
    }

    my (undef, $count) = split /:/, $result;

    my $ret = {
        text    => "$count",
        icon    => "",
        cache   => $self->{check},
    };

    if ($self->{last} < $count) {
        $ret->{blink} = $self->{notify} if $self->{notify};
        $ret->{color} = "%{imapunread.new,white}";
    } elsif ($count > 0) {
        $ret->{color} = "%{imapunread.unread,silver}";
    } else {
        delete $ret->{text};
        $ret->{color} = "%{imapunread.nomail,gray}";
    }

    $self->{last} = $count;
    return $ret;
}

sub on_left_click($)    { return { reset_all => 1 }; }
sub on_right_click($)   { return { reset_all => 1, flush => 1 }; }

sub connect($self) {
    $self->{socket} = IO::Socket::SSL->new(
        PeerAddr    => $self->{server},
        PeerPort    => $self->{port},
        Timeout     => 5,
    ) or return 0;

    $self->{client} = Mail::IMAPClient->new(
        Socket      => $self->{socket},
        User        => $self->{user},
        Password    => $self->{pass},
    ) or return 0;

    return defined $self->{client} && $self->{client}->IsConnected;
}

sub get_mail($self) {
    # disallow writing to stdout/stderr
    close STDOUT;
    close STDERR;

    return "connfail" unless $self->connect;

    my $unseen = 0;
    foreach my $f ($self->{client}->subscribed) {
        next unless $f =~ $self->{filter};
        $unseen += ($self->{client}->unseen_count($f) // 0);
    }

    return "ok:$unseen";
}

1;
