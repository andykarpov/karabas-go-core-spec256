# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

FPGA core for the Karabas Go / Mini / Mini G boards: **Spec256** (a ZX Spectrum 48K whose games carry 256-colour graphics in 8 bitplanes) on Xilinx Spartan-6 XC6SLX25-ftg256-2, ISE 14.7 (XST). `docs/SIMD.md` (Russian) is the design document: how Spec256 works (the execution contract of GZX and NextTang), why the old branches were wrong, the SIMD CPU, the tests and the plan with its state. Read it before changing the CPU, the loader or the video.

All three boards build from the command line on karabas-go-modules with the same `spec256.vhd`; the tops differ: the Mini G (HDMI, I2S DAC, `MCU_SCK` on a global clock pin: bursts at 32 MHz), the Mini (HDMI, sigma-delta audio pins, bursts at the link clock), the Go (analog VGA with `V_CLK`, I2S DAC, `BEEPER` pin, burst cs_n / ready on `MCU_IO(1)` / `MCU_IO(0)`, the other way round).

## Build

- `cd src && make` (all boards) or `make go` / `mini` / `minig` (synthesis, implementation, bitstream, `spec256.kg1` / `.kg2` / `.kg3`, with `core.json` / `core_mini.json` / `core_minig.json`); one step: `make minig-xst`, `-impl`, `-core`; `make minig-report` prints LUTs, slices, block RAMs and the timing result. It sources `/opt/Xilinx/14.7/ISE_DS/settings64.sh` (`ISE_SETTINGS=`). The options are those of the former Mini G `.xise` (area strategy), the same for every board.
- Inputs per board: `karabas_<board>.prj` (the source list; the shared modules as `"../modules/rtl/..."`), `.xst`, `.ucf` (pins, then the timing block), `.ut`; they are exceptions in `.gitignore`. `rtl/` holds only what the prj files use (plus `T80.vhd` / `T80se.vhd`, the reference of `tb_s256`).
- `src/make_core.py` and `src/games/spec256.py` are symlinks into the sibling repo **karabas-go-tools** (check it out next to this one); changes to the converter go there.
- `modules/` is the git submodule **karabas-go-modules** (`git submodule update --init`): `kg_mcu`, `kg_soft_switches`, `kg_osd_overlay`, `kg_sdpram`, `kg_pll`, `kg_pcm5102`, `hdmi_tx` (zhdmi). Its `CLAUDE.md` and `docs/PLAN.md` have the rules (Verilog-2001 for XST, tests, LUT and timing checks). A change to a module is made there.

Convert a game (`NAME.SNA` + `NAME.GFX` side by side, or an EmuZWin `NAME.ezx`): `python3 src/games/spec256.py src/games/EXOLON.SNA` (writes `EXOLON.256`). The converter and its formats: karabas-go-tools `spec256/README.md`, `spec256/EZX.md`.

## Tests (`src/sim`)

- `run_s256_sim.sh [cycles]` (ghdl): `tb_s256.vhd` runs `T80se` and `T80se_S256` on the games and on random code (`gen_random.py`); every clock the main CPU is compared with T80se and, with the planes equal to the SNA RAM, every lane with the main CPU. About 2 minutes at 200000 clocks. `GAMES=`, `SEEDS=` pick a subset.
- `tb_vga.vhd` (ghdl, see its header): the 0xFF passthrough of `vga_spec256` against the ordinary mode.
- `tb_hid.vhd` (ghdl, see its header): `hid_parser`, USB report keys to the ZX matrix.
- `tb_sdram_bg.v` (iverilog, see its header): the SDRAM controller of the backgrounds against a model of the SDRAM (CL2, SDR_CLK at 180 degrees).
- `tb_sram.v` (iverilog, see its header): the lane reads of `sram.v` (a lane reads at its own address only in a table of reversed bytes listed by the converter: same page, not coloured, lane addresses not all the same) and the bank of the word.
- `tb_pager.vhd` (ghdl, see its header): `#7FFD` decoding, the lock, the banks of the 4 windows.
- `run_load_sim.sh [GAME]` (ISim): `tb_load.vhd`, the two ROMs and the first 442396 bytes of a `.256` through `kg_mcu` in 32 MHz bursts into a model of the SRAM; checks every byte and the start of the CPU with the registers of the snapshot.
- A test counts only if it fails when the code it covers is broken: check new tests with a mutation in a scratch copy.

## Architecture (`src/rtl/spec256.vhd`)

- **Clocks** (`kg_pll`, VCO 675 MHz): 56.25 MHz `clk_bus` (CPU with CLKEN 3.5 MHz from `sram.v`, SRAM, SDRAM, MCU link, loaders), 27 MHz video: 720x576 at 50 Hz (CEA 576p, `sync.vhd`), so INT comes 50 times a second as on the Spectrum (640x480 at 60 Hz made the games about 19 % fast); `rtl/hdmi/hdmi_top.v` makes the pixel and 5x clocks with a DCM. The ucf has the constraints and explains each crossing; `TS_CPU` gives the paths inside the CPU 2 clocks (its registers change only on `cpu_ena`, one clock in 16, or on `DIRSet`, after which one clock has no CLKEN): keep every CPU register under CLKEN / DIRSet.
- **CPU** `rtl/cpu/T80_S256.vhd` (+ wrapper `T80se_S256.vhd`): T80 with its control and main data path unchanged plus 8 graphical lanes (`generate`) that repeat the data path (ACC, A', carry, register file, ALU, DO) on the control signals of the main CPU; the flags but the carry are the main CPU's. Lines marked `karabas:` are local changes. `T80.vhd` / `T80se.vhd` are kept as the reference of `tb_s256`. The T80 files keep the `DIR`/`DIRSet` snapshot-load ports.
- **Lane data** (`spec256.vhd` data bus mux): RAM reads give each lane its plane, the ROM gives the ROM byte, I/O reads the port value; reads of the instruction stream (`INST`) give the main byte when `GFX_INST_FROM_MAIN` (open question, docs/SIMD.md 1.2).
- **Memory** `rtl/memory/sram.v`: 72-bit words in the 16-bit SRAM, 5 accesses (`{bank, a[13:0], 3'b000}` low byte = the main byte, words `001`–`100` = planes 0-1 … 6-7), write mask `wr_mask`. `rtl/memory/pager.vhd`: `#7FFD` and the bank of an address (0–7 the RAM of the 128K, 8 ROM 0 `roms/128_0.rom`, 9 ROM 1 `roms/82.rom`); `#30` (ROM 1, banks 5/2/0, locked) on a reset and for a 48K file. No shadow screen (docs/SIMD.md 7.1).
- **Video**: VRAM copies of `4000–5FFF` (8K×8 and 8K×64, `kg_sdpram`); `rtl/video/vga_spec256.vhd`: the palette (a RAM, the `sp256.pal` of GZX by default, the game's from the `.256`), the colour rules of ZX-Poly for 0 / 0xFF (OSD Colour 0/FF), the background from a line buffer filled by `rtl/memory/sdram_bg.v` (a line ahead), the gfx path delayed 13 clocks to meet the ordinary pixel, `I_MODE` = GFX 256 switch; `sync.vhd` timing and INT (32 T-states, synchronised to the CPU clock).
- **MCU**: `kg_mcu` (ROM loader, IOCTL file loader with a write per byte, bursts up to `BURST_MAX_MHZ`), `hid_parser.vhd` (the ZX matrix and joysticks, core specific; one key of the report per clock, as in karabas-go-core-profi, for timing), `kg_soft_switches`: register n is the OSD item n of the core json. `core.json`, `core_mini.json` and `core_minig.json` must keep the same items (4/5 joysticks, 6 GFX 256, 7 Colour 0/FF, 8 AY mode, 9 pause, 10 NMI, 11 reset); a new item changes the index of those after it.
- **Sound**: `rtl/sound/ym2149.v` (MikeJ / Sorgelig, from karabas-go-core-tsconf; `MODE` 1 = the AY-3-8910 volume table) at 1.7734 MHz from a fractional strobe on `clk_bus`, ports `#FFFD` / `#BFFD` of the 128K; the mixer in `spec256.vhd` (AY ABC / ACB / mono by the OSD, the beeper and MIC of `#FE`), unsigned in the positive half of the signed 16 bits; `audio_peaks` (modules) sends the level meters to the MCU (`ENABLE_MATRIX`).
- **File loader** (`.256`): bytes `0–49151` → RAM `4000–FFFF` (banks 5, 2, 0); `49152–442367` → the planes (8 bytes per address); the last 28 → the registers (`regs`, layout in `games/spec256.py`), loaded into the CPU and all lanes with `DIRSet` when the load ends; a 48K snapshot with PC = `0x0072` (a RETN in `roms/82.rom`) so it resumes from its stacked PC, a 128K one with its PC. Then the extension (ROM planes, backgrounds, the 128K block).

## `.256` file format

49152 bytes SNA RAM + 49152 × 8 bytes planes (for each address the 8 planes: bit k of plane p = bit p of the colour of pixel k, a plain transpose of the GFX) + 28 bytes registers = **442396** bytes. Input sizes are strict: SNA 49179 (48K) or 131103 / 147487 (128K), GFX 393216, `.GFn` / `.GFA` / `.GFB` 131072. Then the optional extension `K256` (header, palette, background rules, `.GFB` and `.GFA` ROM planes, backgrounds 256×192 to the SDRAM at 64K each, the 128K block with banks 1, 3, 4, 6, 7; table in docs/SIMD.md section 7). A 48K file is version 1, byte for byte as before; `.GFA` or 128K make it version 2. The loader offsets in `spec256.vhd` and the converter go together.
