#!/usr/bin/env python3
# A test of the lane addresses for tb_s256 (G_TABLE): a ROM and a .256 where every lane looks its own
# byte up in a table of reversed bytes, as games flip their sprites (Exolon, Renegade, Knight Lore):
#   0072: LD A,(9000h)   the byte of each lane: main 01, lane p 1 << p
#         LD H,80h
#         LD L,A
#         LD A,(HL)      the table at 8000h, natural planes: reverse(L) of each lane
#         LD (9001h),A
#   loop: JR loop
# At the end lane p has A = 1 << (7 - p) (with the address of the main CPU: 80h in every lane).
#   gen_table.py <rom out> <.256 out>
import sys

rom = bytearray(16384)
code = bytes([0x3A, 0x00, 0x90, 0x26, 0x80, 0x6F, 0x7E, 0x32, 0x01, 0x90, 0x18, 0xFE])
rom[0x72:0x72 + len(code)] = code
open(sys.argv[1], "wb").write(rom)

ram = bytearray(49152)
rev = bytes(int("{:08b}".format(i)[::-1], 2) for i in range(256))
ram[0x8000 - 0x4000:0x8100 - 0x4000] = rev
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
