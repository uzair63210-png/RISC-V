# RISC-V
try to built the 5 stage pipeline processor and improve it as I gain knowledge

# version 1 uploaded on 21/8/2026 
<br> simple form of cpu
<br> instruction set is 
00 register addressing
01 immediate
10 load and store with offset
11 branch instruction 
<br> 15 alu operations. 32 16-bit registers and Harvard architecture 

# version 2 uploaded on 7/9/2026 
<br> add forwarding unit for EX state

# version 2.1 uploaded on 6/10/2026 
add forwarding unit for mm state

# RISC-V 5-Stage Pipelined CPU

A 16-bit datapath, 5-stage pipeline processor (IF → ID → EX → MEM → WB)
written in Verilog. Custom ISA: RISC-V-style encoding family, but with a
flag register, an accumulator register (`r0`), and a register-indirect
branch target (MAR).

## File Overview

| File | Contents |
|---|---|
| `cpu.v` | Top level: stage interconnect, hazard/forwarding wiring |
| `IF.v`, `IF_stage.v` | Fetch: PC, instruction memory, IF/ID buffer |
| `ID.v` | Decode, register file (32 × 16-bit), SP, ID/EX buffer |
| `ex_state.v`, `ALU.v`, `adder_16bit.v` | Execute: ALU + flags, EX/MEM buffer |
| `forwarding_unit.v` | Operand forwarding, load-use stall, store-data fwd |
| `MEM_state.v` | Data memory, stack push/pop, MEM/WB buffer |
| `WB_state.v` | Write-back buffer |
| `tb_cpu.v` | Self-checking testbench (11 directed tests, 55 checks) |

---

## Register File

32 × 16-bit registers. Special roles:

| Reg | Role | Notes |
|---|---|---|
| `r0` | **Accumulator (acc)** | Updated **every cycle** with the EX/MEM ALU output. Reading `r0` as a source operand returns the *live* accumulator via forwarding. Write-back **never** writes `r0` — a `mov r0, …` is dropped. |
| `r1` | Multiply high half | After `mul`, the high 16 bits land here (the low half goes to `rd`). **No forwarding path** for it — wait ~3 instructions before reading `r1`. |
| `r30`/`r31` | **MAR** (jump target) | Every branch target is `{r31, r30}`. Raw reads, **no bypass**: a jump must be ≥ 5 instructions after the last `mov` into r30/r31 (WB is two pipeline registers deep). |
| `sp` | Stack pointer | Separate 16-bit register, resets to `0x001A`. Grows **down**. |

### Loading a constant

`r0` is the accumulator, so `add rd, r0, #imm` adds to the *live* acc —
never use it for constants. The idiom is:

```asm
xor  r1, r1        # r1 = 0            (ZERO)
xor  rd, r1, #imm  # rd = 0 ^ imm = imm (LDI)
```

---

## Flag Register

6 flags, updated by the ALU (`flags[5:0]`):

| Bit | Name | Set by |
|---|---|---|
| 5 | OV | add/sub carry-out (sub also copies to sign — see errata) |
| 4 | S  | sign |
| 3 | Z  | result == 0 |
| 2 | AC | half-carry `A[7] & B[7]` |
| 1 | C  | carry / not-borrow |
| 0 | P  | even parity of result |

`con = 0xF` (flag op) with `sel = instruction[10:9]`:
`01` = set carry, `10` = toggle carry, else hold.

> **Flag latency:** a branch in ID sees the flags of the instruction
> **2 before it** (`flags` come from the EX/MEM register). Keep exactly
> **one gap instruction** between a flag-producing op and the branch that
> tests it. A `NOP` (`0x3C000000`) holds flags unchanged.

---

## Instruction Formats

### R-type — ALU register ops
```
[31:30]=00  con[29:26]  rd[25:21]  rs1[20:16]  rs2[15:11]  000
```

### I-type — ALU immediate ops
```
[31:30]=01  con[29:26]  rd[25:21]  rs1[20:16]  imm[15:0]
```
`rd = rs1 OP imm` (imm is zero-extended). **If `rs1 = r0`, the live
accumulator is used as the operand.**

### Load / Store
```
[31:30]=10  00  lsu[27:26]  rd[25:21]  base[20:16]  off[15:0]
```
| lsu | Operation |
|---|---|
| 00 | `rd = mem[base + off]` |
| 01 | `rd = mem[base - off]` |
| 10 | `mem[base + off] = rd` (rd = **data** register) |
| 11 | `mem[base - off] = rd` |

Loads write `rd` in WB; the **acc gets the address** (acc rule).
Store data is read at MEM with store-data forwarding (no stall needed).

### Branch / Call
```
[31:30]=11  cond[29:26]  rA[25:21]  rB[20:16]  imm[18:3]  low[2:0]
```
- Target is **always `{r31, r30}` (MAR)** — there are no PC-relative branches.
- `low[2:0] = 101` → **CALL**: pushes frame, jumps to MAR.
- Immediate compares use `instruction[18:3]` (16 bits) — **not** `[15:0]`,
  because `[2:0]` is reserved for the call signature.

### Return
```
[31:26]=000100  …  [1:0]=11        → 0x10000003
```
Pops the return address and flags, `sp += 3`.

---

## ALU Operation Table (`con`)

| con | Name | Result | Notes |
|---|---|---|---|
| 0x0 | mov | `rd = rs1` | Z, P |
| 0x1 | xor | `rd = rs1 ^ rs2` | Z, P |
| 0x2 | sub | `rd = rs1 - rs2` | full flags |
| 0x3 | sbb | `rd = rs1 - rs2 - !C` | carry-in = C flag |
| 0x4 | add | `rd = rs1 + rs2` | full flags |
| 0x5 | adc | `rd = rs1 + rs2 + C` | carry-in = C flag |
| 0x6 | shl | `rd = rs1 << 1` | Z, P |
| 0x7 | shr | `rd = rs1 >> 1` | Z, P |
| 0x8 | rl | rotate left through C | C = bit shifted out |
| 0x9 | rr | rotate right through C | C = bit shifted out |
| 0xA | cmp | `rd = rs1` | Z if eq, C if rs1>rs2, borrow if rs1<rs2 |
| 0xB | or | `rd = rs1 \| rs2` | Z, P |
| 0xC | not | `rd = ~rs1` | Z, P |
| 0xD | and | `rd = rs1 & rs2` | Z, P |
| 0xE | mul | `rd = low(rs1×rs2)`, `r1 = high` | 32-bit product |
| 0xF | flagop | `rd = rs1` | sel[10:9]: 01=set C, 10=toggle C, else hold |

## Branch Condition Table (`cond`)

| cond | Mnemonic | Taken when |
|---|---|---|
| 0 | JMP | always (also CALL when `low=101`) |
| 1 | JC | C = 1 |
| 2 | JN | S = 1 |
| 3 | JP | S = 0 |
| 4 | JEVEN | P = 0 |
| 5 | JODD | P = 1 |
| 6 | JGE | `rA >= rB` *(comment says `>`; hardware includes equality — see errata)* |
| 7 | JEQ | `rA == rB` |
| 8 | JLE | `rA <= rB` *(comment says `<`; hardware includes equality — see errata)* |
| 9 | JGTI | `rA > imm` |
| 10 | JLTI | `rA < imm` |
| 11 | JEQI | `rA == imm` |
| 12 | JLTIA | `acc < imm` |
| 13 | JGTIA | `acc > imm` |
| 14 | JEQIA | `acc == imm` |
| 15 | JACC | `acc > imm` and `acc > 0` *(see errata)* |

---

## Call / Return & Stack Frame

`sp` resets to `0x001A`. On **CALL** (with old `sp = S`, new `sp = S-3`):

| Slot | Content |
|---|---|
| `mem[S-3]` | caller's flags |
| `mem[S-2]` | return address, high half |
| `mem[S-1]` | return address, low half |

The frame is **contiguous from the new sp**. On **RETURN**: `sp += 3`,
PC ← `{mem[sp+1], mem[sp+2]}`, flags restored from `mem[sp]` — all three
reads use the pipelined `sp` exactly as it arrives at the MEM stage.

**Note:** a call/return pair costs pipeline flushes; the instruction after
CALL/RET (the delay slot, below) still executes.

---

## Pipeline Rules (read before writing assembly)

1. **acc (r0) updates every cycle** with the ALU output of the instruction
   currently in MEM. Treat `r0` reads as "result of the previous
   instruction". `r0` can never be written by WB.
2. **Delay slot:** the instruction at `branch+1` **always executes**,
   taken or not (`ID_Buffer` has no flush). Put a NOP there, or use it.
   *(A deliberate MIPS-style slot; removing it needs a flush input on
   `ID_Buffer`.)*
4. **Flag latency:** a branch tests the flags of the instruction 2 before
   it. One NOP gap between flag-producer and branch.
5. **MAR retire:** ≥ 5 instructions between `mov r30/r31` and the
   jump/call that reads them (no bypass; WB is two stages deep).
6. **Branch imm field is `[18:3]`**, not `[15:0]` (low 3 bits = call sig).
7. **Data memory is cleared by reset.** Initialize data after reset.
8. **Multiply:** high half → `r1` with no forwarding; don't read `r1` for
   ~3 instructions after `mul`.
9. **Instruction memory is 2M × 32** but only the low addresses matter in
   simulation; fill unused space with `NOP (0x3C000000)`.

---

## Errata / Known Issues

| # | Issue | Status |
|---|---|---|
| 1 | Return restored flags from `mem[sp]`; call wrote them at old-sp `mem[S]` | **FIXED** — push now writes flags at `mem[sp-3]`, making the frame contiguous from the new sp; read paths unchanged |
| 2 | Taken branch leaked `branch+3` (fetch register not killed) | **FIXED** — `IF.v`: `if (brch) instruction <= NOP;` (a true NOP, so flags are held) |
| 3 | `cond 6/8` (JGE/JLE) included equality; comments said strict `>`/`<` | **FIXED** — cancel conditions now `<=` / `>=` (strict). `cond 9/10/12/13` made strict too; their comments were also swapped |
| 4 | `cond 15` cancel was `(!(acc>imm) && S)` — wrong boolean structure | **FIXED** — taken = `(acc > imm) && !acc[15]` |
| 5 | sub sets S = carry-out (not result sign) | flag design kept by author |
| 6 | Call saved the **call's own** flags (sp−3 result), not the caller's | **FIXED** — `MEM_state.v` delays `flags` one cycle (`flags_q`) so the push captures the caller's flag state |

---

## Testbench

`tb_cpu.v`: 11 directed tests, 55 checks, self-checking, per-test verdicts
and a per-cycle trace (`+NO_MONITOR=1` to silence).

```bash
# Icarus Verilog
iverilog -g2012 -o tb tb_cpu.v cpu.v IF.v IF_stage.v ID.v ex_state.v \
         ALU.v adder_16bit.v forwarding_unit.v MEM_state.v WB_state.v
vvp tb

# Vivado: launch_simulation, then "run 10 us" in the Tcl console
```

Covered: all 16 ALU ops (reg + immediate), multiply high/low, acc
semantics, forwarding at all 3 distances, load-use stall (exactly 1
cycle), store-data forwarding, sub-offset load, carry/parity/reg/acc
branches, full call/return with stack-frame inspection.

Expected final line: `>>> ALL TESTS PASSED <<<` (`TOTAL: 55 checks, 0 errors`).

# The block Diagram
<img width="1942" height="809" alt="cpu_block_diagram" src="https://github.com/user-attachments/assets/89695af8-ebc0-4a40-9538-300e77847010" />

