# Themes

Themes in wild-breeze are simply named colors and gradients. Modules
in wild-breeze should refer to these colors using names instead of
absolutes, since these cannot be themed.

## Theme file

Theme file is simply a YAML file containg a hash, where keys are names
and values are colors. The color name can refer again to another color,
which we can call an "alias".

Example:

```yaml
red:    '$ff0000'
green:  '$00ff00'
blue:   '$0000ff'
# ...

volume.overmax: cyan

@red-to-green:
    - red
    - yellow
    - green
```

## Required colors

All theme files **must** define the following colors directly (they
cannot be aliases): `black`, `silver`, `white`, `red`, `green`, `blue`,
`magenta`, `cyan`, `yellow` and one of `gray` or `grey` (the other will
be defined automatically). If the theme defines both `gray` and `grey`,
they must be equal.

## Other information

To see which colors can be used in modules, see [Modules](MODULES.md),
each module has a section called *Theme colors*.

If you want to make your module compatible with themes, see [Theming
in custom modules](CUSTOM_MODULES.md#theming).
