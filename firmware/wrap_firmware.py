#!/usr/bin/env python3
"""
wrap_firmware.py  –  Strips an ELF to raw binary and prepends a 4-byte
                     little-endian size header for the SD bootloader.

Usage:  python3 wrap_firmware.py firmware.elf firmware.bin

Output format written to SD card at sector 2048 (1 MB):
  Bytes [0..3]   : firmware size in bytes (uint32_t, little-endian)
  Bytes [4..]    : raw firmware binary (text + rodata + data)

The bootloader reads byte [0..3] first to know how many bytes to load,
then copies the rest into App BRAM starting at 0x0001_0000.
"""
import sys
import struct
import subprocess
import os
import tempfile

def wrap(elf_path, out_path):
    # Use objcopy to extract raw binary from ELF
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".raw")
    tmp.close()
    try:
        subprocess.run(
            ["riscv32-unknown-elf-objcopy", "-O", "binary", elf_path, tmp.name],
            check=True
        )
    except FileNotFoundError:
        # Try generic name
        subprocess.run(
            ["riscv64-unknown-elf-objcopy", "-O", "binary", elf_path, tmp.name],
            check=True
        )

    with open(tmp.name, "rb") as f:
        fw_data = f.read()
    os.unlink(tmp.name)

    fw_size = len(fw_data)
    print(f"  Firmware binary: {fw_size} bytes (0x{fw_size:X})")

    if fw_size > 63 * 1024:
        print(f"WARNING: firmware ({fw_size} B) exceeds 63 KB App BRAM budget!", file=sys.stderr)

    # Pad to 4-byte boundary
    while len(fw_data) % 4:
        fw_data += b'\x00'

    header = struct.pack("<I", fw_size)   # 4-byte LE size

    with open(out_path, "wb") as f:
        f.write(header)
        f.write(fw_data)

    total = 4 + len(fw_data)
    sectors = (total + 511) // 512
    print(f"  Output: {out_path}  ({total} bytes, {sectors} sectors)")
    print(f"  Write:  dd if={out_path} of=/dev/sdX bs=512 seek=2048 conv=notrunc")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.elf> <output.bin>", file=sys.stderr)
        sys.exit(1)
    wrap(sys.argv[1], sys.argv[2])
