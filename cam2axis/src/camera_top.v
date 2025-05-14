/*
 * Camera Top Module
 *
 * 此模块是OV7670摄像头的顶层设计
 * 整合了摄像头控制器和AXI Stream接口，支持VDMA传输
 */

`timescale 1ns / 1ps

module camera_top (
    // 全局时钟和复位
    input wire clk_100mhz,           // 100MHz输入时钟
    input wire axi_clk,              // AXI时钟
    input wire aresetn,              // AXI复位（低电平有效）
    
    // 摄像头接口
    output wire cam_xclk,            // 摄像头主时钟
    output wire cam_reset_n,         // 摄像头复位（低电平有效）
    output wire cam_pwdn,            // 摄像头掉电控制（高电平有效）
    input wire cam_pclk,             // 摄像头像素时钟
    input wire cam_href,             // 摄像头行有效信号
    input wire cam_vsync,            // 摄像头场同步信号
    input wire [7:0] cam_data,       // 摄像头像素数据
    
    // AXI Lite接口（控制寄存器）
    input wire [31:0] ctrl_reg,      // 控制寄存器
    output wire [31:0] status_reg,   // 状态寄存器
    
    // AXI Stream主接口
    output wire m_axis_tvalid,       // 数据有效
    output wire [31:0] m_axis_tdata, // 32位数据
    output wire m_axis_tlast,        // 行结束标志
    output wire m_axis_tuser,        // 帧起始标志(SOF) - 仅在帧第一个数据传输时为高
    input wire m_axis_tready         // 下游模块就绪
);

    // 控制寄存器位定义
    wire cam_enable = ctrl_reg[0];       // 摄像头使能
    wire [1:0] cam_power_mode = ctrl_reg[2:1]; // 摄像头电源模式
    
    // 状态寄存器位定义
    reg frame_started, frame_ended;
    assign status_reg = {28'b0, frame_ended, frame_started, cam_vsync, !cam_reset_n};
    
    // 帧状态检测
    reg cam_vsync_d1, cam_vsync_d2;
    always @(posedge axi_clk) begin
        if (!aresetn) begin
            cam_vsync_d1 <= 1'b0;
            cam_vsync_d2 <= 1'b0;
            frame_started <= 1'b0;
            frame_ended <= 1'b0;
        end else begin
            cam_vsync_d1 <= cam_vsync;
            cam_vsync_d2 <= cam_vsync_d1;
            
            // 帧开始检测（vsync下降沿）
            if (cam_vsync_d2 && !cam_vsync_d1)
                frame_started <= 1'b1;
                
            // 帧结束检测（vsync上升沿）
            if (!cam_vsync_d2 && cam_vsync_d1)
                frame_ended <= 1'b1;
        end
    end

    // 摄像头控制器实例化
    ov7670_controller controller_inst (
        .clk_100mhz(clk_100mhz),
        .reset_n(aresetn),
        .enable(cam_enable),
        .power_mode(cam_power_mode),
        .camera_reset_n(cam_reset_n),
        .camera_pwdn(cam_pwdn),
        .camera_xclk(cam_xclk)
    );
    
    // 摄像头捕获模块实例化 - 支持VDMA
    camera_capture_axis capture_inst (
        .axi_clk(axi_clk),
        .aresetn(aresetn),
        .camera_pclk(cam_pclk),
        .camera_href(cam_href),
        .camera_vsync(cam_vsync),
        .camera_data(cam_data),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser),  // 帧起始标志(SOF) - 仅在帧第一个数据传输时为高
        .m_axis_tready(m_axis_tready)
    );

endmodule 