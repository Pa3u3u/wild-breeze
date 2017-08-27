package Breeze::Core;

use v5.26;
use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Carp;
use Data::Dumper;
use JSON::XS;
use Time::HiRes;
use Time::Out   qw(timeout);
use Try::Tiny;

# Wild Breeze modules
use Breeze::Cache;
use Breeze::Counter;
use Breeze::Instances;
use Breeze::Logger;
use Breeze::Logger::File;
use Breeze::Logger::StdErr;
use Breeze::Theme;
use Leaf::Fail;

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

    $self->cache->set_logger($self->log->clone(category => "Breeze::Cache"));

    return $self;
}

# getters
sub cfg($self)      { $self->{config}; }
sub log($self)      { $self->{logger}; }
sub cache($self)    { $self->{cache};  }
sub ticks($self)    { \$self->{ticks}; }
sub theme($self)    { $self->{theme};  }
sub mods($self)     { $self->{mods};   }

sub mod($self, $name) {
    return $self->{mods_by_name}->{$name};
}

# primitive validate configuration
sub validate($self) {
    croak "timeout is not greater than zero"
        unless $self->cfg->{timeout} > 0;
    croak "timeouts is not greater than zero"
        unless $self->cfg->{timeouts} > 0;
    croak "failures is not greater than zero"
        unless $self->cfg->{failures} > 0;
    croak "cooldown is not greater than zero"
        unless $self->cfg->{cooldown} > 0;
}

# replace utf8 hardcoded string
sub u8($self, $what) {
    my $t = join("", map { chr(hex) } ($what =~ m/../g));
    utf8::decode($t);
    return $t;
}

# initializers

sub resolve_defaults($self) {
    foreach (qw(color background border)) {
        my $ref = \$self->cfg->{defaults}->{$_};
        $$ref = $self->theme->resolve($$ref)
            if defined $$ref;
    }
}

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

sub init_modules($self) {
    $self->{mods} = [];
    $self->{mods_by_name} = {};

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
                } elsif ($template->{timeout} <= 0) {
                    $self->log->fatal("invalid timeout for '$name'($driver): $template->{timeout}");
                }

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
                # if it was Leaf::Fail, there is nothing else to do
                if ($driver eq "Leaf::Fail") {
                    $self->log->fatal("Leaf::Fail failed, something's gone terribly wrong");
                }

                $self->log->info("replacing  with failed placeholder");

                $modcfg = {
                    "__failed_" . $self->{mods}->$#* => {
                        driver => "Leaf::Fail",
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
                    driver  => "Leaf::Fail",
                    text    => "check config",
                },
            };

            redo;
        }
    }
}

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

sub fail_module($self, $module, $timer) {
    my $tmr = $module->get_timer($timer);

    if (!($$tmr--)) {
        $self->log->error("module depleted timer '$timer' for the last time, disabling");
        $module->fail;
        return $module->invoke;
    } else {
        # temporarily disable module
        return {
            text    => $module->name_canon,
            blink   => $self->cfg->{cooldown},
            cache   => $self->cfg->{cooldown},
            background  => "%{core.fail.bg,orange,yellow",
            color       => "%{core.fail.fg,fg,white}",
            icon        => ($timer eq "fail" ? "" : ""),
        };
    }
}

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

sub post_process_seg($self, $ret) {
    my $alt = 0;
    foreach my $data (@$ret) {
        # skip separators
        if (exists $data->{separator}) {
            ++$alt;
            next;
        }

        # add defaults
        while (my ($k, $v) = each $self->cfg->{defaults}->%*) {
            next if exists $data->{$k} || !defined $v;

            $data->{$k} = ($k eq "background" && ($alt % 2 == 1) && defined $self->cfg->{alternate})
                        ? $self->cfg->{alternate}
                        : $v;
        }

        # resolve colors if required
        foreach my $k (qw(color background border)) {
            next if !defined $data->{$k};
            $data->{$k} = $self->theme->resolve($data->{$k}) // $self->cfg->{defaults}->{$k};
        }

        # combine text, icon into full_text
        if (defined $data->{text} && defined $data->{icon}) {
            $data->{full_text} = join " ", $data->{icon}, $data->{text};
        } elsif (defined $data->{text} || defined $data->{icon}) {
            $data->{full_text} = join "", ($data->{icon} // ""), ($data->{text} // "");
        }
    }
}

sub post_process_inversion($self, $ret) {
    foreach my $seg (@$ret) {
        # separators are not supposed to blink
        next if exists $seg->{separator};

        my $module = $self->mod($seg->{name});
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

sub post_process_blinking($self, $ret) {
    foreach my $seg (@$ret) {
        # separators are not supposed to blink
        next if exists $seg->{separator};

        my $module = $self->mod($seg->{name});
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

sub post_process_sep($self, $ret) {
    my $default_bg = $self->cfg->{defaults}->{background};

    my $counter = 0;
    foreach my $ix (0..$#$ret) {
        my $sep = $ret->[$ix];
        next if !exists $sep->{separator};

        # set separator icon
        $sep->{full_text} = "%utf8{ee82b2}";
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

        $sep->{name} = $sep->{instance} = "__separator_$counter";
        ++$counter;
    }
}

sub post_process_attr($self, $ret) {
    foreach my $seg (@$ret) {
        # add '$' before colors if not present
        foreach my $col (qw(color background border)) {
            if (defined $seg->{$col} && $seg->{$col} !~ m/^\$/) {
                $seg->{$col} = '$' . $seg->{$col};
            }
        }

        # replace '%utf8{byte}' with utf8 character
        $seg->{full_text} =~ s/%utf8\{(.*?)\}/$self->u8($1)/ge;

        # add padding if requested
        if ($self->cfg->{padding} && $seg->{name} !~ m/^__separator_/) {
            my $pad = " " x $self->cfg->{padding};
            $seg->{full_text} =~ s/^(\S)/$pad$1/;
            $seg->{full_text} =~ s/(\S)$/$1$pad/;
        }

        # remove i3status separator
        $seg->{separator} = JSON::XS::false;
        $seg->{separator_block_width} = 0;
    }
}

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

# event processing

sub event_button($self, $code) {
    return $self->{event_map}->[$code];
}

sub process_event($self, $mod, $data) {
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

    my $data = $mod->run("on_$button");

    if ($data->{fatal}) {
        $data = $self->fail_module($mod, "fail");
    } elsif ($data->{timeout}) {
        $data = $self->fail_module($mod, "timeout");
    } elsif ($data->{ok}) {
        $data = $data->{content};
    } else {
        $self->log->fatal("module wrapper did not return 'ok'");
    }

    if (defined $data and ref $data eq "HASH") {
        $self->process_event($mod, $data);
    } elsif (defined $data) {
        $self->log->debug("event returned ref '", ref($data), "', ignoring");
    }
}

# vim: syntax=perl5-24

1;
