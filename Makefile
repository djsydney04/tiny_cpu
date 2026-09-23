PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
export IVERILOG VVP
RTL := rtl/arm_condition.v rtl/arm_shifter.v rtl/arm_alu.v rtl/tiny_arm.v
PROGRAM ?= examples/sum.hex
SIM_ARGS ?=

.PHONY: all demo run wave test assemble check-asm lint synth
all: test

build/cpu.vvp: $(RTL) sim/tb_cpu.v
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_cpu -o $@ $(RTL) sim/tb_cpu.v

demo: build/cpu.vvp
	$(VVP) $< +image=examples/sum.hex +dump_words=1 $(SIM_ARGS)

run: build/cpu.vvp
	$(VVP) $< +image=$(PROGRAM) $(SIM_ARGS)

wave: build/cpu.vvp
	$(VVP) $< +image=$(PROGRAM) +vcd=build/cpu.vcd $(SIM_ARGS)

assemble:
	$(PYTHON) tools/assemble.py examples/sum.s -o build/sum.hex
	$(PYTHON) tools/assemble.py examples/fibonacci.s -o build/fibonacci.hex
	$(PYTHON) tools/assemble.py examples/gcd.s -o build/gcd.hex

check-asm: assemble
	cmp examples/sum.hex build/sum.hex
	cmp examples/fibonacci.hex build/fibonacci.hex
	cmp examples/gcd.hex build/gcd.hex

lint:
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tiny_arm -o build/core.vvp $(RTL)

test: build/cpu.vvp
	$(PYTHON) -m unittest discover -s tests -v

synth:
	mkdir -p build
	$(YOSYS) -l build/yosys.log -s tools/synth.ys
	test -s build/tiny_arm.json
