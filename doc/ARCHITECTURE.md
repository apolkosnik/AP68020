# AP68020 architecture

AP68020 is the AP68030 core fixed as an MC68020 -- no MMU, the MC68020's
CACR -- that keeps the MC68030 bus (synchronous cycles, bursts, CIIN,
CIOUT), which is faster than the MC68020's asynchronous one. It was derived
from AP68030 and keeps its structure, so references are to the MC68030
User's Manual (UM) sections unless the MC68020 User's Manual is named; the
two describe the same integer core, exception model, coprocessor interface
and asynchronous bus.

## Overview

```
                 +-----------------------------------------------------------+
                 |  ap020_core: instruction unit                              |
                 |  prefetch pipe (6 words) -> decoder -> sequencer -> ALU   |
                 |  exception frames, RTE rerun, coprocessor dialogue         |
                 +-----------+----------------------------+------------------+
                   i_stb/addr/fc  i_ack/data/fault   d_stb/addr/size/rw/fc  d_ack/rdata/fault
                 +-----------+----------------------------+------------------+
                 |  ap020_memsys: instruction and data units                 |
                 |  icache (logical, FC2)  dcache (native-port RAM, option)  |
                 |  write buffer (posted writes)   native port (option)      |
                 |  bus arbitration: writes > data > prefetch                |
                 +-----------------------------+-----------------------------+
                                               | request / done / fill
                 +-----------------------------+-----------------------------+
                 |  ap020_bus: bus controller (S0-S5 half-clock states)      |
                 +-----------------------------------------------------------+
```

Everything runs from one clock. The bus controller uses both clock edges
because the bus states are half clocks long: address and control outputs
change on the falling edge where the real part changes them, and the
asynchronous inputs (DSACKx, BERR, HALT, AVEC, BR, BGACK) are sampled on
the falling edge.

## Instruction unit (ap020_core.v, rtl/core/*.vh)

**Prefetch pipe.** Six words are held in `pq[0..5]` with valid and fault
bits; `pq[0]` is stage C (the word at `scan_pc`), `pq[1]` stage B. The
instruction port fetches longwords with up to two fetches outstanding
(`fetch_out`, returned in order; `fetch_disc` counts those a flush made
stale); the instruction unit keeps one request pending while it looks up
another, signals room with `i_ready`, and delivers a cache hit in the
clock its data is valid, so hits stream at one longword per clock. A fetch
that faults marks its words: the exception is taken only when a faulted
word is needed (UM 8.1.2), so a prefetch past the end of a page into an
unmapped one is harmless.

**Decoder.** `ap020_decode.vh` decodes `dw` (stage C at dispatch, else the
latched `ir`) into the first sequencer state, operand size, ALU operation,
source/destination kinds (register, immediate, EA, quick) and whether the
second word belongs to the operation (`dc_needs_ext`). At an instruction
boundary the dispatcher pops one or two words, latches the decoded controls
into `g_*` registers and jumps to the immediate, EA or execute state.
Simple register instructions dispatch out of `S_GEN_EXEC`, overlapping the
previous instruction's last clock. The register operands of the instruction
being dispatched are read through two dedicated register-file ports
(`rf_d`, `rf_e`) so that the decoder sits in no other path; the states that
follow use the latched `g_*` fields, and the EA engine takes its fields
from `ir`. The ALU's barrel shifter works from registered copies of its
operands (it is the deepest logic of the ALU), which costs shift and rotate
instructions one clock; CAS/CAS2 register their compare flags before
deciding on them for the same reason.

**Sequencer.** A state machine (`S_*` in `ap020_states.vh`) with one data
access at a time: `dreq` posts a request to the data port and parks the
sequencer in `S_DWAIT` with a destination (`dw_dst`) and a return state
(`dw_ret`). The EA engine (`S_EA*`) handles every 68020 addressing mode
including memory indirect with base and outer displacements.

**Undefined flags** follow the 68020/030 behaviour observed on silicon
(the WinUAE 68020 model): BCD N from the result and V from the correction,
DIVx overflow leaves V=1 N=1 Z=0 C=0, CHK sets Z from the operand, MULx.L
with equal registers keeps the high half, MOVEM -(An) stores the initial
An minus the size, MOVE An,-(An) stores the decremented value.

## Exceptions (ap020_exec_b.vh, ap020_frame.vh, ap020_tasks.vh)

Frames $0, $1 (throwaway, S set, on the interrupt stack when M is set),
$2, $9, $A and $B are pushed with the layout of UM 8.4. The SSW carries
FC/FB/RC/RB/DF/RM/RW/SIZE/FC as in Figure 8-9. The internal words of the
$A/$B frames hold this core's resume state:

| words | content                                                             |
|-------|---------------------------------------------------------------------|
| 4     | resume kind (boundary, stream, read, write, RMW) and state          |
| 6-7   | stage C and B images                                                |
| 10-11 | `ea`, 14-17 `src`/`dst`, 20-21 `imm`, 24-25 `tmp`, 28-29 `tmp2`     |
| 22-23 | data input buffer (software completion)                             |
| 26-27 | `ir`, version 0 with `dw_dst`/`dw_ret`                              |
| 32-36 | loop counters, MOVEM mask, EA/immediate return states               |
| 37-38 | the bytes already read of a misaligned operand (UM 8.2.1)           |
| 39-44 | extension word, trace and coprocessor dialogue state                |

The values are captured when the fault is recognised (not while the frame
is being pushed, which reuses the counters). RTE reloads them and, with
DF set, reruns the faulted cycle from the SSW, fault address and DOB; a
cleared DF delivers the DIB (reads) or drops the cycle (writes); an RMW
fault reruns the whole instruction with DF set and counts as emulated
with DF clear (UM 8.2.2). A version mismatch in word 27 is a format error
(UM 8.1.8). Misaligned operands whose later portion faults keep the
portions already transferred in words 37-38 and merge them on the rerun;
for writes the validated first portion is still written, as the real
part's bus would have done.

Interrupts: the IPL lines are synchronised, level 7 is edge sensitive
(a transition to 7, or the mask dropping below 7 with the request held),
IPEND reflects a pending interrupt, STOP wakes on a request above the
mask. Trace T1/T0 follow UM 8.1.7: T1 survives the instruction traps
(DIVZ, CHK, TRAPcc, TRAP), T0 traces changes of flow.

Posted writes that fail on the bus are reported at the next instruction
boundary with a format $A frame (UM 8.1.2); a bus error while stacking a
fault frame halts the processor (UM 7.5.4).

## Memory subsystem (ap020_memsys.v)

There is no MMU: addresses go to the bus as the program forms them, and no
access faults before the bus does. Writes update a data cache line they hit
(write-through, never allocating) and enter a one-entry
write buffer that completes on the bus while the sequencer continues; a
write whose buffer slot and bus are free goes to the bus controller in the
clock it is posted, and the next one may post in the clock the previous
completes. Read-modify-write and CPU-space writes are not posted so that their
bus errors are seen by the instruction. A data cache hit is acknowledged
in the clock its data is valid (two-clock read, UM 11.2). Operands crossing a longword, cache
line or page are split as UM 7.2.2 describes, and the first portion of a
line-crossing read is not burst.

**Native port** (`FAST_PORT`): an integration decodes `fast_addr` and
`fast_fc` and asserts `fast_match` for internal RAM; instruction fetches and
ordinary data then use a request/response port with line bursts instead of
the pin bus. Locked (RMC) transfers, interrupt acknowledges and anything
that can fault stay on the pins.

**System options** (inputs of `ap020_top`, tied to 0 for a plain MC68020):
`snoop_we`/`snoop_addr` invalidate the data cache entry for an address
another bus master has written, for systems whose DMA writes native-port
RAM. `nmi_vec_nocache` makes the level 7 autovector fetch
bypass the data cache, so an external overlay of that vector (a freezer
cartridge) is always seen. The Minimig integration uses both.

**Caches** (`ap020_cache.v`): the instruction cache is 256 bytes, direct
mapped, 16 lines of four longword entries with individual valid bits,
tagged by the address and FC2. Bursts fill the missing entries of a line;
on a narrow port the entry is completed from the extra cycles (UM
6.1.3.1). CIIN inhibits fills and is ignored on writes.
CACR is the MC68020's (MC68020 UM 7.3): E enables, F freezes, C clears all
entries, CE clears the entry CAAR selects; nothing else is stored. CDIS
disables the caches. The organisation differs from the MC68020's 64 single
longword entries only in which stale entries survive when code is changed
without a cache clear.

The data cache is not part of the MC68020. With `DATA_CACHE` (default 1) the
MC68030's 256-byte data cache (tagged by FC2-0) caches as it does there --
pin-bus reads unless CIIN is asserted, with bursts, and native-port reads
-- and is invisible to software: CACR's E enables it with the instruction
cache, C clears it, and nothing reads it back. Writes update a line they
hit and never allocate (there is no WA). Software that changes cached
memory behind the processor (a DMA master, or the same RAM reachable at
another address) must clear the caches with C or report the writes
through the snoop inputs; an MC68020 program that does not expect a data
cache will otherwise see stale data. `DATA_CACHE = 0` builds without it.

## Bus controller (ap020_bus.v, UM 7)

The controller implements the MC68030 protocol, a superset of the
MC68020's. Requests carry an address, byte count, total operand size (for
SIZ), direction, function code and the RMC, CIOUT, CBREQ and OCS
attributes. The controller runs S0-S5 with the timing of UM Figures 7-7 to
7-61:

- asynchronous cycles terminate on DSACKx (three clocks plus wait states),
  with the port size read from DSACK1/0 and the operand assembled or the
  write lanes driven per Tables 7-4 and 7-5;
- synchronous cycles terminate on STERM (two clocks), bursts of four
  longwords with modulo-4 address wrap continue while CBACK is asserted;
- ECS and OCS pulse for the first half clock, DBEN follows UM 7.3;
- BERR, BERR with HALT (retry), HALT (single cycle) and late BERR after
  DSACK are handled as UM 7.5; retry restarts the cycle from S0 after both
  negate;
- BR/BG/BGACK arbitration follows the state machine of Figure 7-61: the
  bus is granted between cycles (never inside an RMC sequence) and the
  outputs are released;
- CPU space cycles (FC=7) serve the interrupt acknowledge (vector on the
  low byte, AVEC, spurious on BERR), breakpoint acknowledge (BERR: illegal
  instruction; DSACK: the opcode replaces the BKPT) and coprocessor CIR
  accesses (type 2, CpID on A15-A13).

## Coprocessor interface (ap020_exec_c.vh, UM 10)

cpGEN, cpBcc, cpDBcc, cpScc, cpTRAPcc, cpSAVE and cpRESTORE talk to CpID
0-7 through the CIRs. CpID 0 is an ordinary coprocessor (an MC68851 on a
real MC68020 system): PMOVE, PTEST, PLOAD and PFLUSH take the coprocessor
protocol and, with no coprocessor answering, end in Line F. Every response primitive of Table 10-2
is served: busy, null (with CA, IA, PF, TF), supervisor check, transfer
operation word, transfer from instruction stream, evaluate and transfer
effective address, evaluate effective address and transfer data (every EA
category check of Table 10-4), write to previously evaluated EA, take
address and transfer data, transfer to/from top of stack, transfer single
and multiple main processor registers, transfer main processor control
register, transfer multiple coprocessor registers, transfer status register
and scanPC, and the three take-exception primitives. Protocol violations,
F-line aborts (the control CIR written with $0001), format errors and the
absence of a coprocessor (BERR on the first CIR access) raise the
exceptions of UM 10.5.

## Verification

`tb/tb_ap020_bus.sv` drives the bus controller alone against slave models
of every termination (asynchronous 8/16/32-bit ports, synchronous with and
without bursts, CIIN, BERR, late BERR, retry, HALT, CBACK negated early)
and checks the data, the fills and the cycle lengths in half clocks.

`tb/tb_ap020_program.sv` wraps the whole processor with 1 MB of RAM
reachable through different ports (synchronous burst, 16-bit, 8-bit,
32-bit with CIIN) and optionally the native port, a bus error region, an
interrupt
controller, the breakpoint and coprocessor acknowledge cycles and a
scripted coprocessor; the self-test programs in `tb/asm` run on it.
`+waits=n` adds wait states to every port, which reorders the interaction
between the write buffer and the prefetcher and is run for
every program.
