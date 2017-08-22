package Breeze::Core;

use v5.26;
use utf8;
use strict;
use warnings;

use feature     qw(signatures);
no  warnings    qw(experimental::signatures);

use Breeze::Logger;
use Breeze::Logger::File;
use Breeze::Logger::StdErr;
use Carp;
use Module::Load;
use Try::Tiny;

sub new($class, $config) {
    my $self = {
        config => $config,
    };

    bless $self, $class;

    $self->validate;
    $self->init_logger;
    $self->init_modules;
    return $self;
}

# getters
sub cfg($self) { $self->{config}; }
sub log($self) { $self->{logger}; }

# primitive validate configuration
sub validate($self) {
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
    foreach my $modcfg (reverse $self->cfg->{modules}->@*) {
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
            my $module = try {
                load $moddrv;

                # pass only the '-name' parameter and those that
                # do not begin with '-'
                my @keys = grep { $_ !~ m/^-/ } (keys $modcfg->%*);
                my %args = $modcfg->%{-name, @keys};
                $args{-log} = $self->log->clone(category => $modname);

                # create instance
                return $moddrv->new(%args);
            } catch {
                chomp $_;
                $self->log->error("failed to initialize '$modname'");
                $self->log->error($_);
                return undef;
            };

            if (!defined $module && $moddrv ne "WBM::Fail") {
                # replace module description with dummy text and redo
                $self->log->info("replacing '$moddrv' with failed placeholder");
                $modcfg = $self->failed_module($modname, $moddrv);
                redo;
            } elsif (!defined $module) {
                # WBM::Fail failed, well fuck
                $self->log->fatal("WBM::Fail failed");
            }

            # got here so far, save all
            my $entry = {
                conf => $modcfg,
                mod  => $module,
            };

            push $self->{mods}->@*, $entry;
            $self->{mods_by_name} = $entry;
        }
    }
}

sub failed_module($self, $name, $driver) {
    return {
        -name   => $name,
        -driver => "WBM::Fail",
        text    => "'$name' ($driver)",
    };
}

# vim: syntax=perl5-24

1;
