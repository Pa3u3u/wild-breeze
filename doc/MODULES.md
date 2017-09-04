# Leaves

Modules that extend wild-breeze and draw components on the i3bar

## Quick Links

  - [`Leaf::ArchCPU`](#leafarchcpu)
  - [`Leaf::Backlight`](#leafbacklight)
  - [`Leaf::Battery`](#leafbattery)
  - [`Leaf::CustomCommand`](#leafcustomcommand)
  - [`Leaf::IMAPUnread`](#leafimapunread)
  - [`Leaf::IPAddr`](#leafipaddr)
  - [`Leaf::LED`](#leafled)
  - [`Leaf::MemInfo`](#leafmeminfo)
  - [`Leaf::PAMixer`](#leafpamixer)
  - [`Leaf::Spotify`](#leafspotify)
  - [`Leaf::Time`](#leaftime)

## How it works

In the configuration file, in the `modules` statement, you _instantiate_
a module using a _driver_. The format is as follows:

```yaml
modules:
    # other modules
    - NAME_OF_THE_INSTANCE:
        driver: NAME_OF_THE_MODULE
        # other parameters
    # other modules
```

**All** modules take the following parameters:

  - `driver` — name of the perl module that provides the implementation,
    this argument is **required**,
  - `refresh` — number of ticks between invokations, defaults to `0`
    (component is redrawn every tick)
  - `timeout` — overrides the global configuration, use scarcely

The following document describes available modules, their configuration
options and requirements (installed programs, Perl modules etc).

# `Leaf::ArchCPU`

![ArchCPU Example](archcpu.png)

Displays CPU utilization, based on what `/proc/cpuinfo` provides in ArchLinux.
This *may* work on other platforms as well, but the fields in `/proc/cpuinfo`
may have different meaning on different platforms. Contributions for
other platforms are welcome.

The foreground color changes from green to red depending on the utilization.
By default, the utilization of all processors is displayed (prefixed with `A`).
If there are at least 2 CPUs, utilizations of these can be displayed by
using side buttons on the mouse (that is,
`next` and `previous`, or `mouse button 4` and `mouse button 5` on some
platforms).

## Events

  - `mouse next` — next CPU (if there are at least 2)
  - `mouse prev` — previous CPU (if there are at least 2)

## Dependencies

None.

## Configuration parameters

 - `warning` — higher utilization than this will invert the colors
    of the component, defaults to `+inf`
 - `critical` — higher utilization than this will cause the component
    to blink, defaults to `+inf`

Example:

```yaml
- cpu:
    driver:     Leaf::ArchCPU
    warning:    80
    critical:   90
```

## Theme colors

  - `archcpu.@grad`, `cpu.@grad`, `@green-to-red`, `green yellow red`

     Color gradient that represents the utilization. The default is
     that the color goes from green to red.

# `Leaf::BackLight`

![Backlight Example](backlight.png)

Displays the current value of the backlight using information
in `/sys/class/backlight/`. Useless on workstations with displays
whose backlight is not controlled by the computer.
The component will invert for a few ticks if the value changes.

The backlight can also be changed by using wheel up and down,
but only if the program `xbacklight` is installed.
Pressing the middle button will toggle the 0% and 40% state.

Note that on some notebooks (like mine) the ACPI events can be delayed
for up to two seconds. This is a bug that has not been adressed yet,
at least I don't know about it. If changing the backlight levels
cause the module to time out, consider adding the `timeout` parameter
of at least 3 ticks to the configuration.

## Events

  - `wheel up` — increase the brightness by 5%
  - `wheel down` — decrease the brightness by 5%
  - `mouse middle click` — toggle between 40% and 0% brightness

## Dependencies

  - `extra/xorg-xbacklight` (ArchLinux)

    RandR-based backlight control application

## Configuration parameters

  - `video` (**required**) -- name of the backlight device to control,
    you can find this out by running `ls /sys/class/backlight`

Example configuration:

```yaml
- backlight:
    driver:     Leaf::BackLight
    timeout:    3
    video:      intel_backlight
```

## Theme colors

  - `backlight.@grad`, `gray white`

    Color gradient that represents the level of brightness. Low values
    are by default shown as gray, high values as white.

# `Leaf::Battery`

![Battery Example](battery.png)

Displays the battery status, which is read from `/sys/class/power_supply`.
The icons change between 5 states according to the levels from full
to empty. When charging, a lightning icon is shown instead.

The color changes, by default, from red when depleted to green when
fully charged.

If `estimate` is enabled, the component will show estimated time until
the battery is depleted, using linear regression.

## Events

None.

## Dependencies

None (except the programs you decide to use in `commands` or `events`
configuration parameters).

## Configuration parameters

  - `battery` (**required**) — name of the device to monitor, you can find
    this out by inspecting `ls /sys/class/power_supply`
  - `warning` — invert color when battery percentage is below this point,
    defaults to 20
  - `critical` — blink when battery percentage is below this point,
    defaults to 10
  - `estimate` — if defined, the module will use this many samples
    to estimate the time until battery gets fully depleted using linear
    regression; more samples will yield slower computation but
    better estimate; if value is less than 2, 2 will be used instead

Example configuration:

```yaml
- battery:
    driver:     Leaf::Battery
    battery:    BAT0
    warning:    20
    critical:   10
    estimate:   50
```

## Theme colors

  - `battery.@grad`, `@red-to-green`, `red yellow green`

     Color gradient used to indicate the power level.

# `Leaf::CustomCommand`

![CustomCommand Example](customcommand.png)

Displays output of custom commands. Can also have commands attached
to some events.

## Events

  - `mouse next` — display output of the next command if there are at least 2
  - `mouse prev` — display output of the previous command if there are at least 2
  - (events defined in configuration will invoke specified commands)

## Dependencies

None.

## Configuration parameters

  - `commands` (**required**) — an array of commands to execute, commands may be strings
    or arrays of strings
  - `icon` — icon to display
  - `color` — foreground color
  - `background` - background color
  - `invert_on_change` - number of ticks to invert the output if the output changes
  - `events` - a hash of event handlers, values are commands, keys are events:
    - `left_click`, `right_click`, `middle_click`
    - `wheel_up`, `wheel_down`

Note that `invert_on_change` of value 0 will invert the output in the current
tick only. To disable inversion entirely, do *not* define this property
(or set it to `null` or `~`).

Example configurations:

```yaml
- whoami:
    driver:     Leaf::CustomCommand
    icon:       
    color:      'cyan'
    commands:
        - "id -n -u"
        - "id -u"
        - "id -g -n"
        - "id -g"
        - "id -G"

- keyboard:
    driver:     Leaf::CustomCommand
    icon:       
    color:      '%{keyboard.color,cyan}'
    invert_on_change:   0
    commands:
        - "xkb-switch"
    events:
        left_click: "xkb-switch -n"
```

## Theme colors

Only those you decide to use with `color` and `background` parameters.

# `Leaf::IMAPUnread`

![IMAPUndread Example](imapunread.png)

Displays the number of unread e-mails in *subscribed* IMAP folders.
Since this operation is usually "slow" (that is, too slow to wait for the
output when redrawing i3bar), the process itself is run asynchronously.
The connection is **always** made using SSL socket.

Login information are read from muttrc file, where it loks for `imap_user` and
`imap_pass` options. If you do not use mutt or do not want wild-breeze
to read the file, just create a different file, e.g. `~/.imap_cred`:

```bash
touch ~/.imap_cred
chmod 0600 ~/.imap_cred
```

and edit the file so it says

```conf
set imap_user = "USERNAME"
set imap_pass = "PASSWORD"
```

## Events

  - `mouse left click` — check e-mails immediately

## Dependencies

  - `extra/perl-io-socket-ssl` (ArchLinux) or `IO::Socket::SSL` (CPAN)
  - `aur/perl-mail-imapclient` (AUR) or `Mail::IMAPClient` (CPAN)
  - `Async` (CPAN only)

## Configuration parameters

  - `muttrc` (**required**) — path to the `.muttrc` file (or the file you created with
    login credentials)
  - `server` (**required**) — name of the IMAP server
  - `port` (**required**) — port to connect to, usually 993
  - `check` — number of ticks between check, defaults to 60
  - `filter` — regular expression to filter folders, defaults to `^.*$`
  - `notify` — number of ticks to blink when the number of unread e-mails
    increases, defaults to 10

Example configuration:

```yaml
- mail:
    driver:         Leaf::IMAPUnread
    muttrc:         /home/cweorth/.muttrc
    server:         imap.example.com
    port:           993
    filter:         "^Personal/"
    check:          180
    notify:         5
```

## Theme colors

  - `imapunread.checking`, `aluminum`, `gray`

    When checking for new e-mails.

  - `imapunread.error`, `orange`, `red`

    When the asynchronous job failed to check new e-mails

  - `imapunread.disconnected`, `red`

    When the client failed to contact the IMAP server

  - `imapunread.new`, `white`

    When there are some new unread e-mails

  - `imapunread.unread`, `silver`

    When tere are unread e-mails, but the number did not increase since last check

  - `imapunread.nomail`, `gray`

    When there are no new or unread e-mails.

# `Leaf::IPAddr`

![IPAddr Example](ipaddr.png)

Displays information about a network interface.
By default show only an indicator whether the interface is DOWN (gray), UP
with no IPs (orange) or UP (green).

Adresses are parsed from the output of `ip addr show DEVICE`. Only
adresses with `scope global` are shown.

## Events

  - `mouse left click` — toggle visibility of IP addresses
  - `mouse next` — show next IP address if there are more than 1
  - `mouse prev` - show previous IP address if there are more than 1

## Dependencies

None.

## Configuration parameters

  - `device` (**required**) — name of the network card to monitor, see `ip addr` to show
    available devices
  - `hidden` — initial state, if set, IP addresses will be hidden
    when started, defaults to 1
  - `icon` — icon to use, defaults to the name of device (icons are just
    strings afterall)
  - `invert_on_change` — if defined, the component will invert its colors
    for this number of ticks, undefined by default

Note that `invert_on_change` of value 0 will invert the output in the current
tick only. To disable inversion entirely, do *not* define this property
(or set it to `null` or `~`).

Example configuration:

```yaml
- wifi:
    driver:     Leaf::IPAddr
    device:     wlp1s0
    icon:       
- ethernet:
    driver:     Leaf::IPAddr
    device:     enp0s31f6
    icon:       
```

## Theme colors

  - `ipaddr.down`, `aluminum`, `gray`

    When the device is DOWN

  - `ipaddr.no_ip`, `orange`, `yellow`

    When the device is UP but has no global IP addresses or is in UNKNOWN state

  - `ipaddr.up`, `green`

    When the device is UP and has global state addresses

# `Leaf::LED`

![LED example](led.png)

Some notebooks, like my own, do not have LED indicators for NumLock or CapsLock.
Which is quite annoying, especially when keybindings in i3 mysteriously
stop to work. Therefore, this module parses output of `xset` and provides
state about LED indicators.

## Events

None.

## Configuration parameters

  - `key` (**required**) — name of the indicator to watch, available values are
    `NumLock`, `CapsLock` and `ScrollLock`
  - `watch_state` — if this key is defined, then the module will invert its
    colors if the indicator is in a **different** state
  - `text` — text to show, defaults to the name of the indicator,
  - `icon` — icon of the component, undefined by default

Example configuration:

```yaml
- led-numlk:
    driver:         Leaf::LED
    key:            NumLock
    text:           NumLk
    # invert when NOT turned on
    watch_state:    true
- led-capslk:
    driver:         Leaf::LED
    key:            CapsLock
    text:           CapsLk
    # invert when NOT turned off
    watch_state:    false
```

## Theme colors:

  - `led.KEY.on`, `led.on`, `green`

    When the indicator is turned on (replace KEY with the name of the indicator)

  - `led.KEY.off`, `led.off`, `aluminum`, `gray`

    When the indicator is turned off (replace KEY with the name of the indicator)

# `Leaf::MemInfo`

![MemInfo Example](meminfo.png)

This module provides information about memory usage. It can show more
"memories" (e.g. RAM and swap) or different formats (free vs used memory),
which are here called "displays" for simplicity.

## Events

  - `mouse next` — next display if there are more than 1
  - `mouse prev` — previous display if there are more than 1
  - `mouse left click` — start or stop automatic switching between displays if enabled
    by the `switch` configuration parameter

## Dependencies

  - `aur/perl-linux-meminfo` (AUR) or `Linux::MemInfo` (CPAN)

## Configuration parameters

  - `unit` — units to display memory (none, `KB`, `MB`, `GB` or `TB`), defaults to `MB`
  - `precision` — `printf`-like format string for printing numbers, defaults to `%4d`,
  - `display` - array of hashes with the following keys:
    - `icon` — icon of the display,
    - `format` — format string, see below
    - `watch` — name of the variable that controls the color, **must be a variable representing percentage**
    - `more` — either `better` or `worse`, choses the gradient based on the value of
      the variable defined in `watch`
  - `warning` — when the value of `watch` is above (`more: worse`) this percentage,
    the component will invert its colors; when `more: better` is set, `100 - warning`
    will automatically be used instead; defaults to 80
  - `critical` — similar to warning, except it will blink, defaults to 90
  - `switch` — if defined, the component will automatically switch between displays
    after this amount of invokations; can be stopped with left mouse click; must be at least 1

Note that the `switch` does **not** define ticks, since this parameter also depends
on `refresh`. If you set `switch` to 5 and `refresh` to 5, the actual number
of ticks between switching would be 25.

### Format string

An arbitrary string, where variables might occur. Variables are denoted
as `%{VARIABLE}`. Available variables are:

  - all variables found in `/proc/meminfo`
  - `MemFreePercent` — % of free memory
  - `MemUsedPercent` — % of used memory
  - `SwapFreePercent` — % of free swap
  - `SwapUsedPercent` — % of used swap
  - `Unit` - the `unit` configuration parameter

Example configuration (with default `display` parameter):

```yaml
- memory:
    driver:     Leaf::MemInfo
    warning:    80
    critical:   90
    unit:       MB
    precision:  "%4d"
    refresh:    5
    display:
        -   icon:   
            format: "%{MemUsed}/%{MemTotal} (%{MemUsedPercent}%)"
            watch:  MemUsedPercent
            more:   worse
        -   icon:   
            format: "%{SwapUsed}/%{SwapTotal} (%{SwapUsedPercent})"
            watch:  SwapUsedPercent
            more:   worse
```

# Theme colors

   - `meminfo.@better`, `@red-to-green`, `red yellow green`

     Gradient to use for displays with `more: better` option

   - `meminfo.@worse`, `@green-to-red`, `green yellow red`

     Gradient to use for displays with `more: worse` option

# `Leaf::PAMixer`

![PAMixer Example](pamixer.png)

Controls a specified sink using the `pamixer` command.

## Events

  - `wheel up` — increase the volume
  - `wheel_down` — decrease the volume
  - `mouse left click` — toggle mute
  - `mouse middle click` — set to 50%

## Dependencies

  - `community/pamixer` (ArchLinux)

    Pulseaudio command-line mixer like amixer

## Configuration parameters

  - `sink` (**required**) — device or ID of the sink, use `pamixer --list-sinks` to find out
  - `step` — % of volume to increment or decrement in a single step, defaults to 2
  - `allow-boost` — allow volumes above 100%

Although this component allows to specify a numeric ID of the sink, this is
discouraged as the ID can change from time to time. The device is listed
in the second column of the output, e.g.

```
$ pamixer --list-sinks
0 "alsa_output.pci-0000_00_1f.3.analog-stereo" "Built-in Audio Analog Stereo"
   ~~~~~~~~~~~~~~~~~ device ~~~~~~~~~~~~~~~~~
```

Example configuration:

```yaml
- volume:
    driver:         Leaf::PAMixer
    sink:           alsa_output.pci-0000_00_1f.3.analog-stereo
    allow-boost:    yes
    step:           2
```

## Theme variables

  - `volume.muted.fg`, `black`

  - `volume.muted.bg`, `silver`

    Foreground and background when the sink is muted

  - `volume.@grad`, `@red-to-green`, `red yellow green`

    Gradient of percentage used when the volume is at most 100% and not muted

  - `volume.overmax`, `cyan`

    Foreground color used when the volume is above 100% and not muted

# `Leaf::Spotify`

![Spotify Example](spotify.png)

Displays information about currently played song in Spotify.
It uses `mpris2` interface in DBus, which is unfortunately not fully
supported (e.g. playback position is not implemented).

Right mouse click on the component will toggle between various information.
By default, title and artist is shown, both at most 15 characters long.
Next three displays show title, artist and album respectively.

## Events

  - `mouse left click` — toggle play / pause
  - `mouse middle click` — show title and artist
  - `mouse right click` — next information
  - `mouse next` — next song
  - `mouse prev` — previous song

## Dependencies

  - `community/perl-net-dbus` (ArchLinux) or `Net::DBus` (CPAN)

## Configuration parameters

None.

## Theme colors

  - `spotify.offline`, `silver`

    Color when cannot connect to spotify via DBus

  - `spotify.stopped`, `red`

    When playback is stopped

  - `spotify.paused`, `orange`, `yellow`

    When playback is paused

  - `spotify.playing`, `cyan`

    When playing a song (note: this will be inverted)

  - `spotify.ad`, `magenta`

    When playing an advertisement

  - `spotify.error`, `red`

    When an error occurs when contacting DBus

## Known bugs

Sometimes, when Spotify exists, the connection to DBus takes a very long
time, which causes the module to time out.

# `Leaf:Time`

![Time Example](time.png)

Displays time. Simple as that.

## Events

None.

## Dependencies

None.

## Configuration options

  - `format` — `stftime`-like format string, defaults to `%a %F %T`, which
    generates output like `Sun 2017-09-03 21:05:01`
  - `icon` — defaults to 

## Theme colors

  - `time.color`, `silver`, `white``

    Foreground color.
