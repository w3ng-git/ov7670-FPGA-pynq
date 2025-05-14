/*
 * OV7670 Camera Capture Testbench - RGB565תRGBAģʽ
 * 
 * �˲���̨ʹ��camDataMockģ��ģ��OV7670����ͷ�����
 * ������֤camera_capture_axisģ��Ĺ���
 */

`timescale 1ns / 1ps

module camera_capture_axis_tb;

    // ���Բ���
    parameter CLK_PERIOD_AXI = 10;       // AXIʱ�����ڣ�10ns (100MHz)
    parameter CLK_PERIOD_XCLK = 41.67;   // ����ͷʱ�����ڣ�41.67ns (24MHz)
    parameter FRAME_WIDTH  = 8;          // ͼ���ȣ�8��
    parameter FRAME_HEIGHT = 4;          // ͼ��߶ȣ�4��
    
    // ʱ�Ӻ͸�λ�ź�
    reg axi_clk;
    reg xclk;
    reg aresetn;
    
    // ����ͷģ��ӿ��ź�
    wire camera_pclk;
    wire camera_href;
    wire camera_vsync;
    wire [7:0] camera_data;
    wire camera_frame_done;    // ���frame_done�ź�
    wire [1:0] camera_current_frame; // ���current_frame�ź�
    
    // AXI Stream�ź�
    wire m_axis_tvalid;
    wire [31:0] m_axis_tdata;
    wire m_axis_tlast;
    wire m_axis_tuser;
    reg m_axis_tready;
    
    // ���Լ�������״̬
    integer data_count;        // ���յ������ݰ�����
    integer tuser_count;       // tuser�ߵ�ƽ����
    integer tlast_count;       // tlast�ߵ�ƽ����
    integer error_count;       // �������
    integer frame_count;       // ֡����
    
    // ʵ����OV7670����ͷģ��ģ��
    camDataMock #(
        .PCLK_FREQ_MHZ(24),
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT),
        .FRAMES_TO_SEND(10)
    ) camera_mock (
        .xclk(xclk),
        .reset_n(aresetn),
        .enable(aresetn),  // ��λ����������
        .pclk(camera_pclk),
        .vsync(camera_vsync),
        .href(camera_href),
        .data_out(camera_data),
        .frame_done(camera_frame_done),
        .current_frame(camera_current_frame)
    );
    
    // ʵ��������ģ��
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
    
    // ����AXIʱ�� (100MHz)
    initial begin
        axi_clk = 0;
        forever #(CLK_PERIOD_AXI/2) axi_clk = ~axi_clk;
    end
    
    // ����XCLK (24MHz)
    initial begin
        xclk = 0;
        forever #(CLK_PERIOD_XCLK/2) xclk = ~xclk;
    end
    
    // ����AXI Stream���
    always @(posedge axi_clk) begin
        if (aresetn && m_axis_tvalid && m_axis_tready) begin
            data_count = data_count + 1;
            
            // ���tuser (SOF)
            if (m_axis_tuser) begin
                tuser_count = tuser_count + 1;
                frame_count = frame_count + 1;
                $display("\n[%0t] --- ��ʼ���յ�%0d֡ ---", $time, frame_count);
            end
            
            // ���tlast (EOL)
            if (m_axis_tlast) begin
                tlast_count = tlast_count + 1;
                $display("[%0t] �н�����־(TLAST), �����ݰ���: %0d", $time, tlast_count % FRAME_HEIGHT);
            end
            
            // ��ȡ����ʾRGBA��������
            $display("[%0t] ���ݰ�[%0d]: 0x%08x, TLAST=%0d, TUSER=%0d", 
                     $time, data_count, m_axis_tdata, m_axis_tlast, m_axis_tuser);
            $display("  RGBA����: R=0x%02x, G=0x%02x, B=0x%02x, A=0x%02x", 
                     m_axis_tdata[31:24], m_axis_tdata[23:16],
                     m_axis_tdata[15:8], m_axis_tdata[7:0]);
        end
    end
    
    // ���֡�߽��״̬
    always @(posedge camera_vsync or posedge camera_frame_done) begin
        if (aresetn) begin
            if (camera_frame_done) begin
                $display("\n[%0t] ALL FRAMES COMPLETED - frame_done signal detected", $time);
                $display("  Total frames sent: %0d", camera_current_frame);
            end else if (frame_count > 0) begin
                $display("\n[%0t] VSYNC detected - Frame %0d completed (camera reporting frame: %0d)", 
                         $time, frame_count, camera_current_frame);
                $display("  Data packets: %0d, TLAST signals: %0d", data_count, tlast_count);
                
                // ���ÿ֡�е�tuser����
                if (tuser_count != frame_count) begin
                    $display("  ERROR: Expected tuser count = %0d, got %0d", frame_count, tuser_count);
                    error_count = error_count + 1;
                end
                
                // ���ÿ֡�е�tlast����
                if (tlast_count != (frame_count * FRAME_HEIGHT)) begin
                    $display("  ERROR: Expected tlast count = %0d, got %0d", 
                             frame_count * FRAME_HEIGHT, tlast_count);
                    error_count = error_count + 1;
                end
            end
        end
    end
    
    // �����Թ���
    initial begin
        // ��ʼ���źźͼ�����
        aresetn = 0;
        m_axis_tready = 1;
        
        data_count = 0;
        tuser_count = 0;
        tlast_count = 0;
        error_count = 0;
        frame_count = 0;
        
        // ��λ�׶�
        #100;
        aresetn = 1;
        
        // ���в��ԣ�ֱ����⵽frame_done�źŻ�ʱ
        $display("\n[%0t] Starting to capture frames...", $time);
        
        // �ȴ�ֱ��frame_done�źű�������ʱ
        wait(camera_frame_done == 1 || $time > 10000000);
        
        if (camera_frame_done) begin
            $display("\n[%0t] Detected frame_done signal after capturing %0d frames", 
                    $time, camera_current_frame);
        end else begin
            $display("\n[%0t] Test timeout reached without detecting frame_done", $time);
            error_count = error_count + 1;
        end
        
        // ����VDMA��ͣ��� - ֻ�е��������������ʱ�������ⲿ��
        if(0) begin  // ������������Ϊ0�������ⲿ�ֲ���
            $display("\n[%0t] Testing VDMA pause scenario...", $time);
            m_axis_tready = 0;
            #500000;
            
            $display("[%0t] Resuming VDMA reception (tready=1)", $time);
            m_axis_tready = 1;
            #5000000;
        end
        
        // ������Խ��
        $display("\n--- Test Summary ---");
        $display("Frames received: %0d", frame_count);
        $display("Frames sent by camera: %0d", camera_current_frame);
        $display("Data packets received: %0d", data_count);
        $display("SOF signals (tuser) detected: %0d", tuser_count);
        $display("EOL signals (tlast) detected: %0d", tlast_count);
        $display("Errors detected: %0d", error_count);
        
        // ��֤������
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