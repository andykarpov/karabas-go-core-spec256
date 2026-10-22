#!/bin/bash
# T80se_S256 against T80se (ghdl), see tb_s256.vhd.
#   run_s256_sim.sh [cycles]   both games, the main CPU against T80se and the lanes with
#                              natural planes (= SNA RAM) against the main CPU
# Each run prints "tb_s256: <n> errors".
set -e -o pipefail
cd "$(dirname "$0")"
CYCLES=${1:-2000000}
WORK=work
CPU=../rtl/cpu
mkdir -p $WORK
GHDL="ghdl"
FLAGS="--std=93c -fexplicit --ieee=synopsys --workdir=$WORK -Wno-hide"
$GHDL -a $FLAGS $CPU/T80_Pack.vhd $CPU/T80_ALU.vhd $CPU/T80_MCode.vhd $CPU/T80_Reg.vhd \
	$CPU/T80.vhd $CPU/T80se.vhd $CPU/T80_S256.vhd $CPU/T80se_S256.vhd tb_s256.vhd
$GHDL -e $FLAGS tb_s256
fail=0
for game in EXOLON CYBERNOI; do
	echo "==== $game, natural planes, $CYCLES clocks"
	out=$($GHDL -r $FLAGS tb_s256 -gG_FILE256=../games/$game.256 -gG_ROM=../roms/82.rom \
		-gG_NATURAL=true -gG_CYCLES=$CYCLES 2>&1 | grep -v "NUMERIC_STD\|^$" || true)
	echo "$out"
	echo "$out" | grep -q "tb_s256: 0 errors" || fail=1
done
[ $fail = 0 ] && echo "==== all passed" || { echo "==== FAILED"; exit 1; }
