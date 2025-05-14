module sccb_controller #(
    parameter C_SCCB_FREQ_KHZ = 100,       // SCCB时钟频率，默认100KHz
    parameter C_CLK_FREQ_MHZ = 100         // 系统时钟频率，默认100MHz
) (
    input  wire        clk,                // 系统时钟
    input  wire        rst_n,              // 异步复位，低电平有效
    
    // 寄存器接口
    input  wire [31:0] ctrl_reg,           // 控制寄存器
    output reg  [31:0] status_reg,         // 状态寄存器
    input  wire [31:0] tx_data,            // 发送数据
    output reg  [31:0] rx_data,            // 接收数据
    output reg         rx_data_valid,       // 接收数据有效标志
    input  wire [7:0]  slave_addr,         // 从机地址
    input  wire [7:0]  reg_addr,           // 从机寄存器地址
    input  wire        wr_pulse,           // 写命令脉冲
    input  wire        rd_pulse,           // 读命令脉冲
    
    // SCCB接口
    output wire        scl_o,              // SCL输出
    input  wire        scl_i,              // SCL输入
    output wire        scl_t,              // SCL三态控制
    output wire        sda_o,              // SDA输出
    input  wire        sda_i,              // SDA输入
    output wire        sda_t,              // SDA三态控制
    
    // 中断
    output reg         sccb_irq            // 中断信号
);

    // 控制寄存器位定义
    localparam CTRL_START_BIT      = 0;    // 写操作启动位
    localparam CTRL_READ_BIT       = 1;    // 读操作启动位
    localparam CTRL_STOP_BIT       = 2;    // 停止位
    localparam CTRL_ACK_BIT        = 3;    // 应答控制位
    localparam CTRL_IRQ_EN_BIT     = 4;    // 中断使能位
    
    // 状态寄存器位定义
    localparam STAT_BUSY_BIT       = 0;    // 忙状态位
    localparam STAT_TRANS_DONE_BIT = 1;    // 传输完成位
    localparam STAT_ACK_ERR_BIT    = 2;    // 应答错误位
    localparam STAT_ARB_LOST_BIT   = 3;    // 仲裁丢失位
    
    // 分频计数器(100KHz时钟)
    reg clk_div;                           // 分频后的SCL时钟
    reg [9:0] cnt_clk;                     // 分频计数器，扩展到10位以支持更大的分频值
    localparam cnt_max_100khz = ((C_CLK_FREQ_MHZ * 1000) / (C_SCCB_FREQ_KHZ * 2)) - 1;
    
    // 状态机定义
    reg [4:0] state;
    
    // 状态定义
    localparam
        IDLE          = 5'd0,  // 空闲
        START         = 5'd1,  // 起始位
        W_SLAVE_ADDR  = 5'd2,  // 写7位从设备地址+写命令0
        ACK1          = 5'd3,  // 应答1
        W_BYTE_ADDR   = 5'd4,  // 写8位字地址
        ACK2          = 5'd5,  // 应答2
        STOP          = 5'd6,  // 停止位
        W_DATA        = 5'd7,  // 写8位数据
        W_ACK         = 5'd8,  // 写应答           
        STOP2         = 5'd9,  // 中间停止位
        START2        = 5'd10, // 中间起始位                         
        R_SLAVE_ADDR  = 5'd11, // 写7位从设备地址+读命令1 
        R_ACK         = 5'd12, // 读应答 
        R_DATA        = 5'd13, // 读8位数据位        
        N_ACK         = 5'd14; // 无应答
    
    // 位计数器及数据寄存器
    reg [3:0] cnt_bit;          // 位计数器
    reg [7:0] w_data_buf;       // 写入数据寄存器
    reg [7:0] r_data_buf;       // 读出数据寄存器
    reg [7:0] w_slave_addr_buf; // 从设备地址寄存器（写）
    reg [7:0] r_slave_addr_buf; // 从设备地址寄存器（读）
    reg [7:0] byte_addr_buf;    // 字地址寄存器
    
    // 控制信号
    reg work_en;                // 工作使能信号
    reg work_done;              // 工作完成信号
    
    // SDA控制信号
    reg sda_oe;                 // SDA输出使能
    reg sda_out;                // SDA输出值
    
    // 时钟相位控制
    wire scl_half_1;            // SCL高电平中点
    wire scl_half_0;            // SCL低电平中点
    wire scl_ack_jump;          // ACK状态跳转时刻
    
    assign scl_half_1  = (cnt_clk == cnt_max_100khz >> 1 && clk_div==1'b1);     // SCL高电平中点
    assign scl_half_0  = (cnt_clk == cnt_max_100khz >> 1 && clk_div==1'b0);     // SCL低电平中点
    assign scl_ack_jump= ((cnt_clk ==(cnt_max_100khz >> 1)-5) && clk_div==1'b0); // SCL低电平中点前5clk周期
    
    // SCL和SDA接口控制
    assign scl_o = (state == STOP2 || state == START2) ? 1'b1 : clk_div;  // 在重复开始之间保持SCL高电平
    assign scl_t = 1'b0;         // SCL恒为输出模式
    assign sda_o = sda_out;      // SDA输出值
    assign sda_t = ~sda_oe;      // SDA三态控制（0=输出，1=高阻）
    
    // 分频计数器产生SCL时钟
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_clk <= 10'd1;
            clk_div <= 1'b1;
        end else if (!work_en) begin
            // 未工作时，保持SCL高电平
            cnt_clk <= 10'd1;
            clk_div <= 1'b1;
        end else if (cnt_clk == cnt_max_100khz) begin
            cnt_clk <= 10'd1;
            clk_div <= ~clk_div;
        end else 
            cnt_clk <= cnt_clk + 10'd1;
    end
    
    // 寄存数据（避免传输中途数据不稳定）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_slave_addr_buf <= 8'b0000_0000; // 0位为写命令0
            r_slave_addr_buf <= 8'b0000_0001; // 0位为读命令1
            byte_addr_buf    <= 8'b0;
            w_data_buf       <= 8'b0;
        end else if (wr_pulse || rd_pulse) begin
            w_slave_addr_buf [7:1] <= slave_addr[6:0]; // 只使用7位地址
            r_slave_addr_buf [7:1] <= slave_addr[6:0]; // 只使用7位地址
            w_data_buf       <= tx_data[7:0];
            byte_addr_buf    <= reg_addr;
        end
    end
    
    // 状态机
    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            state         <= IDLE;
            sda_oe        <= 1'b0; // SDA默认为高阻态（由外部上拉为高）
            sda_out       <= 1'b1; // SDA默认输出1
            work_en       <= 1'b0;
            work_done     <= 1'b0;
            cnt_bit       <= 4'd0;
            rx_data       <= 32'h0;
            rx_data_valid <= 1'b0;
            status_reg    <= 32'h0;
            sccb_irq      <= 1'b0;
        end else
            case(state)
                //---------------------空闲----------------------//
                IDLE: begin
                    sda_oe    <= 1'b0; // SDA为高阻态
                    sda_out   <= 1'b1; // 输出1（高阻态）
                    work_en   <= 1'b0; // 未工作
                    work_done <= 1'b0; // 清除完成标志
                    status_reg[STAT_BUSY_BIT] <= 1'b0;  // 清除忙状态
                    status_reg[STAT_TRANS_DONE_BIT] <= 1'b0; // 清除完成标志
                    
                    if (wr_pulse || rd_pulse) begin
                        state   <= START;
                        work_en <= 1'b1; // 开始工作
                        status_reg[STAT_BUSY_BIT] <= 1'b1;  // 设置忙状态
                    end
                end 
                
                //--------------------起始位--------------------//
                START: begin
                    sda_oe <= 1'b1; // SDA为输出模式
                    rx_data_valid <= 1'b0; // 清除数据有效标志
                    
                    if (scl_half_1) begin
                        sda_out <= 1'b0; // SDA输出起始位0
                        state <= W_SLAVE_ADDR;
                        cnt_bit <= 4'd0;
                    end else begin
                        sda_out <= 1'b1; // 保持SDA高电平直到scl_half_1
                    end
                end
                
                //--------------7bit从地址+写命令0---------------//
                W_SLAVE_ADDR: begin
                    sda_oe <= 1'b1; // SDA为输出模式
                    if (scl_half_0) begin
                        if (cnt_bit != 4'd8) begin
                            sda_out <= w_slave_addr_buf[7-cnt_bit]; // SDA输出设备地址（从高到低）
                            cnt_bit <= cnt_bit + 4'd1;
                        end else begin
                            state   <= ACK1;
                            cnt_bit <= 4'd0;
                        end
                    end
                end
                
                //--------------------应答1---------------------//
                ACK1: begin 
                    sda_oe <= 1'b0; // SDA为输入模式，等待从机应答
                    
                    if (scl_ack_jump) 
                        state <= W_BYTE_ADDR;
                end
                
                //-----------------8bit字节地址-----------------//
                W_BYTE_ADDR: begin
                    sda_oe <= 1'b1; // SDA为输出模式
                    if (scl_half_0) begin
                        if (cnt_bit != 4'd8) begin
                            sda_out <= byte_addr_buf[7-cnt_bit]; // SDA输出字节地址（从高到低）
                            cnt_bit <= cnt_bit + 4'd1;
                        end else begin
                            state   <= ACK2;
                            cnt_bit <= 4'd0;
                        end
                    end
                end
                
                //--------------------应答2---------------------//
                ACK2: begin 
                    sda_oe <= 1'b0; // SDA为输入模式，等待从机应答
                    
                    if (scl_ack_jump) begin
                        if (rd_pulse || ctrl_reg[CTRL_READ_BIT]) begin
                            // 读操作需要先停止再重新起始
                            state   <= STOP2;
                            sda_oe  <= 1'b1; // SDA转为输出模式
                            sda_out <= 1'b0; // 停止位需要先拉低再拉高
                        end else begin
                            // 写操作直接发送数据
                            state   <= W_DATA;
                        end
                    end
                end
                
                //--------------------写数据--------------------//
                W_DATA: begin               
                    sda_oe <= 1'b1; // SDA为输出模式
                    if (scl_half_0) begin
                        if (cnt_bit != 4'd8) begin
                            sda_out <= w_data_buf[7-cnt_bit]; // SDA输出写入数据（从高到低）
                            cnt_bit <= cnt_bit + 4'd1;
                        end else begin
                            state   <= W_ACK;
                            cnt_bit <= 4'd0;
                        end
                    end
                end
                
                //-------------------写应答---------------------//
                W_ACK: begin 
                    sda_oe <= 1'b0; // SDA为输入模式，等待从机应答
                    
                    if (scl_ack_jump) begin
                        state   <= STOP;
                        sda_oe  <= 1'b1; // SDA转为输出模式
                        sda_out <= 1'b0; // 停止位需要先拉低再拉高
                    end
                end
                
                //------------------停止位----------------------//
                STOP: begin
                    sda_oe <= 1'b1; // SDA为输出模式
                    // 设置传输完成标志和中断，同时清除忙状态位
                    status_reg[STAT_TRANS_DONE_BIT] <= 1'b1;
                    status_reg[STAT_BUSY_BIT] <= 1'b0;  // 清除忙状态
                    
                    if (scl_half_1) begin
                        sda_out   <= 1'b1; // SDA拉高，完成停止位
                        work_done <= 1'b1; // 工作结束信号置1
                        work_en   <= 1'b0; // 停止工作
                        state     <= IDLE;
                        
                        // 设置中断信号
                        if (ctrl_reg[CTRL_IRQ_EN_BIT])
                            sccb_irq <= 1'b1;
                    end else begin
                        sda_out <= 1'b0; // SCL高电平前SDA保持低
                    end
                end
                
                //------------------中间停止位------------------//
                STOP2: begin
                    sda_oe <= 1'b1; // SDA为输出模式
                    // 注意此状态不会改变work_en，保持为1，因为整个操作还没完成
                    
                    if (scl_half_1) begin
                        sda_out <= 1'b1; // SDA拉高，完成中间停止位
                        state <= START2;
                    end else begin
                        sda_out <= 1'b0; // SCL高电平前SDA保持低
                    end
                end
                
                //-------------------起始位2--------------------//
                START2: begin
                    sda_oe <= 1'b1; // SDA为输出模式
                    // 在此状态保持SCL高电平，直到SDA下降再开始SCL时钟
                    
                    if (scl_half_1) begin
                        sda_out <= 1'b0; // SDA输出起始位0
                        state <= R_SLAVE_ADDR;
                        cnt_bit <= 4'd0;
                    end else begin
                        sda_out <= 1'b1; // SCL高电平前SDA保持高，直到跳变点
                    end
                end
                
                //--------------7bit从地址+读命令1---------------//
                R_SLAVE_ADDR: begin
                    sda_oe <= 1'b1; // SDA为输出模式
                    if (scl_half_0) begin
                        if (cnt_bit != 4'd8) begin
                            sda_out <= r_slave_addr_buf[7-cnt_bit]; // SDA输出设备地址（从高到低）
                            cnt_bit <= cnt_bit + 4'd1;
                        end else begin
                            state   <= R_ACK;
                            cnt_bit <= 4'd0;
                        end
                    end
                end
                
                //-------------------读应答---------------------//
                R_ACK: begin 
                    sda_oe <= 1'b0; // SDA为输入模式，等待从机应答
                    
                    if (scl_ack_jump) 
                        state <= R_DATA;
                end
                
                //-----------------读数据-----------------//
                R_DATA: begin
                    sda_oe <= 1'b0; // SDA为输入模式，接收数据
                    
                    if (scl_half_1 && cnt_bit!=4'd8) begin      
                        r_data_buf[7-cnt_bit] <= sda_i; // 在SCL高电平中点读取数据
                        cnt_bit <= cnt_bit + 4'd1;
                    end 
                    
                    if (scl_ack_jump && cnt_bit==4'd8) begin          
                        rx_data <= {24'h0, r_data_buf}; // 保存读取的数据到输出寄存器
                        rx_data_valid <= 1'b1;          // 设置数据有效标志
                        state <= N_ACK;                 // 跳转到无应答状态
                        cnt_bit <= 4'd0;                // 重置位计数器
                    end
                end
                
                //--------------------无应答--------------------//  
                N_ACK: begin 
                    sda_oe <= 1'b1; // SDA为输出模式
                    
                    if (scl_half_0)
                        sda_out <= 1'b1; // 主机无应答(1)
                        
                    if (scl_ack_jump) begin
                        state <= STOP;
                        sda_out <= 1'b0; // 停止位需要先拉低再拉高
                    end
                end
                
                default: state <= IDLE;
            endcase 
    end
    
endmodule 