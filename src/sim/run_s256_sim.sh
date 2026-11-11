#!/bin/bash
# T80se_S256 against T80se (ghdl), see tb_s256.vhd. With natural planes (= SNA RAM):
# the main CPU against T80se and every lane against the main CPU, on every clock.
#   run_s256_sim.sh [cycles]   the games of ../games and random code (gen_random.py, seeds
#                              in SEEDS), 200000 clocks each by default
#   GAMES="EXOLON" SEEDS="1 2" run_s256_sim.sh ...   a subset
# Each run prints "tb_s256: <n> errors".
set -e -o pipefail
cd "$(dirname "$0")"
CYCLES=${1:-200000}
GAMES=${GAMES-EXOLON CYBERNOI}
SEEDS=${SEEDS-1 2 3 4}
WORK=work
CPU=../rtl/cpu
mkdir -p $WORK
FLAGS="--std=93c -fexplicit --ieee=synopsys --workdir=$WORK -Wno-hide"
ghdl -a $FLAGS $CPU/T80_Pack.vhd $CPU/T80_ALU.vhd $CPU/T80_MCode.vhd $CPU/T80_Reg.vhd \
	$CPU/T80.vhd $CPU/T80se.vhd $CPU/T80_S256.vhd $CPU/T80se_S256.vhd tb_s256.vhd
ghdl -e $FLAGS tb_s256
fail=0
run() { # <name> <rom> <.256>
	echo "==== $1, $CYCLES clocks"
	out=$(ghdl -r $FLAGS tb_s256 -gG_FILE256=$3 -gG_ROM=$2 -gG_NATURAL=true -gG_CYCLES=$CYCLES 2>&1 \
		| grep -v "std_logic_arith.vhdl\|NUMERIC_STD\|^$" || true)
	echo "$out"
	echo "$out" | grep -q "tb_s256: 0 errors" || fail=1
}
for game in $GAMES; do
	run $game ../roms/82.rom ../games/$game.256
done
for seed in $SEEDS; do
	python3 gen_random.py $seed $WORK/random$seed.rom $WORK/random$seed.256
	run "random code, seed $seed" $WORK/random$seed.rom $WORK/random$seed.256
done
python3 gen_table.py $WORK/table.rom $WORK/table.256
echo "==== table lookup (lane addresses), 2000 clocks"
out=$(ghdl -r $FLAGS tb_s256 -gG_FILE256=$WORK/table.256 -gG_ROM=$WORK/table.rom -gG_NATURAL=false -gG_TABLE=true -gG_CYCLES=2000 2>&1 \
	| grep -v "std_logic_arith.vhdl\|NUMERIC_STD\|^$" || true)
echo "$out"
echo "$out" | grep -q "tb_s256: 0 errors" || fail=1
python3 gen_mono.py $WORK/mono.rom $WORK/mono.256
for m in true false; do
	echo "==== ARITH_MONO $m (the A of the main CPU after arithmetic), 2000 clocks"
	out=$(ghdl -r $FLAGS tb_s256 -gG_FILE256=$WORK/mono.256 -gG_ROM=$WORK/mono.rom -gG_NATURAL=false -gG_MONO=true -gG_ARITH_MONO=$m -gG_CYCLES=2000 2>&1 \
		| grep -v "std_logic_arith.vhdl\|NUMERIC_STD\|^$" || true)
	echo "$out"
	echo "$out" | grep -q "tb_s256: 0 errors" || fail=1
done
[ $fail = 0 ] && echo "==== all passed" || { echo "==== FAILED"; exit 1; }
