#!/bin/bash
# tb_load.vhd with ISim (ISE 14.7): the ROM and a .256 through kg_mcu in bursts into the SRAM.
#   run_load_sim.sh [GAME]   (default EXOLON; games/GAME.256 and games/GAME.SNA)
# Prints "tb_load: <n> errors".
set -e -o pipefail
SETTINGS=${ISE_SETTINGS:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}
GAME=${1:-EXOLON}
# settings64.sh takes the arguments of the script that sources it
set --
source "$SETTINGS" > /dev/null
cd "$(dirname "$0")"
OUT=build_load
mkdir -p $OUT

# the ROM and the file as hex lines; SP and the PC on the stack of the snapshot
python3 - ../roms/128_0.rom ../roms/82.rom ../games/$GAME.256 ../games/$GAME.SNA $OUT/load.hex > $OUT/regs.txt <<'EOF'
import sys
rom0, rom1, f256, sna, out = sys.argv[1:6]
data = open(rom0, "rb").read() + open(rom1, "rb").read() + open(f256, "rb").read()
open(out, "w").write("".join("%02X\n" % b for b in data))
s = open(sna, "rb").read()
sp = s[23] | s[24] << 8
pc = s[27 + sp - 0x4000] | s[27 + sp - 0x4000 + 1] << 8
print(sp, pc)
EOF
read SP PC < $OUT/regs.txt
echo "$GAME: SP $SP, PC $PC"

# the sources of the Mini G build (karabas_minig.prj) but its top, paths from $OUT
cd $OUT
grep '^verilog' ../../karabas_minig.prj | sed 's/^verilog work "\(.*\)"/..\/..\/\1/' > verilog.lst
grep '^vhdl' ../../karabas_minig.prj | grep -v karabas_minig_top | sed 's/^vhdl work "\(.*\)"/..\/..\/\1/' > vhdl.lst
vlogcomp -work work -i ../../../modules/rtl/mcu $(cat verilog.lst) $XILINX/verilog/src/glbl.v > vlogcomp.log
vhpcomp -work work $(cat vhdl.lst) ../tb_load.vhd > vhpcomp.log
fuse -top work.tb_load -top work.glbl -L unisims_ver -L unisim -o tb_load.exe \
	-generic_top "G_HEX=load.hex" -generic_top "G_SP=$SP" -generic_top "G_PC=$PC" > fuse.log
echo "run all; quit" > run.tcl
./tb_load.exe -tclbatch run.tcl > sim.log 2>&1 || true
grep -v "^ISim\|^This is a Full\|^Time resolution\|^Simulator is doing\|^Finished circuit\|^WARNING: A WEBPACK\|^#\|^$" sim.log | tail -30
grep -q "tb_load: 0 errors" sim.log
