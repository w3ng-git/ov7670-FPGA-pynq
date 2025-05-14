/*
 * OV7670 Control Module
 * 
 * 此模块提供OV7670摄像头的基本控制信号
 * 包括复位控制和主时钟生成
 * SCCB配置由PS端通过I2C控制器完成
 */

`timescale 1ns / 1ps

module ov7670_controller (
    // 全局时钟和复位
    input wire clk_100mhz,        // 100MHz输入时钟
    input wire reset_n,           // 系统复位（低电平有效）
    
    // 控制信号
    input wire enable,            // 使能信号，由PS控制
    input wire [1:0] power_mode,  // 电源模式控制
    
    // 摄像头控制信号
    output reg camera_reset_n,    // 摄像头复位（低电平有效）
    output reg camera_pwdn,       // 摄像头掉电控制（高电平有效）
    output wire camera_xclk       // 摄像头主时钟 (24MHz)
);

    // 状态定义
    localparam STATE_RESET = 2'b00;
    localparam STATE_INIT  = 2'b01;
    localparam STATE_IDLE  = 2'b10;
    localparam STATE_RUN   = 2'b11;
    
    // 计数器和状态寄存器
    reg [1:0] state;
    reg [23:0] counter;
    
    // 时钟分频器 (100MHz -> 24MHz) 
    reg [1:0] clk_div;
    assign camera_xclk = clk_div[1]; // 24MHz (100MHz除以4的分频)
    
    // 时钟分频
    always @(posedge clk_100mhz or negedge reset_n) begin
        if (!reset_n)
            clk_div <= 2'b00;
        else
            clk_div <= clk_div + 1'b1;
    end
    
    // 主状态机
    always @(posedge clk_100mhz or negedge reset_n) begin
        if (!reset_n) begin
            // 复位状态
            state <= STATE_RESET;
            counter <= 24'd0;
            camera_reset_n <= 1'b0;  // 激活复位
            camera_pwdn <= 1'b1;     // 掉电模式
        end
        else begin
            case (state)
                STATE_RESET: begin
                    // 初始复位状态，等待5ms
                    camera_reset_n <= 1'b0;
                    camera_pwdn <= 1'b1;
                    
                    if (counter < 24'd500000) // 5ms @ 100MHz
                        counter <= counter + 1'b1;
                    else begin
                        counter <= 24'd0;
                        state <= STATE_INIT;
                    end
                end
                
                STATE_INIT: begin
                    // 初始化序列：释放复位，等待10ms
                    camera_reset_n <= 1'b1;
                    camera_pwdn <= 1'b1;
                    
                    if (counter < 24'd1000000) // 10ms @ 100MHz
                        counter <= counter + 1'b1;
                    else begin
                        counter <= 24'd0;
                        state <= STATE_IDLE;
                    end
                end
                
                STATE_IDLE: begin
                    // 空闲状态：如果使能，则进入运行状态
                    camera_reset_n <= 1'b1;
                    camera_pwdn <= ~enable; // 如果使能，则退出掉电模式
                    
                    if (enable)
                        state <= STATE_RUN;
                end
                
                STATE_RUN: begin
                    // 运行状态
                    camera_reset_n <= 1'b1;
                    
                    // 根据电源模式控制PWDN
                    case (power_mode)
                        2'b00: camera_pwdn <= 1'b0; // 正常工作模式
                        2'b01: camera_pwdn <= 1'b0; // 正常工作模式
                        2'b10: camera_pwdn <= 1'b1; // 低功耗模式
                        2'b11: camera_pwdn <= 1'b1; // 掉电模式
                    endcase
                    
                    // 如果禁用，返回空闲状态
                    if (!enable)
                        state <= STATE_IDLE;
                end
                
                default: state <= STATE_RESET;
            endcase
        end
    end

endmodule 