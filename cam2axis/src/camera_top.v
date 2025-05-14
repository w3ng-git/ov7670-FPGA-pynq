/*
 * Camera Top Module
 *
 * ��ģ����OV7670����ͷ�Ķ������
 * ����������ͷ��������AXI Stream�ӿڣ�֧��VDMA����
 */

`timescale 1ns / 1ps

module camera_top (
    // ȫ��ʱ�Ӻ͸�λ
    input wire clk_100mhz,           // 100MHz����ʱ��
    input wire axi_clk,              // AXIʱ��
    input wire aresetn,              // AXI��λ���͵�ƽ��Ч��
    
    // ����ͷ�ӿ�
    output wire cam_xclk,            // ����ͷ��ʱ��
    output wire cam_reset_n,         // ����ͷ��λ���͵�ƽ��Ч��
    output wire cam_pwdn,            // ����ͷ������ƣ��ߵ�ƽ��Ч��
    input wire cam_pclk,             // ����ͷ����ʱ��
    input wire cam_href,             // ����ͷ����Ч�ź�
    input wire cam_vsync,            // ����ͷ��ͬ���ź�
    input wire [7:0] cam_data,       // ����ͷ��������
    
    // AXI Lite�ӿڣ����ƼĴ�����
    input wire [31:0] ctrl_reg,      // ���ƼĴ���
    output wire [31:0] status_reg,   // ״̬�Ĵ���
    
    // AXI Stream���ӿ�
    output wire m_axis_tvalid,       // ������Ч
    output wire [31:0] m_axis_tdata, // 32λ����
    output wire m_axis_tlast,        // �н�����־
    output wire m_axis_tuser,        // ֡��ʼ��־(SOF) - ����֡��һ�����ݴ���ʱΪ��
    input wire m_axis_tready         // ����ģ�����
);

    // ���ƼĴ���λ����
    wire cam_enable = ctrl_reg[0];       // ����ͷʹ��
    wire [1:0] cam_power_mode = ctrl_reg[2:1]; // ����ͷ��Դģʽ
    
    // ״̬�Ĵ���λ����
    reg frame_started, frame_ended;
    assign status_reg = {28'b0, frame_ended, frame_started, cam_vsync, !cam_reset_n};
    
    // ֡״̬���
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
            
            // ֡��ʼ��⣨vsync�½��أ�
            if (cam_vsync_d2 && !cam_vsync_d1)
                frame_started <= 1'b1;
                
            // ֡������⣨vsync�����أ�
            if (!cam_vsync_d2 && cam_vsync_d1)
                frame_ended <= 1'b1;
        end
    end

    // ����ͷ������ʵ����
    ov7670_controller controller_inst (
        .clk_100mhz(clk_100mhz),
        .reset_n(aresetn),
        .enable(cam_enable),
        .power_mode(cam_power_mode),
        .camera_reset_n(cam_reset_n),
        .camera_pwdn(cam_pwdn),
        .camera_xclk(cam_xclk)
    );
    
    // ����ͷ����ģ��ʵ���� - ֧��VDMA
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
        .m_axis_tuser(m_axis_tuser),  // ֡��ʼ��־(SOF) - ����֡��һ�����ݴ���ʱΪ��
        .m_axis_tready(m_axis_tready)
    );

endmodule 