`timescale 1ns / 1ps

module w3_sccb_tb;

    // 时钟和复位信号
    reg         clk;
    reg         rst_n;
    
    // AXI4-Lite接口信号
    reg [4:0]   s_axi_awaddr;   // 5位地址总线（C_S00_AXI_ADDR_WIDTH）
    reg [2:0]   s_axi_awprot;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg [31:0]  s_axi_wdata;    // 32位数据总线（C_S00_AXI_DATA_WIDTH）
    reg [3:0]   s_axi_wstrb;    // 4位写选通
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg [4:0]   s_axi_araddr;   // 5位地址总线
    reg [2:0]   s_axi_arprot;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;    // 32位数据总线
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;
    
    // SCCB接口信号
    wire        scl_o;          // SCL输出
    wire        scl_i;          // SCL输入
    wire        scl_t;          // SCL三态控制
    wire        sda_o;          // SDA输出
    wire        sda_i;          // SDA输入
    wire        sda_t;          // SDA三态控制
    wire        sccb_irq;        // 中断信号
    
    // SCCB总线信号
    wire        scl;            // SCCB时钟线
    wire        sda;            // SCCB数据线
    
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
    
    // 设置模拟SCCB总线
    assign scl = scl_t ? 1'b1 : scl_o;
    assign scl_i = scl;
    
    // 修改SDA总线连接，支持双向数据传输
    // 当主设备和从设备都不驱动时，SDA保持高电平
    // 当任一设备驱动低电平时，SDA为低电平（线与逻辑）
    assign sda = sda_t ? 1'bz : sda_o;  // 主设备驱动SDA
    assign sda_i = sda;
    
    // SCCB总线状态监控
    reg prev_mon_scl, prev_mon_sda;
    
    always @(posedge clk) begin
        prev_mon_scl <= scl;
        prev_mon_sda <= sda;
        
        // 检测SCL或SDA变化
        if (scl != prev_mon_scl || sda != prev_mon_sda) begin
            $display("[%0t] SCCB总线状态: SCL=%b, SDA=%b", $time, scl, sda);
        end
        
        // 检测起始和停止条件
        if (scl && prev_mon_sda && !sda)
            $display("[%0t] SCCB总线: 检测到起始条件 ↓", $time);
        if (scl && !prev_mon_sda && sda)
            $display("[%0t] SCCB总线: 检测到停止条件 ↑", $time);
            
        // 在SCL上升沿采样SDA
        if (scl && !prev_mon_scl)
            $display("[%0t] SCCB总线: SCL↑时SDA=%b (数据采样)", $time, sda);
    end
    
    // 寄存器偏移量定义
    localparam CTRL_REG_ADDR      = 3'h0;  // 控制寄存器地址
    localparam STATUS_REG_ADDR    = 3'h1;  // 状态寄存器地址
    localparam TX_DATA_REG_ADDR   = 3'h2;  // 发送数据寄存器地址
    localparam RX_DATA_REG_ADDR   = 3'h3;  // 接收数据寄存器地址
    localparam ADDR_REG_ADDR      = 3'h4;  // 设备地址寄存器地址
    localparam SLAVE_REG_ADDR     = 3'h5;  // 从机寄存器地址
    
    // OV7670摄像头地址
    localparam OV7670_ADDR        = 8'h42 >> 1;  // OV7670地址（0x42 >> 1 = 0x21）
    
    // 读操作相关变量
    reg [31:0] read_data;       // 存储从SCCB读取的数据
    
    // OV7670常用寄存器地址
    localparam REG_COM7      = 8'h12;   // 控制寄存器7
    localparam REG_COM10     = 8'h15;   // 控制寄存器10
    localparam REG_PID       = 8'h0A;   // 产品ID高字节
    localparam REG_VER       = 8'h0B;   // 产品ID低字节
    localparam REG_CLKRC     = 8'h11;   // 时钟控制
    localparam REG_RGB444    = 8'h8C;   // RGB444控制
    localparam REG_COM1      = 8'h04;   // 控制寄存器1
    
    // 实例化mock_ov7670_sccb模块
    mock_ov7670_sccb mock_ov7670_sccb_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .scl      (scl),
        .sda      (sda)
    );
    
    // 实例化待测试的SCCB模块
    w3_sccb_v1_0 #(
        .C_SCCB_FREQ_KHZ(100),         // 使用100KHz速率进行测试
        .C_CLK_FREQ_MHZ(100),         // 系统时钟100MHz
        .C_S00_AXI_DATA_WIDTH(32),    // AXI数据宽度32位
        .C_S00_AXI_ADDR_WIDTH(5)      // AXI地址宽度5位
    ) w3_sccb_v1_0_inst (
        // SCCB接口
        .scl_o(scl_o),
        .scl_i(scl_i),
        .scl_t(scl_t),
        .sda_o(sda_o),
        .sda_i(sda_i),
        .sda_t(sda_t),
        .sccb_irq(sccb_irq),
        
        // AXI接口
        .s00_axi_aclk(clk),
        .s00_axi_aresetn(rst_n),
        .s00_axi_awaddr(s_axi_awaddr),
        .s00_axi_awprot(s_axi_awprot),
        .s00_axi_awvalid(s_axi_awvalid),
        .s00_axi_awready(s_axi_awready),
        .s00_axi_wdata(s_axi_wdata),
        .s00_axi_wstrb(s_axi_wstrb),
        .s00_axi_wvalid(s_axi_wvalid),
        .s00_axi_wready(s_axi_wready),
        .s00_axi_bresp(s_axi_bresp),
        .s00_axi_bvalid(s_axi_bvalid),
        .s00_axi_bready(s_axi_bready),
        .s00_axi_araddr(s_axi_araddr),
        .s00_axi_arprot(s_axi_arprot),
        .s00_axi_arvalid(s_axi_arvalid),
        .s00_axi_arready(s_axi_arready),
        .s00_axi_rdata(s_axi_rdata),
        .s00_axi_rresp(s_axi_rresp),
        .s00_axi_rvalid(s_axi_rvalid),
        .s00_axi_rready(s_axi_rready)
    );
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz时钟
    end
    
    // 测试平台初始化
    initial begin
        // 初始化信号
        rst_n = 0;
        s_axi_awvalid = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;
        s_axi_wstrb = 4'hF;
        read_data = 0;
        
        // 释放复位
        #100;
        rst_n = 1;
        #100;
        
        // 测试SCCB先写后读操作
        test_sccb_write_then_read();
        
        // 也可以单独测试读操作
        // test_sccb_read();
        
        // 测试完成
        #5000;
        $display("[%0t] 测试完成!", $time);
        $finish;
    end
    
    // AXI写任务
    task axi_write;
        input [4:0]  addr;
        input [31:0] data;
        integer resp_timeout;
        begin
            $display("[%0t] AXI写操作开始 - 地址:0x%h, 数据:0x%h", $time, addr, data);
        
            // 将地址和数据准备好
            s_axi_awaddr = {addr, 2'b00}; // 字对齐
            s_axi_awprot = 3'b000;
            s_axi_wdata = data;
            s_axi_wstrb = 4'b1111; // 写入所有字节
            
            // 同时拉高有效信号
            @(posedge clk);
            s_axi_awvalid = 1'b1;
            s_axi_wvalid = 1'b1;
            s_axi_bready = 1'b1;
            
            // 等待两个通道都完成握手
            while (!(s_axi_awready && s_axi_wready)) begin
                @(posedge clk);
            end
            
            // 两个通道都完成握手后，同时拉低有效信号
            @(posedge clk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;
            $display("[%0t] AXI地址和数据通道握手同时完成", $time);
            
            // 等待响应，添加超时保护
            resp_timeout = 0;
            
            // 使用简单循环等待响应或超时
            while (!s_axi_bvalid && resp_timeout < 100) begin
                @(posedge clk);
                resp_timeout = resp_timeout + 1;
            end
            
            if (s_axi_bvalid) begin
                @(posedge clk);
                s_axi_bready = 1'b0; // 确认响应完成
                @(posedge clk);
                s_axi_bready = 1'b1; // 恢复默认状态
                $display("[%0t] AXI响应通道握手成功", $time);
            end else begin
                $display("[%0t] 警告: AXI响应通道握手超时! 强制继续执行", $time);
            end
            
            // 额外延迟，确保完整握手
            @(posedge clk);
            @(posedge clk);
            
            $display("[%0t] AXI写操作完成 - 地址:0x%h, 数据:0x%h, 响应超时=%0d", $time, addr, data, resp_timeout);
        end
    endtask
    
    // AXI读任务
    task axi_read;
        input  [4:0]  addr;
        output [31:0] data;
        integer resp_timeout;
        begin
            $display("[%0t] AXI读操作开始 - 地址:0x%h", $time, addr);
        
            // 准备地址
            s_axi_araddr = {addr, 2'b00}; // 字对齐
            s_axi_arprot = 3'b000;
            
            // 地址通道
            @(posedge clk);
            s_axi_arvalid = 1'b1;
            s_axi_rready = 1'b1;
            
            // 等待地址通道握手完成
            wait(s_axi_arready);
            @(posedge clk);
            s_axi_arvalid = 1'b0;
            $display("[%0t] AXI读地址通道握手完成", $time);
            
            // 等待数据通道握手，添加超时保护
            resp_timeout = 0;
            
            // 使用简单循环等待响应或超时
            while (!s_axi_rvalid && resp_timeout < 100) begin
                @(posedge clk);
                resp_timeout = resp_timeout + 1;
            end
            
            if (s_axi_rvalid) begin
                data = s_axi_rdata;
                @(posedge clk);
                s_axi_rready = 1'b0; // 完成读取
                @(posedge clk);
                s_axi_rready = 1'b1; // 恢复默认状态
                $display("[%0t] AXI读数据通道握手成功", $time);
            end else begin
                data = 32'hDEADDEAD; // 出错时返回特殊值
                $display("[%0t] 警告: AXI读数据通道握手超时! 返回错误数据", $time);
            end
            
            // 额外延迟，确保完整握手
            @(posedge clk);
            @(posedge clk);
            
            $display("[%0t] AXI读操作完成 - 地址:0x%h, 数据:0x%h, 响应超时=%0d", $time, addr, data, resp_timeout);
        end
    endtask
    
    // 等待传输完成任务
    task wait_transfer_done;
        reg [31:0] status;
        integer timeout_count;
        begin
            timeout_count = 0;
            $display("[%0t] 开始等待SCCB传输完成", $time);
            #1000; // 先等待一小段时间
            
            // 检查状态直到不忙或超时
            status[0] = 1'b1; // 初始化为忙状态
            while (status[0] == 1'b1 && timeout_count < 1000) begin
                axi_read(STATUS_REG_ADDR, status);
                $display("[%0t] 等待传输完成: 状态寄存器=0x%h, 忙标志=%b, 完成标志=%b, 计数=%d", 
                         $time, status, status[0], status[1], timeout_count);
                #1000; // 等待1000个时间单位
                timeout_count = timeout_count + 1;
            end
            
            if (timeout_count >= 1000) begin
                $display("[%0t] 错误: 等待传输完成超时! 最后状态=0x%h", $time, status);
            end else begin
                $display("[%0t] 传输已完成: 状态寄存器=0x%h", $time, status);
            end
        end
    endtask
    
    // SCCB读操作测试任务
    task test_sccb_read;
        begin
            $display("[%0t] 开始SCCB读操作测试", $time);
            
            // 1. 设置设备地址 (OV7670地址)
            axi_write(ADDR_REG_ADDR, OV7670_ADDR);
            #100;
            
            // 2. 设置寄存器地址 (读取产品ID)
            axi_write(SLAVE_REG_ADDR, REG_PID);
            #100;
            
            // 3. 设置控制寄存器 - 启动读操作
            axi_write(CTRL_REG_ADDR, (1 << CTRL_READ_BIT) | (1 << CTRL_STOP_BIT));
            
            // 等待SCCB传输完成
            wait_transfer_done();
            

            // 4. 读取状态寄存器，检查传输是否完成
            axi_read(STATUS_REG_ADDR, read_data);
            $display("[%0t] SCCB读操作后状态寄存器值: 0x%h", $time, read_data);
            
            // 5. 读取接收到的数据
            axi_read(RX_DATA_REG_ADDR, read_data);
            $display("[%0t] SCCB读操作接收到的数据: 0x%h (期望值: 0x76)", $time, read_data);
            
            // 验证读取到的产品ID是否正确
            if (read_data[7:0] == 8'h76) begin
                $display("[%0t] SCCB读操作测试成功! 读取到正确的产品ID: 0x%h", $time, read_data[7:0]);
            end else begin
                $display("[%0t] SCCB读操作测试失败! 读取到错误的产品ID: 0x%h，期望值: 0x76", $time, read_data[7:0]);
            end
        end
    endtask
    
    // SCCB写操作测试任务
    task test_sccb_write;
        input [7:0] reg_addr;
        input [7:0] data;
        begin
            $display("[%0t] 开始SCCB写操作测试 - 寄存器地址:0x%h, 数据:0x%h", $time, reg_addr, data);
            
            // 1. 设置设备地址 (OV7670地址)
            axi_write(ADDR_REG_ADDR, OV7670_ADDR);
            #100;
            
            // 2. 设置要写入的寄存器地址
            axi_write(SLAVE_REG_ADDR, reg_addr);
            #100;
            
            // 3. 设置要发送的数据
            axi_write(TX_DATA_REG_ADDR, data);
            #100;
            
            // 4. 设置控制寄存器 - 启动写操作（启动位+停止位）
            axi_write(CTRL_REG_ADDR, (1 << CTRL_START_BIT) | (1 << CTRL_STOP_BIT));
            
            // 等待SCCB传输完成
            wait_transfer_done();

            #10000;
            
            // 5. 读取状态寄存器，检查传输是否完成
            axi_read(STATUS_REG_ADDR, read_data);
            $display("[%0t] SCCB写操作后状态寄存器值: 0x%h", $time, read_data);
            
            if (read_data[STAT_TRANS_DONE_BIT] && !read_data[STAT_ACK_ERR_BIT]) begin
                $display("[%0t] SCCB写操作成功完成 - 寄存器[0x%h]=0x%h", $time, reg_addr, data);
            end else begin
                $display("[%0t] SCCB写操作失败! 状态寄存器=0x%h", $time, read_data);
            end
        end
    endtask
    
    // SCCB先写后读测试任务
    task test_sccb_write_then_read;
        reg [7:0] test_reg_addr;
        reg [7:0] test_data;
        reg [31:0] read_value;
        begin
            $display("[%0t] 开始SCCB先写后读测试", $time);
            
            // 选择一个测试寄存器地址 (选择COM7寄存器进行测试)
            test_reg_addr = REG_COM7;
            test_data = 8'hA5;  // 测试数据模式，可以换成其他特定值
            
            // 第一步：先写入数据
            test_sccb_write(test_reg_addr, test_data);
            #2000;  // 等待稳定
            
            // 第二步：检查写入是否成功（通过读取验证）
            // 1. 设置设备地址
            axi_write(ADDR_REG_ADDR, OV7670_ADDR);
            #100;
            
            // 2. 设置寄存器地址
            axi_write(SLAVE_REG_ADDR, test_reg_addr);
            #100;
            
            // 3. 设置控制寄存器 - 启动读操作
            axi_write(CTRL_REG_ADDR, (1 << CTRL_READ_BIT) | (1 << CTRL_STOP_BIT));
            
            // 等待SCCB传输完成
            wait_transfer_done();
            
            // 4. 读取状态寄存器，检查传输是否完成
            axi_read(STATUS_REG_ADDR, read_value);
            $display("[%0t] SCCB读操作后状态寄存器值: 0x%h", $time, read_value);
            
            // 5. 读取接收到的数据
            axi_read(RX_DATA_REG_ADDR, read_value);
            $display("[%0t] SCCB读操作接收到的数据: 0x%h (期望值: 0x%h)", $time, read_value[7:0], test_data);
            
            // 验证读取到的数据是否与写入值匹配
            if (read_value[7:0] == test_data) begin
                $display("[%0t] SCCB先写后读测试成功! 读取到正确的数据: 0x%h", $time, read_value[7:0]);
            end else begin
                $display("[%0t] SCCB先写后读测试失败! 读取到的数据: 0x%h，期望值: 0x%h", 
                         $time, read_value[7:0], test_data);
            end
            
            // 额外测试：再测试一次读取PID寄存器
            $display("[%0t] 附加测试 - 读取PID寄存器", $time);
            
            // 1. 设置设备地址 (OV7670地址)
            axi_write(ADDR_REG_ADDR, OV7670_ADDR);
            #100;
            
            // 2. 设置寄存器地址 (读取产品ID)
            axi_write(SLAVE_REG_ADDR, REG_PID);
            #100;
            
            // 3. 设置控制寄存器 - 启动读操作
            axi_write(CTRL_REG_ADDR, (1 << CTRL_READ_BIT) | (1 << CTRL_STOP_BIT));
            
            // 等待SCCB传输完成
            wait_transfer_done();
            
            // 4. 读取状态寄存器，检查传输是否完成
            axi_read(STATUS_REG_ADDR, read_value);
            $display("[%0t] PID读操作后状态寄存器值: 0x%h", $time, read_value);
            
            // 5. 读取接收到的数据
            axi_read(RX_DATA_REG_ADDR, read_value);
            $display("[%0t] PID读操作接收到的数据: 0x%h (期望值: 0x76)", $time, read_value[7:0]);
            
            // 验证读取到的产品ID是否正确
            if (read_value[7:0] == 8'h76) begin
                $display("[%0t] PID读操作测试成功! 读取到正确的产品ID: 0x%h", $time, read_value[7:0]);
            end else begin
                $display("[%0t] PID读操作测试失败! 读取到错误的产品ID: 0x%h，期望值: 0x76", $time, read_value[7:0]);
            end
        end
    endtask

endmodule 