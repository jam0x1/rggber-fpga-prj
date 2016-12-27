//---------------------------------------------------------------------------------------

module top(
		
		//
		CLK_50M, nRESET, 
		//
		LED_YG, LED_BLUE, LED_YELLOW, LED_RED, 
		//
		FPGA_K0, FPGA_K1,
		//
		FPGA_TX1, FPGA_RX1, FPGA_2102RST,
		//
		TX_D, TX_IDCK, TX_DE, TX_HSYNC, TX_VSYNC, TX_PO1, TX_RST,
		TXCEC, TXHPD,
		//
		RX_D, RX_OCK_INV, RX_SCDT, RX_CTL, RX_DE, RX_VSYNC, RX_HSYNC,
		RX_ODCK, DDC_RX_SDA, DDC_RX_SCL, RXHPD, RXCEC,
		//
		EN_CIS1V5, EN_CISA3V0, EN_CIS2V8, CIS_RST,
		CIS_VSYNC, CIS_PWDN, CIS_HREF, CIS_STROBE, CIS_XCLK, CIS_PCLK,
		CIS_Y,
		//
		mem_cs_n, mem_cke, mem_addr, mem_ba, mem_ras_n, mem_cas_n, mem_we_n,
		mem_clk, mem_clk_n, mem_dm, mem_dq, mem_dqs, mem_odt,
		//
		MCU_SDA0_3V3, MCU_SCL0_3V3, MCU_INT0, MCU_INT1, MCU_SCK, MCU_MISO, 
		MCU_MOSI, MCU_NSS, 
		//
		SD_DAT, SD_CMD, SD_CLK, SD_DET,
		//
		iXHis_LVDS, iXHis_SE0, iXHis_RX_CLK

        );
		
//---------------------------------------------------------------------------------------

// 
input				CLK_50M;
input				nRESET;

//
output				LED_YG;
output				LED_YELLOW;
output				LED_BLUE;
output				LED_RED;

//
input				FPGA_K0;
input				FPGA_K1;

//
output				FPGA_TX1;
input				FPGA_RX1;
output				FPGA_2102RST;

//
output	[23:0]		TX_D;
output				TX_IDCK;
output				TX_DE;
output				TX_HSYNC;
output				TX_VSYNC;
input				TX_PO1;
output				TX_RST;
output				TXCEC;
input				TXHPD;

//
input	[23:0]		RX_D;
output				RX_OCK_INV;
input				RX_SCDT;
input	[2:0]		RX_CTL;
input				RX_DE;
input				RX_VSYNC;
input				RX_HSYNC;
input				RX_ODCK;
output				DDC_RX_SCL;
inout				DDC_RX_SDA;
output				RXHPD;
input				RXCEC;

//
output				EN_CIS1V5;
output				EN_CISA3V0;
output				EN_CIS2V8;
output				CIS_RST;
input				CIS_VSYNC;
output				CIS_PWDN;
input				CIS_HREF;
input				CIS_STROBE;
output				CIS_XCLK;
input				CIS_PCLK;
input	[7:0]       CIS_Y;

//
output  	  		mem_cs_n;
output  	  		mem_cke;
output  [12:0]  	mem_addr;
output  [2:0]  		mem_ba;
output  			mem_ras_n;
output  			mem_cas_n;
output  			mem_we_n; 
inout  				mem_clk;
inout  				mem_clk_n;
output  [3:0]  		mem_dm;
inout  	[31:0]  	mem_dq; 
inout  	[3:0]  		mem_dqs; 
output				mem_odt;

//
inout 				MCU_SDA0_3V3;
input				MCU_SCL0_3V3;
output				MCU_INT0;
output 				MCU_INT1; 
input				MCU_SCK;
output				MCU_MISO;
input				MCU_MOSI; 
input				MCU_NSS;

//
inout	[3:0]    	SD_DAT; 
output				SD_CMD; 
output				SD_CLK; 
input				SD_DET;

//
output				iXHis_SE0;
input	[14:0]	    iXHis_LVDS;
input	            iXHis_RX_CLK;			

//---------------------------------------------------------------------------------------

//
wire 								phy_clk;
wire	[23:0]						local_address;
wire 								local_write_req;
wire 								local_read_req;
wire	[MEM_DATA_BITS - 1:0]		local_wdata;
wire	[MEM_DATA_BITS/8 - 1:0]		local_be;
wire	[2:0]						local_size;
wire 								local_ready;
wire	[MEM_DATA_BITS - 1:0]		local_rdata;
wire 								local_rdata_valid;
wire 								local_wdata_req;
wire 								local_init_done;
wire 								wr_burst_finish;
wire 								rd_burst_finish;
wire	[23:0] 						wr_burst_addr;
wire	[23:0] 						rd_burst_addr;
wire 								wr_burst_data_req;
wire 								rd_burst_data_valid;
wire	[9:0] 						wr_burst_len;
wire	[9:0] 						rd_burst_len;
wire 								wr_burst_req;
wire 								rd_burst_req;
wire	[MEM_DATA_BITS - 1:0] 		wr_burst_data;
wire	[MEM_DATA_BITS - 1:0] 		rd_burst_data;
wire 								local_burstbegin;
wire 								rst_n;

//
wire 								vga_out_hs_tmp0;
reg 								vga_out_hs_tmp1;
reg 								vga_out_hs_tmp2;
wire 								vga_out_vs_tmp0;
reg 								vga_out_vs_tmp1;
reg 								vga_out_vs_tmp2;
wire 								vga_out_de_tmp0;
reg 								vga_out_de_tmp1;
reg 								vga_out_de_tmp2;
wire	[7:0] 						fifo_q;
reg		[7:0] 						fifo_q_d0;

//
wire 								s_cis_i2c_standby;	

//---------------------------------------------------------------------------------------

parameter MEM_DATA_BITS = 64;

//---------------------------------------------------------------------------------------

assign 				FPGA_2102RST = 1'b1;
assign 				TX_RST = 1'b1;
assign				RX_OCK_INV = 1'b1;

assign				DDC_RX_SCL = 1'bz;
assign				DDC_RX_SDA = 1'bz;

assign				MCU_INT0 = ~s_cis_i2c_standby;

//---------------------------------------------------------------------------------------

reset reset_m0(

			.clk(CLK_50M),
			.rst_n(rst_n)

);

tfp410_pll	tfp410_pll_u0(
				
			.inclk0(CLK_50M),
			.c0(TX_IDCK)
	
);

pll_ov5640	pll_ov5640_u0(
				
			.inclk0(CLK_50M),
			.c0(CIS_XCLK)
				
);

demosaic demosaic_u0(

				.clock(TX_IDCK), 
				.reset_n(rst_n),
				.vs_i(vga_out_vs_tmp2), 
				.hs_i(vga_out_hs_tmp2), 
				.de_i(vga_out_de_tmp2),
				.bayer(fifo_q_d0),
				.vs_o(TX_VSYNC), 
				.hs_o(TX_HSYNC), 
				.de_o(TX_DE),
				.rgb_r_o(TX_D[23:16]), 
				.rgb_g_o(TX_D[15:8]), 
				.rgb_b_o(TX_D[7:0])

);

color_bar vga_color_bar(
			
			.clk(TX_IDCK),
			.rst(~rst_n),
			.hs(vga_out_hs_tmp0),
			.vs(vga_out_vs_tmp0),
			.de(vga_out_de_tmp0)		
			
);

always@(posedge TX_IDCK)
	begin	
		vga_out_hs_tmp1 <= vga_out_hs_tmp0;
		vga_out_vs_tmp1 <= vga_out_vs_tmp0;
		vga_out_de_tmp1 <= vga_out_de_tmp0;
		vga_out_hs_tmp2 <= vga_out_hs_tmp1;
		vga_out_vs_tmp2 <= vga_out_vs_tmp1;
		vga_out_de_tmp2 <= vga_out_de_tmp1;	
		fifo_q_d0 <= fifo_q;
	end
	
power_up power_up_u0(
		
				.clock(CLK_50M), 
				.reset_n(nRESET),
				.en_cis1v5(EN_CIS1V5), 
				.en_cisa3v0(EN_CISA3V0),
				.en_cis2v8(EN_CIS2V8), 
				.cis_pwdn(CIS_PWDN), 
				.cis_rst(CIS_RST),
		        .cis_i2c_standby(s_cis_i2c_standby)

);


vin_frame_buffer_ctrl vin_frame_buffer_ctrl_m0(

			.rst_n(rst_n),
			.vin_clk(CIS_PCLK),
			.vin_vs(CIS_VSYNC),
			.vin_de(CIS_HREF),
			.vin_data(CIS_Y),
			.vin_width(12'd480),
			.vin_height(),
			.mem_clk(phy_clk),
			.wr_burst_req(wr_burst_req),
			.wr_burst_len(wr_burst_len),
			.wr_burst_addr(wr_burst_addr),
			.wr_burst_data_req(wr_burst_data_req),
			.wr_burst_data(wr_burst_data),
			.burst_finish(wr_burst_finish),
			
);

vout_frame_buffer_ctrl vout_frame_buffer_ctrl_m0(

			.rst_n(rst_n),
			.vout_clk(TX_IDCK),
			.vout_vs(vga_out_vs_tmp0),
			.vout_rd_req(vga_out_de_tmp0),
			.vout_data(fifo_q),
			.vout_width(12'd480),
			.vout_height(),
			.mem_clk(phy_clk),
	
			.rd_burst_req(rd_burst_req),
			.rd_burst_len(rd_burst_len),
			.rd_burst_addr(rd_burst_addr),
			.rd_burst_data_valid(rd_burst_data_valid),
			.rd_burst_data(rd_burst_data),
			.burst_finish(rd_burst_finish)
			
);

ddr2 ddr_m0(

			.local_address(local_address),
			.local_write_req(local_write_req),
			.local_read_req(local_read_req),
			.local_wdata(local_wdata),
			.local_be(local_be),
			.local_size(local_size),
			.global_reset_n(rst_n),
	
			.pll_ref_clk(CLK_50M),
			.soft_reset_n(1'b1),
			.local_ready(local_ready),
			.local_rdata(local_rdata),
			.local_rdata_valid(local_rdata_valid),
			.reset_request_n(),
			.mem_cs_n(mem_cs_n),
			.mem_cke(mem_cke),
			.mem_addr(mem_addr),
			.mem_ba(mem_ba),
			.mem_ras_n(mem_ras_n),
			.mem_cas_n(mem_cas_n),
			.mem_we_n(mem_we_n),
			.mem_dm(mem_dm),

			.local_burstbegin(local_burstbegin),
			.local_init_done(local_init_done),
			.reset_phy_clk_n(),
			.phy_clk(phy_clk),
			.aux_full_rate_clk(),
			.aux_half_rate_clk(),
			.mem_clk(mem_clk),
			.mem_clk_n(mem_clk_n),
			.mem_dq(mem_dq),
			.mem_dqs(mem_dqs),
			.mem_odt(mem_odt)
			
);

mem_burst_v2 mem_burst_m0(

			.rst_n(rst_n),
			.mem_clk(phy_clk),
			.rd_burst_req(rd_burst_req),
			.wr_burst_req(wr_burst_req),
			.rd_burst_len(rd_burst_len),
			.wr_burst_len(wr_burst_len),
			.rd_burst_addr(rd_burst_addr),
			.wr_burst_addr(wr_burst_addr),
			.rd_burst_data_valid(rd_burst_data_valid),
			.wr_burst_data_req(wr_burst_data_req),
			.rd_burst_data(rd_burst_data),
			.wr_burst_data(wr_burst_data),
			.rd_burst_finish(rd_burst_finish),
			.wr_burst_finish(wr_burst_finish),
	
			.local_init_done(local_init_done),
			.local_ready(local_ready),
			.local_burstbegin(local_burstbegin),
			.local_wdata(local_wdata),
			.local_rdata_valid(local_rdata_valid),
			.local_rdata(local_rdata),
			.local_write_req(local_write_req),
			.local_read_req(local_read_req),
			.local_address(local_address),
			.local_be(local_be),
			.local_size(local_size)
	
);

//---------------------------------------------------------------------------------------

endmodule