# Follow a program through the CPU

A CPU repeatedly reads an instruction from memory, interprets its bits, changes its state, and selects the next instruction. Verilog describes the digital hardware that performs those steps. Icarus simulates that hardware advancing on clock edges.

Start with the sum program:

```asm
mov r0, #0       @ total
mov r1, #10      @ counter
loop:
add r0, r0, r1   @ total += counter
subs r1, r1, #1  @ counter -= 1; update flags
bne loop        @ repeat while counter is nonzero
mov r2, #0x100   @ output address
str r0, [r2]    @ store the answer
svc #0          @ stop this project's monitor
```

`r0`, `r1`, and `r2` are storage inside the CPU. RAM is separate storage accessed through the memory port. `str` copies a register value to RAM; ordinary arithmetic only reads and writes registers.

For `add r0, r0, r1`, the register file supplies two numbers. The shifter passes `r1` through unchanged. The ALU adds them, and the controller writes the result into `r0`. The next instruction address is four bytes later because each A32 instruction occupies four bytes.

`subs` also updates the flags. On the final iteration the counter becomes zero, so Z becomes one. `bne` means “branch if Z is zero.” Its condition fails, so execution continues to the store. The stored word is 55.

## See the actual machine code

The first line of `examples/sum.hex` is `e3a00000`, the encoded `mov r0, #0`. The file contains one 32-bit hexadecimal word per line. It is not a new instruction set or a text interpreter: the RTL decodes those instruction bits.

Run:

```sh
make run PROGRAM=examples/sum.hex SIM_ARGS='+trace +dump_words=1'
```

Each `TRACE` line shows the address and encoded instruction, followed by the flags and all fifteen general registers after that instruction. Find address `00000008`: those are the additions. The successive `r0` values are 10, 19, 27, 34, 40, 45, 49, 52, 54, and 55.

## See the clock cycles

```sh
make wave SIM_ARGS='+wait=2'
```

Open `build/cpu.vcd` in a waveform viewer and inspect `clk`, `dut.state`, `mem_valid` (or the testbench's `valid`), `mem_ready` (`ready`), `pc`, `instruction`, and `regs`.

Watch the core hold the same address while waiting for a response. During a store, register writeback waits for the memory handshake. During a branch, PC changes in EXECUTE and the next FETCH reads the target address.

## Files to read next

1. `rtl/arm_condition.v`: decide whether an instruction should execute.
2. `rtl/arm_alu.v`: arithmetic, logic, carry, and overflow.
3. `rtl/arm_shifter.v`: create the second operand and its carry bit.
4. `rtl/tiny_arm.v`: connect the components and sequence instructions.
5. `sim/tb_cpu.v`: provide clock, reset, RAM, wait states, and diagnostics.

The [Fibonacci example](../examples/fibonacci.s) demonstrates arrays and post-indexed stores. The [GCD example](../examples/gcd.s) demonstrates conditional arithmetic, BL/BX calls, and a stack using single-register loads/stores. Its subtraction algorithm assumes positive inputs.

To put the design on an FPGA, the next concrete task is choosing a board, then implementing its memory and clock/reset wrapper. The simulation testbench is not that hardware wrapper.
