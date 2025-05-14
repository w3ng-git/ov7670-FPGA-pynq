/*
 * Camera Top Wrapper with AXI4-Lite Interface
 *
 * ��ģ���Ƕ�camera_top��AXI4-Lite�ӿڷ�װ
 * �������ӵ�PSϵͳ��֧��VDMA��Ƶ����
 */

`timescale 1ns / 1ps

module camera_top_wrapper #(
    // AXI4-Lite����
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 8
) (
    // ȫ��ʱ�Ӻ͸�λ
    input wire clk_100mhz,               // 100MHz����ʱ��
    input wire axi_clk,                  // AXIʱ��
    
    // ����ͷ�ӿ�
    output wire cam_xclk,                // ����ͷ��ʱ��
    output wire cam_reset_n,             // ����ͷ��λ���͵�ƽ��Ч��
    output wire cam_pwdn,                // ����ͷ������ƣ��ߵ�ƽ��Ч��
    input wire cam_pclk,                 // ����ͷ����ʱ��
    input wire cam_href,                 // ����ͷ����Ч�ź�
    input wire cam_vsync,                // ����ͷ��ͬ���ź�
    input wire [7:0] cam_data,           // ����ͷ��������
    
    // AXI Stream���ӿ� - ֧��VDMA
    output wire m_axis_tvalid,           // ������Ч
    output wire [31:0] m_axis_tdata,     // 32λ����
    output wire m_axis_tlast,            // �н�����־
    output wire m_axis_tuser,            // ֡��ʼ��־ (SOF) - ����֡��һ�����ݴ���ʱΪ��
    output wire [(C_S_AXI_DATA_WIDTH/8)-1:0] m_axis_tkeep, // �ֽ���Ч�ź�
    input wire m_axis_tready,            // ����ģ�����
    
    // AXI4-Lite�ӽӿ�
    input wire s_axi_aclk,               // Ϊ�˱���AXIЭ��ı�׼����
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

    // �Ĵ�����ַƫ��
    localparam CTRL_REG_OFFSET = 8'h00;
    localparam STATUS_REG_OFFSET = 8'h04;
    
    // �ڲ��ź�
    reg [31:0] ctrl_reg;
    wire [31:0] status_reg;
    
    // AXI4-Lite�ź�
    reg s_axi_awready_i;
    reg s_axi_wready_i;
    reg s_axi_bvalid_i;
    reg s_axi_arready_i;
    reg [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata_i;
    reg s_axi_rvalid_i;
    
    // ��ѭ�����������Ƶ��˴�
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    integer byte_index;
    
    // AXI4-Lite�����ֵ
    assign s_axi_awready = s_axi_awready_i;
    assign s_axi_wready = s_axi_wready_i;
    assign s_axi_bresp = 2'b00; // OKAY
    assign s_axi_bvalid = s_axi_bvalid_i;
    assign s_axi_arready = s_axi_arready_i;
    assign s_axi_rdata = s_axi_rdata_i;
    assign s_axi_rresp = 2'b00; // OKAY
    assign s_axi_rvalid = s_axi_rvalid_i;
    
    // д��ַ����
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
    
    // д���ݴ���
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_wready_i <= 1'b0;
            s_axi_bvalid_i <= 1'b0;
            ctrl_reg <= 32'h0; // Ĭ��ֵ������ͷ����
        end else begin
            if (~s_axi_wready_i && s_axi_wvalid && s_axi_awvalid) begin
                s_axi_wready_i <= 1'b1;
                
                // д���ƼĴ���
                if (axi_awaddr[7:0] == CTRL_REG_OFFSET) begin
                    // ʹ����Ԥ�������ı���
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
    
    // ����ַ����
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
    
    // �����ݴ���
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_rvalid_i <= 1'b0;
            s_axi_rdata_i <= 0;
        end else begin
            if (s_axi_arready_i && s_axi_arvalid && ~s_axi_rvalid_i) begin
                s_axi_rvalid_i <= 1'b1;
                
                // ���Ĵ���
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
    
    // AXI Stream�����ֵ
    assign m_axis_tkeep = {(C_S_AXI_DATA_WIDTH/8){1'b1}}; // ���ó����ߵ�ƽ����ʾ�����ֽڶ���Ч
    
    // ����ͷ����ģ��ʵ����
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
        .m_axis_tuser(m_axis_tuser), // ֡��ʼ��־(SOF) - ����֡��һ�����ݴ���ʱΪ��
        .m_axis_tready(m_axis_tready)
    );

endmodule 