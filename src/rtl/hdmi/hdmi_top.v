`timescale 1ns / 1ps
`default_nettype wire
/*
 hdmi_top.v
 HDMI of the spec256 core: hdmi_tx (zhdmi, karabas-go-modules) on the VGA clock, the 5x serial
 clock pair from hdmi_pll (DCM_SP), audio samples at SAMPLERATE.
 The zhdmi_top of karabas-go-modules is made for the 28 / 24 MHz clock of profi (ds80) and its
 audio_samplerate gives fs / 2 (karabas-go-modules docs/PLAN.md, tsconf): here the sample strobe
 comes from a fractional counter, SAMPLERATE strobes per CLKRATE clocks exactly.
 The audio comes from the clock of the core (the beeper, a bit that changes at audio rates): two
 flip-flops on the pixel clock. audio_en (the DVI switch of the MCU) too: straight into hdmi_tx it
 was timed as a path from clk_bus to the 5x serial clock (karabas-go-modules docs/PLAN.md).
*/
module hdmi_top #(
	parameter SAMPLERATE = 44100,
	parameter CLKRATE = 27000000    // the frequency of clk, Hz
) (
	input wire clk,                 // VGA pixel clock
	input wire reset,
	input wire [23:0] vga_rgb,
	input wire vga_hs,
	input wire vga_vs,
	input wire vga_de,
	input wire audio_en,            // 0: DVI (hdmi_tx sends no data islands)
	input wire [15:0] audio_l,      // from the clock of the core
	input wire [15:0] audio_r,
	output wire [3:0] tmds_p,
	output wire [3:0] tmds_n
);

wire clk_hdmi, clk_hdmi_n, clk_pix, locked;

hdmi_pll hdmi_pll (
	.clk(clk),
	.reset(reset),
	.clk_hdmi(clk_hdmi),
	.clk_hdmi_n(clk_hdmi_n),
	.clk_pix(clk_pix),
	.clk_pix2(),
	.locked(locked),
	.o_reset()
);

// audio: into the pixel clock, a sample every CLKRATE / SAMPLERATE clocks on average
reg [15:0] audio_l_s1 = 16'd0, audio_l_s2 = 16'd0, audio_r_s1 = 16'd0, audio_r_s2 = 16'd0;
reg audio_en_s1 = 1'b0, audio_en_s2 = 1'b0;
reg [24:0] audio_acc = 25'd0;
reg audio_stb = 1'b0;
reg signed [23:0] hdmi_audio_l = 24'sd0, hdmi_audio_r = 24'sd0;

always @(posedge clk_pix) begin
	audio_en_s1 <= audio_en;
	audio_en_s2 <= audio_en_s1;
	audio_l_s1 <= audio_l;
	audio_l_s2 <= audio_l_s1;
	audio_r_s1 <= audio_r;
	audio_r_s2 <= audio_r_s1;
	if (audio_acc + SAMPLERATE >= CLKRATE) begin
		audio_acc <= audio_acc + SAMPLERATE - CLKRATE;
		audio_stb <= 1'b1;
	end else begin
		audio_acc <= audio_acc + SAMPLERATE;
		audio_stb <= 1'b0;
	end
	if (audio_stb) begin
		hdmi_audio_l <= { audio_l_s2, 8'h00 };
		hdmi_audio_r <= { audio_r_s2, 8'h00 };
	end
end

hdmi_tx #(.SAMPLE_FREQ(SAMPLERATE)) hdmi_tx (
	.clk(clk_pix),
	.sclk(clk_hdmi),
	.sclk_n(clk_hdmi_n),
	.reset(reset || ~locked),
	.rgb(vga_rgb),
	.vsync(vga_vs),
	.hsync(vga_hs),
	.de(vga_de),
	.audio_en(audio_en_s2),
	.audio_l(hdmi_audio_l),
	.audio_r(hdmi_audio_r),
	.audio_clk(audio_stb),
	.tx_clk_n(tmds_n[3]),
	.tx_clk_p(tmds_p[3]),
	.tx_d_n(tmds_n[2:0]),
	.tx_d_p(tmds_p[2:0])   // 0: blue, 1: green, 2: red
);

endmodule
