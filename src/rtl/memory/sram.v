module sram(
    input wire             clk,
    input wire             reset,

    input wire  [15:0]     a,
    input wire  [3:0]      bank,         // the bank of a (pager.vhd): the SRAM word is {bank, a[13:0], 3 bits}
    input wire  [71:0]     di,
    output reg  [71:0]     do,
    input wire             wr,
	 input wire  [8:0]      wr_mask = 9'b111111111,
    input wire             rd,
	 // karabas: the addresses of the 8 lanes (T80_S256 GA, lane p in bits 16p+15..16p) for a read with
	 // lane_en: after the 72-bit word of a, the plane byte of a lane is read at its own address when
	 // that is a table lookup with a byte of the lane: a in one of lane_pages (the converter finds the
	 // tables of reversed bytes that games flip their sprites with; other tables, masks, must give the
	 // entry of the main byte), the same 256-byte page as a (only L differs),
	 // the word of a not coloured (its 8 planes are the main byte: a table, not graphics) and the 8
	 // lane addresses not all the same (the lanes hold the colours of a graphics byte). A lane
	 // address that differs otherwise is a pointer or a coordinate gone apart from the main CPU (the
	 // planes of the variables are those of the moment the GFX was made, the same in every plane):
	 // the lane reads at a. The CPU waits on busy.
	 input wire  [127:0]    lane_a,
	 input wire             lane_en,
	 input wire  [23:0]     lane_pages,   // the pages of the tables of reversed bytes (the .256), 0: none
	 // karabas: the read windows of the game (the block of the windows of the .256, up to 8): a read of
	 // data (not M1) whose page a[15:8] is in [first, last] of a window, with the opcode (the last byte
	 // read in an M1 cycle: xx of CB xx / ED xx, CB of DD CB d xx) passing its filter
	 // ((op ^ value) & mask) == 0 (inverted with negate), hits; the first window that hits wins. On a
	 // hit each lane with lane_en reads at its own address when the 8 differ (any page of the RAM: the
	 // bank of its 16K window, 4000 bank 5, 8000 bank 2, C000 top_bank) and every plane byte is XORed with
	 // the xor of the window. Spec256 DOS v1.2 reads so (synthetic readers of SPEC256.EXE) in Knight Lore,
	 // Sabre Wulf, Underwurlde; Head over Heels, Scooby-Doo, Bubbler, Mad Mix 2 need it in theirs.
	 input wire             m1,           // the read is an M1 cycle (an opcode)
	 input wire  [2:0]      top_bank,     // the bank at C000 (#7FFD bits 2..0)
	 input wire             win_we,       // a window from the loader: {xor, negate, mask, value, last,
	 input wire  [2:0]      win_wa,       // first}; windows 0..win_cnt-1 are in use
	 input wire  [40:0]     win_wd,
	 input wire  [3:0]      win_cnt,
	 output wire            cpu_ena,

    output reg  [20:0]     sram_a = 0,
    inout wire  [15:0]     sram_d,
    output reg  [1:0]      sram_wr_n = 2'b11,
    output reg  [1:0]      sram_rd_n = 2'b11,
    
    output reg             busy = 0,
    output reg             do_rdy = 0
);

// FSM states
localparam S_IDLE           = 0;
localparam S_WRITE1         = 1;
localparam S_WRITE2         = 2;
localparam S_WRITE3         = 3;
localparam S_WRITE4         = 4;
localparam S_WRITE5         = 5;
localparam S_READ1          = 6;
localparam S_READ2          = 7;
localparam S_READ3          = 8;
localparam S_READ4          = 9;
localparam S_READ5          = 10;
localparam S_READ1_DONE     = 11;
localparam S_READ2_DONE     = 12;
localparam S_READ3_DONE     = 13;
localparam S_READ4_DONE     = 14;
localparam S_READ5_DONE     = 15;
localparam S_WRITE1_DONE     = 16;
localparam S_WRITE2_DONE     = 17;
localparam S_WRITE3_DONE     = 18;
localparam S_WRITE4_DONE     = 19;
localparam S_WRITE5_DONE     = 20;
localparam S_LANE           = 21;
localparam S_LANE_DONE      = 22;

reg [4:0] state = S_IDLE;
reg [71:0] diD;
reg [15:0] outD;
reg [15:0] aD;
reg [3:0] bD;
assign sram_d = (sram_wr_n != 2'b11) ? outD : 16'bz;
reg prev_rd, prev_wr;
reg [127:0] laD;
reg laEn;
reg laUni;   // the 8 lane addresses are the same
wire table_page = aD[15:8] != 8'h00 &&
	(aD[15:8] == lane_pages[7:0] || aD[15:8] == lane_pages[15:8] || aD[15:8] == lane_pages[23:16]);
reg [3:0] lp;
// the word read is not coloured: every plane is the main byte (taken with the last 16 bits of the word,
// before the bytes of the lanes replace planes in do)
reg natural;
// the windows: distributed RAM, one window looked at per clock while the word of a is read
reg [40:0] win [0:7];
always @(posedge clk) if (win_we) win[win_wa] <= win_wd;
reg [3:0] wi;          // the window looked at
reg wHit;              // a window hit
reg [7:0] wX;          // its xor
reg rdM1;              // the read is an opcode
reg [7:0] op;          // the last opcode
wire [40:0] w = win[wi[2:0]];
wire [7:0] w_first = w[7:0], w_last = w[15:8], w_val = w[23:16], w_mask = w[31:24];
wire w_match = !rdM1 && !wHit && wi < win_cnt && aD[15:8] >= w_first && aD[15:8] <= w_last &&
	((((op ^ w_val) & w_mask) == 8'h00) ^ w[32]);
wire [15:0] la_cur = laD[16*lp[2:0] +: 16];
// the bank of the 16K window of the lane address (a lane address in the ROM is a: lane_a of spec256.vhd)
wire [3:0] la_bank = la_cur[15:14] == 2'b01 ? 4'd5 : la_cur[15:14] == 2'b10 ? 4'd2 : {1'b0, top_bank};
wire la_table = la_cur != aD && la_cur[15:8] == aD[15:8] && natural && !laUni && table_page;
wire la_win = wHit && la_cur != aD && !laUni;

reg [3:0] en = 0;
always @(posedge clk, posedge reset)
begin
	if (reset) begin
		en <= 0;
	end
	else begin
		en <= en + 1;
	end
end
assign cpu_ena = (~busy && en == 4'b1111) ? 1'b1 : 1'b0;

// main FSM
always @(posedge clk, posedge reset)
begin
    if (reset) begin
        state <= S_IDLE;
        busy <= 0;
		  sram_wr_n <= 2'b11;
		  sram_rd_n <= 2'b11;
    end
    else begin

		  prev_rd <= rd;
		  prev_wr <= wr;

		  if (w_match) begin
				wHit <= 1'b1;
				wX <= w[40:33];
		  end
		  if (!wi[3]) wi <= wi + 1'd1;

        // state machine
        case (state)

            S_IDLE: begin
                busy <= 0;
                sram_wr_n <= 2'b11;
                sram_rd_n <= 2'b11;
					 outD <= 16'bz;

                if (wr && ~prev_wr) begin
                    busy <= 1;
                    diD <= di;
                    aD <= a;
                    bD <= bank;
						  if (wr_mask[0])
							   state <= S_WRITE1;
						  else if (wr_mask[2:1] != 2'b00)
								state <= S_WRITE2;
						  else if (wr_mask[4:3] != 2'b00)
								state <= S_WRITE3;
						  else if (wr_mask[6:5] != 2'b00)
								state <= S_WRITE4;
						  else if (wr_mask[8:7] != 2'b00)
								state <= S_WRITE5;
						  else 
							 busy <= 0;
                end
                else if (rd && ~prev_rd) begin
                    busy <= 1;
                    do_rdy <= 0;
                    aD <= a;
                    bD <= bank;
                    laD <= lane_a;
                    laEn <= lane_en;
                    laUni <= lane_a[127:16] == {7{lane_a[15:0]}};
                    lp <= 0;
                    rdM1 <= m1;
                    wi <= 0;
                    wHit <= 1'b0;
                    wX <= 8'h00;
                    state <= S_READ1;
                end                
            end
            
            S_READ1: begin
                sram_a <= {bD, aD[13:0], 3'b000};
                sram_rd_n <= 2'b00;
                state <= S_READ1_DONE;
            end
				
				S_READ1_DONE: begin
					do[7:0] <= sram_d[7:0];
					sram_rd_n <= 2'b11;
					state <= S_READ2;
				end
            
            S_READ2: begin
                sram_a <= {bD, aD[13:0], 3'b001};
                sram_rd_n <= 2'b00;
                state <= S_READ2_DONE;
            end

				S_READ2_DONE: begin
					do[23:8] <= sram_d;
					sram_rd_n <= 2'b11;
					state <= S_READ3;
				end
 
            S_READ3: begin
                sram_a <= {bD, aD[13:0], 3'b010};
					 sram_rd_n <= 2'b00;
                state <= S_READ3_DONE;
            end
				
				S_READ3_DONE: begin
					do[39:24] <= sram_d;
					sram_rd_n <= 2'b11;
					state <= S_READ4;
				end

            S_READ4: begin
                sram_a <= {bD, aD[13:0], 3'b011};
					 sram_rd_n <= 2'b00;
                state <= S_READ4_DONE;
            end

            S_READ4_DONE: begin
                do[55:40] <= sram_d;
                sram_rd_n <= 2'b11;
                state <= S_READ5;
            end

            S_READ5: begin
                sram_a <= {bD, aD[13:0], 3'b100};
					 sram_rd_n <= 2'b00;
                state <= S_READ5_DONE;
            end

            S_READ5_DONE: begin
                do[71:56] <= sram_d;
                natural <= {sram_d, do[55:8]} == {8{do[7:0]}};
                sram_rd_n <= 2'b11;
                if (rdM1)
                    op <= do[7:0];
                if (laEn || wHit)
                    state <= S_LANE;
                else begin
                    do_rdy <= 1;
                    state <= S_IDLE;
                end
            end

            // the lanes with an address of their own: word {address, 1 + p/2}, byte p%2
            S_LANE: begin
                if (lp[3]) begin
                    do[71:8] <= do[71:8] ^ {8{wX}};
                    do_rdy <= 1;
                    state <= S_IDLE;
                end
                else if (laEn && (la_table || la_win)) begin
                    // a table: the page of a, the bank of a; a window: the bank of the lane address
                    sram_a <= {la_table ? bD : la_bank, la_cur[13:0], 3'b001 + lp[2:1]};
                    sram_rd_n <= 2'b00;
                    state <= S_LANE_DONE;
                end
                else if (!laEn)
                    lp <= 4'd8;   // a window hit without lane addresses: only the xor
                else
                    lp <= lp + 1'd1;
            end

            S_LANE_DONE: begin
                do[8 + 8*lp[2:0] +: 8] <= lp[0] ? sram_d[15:8] : sram_d[7:0];
                sram_rd_n <= 2'b11;
                lp <= lp + 1'd1;
                state <= S_LANE;
            end

            S_WRITE1: begin
                sram_a <= {bD, aD[13:0], 3'b000};
                outD <= diD[7:0];
                sram_wr_n <= 2'b10;
                state <= S_WRITE1_DONE;
            end
				
				S_WRITE1_DONE: begin
					sram_wr_n <= 2'b11;
					if (wr_mask[2:1] != 2'b00)
						state <= S_WRITE2;
					else if (wr_mask[4:3] != 2'b00)
						state <= S_WRITE3;
					else if (wr_mask[6:5] != 2'b00)
						state <= S_WRITE4;
					else if (wr_mask[8:7] != 2'b00)
						state <= S_WRITE5;
					else
						state <= S_IDLE;
				end

            S_WRITE2: begin
                sram_a <= {bD, aD[13:0], 3'b001};
                outD <= diD[23:8];
                sram_wr_n <= ~wr_mask[2:1];
                state <= S_WRITE2_DONE;
            end

				S_WRITE2_DONE: begin
					sram_wr_n <= 2'b11;
					if (wr_mask[4:3] != 2'b00)
						state <= S_WRITE3;
					else if (wr_mask[6:5] != 2'b00)
						state <= S_WRITE4;
					else if (wr_mask[8:7] != 2'b00)
						state <= S_WRITE5;
					else
						state <= S_IDLE;
				end

           S_WRITE3: begin
                sram_a <= {bD, aD[13:0], 3'b010};
                outD <= diD[39:24];
                sram_wr_n <= ~wr_mask[4:3];
                state <= S_WRITE3_DONE;
            end

				S_WRITE3_DONE: begin
					sram_wr_n <= 2'b11;
					if (wr_mask[6:5] != 2'b00)
						state <= S_WRITE4;
					else if (wr_mask[8:7] != 2'b00)
						state <= S_WRITE5;
					else
						state <= S_IDLE;
				end

           S_WRITE4: begin
                sram_a <= {bD, aD[13:0], 3'b011};
                outD <= diD[55:40];
                sram_wr_n <= ~wr_mask[6:5];
                state <= S_WRITE4_DONE;
            end

				S_WRITE4_DONE: begin
					sram_wr_n <= 2'b11;
					if (wr_mask[8:7] != 2'b00)
						state <= S_WRITE5;
					else
						state <= S_IDLE;
				end

           S_WRITE5: begin
                sram_a <= {bD, aD[13:0], 3'b100};
                outD <= diD[71:56];
                sram_wr_n <= ~wr_mask[8:7];
                state <= S_WRITE5_DONE;
            end

				S_WRITE5_DONE: begin
					sram_wr_n <= 2'b11;
					state <= S_IDLE;
				end
            
            default: begin
                state <= S_IDLE;
            end
            
        endcase
    end
end

endmodule
