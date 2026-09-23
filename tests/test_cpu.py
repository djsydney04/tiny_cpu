import os
from pathlib import Path
import random
import re
import subprocess
import unittest

from reference import MASK, alu, condition, shift

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build/tests"
IVERILOG = os.environ.get("IVERILOG", "iverilog")
VVP = os.environ.get("VVP", "vvp")
HALT = 0xEF000000


def dp(op, rd=0, rn=0, operand=0, immediate=True, s=False, cond=14):
    return (cond << 28) | (int(immediate) << 25) | (op << 21) | (int(s) << 20) | (rn << 16) | (rd << 12) | operand


def mov(rd, value):
    for rotate in range(16):
        for byte in range(256):
            result, _ = shift(True, rotate * 256 + byte, 0, 0)
            if result == value:
                return dp(13, rd, operand=rotate * 256 + byte)
    raise ValueError(f"{value:#x} is not an ARM immediate")


def transfer(load, rd, rn, offset=0, byte=False, pre=True, wb=False, cond=14):
    return ((cond << 28) | 0x04000000 | (int(pre) << 24) | (int(offset >= 0) << 23)
            | (int(byte) << 22) | (int(wb) << 21) | (int(load) << 20)
            | (rn << 16) | (rd << 12) | abs(offset))


def compile_tb(name, bench):
    BUILD.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([IVERILOG, "-g2012", "-Wall", "-s", name, "-o", str(BUILD / (name + ".vvp")),
                             *map(str, sorted((ROOT / "rtl").glob("*.v"))), str(ROOT / bench)],
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)


class DatapathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compile_tb("tb_datapath", "tests/tb_datapath.v")

    def vectors(self, kind, values):
        path = BUILD / f"{kind}.txt"
        path.write_text("".join(" ".join(f"{x:08x}" for x in value) + "\n" for value in values))
        run = subprocess.run([VVP, str(BUILD / "tb_datapath.vvp"), f"+kind={kind}", f"+vectors={path}"],
                             capture_output=True, text=True, timeout=30)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        print(" ", run.stdout.splitlines()[0])

    def test_all_conditions_and_flags(self):
        self.vectors("cond", [(0, 0, code, flags, int(condition(code, flags)), 0)
                              for code in range(16) for flags in range(16)])

    def test_alu_edges_and_random(self):
        rng = random.Random(4100)
        edges = [0, 1, 2, 0x7FFFFFFE, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFE, MASK]
        inputs = [(op, a, b, old, carry) for op in range(16) for a in edges for b in edges
                  for old in (0, 1, 2, 3) for carry in (0, 1)]
        inputs += [(rng.randrange(16), rng.getrandbits(32), rng.getrandbits(32), rng.randrange(16), rng.randrange(2))
                   for _ in range(6000)]
        self.vectors("alu", [(a, b, op | (carry << 4), old, *alu(op, a, b, old, carry))
                             for op, a, b, old, carry in inputs])

    def test_shifter_all_immediates_and_shift_amounts(self):
        values = [0, 1, 2, 0x80000000, 0xFFFFFFFF, 0x12345678, 0x87654321]
        inputs = [(True, operand, 0, carry) for operand in range(4096) for carry in (0, 1)]
        inputs += [(False, amount << 7 | kind << 5, value, carry)
                   for kind in range(4) for amount in range(32) for value in values for carry in (0, 1)]
        self.vectors("shift", [(value, 0, int(imm) << 12 | operand, carry << 1,
                               *shift(imm, operand, value, carry)) for imm, operand, value, carry in inputs])


class CoreTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compile_tb("tb_cpu", "sim/tb_cpu.v")

    def run_cpu(self, words=None, *, image=None, wait=0, fault=0, extra=(), trace=False):
        if image is None:
            image = BUILD / "program.hex"
            image.write_text("".join(f"{word:08x}\n" for word in words))
        args = [VVP, str(BUILD / "tb_cpu.vvp"), f"+image={image}", f"+wait={wait}", *extra]
        if trace:
            args.append("+trace")
        run = subprocess.run(args, capture_output=True, text=True, timeout=30)
        self.assertEqual(run.returncode, int(fault != 0), (run.stdout + run.stderr)[-4000:])
        match = re.search(r"RESULT fault=(\d+) pc=([0-9a-f]+) cycles=(\d+) retired=(\d+)", run.stdout)
        self.assertIsNotNone(match, run.stdout[-4000:])
        self.assertEqual(int(match[1]), fault, run.stdout[-4000:])
        state = next(line for line in run.stdout.splitlines() if line.startswith("STATE "))
        pc, flags, *regs = [int(x, 16) for x in state.split()[1:]]
        memory = {int(a, 16): int(b, 16) for a, b in re.findall(r"MEM ([0-9a-f]+) ([0-9a-f]+)", run.stdout)}
        traces = [[int(x, 16) for x in line.split()[1:]] for line in run.stdout.splitlines() if line.startswith("TRACE ")]
        return dict(pc=pc, flags=flags, regs=regs, memory=memory, trace=traces,
                    cycles=int(match[3]), retired=int(match[4]))

    def test_real_assembly_examples_with_wait_states(self):
        expected = {"sum": [55], "gcd": [6], "fibonacci": [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89]}
        for name, numbers in expected.items():
            previous = None
            for wait in (0, 1, 7):
                with self.subTest(program=name, wait=wait):
                    state = self.run_cpu(image=ROOT / f"examples/{name}.hex", wait=wait, trace=True)
                    self.assertEqual([state["memory"][256 + 4*i] for i in range(len(numbers))], numbers)
                    if previous:
                        self.assertEqual(state["trace"], previous["trace"])
                        self.assertGreater(state["cycles"], previous["cycles"])
                    previous = state

    def test_reset_during_pending_store_and_after_halt(self):
        compile_tb("tb_reset", "tests/tb_reset.v")
        run = subprocess.run([VVP, str(BUILD / "tb_reset.vvp")], capture_output=True, text=True, timeout=10)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_runaway_program_times_out(self):
        path = BUILD / "forever.hex"
        path.write_text("eafffffe\n")
        run = subprocess.run([VVP, str(BUILD / "tb_cpu.vvp"), f"+image={path}", "+max_cycles=25"],
                             capture_output=True, text=True, timeout=10)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("execution timeout", run.stdout)

    def test_byte_lanes_and_zero_extension(self):
        program = [mov(0, 0x100), dp(15, 1, operand=0), transfer(False, 1, 0)]
        for lane, value in enumerate((0xAA, 0xBB, 0xCC, 0xDD)):
            program += [mov(1, value), transfer(False, 1, 0, lane, byte=True),
                        transfer(True, 4 + lane, 0), transfer(True, 8 + lane, 0, lane, byte=True)]
        state = self.run_cpu(program + [HALT], wait=3)
        self.assertEqual(state["regs"][4:8], [0xFFFFFFAA, 0xFFFFBBAA, 0xFFCCBBAA, 0xDDCCBBAA])
        self.assertEqual(state["regs"][8:12], [0xAA, 0xBB, 0xCC, 0xDD])

    def test_pre_post_and_negative_offsets(self):
        state = self.run_cpu([mov(0, 0x100), mov(1, 42), transfer(False, 1, 0, 4, wb=True),
                              transfer(True, 2, 0, -4, pre=False), transfer(True, 3, 0, 4),
                              transfer(False, 1, 0, 4, pre=False),
                              transfer(True, 4, 0, -4, wb=True), HALT], wait=4)
        self.assertEqual(state["regs"][:5], [0x100, 42, 42, 42, 42])
        self.assertEqual(state["memory"][0x100], 42)
        self.assertEqual(state["memory"][0x104], 42)

    def test_pc_reads_literal_load_and_alu_branch(self):
        words = [dp(13, 0, operand=15, immediate=False), transfer(True, 1, 15, 12),
                 mov(2, 20), dp(13, 15, operand=2, immediate=False), mov(0, 99), HALT, 0x12345678]
        state = self.run_cpu(words)
        self.assertEqual(state["regs"][:3], [8, 0x12345678, 20])
        self.assertEqual(state["pc"], 20)

    def test_load_pc_and_base_writeback(self):
        state = self.run_cpu([mov(0, 0x100), mov(1, 20), transfer(False, 1, 0),
                              transfer(True, 15, 0, 4, pre=False), mov(1, 99), HALT])
        self.assertEqual(state["regs"][:2], [0x104, 20])

    def test_failed_conditions_have_no_side_effects(self):
        state = self.run_cpu([0x00000090, transfer(False, 1, 0, 1, cond=0),
                              0x0F000001, dp(13, 1, operand=42, cond=0), HALT])
        self.assertEqual(state["regs"], [0] * 15)
        self.assertEqual(state["retired"], 5)

    def test_unsupported_encodings_fault(self):
        for word in (0xE0000090, 0xE8BD8000, 0xE10F0000, 0xE1A00211, 0xFA000000,
                     0xEF000001, 0xE1B0F000, 0xE5C0F000, 0xE580F000, 0xE4900004,
                     0xE4B01004, 0xE7901002, 0xE3A10000, 0xE3511000):
            with self.subTest(word=f"{word:08x}"):
                state = self.run_cpu([word, HALT], fault=1)
                self.assertEqual(state["pc"], 0)
                self.assertEqual(state["retired"], 0)

    def test_alignment_faults_are_precise(self):
        for word in (transfer(False, 1, 0, 1, wb=True), transfer(True, 1, 0, 1, wb=True)):
            state = self.run_cpu([mov(0, 0x100), mov(1, 7), word, HALT], fault=2)
            self.assertEqual(state["regs"][:2], [0x100, 7])
            self.assertEqual(state["pc"], 8)
            self.assertEqual(state["memory"][0x100], 0)
        for target, instruction, fault in ((2, 0xE12FFF10, 2), (1, 0xE12FFF10, 4), (2, 0xE1A0F000, 2)):
            self.run_cpu([mov(0, target), instruction, HALT], fault=fault)
        state = self.run_cpu([mov(0, 0x100), mov(1, 2), transfer(False, 1, 0),
                              transfer(True, 15, 0, 4, pre=False), HALT], fault=2)
        self.assertEqual(state["regs"][0], 0x100)

    def test_bus_errors_do_not_commit_load_or_writeback(self):
        for load in (False, True):
            state = self.run_cpu([mov(0, 0x100), mov(1, 7), transfer(load, 1, 0, 4, wb=True), HALT],
                                 fault=3, wait=5, extra=("+error_addr=00000104",))
            self.assertEqual(state["regs"][:2], [0x100, 7])
            self.assertEqual(state["memory"][0x104], 0)
            self.assertEqual(state["pc"], 8)
        state = self.run_cpu([mov(0, 7), HALT], fault=3, extra=("+error_addr=00000004",))
        self.assertEqual(state["regs"][0], 7)
        self.assertEqual(state["pc"], 4)
        self.run_cpu([mov(0, 0x10000), transfer(True, 1, 0), HALT], fault=3)

    def test_seeded_instruction_stream_against_math_reference(self):
        rng = random.Random(0xA32)
        regs, flags, words, expected = [0] * 15, 0, [], []
        for index in range(1500):
            op, immediate, s, cond = rng.randrange(16), bool(rng.randrange(2)), bool(rng.randrange(2)), rng.randrange(15)
            rn, rd, rm = rng.randrange(16), rng.randrange(13), rng.randrange(16)
            if op in (8, 9, 10, 11):
                s, rd = True, 0
            if op in (13, 15):
                rn = 0
            operand = rng.randrange(4096) if immediate else rng.randrange(32) << 7 | rng.randrange(4) << 5 | rm
            word = dp(op, rd, rn, operand, immediate, s, cond)
            words.append(word)
            pc = index * 4
            if condition(cond, flags):
                a = pc + 8 if rn == 15 else regs[rn]
                value = pc + 8 if rm == 15 else regs[rm]
                b, carry = shift(immediate, operand, value, (flags >> 1) & 1)
                result, new_flags = alu(op, a, b, flags, carry)
                if op not in (8, 9, 10, 11):
                    regs[rd] = result
                if s:
                    flags = new_flags
            expected.append([pc, word, flags, *regs])
        words.append(HALT)
        expected.append([6000, HALT, flags, *regs])
        for wait in (0, 3):
            state = self.run_cpu(words, wait=wait, trace=True, extra=("+dump_words=0",))
            self.assertEqual(len(state["trace"]), len(expected))
            for index, (got, want) in enumerate(zip(state["trace"], expected)):
                self.assertEqual(got, want, f"instruction {index}, wait {wait}")


if __name__ == "__main__":
    unittest.main()
