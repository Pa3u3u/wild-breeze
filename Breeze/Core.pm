package Breeze::Core;

use v5.26;
use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Breeze::Cache;
use Breeze::Counter;
use Breeze::Logger;
use Breeze::Logger::File;
use Breeze::Logger::StdErr;
use Carp;
use Data::Dumper;
use JSON::XS;
use Module::Load;
use Time::Out   qw(timeout);
use Try::Tiny;

sub new($class, $config) {
    my $self = {
        config  => $config,
        cache   => Breeze::Cache->new,
    };

    bless $self, $class;

    $self->validate;
    $self->init_logger;
    $self->init_modules;
    return $self;
}

# getters
sub cfg($self)      { $self->{config}; }
sub log($self)      { $self->{logger}; }
sub cache($self)    { $self->{cache};  }

sub mod($self, $name = undef) {
    return $self->{mods} if !defined $name;
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
}

# initializers
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
                push $self->{mods}->@*, { separator => undef };
            # otherwise it's an error
            } else {
                $self->log->fatal("scalar '$modcfg' found instead of module description");
            }
        } else {
            # check for required parameters
            foreach my $key (qw(-name -driver)) {
                $self->log->fatal("missing '$key' in module description")
                    unless defined $modcfg->{$key};
            }

            # check that only known keys begin with '-'
            foreach my $key (grep { $_ =~ m/^-/ } (keys $modcfg->%*)) {
                $self->log->warn("unknown '$key' in module description")
                    unless $key =~ m/^-(name|refresh|driver)$/;
            }

            my ($moddrv, $modname) = $modcfg->@{qw(-driver -name)};
            $self->log->info("trying to load '$moddrv' as '$modname'");

            # initialize the module instance
            my $modlog = $self->log->clone(category => "$modname($moddrv)");

            my $module = try {
                load $moddrv;

                # pass only the '-name' parameter and those that
                # do not begin with '-'
                my @keys = grep { $_ !~ m/^-/ } (keys $modcfg->%*);
                my %args = $modcfg->%{-name, @keys};
                $args{-log} = $modlog;

                # create instance
                return $moddrv->new(%args);
            } catch {
                chomp $_;
                $self->log->error("failed to initialize '$modname'");
                $self->log->error($_);
                return;
            };

            # module failed to initialize?
            if (!defined $module && $moddrv ne "WBM::Fail") {
                # replace module description with dummy text and redo
                $self->log->info("replacing '$moddrv' with failed placeholder");
                $modcfg = {
                    -name   => $modname,
                    -driver => "WBM::Fail",
                    text    => "'$modname' ($moddrv)",
                };

                redo;
            } elsif (!defined $module) {
                # WBM::Fail failed, well, fuck
                $self->log->fatal("WBM::Fail failed");
            }

            my %counterconf = (from => 0, step => 1, cycle => 0);

            # got here so far, save all
            my $entry = {
                conf => $modcfg,
                mod  => $module,
                tmrs => {
                    timeout => Breeze::Counter->new(%counterconf,
                        current => $self->cfg->{timeouts},
                        to      => $self->cfg->{timeouts},
                    ),
                    fail    => Breeze::Counter->new(%counterconf,
                        current => $self->cfg->{failures},
                        to      => $self->cfg->{failures},
                    ),
                },
            };

            push $self->{mods}->@*, $entry;
            $self->{mods_by_name}->{$modname} = $entry;
        }
    }
}
sub run($self) {
    my $ret;

    foreach my $entry ($self->mod->@*) {
        # separators will be handled in postprocessing
        if (exists $entry->{separator}) {
            push @$ret, { %$entry };
            next;
        }

        # try to get cached output first
        my $data = $self->cache->get($entry->{conf}->{-name});

        if (!defined $data) {
            $data = timeout($self->cfg->{timeout} => sub {
                return try {
                    $entry->{mod}->invoke;
                } catch {
                    chomp $_;
                    $self->log->error("error in '$entry->{conf}->{-name}' ($entry->{conf}->{-driver})");
                    $self->log->error($_);
                    undef;
                };
            });

            # module timeouted?
            if ($@) {
                $data = $self->timeout_module($entry);
            # module failed?
            } elsif (!defined $data) {
                $data = $self->fail_module($entry);
            }
        } else {
            # ignore cached 'blink' and 'invert'
            delete $data->@{qw(blink invert cache)};
        }

        # set entry and instance
        $data->@{qw(entry instance)} = $entry->{conf}->@{qw(-name -name)};

        if (($entry->{conf}->{-refresh} // 0) >= 1) {
            $self->cache->set($entry->{conf}->{-name}, $data, $entry->{conf}->{-refresh});
        } elsif (defined $data->{cache} && $data->{cache} >= 0) {
            $self->cache->set($entry->{conf}->{-name}, $data, $data->{cache});
        }

        push @$ret, $data;
    }

    # run post-processing
    $self->post_process($ret);

    return $ret;
}

sub u8($self, $what) {
    my $t = join("", map { chr(hex) } ($what =~ m/../g));
    utf8::decode($t);
    return $t;
}

sub post_process_seg($self, $ret) {
    foreach my $data (@$ret) {
        # skip separators
        next if exists $data->{separator};

        # add defaults
        while (my ($k, $v) = each $self->cfg->{defaults}->%*) {
            $data->{$k} = $v if !exists $data->{$k} && defined $v;
        }

        # copy colors if required
        foreach my $k (qw(color background border)) {
            next if !defined $data->{$k};
            if ($data->{$k} =~ m/^%(?<attr>color|background|border)$/) {
                $data->{$k} = $data->{$+{attr}};
            }
        }

        # combine text, icon into full_text
        if (defined $data->{text} && defined $data->{icon}) {
            $data->{full_text} = "$data->{icon} $data->{text}";
        } elsif (defined $data->{text}) {
            $data->{full_text} = $data->{text};
        }
    }
}

sub get_or_set_timer($self, $key, $timer, $ticks) {
    my $timers = $self->mod($key)->{tmrs};

    # nothing to do if no timer set and ticks is undefined
    return if !defined $timers->{$timer} && !defined $ticks;

    # create timer if there is none
    $timers->{$timer} = Breeze::Counter->new(current => $ticks)
        if !defined $timers->{$timer};

    # return a reference to the timer
    return \$timers->{$timer};
}

sub delete_timer($self, $key, $timer) {
    delete $self->mod($key)->{tmrs}->{$timer};
}

sub post_process_inversion($self, $ret) {
    foreach my $seg (@$ret) {
        # separators are not supposed to blink
        next if exists $seg->{separator};

        my $timer = $self->get_or_set_timer($seg->{entry}, "invert", $seg->{invert});
        next if !defined $timer;

        # advance timer
        my $tick  = (--$$timer)->current;

        # use xor to invert blinking if 'invert' flag is already set
        $seg->{invert} = 1 if $tick >= 0;

        # remove timer if expired
        $self->delete_timer($seg->{entry}, "invert") unless $tick;
    }
}

sub post_process_blinking($self, $ret) {
    foreach my $seg (@$ret) {
        # separators are not supposed to blink
        next if exists $seg->{separator};

        my $timer = $self->get_or_set_timer($seg->{entry}, "blink", $seg->{blink});
        next if !defined $timer;

        # advance timer
        my $tick = (--$$timer)->current;

        # use xor to invert blinking if 'invert' flag is already set
        $seg->{invert} = ($seg->{invert} xor ($tick % 2 == 0));

        # remove timer if expired
        $self->delete_timer($seg->{entry}, "blink") unless $tick;
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

        $sep->{entry} = $sep->{instance} = "__separator_$counter";
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
        if ($self->cfg->{padding} && $seg->{entry} !~ m/^__separator_/) {
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
        delete $seg->@{qw(separator text icon blink invert)};
    }
}

# vim: syntax=perl5-24

1;
