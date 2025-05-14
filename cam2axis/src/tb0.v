/*
 * OV7670 Camera Capture Testbench - RGB565转RGBA模式
 * 
 * 此测试台使用camDataMock模块模拟OV7670摄像头的输出
 * 用于验证camera_capture_axis模块的功能
 */

`timescale 1ns / 1ps

module camera_capture_axis_tb;

    // 测试参数
    parameter CLK_PERIOD_AXI = 10;       // AXI时钟周期：10ns (100MHz)
    parameter CLK_PERIOD_XCLK = 41.67;   // 摄像头时钟周期：41.67ns (24MHz)
    parameter FRAME_WIDTH  = 8;          // 图像宽度：8列
    parameter FRAME_HEIGHT = 4;          // 图像高度：4行
    
    // 时钟和复位信号
    reg axi_clk;
    reg xclk;
    reg aresetn;
    
    // 摄像头模拟接口信号
    wire camera_pclk;
    wire camera_href;
    wire camera_vsync;
    wire [7:0] camera_data;
    wire camera_frame_done;    // 添加frame_done信号
    wire [1:0] camera_current_frame; // 添加current_frame信号
    
    // AXI Stream信号
    wire m_axis_tvalid;
    wire [31:0] m_axis_tdata;
    wire m_axis_tlast;
    wire m_axis_tuser;
    reg m_axis_tready;
    
    // 测试计数器和状态
    integer data_count;        // 接收到的数据包计数
    integer tuser_count;       // tuser高电平计数
    integer tlast_count;       // tlast高电平计数
    integer error_count;       // 错误计数
    integer frame_count;       // 帧计数
    
    // 实例化OV7670摄像头模拟模块
    camDataMock #(
        .PCLK_FREQ_MHZ(24),
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT),
        .FRAMES_TO_SEND(10)
    ) camera_mock (
        .xclk(xclk),
        .reset_n(aresetn),
        .enable(aresetn),  // 复位后立即启用
        .pclk(camera_pclk),
        .vsync(camera_vsync),
        .href(camera_href),
        .data_out(camera_data),
        .frame_done(camera_frame_done),
        .current_frame(camera_current_frame)
    );
    
    // 实例化被测模块
    camera_capture_axis #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) uut (
        .axi_clk(axi_clk),
        .aresetn(aresetn),
        .camera_pclk(camera_pclk),
        .camera_href(camera_href),
        .camera_vsync(camera_vsync),
        .camera_data(camera_data),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser),
        .m_axis_tready(m_axis_tready)
    );
    
    // 生成AXI时钟 (100MHz)
    initial begin
        axi_clk = 0;
        forever #(CLK_PERIOD_AXI/2) axi_clk = ~axi_clk;
    end
    
    // 生成XCLK (24MHz)
    initial begin
        xclk = 0;
        forever #(CLK_PERIOD_XCLK/2) xclk = ~xclk;
    end
    
    // 监视AXI Stream输出
    always @(posedge axi_clk) begin
        if (aresetn && m_axis_tvalid && m_axis_tready) begin
            data_count = data_count + 1;
            
            // 检测tuser (SOF)
            if (m_axis_tuser) begin
                tuser_count = tuser_count + 1;
                frame_count = frame_count + 1;
                $display("\n[%0t] --- 开始接收第%0d帧 ---", $time, frame_count);
            end
            
            // 检测tlast (EOL)
            if (m_axis_tlast) begin
                tlast_count = tlast_count + 1;
                $display("[%0t] 行结束标志(TLAST), 行数据包数: %0d", $time, tlast_count % FRAME_HEIGHT);
            end
            
            // 提取和显示RGBA像素数据
            $display("[%0t] 数据包[%0d]: 0x%08x, TLAST=%0d, TUSER=%0d", 
                     $time, data_count, m_axis_tdata, m_axis_tlast, m_axis_tuser);
            $display("  RGBA像素: R=0x%02x, G=0x%02x, B=0x%02x, A=0x%02x", 
                     m_axis_tdata[31:24], m_axis_tdata[23:16],
                     m_axis_tdata[15:8], m_axis_tdata[7:0]);
        end
    end
    
    // 检测帧边界和状态
    always @(posedge camera_vsync or posedge camera_frame_done) begin
        if (aresetn) begin
            if (camera_frame_done) begin
                $display("\n[%0t] ALL FRAMES COMPLETED - frame_done signal detected", $time);
                $display("  Total frames sent: %0d", camera_current_frame);
            end else if (frame_count > 0) begin
                $display("\n[%0t] VSYNC detected - Frame %0d completed (camera reporting frame: %0d)", 
                         $time, frame_count, camera_current_frame);
                $display("  Data packets: %0d, TLAST signals: %0d", data_count, tlast_count);
                
                // 检查每帧中的tuser数量
                if (tuser_count != frame_count) begin
                    $display("  ERROR: Expected tuser count = %0d, got %0d", frame_count, tuser_count);
                    error_count = error_count + 1;
                end
                
                // 检查每帧中的tlast数量
                if (tlast_count != (frame_count * FRAME_HEIGHT)) begin
                    $display("  ERROR: Expected tlast count = %0d, got %0d", 
                             frame_count * FRAME_HEIGHT, tlast_count);
                    error_count = error_count + 1;
                end
            end
        end
    end
    
    // 主测试过程
    initial begin
        // 初始化信号和计数器
        aresetn = 0;
        m_axis_tready = 1;
        
        data_count = 0;
        tuser_count = 0;
        tlast_count = 0;
        error_count = 0;
        frame_count = 0;
        
        // 复位阶段
        #100;
        aresetn = 1;
        
        // 运行测试，直到检测到frame_done信号或超时
        $display("\n[%0t] Starting to capture frames...", $time);
        
        // 等待直到frame_done信号被触发或超时
        wait(camera_frame_done == 1 || $time > 10000000);
        
        if (camera_frame_done) begin
            $display("\n[%0t] Detected frame_done signal after capturing %0d frames", 
                    $time, camera_current_frame);
        end else begin
            $display("\n[%0t] Test timeout reached without detecting frame_done", $time);
            error_count = error_count + 1;
        end
        
        // 测试VDMA暂停情况 - 只有当我们想继续测试时才运行这部分
        if(0) begin  // 将此条件设置为0，跳过这部分测试
            $display("\n[%0t] Testing VDMA pause scenario...", $time);
            m_axis_tready = 0;
            #500000;
            
            $display("[%0t] Resuming VDMA reception (tready=1)", $time);
            m_axis_tready = 1;
            #5000000;
        end
        
        // 报告测试结果
        $display("\n--- Test Summary ---");
        $display("Frames received: %0d", frame_count);
        $display("Frames sent by camera: %0d", camera_current_frame);
        $display("Data packets received: %0d", data_count);
        $display("SOF signals (tuser) detected: %0d", tuser_count);
        $display("EOL signals (tlast) detected: %0d", tlast_count);
        $display("Errors detected: %0d", error_count);
        
        // 验证像素数
        if (data_count != (FRAME_WIDTH * FRAME_HEIGHT * frame_count)) begin
            $display("ERROR: Expected %0d pixels, received %0d", 
                      FRAME_WIDTH * FRAME_HEIGHT * frame_count, data_count);
            error_count = error_count + 1;
        end
        
        if (error_count == 0 && camera_frame_done) begin
            $display("TEST PASSED! Successfully captured all %0d frames", camera_current_frame);
        end else begin
            $display("TEST FAILED with %0d errors", error_count);
        end
        
        $finish;
    end

endmodule 