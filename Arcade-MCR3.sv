//============================================================================
//  Arcade: Tapper
//
//  Port to MiSTer
//  Copyright (C) 2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,    // 1 - signed audio samples, 0 - unsigned

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE, 

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : (status[2] | landscape) ? 8'd4 : 8'd3;
assign HDMI_ARY = status[1] ? 8'd9  : (status[2] | landscape) ? 8'd3 : 8'd4;

`include "build_id.v" 
localparam CONF_STR = {
	"A.TAPPER;;",
	"H0O1,Aspect Ratio,Original,Wide;",
	//"H2H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O6,Audio,Mono,Stereo;",
	"OD,Video Mode,Interlaced,Progressive;",
	"-;",
	"h1O7,Rotate,Buttons,Spinner;",
	"h1-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Fire A,Fire B,Fire C,Fire D,Rotate CW,Rotate CCW,Start1+Coin,Start2+Coin;",
	"jn,A,B,X,Y,R,L,Start,Select;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys,clk_80M;
wire clk_mem = clk_80M;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys), // 40M
	.outclk_1(clk_80M), // 80M
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_index;

wire [10:0] ps2_key;

wire [15:0] joy1, joy2;
wire [15:0] joy = joy1 | joy2;

wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.status_menumask({landscape,mod_dotron,direct_video}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joy1),
	.joystick_1(joy2),

	.ps2_key(ps2_key)
);

wire rom_download = ioctl_download && !ioctl_index;

wire [15:0] rom_addr;
wire [15:0] rom_do;
wire [13:0] snd_addr;
wire [15:0] snd_do;
wire [14:0] sp_addr;
wire [31:0] sp_do;

// ROM structure:
// 00000 - 0DFFF  - Main ROM (8 bit)
// 0E000 - 11FFF - Super Sound board ROM (8 bit)
// 12000 - 31FFF - Sprite ROMs (32 bit)
// 32000 - 39FFF - BG ROMS

//wire [24:0] rom_ioctl_addr = ~ioctl_addr[16] ? ioctl_addr : // 8 bit ROMs
//                             {ioctl_addr[24:16], ioctl_addr[15], ioctl_addr[13:0], ioctl_addr[14]}; // 16 bit ROM

wire [24:0] sp_ioctl_addr = ioctl_addr - 17'h12000; //SP ROM offset: 0x12000
wire [24:0] dl_addr = ioctl_addr - 18'h32000; //background offset

reg port1_req, port2_req;
sdram sdram
(
	.*,
	.init_n        ( pll_locked   ),
	.clk           ( clk_mem      ),

	// port1 used for main + sound CPUs
	.port1_req     ( port1_req    ),
	.port1_ack     ( ),
	.port1_a       ( ioctl_addr[23:1] ),
	.port1_ds      ( {ioctl_addr[0], ~ioctl_addr[0]} ),
	.port1_we      ( rom_download ),
	.port1_d       ( {ioctl_dout, ioctl_dout} ),
	.port1_q       ( ),

	.cpu1_addr     ( rom_download ? 16'hffff : {1'b0, rom_addr[15:1]} ),
	.cpu1_q        ( rom_do ),
	.cpu2_addr     ( rom_download ? 16'hffff : (16'h7000 + snd_addr[13:1]) ),
	.cpu2_q        ( snd_do ),
	
	// port2 for sprite graphics
	.port2_req     ( port2_req ),
	.port2_ack     ( ),
	.port2_a       ( {sp_ioctl_addr[18:17], sp_ioctl_addr[14:0], sp_ioctl_addr[16]} ), // merge sprite roms to 32-bit wide words
	.port2_ds      ( {sp_ioctl_addr[15], ~sp_ioctl_addr[15]} ),
	.port2_we      ( rom_download ),
	.port2_d       ( {ioctl_dout, ioctl_dout} ),
	.port2_q       ( ),

	.sp_addr       ( rom_download ? 15'h7fff : sp_addr ),
	.sp_q          ( sp_do )
);

// ROM download controller
always @(posedge clk_sys) begin
	reg        ioctl_wr_last = 0;

	ioctl_wr_last <= ioctl_wr && !ioctl_index;
	if (rom_download) begin
		if (~ioctl_wr_last && (ioctl_wr && !ioctl_index)) begin
			port1_req <= ~port1_req;
			port2_req <= ~port2_req;
		end
	end
end

// reset signal generation
reg reset;
always @(posedge clk_sys) reset <= RESET | status[0] | buttons[1];

wire       pressed = ps2_key[9];
wire [7:0] code    = ps2_key[7:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'h75: btn_up            <= pressed; // up
			'h72: btn_down          <= pressed; // down
			'h6B: btn_left          <= pressed; // left
			'h74: btn_right         <= pressed; // right
			'h76: btn_coin1         <= pressed; // ESC
			'h05: btn_start1        <= pressed; // F1
			'h06: btn_start2        <= pressed; // F2
			//'h04: btn_start3        <= pressed; // F3
			//'h0C: btn_start4        <= pressed; // F4
			'h12: btn_fireD         <= pressed; // l-shift
			'h14: btn_fireC         <= pressed; // ctrl
			'h11: btn_fireB         <= pressed; // alt
			'h29: btn_fireA         <= pressed; // Space
			// JPAC/IPAC/MAME Style Codes
			'h16: btn_start1        <= pressed; // 1
			'h1E: btn_start2        <= pressed; // 2
			//'h26: btn_start3        <= pressed; // 3
			//'h25: btn_start4        <= pressed; // 4
			'h2E: btn_coin1         <= pressed; // 5
			'h36: btn_coin2         <= pressed; // 6
			//'h3D: btn_coin3         <= pressed; // 7
			//'h3E: btn_coin4         <= pressed; // 8
			'h2D: btn_up2           <= pressed; // R
			'h2B: btn_down2         <= pressed; // F
			'h23: btn_left2         <= pressed; // D
			'h34: btn_right2        <= pressed; // G
			'h1C: btn_fire2A        <= pressed; // A
			'h1B: btn_fire2B        <= pressed; // S
			'h21: btn_fire2C        <= pressed; // Q
			'h1D: btn_fire2D        <= pressed; // W
			//'h1D: btn_fire2E        <= pressed; // W
			//'h1D: btn_fire2F        <= pressed; // W
			//'h1D: btn_tilt <= pressed; // W
		endcase
	end
end

reg btn_left   = 0;
reg btn_right  = 0;
reg btn_down   = 0;
reg btn_up     = 0;
reg btn_fireA  = 0;
reg btn_fireB  = 0;
reg btn_fireC  = 0;
reg btn_fireD  = 0;
reg btn_coin1  = 0;
reg btn_coin2  = 0;
reg btn_start1 = 0;
reg btn_start2 = 0;
reg btn_up2    = 0;
reg btn_down2  = 0;
reg btn_left2  = 0;
reg btn_right2 = 0;
reg btn_fire2A = 0;
reg btn_fire2B = 0;
reg btn_fire2C = 0;
reg btn_fire2D = 0;

wire service = sw[1][0];

// Generic controls - make a module from this?

wire m_start1  = btn_start1 | joy[10];
wire m_start2  = btn_start2 | joy[11];
wire m_coin1   = btn_coin1  | btn_coin2 | joy[10] | joy[11];

wire m_right1  = btn_right  | joy1[0];
wire m_left1   = btn_left   | joy1[1];
wire m_down1   = btn_down   | joy1[2];
wire m_up1     = btn_up     | joy1[3];
wire m_fire1a  = btn_fireA  | joy1[4];
wire m_fire1b  = btn_fireB  | joy1[5];
wire m_fire1c  = btn_fireC  | joy1[6];
wire m_fire1d  = btn_fireD  | joy1[7];
wire m_rcw1    =              joy1[8];
wire m_rccw1   =              joy1[9];

wire m_right2  = btn_right2 | joy2[0];
wire m_left2   = btn_left2  | joy2[1];
wire m_down2   = btn_down2  | joy2[2];
wire m_up2     = btn_up2    | joy2[3];
wire m_fire2a  = btn_fire2A | joy2[4];
wire m_fire2b  = btn_fire2B | joy2[5];
wire m_fire2c  = btn_fire2C | joy2[6];
wire m_fire2d  = btn_fire2D | joy2[7];
wire m_rcw2    =              joy1[8];
wire m_rccw2   =              joy1[9];

wire m_right   = m_right1 | m_right2;
wire m_left    = m_left1  | m_left2; 
wire m_down    = m_down1  | m_down2; 
wire m_up      = m_up1    | m_up2;   
wire m_fire_a  = m_fire1a | m_fire2a;
wire m_fire_b  = m_fire1b | m_fire2b;
wire m_fire_c  = m_fire1c | m_fire2c;
wire m_fire_d  = m_fire1d | m_fire2d;
wire m_rcw     = m_rcw1   | m_rcw2;
wire m_rccw    = m_rccw1  | m_rccw2;

reg  [7:0] input_0;
reg  [7:0] input_1;
reg  [7:0] input_2;
reg  [7:0] input_3;
reg  [7:0] input_4;

reg mod_tapper = 0;
reg mod_timber = 0;
reg mod_dotron = 0;
reg mod_journey= 0;
always @(posedge clk_sys) begin
	reg [7:0] mod = 0;
	if (ioctl_wr & (ioctl_index==1)) mod <= ioctl_dout;

	mod_tapper <= ( mod == 0 );
	mod_timber <= ( mod == 1 );
	mod_dotron <= ( mod == 2 );
	mod_journey<= ( mod == 3 );
end

// load the DIPS
reg [7:0] sw[8];
always @(posedge clk_sys) if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;

reg landscape;

// Game specific sound board/DIP/input settings
always @(*) begin

	landscape = 1; 
	input_0 = 8'hff;
	input_1 = 8'hff;
	input_2 = 8'hff;
	input_3 = sw[0];
	input_4 = 8'hff;

	if (mod_tapper) begin
		input_0 = ~{ service, 3'b000, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ 3'b000, m_fire_a, m_up, m_down, m_left, m_right };
		input_2 = ~{ 3'b000, m_fire_a, m_up, m_down, m_left, m_right };
	end
	else if (mod_timber) begin
		input_0 = ~{ service, 3'b000, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ 2'b00, m_fire1a, m_fire1b, m_up1, m_down1, m_left1, m_right1 };
		input_2 = ~{ 2'b00, m_fire2a, m_fire2b, m_up2, m_down2, m_left2, m_right2 };
	end
	else if (mod_dotron) begin
		input_0 = ~{ service, 2'b00, m_fire_a, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ 1'b0, spin_tron[7:1] };
		input_2 = ~{ 1'b0, m_fire_b, m_fire_c, m_fire_d, m_down, m_up, m_right, m_left };
	end
	else if (mod_journey) begin
		landscape = 0;
		input_0 = ~{ service, 2'b00, m_fire_a, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ 4'b0000, m_down, m_up, m_right, m_left };
		input_2 = ~{ 3'b000, m_fire_a, m_down, m_up, m_right, m_left };
	end
end

wire [7:0] spin_tron;
spinner spinner_tr (
	.clock_40(clk_sys),
	.reset(reset),
	.btn_acc(0),
	.btn_left(m_rccw),
	.btn_right(m_rcw),
	.ctc_zc_to_2(vs),
	.use_spinner(status[7]),
	.spin_angle(spin_tron)
);

wire ce_pix;
wire hblank, vblank;
wire hs, vs;
wire [2:0] r,g;
wire [2:0] b;

wire no_rotate = status[2] | direct_video | landscape;
 
arcade_video #(512,480,9) arcade_video
(
	.*,
	.clk_video(clk_sys),
	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),
	.no_rotate(1),
	.rotate_ccw(0),
	.fx(status[5:3])
);

assign AUDIO_S = 0;
wire [15:0] audio_l, audio_r;

assign AUDIO_L = audio_l;
assign AUDIO_R = audio_r;

Tapper Tapper
(
	.clock_40(clk_sys),
	.reset(reset),
	.video_r(r),
	.video_g(g),
	.video_b(b),
	.video_vblank(vblank),
	.video_hblank(hblank),
	.video_hs(hs),
	.video_vs(vs),
	.video_ce(ce_pix),
	.video_hflip(mod_dotron),
	.tv15Khz_mode(~status[13]),
	.separate_audio(status[6]),
	.audio_out_l(audio_l),
	.audio_out_r(audio_r),
	.input_0      ( input_0),
	.input_1      ( input_1),
	.input_2      ( input_2),
	.input_3      ( input_3),
	.input_4      ( input_4),	
	.mcr2p5       ( mod_journey ),
	.cpu_rom_addr ( rom_addr ),
	.cpu_rom_do   ( rom_addr[0] ? rom_do[15:8] : rom_do[7:0] ),
	.snd_rom_addr ( snd_addr ),
	.snd_rom_do   ( snd_addr[0] ? snd_do[15:8] : snd_do[7:0] ),
	.sp_addr      ( sp_addr ),
	.sp_graphx32_do ( sp_do ),
	.dl_addr      ( dl_addr    ),
	.dl_wr        ( ioctl_wr & !ioctl_index),
	.dl_data      ( ioctl_dout )
);

endmodule
