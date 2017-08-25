package Breeze::Theme;

use v5.26;
use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use List::Util  qw(any);

sub new($class, $log, $theme) {
    my $self = bless {
        cache   => {},
        log     => $log,
        theme   => $theme,
    }, $class;

    $self->validate;
    return $self;
}

sub cache($self)    { $self->{cache};   }
sub log($self)      { $self->{log};     }
sub palette($self)  { $self->{theme};   }

sub validate($self) {
    my @required = qw(black silver white red green blue magenta cyan yellow);
    foreach my $color (@required) {
        $self->log->fatal("theme does not define '$color'")
            unless defined $self->palette->{$color};
        $self->log->fatal("basic color '$color' is not RGB")
            unless $self->palette->{$color} =~ m/^\$?[\da-f]{6}$/i;
    }

    # special case for gray
    $self->log->fatal("theme does not define 'gray' nor 'grey'")
        if !defined $self->palette->{gray} && !defined $self->palette->{grey};

    if (defined $self->palette->{gray} xor defined $self->palette->{grey}) {
        my $color = $self->palette->{gray} // $self->palette->{grey};
        $self->palette->@{qw(gray grey)} = ($color, $color);
    }

    $self->log->fatal("theme defines different 'gray' and 'grey'")
        if $self->palette->{grey} ne $self->palette->{gray};
}

sub resolve($self, $colspec) {
    return $colspec         if $colspec =~ m/^\$[\da-f]{6}$/i;
    return '$' . $colspec   if $colspec =~ m/^[\da-f]{6}$/i;

    my $tmp = $self->cache->{$colspec};
    return $tmp if defined $tmp;

    $tmp = $self->palette->{$colspec};
    return $self->cache->{$colspec} = $self->resolve($tmp)
        if defined $tmp;

    if ($colspec =~ m/^\s*%\{(?<colors>[^}]+)\}\s*$/) {
        foreach my $col (split /,/, $+{colors}) {
            my $tmp = $self->resolve($col);
            return $tmp if defined $tmp;
        }
    }

    return;
}

sub solve_gradient($self, $grad) {
    my $tmp = $self->cache->{"grad:" . $grad};
    return $tmp if defined $tmp;

    if (defined($tmp = $self->palette->{$grad})) {
        return $self->cache->{"grad:" . $grad} = $self->solve_gradient($tmp);
    }

    if ($grad =~ m/^\s*%\{(?<grads>[^}]+)\}\s*$/) {
        foreach my $gr (split /,/, $+{grads}) {
            my $tmp = $self->solve_gradient($gr);
            next if !defined $tmp;
            return ($self->cache->{"grad:" . $grad} = $tmp);
        }
    }

    # last resort, a sequence of colors
    my @colors = map {
        $_ = $self->resolve($_);
        s/^\$// if defined;
        $_;
    } (split ' ', $grad);

    return if !@colors || any { !defined } @colors;

    return ($self->cache->{"grad:" . $grad} = \@colors);
}

sub grad($self, $p, $grad) {
    use Data::Dumper;
    my $colors = $self->solve_gradient($grad);
    return unless defined $colors;
    return Breeze::Grad::get($p, grep { defined } @$colors);
}

# vim: syntax=perl5-24

1;
