module vout_frame_buffer_ctrl#(
	parameter MEM_DATA_BITS = 64
)(
	input rst_n,                                   ///*复位*/
	input vout_clk,                                ///*视频时钟*/
	input vout_vs,                                 ///*视频输出场同步*/
	input vout_rd_req,                             ///*视频输出数据读取请求*/
	output[15:0] vout_data,                        ///*视频输出读取的数据*/
	input[11:0] vout_width,                        ///*视频输出的宽度，指的是存在存储器内的视频宽度*/
	input[11:0] vout_height,                       ///*视频输出的高度*/
                                                   
	input mem_clk,                                 ///*存储器接口时钟*/
	output reg rd_burst_req,                       ///*存储器接口读取请求*/
	output reg[9:0] rd_burst_len,                  ///*存储器接口读取长度*/
	output reg[23:0] rd_burst_addr,                ///*存储器接口读取首地址*/
	input rd_burst_data_valid,                     ///*存储器接口返回读取数据有效*/
	input[MEM_DATA_BITS - 1:0] rd_burst_data,      ///*存储器接口返回的读取数据*/
	input burst_finish                             ///*本次读取完成*/
);                                                 
localparam BURST_LEN = 10'd32;                    ///*定义突发读取的长度，如果数据达不到这个长度则按数据实际长度读取 */
localparam BURST_IDLE = 3'd0;                      ///*读取控制状态机：空闲状态*/
localparam BURST_ONE_LINE_START = 3'd1;            ///*读取控制状态机：开始读取一行视频 */
localparam BURSTING = 3'd2;                        ///*读取控制状态机：正在完成一次突发读取 */
localparam BURST_END = 3'd3;                       ///*读取控制状态机：一次突发读取操作完成 */
localparam BURST_ONE_LINE_END = 3'd4;              ///*读取控制状态机：一行视频数据读取完成*/
reg[2:0] burst_state = 3'd0;                       ///*读取控制状态机：当前状态 */
reg[2:0] burst_state_next = 3'd0;                  ///*读取控制状态机：下一个状态 */
reg[11:0] burst_line = 12'd0;                      ///*本轮（每场一轮）已经读取的总行数 */
reg frame_flag;
reg vout_vs_mem_clk_d0;
reg vout_vs_mem_clk_d1;
reg[10:0] remain_len;
wire[11:0] wrusedw;
fifo_1024_64d_16q fifo_1024_64d_16q_m0(
	.aclr(frame_flag),
	.data(rd_burst_data),
	.rdclk(vout_clk),
	.rdreq(vout_rd_req),
	.wrclk(mem_clk),
	.wrreq(rd_burst_data_valid),
	.q(vout_data),
	.rdempty(),
	.rdusedw(),
	.wrfull(),
	.wrusedw(wrusedw));
	
///*ddr2读取首地址计算，需要注意的是视频并不是连续读取的，而是按照“行”为单元存取*/
always@(posedge mem_clk or negedge rst_n)
begin
	if(!rst_n)
		rd_burst_addr <= 24'd0;
	else if(burst_state_next == BURST_ONE_LINE_START)
		rd_burst_addr <= {2'd0,burst_line[10:0],11'd0};//24bit ddr addr
	else if(burst_state_next == BURST_END && burst_state != BURST_END)
		rd_burst_addr <= rd_burst_addr + {15'd0,BURST_LEN[8:0]};
	else
		rd_burst_addr <= rd_burst_addr;
end	

/////////////////////////////////////////////////////

always@(posedge mem_clk)
begin
	vout_vs_mem_clk_d0 <= vout_vs;
	vout_vs_mem_clk_d1 <= vout_vs_mem_clk_d0;
	frame_flag <= vout_vs_mem_clk_d0 && ~vout_vs_mem_clk_d1;
end

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
		BURST_IDLE:  ///*如果fifo空间够写入一次突然地数据，就完成一行数据的第一次突发*/
			if(wrusedw < 512 - BURST_LEN[7:0])/*判断fifo空间*/
				burst_state_next <= BURST_ONE_LINE_START;
			else
				burst_state_next <= BURST_IDLE;
		BURST_ONE_LINE_START:
			burst_state_next <= BURSTING;
		BURSTING:  ///*完成一次突发读操作*/
			if(burst_finish)
				burst_state_next <= BURST_END;
			else
				burst_state_next <= BURSTING;
		BURST_END:
			if(remain_len == 11'd0)/*判断一行数据是否读完，没有读完则等待fifo以完成下次读*/
				burst_state_next <= BURST_ONE_LINE_END;
			else if(wrusedw < 512 - BURST_LEN[7:0])/*判断fifo空间*/
				burst_state_next <= BURSTING;
			else
				burst_state_next <= BURST_END;
		BURST_ONE_LINE_END:/*完成一行数据的读取*/
				burst_state_next <= BURST_IDLE;
		default:
			burst_state_next <= BURST_IDLE;
	endcase
end

always@(posedge mem_clk or negedge rst_n)
begin
	if(!rst_n)
		burst_line <= 12'd0;
	else if(frame_flag)
		burst_line <= 12'd0;
	else if(burst_state_next == BURST_ONE_LINE_END && burst_state == BURST_END)
		burst_line <= burst_line + 12'd1;/*每次完成一行数据的读取burst_line加1*/
	else
		burst_line <= burst_line;
end


/*计算每行剩余数据*/
always@(posedge mem_clk or negedge rst_n)
begin
	if(!rst_n)
		remain_len <= 11'd0;
	else if(burst_state_next == BURST_ONE_LINE_START)
		remain_len <= vout_width[10:0];
	else if(burst_state_next == BURST_END && burst_state != BURST_END)
		if(remain_len < BURST_LEN)
			remain_len <= 11'd0;
		else
			remain_len <= remain_len - BURST_LEN;	
	else
		remain_len <= remain_len;
end

/*计算突发读取的长度*/
always@(posedge mem_clk or negedge rst_n)
begin
	if(!rst_n)
		rd_burst_len <= 10'd0;
	else if(burst_state_next == BURSTING && burst_state != BURSTING)
		if(remain_len > BURST_LEN)
			rd_burst_len <= BURST_LEN;
		else
			rd_burst_len <= remain_len;
	else
		rd_burst_len <=  rd_burst_len;
end

/*读请求信号的发出与撤销*/
always@(posedge mem_clk or negedge rst_n)
begin
	if(!rst_n)
		rd_burst_req <= 1'd0;
	else if(burst_state_next == BURSTING && burst_state != BURSTING)
		rd_burst_req <= 1'b1;
	else if(burst_finish || burst_state == BURST_IDLE || rd_burst_data_valid)
		rd_burst_req <= 1'b0;
	else
		rd_burst_req <= rd_burst_req; 
end

endmodule 