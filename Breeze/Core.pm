package Breeze::Core;

use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Carp;
use JSON;
use Time::HiRes;
use Time::Out   qw(timeout);
use Try::Tiny;

# Wild Breeze modules
use Breeze::Cache;
use Breeze::Counter;
use Breeze::Logger;
use Breeze::Logger::File;
use Breeze::Logger::StdErr;
use Breeze::Module;
use Breeze::Separator;
use Breeze::Theme;
use Stalk::Fail;

=head1 NAME

    Breeze::Core -- Implements main functionality of wild-breeze

=head1 DESCRIPTION

=head2 Methods

=over

=item C< new($class, $config, $theme) >

Creates a new instance of the Core. In the process, it

=over

=item validates the configuration

=item initializes loggers

=item initializes theme

=item constructs modules described in the configuration

=back

Required arguments are:

=over

=item C<$config>

parsed configuration file contents as hashref

=item C<$theme>

parsed theme file contents as hashref

=back

=cut

sub new($class, $config, $theme) {
    my $self = {
        config  => $config,
        cache   => Breeze::Cache->new,
        ticks   => Breeze::Counter->new,
    };

    bless $self, $class;

    $self->validate;
    $self->init_logger;

    $self->{theme} = Breeze::Theme->new(
        $self->log->clone(category => "Breeze::Theme"),
        $theme
    );

    $self->resolve_defaults;
    $self->init_modules;
    $self->init_events;

    $self->cache->log($self->log->clone(category => "Breeze::Cache"));

    return $self;
}

=item C<< $core->ticks >>

Returns a I<reference> to the internal L<Breeze::Counter> instance.
This counter keeps track of ticks passed since start.

=cut

sub ticks($self)    { \$self->{ticks}; }

=item C<< $core->cfg >>

=item C<< $core->theme >>

=item C<< $core->log >>

=item C<< $core->cache >>

=item C<< $core->mods >>

Getters that return configuration, theme, logger instance, cache instance
and all modules, respectively.

=cut

sub cfg($self)      { $self->{config}; }
sub theme($self)    { $self->{theme};  }
sub log($self)      { $self->{logger}; }
sub cache($self)    { $self->{cache};  }
sub mods($self)     { $self->{mods};   }

=item C<< $core->mod($name) >>

Returns a L<Breeze::Module> instance with the given name or C<undef> if
no such module exists.

=cut

sub mod($self, $name) {
    return $self->{mods_by_name}->{$name};
}

=back

=head2 Initializers (internal)

You are not supposed to call these methods directly.

=over

=item C<< $core->validate >>

Validates the configuration. Croaks if it finds errors.

=cut

sub validate($self) {
    my $cfg = $self->cfg;

    foreach my $key (qw(tick timeout timeouts failures cooldown padding
            separator theme defaults alternate modules
            )) {
        croak "'$key' is not defined in configuration"
            unless defined $cfg->{$key};
    }

    croak "tick is not a positive number"
        unless $cfg->{tick} >= 0;
    croak "timeout is not greater than zero"
        unless $cfg->{timeout} > 0;
    croak "timeouts is not greater than zero"
        unless $cfg->{timeouts} > 0;
    croak "failures is not greater than zero"
        unless $cfg->{failures} > 0;
    croak "cooldown is not greater than zero"
        unless $cfg->{cooldown} > 0;
    croak "padding is not greater than zero"
        unless $cfg->{padding} > 0;

    croak "defaults is not a hash"
        unless ref $cfg->{defaults} eq "HASH";

    foreach my $key (qw(background color border)) {
        croak "missing defaults.$key in configuration"
            unless exists $cfg->{defaults}->{$key};
    }

    croak "modules is not an array"
        unless ref $cfg->{modules} eq "ARRAY";

    my $names = {};
    foreach my $mod ($cfg->{modules}->@*) {
        if (ref $mod eq "HASH") {
            croak "empty hash in module definition"
                if scalar keys %$mod < 1;
            croak "too many keys in module definition: '" . join(",", keys %$mod), "'"
                if scalar keys %$mod > 1;

            my $key = (keys %$mod)[0];
            my $def = $mod->{$key};

            croak "missing or invalid driver option in definition of '$key'"
                unless defined $def->{driver} && length $def->{driver} > 0;

            croak "invalid timeout in definition of '$key'"
                if defined $def->{timeout} && $def->{timeout} <= 0;

            croak "invalid refresh in definition of '$key'"
                if defined $def->{refresh} && $def->{refresh} <  1;
        } elsif (ref $mod eq "") {
            croak "invalid scalar '$mod', did you want 'separator'?"
                unless $mod eq "separator";
        } else {
            croak "found " . ref($mod) . " in module definition";
        }
    }
}

=item C<< $core->u8($string) >>

Constructs a utf-8 string from a hex string ([0-9a-zA-Z]+).

=cut

sub u8($self, $what) {
    my $t = join("", map { chr(hex) } ($what =~ m/../g));
    utf8::decode($t);
    return $t;
}

=item C<< $core->resolve_defaults >>

Resolves default colors in the configuration.

=cut

sub resolve_defaults($self) {
    foreach (qw(color background border)) {
        my $ref = \$self->cfg->{defaults}->{$_};
        $$ref = $self->theme->resolve($$ref)
            if defined $$ref;
    }
}

=item C<< $core->init_logger >>

Initializes the logger as set in the configuration.

=cut

sub init_logger($self) {
    my $f = $self->cfg->{logfile};
    my %a = $self->cfg->%{qw(debug)};
    my $c = "Breeze::Core";

    if (!defined $f) {
        $self->{logger} = Breeze::Logger->new($c, %a);
    } elsif ($f eq "%STDERR") {
        $self->{logger} = Breeze::Logger::StdErr->new($c, %a);
    } else {
        $f =~ s/\$\$/$$/g;
        $self->{logger} = Breeze::Logger::File->new($c, filename => $f, %a);
    }
}

=item C<< $core->init_modules >>

Instantiates all modules described by the configuration file.
If the instantiation of a module fails, it gets replaced by L<Stalk::Fail>.
Note that if L<Stalk::Fail> itself fails, the class will intentionally croak.

=cut

sub init_modules($self) {
    $self->{mods} = [];
    $self->{mods_by_name} = {
        # fallback module
        __zero => Breeze::Module->new("__zero", { driver => "Stalk::Driver" }, {
            log         => $self->log,
            theme       => $self->theme,
            timeouts    => 0,
            failures    => 0,
        }),
    };

    # stack modules in reverse order, first module will be added to
    # the list as the last
    foreach my $modcfg ($self->cfg->{modules}->@*) {
        # is $modcfg is a scalar?
        if (ref $modcfg eq "") {
            # it might be a separator
            if ($modcfg eq "separator") {
                push $self->{mods}->@*, Breeze::Separator->new();
            # otherwise it's an error
            } else {
                $self->log->fatal("scalar '$modcfg' found instead of module description");
            }
        } elsif (ref $modcfg eq "HASH" && keys %$modcfg == 1) {
            my $name        = (keys %$modcfg)[0];
            my $template    = $modcfg->{$name};
            my $driver      = $template->{driver} // "<undef>";

            $self->log->debug("trying to instantiate '$name'($driver)");
            my $inst = try {
                if (!defined $template->{timeout}) {
                    $template->{timeout} = $self->cfg->{timeout};
                }

                # reset DIE handler
                local $SIG{__DIE__} = undef;
                Breeze::Module->new($name, $template, {
                    log         => $self->log,
                    theme       => $self->theme,
                    timeouts    => $self->cfg->{timeouts},
                    failures    => $self->cfg->{failures},
                });
            } catch {
                chomp $_;
                $self->log->error("failed to instantiate '$name'($driver)");
                $self->log->error($_);
                undef;
            };

            # if module failed
            if (!defined $inst) {
                # if it was Stalk::Fail, there is nothing else to do
                if ($driver eq "Stalk::Fail") {
                    $self->log->fatal("Stalk::Fail failed, something's gone terribly wrong");
                }

                $self->log->info("replacing with failed placeholder");

                $modcfg = {
                    "__failed_" . $self->{mods}->$#* => {
                        driver => "Stalk::Fail",
                        text    => "'$name'($driver)",
                    }
                };

                redo;
            }

            push $self->{mods}->@*, $inst;
            $self->{mods_by_name}->{$name} = $inst;
        } else {
            $self->log->error("invalid syntax in configuration file");
            $modcfg = {
                "__invalid_" . $self->{mods}->$#* => {
                    driver  => "Stalk::Fail",
                    text    => "check config",
                },
            };

            redo;
        }
    }
}

=item C<< $core->init_events >>

Initializes an array of events. This maps event numbers to their names.

=cut

sub init_events($self) {
    $self->{event_map} = [
        # 0     - unknown
        undef,
        # 1 2 3 - clicks
        qw(left_click   middle_click    right_click),
        # 4 5   - wheel
        qw(wheel_up     wheel_down),
        # 6 7   - ?
        undef, undef,
        # 8 9   - mouse side buttons
        qw(back next)
    ];
}

=item C<< $core->fail_module($module, $counter) >>

Handles a module failure using the C<$counter>.
If the C<$counter> reaches zero, the module is replaced by L<Stalk::Fail>.

=cut

sub fail_module($self, $module, $counter) {
    my $tmr = $module->get_timer($counter);

    if (!($$tmr--)) {
        $self->log->error("module depleted counter '$counter' for the last time, disabling");
        $module->fail;
        return $module->run("invoke");
    } else {
        # temporarily disable module
        return {
            instance    => "__zero",
            name        => $module->driver,
            text        => $module->name_canon,
            blink       => $self->cfg->{cooldown},
            cache       => $self->cfg->{cooldown},
            background  => "%{core.fail.bg,bg,black}",
            color       => "%{core.fail.fg,fg,orange,yellow}",
            icon        => ($counter eq "fail" ? "" : ""),
        };
    }
}

=back

=head2 Output generation

Methods associated with running modules and constructing output for i3.

=over

=item C<< $core->run >>

Calls C<invoke> on all modules, except those with cached values.
If a module timeouts or fails, it gets replaced by whatever
L</fail_module> returns.

In later methods, whatever the C<invoke> or cache returns, is called a segment.

=cut

sub run($self) {
    my $ret = [];

    foreach my $module ($self->mods->@*) {
        # separators will be handled in postprocessing
        if ($module->is_separator) {
            push @$ret, { separator => 1 };
            next;
        }

        # try to get cached output first
        my $data = $self->cache->get($module->name);

        if (!defined $data) {
            # run module
            $data = $module->run("invoke");

            if ($data->{fatal}) {
                $data = $self->fail_module($module, "fail");
            } elsif ($data->{timeout}) {
                $data = $self->fail_module($module, "timeout");
            } elsif ($data->{ok}) {
                $data = $data->{content};
            } else {
                $self->log->fatal("module wrapper did not return 'ok'");
            }
        } else {
            # ignore cached 'blink', 'invert', 'reset_blink' and 'reset_invert'
            delete $data->@{qw(blink invert cache reset_blink reset_invert reset_all)};
        }

        if (($module->refresh // 0) >= 1) {
            $self->cache->set($module->name, $data, $module->refresh);
        } elsif (defined $data->{cache} && $data->{cache} >= 0) {
            $self->cache->set($module->name, $data, $data->{cache});
        }

        push @$ret, $data;
    }

    # run post-processing
    $self->post_process($ret);

    ++$self->ticks->$*;
    return $ret;
}

=item C<< $core->post_process($ret) >>

Runs postprocessing methods below on the data returned by all modules.

=cut

sub post_process($self, $ret) {
    # process all module segments
    $self->post_process_seg($ret);

    # process inversion and blinking
    # (colors must be figured before computing separators)
    $self->post_process_inversion($ret);
    $self->post_process_blinking($ret);

    # process inverted elements
    $self->post_process_inverted($ret);

    # process separator segment
    $self->post_process_sep($ret);

    # fix colors and utf8 characters
    $self->post_process_attr($ret);

    # cleanup tags
    foreach my $seg (@$ret) {
        delete $seg->@{qw(separator text icon blink invert reset_blink reset_invert)};
    }
}

=item C<< $core->post_process_seg >>

Processes segment colors, alternating colors and builds C<full_text>
from C<icon> and/or C<text>.

=cut

sub post_process_seg($self, $ret) {
    my $alt = 0;
    foreach my $seg (@$ret) {
        # skip separators
        if (exists $seg->{separator}) {
            ++$alt;
            next;
        }

        # add defaults
        while (my ($k, $v) = each $self->cfg->{defaults}->%*) {
            next if exists $seg->{$k} || !defined $v;

            $seg->{$k} = ($k eq "background" && ($alt % 2 == 1)
                    && defined $self->cfg->{alternate})
                ? $self->cfg->{alternate}
                : $v;
        }

        # resolve gradients if required
        foreach my $k (qw(color background border)) {
            my $g = $k . "_grad";

            if (defined $seg->{$g}) {
                $seg->{$k} = $self->theme->grad((delete $seg->{$g})->@*);
            } elsif (ref $seg->{$k} eq "ARRAY") {
                $seg->{$k} = $self->theme->grad($seg->{$k}->@*);
            }
        }

        # resolve colors if required
        foreach my $k (qw(color background border)) {
            next if !defined $seg->{$k};
            $seg->{$k} = $self->theme->resolve($seg->{$k}) // $self->cfg->{defaults}->{$k};
        }

        # combine text, icon into full_text
        if (defined $seg->{text} && defined $seg->{icon}) {
            $seg->{full_text} = join " ", $seg->{icon}, $seg->{text};
        } elsif (defined $seg->{text} || defined $seg->{icon}) {
            $seg->{full_text} = join "", ($seg->{icon} // ""), ($seg->{text} // "");
        }
    }
}

=item C<< $core->post_process_inversion($ret) >>

Processes C<invert> command in the segment, from the aspect of timers.
It does not actually invert colors, as blinking might affect the
inversion again.

=cut

sub post_process_inversion($self, $ret) {
    foreach my $seg (@$ret) {
        # separators are not supposed to blink
        next if exists $seg->{separator};

        my $module = $self->mod($seg->{instance});
        $module->delete_timer("invert")
            if $seg->{reset_invert} || $seg->{reset_all};

        my $timer = $module->get_or_set_timer("invert", $seg->{invert});
        next if !defined $timer;

        # advance timer, use global if evaluates to inf
        my $tick = int($$timer == "+inf" || ref $timer eq "SCALAR"
            ? $self->ticks->$* : $$timer);

        # set inversion
        $seg->{invert} = 1 if $tick >= 0;

        # remove timer if expired
        $module->delete_timer("invert") unless $$timer--;
    }
}

=item C<< $core->post_process_blinking($ret) >>

Processes C<blink> command in the segment, from the aspect of timers.
Blinking is essentially just periodical inversion.

=cut

sub post_process_blinking($self, $ret) {
    foreach my $seg (@$ret) {
        # separators are not supposed to blink
        next if exists $seg->{separator};

        my $module = $self->mod($seg->{instance});
        $module->delete_timer("blink")
            if $seg->{reset_blink} || $seg->{reset_all};

        my $timer = $module->get_or_set_timer("blink", $seg->{blink});
        next if !defined $timer;

        # advance timer, use global if evaluates to inf
        my $tick = int($$timer == "+inf" || ref $timer eq "SCALAR"
            ? $self->ticks->$* : $$timer);

        # use xor to invert blinking if 'invert' flag is already set
        $seg->{invert} = ($seg->{invert} xor ($tick % 2 == 0));

        # remove timer if expired
        $module->delete_timer("blink") unless $$timer--;
    }
}

=item C<< $core->post_process_inverted($ret) >>

Does actual color inversion, requires processing from previous two methods.

=cut

sub post_process_inverted($self, $ret) {
    foreach my $seg (@$ret) {
        # separators are not to be inverted (here)
        next if exists $seg->{separator};

        if ($seg->{invert}) {
            # set sane defaults
            foreach (qw(color background)) {
                $seg->{$_} = $self->cfg->{defaults}->{$_}
                    unless defined $seg->{$_};
            }

            $seg->@{qw(color background)} = $seg->@{qw(background color)};
        }
    }
}

=item C<< $core->post_process_sep($ret) >>

Once colors and backgrounds of module segments are resolved, this methods
determines foreground and background colors of separators.

    M1 <SEPARATOR< M2

In above example, SEPARATOR will have background of M1 and foreground of M2.

=cut

sub post_process_sep($self, $ret) {
    my $default_bg = $self->cfg->{defaults}->{background};

    my $counter = 0;
    foreach my $ix (0..$#$ret) {
        my $sep = $ret->[$ix];
        next if !exists $sep->{separator};

        # set separator icon
        $sep->{full_text} = $self->cfg->{separator};
        # copy color of the next segment if exists
        $sep->{color} = defined $ret->[$ix + 1]
                      ? ($ret->[$ix + 1]->{background} // $default_bg)
                      : '000000';

        # first segment has no background nor border
        if (!$ix) {
            delete $sep->@{qw(background border)};
        # other segments have background of previous segments
        } else {
            delete $sep->{border};
            $sep->{background} = $ret->[$ix - 1]->{background} // $default_bg;
        }

        $sep->@{qw(name instance)} = ("__separator", "__separator_$counter");
        ++$counter;
    }
}

=item C<< $core->post_process_attr($ret) >>

Final postprocessing, which adds padding, replaces C<%utf8{...}> segments
and turns of i3 separators.

=cut

sub post_process_attr($self, $ret) {
    foreach my $seg (@$ret) {
        # final color resolution
        foreach my $col (qw(color background border)) {
            $seg->{$col} = $self->theme->resolve($seg->{$col}) if defined $seg->{$col};
        }

        # replace '%utf8{byte}' with utf8 character
        $seg->{full_text} =~ s/%utf8\{(.*?)\}/$self->u8($1)/ge;

        # add padding if requested
        if ($self->cfg->{padding} && $seg->{instance} !~ m/^__separator/) {
            my $pad = " " x $self->cfg->{padding};
            $seg->{full_text} = $pad . $seg->{full_text} . $pad;
        }

        # remove i3status separator
        $seg->{separator} = JSON::false;
        $seg->{separator_block_width} = 0;
    }
}

=back

=head2 Event processing

=over

=item C<< $core->event($event) >>

Processes event parsed from i3bar.
The event should look like this in JSON:

    {
        "name":     "name_of_component",
        "button":   button_code,
        # additional attributes
    }

=cut

sub event($self, $event) {
    my $target = $event->{instance};
    my $mod    = $self->mod($target);

    if (!defined $mod) {
        $self->log->error("got event for unknown module '$target'");
        return;
    }

    my $button = $self->event_button($event->{button});
    if (!defined $button) {
        $self->log->error("got unknown event '$event->{button}' for '$target'");
        return;
    }

    $self->cache->flush($mod->name)
        if ($mod->refresh_on_event);

    my $data = defined $button
        ? $mod->run("on_$button")
        : $mod->run("on_event", $event);

    if ($data->{fatal}) {
        $self->cache->flush($mod->name);
        $data = $self->fail_module($mod, "fail");
    } elsif ($data->{timeout}) {
        $self->cache->flush($mod->name);
        $data = $self->fail_module($mod, "timeout");
    } elsif ($data->{ok}) {
        $data = $data->{content};
    } else {
        $self->log->fatal("module wrapper did not return 'ok'");
    }

    if (defined $data and ref $data eq "HASH") {
        $self->process_event_output($mod, $data);
    } elsif (defined $data) {
        $self->log->debug("event returned ref '", ref($data), "', ignoring");
    }
}

=item C<< $core->event_button($code) >>

Translates button code to a name using a map initialized in L</init_events>.

=cut

sub event_button($self, $code) {
    return $self->{event_map}->[$code];
}

=item C<< $core->process_event_output($mod, $data) >>

If event handler returns C<HASHREF>, it is processed by this method.
It allows to set or unset timers for inversion and caching.

=cut

sub process_event_output($self, $mod, $data) {
    # module might want to redraw after event
    $self->cache->flush($mod->name)
        if $data->{flush};

    # stop timers
    $mod->delete_timer("blink")
        if $data->{reset_blink}  || $data->{reset_all};

    $mod->delete_timer("invert")
        if $data->{reset_invert} || $data->{reset_all};

    # reset timers on demand
    $mod->get_or_set_timer("blink", $data->{blink})
        if defined $data->{blink};

    $mod->get_or_set_timer("invert", $data->{invert})
        if defined $data->{invert};
}

=back

=cut

1;
