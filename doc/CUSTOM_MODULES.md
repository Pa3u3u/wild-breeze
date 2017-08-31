# Custom modules

Modules in wild-breeze are implemented as Perl modules ("classes").
They must implement several methods, which wild-breeze calls on certain
conditions.

This document describes which methods must be provided and what are they
expected to return.

## Overview

This chapter describes the API between modules and wild-breeze.
You don't need to implement it whole, as there are parent classes you can
use to simplify the implementation.

The module is loaded after the configuration is parsed and roughly validated.

```yaml
modules:
    - my_module:
        driver:     Namespace::Module
        ...
```

In the above example, the `Breeze::Core::init_modules` method will first
load `Namespace::Module` and then call its constructor. If the constructor
fails or does not return a blessed object, the module is considered failed
and a failed placeholder is displayed instead (`Stalk::Fail`).

Once the module is initialized, each tick a method `invoke` is called,
with no parameters. This method is supposed to return a hashref which
describes what should be displayed. Detalils on this hash will be
discussed later. Similarly, when an event for the component occurs,
an appropriate method on the component is called. The event handler
can also return a hash, which has a limited ability to control the output
during the next invocation.

### Note on syntax

The following document will use signatures, which are still experimental
in Perl since 5.20 to 5.26. If you do not want to use them, it is very simple
to rewrite the examples as follows:

With signatures:

```perl
sub method($a, $b, %c) { ... }
sub method($a, $b, @c) { ... }
sub method($a, $b, $c = default_value) { ... }
```

Using original syntax:

```perl
sub method { my ($a, $b, %c) = @_; ... }
sub method { my ($a, $b, @c) = @_; ... }
sub method { my ($a, $b, $c) = @_; $c = default_value unless defined $c; ... }
```

These are not fully equivalent, however, as signatures check that provided
arguments are defined.

### Constructors

```perl
sub new($class, %args)
```

Creates a new instance of the package `$class`. Parameters are passed
in `%args`, including the name of the instance, which is passed as `name`.

The following parameters are *always* passed to the constructor from wild-breeze:

  - `name` — name of the instance,
  - `driver` — name of the module (should be equal to `__PACKAGE__`),
  - `refresh` — number of ticks between invocations, defaults to 0 if not
    specified in the configuration
  - `timeout` — how much time `invoke` and event handlers have to produce the output
  - `log` — an instance of logger, see [Logging](#logging)
  - `theme` — an instance of theme, you will probably not use

For instance,

```yaml
modules:
    - wifi:
        driver:     Leaf::IPAddr
        device:     wlp1s0
```

will call

```perl
Leaf::IPAddr->(
        # parameters from Breeze
        name    => "wifi",
        driver  => "Leaf::IPAddr",
        refresh => 0,
        timeout => 0.5,     # value in example configuration
        log     => $log,    # instance of Breeze::Logger
        theme   => $theme,  # instance of Breeze::Theme

        # custom parameters
        device  => "wlp1s0",
    );
```

Do **not** use `name`, `driver`, `refresh`, `timeout`, `log` nor `theme` parameters for
your own stuff, as they are used by wild-breeze.

### Invocation

```perl
sub invoke($self)
```

This method is called when the module component is being redrawn.
This does *not* need to be every second. If you specify `refresh: N` parameter
in the configuration and `N > 0`, then the output will be cached for `N` ticks.
The method itself can, in fact, ask wild-breeze to cache the output on demand.

If the method does not return before the timeout expires, it gets interrupted
and a failed placeholder will be shown instead. If the method timeouts or fails
too many times (see `timeouts` and `fails`, respectively), the module will be
disabled entirely.

The method **must** return a hashref, which can contain the following keys:

  - `full_text` — the text to be shown
  - `icon` and/or `text` — if either of these is defined, then both
    will be combined into `full_text` (if `full_text` is defined, it will be
    overwritten)
  - `color`, `background`, `color_grad`, `background_grad` — color of the foreground and background,
    or gradients, see [Theming](#theming) below.
  - `cache` — if defined, the output of this module will be cached for this
    amount of ticks
  - `invert` — if defined and at least 0, the output will have inverted colors
    for this amount of ticks (0 means only the current tick)
  - `blink` — if defined and at least 0, the output will blink (invert colors
    every other tick) for this amount of ticks
  - `reset_invert`, `reset_blink`, `reset_all` — if evaluates to true,
    will stop inversion, blinking or all effects respectively

Example:

```perl
    return {
        text        => "example",
        icon        => "",
        color       => "magenta",
        background  => "000000",
        cache       => 5,
    };
```

will produce ![example](example-1.png) and will cache this output for 5 ticks.

### Events

```perl
sub refresh_on_event($) { 0; }
sub refresh_on_event($) { 1; }
```

Method `refresh_on_event` is called every time an event arrives (even when
the handler does nothing). If it evaluates to true, the cached output (if any)
will be flushed and the component will be redrawn next tick.

```perl
sub on_left_click($)
sub on_middle_click($)
sub on_right_click($)
sub on_wheel_up($)
sub on_wheel_down($)
sub on_back($)
sub on_next($)
```

These methods will be called for respective events.
The handlers can do whatever they want (mind the timeout, however).

If they return a hashref (other values are ignored), then the following
keys are looked for:

   - `blink`, `invert`, `reset_invert`, `reset_blink`, `reset_all` — same meaning
     as for `invoke` method
   - `flush` — if evaluates to true, flushes the cache for this module,
     forcing redraw in the next tick; works even if `refresh_on_event`
     evaluates to 0

```perl
sub on_event($self, $event)
```

An event handler that is called for an unknown event (e.g. special buttons).
The event from i3bar is passed as the parameter, which usually contains
keys `button`, `x`, `y` and `instance` (that is, `name` in wild-breeze).
The `button` is usually just a number, so you will need to inspect it before
using. You can, for instance, use [Logging](#logging).

## Using base classes

There are two base modules you can inherit from in your own module.
You don't need to use them and you can implement a module from a scratch,
but these provide basic implementations for events and some extra features.

### `Stalk::Driver`

This module provides basic implementation for the constructor, method `invoke`
(which carps when called, so you *must* override it) and implementations
for event handles, which do nothing. `refresh_on_event` returns `0` when
called.

You can use the following template:

```perl
package REPLACE_THIS;

use utf8;
use strict;
use warnings;

use parent "Stalk::Driver";

# signatures
use feature  "signatures";
no  warnings "experimental::signatures";

sub new($class, %args) {
    my $self = $class->SUPER::new(%args);

    # initialize custom stuff

    return $self;
}

sub invoke($self) {
    # do something
    return $data;
}

# override event handlers or refresh_on_event

1;
```

The class provides getters for `log`, `name`, `timeout`
and `refresh` (`driver` woudl make no sense, as you just *know* which module
you are implementing right now), e.g. `$self->log->info("message");`.

### `Stalk::Command`

Descendant of `Stalk::Driver`, adds a special method `run_command` to simplify
calling external programs.

The constructor takes the same parameters as `Stalk::Driver`, where it also
recognizes two parameters in `%args`:

  - `stderr_fatal` — log standard outputs and status of called program
    and croak if the program writes something to its standard error output
  - `status_fatal` — log standard outputs and status of called program
    and croak if the program exits with non-zero status code

These parameters must be passed in the configuration file, however.
so you can set these parameters yourself in the constructor like this:

```perl
sub new($class, %args) {
    my $self = $class->SUPER::new(%args);
    $self->{stderr_fatal} = 1;
    $self->{status_fatal} = 1;
    return $self;
}
```

If you want to set these parameters (or disable them) only for some commands,
you can pass the parameters to `run_command`.

```perl
sub run_command($self, $cmd, %opt)
```

The parameter `$cmd` is an *arrayref* (not a string, so this can use
`fork` and `execvp`` instead of slower `system`) describing a program
to be run and its parameters, like `[qw(pamixer --sink 0 --get-volume)]`.

Options passed in `%opt` are, again, `status_fatal` and `stderr_fatal`.
These values override whatever was set in the constructor, so it is useful
to change the behaviour for some commands if the driver runs more than one.

Another option is `stdin`, which sets the standard input for the command.
If undefined, the input of the program is connected to `/dev/null`.

The method returns a list consisting of standard output, standard error output
and status of the program. If you don't care about the latter two, you can call
it like this:

```perl
my ($output, undef, undef) = $self->run_command(...);
```

## Logging

Logging facility is implemented in `Breeze::Logger`. Details on
how file or stderr loggers are implemented, please see

  - `perldoc Breeze/Logger.pm`
  - `perldoc Breeze/Logger/File.pm`
  - `perldoc Breeze/Logger/StdErr.pm`

Logger provides the following methods:

  - `info(@message)` joins the list into a single message and logs it
  - `error(@message)` joins the list into a single message and logs it as
    an error
  - `debug(@message)` joins the list and logs it if debugging is enabled
    (either by `debug: yes` configuration or `--debug` parameter)
  - `warning(@message)` logs the message as `error` and then calls `carp`
  - `fatal(@message)` logs the message as error and then calls `croak`

## Theming

In wild-breeze, theme is simply a hash of colors. More details on how
to write your own theme, see [Themes](THEMES.md).

### Single colors

When using `color` or `background` key in `invoke` method, there are several
ways to define a color:

  - `RGB` or `$RGB` hex string, e.g. `00ff00` or `$0000ff`
  - `color_name`, which will be interpreted as a name and looked up
    in the theme file, e.g. `magenta`; if not defined, the default foreground
    or background color will be used
  - `%{COLOR,COLOR,COLOR}` is a list of colors as specified above,
    the first that exists will be used. This provides a way to theme
    a component as well as define defaults when no specific theming exists.
    For example, `%{time.fg,white}` will use the color named `time.fg` if
    it exists, otherwise it will use `white`.

The theme file **must** always define the following colors:
`black`, `silver`, `white`, `red`, `green`, `blue`, `magenta`, `cyan`,
`yellow` and one of `gray` or `grey` (the other will be set to the same value).
You are encouraged to use these colors as defaults.

### Gradients

Sometimes you may need to display a color within some gradient, e.g.
battery level could have a color between red and green, depending on the
energy stored.

This is achieved by setting `color_grad` or `background_grad` keys.
These should be arrayrefs of two values, the percentage and gradient
specification.

The gradient specification is either

  - `COLOR COLOR...` list of colors (as in the previous section) delimited
    by space; if at least one color is not defined, the whole gradient is
    undefined and default is used
  - `GRADIENT_NAME` will be looked up in the theme file
  - `%{GRADIENT,...}` list of gradients separated by commas, the first
    that is *fully* defined will be used

For instance, `%{battery.@grad,@red-to-green,red yellow green}`
tries to look up a gradient named `battery.@grad` first, then
`@red-to-green` and finally `red yellow green` (which always exists, as
all these colors are *required* to exist) until one is found.

Example returned by `invoke`:

```perl
return {
    color_grad  => [
        $percentage,
        '%{battery.@grad,@red-to-green,red yellow green}'
    ],
    # ...
};
```

You should always provide a gradient consisting of basic colors at the end
of the list as a default.

### Notes on implementation

When implementing a new module, you should always provide a way to
"theme" your module. General recommendations are:

  - use color lists, the first color should be "specific" for your module,
    prefixed with some sane string a'la namespace (e.g. `imap.new_mail`),
    to avoid name clash, the last should be one of the default colors,
  - the same holds for gradients, the first should be module specific
    (e.g. `meminfo.@worse`), the last should be a list of default colors
    (e.g. `red yellow green`).
  - use `@` somewhere in gradient name to avoid name clash with colors,
    and never use `@` in names of colors. Components in wild-breeze
    use `@` just before the name of the gradient, after the "namespace",
    e.g. `battery.@grad`.

## A few notes on `invert` and `blink`

Inversion and blinking are implemented as counters (`timers` in the code,
because their original meaning was different).
Setting `invoke => N` or `blink => N` in `invoke` will start these counters,
and the component will be inverted or blink until these counters reach zero
(they decrease every tick). On the other hand, `reset...` keys destroy
these counters.

So, if you set `invert => 4`, a counter with value 4 will be created
for the module and the module will be inverted for next 4 ticks (5 if
we are counting the current tick). There is no need to return `invert`
in the next invocation; actually, since the counter is already set,
this key will be completely ignored.

As a simple optimization, setting `invert` or `blink` to zero will not
actually set any counter, but will use a global counter that is never zero
only for the current tick. Therefore, if you want the component to blink
as long as some condition holds, you can do it simply by adding
this snipped before returning the hashref from `invoke`:

```perl
my $ret = { ... };
$ret->{blink} = 0 if some_condition;
return $ret;
```

Note that setting `invert` or `blink` in event handler to 0 does not actually
do anything since events are processed "outside of ticks", so there is no
"current tick" during which the component could have this effect.

## Tips and tricks

  - you can cache the output "forever" and only redraw it on event,
    just define `refresh_on_event` to return `1` and `invoke` to return
    a hash with key `cache => "+inf"`

  - if you want to redraw the output only on certain events, define
    `refresh_on_event` to return `0` and make event handlers return
    hashref with key `flush => 1` when redraw is needed.

  - to actually reset a counter (inversion or blinking), return a hashref
    that contains `reset_invert => 1, invert => N`, as `reset` keys
    are evaluated before setting new counters
