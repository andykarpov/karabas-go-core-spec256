// tb_sram: the lane reads of sram.v (lane_a / lane_en, T80_S256 GA): a lane reads its plane byte at
// its own address only in the same 256-byte page, when the word at the address of the main CPU is not
// coloured (a table) and the 8 lane addresses are not all the same; otherwise it gets the plane of that
// word.
//   cd src/sim && sed 's/\bdo\b/dout/g; s/ = 9.b111111111,/,/' ../rtl/memory/sram.v > work/sram_t.v &&
//   iverilog -g2005 -o work/tb_sram work/sram_t.v tb_sram.v && vvp work/tb_sram
// (iverilog takes neither the default value of wr_mask nor, in SystemVerilog mode, the port "do")
// Prints "tb_sram: <n> errors".
`timescale 1ns / 1ps
module tb_sram;
reg clk = 0, reset = 1, rd = 0, lane_en = 0;
reg [15:0] a = 0;
reg [127:0] lane_a = 0;
wire [71:0] dout;
wire [20:0] sram_a;
wire [15:0] sram_d;
wire [1:0] sram_wr_n, sram_rd_n;
wire busy, do_rdy, cpu_ena;
reg [15:0] mem [0:(1<<19)-1];
integer errors = 0, i, p;

always #5 clk = ~clk;
assign sram_d = (sram_rd_n == 2'b00) ? mem[sram_a[18:0]] : 16'bz;

sram dut(.clk(clk), .reset(reset), .a(a), .di(72'd0), .dout(dout), .wr(1'b0), .wr_mask(9'h1FF),
	.rd(rd), .lane_a(lane_a), .lane_en(lane_en), .cpu_ena(cpu_ena), .sram_a(sram_a), .sram_d(sram_d),
	.sram_wr_n(sram_wr_n), .sram_rd_n(sram_rd_n), .busy(busy), .do_rdy(do_rdy));

// the word of an address: main byte m, plane p = pl[p]
task put(input [15:0] addr, input [7:0] m, input [63:0] pl);
	begin
		mem[{addr, 3'b000}] = {8'h00, m};
		mem[{addr, 3'b001}] = pl[15:0];
		mem[{addr, 3'b010}] = pl[31:16];
		mem[{addr, 3'b011}] = pl[47:32];
		mem[{addr, 3'b100}] = pl[63:48];
	end
endtask

task read(input [15:0] addr);
	begin
		@(negedge clk) a = addr; rd = 1;
		@(negedge clk); @(negedge clk);
		while (busy) @(negedge clk);
		rd = 0;
		@(negedge clk);
	end
endtask

task expect(input [63:0] pl, input [8*24-1:0] what);
	begin
		if (dout[71:8] !== pl) begin
			errors = errors + 1;
			$display("%0s: planes %h, expected %h", what, dout[71:8], pl);
		end
	end
endtask

initial begin
	for (i = 0; i < 128; i = i + 1) begin put(16'h8000 + i, 8'h00, 64'd0); put(16'h9000 + i, 8'h00, 64'd0); end
	put(16'h8040, 8'h12, {8{8'h12}});                      // a table entry, not coloured
	put(16'h9040, 8'h12, 64'h12_12_12_12_77_12_12_12);     // coloured (plane 3)
	// the entries of the lanes: plane p of 80(10+p) is A0+p
	for (p = 1; p < 8; p = p + 1) put(16'h8010 + p, 8'h55, {8{8'hA0 + p[7:0]}});
	for (p = 1; p < 8; p = p + 1) put(16'h9010 + p, 8'h55, {8{8'hA0 + p[7:0]}});
	put(16'h7015, 8'h55, {8{8'hEE}});
	#20 reset = 0;
	#40;   // prev_rd of sram.v is not reset: a clock with rd = 0 first

	// lane 0 at a, lanes 1..7 at 80(10+p) in the page of a: each its own entry
	lane_en = 1;
	lane_a[15:0] = 16'h8040;
	for (p = 1; p < 8; p = p + 1) lane_a[16*p +: 16] = 16'h8010 + p;
	read(16'h8040);
	expect({8'hA7, 8'hA6, 8'hA5, 8'hA4, 8'hA3, 8'hA2, 8'hA1, 8'h12}, "table");

	// lane_en off: the planes of a
	lane_en = 0;
	read(16'h8040);
	expect({8{8'h12}}, "lane_en off");

	// the word at a coloured: the planes of a
	lane_en = 1;
	lane_a[15:0] = 16'h9040;
	for (p = 1; p < 8; p = p + 1) lane_a[16*p +: 16] = 16'h9010 + p;
	read(16'h9040);
	expect(64'h12_12_12_12_77_12_12_12, "coloured");

	// lane 5 in another page: the plane of a for it, the others their entries
	lane_a[15:0] = 16'h8040;
	for (p = 1; p < 8; p = p + 1) lane_a[16*p +: 16] = 16'h8010 + p;
	lane_a[16*5 +: 16] = 16'h7015;
	read(16'h8040);
	expect({8'hA7, 8'hA6, 8'h12, 8'hA4, 8'hA3, 8'hA2, 8'hA1, 8'h12}, "other page");

	// the 8 lane addresses the same (a coordinate gone apart): the planes of a
	for (p = 0; p < 8; p = p + 1) lane_a[16*p +: 16] = 16'h8013;
	read(16'h8040);
	expect({8{8'h12}}, "uniform");

	$display("tb_sram: %0d errors", errors);
	$finish;
end
endmodule
