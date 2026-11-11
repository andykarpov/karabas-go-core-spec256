#!/usr/bin/env python3
# A test of ARITH_MONO for tb_s256 (G_MONO): after an instruction that puts arithmetic into A the lanes take
# the A of the main CPU; AND, XOR, OR r keep the colour. A ROM and a .256 where A is coloured (main 01,
# lane p 1 << p) before each instruction:
#   0072: LD A,(9000h)  LD B,A
#         ADD A,0       LD C,A     mono: 01, else 1 << p
#         LD A,B  OR 0  LD D,A     mono: 01, else 1 << p
#         LD A,B  AND A LD E,A     1 << p (a logic op on a register keeps the colour)
#         LD A,B  NEG   LD H,A     mono: FF, else -(1 << p)
#         LD A,B  INC A LD L,A     mono: 02, else (1 << p) + 1
#         LD A,B  ADC A,0          mono: 02, else (1 << p) + 1 (NEG left the carry set in every lane)
#   loop: JR loop
#   gen_mono.py <rom out> <.256 out>
import sys

rom = bytearray(16384)
code = bytes([0x3A, 0x00, 0x90, 0x47,
              0xC6, 0x00, 0x4F,
              0x78, 0xF6, 0x00, 0x57,
              0x78, 0xA7, 0x5F,
              0x78, 0xED, 0x44, 0x67,
              0x78, 0x3C, 0x6F,
              0x78, 0xCE, 0x00,
              0x18, 0xFE])
rom[0x72:0x72 + len(code)] = code
open(sys.argv[1], "wb").write(rom)

ram = bytearray(49152)
ram[0x9000 - 0x4000] = 0x01
planes = bytearray()
for i in range(49152):
    if i == 0x9000 - 0x4000:
        planes += bytes(1 << p for p in range(8))
    else:
        planes += bytes([ram[i]] * 8)
regs = bytearray(28)
regs[6], regs[7] = 0x00, 0xFF   # SP = FF00 (its stack: the PC of the snapshot, 0072 again)
regs[8], regs[9] = 0x72, 0x00
ram[0xFF00 - 0x4000], ram[0xFF01 - 0x4000] = 0x72, 0x00
planes[(0xFF00 - 0x4000) * 8:(0xFF02 - 0x4000) * 8] = bytes([0x72] * 8 + [0x00] * 8)
open(sys.argv[2], "wb").write(ram + planes + regs)
