#!/usr/bin/env python3
#
# makehex.py - Convert binary to Verilog $readmemh hex format

import sys
import struct

def bin_to_hex(bin_path, nwords=None):
    with open(bin_path, "rb") as f:
        bindata = f.read()

    # Pad to 4-byte boundary
    while len(bindata) % 4:
        bindata += b'\x00'

    total_words = len(bindata) // 4

    # Nếu có nwords (cách dùng cũ): kiểm tra kích thước như file gốc
    if nwords is not None:
        assert len(bindata) <= 4 * nwords, \
            f"Binary ({len(bindata)} bytes) exceeds {4*nwords} bytes ({nwords} words)!"
        total_words = nwords

    for i in range(total_words):
        if i < len(bindata) // 4:
            w = bindata[4*i : 4*i+4]
            print("%02x%02x%02x%02x" % (w[3], w[2], w[1], w[0]))
        else:
            print("00000000")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <binary_file> [nwords]", file=sys.stderr)
        sys.exit(1)

    bin_path = sys.argv[1]
    nwords   = int(sys.argv[2]) if len(sys.argv) >= 3 else None
    bin_to_hex(bin_path, nwords)
