#!/usr/bin/env python3
# Random code for tb_s256: a 16K "ROM" and a .256 file (random RAM, planes, registers)
# that run every instruction group, prefixes included, in a few hundred thousand clocks.
# HALT (0x76) becomes NOP, so the CPU cannot stop for good (HALT with DI).
#   gen_random.py <seed> <rom out> <.256 out>
import random
import sys

seed, rom_out, f256_out = int(sys.argv[1]), sys.argv[2], sys.argv[3]
rnd = random.Random(seed)


def code(n):
    return bytes(0x00 if b == 0x76 else b for b in (rnd.randrange(256) for _ in range(n)))


with open(rom_out, "wb") as f:
    f.write(code(16384))

regs = bytearray(rnd.randrange(256) for _ in range(28))
regs[8] = 0x72   # PC = 0x0072, as the core starts a snapshot
regs[9] = 0x00
regs[26] = rnd.randrange(16)  # IFF2, IFF1, IM (IM 3 is IM 2 for T80)
with open(f256_out, "wb") as f:
    f.write(code(49152))
    f.write(bytes(rnd.randrange(256) for _ in range(49152 * 8)))
    f.write(regs)
