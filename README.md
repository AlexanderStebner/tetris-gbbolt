# Tetris (Game Boy) - gbbolt disassembly

**Open it: <https://gbbolt.lingora.org/tetris/>**

A complete, matching disassembly of *Tetris* for the Game Boy (Nintendo, 1989), with
pseudo-code written next to every function and checked against the original code in an
emulator. It is read with [gbbolt](https://github.com/gbbolt/gbbolt): code
and pseudo-code side by side, linked line by line.

- **282 of 282 functions** have pseudo-code: 211 are verified by differential testing
  (the pseudo-code and the original code give identical results on 64 random machine
  states), the other 71 are checked (they wait for the LCD, talk to the link cable or
  never return, so they can't run in isolation).
- **Every label and RAM variable is named**, every function sits in a virtual folder
  (`game/piece`, `versus/sync`, `sound/music`, ...), which the viewer shows as a tree and
  as the chapters of a book.
- **Graphics**: tile sheets, tilemaps (drawn with the game's own loading routines),
  sprites (drawn by the game's own sprite routine), the cartridge header.
- **Sound**: the sound engine is fully annotated; all 17 songs and 14 sound effects are
  rendered from it, with a piano roll, the channel settings at every moment and mute /
  solo per channel. The song data is decoded into song headers, pattern lists and
  patterns.

## Building

The disassembly rebuilds the original ROM byte for byte. You need
[RGBDS](https://rgbds.gbdev.io) 1.0.1, Python 3.9+ with numpy, and gbbolt next to this
folder:

```
git clone https://github.com/gbbolt/gbbolt
git clone https://github.com/gbbolt/tetris-gbbolt
cd tetris-gbbolt
python ../gbbolt/tools/gbbolt.py            # build, verify, write out/site/index.html
python ../gbbolt/tools/audio.py             # render the music (needs ffmpeg)
```

The build is checked against the SHA1 of the original ROM
(`74591cc9501af93873f9a5d3eb12da12c0723bbc`, the release with mask ROM version 1, i.e. v1.1). No ROM is needed
to build it. If you put your own dump next to `game.json` as `tetris.gb`, it is compared
byte by byte and differences are reported with their address.

## Layout

```
game.json           what gbbolt needs to know about the game
src/game.asm        the main file
src/bank_000.asm    the disassembly with its annotations
src/ram.inc         RAM variables: names, types, descriptions
src/hardware.inc    hardware registers
src/folders.txt     the virtual folders
src/sound.json      how to drive the sound engine
```

## Legal

Tetris and its code, graphics and music are the property of their respective owners
(Nintendo; The Tetris Company; the music by Hirokazu Tanaka). This repository contains
no ROM. It is a research and documentation project in the tradition of other community
disassemblies; please buy the game.

The annotations, names, pseudo-code, descriptions and configuration written for this
project are available under the MIT license (see [LICENSE](LICENSE)), as far as they are
separable from the game itself.
