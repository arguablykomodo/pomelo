# Pomelo

A [Lemonbar][bar] manager very heavily inspired by [succade][succade].

## Configuration

Configuration is done via INI files, located in the
`${XDG_CONFIG_DIR:-$HOME/.config}/pomelo` directory. All parameters are
optional unless specified otherwise.

- Comments are only allowed on separate lines and start with `;`.
- Integers can be written in decimal, hexadecimal, octal, or binary, as long as
  the correct prefix is used (`0x`, `0o`, or `0b`, respectively).
- Booleans must be written in all lowercase (`true` or `false`).
- Strings don't require quotes.

Check the Lemonbar manual (`man lemonbar`) for more detailed information on all
the parameters. Most non-visual parameters can be left untouched as they have
sane defaults.

An example configuration can be found in the `example` directory.

### Bar

These are all set in the `pomelo.ini` file.

|Key|Type|Description
|:-|:-|:-
|`width`|Integer|Bar width in pixels.
|`height`|Integer|Bar height in pixels.
|`x`|Integer|Bar horizontal offset in pixels.
|`y`|Integer|Bar vertical offset in pixels.
|`bottom`|Boolean|Whether or not to dock the bar at the bottom of the screen.
|`force_docking`|Boolean|Whether or not to force docking without asking the window manager.
|`fonts`|String|Fonts to use. Comma-separated.
|`wm_name`|String|Sets the `WM_NAME` atom value for the bar.
|`line_width`|Integer|Width of underlines and overlines, in pixels.
|`background_color`|String|Background color of the bar.
|`foreground_color`|String|Foreground color of the bar.
|`line_color`|String|Default color for underlines and overlines.

### Blocks

Each block on the bar corresponds to an INI file in the `blocks` directory.
There are three different kinds of blocks, which differ in the way their
command is executed:

- `once` blocks run their command only once on initialization.
- `interval` blocks repeatedly run their command on a set interval, updating
  each time.
- `live` blocks have long runnning commands, that update whenever a new line is
  printed to standard outpout.

|Key|Type|Description
|:-|:-|:-
|`command`|String|Command to run. **Required**.
|`mode`|String|Block type. Can be `once`, `interval`, or `live`. **Required**.
|`interval`|Integer|Interval at which the command should be run, in milliseconds. **Required** if `mode` is set to `interval`
|`side`|String|Side of the bar to place block in. Can be `left`, `center`, or `right`. **Required**.
|`position`|Number|Position of the block within its side. Blocks will be sorted left-to-right by this value. Not necessarily continuous.
|`left_click`|String|Command to execute when the block is left clicked.
|`middle_click`|String|Command to execute when the block is middle clicked.
|`right_click`|String|Command to execute when the block is right clicked.
|`scroll_up`|String|Command to execute when the block is scrolled up.
|`scroll_down`|String|Command to execute when the block is scrolled down.
|`margin_left`|Integer|Space added between left-adjacent blocks, in pixels.
|`margin_right`|Integer|Space added between right-adjacent blocks, in pixels.
|`padding`|Integer|Extra space added within the block, in pixels.
|`underline`|Boolean|Whether or not to draw an underline.
|`overline`|Boolean|Whether or not to draw an overline.
|`background_color`|String|Background color of the block.
|`foreground_color`|String|Foreground color of the block.
|`line_color`|String|Color of the blocks underlines/overlines.

The `margin_left`, `margin_right`, `padding`, `underline`, `overline`, and
`background_color` properties can also be set in the `[defaults]` section of
`pomelo.ini`, and will act as a fallback for any blocks that don't have these
properties set.

[bar]:https://github.com/LemonBoy/bar
[succade]:https://github.com/domsson/succade
