#!/usr/bin/env python3
# Random code for tb_s256: a 16K "ROM" and a .256 file (random RAM, planes, registers)
# that run every instruction group, prefixes included, in a hundred thousand clocks.
#   gen_random.py <seed> <rom out> <.256 out>
# The code is a stream of whole instructions (the length of each from the Z80 tables), so the
# CPU runs it from start to end: random bytes alone run operands as opcodes, fall into a short
# loop after a hundred instructions and reach an ED opcode (RLD...) a few times.
# - the prefix is picked first (none, CB, ED, DD, FD, DD CB, FD CB, each 1/7), then the opcode
#   and the operands at random;
# - 9 of 10 jumps, calls, returns and RSTs become NOP and the relative jumps go forward, so
#   the code goes on mostly in a line and the rest still runs the control flow;
# - the repeating block instructions (LDIR, CPIR, INIR, OTIR...) become the single ones
#   (LDI...): BC is random, a repeat would run for up to 65535 times;
# - HALT (0x76) becomes NOP, so the CPU cannot stop for good (HALT with DI).
import random
import sys

seed, rom_out, f256_out = int(sys.argv[1]), sys.argv[2], sys.argv[3]
rnd = random.Random(seed)

PREFIXES = ((), (0xCB,), (0xED,), (0xDD,), (0xFD,), (0xDD, 0xCB), (0xFD, 0xCB))

# unprefixed opcodes with operands: their length
LEN2 = {0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38,
        0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE, 0xD3, 0xDB}
LEN3 = {0x01, 0x11, 0x21, 0x31, 0x22, 0x2A, 0x32, 0x3A,
        0xC2, 0xC3, 0xCA, 0xD2, 0xDA, 0xE2, 0xEA, 0xF2, 0xFA,
        0xC4, 0xCC, 0xCD, 0xD4, 0xDC, 0xE4, 0xEC, 0xF4, 0xFC}
# opcodes on (HL) that take a displacement after DD/FD
HL_MEM = {0x34, 0x35, 0x36, 0x86, 0x8E, 0x96, 0x9E, 0xA6, 0xAE, 0xB6, 0xBE} | \
         {0x46 + 8 * i for i in range(8) if i != 6} | set(range(0x70, 0x78)) - {0x76}
# control flow: DJNZ, JR, JP, CALL, RET, RST, JP (HL)
JUMPS = {0x10, 0x18, 0x20, 0x28, 0x30, 0x38, 0xC3, 0xC9, 0xCD, 0xE9} | \
        {0xC0 + 8 * i + k for i in range(8) for k in (0, 2, 4, 7)}
# ED: LD (nn),rr / LD rr,(nn); RETN / RETI (ED x5, ED xD with bits 7-6 = 01)
ED_LEN4 = {0x43, 0x4B, 0x53, 0x5B, 0x63, 0x6B, 0x73, 0x7B}
ED_RET = {0x45 + 8 * i for i in range(8)}


def rand_bytes(n):
    return [rnd.randrange(256) for _ in range(n)]


def opcode():
    op = rnd.randrange(256)
    if op == 0x76 or op in (0xCB, 0xED, 0xDD, 0xFD) or (op in JUMPS and rnd.random() < 0.9):
        return 0x00
    return op


def base_len(op):
    return 3 if op in LEN3 else 2 if op in LEN2 else 1


def instruction():
    prefix = rnd.choice(PREFIXES)
    if prefix in ((0xDD, 0xCB), (0xFD, 0xCB)):
        return list(prefix) + rand_bytes(2)          # d, opcode
    if prefix == (0xCB,):
        return [0xCB] + rand_bytes(1)
    if prefix == (0xED,):
        op = rnd.randrange(256)
        if op & 0xE4 == 0xA0 and op & 0x10:       # LDIR... -> LDI...
            op &= ~0x10
        if op in ED_RET and rnd.random() < 0.9:
            op = 0x44                              # NEG
        return [0xED, op] + rand_bytes(2 if op in ED_LEN4 else 0)
    op = opcode()
    if op in (0x10, 0x18, 0x20, 0x28, 0x30, 0x38):
        return list(prefix) + [op, rnd.randrange(128)]   # forward: a loop back would run on
    n = base_len(op) - 1
    if prefix and op in HL_MEM:
        n += 1
    return list(prefix) + [op] + rand_bytes(n)


def code(n):
    out = []
    while len(out) < n:
        out += instruction()
    return bytes(out[:n])


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
