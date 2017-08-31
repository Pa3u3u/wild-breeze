package Breeze::Theme;

use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use List::Util  qw(any);

=head1 NAME

    Breeze::Theme -- implements theme functions

=head1 DESCRIPTION

=head2 Constructors

=over

=item C<< new($log, $theme) >>

Creates a new theme. The C<$theme> should be a hashref parsed from the
theme file.

=cut

sub new($class, $log, $theme) {
    my $self = bless {
        cache   => {},
        log     => $log,
        theme   => $theme,
    }, $class;

    $self->validate;
    return $self;
}

=back

=head2 Getters

=over

=item C<< $theme->cache >>

The hashref of memoized colors and definitions.

=item C<< $theme->log >>

Logger.

=item C<< $theme->palette >>

The original hashref from the theme file.
Same as what was passed as the C<$theme> argument to the constructor.

=cut

sub cache($self)    { $self->{cache};   }
sub log($self)      { $self->{log};     }
sub palette($self)  { $self->{theme};   }

=back

=head2 Methods

=over

=item C<< $theme->validate >>

Makes sure that the theme defines all basic colors, that is C<black>,
C<silver>, C<white>, C<red>, C<green>, C<blue>, C<magenta>, C<cyan>,
C<yellow> and I<one of> C<gray> I<or> C<grey>.

If the theme defines both C<gray> and C<grey>, they must be equal.
Otherwise, if there is only one defined, it the other will be set to the
same value.

=cut

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

=item C<< $theme->resolve($colorspec) >>

Resolves the color using the theme. The C<$colorspec> argument can be
in the following format:

=over

=item C<< RGB >>

Returns the color without any resolving.

    $theme->resolve("0026f3");

=item C<< color_name >>

Looks into the palette file and returns the color with the given name
or C<undef> if there is no such color.

    $theme->resolve("black");

=item C<< %{color,color,...} >>

Resolves the list of colors and returns the first that is defined.
It makes no sense to allow nested lists (e.g. C<%{A,%{B,C},D}>),
so while it B<may> work, it will more probably crash the program.
After all, it is equivalent to C<%{A,B,C,D}>.

=back

The method returns a RGB color prepended with character C<'$'> to be
immediately used in i3 protocol.

=cut

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

=item C<< $theme->_solve_gradient($grad) >>

Helper method to solve gradients in color specification.

=cut

sub _solve_gradient($self, $grad) {
    my $tmp = $self->cache->{"grad:" . $grad};
    return $tmp if defined $tmp;

    if (defined($tmp = $self->palette->{$grad})) {
        return $self->cache->{"grad:" . $grad} = $self->_solve_gradient($tmp);
    }

    if ($grad =~ m/^\s*%\{(?<grads>[^}]+)\}\s*$/) {
        foreach my $gr (split /,/, $+{grads}) {
            my $tmp = $self->_solve_gradient($gr);
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

=item C<< $theme->grad($p, $grad) >>

Returns a color from the gradient at percentage C<$p> or C<undef>
if there is no such gradient.
The gradient is specified by the C<$grad> parameter, which is a string
of one of the following formats:

=over

=item C<< color color color ... >>

a list of colors separated by whitespace

    $theme->grad($p, "red yellow green");

=item C<< named_gradiend >>

the name of the gradient that will be fetched from the palette

    $theme->grad($p, "@red-to-green");

(It is not required to use C<'@'> in names of gradients, but it is a little
convention I used to differentiate between color names and gradient names).

=item C<< %{gradient,gradient,gradient} >>

a list of gradients, the first that can be resolved will be used.

    $theme->grad($p, "%{battery.@gradient,@red-to-green,red yellow green}");

Again, it makes no sense to allow or use nested list of gradients.

=back

=cut

sub grad($self, $p, $grad) {
    my $colors = $self->_solve_gradient($grad);
    return unless defined $colors;
    return Breeze::Grad::get($p, grep { defined } @$colors);
}

=back

=cut

1;
