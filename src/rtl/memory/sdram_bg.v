`timescale 1ns / 1ps
`default_nettype wire
/*
 sdram_bg.v
 The SDRAM of the board for the backgrounds of the games (docs/SIMD.md section 7): bytes written by
 the file loader, lines of 256 bytes read for the video. 16-bit SDRAM, 4 banks x 8192 rows x 512
 columns (32 MB), CAS latency 2, burst length 1, on clk (56.25 MHz; SDR_CLK is clk at 180 degrees from
 an ODDR2 in the top).
 - init: 200 us, PRECHARGE ALL, 2 x AUTO REFRESH, LOAD MODE;
 - write: a byte (DQM selects it) from a FIFO of 4: ACTIVE, WRITE with auto precharge;
 - line: 128 words from byte address line_addr (256-byte aligned: one SDRAM row holds it): ACTIVE,
   128 READs one per clock, PRECHARGE ALL; the words go to the line buffer as lb_we / lb_addr /
   lb_data (lb_addr = {line_sel, word}); about 140 clocks;
 - AUTO REFRESH every REFRESH_CLOCKS clocks (8192 rows in 64 ms: 7.8 us).
 Byte address [23:0]: word = addr[23:1]: column [8:0], row [21:9], bank {0, word[22]}.
 RD_DELAY: the clocks from a READ command to the clock that takes its data (CAS latency 2, plus the
 half clock of SDR_CLK at 180 degrees and the delays of the pads).
*/
module sdram_bg #(
	parameter INIT_CLOCKS = 15'd12000,    // 213 us at 56.25 MHz
	parameter REFRESH_CLOCKS = 10'd390,   // 6.9 us
	parameter RD_DELAY = 3
) (
	input wire clk,
	input wire reset,

	// bytes of the file loader
	input wire wr,
	input wire [23:0] wr_addr,
	input wire [7:0] wr_data,

	// a line for the video: a pulse of line_req starts it
	input wire line_req,
	input wire [23:0] line_addr,
	input wire line_sel,
	output reg lb_we = 1'b0,
	output reg [7:0] lb_addr = 8'd0,
	output reg [15:0] lb_data = 16'd0,
	output wire ready,                    // init done

	// SDRAM
	output reg [12:0] sdr_a = 13'd0,
	output reg [1:0] sdr_ba = 2'd0,
	inout wire [15:0] sdr_dq,
	output reg [1:0] sdr_dqm = 2'b11,
	output reg sdr_ras_n = 1'b1,
	output reg sdr_cas_n = 1'b1,
	output reg sdr_we_n = 1'b1
);

localparam [2:0] CMD_NOP = 3'b111, CMD_ACTIVE = 3'b011, CMD_READ = 3'b101, CMD_WRITE = 3'b100,
	CMD_PRECHARGE = 3'b010, CMD_REFRESH = 3'b001, CMD_MODE = 3'b000;

localparam [3:0] S_INIT = 0, S_INIT_PRE = 1, S_INIT_REF1 = 2, S_INIT_REF2 = 3, S_INIT_MODE = 4,
	S_IDLE = 5, S_WAIT = 6, S_WR_CMD = 7, S_RD_ACT = 8, S_RD_CMD = 9, S_RD_END = 10;

reg [3:0] state = S_INIT;
reg [3:0] next_state = S_IDLE;
reg [14:0] cnt = 15'd0;
reg [9:0] ref_cnt = 10'd0;
reg ref_pending = 1'b0;
reg init_done = 1'b0;
assign ready = init_done;

task cmd(input [2:0] c);
	begin
		sdr_ras_n <= c[2];
		sdr_cas_n <= c[1];
		sdr_we_n <= c[0];
	end
endtask

// the write FIFO: 4 bytes
reg [31:0] fifo [0:3];
reg [1:0] f_wp = 2'd0, f_rp = 2'd0;
reg [2:0] f_n = 3'd0;
wire [31:0] f_head = fifo[f_rp];
wire f_pop;

// the data bus: driven in the clock of a WRITE
reg dq_oe = 1'b0;
reg [15:0] dq_out = 16'd0;
assign sdr_dq = dq_oe ? dq_out : 16'bz;

// the line being read
reg line_pend = 1'b0;
reg [23:0] l_addr;
reg l_sel;
reg [7:0] rd_n;                       // READs issued
reg [RD_DELAY:0] rd_pipe = 0;         // a READ RD_DELAY clocks ago
reg [6:0] lb_word = 7'd0;

reg pop;
assign f_pop = pop;

always @(posedge clk) begin
	// the FIFO
	if (wr && f_n != 3'd4) begin
		fifo[f_wp] <= {wr_addr, wr_data};
		f_wp <= f_wp + 1'd1;
	end
	if (pop) f_rp <= f_rp + 1'd1;
	f_n <= f_n + (wr && f_n != 3'd4 ? 3'd1 : 3'd0) - (pop ? 3'd1 : 3'd0);

	if (line_req) begin
		line_pend <= 1'b1;
		l_addr <= line_addr;
		l_sel <= line_sel;
	end

	if (ref_cnt == REFRESH_CLOCKS) begin
		ref_cnt <= 10'd0;
		ref_pending <= 1'b1;
	end else
		ref_cnt <= ref_cnt + 1'd1;

	// the data of the READs
	rd_pipe <= {rd_pipe[RD_DELAY-1:0], 1'b0};
	lb_we <= 1'b0;
	if (rd_pipe[RD_DELAY-1]) begin
		lb_we <= 1'b1;
		lb_data <= sdr_dq;
		lb_addr <= {l_sel, lb_word};
		lb_word <= lb_word + 1'd1;
	end

	pop <= 1'b0;
	cmd(CMD_NOP);
	dq_oe <= 1'b0;
	sdr_dqm <= 2'b00;

	if (reset) begin
		state <= S_INIT;
		cnt <= 15'd0;
		init_done <= 1'b0;
		line_pend <= 1'b0;
		f_wp <= 2'd0;
		f_rp <= 2'd0;
		f_n <= 3'd0;
		sdr_dqm <= 2'b11;
	end else case (state)
		S_INIT: begin
			sdr_dqm <= 2'b11;
			cnt <= cnt + 1'd1;
			if (cnt == INIT_CLOCKS) state <= S_INIT_PRE;
		end
		S_INIT_PRE: begin
			cmd(CMD_PRECHARGE);
			sdr_a[10] <= 1'b1;                // all banks
			cnt <= 15'd3;
			next_state <= S_INIT_REF1;
			state <= S_WAIT;
		end
		S_INIT_REF1: begin
			cmd(CMD_REFRESH);
			cnt <= 15'd8;
			next_state <= S_INIT_REF2;
			state <= S_WAIT;
		end
		S_INIT_REF2: begin
			cmd(CMD_REFRESH);
			cnt <= 15'd8;
			next_state <= S_INIT_MODE;
			state <= S_WAIT;
		end
		S_INIT_MODE: begin
			cmd(CMD_MODE);
			sdr_ba <= 2'b00;
			sdr_a <= 13'b000_1_00_010_0_000;  // single location writes, CAS 2, sequential, burst 1
			cnt <= 15'd3;
			next_state <= S_IDLE;
			state <= S_WAIT;
		end

		S_WAIT: begin
			if (cnt == 15'd0) begin
				state <= next_state;
				if (next_state == S_IDLE) init_done <= 1'b1;
			end else
				cnt <= cnt - 1'd1;
		end

		S_IDLE: begin
			if (ref_pending) begin
				ref_pending <= 1'b0;
				cmd(CMD_REFRESH);
				cnt <= 15'd6;
				next_state <= S_IDLE;
				state <= S_WAIT;
			end else if (f_n != 3'd0) begin
				// ACTIVE the row of the byte
				cmd(CMD_ACTIVE);
				sdr_ba <= {1'b0, f_head[31]};
				sdr_a <= f_head[30:18];
				cnt <= 15'd0;
				next_state <= S_WR_CMD;
				state <= S_WAIT;
			end else if (line_pend) begin
				line_pend <= 1'b0;
				cmd(CMD_ACTIVE);
				sdr_ba <= {1'b0, l_addr[23]};
				sdr_a <= l_addr[22:10];
				rd_n <= 8'd0;
				lb_word <= 7'd0;
				cnt <= 15'd0;
				next_state <= S_RD_CMD;
				state <= S_WAIT;
			end
		end

		// WRITE with auto precharge, then tWR + tRP
		S_WR_CMD: begin
			cmd(CMD_WRITE);
			sdr_a <= {2'b00, 1'b1, 1'b0, f_head[17:9]};
			dq_out <= {f_head[7:0], f_head[7:0]};
			dq_oe <= 1'b1;
			sdr_dqm <= f_head[8] ? 2'b01 : 2'b10;   // the odd byte is the high one
			pop <= 1'b1;
			cnt <= 15'd4;
			next_state <= S_IDLE;
			state <= S_WAIT;
		end

		// 128 READs of the row, one per clock
		S_RD_CMD: begin
			cmd(CMD_READ);
			sdr_a <= {2'b00, 1'b0, 1'b0, l_addr[9:8], rd_n[6:0]};
			rd_pipe[0] <= 1'b1;
			rd_n <= rd_n + 1'd1;
			if (rd_n == 8'd127) state <= S_RD_END;
		end

		// the last data, then PRECHARGE ALL and tRP
		S_RD_END: begin
			if (rd_pipe == 0) begin
				cmd(CMD_PRECHARGE);
				sdr_a[10] <= 1'b1;
				cnt <= 15'd3;
				next_state <= S_IDLE;
				state <= S_WAIT;
			end
		end

		default: state <= S_IDLE;
	endcase
end

endmodule
