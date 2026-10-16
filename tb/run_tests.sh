#!/bin/sh
# AP68020 self-test suite under Verilator.
# Needs verilator (5.x), vasmm68k_mot (vbcc) and python3.
# Usage: [FAST_PORT=1] [DATA_CACHE=0] sh run_tests.sh [workdir]
#   FAST_PORT=1   RAM through the native port
#   DATA_CACHE=0  build without the (native-port) data cache
set -eu
cd "$(dirname "$0")"

VASM=${VASM:-vasmm68k_mot}
RTL=../rtl
WORK=${1:-build}
mkdir -p "$WORK"

SRC="$RTL/ap020_top.v $RTL/ap020_core.v $RTL/ap020_memsys.v $RTL/ap020_cache.v \
     $RTL/ap020_bus.v $RTL/ap020_alu.v $RTL/ap020_muldiv.v $RTL/ap020_regfile.v"

PROGS="t_integer t_exceptions t_bus t_m020 t_cp t_callm t_rec_rmw_postincrement t_rec_software_moves_byte t_rec_software_movem_word t_rec_pipeline_completion t_rec_rte_validation"
HALTPROGS="t_dblfault"

echo "== assembling test programs =="
for t in $PROGS $HALTPROGS; do
	[ -f "asm/$t.s" ] || continue
	$VASM -Fbin -m68020 -m68851 -no-opt -o "$WORK/$t.bin" "asm/$t.s" >/dev/null
	python3 bin2hex.py "$WORK/$t.bin" "$WORK/$t.hex"
done

# compiled C programs (tb/c): vbcc for the 68020, linked flat behind
# tb/c/start.s (vectors at 0, code from $400) by vlink.  dhry is Dhrystone
# 2.1; it checks its final values and reports clocks, Dhrystones/s and DMIPS.
VBCC=${VBCC:-/opt/amiga-cc/vbcc}
export VBCC
CPROGS=""
if [ -x "$VBCC/bin/vc" ]; then
	VC="$VBCC/bin/vc"; VLINK="$VBCC/bin/vlink"
	$VASM -quiet -Fhunk -m68020 -o "$WORK/start.o" c/start.s
	$VC +aos68k -c -O2 -speed -cpu=68020 -DTIME -o "$WORK/dhry_1.o" c/dhry_1.c > "$WORK/dhry.compile.log" 2>&1
	$VC +aos68k -c -O2 -speed -cpu=68020 -DTIME -o "$WORK/dhry_2.o" c/dhry_2.c >> "$WORK/dhry.compile.log" 2>&1
	$VLINK -brawbin1 -o "$WORK/dhry.bin" "$WORK/start.o" "$WORK/dhry_1.o" "$WORK/dhry_2.o"
	python3 bin2hex.py "$WORK/dhry.bin" "$WORK/dhry.hex"
	CPROGS="dhry"
else
	echo "  (vbcc not found at $VBCC: compiled C programs skipped)"
fi

VFLAGS="--binary --timing -Wno-fatal -Wno-lint -Wno-style -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-CASEINCOMPLETE \
        --output-split 20000 --output-split-cfuncs 500 -CFLAGS -O1 -I$RTL -I$RTL/core"

echo "== compiling =="
build() {
	name=$1; top=$2; shift 2
	# shellcheck disable=SC2086
	verilator $VFLAGS --top-module "$top" --Mdir "$WORK/obj_$name" -o "tb_$name" "$@" \
	    > "$WORK/build_$name.log" 2>&1 || { echo "  BUILD FAIL  $name  (see $WORK/build_$name.log)"; exit 1; }
}
build bus  tb_ap020_bus     tb_ap020_bus.sv $RTL/ap020_bus.v &
pid_bus=$!
build prog tb_ap020_program "-GFAST_PORT=${FAST_PORT:-0}" "-GDATA_CACHE=${DATA_CACHE:-1}" tb_ap020_program.sv $SRC &
pid_prog=$!
wait $pid_bus || exit 1
wait $pid_prog || exit 1

echo "== running =="
fail=0
run() {
	name=$1; shift
	rc=0
	"$@" > "$WORK/$name.log" 2>&1 || rc=$?
	if [ "$rc" -eq 0 ] && grep -q "ALL TESTS PASSED" "$WORK/$name.log" && ! grep -Eq 'TEST FAILED|FAIL:' "$WORK/$name.log"; then
		echo "  pass  $name"
	else
		echo "  FAIL  $name  (see $WORK/$name.log)"
		fail=1
	fi
}
run bus "$WORK/obj_bus/tb_bus"
for t in $PROGS; do
	[ -f "$WORK/$t.hex" ] || continue
	run "$t" "$WORK/obj_prog/tb_prog" "+prog=$WORK/$t.hex"
	run "${t}_waits" "$WORK/obj_prog/tb_prog" "+prog=$WORK/$t.hex" +waits=2
done
for t in $CPROGS; do
	run "$t" "$WORK/obj_prog/tb_prog" "+prog=$WORK/$t.hex" +maxclk=20000000
	run "${t}_waits" "$WORK/obj_prog/tb_prog" "+prog=$WORK/$t.hex" +maxclk=40000000 +waits=2
	grep -h "^BENCH" "$WORK/$t.log" "$WORK/${t}_waits.log" | sed 's/^/        /'
done
for t in $HALTPROGS; do
	[ -f "$WORK/$t.hex" ] || continue
	run "$t" "$WORK/obj_prog/tb_prog" "+prog=$WORK/$t.hex" +expect_halt
done

if [ $fail -eq 0 ]; then echo "AP68020: ALL TESTS PASSED"; else echo "AP68020: FAILURES"; exit 1; fi
