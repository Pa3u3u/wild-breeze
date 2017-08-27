package Leaf::Spotify;

use v5.26;
use utf8;
use strict;
use warnings;

use parent      "Stalk::Driver";
use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Breeze::Counter;
use Net::DBus;
use Try::Tiny;

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);
    $self->{show} = Breeze::Counter->new(to => 3, cycle => 1);
    return $self;
}

sub getobj($self) {
    my $obj = try {
        my $bus = Net::DBus->session()
            or $self->log->fatal("failed to connect to DBus");
        my $svc = $bus->get_service("org.mpris.MediaPlayer2.spotify")
            or return;
        my $obj = $svc->get_object("/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player");
        $obj->Metadata;
        return $obj;
    };

    return $obj;
}

sub wfix {
    my (undef, $text, $width) = @_;

    my $lt = length $text;
    return $text . (" " x ($width - $lt)) if $lt <= $width;

    $text .= "...";
    $lt   += 3;

    my $df = $lt - $width + 1;
    my $ix = +time % $df;
    return substr $text, $ix, $width;
}

sub show_all {
    my ($self, $status, $meta) = @_;

    my %ico = (
        Stopped     => "",
        Paused      => "",
        Playing     => "",
        PlayingAD   => "",
    );

    my $title   = $meta->{"xesam:title"};
    my $artists = join ", ", @{$meta->{"xesam:artist"}};
    utf8::decode($title);
    utf8::decode($artists);

    my $text    = sprintf "%15s | %15s", $self->wfix($title, 15), $self->wfix($artists, 15);
    my $icon    = $ico{$status};
    return ($icon, $text);
}

sub show_title {
    my ($self, $meta) = @_;

    my $title = $meta->{"xesam:title"};
    utf8::decode($title);
    return ("", "(" . $self->wfix($title, 33) . ")");
}

sub show_artist {
    my ($self, $meta) = @_;

    my $artist = join ", ", $meta->{"xesam:artist"}->@*;
    utf8::decode($artist);
    return ("", "(" . $self->wfix($artist, 33). ")");
}

sub show_album {
    my ($self, $meta) = @_;

    my $album = join ", ", $meta->{"xesam:album"};
    utf8::decode($album);
    return ("", "(" . $self->wfix($album, 33) . ")");
}

sub invoke {
    my ($self) = @_;
    my $sp;
    if (!defined ($sp = $self->getobj)) {
        return {
            icon    => "",
            text    => undef,
            color   => '%{spotify.offline,silver}',
        };
    }

    my $meta = $sp->Metadata;

    my $data = {
        ad      => scalar($meta->{"mpris:trackid"} =~ /^spotify:ad:/),
        status  => $sp->PlaybackStatus,
    };

    $data->{status} = "PlayingAd" if $data->{status} eq "Playing" && $data->{ad};

    my $show = int $self->{show};
    if (int $show == 0) {
        @{$data}{qw(icon text)} = ($self->show_all($data->{status}, $meta));
    } elsif ($show == 1) {
        @{$data}{qw(icon text)} = $self->show_title($meta);
    } elsif ($show == 2) {
        @{$data}{qw(icon text)} = $self->show_artist($meta);
    } elsif ($show == 3) {
        @{$data}{qw(icon text)} = $self->show_album($meta);
    }

    my %cm = (
        Stopped     => '%{spotify.stopped,red}',
        Paused      => '%{spotify.paused,orange,yellow}',
        Playing     => '%{spotify.playing,cyan}',
        PlayingAd   => '%{spotify.playing.ad,magenta}',
        Error       => '%{spotify.error,red}',
    );

    my $c = $cm{$self->{evstat} // $data->{status}};
    $self->{evstat} = undef;

    my $ret = {
        text        => $data->{text},
        icon        => $data->{icon},
        color       => $c,
    };

    $ret->{invert} = 0;
    return $ret;
}

sub refresh_on_event($) { 1; }

sub on_left_click($self) {
    my $sp;
    if (!defined($sp = $self->getobj)) {
        $self->{evstat} = "Error";
        return;
    }

    $sp->PlayPause;
}

sub on_middle_click($self) { $self->{show}->reset; }
sub on_right_click($self)  { ++$self->{show}; }

sub on_back($self) {
    my $sp;
    if (!defined ($sp = $self->getobj)) {
        $self->{evstat} = "Error";
        return;
    }

    $sp->Next;
}

sub on_next($self) {
    my $sp;
    if (!defined ($sp= $self->getobj)) {
        $self->{evstat} = "Error";
        return;
    }

    $sp->Previous;
}

# vim: syntax=perl5-24

1;
