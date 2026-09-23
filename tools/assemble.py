#!/usr/bin/env python3
"""Assemble real A32 source with LLVM and emit a little-endian RAM image."""
import argparse
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RAM_BYTES = 65536


def linker():
    if os.environ.get("LLD"):
        return [os.environ["LLD"]]
    if path := shutil.which("ld.lld"):
        return [path]
    # Rust ships the same LLVM linker; this makes stock macOS Rust installs useful.
    if shutil.which("rustc"):
        sysroot = subprocess.check_output(["rustc", "--print", "sysroot"], text=True).strip()
        candidates = sorted(Path(sysroot).glob("lib/rustlib/*/bin/rust-lld"))
        if candidates:
            return [str(candidates[0]), "-flavor", "gnu"]
    raise ValueError("LLVM ld.lld is required. Install LLVM/lld or set LLD to its path.")


def elf_image(data):
    if data[:7] != b"\x7fELF\x01\x01\x01":
        raise ValueError("expected a little-endian ELF32 executable")
    if struct.unpack_from("<HH", data, 16) != (2, 40):
        raise ValueError("expected an ARM executable")
    if struct.unpack_from("<I", data, 24)[0] != 0:
        raise ValueError("entry point must match reset address zero")
    phoff = struct.unpack_from("<I", data, 28)[0]
    size, count = struct.unpack_from("<HH", data, 42)
    image = bytearray()
    for i in range(count):
        kind, offset, va, pa, filesz, memsz, flags, align = struct.unpack_from(
            "<8I", data, phoff + size * i
        )
        if kind != 1:
            continue
        if va != pa or filesz > memsz or pa + memsz > RAM_BYTES or offset + filesz > len(data):
            raise ValueError("ELF load segment does not fit the 64 KiB RAM contract")
        end = pa + memsz
        if end > len(image):
            image.extend(bytes(end - len(image)))
        image[pa:pa + filesz] = data[offset:offset + filesz]
    if not image:
        raise ValueError("ELF has no loadable code")
    image.extend(bytes(-len(image) % 4))
    return image


def assemble(source, output):
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    obj, elf = output.with_suffix(".o"), output.with_suffix(".elf")
    subprocess.run([
        os.environ.get("CLANG", "clang"), "--target=armv4t-none-eabi",
        "-march=armv4t", "-marm", "-c", str(source), "-o", str(obj),
    ], check=True)
    subprocess.run(linker() + ["-T", str(ROOT / "sim/link.ld"), str(obj), "-o", str(elf)], check=True)
    image = elf_image(elf.read_bytes())
    output.with_suffix(".bin").write_bytes(image)
    output.write_text("".join(f"{word[0]:08x}\n" for word in struct.iter_unpack("<I", image)))
    return len(image)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True, help="output .hex file")
    args = parser.parse_args()
    if args.output.suffix != ".hex":
        parser.error("output must end in .hex")
    try:
        size = assemble(args.source, args.output)
    except (ValueError, OSError, subprocess.CalledProcessError, struct.error) as exc:
        parser.exit(1, f"assembly failed: {exc}\n")
    print(f"{args.output}: {size} bytes of A32 code/data")


if __name__ == "__main__":
    main()
