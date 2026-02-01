module sram(
    input wire             clk,
    input wire             reset,

    input wire  [15:0]     a,
    input wire  [63:0]     di,
    output reg  [63:0]     do,
    input wire             wr,
    input wire             rd,
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
localparam S_READ1          = 5;
localparam S_READ2          = 6;
localparam S_READ3          = 7;
localparam S_READ4          = 8;
localparam S_READ1_DONE     = 9;
localparam S_READ2_DONE     = 10;
localparam S_READ3_DONE     = 11;
localparam S_READ4_DONE     = 12;
localparam S_WRITE1_DONE     = 13;
localparam S_WRITE2_DONE     = 14;
localparam S_WRITE3_DONE     = 15;
localparam S_WRITE4_DONE     = 16;

reg [4:0] state = S_IDLE;
reg [63:0] diD;
reg [15:0] outD;
reg [15:0] aD;
assign sram_d = (sram_wr_n != 2'b11) ? outD : 16'bz;
reg prev_rd, prev_wr;

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
                    state <= S_WRITE1;
                end
                else if (rd && ~prev_rd) begin
                    busy <= 1;
                    do_rdy <= 0;
                    aD <= a;
                    state <= S_READ1;
                end                
            end
            
            S_READ1: begin
                sram_a <= {aD[15:0], 2'b00};
                sram_rd_n <= 2'b00;
                state <= S_READ1_DONE;
            end
				
				S_READ1_DONE: begin
					do[15:0] <= sram_d;
					sram_rd_n <= 2'b11;
					state <= S_READ2;
				end
            
            S_READ2: begin
                sram_a <= sram_a+1;
                sram_rd_n <= 2'b00;
                state <= S_READ2_DONE;
            end

				S_READ2_DONE: begin
					do[31:16] <= sram_d;
					sram_rd_n <= 2'b11;
					state <= S_READ3;
				end
 
            S_READ3: begin
                sram_a <= sram_a+1;
					 sram_rd_n <= 2'b00;
                state <= S_READ3_DONE;
            end
				
				S_READ3_DONE: begin
					do[47:32] <= sram_d;
					sram_rd_n <= 2'b11;
					state <= S_READ4;
				end

            S_READ4: begin
                sram_a <= sram_a+1;
					 sram_rd_n <= 2'b00;
                state <= S_READ4_DONE;
            end

            S_READ4_DONE: begin
                do[63:48] <= sram_d;
                sram_rd_n <= 2'b11;
                do_rdy <= 1;
                state <= S_IDLE;
            end

            S_WRITE1: begin
                sram_a <= {aD[15:0], 2'b00};
                outD <= diD[15:0];
                sram_wr_n <= 2'b00;
                state <= S_WRITE1_DONE;
            end
				
				S_WRITE1_DONE: begin
					sram_wr_n <= 2'b11;
					state <= S_WRITE2;
				end

            S_WRITE2: begin
                sram_a <= sram_a + 1;
                outD <= diD[31:16];
                sram_wr_n <= 2'b00;
                state <= S_WRITE2_DONE;
            end

				S_WRITE2_DONE: begin
					sram_wr_n <= 2'b11;
					state <= S_WRITE3;
				end

           S_WRITE3: begin
                sram_a <= sram_a + 1;
                outD <= diD[47:32];
					 sram_wr_n <= 2'b00;
                state <= S_WRITE3_DONE;
            end

				S_WRITE3_DONE: begin
					sram_wr_n <= 2'b11;
					state <= S_WRITE4;
				end

           S_WRITE4: begin
                sram_a <= sram_a + 1;
                outD <= diD[63:48];
					 sram_wr_n <= 2'b00;
                state <= S_WRITE4_DONE;
            end

				S_WRITE4_DONE: begin
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
