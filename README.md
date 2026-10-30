# Spec256 core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

A ZX Spectrum 48K that plays the games of the [Spec256](https://en.wikipedia.org/wiki/Spec256)
project in 256 colours, in hardware, for the Karabas Go family of boards (Xilinx Spartan-6
XC6SLX25).

Spec256 games are ordinary Spectrum games plus a second copy of their memory with 8 bits per
pixel: the game runs as usual, and every byte it moves, shifts or combines is moved, shifted and
combined in the same way in 8 bitplanes, which together make a 256-colour picture. The core does
this with one Z80 and a 64-bit "SIMD" unit next to it: 8 graphical lanes that repeat the data path
of the Z80 (registers, ALU) on the control signals of the main CPU. `docs/SIMD.md` (in Russian)
explains how it works.

| Board | Core file | Video | Audio |
|---|---|---|---|
| Karabas Go | `spec256.kg1` | VGA, 720x576 50 Hz | I2S DAC (PCM5102), beeper pin |
| Karabas Mini | `spec256.kg2` | HDMI, 720x576 50 Hz | HDMI, analog output (sigma-delta) |
| Karabas Mini G | `spec256.kg3` | HDMI, 720x576 50 Hz | HDMI, I2S DAC |

The core files are in `src/`. The Mini G core has been tested on the board; the Go and Mini cores
are built the same way but not tested on their boards yet.

## What it does

- **Spec256 graphics:** the game RAM and its 8 bitplanes, the palette of the game (`.PAL`) or the
  standard Spec256 palette (that of the GZX emulator), the ROM graphics of the game (`.GFB`).
  Colours 0 and 0xFF follow the rules of the ZX-Poly emulator (the `.CFG` of the game: the PAPER /
  INK of the attributes, colours mixed with the attribute colour); **Colour 0/FF** in the OSD can
  change that.
- **Background pictures** (`.B00`...): colour 0 shows the picture, chosen by the rules of the
  `.CFG` as the game runs; they are kept in the SDRAM of the board.
- **GFX 256** in the OSD switches between the 256-colour picture and the ordinary Spectrum picture
  at any time.
- **Computer:** a Spectrum 48K, Z80 at 3.5 MHz, the 48K ROM. The frame interrupt comes from the
  video frame, 720x576 at 50 Hz, so games run at the speed of the Spectrum.
- **Sound:** the beeper and an AY-3-8910 on the ports of the Spectrum 128 (#FFFD / #BFFD), stereo
  ABC, ACB or mono; the level meters of the board get the sound level.
- **Input:** USB keyboard; two joysticks (the joysticks of the board or USB gamepads) as Kempston,
  Sinclair 1, Sinclair 2, Cursor, QAOPM or QAOPS.
- **Loading:** a game is one `.256` file from the SD card, sent to the core in fast bursts.

Not there yet:

- The 128K Spec256 extensions (`.GF0`...`.GF7`, `.GFA`), tape, saving the game.

## Getting started

1. Copy `spec256.kg1` (Go), `spec256.kg2` (Mini) or `spec256.kg3` (Mini G) to the root of the SD
   card of the board.
2. Put `.256` games on the SD card (two are in `src/games`, see [Games](#games) to make more).
3. Choose Spec256 in the core menu. The Spectrum starts with its ROM.
4. Open the OSD with **Menu+Esc**, choose a game in **Snapshot** (or press **Menu+T**). The game
   starts right after it is loaded.

"Menu" is the Windows key of the keyboard.

## OSD menu

**Menu+Esc** opens and closes the menu.

| Item | Values | Hotkey |
|---|---|---|
| Snapshot | a `.256` game | Menu+T |
| Joystick L | Kempston / Sinclair1 / Sinclair2 / Cursor / QAOPM / QAOPS | Menu+J |
| Joystick R | the same | Menu+R |
| GFX 256 | Off / On: the ordinary or the 256-colour picture | Menu+V |
| Colour 0/FF | Auto: as the `.CFG` of the game; Attr: colour 0 is PAPER, 0xFF is INK; Palette: both from the palette; Pixel: 0xFF is the ordinary Spectrum pixel | Menu+C |
| AY mode | ABC / ACB / Mono | Menu+A |
| Pause | Off / On | Menu+P |
| NMI | the NMI of the Z80 | Menu+F12 |
| Reset | resets the Spectrum | Ctrl+Alt+Del |

## Keyboard

The USB keyboard is a Spectrum keyboard. Shift is CAPS SHIFT, Ctrl is SYMBOL SHIFT, Alt and
Caps Lock are both (extended mode). The arrow keys are CAPS SHIFT+5...8, Backspace is DELETE
(CAPS SHIFT+0), Esc is BREAK (CAPS SHIFT+SPACE), and the punctuation keys type what is printed on
them (for example `;` is SYMBOL SHIFT+O).

## Games

A Spectrum 48K snapshot (`NAME.SNA`, 49179 bytes) and its Spec256 graphics (`NAME.GFX`, 393216
bytes) make one `.256` file for the core. The Spec256 game packs have both, under the same name.
The converter is `spec256/spec256.py` of
[karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) (`src/games/spec256.py` here
is a link to it):

```
python3 spec256.py EXOLON.SNA
```

It reads `EXOLON.SNA` and `EXOLON.GFX` next to it and writes `EXOLON.256`; the other files of the
pack with the same name are added when they are there: `.PAL` (the palette), `.CFG` (the colour
rules and the rules of the backgrounds), `.GFB` (the ROM graphics), `.B00`...`.B99` (the
backgrounds). The case of the names does not matter. `--plain` writes the old format without them.

The `.256` file: the 48K of the snapshot RAM, then for every address the 8 bitplanes (bit k of
plane p is bit p of the colour of pixel k), then the registers of the snapshot, 442396 bytes; then
the extension `K256` (settings, palette, rules, ROM graphics, backgrounds 256×192), described in
`docs/SIMD.md` section 7.

## Building

The core is built with Xilinx ISE 14.7 on Linux: `cd src && make` (all three boards) or
`make go`, `make mini`, `make minig`; `make minig-report` shows the size and the timing. The board
modules are the submodule `modules/`
([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)): clone with
`git clone --recursive` or run `git submodule update --init`. The builds need the sibling repo
[karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) next to this one (for
`make_core.py` and the converter). The CPU tests (ghdl) are in `src/sim`. `CLAUDE.md` and
`docs/SIMD.md` have the details of the design and of the tests.

## Credits and license

- Spec256: the original emulator and the 256-colour versions of the games by the Spec256 project.
- The GZX emulator and NextTang: the reference for how Spec256 executes the
  games and for the palette (no code taken).
- The Spec256 core of the Reverse-U16 board: MVV; this core started as its port.
- T80: Daniel Wallner and others; YM2149 / AY: MikeJ, Sorgelig.
- Karabas Go boards and the core: Andy Karpov.

The core is under the MIT license (`LICENSE`); T80 and the YM2149 keep the licenses in their
headers.
