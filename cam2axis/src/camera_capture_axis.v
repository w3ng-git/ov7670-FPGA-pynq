/*
 * OV7670 Camera Capture with AXI Stream Interface
 * 
 * ��ģ�齫OV7670����ͷ����ת��ΪAXI Stream��ʽ
 * ������AXI VDMA���ӣ���ͼ�����ݴ��䵽PS DDR�ڴ�
 * 
 * RGB565��ʽתRGBA��ʽ��
 * RGB565: RRRRRGGG GGGBBBBB (�����ֽڱ�ʾһ������)
 * RGBA:   RRRRRRRR GGGGGGGG BBBBBBBB AAAAAAAA (�ĸ��ֽڱ�ʾһ������)
 */

`timescale 1ns / 1ps

module camera_capture_axis #(
    // �û������ò���
    parameter FRAME_WIDTH  = 640,  // ͼ���� (Ĭ��640��) 
    parameter FRAME_HEIGHT = 480,  // ͼ��߶� (Ĭ��480��)
    parameter FIFO_DEPTH   = 16    // FIFO��Ȳ���
)(
    // ȫ��ʱ�Ӻ͸�λ
    input wire axi_clk,                  // AXIʱ��
    input wire aresetn,                  // AXI��λ���͵�ƽ��Ч��
    
    // ����ͷ�ӿ�
    input wire camera_pclk,             // ����ʱ��
    input wire camera_href,             // ����Ч�ź�
    input wire camera_vsync,            // ��ͬ���ź�
    input wire [7:0] camera_data,       // ��������
    
    // AXI Stream���ӿ� - ����VDMA
    output reg m_axis_tvalid,           // ������Ч
    output reg [31:0] m_axis_tdata,     // 32λ���ݣ�RGBA��ʽ��
    output reg m_axis_tlast,            // �н�����־
    output reg m_axis_tuser,            // ֡��ʼ��־ (VDMA����)
    input wire m_axis_tready            // ����ģ�����
);

    // ============== �źŶ��� ==============
    // ����ͷ�źżĴ��ӳ�
    reg camera_href_1 = 1'b0;
    reg camera_href_2 = 1'b0;
    reg camera_vsync_1 = 1'b0;
    reg camera_vsync_2 = 1'b0;
    
    // ��Ե����ź�
    wire camera_href_rising;
    wire camera_href_falling;
    wire camera_vsync_rising;
    wire camera_vsync_falling;
    
    // ���ش����־
    reg byte_toggle = 1'b0;             // �л��ֽڱ�־�����ֽ�/���ֽڣ�
    
    // RGB565ԭʼ���ݴ洢
    reg [7:0] cam_data_high = 8'b0;     // ���ֽ� (RRRRRGGG)
    reg [7:0] cam_data_low = 8'b0;      // ���ֽ� (GGGBBBBB)
    
    // RGB�������غͿ����ź�
    reg pixel_valid = 1'b0;             // ������Ч��־
    
    // ���м���������ź�
    reg [11:0] h_cnt = 12'b0;           // �м���
    reg [11:0] v_cnt = 12'b0;           // �м���
    reg is_first_pixel = 1'b0;         // ֡��һ�����ر�־
    
    // �п�ȸ���
    reg [11:0] line_width = 12'b0;      // ��ǰ�п�� (camera_pclk��)

    // ============== AXIʱ�����hrefͬ���ͱ�Ե��� ==============
    reg [2:0] href_sync = 3'b0;         // AXI���hrefͬ���Ĵ���
    wire href_rising_axi;               // AXI���href������
    
    always @(posedge axi_clk or negedge aresetn) begin
        if (!aresetn) begin
            href_sync <= 3'b0;
        end else begin
            href_sync <= {href_sync[1:0], camera_href};
        end
    end
    
    // AXI���href�����ؼ��
    assign href_rising_axi = (href_sync[1] == 1'b1 && href_sync[2] == 1'b0);
    
    // ============== ����ͷ�ź�ͬ�����Ե��� ==============
    // �ź��ӳ�һ������ - �޸�Ϊ��pclk�����ز���
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
    
    // ��Ե���
    assign camera_href_rising = (camera_href_1 & ~camera_href_2);
    assign camera_href_falling = (~camera_href_1 & camera_href_2);
    assign camera_vsync_rising = (camera_vsync_1 & ~camera_vsync_2);
    assign camera_vsync_falling = (~camera_vsync_1 & camera_vsync_2);
    
    // ============== RGB565���ݴ��� ==============
    // RGB565��ʽ���մ��� - �޸�Ϊ��pclk�����ز���
    // ��pclk�����ؼ�⵽href��Чʱ����ֱ�ӽ����ֽ��л�
    
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            byte_toggle <= 1'b0;
            cam_data_high <= 8'b0;
            cam_data_low <= 8'b0;
            pixel_valid <= 1'b0;
            is_first_pixel <= 1'b0;
        end else if (camera_vsync) begin  // ֱ��ʹ��camera_vsync
            // ��ͬ���ڼ�����
            byte_toggle <= 1'b0;
            pixel_valid <= 1'b0;
            is_first_pixel <= 1'b0;
        end else if (camera_href) begin  // ֱ��ʹ��camera_href
            // href��Чʱֱ���л�byte_toggle
            byte_toggle <= ~byte_toggle;
            
            if (byte_toggle) begin
                // toggle=1ʱ���յ��ڶ����ֽڣ����ֽڣ�
                cam_data_low <= camera_data;
                
                // ������������λ��Ч��־
                pixel_valid <= 1'b1;
                
                // ����Ƿ�Ϊ֡��һ������
                if (h_cnt == 12'd0 && v_cnt == 12'd0) begin
                    is_first_pixel <= 1'b1;
                end else begin
                    is_first_pixel <= 1'b0;
                end
            end else begin
                // toggle=0ʱ���յ���һ���ֽڣ����ֽڣ�
                cam_data_high <= camera_data;
                pixel_valid <= 1'b0;
            end
        end else begin
            // �м�϶�ڼ����ñ�־
            byte_toggle <= 1'b0;
            pixel_valid <= 1'b0;
            is_first_pixel <= 1'b0;
        end
    end
    
    // ============== ���м��� ==============
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            h_cnt <= 12'b0;
            v_cnt <= 12'b0;
        end else if (camera_vsync) begin  // ֱ��ʹ��camera_vsync
            // ��ͬ���ڼ����ü���
            h_cnt <= 12'b0;
            v_cnt <= 12'b0;
        end else if (!camera_href && camera_href_1) begin  // ���href�½���
            // һ�н����������м����������м���
            h_cnt <= 12'b0;
            v_cnt <= v_cnt + 1'b1;
        end else if (camera_href && byte_toggle) begin  // ֱ��ʹ��camera_href
            // ÿ�����ֽ����һ�����أ������м���
            h_cnt <= h_cnt + 1'b1;
        end
    end
    
    // ============== �п�ȼ�� ==============
    // ��¼�п�����ڼ���н��� - �޸�Ϊ��pclk�����ز���
    reg [11:0] h_cnt_temp = 12'b0;
    
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            h_cnt_temp <= 12'b0;
            line_width <= 12'b0;
        end else if (camera_vsync) begin  // ֱ��ʹ��camera_vsync
            // ��ͬ���ڼ�����
            h_cnt_temp <= 12'b0;
            line_width <= 12'b0;
        end else if (camera_href) begin  // ֱ��ʹ��camera_href
            // ֻ�ڽ��յ��������غ����Ӽ���
            // �������ȷ����h_cnt������������ȫ��ͬ
            if (byte_toggle && pixel_valid) 
                h_cnt_temp <= h_cnt_temp + 1'b1;
        end else if (!camera_href && camera_href_1) begin  // ���href�½���
            // һ�н�������¼�п��
            line_width <= h_cnt_temp;
            h_cnt_temp <= 12'b0;
        end
    end
    
    // ============== ��ʱ����FIFO���� ==============
    // FIFO���ݽṹ - ÿ��Ԫ�ذ���RGB565ԭʼ���ݺͿ����ź�
    reg [17:0] fifo_data[0:FIFO_DEPTH-1]; // {is_first_pixel, cam_data_high, cam_data_low}
    reg [$clog2(FIFO_DEPTH):0] wr_ptr = 0; // дָ�룬��FIFO_DEPTH��һλ���������
    reg [$clog2(FIFO_DEPTH):0] rd_ptr = 0; // ��ָ�룬��FIFO_DEPTH��һλ���ڿռ��
    
    // FIFO״̬�ź�
    wire fifo_empty; 
    wire fifo_full;
    wire fifo_almost_full;
    wire [$clog2(FIFO_DEPTH):0] fifo_count;
    
    // FIFO״̬����
    assign fifo_count = wr_ptr - rd_ptr;
    assign fifo_empty = (wr_ptr == rd_ptr);
    assign fifo_full = (fifo_count >= FIFO_DEPTH); 
    assign fifo_almost_full = (fifo_count >= FIFO_DEPTH-2);
    
    // ��ĩβ���ر�� (������FIFO�б���н���)
    reg is_last_pixel = 1'b0;
    
    // ��camera_pclk�����н���������
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            is_last_pixel <= 1'b0;
        end else if (camera_vsync) begin
            is_last_pixel <= 1'b0;
        end else if (camera_href) begin
            // �����ǰ�м�������Ԥ���ȼ�1����Ϊ��ĩ����
            is_last_pixel <= (h_cnt == FRAME_WIDTH - 1'b1) ;// && byte_toggle && pixel_valid;
        end else begin
            is_last_pixel <= 1'b0;
        end
    end
    
    // ============== FIFOд�߼� (camera_pclk��) ==============
    reg fifo_wr_en = 1'b0;
    reg [17:0] fifo_din = 18'b0; // {is_first_pixel, is_last_pixel, cam_data_high, cam_data_low}
    
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            fifo_wr_en <= 1'b0;
            fifo_din <= 18'b0;
        end else begin
            // Ĭ�Ͻ���д��
            fifo_wr_en <= 1'b0;
            
            // ����������������FIFOδ��ʱд��FIFO
            if (pixel_valid && !fifo_almost_full) begin
                fifo_din <= {is_first_pixel, is_last_pixel, cam_data_high, cam_data_low};
                fifo_wr_en <= 1'b1;
            end
        end
    end
    
    // ����дָ��
    always @(posedge camera_pclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_ptr <= 0;
        end else if (fifo_wr_en && !fifo_full) begin
            // д��FIFO������дָ��
            fifo_data[wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= fifo_din;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end
    
    // ============== FIFO���߼� (axi_clk��) ==============
    reg fifo_rd_en = 1'b0;
    reg [17:0] fifo_dout = 18'b0;
    reg fifo_valid = 1'b0;
    
    // ���¶�ָ��Ͷ�ȡ����
    always @(posedge axi_clk or negedge aresetn) begin
        if (!aresetn) begin
            rd_ptr <= 0;
            fifo_dout <= 18'b0;
            fifo_valid <= 1'b0;
        end else begin
            // Ĭ����Ч
            fifo_valid <= 1'b0;
            
            // ��FIFO�ǿ����ϴ������ѱ��������δ��ȡ����ʱ���Զ�ȡ
            if (!fifo_empty && (!fifo_valid || (m_axis_tvalid && m_axis_tready))) begin
                fifo_dout <= fifo_data[rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
                rd_ptr <= rd_ptr + 1'b1;
                fifo_valid <= 1'b1;
            end else if (m_axis_tvalid && m_axis_tready) begin
                // �����ѱ�AXI���ܣ������Ч��־
                fifo_valid <= 1'b0;
            end
        end
    end
    
    // ����FIFO����
    wire fifo_first_pixel = fifo_dout[17];
    wire fifo_last_pixel = fifo_dout[16];
    wire [7:0] fifo_data_high = fifo_dout[15:8];
    wire [7:0] fifo_data_low = fifo_dout[7:0];
    
    // RGBA����߼�
    wire [4:0] rgb_r = fifo_data_high[7:3];                 // ��ɫ���� (5λ)
    wire [5:0] rgb_g = {fifo_data_high[2:0], fifo_data_low[7:5]}; // ��ɫ���� (6λ)
    wire [4:0] rgb_b = fifo_data_low[4:0];                  // ��ɫ���� (5λ)
    
    // RGB565��RGBA��ת������߼�
    wire [7:0] R8 = {rgb_r, rgb_r[4:2]};      // 5λ��չ��8λ����λ���Ƶ���λ
    wire [7:0] G8 = {rgb_g, rgb_g[5:4]};      // 6λ��չ��8λ����λ���Ƶ���λ
    wire [7:0] B8 = {rgb_b, rgb_b[4:2]};      // 5λ��չ��8λ����λ���Ƶ���λ
    wire [31:0] rgba_data = {R8, G8, B8, 8'hFF}; // ��ϳ�32λRGBA
    
    // AXI Stream״̬��
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
                    // ֻ�е�FIFO����Ч����ʱ����������
                    if (fifo_valid) begin
                        m_axis_tdata <= rgba_data;  // ʹ������߼�ֱ������RGBA
                        m_axis_tvalid <= 1'b1;
                        
                        // ����tuser (֡��ʼ��־)
                        m_axis_tuser <= fifo_first_pixel;
                        
                        // ����tlast (�н�����־) - ����FIFO�еı��
                        m_axis_tlast <= fifo_last_pixel;
                        
                        axi_state <= SEND;
                    end else begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast <= 1'b0;
                        m_axis_tuser <= 1'b0;
                    end
                end
                
                SEND: begin
                    // �ɹ����ֺ���������źŲ�����IDLE״̬
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