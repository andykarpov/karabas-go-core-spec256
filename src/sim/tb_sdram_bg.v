// tb_sdram_bg: sdram_bg.v against a model of the SDRAM (CAS latency 2, burst 1). The SDRAM clock is
// clk at 180 degrees (the ODDR2 of the top): commands are taken on the falling edge of clk, read data
// is valid from tAC (5.4 ns) after the second SDRAM edge to tOH (2.7 ns) after the third.
// Writes the bytes of two lines (a byte every 14 clocks, as the file loader with 32 MHz bursts), reads
// both lines into the line buffer and checks every word; checks the timing rules of the commands
// (tRCD, a READ or WRITE only to the open row, a refresh at least every 7.8 us).
//   cd src/sim && iverilog -g2005 -o work/tb_sdram_bg ../rtl/memory/sdram_bg.v tb_sdram_bg.v && vvp work/tb_sdram_bg
// Prints "tb_sdram_bg: <n> errors".
`timescale 1ns / 1ps
module tb_sdram_bg;
parameter real T = 17.778;         // 56.25 MHz
reg clk = 0, reset = 1;
always #(T/2) clk = ~clk;

reg wr = 0, line_req = 0, line_sel = 0;
reg [23:0] wr_addr = 0, line_addr = 0;
reg [7:0] wr_data = 0;
wire lb_we, ready;
wire [7:0] lb_addr;
wire [15:0] lb_data;
wire [12:0] sdr_a;
wire [1:0] sdr_ba, sdr_dqm;
wire [15:0] sdr_dq;
wire ras_n, cas_n, we_n;
integer errors = 0, i, refreshes = 0;
real last_ref = 0;

sdram_bg #(.INIT_CLOCKS(15'd100)) dut(.clk(clk), .reset(reset), .wr(wr), .wr_addr(wr_addr),
	.wr_data(wr_data), .line_req(line_req), .line_addr(line_addr), .line_sel(line_sel), .lb_we(lb_we),
	.lb_addr(lb_addr), .lb_data(lb_data), .ready(ready), .sdr_a(sdr_a), .sdr_ba(sdr_ba), .sdr_dq(sdr_dq),
	.sdr_dqm(sdr_dqm), .sdr_ras_n(ras_n), .sdr_cas_n(cas_n), .sdr_we_n(we_n));

// the model: 2 banks used (bank bit 1 is always 0 here), 8192 rows x 512 columns
reg [15:0] mem [0:(1<<23)-1];
reg [12:0] open_row [0:3];
reg row_open [0:3];
real act_time [0:3];
reg [15:0] dq_drive = 16'bz;
assign sdr_dq = dq_drive;
reg moded = 0;

task fail(input [8*40-1:0] what);
	begin
		errors = errors + 1;
		if (errors < 20) $display("%t: %0s", $time, what);
	end
endtask

always @(negedge clk) begin : model
	reg [22:0] w;
	case ({ras_n, cas_n, we_n})
		3'b011: begin  // ACTIVE
			if (row_open[sdr_ba]) fail("ACTIVE to an open bank");
			row_open[sdr_ba] = 1; open_row[sdr_ba] = sdr_a; act_time[sdr_ba] = $realtime;
		end
		3'b100, 3'b101: begin  // WRITE, READ
			if (!moded) fail("access before LOAD MODE");
			if (!row_open[sdr_ba]) fail("access to a closed bank");
			if ($realtime - act_time[sdr_ba] < 15.0) fail("tRCD");
			w = {sdr_ba[0], open_row[sdr_ba], sdr_a[8:0]};
			if (we_n == 0) begin
				if (!sdr_dqm[0]) mem[w][7:0] = sdr_dq[7:0];
				if (!sdr_dqm[1]) mem[w][15:8] = sdr_dq[15:8];
			end else
				read_out(mem[w]);
			if (sdr_a[10]) row_open[sdr_ba] = 0;   // auto precharge
		end
		3'b010: begin  // PRECHARGE
			if (sdr_a[10]) begin row_open[0] = 0; row_open[1] = 0; row_open[2] = 0; row_open[3] = 0; end
			else row_open[sdr_ba] = 0;
		end
		3'b001: begin  // AUTO REFRESH
			if (row_open[0] || row_open[1] || row_open[2] || row_open[3]) fail("REFRESH with a row open");
			if (moded && $realtime - last_ref > 7800.0) fail("refresh interval");
			last_ref = $realtime; refreshes = refreshes + 1;
		end
		3'b000: moded = 1;  // LOAD MODE
	endcase
end

// data of a READ: valid from 2 SDRAM clocks + tAC to 3 SDRAM clocks + tOH (the value taken now)
task read_out(input [15:0] d);
	begin
		dq_drive <= #(2*T + 5.4) d;
		dq_drive <= #(3*T + 2.7) 16'bz;
	end
endtask

// the line buffer: 2 x 128 words
reg [15:0] lb [0:255];
always @(posedge clk) if (lb_we) lb[lb_addr] <= lb_data;

function [7:0] pattern(input [23:0] a);
	pattern = a[7:0] ^ a[15:8] ^ (a[23:16] * 8'd37) ^ 8'h5A;
endfunction

initial begin
	for (i = 0; i < 4; i = i + 1) row_open[i] = 0;
	#100 reset = 0;
	wait (ready);
	// two lines of background 3 (byte address 3 * 65536 + y * 256), y 10 and 11, a byte every 14 clocks
	for (i = 0; i < 512; i = i + 1) begin
		@(posedge clk) begin
			wr <= 1;
			wr_addr <= 24'h030000 + 24'd10 * 256 + i;
			wr_data <= pattern(24'h030000 + 24'd10 * 256 + i);
		end
		@(posedge clk) wr <= 0;
		repeat (12) @(posedge clk);
	end
	repeat (20) @(posedge clk);
	// line 10 into half 0, line 11 into half 1
	@(posedge clk) begin line_req <= 1; line_addr <= 24'h030000 + 24'd10 * 256; line_sel <= 0; end
	@(posedge clk) line_req <= 0;
	repeat (300) @(posedge clk);
	@(posedge clk) begin line_req <= 1; line_addr <= 24'h030000 + 24'd11 * 256; line_sel <= 1; end
	@(posedge clk) line_req <= 0;
	repeat (300) @(posedge clk);
	for (i = 0; i < 256; i = i + 1)
		if (lb[i] !== {pattern(24'h030000 + 24'd10 * 256 + 2*i + 1), pattern(24'h030000 + 24'd10 * 256 + 2*i)}) begin
			errors = errors + 1;
			if (errors < 20) $display("line buffer word %0d: %h", i, lb[i]);
		end
	// 20 us idle: the refreshes go on
	repeat (1200) @(posedge clk);
	if (refreshes < 5) begin errors = errors + 1; $display("%0d refreshes", refreshes); end
	$display("tb_sdram_bg: %0d errors", errors);
	$finish;
end
endmodule
