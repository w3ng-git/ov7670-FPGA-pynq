/*
 * OV7670 Control Module
 * 
 * ��ģ���ṩOV7670����ͷ�Ļ��������ź�
 * ������λ���ƺ���ʱ������
 * SCCB������PS��ͨ��I2C���������
 */

`timescale 1ns / 1ps

module ov7670_controller (
    // ȫ��ʱ�Ӻ͸�λ
    input wire clk_100mhz,        // 100MHz����ʱ��
    input wire reset_n,           // ϵͳ��λ���͵�ƽ��Ч��
    
    // �����ź�
    input wire enable,            // ʹ���źţ���PS����
    input wire [1:0] power_mode,  // ��Դģʽ����
    
    // ����ͷ�����ź�
    output reg camera_reset_n,    // ����ͷ��λ���͵�ƽ��Ч��
    output reg camera_pwdn,       // ����ͷ������ƣ��ߵ�ƽ��Ч��
    output wire camera_xclk       // ����ͷ��ʱ�� (24MHz)
);

    // ״̬����
    localparam STATE_RESET = 2'b00;
    localparam STATE_INIT  = 2'b01;
    localparam STATE_IDLE  = 2'b10;
    localparam STATE_RUN   = 2'b11;
    
    // ��������״̬�Ĵ���
    reg [1:0] state;
    reg [23:0] counter;
    
    // ʱ�ӷ�Ƶ�� (100MHz -> 24MHz) 
    reg [1:0] clk_div;
    assign camera_xclk = clk_div[1]; // 24MHz (100MHz����4�ķ�Ƶ)
    
    // ʱ�ӷ�Ƶ
    always @(posedge clk_100mhz or negedge reset_n) begin
        if (!reset_n)
            clk_div <= 2'b00;
        else
            clk_div <= clk_div + 1'b1;
    end
    
    // ��״̬��
    always @(posedge clk_100mhz or negedge reset_n) begin
        if (!reset_n) begin
            // ��λ״̬
            state <= STATE_RESET;
            counter <= 24'd0;
            camera_reset_n <= 1'b0;  // ���λ
            camera_pwdn <= 1'b1;     // ����ģʽ
        end
        else begin
            case (state)
                STATE_RESET: begin
                    // ��ʼ��λ״̬���ȴ�5ms
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
                    // ��ʼ�����У��ͷŸ�λ���ȴ�10ms
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
                    // ����״̬�����ʹ�ܣ����������״̬
                    camera_reset_n <= 1'b1;
                    camera_pwdn <= ~enable; // ���ʹ�ܣ����˳�����ģʽ
                    
                    if (enable)
                        state <= STATE_RUN;
                end
                
                STATE_RUN: begin
                    // ����״̬
                    camera_reset_n <= 1'b1;
                    
                    // ���ݵ�Դģʽ����PWDN
                    case (power_mode)
                        2'b00: camera_pwdn <= 1'b0; // ��������ģʽ
                        2'b01: camera_pwdn <= 1'b0; // ��������ģʽ
                        2'b10: camera_pwdn <= 1'b1; // �͹���ģʽ
                        2'b11: camera_pwdn <= 1'b1; // ����ģʽ
                    endcase
                    
                    // ������ã����ؿ���״̬
                    if (!enable)
                        state <= STATE_IDLE;
                end
                
                default: state <= STATE_RESET;
            endcase
        end
    end

endmodule 