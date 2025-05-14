/*
 * Camera Top Wrapper with AXI4-Lite Interface
 *
 * 此模块是对camera_top的AXI4-Lite接口封装
 * 用于连接到PS系统，支持VDMA视频传输
 */

`timescale 1ns / 1ps

module camera_top_wrapper #(
    // AXI4-Lite参数
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 8
) (
    // 全局时钟和复位
    input wire clk_100mhz,               // 100MHz输入时钟
    input wire axi_clk,                  // AXI时钟
    
    // 摄像头接口
    output wire cam_xclk,                // 摄像头主时钟
    output wire cam_reset_n,             // 摄像头复位（低电平有效）
    output wire cam_pwdn,                // 摄像头掉电控制（高电平有效）
    input wire cam_pclk,                 // 摄像头像素时钟
    input wire cam_href,                 // 摄像头行有效信号
    input wire cam_vsync,                // 摄像头场同步信号
    input wire [7:0] cam_data,           // 摄像头像素数据
    
    // AXI Stream主接口 - 支持VDMA
    output wire m_axis_tvalid,           // 数据有效
    output wire [31:0] m_axis_tdata,     // 32位数据
    output wire m_axis_tlast,            // 行结束标志
    output wire m_axis_tuser,            // 帧起始标志 (SOF) - 仅在帧第一个数据传输时为高
    output wire [(C_S_AXI_DATA_WIDTH/8)-1:0] m_axis_tkeep, // 字节有效信号
    input wire m_axis_tready,            // 下游模块就绪
    
    // AXI4-Lite从接口
    input wire s_axi_aclk,               // 为了保持AXI协议的标准命名
    input wire s_axi_aresetn,
    input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input wire [2:0] s_axi_awprot,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output wire [1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input wire [2:0] s_axi_arprot,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire s_axi_rvalid,
    input wire s_axi_rready
);

    // 寄存器地址偏移
    localparam CTRL_REG_OFFSET = 8'h00;
    localparam STATUS_REG_OFFSET = 8'h04;
    
    // 内部信号
    reg [31:0] ctrl_reg;
    wire [31:0] status_reg;
    
    // AXI4-Lite信号
    reg s_axi_awready_i;
    reg s_axi_wready_i;
    reg s_axi_bvalid_i;
    reg s_axi_arready_i;
    reg [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata_i;
    reg s_axi_rvalid_i;
    
    // 将循环变量声明移到此处
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    integer byte_index;
    
    // AXI4-Lite输出赋值
    assign s_axi_awready = s_axi_awready_i;
    assign s_axi_wready = s_axi_wready_i;
    assign s_axi_bresp = 2'b00; // OKAY
    assign s_axi_bvalid = s_axi_bvalid_i;
    assign s_axi_arready = s_axi_arready_i;
    assign s_axi_rdata = s_axi_rdata_i;
    assign s_axi_rresp = 2'b00; // OKAY
    assign s_axi_rvalid = s_axi_rvalid_i;
    
    // 写地址处理
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready_i <= 1'b0;
            axi_awaddr <= 0;
        end else begin
            if (~s_axi_awready_i && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_awready_i <= 1'b1;
                axi_awaddr <= s_axi_awaddr;
            end else begin
                s_axi_awready_i <= 1'b0;
            end
        end
    end
    
    // 写数据处理
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_wready_i <= 1'b0;
            s_axi_bvalid_i <= 1'b0;
            ctrl_reg <= 32'h0; // 默认值：摄像头禁用
        end else begin
            if (~s_axi_wready_i && s_axi_wvalid && s_axi_awvalid) begin
                s_axi_wready_i <= 1'b1;
                
                // 写控制寄存器
                if (axi_awaddr[7:0] == CTRL_REG_OFFSET) begin
                    // 使用已预先声明的变量
                    for (byte_index = 0; byte_index < (C_S_AXI_DATA_WIDTH/8); byte_index = byte_index + 1) begin
                        if (s_axi_wstrb[byte_index]) begin
                            ctrl_reg[(byte_index*8) +: 8] <= s_axi_wdata[(byte_index*8) +: 8];
                        end
                    end
                end
            end else begin
                s_axi_wready_i <= 1'b0;
            end
            
            if (~s_axi_bvalid_i && s_axi_wready_i && s_axi_wvalid && s_axi_awready_i && s_axi_awvalid) begin
                s_axi_bvalid_i <= 1'b1;
            end else if (s_axi_bvalid_i && s_axi_bready) begin
                s_axi_bvalid_i <= 1'b0;
            end
        end
    end
    
    // 读地址处理
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready_i <= 1'b0;
            axi_araddr <= 0;
        end else begin
            if (~s_axi_arready_i && s_axi_arvalid) begin
                s_axi_arready_i <= 1'b1;
                axi_araddr <= s_axi_araddr;
            end else begin
                s_axi_arready_i <= 1'b0;
            end
        end
    end
    
    // 读数据处理
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_rvalid_i <= 1'b0;
            s_axi_rdata_i <= 0;
        end else begin
            if (s_axi_arready_i && s_axi_arvalid && ~s_axi_rvalid_i) begin
                s_axi_rvalid_i <= 1'b1;
                
                // 读寄存器
                case (axi_araddr[7:0])
                    CTRL_REG_OFFSET: s_axi_rdata_i <= ctrl_reg;
                    STATUS_REG_OFFSET: s_axi_rdata_i <= status_reg;
                    default: s_axi_rdata_i <= 0;
                endcase
            end else if (s_axi_rvalid_i && s_axi_rready) begin
                s_axi_rvalid_i <= 1'b0;
            end
        end
    end
    
    // AXI Stream输出赋值
    assign m_axis_tkeep = {(C_S_AXI_DATA_WIDTH/8){1'b1}}; // 设置常量高电平，表示所有字节都有效
    
    // 摄像头顶层模块实例化
    camera_top camera_top_inst (
        .clk_100mhz(clk_100mhz),
        .axi_clk(axi_clk),
        .aresetn(s_axi_aresetn),
        
        .cam_xclk(cam_xclk),
        .cam_reset_n(cam_reset_n),
        .cam_pwdn(cam_pwdn),
        .cam_pclk(cam_pclk),
        .cam_href(cam_href),
        .cam_vsync(cam_vsync),
        .cam_data(cam_data),
        
        .ctrl_reg(ctrl_reg),
        .status_reg(status_reg),
        
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser), // 帧起始标志(SOF) - 仅在帧第一个数据传输时为高
        .m_axis_tready(m_axis_tready)
    );

endmodule 