# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

FPGA core for the Karabas Go family of boards: a port of MVV's ReVerSE-U16 **Spec256** core (ZX Spectrum 48K with 256-colour graphics, where 8 "virtual" Z80s run the same program on 8 bitplanes of graphics data). Written in VHDL/Verilog for Xilinx Spartan-6 (xc6slx25-ftg256), built with **Xilinx ISE** (no Makefile, simulation, or tests in the repo). Code comments are often in Russian.

All sources live under `src/`; paths in the `.xise` projects are relative to `src/`.

## Board variants

| Board | ISE project | Top entity | UCF | Bitstream | core json | Packaged core |
|---|---|---|---|---|---|---|
| Karabas Go | `karabas-go.xise` | `karabas_go_top.vhd` | `karabas_go.ucf` | `karabas_go.bin` | `core.json` | — |
| Karabas Mini | `karabas-mini.xise` | `karabas_mini_top.vhd` | `karabas_mini.ucf` | `karabas_mini.bin` | `core_mini.json` | `spec256.kg2` |
| Karabas Mini G | `karabas-minig.xise` | `karabas_minig_top.vhd` | `karabas_minig.ucf` | `karabas_minig.bin` | `core_minig.json` | `spec256.kg3` |

Each board top only adapts board I/O (HDMI/DVI encoders, audio DAC, MCU SPI) and instantiates the shared `rtl/spec256.vhd`. Mini/Mini G output HDMI via `rtl/hdmi/zhdmi_top.v` + `rtl/zhdmi/*`; Go uses `pcm5102.v` for audio.

**Branch `simd` caveat:** only `karabas-mini.xise` has been updated to the new SIMD design (`rtl/cpu/gfx_cpu.vhd`). `karabas-go.xise` and `karabas-minig.xise` still list the old `rtl/cpu/T80se64.vhd` (8 parallel T80s) and don't include `gfx_cpu.vhd`, so they won't build against the current `spec256.vhd` until their file lists are updated. `core_mini.json` also has an extra "GFX 256" on/off OSD switch that the other jsons lack.

## Commands

Synthesize/implement in ISE (open the `.xise`, Generate Programming File; bitgen must produce the `.bin`). Then package a core file for the Karabas Go firmware (run from `src/`):

```sh
python3 make_core.py core_mini.json spec256.kg2
python3 make_core.py core_minig.json spec256.kg3
```

Convert a Spec256 game (`NAME.SNA` + `NAME.GFX` side by side) into the `.256` format loaded by the core:

```sh
python3 src/games/spec256.py src/games/EXOLON.SNA   # writes EXOLON.256 next to it (needs numpy)
```

## Architecture (`rtl/spec256.vhd`)

- **Clocks** (`rtl/clock/clock.vhd`): 56 MHz system/memory clock (`clk_sdram`, also the CPU clock gated by `cpu_ena`), 25.2 MHz VGA clock.
- **CPU0**: a single `t80se` (Z80) running the real program. The T80 sources in `rtl/cpu/` are **locally modified**: extra ports `MC_O`, `TS_O`, `IR_O`, `PC_O`, `REG` (expose internal state) and `DIR`/`DIRSet` (load all registers at once, used to restore snapshot registers). Keep these when touching T80 files.
- **GFX SIMD extender** (`rtl/cpu/gfx_cpu.vhd`, `U8`): instead of 8 extra Z80s, it snoops CPU0's bus, opcode bytes, M-cycle/T-state and registers, decodes the instructions that move/compute data (LD A,(HL)/(BC)/(DE)/(nn)/(IX+d)/(IY+d), ALU ops with (HL), POP AF, LDI/LDIR…), and applies them to an 8-lane vector register file (8×8-bit). It produces the 64-bit `gfx_do` written to memory alongside CPU0's byte.
- **Memory** (`rtl/memory/sram.v`): external SRAM accessed as 72-bit words — bits `[7:0]` are CPU0's byte, `[71:8]` are the 8 graphic bitplane bytes for the same address — with a 9-bit write mask and a `do_rdy` strobe consumed by `gfx_cpu`. ROM area (`0000–3FFF`) returns the CPU0 byte replicated to all 8 lanes.
- **Video**: two dual-port VRAM copies of the screen area (`4000–5FFF`): 8K×8 (normal ZX screen) and 8K×64 (bitplanes). `rtl/video/vga_spec256.vhd` combines them into 256-colour output; `I_MODE` (OSD "GFX 256" switch) selects normal vs 256-colour. `sync.vhd` generates timing and the 50 Hz INT.
- **MCU / OSD**: the board's MCU talks over SPI (`rtl/mcu/mcu.vhd`) providing USB HID keyboard/joysticks (`hid_parser.vhd` → ZX 8×5 matrix + Kempston/Sinclair/cursor/QAOP), soft switches from the OSD (`soft_switches*.vhd`), ROM loading and file loading. OSD menu items are defined in the `core*.json` files; the MCU sends each item's 0-based position in the `osd` list as the command index that `soft_switches*.vhd` decodes (e.g. in Mini: 4/5 = joysticks, 6 = GFX mode, 7 = pause, 8 = NMI, 9 = reset), so inserting/reordering json items requires updating the matching `soft_switches` file.
- **File loader**: on `.256` load, bytes are routed by offset: `0–49151` → CPU0 RAM at `4000–FFFF`; `49152–442367` → bitplane RAM (8 bytes per address, assembled into 64-bit words); last 28 bytes → register image (`regs`, 224 bits, layout documented in `games/spec256.py`), applied via `DIRSet`, plus border colour. PC is set to `0x0072` (a RETN in the 48K ROM `roms/82.rom`) so execution resumes from the SNA's stacked PC.

## `.256` file format

`49152` bytes SNA RAM + `49152×8` bytes bitplanes (for each address, 8 bytes where byte *n* holds bit *n* of the 8 GFX pixels — i.e. GFX is transposed into bitplanes; addresses whose GFX is all zero or contains `0xFF` fall back to the SNA byte in every plane) + `28` bytes registers = **442396** bytes. Input sizes are strict: SNA 49179 bytes, GFX 393216 bytes. If the loader offsets in `spec256.vhd` change, `games/spec256.py` must change with them (and vice versa).

## `make_core.py`

Shared across Karabas Go cores: builds the `kgo1` binary (header, bitstream, ROM block, OSD descriptor). OSD item types: `S`, `N`, `T`, `H`, `P` (text line), `F` (file mounter), `FL` (file loader). Hotkeys must be exactly one non-modifier key plus optional `Ctrl/Shift/Alt/Menu`.
