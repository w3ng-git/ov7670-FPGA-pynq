/*
 * OV7670 Camera Capture with AXI Stream Interface
 * 
 * 此模块将OV7670摄像头数据转换为AXI Stream格式
 * 用于与AXI VDMA连接，将图像数据传输到PS DDR内存
 * 
 * RGB565格式转RGBA格式：
 * RGB565: RRRRRGGG GGGBBBBB (两个字节表示一个像素)
 * RGBA:   RRRRRRRR GGGGGGGG BBBBBBBB AAAAAAAA (四个字节表示一个像素)
 */

`timescale 1ns / 1ps

module camera_capture_axis #(
    // 用户可配置参数
    parameter FRAME_WIDTH  = 640,  // 图像宽度 (默认640列) 
    parameter FRAME_HEIGHT = 480,  // 图像高度 (默认480行)
    parameter FIFO_DEPTH   = 16    // FIFO深度参数
)(
    // 全局时钟和复位
    input wire axi_clk,                  // AXI时钟
    input wire aresetn,                  // AXI复位（低电平有效）
    
    // 摄像头接口
    input wire camera_pclk,             // 像素时钟
    input wire camera_href,             // 行有效信号
    input wire camera_vsync,            // 场同步信号
    input wire [7:0] camera_data,       // 像素数据
    
    // AXI Stream主接口 - 兼容VDMA
    output reg m_axis_tvalid,           // 数据有效
    output reg [31:0] m_axis_tdata,     // 32位数据（RGBA格式）
    output reg m_axis_tlast,            // 行结束标志
    output reg m_axis_tuser,            // 帧起始标志 (VDMA特有)
    input wire m_axis_tready            // 下游模块就绪
);

    // ============== 信号定义 ==============
    // 摄像头信号寄存延迟
    reg camera_href_1 = 1'b0;
    reg camera_href_2 = 1'b0;
    reg camera_vsync_1 = 1'b0;
    reg camera_vsync_2 = 1'b0;
    
    // 边缘检测信号
    wire camera_href_rising;
    wire camera_href_falling;
    wire camera_vsync_rising;
    wire camera_vsync_falling;
    
    // 像素处理标志
    reg byte_toggle = 1'b0;             // 切换字节标志（低字节/高字节）
    
    // RGB565原始数据存储
    reg [7:0] cam_data_high = 8'b0;     // 高字节 (RRRRRGGG)
    reg [7:0] cam_data_low = 8'b0;      // 低字节 (GGGBBBBB)
    
    // RGB完整像素和控制信号
    reg pixel_valid = 1'b0;             // 像素有效标志
    
    // 行列计数与控制信号
    reg [11:0] h_cnt = 12'b0;           // 列计数
    reg [11:0] v_cnt = 12'b0;           // 行计数
    reg is_first_pixel = 1'b0;         // 帧第一个像素标志
    
    // 行宽度跟踪
    reg [11:0] line_width = 12'b0;      // 当前行宽度 (camera_pclk域)

    // ============== AXI时钟域的href同步和边缘检测 ==============
    reg [2:0] href_sync = 3'b0;         // AXI域的href同步寄存器
    wire href_rising_axi;               // AXI域的href上升沿
    
    always @(posedge axi_clk or negedge aresetn) begin
        if (!aresetn) begin
            href_sync <= 3'b0;
        end else begin
            href_sync <= {href_sync[1:0], camera_href};
        end
    end
    
    // AXI域的href上升沿检测
    assign href_rising_axi = (href_sync[1] == 1'b1 && href_sync[2] == 1'b0);
    
    // ============== 摄像头信号同步与边缘检测 ==============
    // 信号延迟一个周期 - 修改为在pclk上升沿采样
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            camera_href_1 <= 1'b0;
            camera_href_2 <= 1'b0;
            camera_vsync_1 <= 1'b0;
            camera_vsync_2 <= 1'b0;
        end else begin
            camera_href_1 <= camera_href;
            camera_href_2 <= camera_href_1;
            camera_vsync_1 <= camera_vsync;
            camera_vsync_2 <= camera_vsync_1;
        end
    end
    
    // 边缘检测
    assign camera_href_rising = (camera_href_1 & ~camera_href_2);
    assign camera_href_falling = (~camera_href_1 & camera_href_2);
    assign camera_vsync_rising = (camera_vsync_1 & ~camera_vsync_2);
    assign camera_vsync_falling = (~camera_vsync_1 & camera_vsync_2);
    
    // ============== RGB565数据处理 ==============
    // RGB565格式接收处理 - 修改为在pclk上升沿采样
    // 在pclk上升沿检测到href有效时可以直接进行字节切换
    
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            byte_toggle <= 1'b0;
            cam_data_high <= 8'b0;
            cam_data_low <= 8'b0;
            pixel_valid <= 1'b0;
            is_first_pixel <= 1'b0;
        end else if (camera_vsync) begin  // 直接使用camera_vsync
            // 场同步期间重置
            byte_toggle <= 1'b0;
            pixel_valid <= 1'b0;
            is_first_pixel <= 1'b0;
        end else if (camera_href) begin  // 直接使用camera_href
            // href有效时直接切换byte_toggle
            byte_toggle <= ~byte_toggle;
            
            if (byte_toggle) begin
                // toggle=1时接收到第二个字节（低字节）
                cam_data_low <= camera_data;
                
                // 数据完整后，置位有效标志
                pixel_valid <= 1'b1;
                
                // 检测是否为帧第一个像素
                if (h_cnt == 12'd0 && v_cnt == 12'd0) begin
                    is_first_pixel <= 1'b1;
                end else begin
                    is_first_pixel <= 1'b0;
                end
            end else begin
                // toggle=0时接收到第一个字节（高字节）
                cam_data_high <= camera_data;
                pixel_valid <= 1'b0;
            end
        end else begin
            // 行间隙期间重置标志
            byte_toggle <= 1'b0;
            pixel_valid <= 1'b0;
            is_first_pixel <= 1'b0;
        end
    end
    
    // ============== 行列计数 ==============
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            h_cnt <= 12'b0;
            v_cnt <= 12'b0;
        end else if (camera_vsync) begin  // 直接使用camera_vsync
            // 场同步期间重置计数
            h_cnt <= 12'b0;
            v_cnt <= 12'b0;
        end else if (!camera_href && camera_href_1) begin  // 检测href下降沿
            // 一行结束，增加行计数，重置列计数
            h_cnt <= 12'b0;
            v_cnt <= v_cnt + 1'b1;
        end else if (camera_href && byte_toggle) begin  // 直接使用camera_href
            // 每两个字节组成一个像素，增加列计数
            h_cnt <= h_cnt + 1'b1;
        end
    end
    
    // ============== 行宽度检测 ==============
    // 记录行宽度用于检测行结束 - 修改为在pclk上升沿采样
    reg [11:0] h_cnt_temp = 12'b0;
    
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            h_cnt_temp <= 12'b0;
            line_width <= 12'b0;
        end else if (camera_vsync) begin  // 直接使用camera_vsync
            // 场同步期间重置
            h_cnt_temp <= 12'b0;
            line_width <= 12'b0;
        end else if (camera_href) begin  // 直接使用camera_href
            // 只在接收到完整像素后增加计数
            // 这里必须确保与h_cnt的增加条件完全相同
            if (byte_toggle && pixel_valid) 
                h_cnt_temp <= h_cnt_temp + 1'b1;
        end else if (!camera_href && camera_href_1) begin  // 检测href下降沿
            // 一行结束，记录行宽度
            line_width <= h_cnt_temp;
            h_cnt_temp <= 12'b0;
        end
    end
    
    // ============== 跨时钟域FIFO定义 ==============
    // FIFO数据结构 - 每个元素包含RGB565原始数据和控制信号
    reg [17:0] fifo_data[0:FIFO_DEPTH-1]; // {is_first_pixel, cam_data_high, cam_data_low}
    reg [$clog2(FIFO_DEPTH):0] wr_ptr = 0; // 写指针，比FIFO_DEPTH多一位用于满检测
    reg [$clog2(FIFO_DEPTH):0] rd_ptr = 0; // 读指针，比FIFO_DEPTH多一位用于空检测
    
    // FIFO状态信号
    wire fifo_empty; 
    wire fifo_full;
    wire fifo_almost_full;
    wire [$clog2(FIFO_DEPTH):0] fifo_count;
    
    // FIFO状态计算
    assign fifo_count = wr_ptr - rd_ptr;
    assign fifo_empty = (wr_ptr == rd_ptr);
    assign fifo_full = (fifo_count >= FIFO_DEPTH); 
    assign fifo_almost_full = (fifo_count >= FIFO_DEPTH-2);
    
    // 行末尾像素标记 (用于在FIFO中标记行结束)
    reg is_last_pixel = 1'b0;
    
    // 在camera_pclk域检测行结束的像素
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            is_last_pixel <= 1'b0;
        end else if (camera_vsync) begin
            is_last_pixel <= 1'b0;
        end else if (camera_href) begin
            // 如果当前列计数等于预设宽度减1，则为行末像素
            is_last_pixel <= (h_cnt == FRAME_WIDTH - 1'b1) ;// && byte_toggle && pixel_valid;
        end else begin
            is_last_pixel <= 1'b0;
        end
    end
    
    // ============== FIFO写逻辑 (camera_pclk域) ==============
    reg fifo_wr_en = 1'b0;
    reg [17:0] fifo_din = 18'b0; // {is_first_pixel, is_last_pixel, cam_data_high, cam_data_low}
    
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            fifo_wr_en <= 1'b0;
            fifo_din <= 18'b0;
        end else begin
            // 默认禁用写入
            fifo_wr_en <= 1'b0;
            
            // 当有完整的像素且FIFO未满时写入FIFO
            if (pixel_valid && !fifo_almost_full) begin
                fifo_din <= {is_first_pixel, is_last_pixel, cam_data_high, cam_data_low};
                fifo_wr_en <= 1'b1;
            end
        end
    end
    
    // 更新写指针
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_ptr <= 0;
        end else if (fifo_wr_en && !fifo_full) begin
            // 写入FIFO并更新写指针
            fifo_data[wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= fifo_din;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end
    
    // ============== FIFO读逻辑 (axi_clk域) ==============
    reg fifo_rd_en = 1'b0;
    reg [17:0] fifo_dout = 18'b0;
    reg fifo_valid = 1'b0;
    
    // 更新读指针和读取数据
    always @(posedge axi_clk or negedge aresetn) begin
        if (!aresetn) begin
            rd_ptr <= 0;
            fifo_dout <= 18'b0;
            fifo_valid <= 1'b0;
        end else begin
            // 默认无效
            fifo_valid <= 1'b0;
            
            // 当FIFO非空且上次数据已被处理或尚未读取数据时尝试读取
            if (!fifo_empty && (!fifo_valid || (m_axis_tvalid && m_axis_tready))) begin
                fifo_dout <= fifo_data[rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
                rd_ptr <= rd_ptr + 1'b1;
                fifo_valid <= 1'b1;
            end else if (m_axis_tvalid && m_axis_tready) begin
                // 数据已被AXI接受，清除有效标志
                fifo_valid <= 1'b0;
            end
        end
    end
    
    // 解析FIFO数据
    wire fifo_first_pixel = fifo_dout[17];
    wire fifo_last_pixel = fifo_dout[16];
    wire [7:0] fifo_data_high = fifo_dout[15:8];
    wire [7:0] fifo_data_low = fifo_dout[7:0];
    
    // RGBA组合逻辑
    wire [4:0] rgb_r = fifo_data_high[7:3];                 // 红色分量 (5位)
    wire [5:0] rgb_g = {fifo_data_high[2:0], fifo_data_low[7:5]}; // 绿色分量 (6位)
    wire [4:0] rgb_b = fifo_data_low[4:0];                  // 蓝色分量 (5位)
    
    // RGB565到RGBA的转换组合逻辑
    wire [7:0] R8 = {rgb_r, rgb_r[4:2]};      // 5位扩展到8位，高位复制到低位
    wire [7:0] G8 = {rgb_g, rgb_g[5:4]};      // 6位扩展到8位，高位复制到低位
    wire [7:0] B8 = {rgb_b, rgb_b[4:2]};      // 5位扩展到8位，高位复制到低位
    wire [31:0] rgba_data = {R8, G8, B8, 8'hFF}; // 组合成32位RGBA
    
    // AXI Stream状态机
    localparam IDLE = 1'b0;
    localparam SEND = 1'b1;
    reg axi_state = IDLE;
    
    always @(posedge axi_clk or negedge aresetn) begin
        if (!aresetn) begin
            axi_state <= IDLE;
            m_axis_tvalid <= 1'b0;
            m_axis_tdata <= 32'b0;
            m_axis_tlast <= 1'b0;
            m_axis_tuser <= 1'b0;
        end else begin
            case (axi_state)
                IDLE: begin
                    // 只有当FIFO有有效数据时才启动传输
                    if (fifo_valid) begin
                        m_axis_tdata <= rgba_data;  // 使用组合逻辑直接生成RGBA
                        m_axis_tvalid <= 1'b1;
                        
                        // 设置tuser (帧起始标志)
                        m_axis_tuser <= fifo_first_pixel;
                        
                        // 设置tlast (行结束标志) - 基于FIFO中的标记
                        m_axis_tlast <= fifo_last_pixel;
                        
                        axi_state <= SEND;
                    end else begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast <= 1'b0;
                        m_axis_tuser <= 1'b0;
                    end
                end
                
                SEND: begin
                    // 成功握手后立即清除信号并返回IDLE状态
                    if (m_axis_tready) begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast <= 1'b0;
                        m_axis_tuser <= 1'b0;
                        axi_state <= IDLE;
                    end
                end
                
                default: axi_state <= IDLE;
            endcase
        end
    end

endmodule 