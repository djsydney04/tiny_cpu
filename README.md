# tiny_cpu

A small hardware CPU written in Verilog that executes a defined subset of **32-bit ARM (A32) machine code**. It has a register file, ALU, barrel shifter, condition flags, and a multi-cycle controller. Programs are assembled with LLVM's ARM assembler and execute on the RTL in Icarus Verilog.

This is an educational implementation, not a complete ARM processor. It does not execute AArch64 or Thumb, boot Linux, or run arbitrary compiler output. The exact supported forms are documented in [the architecture guide](docs/architecture.md).

## Run it

You need Icarus Verilog (`iverilog` and `vvp`), Python 3.10+, and Make. The example machine-code images are included, so trying the CPU does not require an ARM toolchain.

```sh
make demo
make test
```

`make demo` executes [sum.s](examples/sum.s), which adds 1 through 10 and stores the result at address `0x100`. Look for:

```text
RESULT fault=0 pc=0000001c cycles=71 retired=35
MEM 00000100 00000037
```

`0x37` is 55. A fault or execution timeout exits with an error.

Try the other programs, slow down memory, inspect each retired instruction, or record a waveform:

```sh
make run PROGRAM=examples/fibonacci.hex
make run PROGRAM=examples/gcd.hex SIM_ARGS='+wait=3 +trace'
make wave PROGRAM=examples/sum.hex
```

The waveform is `build/cpu.vcd`, viewable in a VCD viewer such as GTKWave. A `TRACE` line contains the instruction address, instruction word, NZCV flags after retirement, then `r0` through `r14`. `STATE` contains the current PC, flags, and those registers. `MEM` shows word addresses and values.

## What it supports

| Component | Implemented |
| --- | --- |
| Registers | 32-bit `r0`–`r14`, PC (`r15`), NZCV flags |
| Arithmetic | ADD, ADC, SUB, SBC, RSB, RSC |
| Logic and moves | AND, EOR, ORR, BIC, MOV, MVN |
| Compare and test | CMP, CMN, TST, TEQ |
| Operand shifts | Immediate LSL, LSR, ASR, ROR, RRX; rotated constants |
| Control flow | All ordinary conditions, B, BL, BX to A32, aligned ALU/LDR writes to PC |
| Memory | LDR, STR, LDRB, STRB with immediate offsets; pre/post indexing |
| Simulation stop | `svc #0` stops the core through a project-specific monitor convention |

Unsupported executed encodings stop with a diagnostic fault. There are no architectural exception handlers, privilege modes, interrupts, MMU, caches, floating point, multiply/divide, or load/store multiple. Register-controlled shifts and register-offset memory addressing are also outside this version.

## Write an assembly program

Assembly additionally needs Clang with the ARM target and LLVM `ld.lld`. On macOS, the build helper can also find the LLVM linker bundled with an active Rust toolchain. Set `CLANG` or `LLD` to override their executable paths.

```sh
python3 tools/assemble.py examples/gcd.s -o build/my-program.hex
make run PROGRAM=build/my-program.hex
make check-asm
```

Use `.syntax unified`, `.arm`, and a global `_start` at address zero, as in the examples. End with `svc #0`. Initialize `sp` before using the stack. The simulated RAM is 64 KiB, is zero-filled before loading the program, and is shared by instructions and data. The helper emits `.o`, `.elf`, `.bin`, and `.hex` artifacts under the output stem; `.bss` is zero-filled. Assembly checks syntax and encoding, but does **not** guarantee every emitted instruction is supported by this core.

`make check-asm` rebuilds all example images using the real assembler/linker and checks that they match the committed hex files. `make test` needs no assembler or third-party Python packages.

## Hardware and verification

The synthesizable core is [rtl/tiny_arm.v](rtl/tiny_arm.v). It connects to external memory through a single 32-bit valid/ready port with byte write strobes. The simulation RAM and host diagnostics live separately in `sim/`.

```sh
make lint
make synth                     # requires Yosys
```

Synthesis writes a generic netlist to `build/tiny_arm.json`. An FPGA build still needs a board wrapper, RAM implementation, clock/reset wiring, pin constraints, and place-and-route. No board or silicon has been tested, and no device frequency or area is claimed.

The tests cover 16,368 ALU vectors, 9,984 shifter vectors, all 256 condition/flag combinations, a seeded 1,500-instruction stream checked after every retirement, assembly examples with memory stalls, byte lanes, addressing modes, PC behavior, precise faults, reset cancellation, and timeouts. These checks establish behavior for the documented subset; they are not ARM architectural certification or a formal proof.

Read [the architecture guide](docs/architecture.md) for the datapath, memory protocol, instruction boundaries, and fault codes, [the walkthrough](docs/walkthrough.md) to follow a program through the CPU, and [the validation record](docs/validation.md) for the checks performed.
