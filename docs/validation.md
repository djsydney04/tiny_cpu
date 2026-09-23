# Validation record

Local verification on 2026-09-23 used Icarus Verilog 13.0, Apple Clang 16.0 with LLVM's ARM target, LLVM LLD from the installed Rust toolchain, and Yosys 0.69 through YoWASP.

| Check | Result |
| --- | --- |
| `make lint` | Core elaborates with `-Wall`, without warnings |
| `make test` | All 15 test groups pass |
| Datapath vectors | 16,368 ALU, 9,984 shifter, 256 condition/flag cases pass |
| Instruction stream | 1,500 generated instructions compared after every retirement, with zero and three memory wait cycles |
| Assembly programs | Sum, Fibonacci, and GCD produce expected results with zero, one, and seven memory wait cycles |
| `make check-asm` | All three committed machine-code images match freshly assembled and linked source |
| Reset | Cancels an unaccepted store and restarts both a running and halted core |
| Faults | Decode, alignment, Thumb request, and bus errors checked; no destination/base updates on failed transfers |
| `make wave SIM_ARGS='+wait=2 +dump_words=1'` | VCD generated; sum remains 55 at address `0x100` |
| Yosys synthesis | Generic gate netlist emitted at `build/tiny_arm.json` after `check -assert` |
| Netlist reload | Generated JSON reloaded into Yosys; hierarchy validation and `check -assert` report zero problems |

The simulation memory model asserts request stability across stalls, bus address alignment, and stable halt behavior. Runaway programs produce an error after a configurable cycle limit. The arithmetic reference computes signed overflow and unsigned carry with Python integers independently of the RTL's adder implementation.

Synthesis used the checked-in `tools/synth.ys`; YoWASP's compiled-runtime disk cache was disabled locally because free disk space was limited. That local tool-runtime setting does not change the synthesized design. The standard `make synth` target uses native `yosys` by default and can be overridden with `YOSYS=path/to/yosys`.

No FPGA place-and-route, board testing, timing closure, silicon verification, full ARM compliance suite, or formal equivalence proof has been performed. The added GitHub Actions workflow has not been run remotely during this task.
