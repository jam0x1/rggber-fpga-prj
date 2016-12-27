`timescale 1ps/1ps
/*
模块完成16bit的YC数据的64bit的数据对齐，然后写入FIFO，
有帧写入状态机完成64bit数据写入ddr2
*/
module vin_frame_buffer_ctrl_ch2
 #(
	parameter MEM_DATA_BITS = 64
) 
(
	input rst_n,                                    /*复位 */
	input vin_clk,                                  /*视频输入时钟 */
	input vin_vs,                                   /*视频输入场同步 */
	input vin_de,                                   /*视频输入数据有效 */
	input[15:0] vin_data,                           /*视频输入数据YC */
	input[11:0] vin_width,                          /*视频输入宽度*/
	input[11:0] vin_height,                         /*视频输入高度*/
	
	input mem_clk,                                  /*存储器接口：时钟*/
	output reg wr_burst_req,                        /*存储器接口：写请求*/
	output reg[9:0] wr_burst_len,                   /*存储器接口：写长度*/
	output reg[23:0] wr_burst_addr,                 /*存储器接口：写首地址 */
	input wr_burst_data_req,                        /*存储器接口：写数据数据读指示 */
	output[MEM_DATA_BITS - 1:0] wr_burst_data,      /*存储器接口：写数据*/
	input burst_finish,                             /*存储器接口：本次写完成 */
	
	//
	input[7:0]	base_ch2_hsync,
	input[15:0]	base_ch2_vsync,
	input[15:0]	width_ch2
);                                                   
localparam BURST_LEN = 10'd128;                /*一次写操作数据长度 */
localparam BURST_IDLE = 3'd0;                 /*状态机状态：空闲 */
localparam BURST_ONE_LINE_START = 3'd1;       /*状态机状态：视频数据一行写开始 */
localparam BURSTING = 3'd2;                   /*状态机状态：正在处理一次ddr2写操作 */
localparam BURST_END = 3'd3;                  /*状态机状态：一次ddr2写操作完成*/
localparam BURST_ONE_LINE_END = 3'd4;         /*状态机状态：视频数据一行写完成*/
reg[2:0] burst_state = 3'd0;                  /*状态机状态：当前状态 */
reg[2:0] burst_state_next = 3'd0;             /*状态机状态：下一个状态*/
reg[11:0] burst_line = 12'd0;/*已经写入ddr2的行计数*/
reg[11:0] remain_len = 12'd0;/*当前视频一行数据的剩余数据个数*/
reg vin_vs_mem_clk_d0 = 1'b0;
reg vin_vs_mem_clk_d1 = 1'b0;
reg frame_flag = 1'b0;
wire[11:0] rdusedw;

//
reg[7:0]	r_base_ch2_hsync_d0;
reg[7:0]	r_base_ch2_hsync_d1;
reg[15:0]	r_base_ch2_vsync_d0;
reg[15:0]	r_base_ch2_vsync_d1;
reg[15:0]	r_width_ch2_d0;
reg[15:0]	r_width_ch2_d1;

always@(posedge mem_clk)
begin
	r_base_ch2_hsync_d0 <= base_ch2_hsync;
	r_base_ch2_hsync_d1 <= r_base_ch2_hsync_d0;
	r_base_ch2_vsync_d0 <= base_ch2_vsync;
	r_base_ch2_vsync_d1 <= r_base_ch2_vsync_d0;
	r_width_ch2_d0 <= width_ch2;
	r_width_ch2_d1 <= r_width_ch2_d0;
end

fifo_4096_16d_64q fifo_4096_16d_64q_m0(
	.aclr(frame_flag),
	.data(vin_data),					//RGB565
	.rdclk(mem_clk),
	.rdreq(wr_burst_data_req),
	.wrclk(vin_clk),
	.wrreq(vin_de),
	.q(wr_burst_data),
	.rdempty(),
	.rdusedw(rdusedw),
	.wrfull(),
	.wrusedw());
/*突发写首地址的产生*/
always@(posedge mem_clk or negedge rst_n)
begin
	if(!rst_n)
		wr_burst_addr <= 24'd0;
	else if(burst_state_next == BURST_ONE_LINE_START)
		wr_burst_addr <= {2'd0,burst_line[10:0],3'd0,r_base_ch2_hsync_d1};//24bit ddr addr
	else if(burst_state_next == BURST_END  && burst_state != BURST_END)
		wr_burst_addr <= wr_burst_addr + BURST_LEN[7:0];
	else
		wr_burst_addr <= wr_burst_addr;
end

always@(posedge mem_clk)
begin
	vin_vs_mem_clk_d0 <= vin_vs;
	vin_vs_mem_clk_d1 <= vin_vs_mem_clk_d0;
	frame_flag <= vin_vs_mem_clk_d0 && ~vin_vs_mem_clk_d1;
end
/*每一帧都将状态机强行进入BURST_IDLE状态*/
always@(posedge mem_clk or negedge rst_n)
begin
	if(!rst_n)
		burst_state <= BURST_IDLE;
	else if(frame_flag)
		burst_state <= BURST_IDLE;
	else
		burst_state <= burst_state_next;
end
always@(*)
begin
	case(burst_state)
		BURST_IDLE:/*如果FIFO有足够的数据则完成一行第一次写操作*/
			if(rdusedw > BURST_LEN[7:0])
				burst_state_next <= BURST_ONE_LINE_START;
			else
				burst_state_next <= BURST_IDLE;
		BURST_ONE_LINE_START:/*一行的写操作开始*/
			burst_state_next <= BURSTING;
		BURSTING:/*写操作*/
			if(burst_finish)
				burst_state_next <= BURST_END;
			else
				burst_state_next <= BURSTING;
		BURST_END:/*写操作完成时判断一行数据是否已经完全写入ddr2，如果完成则进入空闲状态，等待第二行数据*/
			if(remain_len == 12'd0)
				burst_state_next <= BURST_ONE_LINE_END;
			else if(rdusedw >= BURST_LEN[7:0])// || (remain_len <= BURST_LEN && rdusedw == remain_len - 10'd1))//һ��ͻ������,��һ������һ��ͻ��
				burst_state_next <= BURSTING;
			else
				burst_state_next <= BURST_END;
		BURST_ONE_LINE_END:
			burst_state_next <= BURST_IDLE;
		default:
			burst_state_next <= BURST_IDLE;
	endcase
end

/*burst_line产生*/
always@(posedge mem_clk or negedge rst_n)
begin
	if(!rst_n)
		burst_line <= 12'd0;
	else if(frame_flag)
		burst_line <= r_base_ch2_vsync_d1[11:0];
	else if(burst_state == BURST_ONE_LINE_END)//每次一行写完burst_line加1
		burst_line <= burst_line + 12'd1;
	else
		burst_line <= burst_line;
end

/*remain_len产生，每一行写开始时等于byte_per_line，如果一行数据小于一次写的最大长度，
一次写完，则remain_len = 0，否则减去最大写长度*/
always@(posedge mem_clk or negedge rst_n)
begin
	if(!rst_n)
		remain_len <= 12'd0;
	else if(burst_state_next == BURST_ONE_LINE_START)
		remain_len <= r_width_ch2_d1[11:0];
	else if(burst_state_next == BURST_END && burst_state != BURST_END)
		if(remain_len < BURST_LEN)
			remain_len <= 12'd0;
		else
			remain_len <= remain_len - BURST_LEN;	
	else
		remain_len <= remain_len;
end
/*突发长度产生，如果一行的剩余数据大于最大写长度，则突发长度是BURST_LEN，否则就等于剩余数据长度*/
always@(posedge mem_clk or negedge rst_n)
begin
	if(!rst_n)
		wr_burst_len <= 10'd0;
	else if(burst_state_next == BURSTING && burst_state != BURSTING)
		if(remain_len > BURST_LEN)
			wr_burst_len <= BURST_LEN;
		else
			wr_burst_len <= remain_len;
	else
		wr_burst_len <=  wr_burst_len;
end
/*ddr2写请求信号的产生于撤销*/
always@(posedge mem_clk or negedge rst_n)
begin
	if(!rst_n)
		wr_burst_req <= 1'd0;
	else if(burst_state_next == BURSTING && burst_state != BURSTING)
		wr_burst_req <= 1'b1;
	else if(burst_finish  || wr_burst_data_req || burst_state == BURST_IDLE)
		wr_burst_req <= 1'b0;
	else
		wr_burst_req <= wr_burst_req;
end

endmodule 