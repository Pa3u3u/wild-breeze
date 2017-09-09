# Wild Breeze

`wild-breeze` is a replacement of `i3bar` with extensions and events.

![Example](full-example.png)

## Why wild-breeze?

I just used the [Project Name Generator](http://online-generator.com/name-generator/project-name-generator.php)
and I liked the name.

## Duh, I mean, why another i3status replacement?

I tried a few alternatives listed on [ArchLinux Wiki page on i3](https://wiki.archlinux.org/index.php/i3#i3bar_alternatives),
but they were either outdated, no longer supported or required too much
effort to get them running on my system.

I liked [i3status-rust](https://github.com/greshake/i3status-rust) the most,
but several plugins do not work on my system and I don't know rust, so
I couldn't fix them. I must admit that I got inspired by it's graphical design,
though.

wild-breeze provides a few advantages over these replacements, such as
  - named colors in themes
  - gradients
  - inversion and blinking on demand

There are some disadvantages, of course, like
  - it is written in Perl
  - since it is brand new, there are still some bugs (issues or patches are welcome)

## Getting Started

The following instructions will get you a running instance of `wild-breeze`.
The whole program was developed and tested on ArchLinux, so this document
provides package names from its repository or AUR. Some of the
Perl libraries are **not** available in Arch repositories (not even `aur`,
unfortunately), these you need to install using `cpan` or `cpanm`.

### Requirements

In order to run `wild-breeze` alone, you will need:

  - `core/perl`, version at least `5.20`
  - `community/awesome-terminal-fonts` or something that provides Font Awesome
  - `community/i3-wm` obviously

You should also know, and be able to, install Perl dependencies.

### Perl Dependencies

Except packages that are already in Perl Core, you may need to install
these modules:

  - `File::Slurp` (`community/perl-file-slurp`)
  - `IPC::Run3` (`extra/perl-ipc-run3`)
  - `JSON` (`community/perl-json`)
  - `Math::Gradient` (install from CPAN)
  - `Time::Format` (`community/perl-time-format`)
  - `Time::Out` (`aur/perl-time-out`)
  - `Try::Tiny` (`extra/perl-try-tiny`)
  - `YAML::Syck` (`extra/perl-yaml-syck`)

Optionally, you can install `JSON::XS` (`community/perl-json-xs`) for
faster JSON parsing and serialization.

To install CPAN modules locally without root privileges, take a look
at [`local::lib`](https://metacpan.org/pod/local::lib).

All packages can be installed using the following commands (assuming
you use `packer` for AUR repository and `cpanm` for Perl packages):

```bash
# install packages from ArchLinux repository
pacman -S --needed perl-file-slurp perl-ipc-run3 perl-json \
    perl-time-format perl-try-tiny perl-yaml-syck perl-json-xs

# install packages from AUR
packer --aur -S --noconfirm perl-time-out

# install other dependencies from CPAN
cpanm Math::Gradient
```

**NOTE**: Modules in `Leaf` namespace might need other dependencies.
Please see [Modules page](doc/MODULES.md).

## Using wild-breeze

### Configuration file

First of all, copy the [example configuration file](example.yml) to a desired
location (e.g. `~/.config/i3/breeze.yml`) and modify it as you want.
You may want to add some modules, please see the list of available modules
in the wiki page.

### Test run

Try to run wild-breeze from the command line:

    ./wild-breeze --debug --stderr ${YOUR_CONFIG_FILE} </dev/null

You may omit the path to the configuration file if you placed it in
`~/.config/i3/breeze.yml` as this is the default.
Ideally, the command should print some JSON along with debugging
information. The last two lines should be similar to

    2017-09-02 10:06:38 debg[wild-breeze] input stream ended prematurely
    ]

If there are no messages with `fail[...]`, then all seems to be OK and you may
continue to set up i3bar. Otherwise, see [Troubleshooting](#troubleshooting).

### Configuring i3bar

Open your i3 configuration (usually `~/.config/i3/config`) and change your
bar configuration, which should look like this:

```conf
bar {
    font ...
    status_command i3bar
}
```

to something like this (I use Terminus font, but you can change it if you want,
but do *not* remove the `pango:` substring):

```conf
bar {
    font pango:xos4 Terminus,Awesome 8
#   status_command i3bar
    status_command path-to-wild-breeze path-to-configuration-file
}
```

Reload i3 and enjoy!

## What next?

See the project's wiki page for more details, e.g. how to use provided
modules, how to write your own and so on.

## Troubleshooting

This section was moved to project's wiki page.

## Author

Roman Lacko (<xlacko1@fi.muni.cz>)

## License

This project is licensed under the [MIT License](LICENSE.md).
