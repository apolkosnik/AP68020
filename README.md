# AP68020

A synthesisable MC68020 in Verilog: the complete 68020 integer instruction
set, the instruction cache and the coprocessor interface, on the MC68030
bus, validated with Verilator against the *MC68020 User's Manual*, the
*MC68030 User's Manual* (for the bus), the *M68000 Family Programmer's
Reference Manual* and the WinUAE cputest corpus.

AP68020 is derived from [AP68030](https://github.com/apolkosnik/AP68030)
and fixed as an MC68020:

- **no MMU**: PMOVE, PTEST, PLOAD and PFLUSH are coprocessor-ID-0
  instructions (an MC68851 on a real system); with no coprocessor
  answering they take the Line F exception;
- **the MC68020's CACR**: E (enable), F (freeze), C (clear) and CE (clear
  entry, with CAAR); the MC68030's data cache, burst and write-allocate
  bits do not exist, so software (Kickstart, for one) identifies an
  MC68020;
- **the MC68030 bus**, which is faster than the MC68020's: asynchronous
  cycles with DSACKx and 8/16/32-bit dynamic bus sizing, synchronous
  two-clock cycles with STERM, burst line fills with CBREQ/CBACK, CIIN and
  CIOUT, half-clock bus states S0-S5, ECS/OCS, DBEN, RMC, BERR/HALT retry
  and rerun, bus arbitration, interrupt, breakpoint and coprocessor
  acknowledge cycles in CPU space, and the RESET instruction driving the
  RESET pin for 512 clocks. There is no MMUDIS, STATUS or REFILL. A board
  built for the MC68020 bus ties STERM and CBACK high, uses DSACKx and
  asserts CIIN for I/O (or builds without the data cache).

Two options go beyond the MC68020, for integrations that want speed:

- `FAST_PORT=1`: a native request/response port with line bursts, which an
  integration uses for its internal RAM instead of the pin bus;
- `DATA_CACHE=1` (the default): the MC68030's 256-byte data cache, which
  caches as it does there: pin-bus reads unless CIIN is asserted, and the
  native port. It is invisible to software: CACR's E enables it with the
  instruction cache and their bursts, C clears it. Memory changed behind
  the processor must be cleared with C or reported through the snoop
  inputs.

## Integration

`ap020_top` presents the bidirectional pins as separate input, output and
enable signals (`d_i`/`d_o`/`d_oe`, `bus_oe` for the address and strobes,
`reset_n_i`/`reset_n_oe`), so it simulates as is and wraps onto an FPGA's
tristate buffers.

| parameter | default | |
|---|---|---|
| `FAST_PORT` | 0 | enable the native RAM port |
| `DATA_CACHE` | 1 | the data cache on native-port reads |
| `PCREL_PROGRAM_SPACE` | 1 | PC-relative operand reads use program space; 0 keeps the data function code, for glue (TG68-style, as Minimig's) that treats program space as instruction fetch |

`snoop_we`/`snoop_addr` invalidate the data cache entry for a write by
another bus master, and `nmi_vec_nocache` makes the level 7 autovector
fetch bypass the data cache; tie all three to 0 for a plain MC68020.

### The native port

With `FAST_PORT=1` the integration decodes `fast_addr` and `fast_fc` and
asserts `fast_match` for its internal RAM. Ordinary instruction fetches and
data transfers then use the port; RMW cycles (TAS, CAS, CAS2) and interrupt
acknowledges stay on the pin bus.

A request is accepted on a rising edge with `fast_req && fast_ready`; its
fields stay stable until then. `fast_rw=1` reads; `fast_be[3]` selects
`fast_wdata[31:24]`, the lowest-addressed byte. Responses begin at least
one clock after acceptance with `fast_valid` and an aligned 32-bit
`fast_rdata`. The first response completes the operand; `fast_word` names
its longword within the 16-byte line. A burst read (`fast_burst`) returns
four longwords, requested one first, wrapping modulo four; `fast_last`
releases the slot. A write takes one response. There is one transaction at
a time, no response backpressure and no bus error: a target that can fault
must use the pin bus. Reset must cancel or drain an outstanding transaction
before the target accepts a new request.

## Layout

```
rtl/ap020_top.v        pin-level top: MC68030 bus signal set, reset synchroniser, options
rtl/ap020_core.v       instruction unit: prefetch pipe, decoder, sequencer, exceptions
rtl/core/*.vh          sequencer states (exec_a/b/c), decoder, frame layout, tasks
rtl/ap020_memsys.v     data/instruction units: cache lookup, write buffer, native port,
                       bus arbitration between writes, data and prefetch
rtl/ap020_cache.v      256-byte direct mapped cache (16 lines x 4 entries)
rtl/ap020_bus.v        bus controller: S0-S5 states, sizing, STERM, bursts, retry, arbitration
rtl/ap020_alu.v        ALU, barrel shifter, BCD
rtl/ap020_muldiv.v     32x32 multiply, 64/32 divide
rtl/ap020_regfile.v    D0-D7, A0-A6, USP/ISP/MSP
rtl/ap020_defs.svh     constants
tb/tb_ap020_bus.sv     pin-level bench of the bus controller with slave models
tb/tb_ap020_program.sv program bench: 1 MB RAM behind several port types, test registers
tb/tb_cp_model.svh     scripted coprocessor at CpID 1
tb/asm/*.s             self-test programs (vasm syntax)
tb/run_tests.sh        the regression
tb/cputest/            the WinUAE cputest corpus replay
syn/                   Quartus project for the timing check
doc/ARCHITECTURE.md    how the core is built
```

## Running the tests

Requirements: Verilator 5.x, `vasmm68k_mot` (vasm with the Motorola syntax
module), Python 3; vbcc for Dhrystone.

```
cd tb
sh run_tests.sh                            # the pin bus
FAST_PORT=1 sh run_tests.sh build_fast     # RAM through the native port, data cache on
FAST_PORT=1 DATA_CACHE=0 sh run_tests.sh build_nodc
./run_prog.sh t_m020 +trace                # one program, with the instruction trace
```

The programs report through memory-mapped test registers (documented at
the top of `tb/tb_ap020_program.sv`) and print the source of a failing
check. Every program also runs with two wait states on every port. A
passing program reports its clock count, instruction count and clocks per
instruction. Besides `+trace`, the bench takes `+bustrace` (bus and
native-port cycles), `+ctrace`, `+itrace`, `+rftrace` (register file
writes) and `+strace` (sequencer and memory unit state every clock, for
profiling).

| program        | covers                                                                       |
|----------------|------------------------------------------------------------------------------|
| `t_integer`    | the integer instruction set, addressing modes, condition codes, bit fields, CAS, MOVEM, MOVEP, BCD |
| `t_exceptions` | traps and frames ($0/$1/$2/$9/$A/$B), illegal/A-line/F-line, CHK/CHK2, privilege, MOVEC/MOVES, trace T1/T0, interrupts (levels, autovector, vectored, spurious, level 7 edge), STOP, master stack and throwaway frames, RTE format errors, BKPT, bus error rerun and software completion on reads, posted writes and instruction fetches, address errors, RESET |
| `t_bus`        | dynamic bus sizing through 32/16/8-bit and synchronous ports with the caches on, misaligned operands, line crossings, MOVEP, TAS/CAS RMW cycles, code from narrow ports |
| `t_m020`       | the MC68020 specifics: CACR bits, MMU instructions taking Line F (supervisor and user mode), the data cache option and its burst fills, the CIIN window, the instruction cache with C and CE/CAAR |
| `t_cp`         | the coprocessor protocol: every response primitive, cpGEN with all EA forms, cpBcc/cpDBcc/cpScc/cpTRAPcc, cpSAVE/cpRESTORE, busy, exceptions requested by the coprocessor |
| `t_dblfault`   | a bus error while stacking a bus error frame halts the processor |

`tb/cputest/run_cputest.py` replays a WinUAE cputest corpus (68020 or
68030 integer groups; see the script's header) on the processor.

## Timing and performance

`syn/run_syn.sh` runs Quartus Prime 17.0 (Cyclone V 5CSEBA6U23I7, 50 MHz
constraint, ports as virtual pins with a 2 ns budget) and prints the Fmax
summary. AP68020 reaches 52.7 MHz at the slow 1100 mV 100 C corner, with
+0.52 ns worst-case setup slack at 50 MHz across the four corners.

| FPGA resource (Cyclone V) | used |
|---|---|
| ALMs | 14,936 (36 %) |
| registers | 7,612 |
| block RAM | 5 M10K, 4,096 bits |
| DSP blocks | 4 |

Dhrystone 2.1 (`tb/c`, vbcc `-O2 -speed -cpu=68020`, caches on, 2000
runs, checked against its final values), simulated and normalised to
50 MHz:

| configuration | clocks per Dhrystone | DMIPS |
|---|---:|---:|
| synchronous burst pin bus, no wait states, data cache | 2437 | 11.68 |
| synchronous burst pin bus, no wait states, no data cache | 3116 | 9.13 |
| native port, data cache | 2496 | 11.40 |
| native port, no data cache | 4263 | 6.68 |

On the MC68020's asynchronous bus (DSACK only, no data cache) the same
build took 4549 clocks, 6.26 DMIPS.

These are simulation results; AP68020 has not been run on a board.

## Licence

GPL, see `LICENSE`.
