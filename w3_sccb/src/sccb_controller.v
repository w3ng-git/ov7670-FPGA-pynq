module sccb_controller #(
    parameter C_SCCB_FREQ_KHZ = 100,       // SCCBʱ��Ƶ�ʣ�Ĭ��100KHz
    parameter C_CLK_FREQ_MHZ = 100         // ϵͳʱ��Ƶ�ʣ�Ĭ��100MHz
) (
    input  wire        clk,                // ϵͳʱ��
    input  wire        rst_n,              // �첽��λ���͵�ƽ��Ч
    
    // �Ĵ����ӿ�
    input  wire [31:0] ctrl_reg,           // ���ƼĴ���
    output reg  [31:0] status_reg,         // ״̬�Ĵ���
    input  wire [31:0] tx_data,            // ��������
    output reg  [31:0] rx_data,            // ��������
    output reg         rx_data_valid,       // ����������Ч��־
    input  wire [7:0]  slave_addr,         // �ӻ���ַ
    input  wire [7:0]  reg_addr,           // �ӻ��Ĵ�����ַ
    input  wire        wr_pulse,           // д��������
    input  wire        rd_pulse,           // ����������
    
    // SCCB�ӿ�
    output wire        scl_o,              // SCL���
    input  wire        scl_i,              // SCL����
    output wire        scl_t,              // SCL��̬����
    output wire        sda_o,              // SDA���
    input  wire        sda_i,              // SDA����
    output wire        sda_t,              // SDA��̬����
    
    // �ж�
    output reg         sccb_irq            // �ж��ź�
);

    // ���ƼĴ���λ����
    localparam CTRL_START_BIT      = 0;    // д��������λ
    localparam CTRL_READ_BIT       = 1;    // ����������λ
    localparam CTRL_STOP_BIT       = 2;    // ֹͣλ
    localparam CTRL_ACK_BIT        = 3;    // Ӧ�����λ
    localparam CTRL_IRQ_EN_BIT     = 4;    // �ж�ʹ��λ
    
    // ״̬�Ĵ���λ����
    localparam STAT_BUSY_BIT       = 0;    // æ״̬λ
    localparam STAT_TRANS_DONE_BIT = 1;    // �������λ
    localparam STAT_ACK_ERR_BIT    = 2;    // Ӧ�����λ
    localparam STAT_ARB_LOST_BIT   = 3;    // �ٲö�ʧλ
    
    // ��Ƶ������(100KHzʱ��)
    reg clk_div;                           // ��Ƶ���SCLʱ��
    reg [9:0] cnt_clk;                     // ��Ƶ����������չ��10λ��֧�ָ���ķ�Ƶֵ
    localparam cnt_max_100khz = ((C_CLK_FREQ_MHZ * 1000) / (C_SCCB_FREQ_KHZ * 2)) - 1;
    
    // ״̬������
    reg [4:0] state;
    
    // ״̬����
    localparam
        IDLE          = 5'd0,  // ����
        START         = 5'd1,  // ��ʼλ
        W_SLAVE_ADDR  = 5'd2,  // д7λ���豸��ַ+д����0
        ACK1          = 5'd3,  // Ӧ��1
        W_BYTE_ADDR   = 5'd4,  // д8λ�ֵ�ַ
        ACK2          = 5'd5,  // Ӧ��2
        STOP          = 5'd6,  // ֹͣλ
        W_DATA        = 5'd7,  // д8λ����
        W_ACK         = 5'd8,  // дӦ��           
        STOP2         = 5'd9,  // �м�ֹͣλ
        START2        = 5'd10, // �м���ʼλ                         
        R_SLAVE_ADDR  = 5'd11, // д7λ���豸��ַ+������1 
        R_ACK         = 5'd12, // ��Ӧ�� 
        R_DATA        = 5'd13, // ��8λ����λ        
        N_ACK         = 5'd14; // ��Ӧ��
    
    // λ�����������ݼĴ���
    reg [3:0] cnt_bit;          // λ������
    reg [7:0] w_data_buf;       // д�����ݼĴ���
    reg [7:0] r_data_buf;       // �������ݼĴ���
    reg [7:0] w_slave_addr_buf; // ���豸��ַ�Ĵ�����д��
    reg [7:0] r_slave_addr_buf; // ���豸��ַ�Ĵ���������
    reg [7:0] byte_addr_buf;    // �ֵ�ַ�Ĵ���
    
    // �����ź�
    reg work_en;                // ����ʹ���ź�
    reg work_done;              // ��������ź�
    
    // SDA�����ź�
    reg sda_oe;                 // SDA���ʹ��
    reg sda_out;                // SDA���ֵ
    
    // ʱ����λ����
    wire scl_half_1;            // SCL�ߵ�ƽ�е�
    wire scl_half_0;            // SCL�͵�ƽ�е�
    wire scl_ack_jump;          // ACK״̬��תʱ��
    
    assign scl_half_1  = (cnt_clk == cnt_max_100khz >> 1 && clk_div==1'b1);     // SCL�ߵ�ƽ�е�
    assign scl_half_0  = (cnt_clk == cnt_max_100khz >> 1 && clk_div==1'b0);     // SCL�͵�ƽ�е�
    assign scl_ack_jump= ((cnt_clk ==(cnt_max_100khz >> 1)-5) && clk_div==1'b0); // SCL�͵�ƽ�е�ǰ5clk����
    
    // SCL��SDA�ӿڿ���
    assign scl_o = (state == STOP2 || state == START2) ? 1'b1 : clk_div;  // ���ظ���ʼ֮�䱣��SCL�ߵ�ƽ
    assign scl_t = 1'b0;         // SCL��Ϊ���ģʽ
    assign sda_o = sda_out;      // SDA���ֵ
    assign sda_t = ~sda_oe;      // SDA��̬���ƣ�0=�����1=���裩
    
    // ��Ƶ����������SCLʱ��
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_clk <= 10'd1;
            clk_div <= 1'b1;
        end else if (!work_en) begin
            // δ����ʱ������SCL�ߵ�ƽ
            cnt_clk <= 10'd1;
            clk_div <= 1'b1;
        end else if (cnt_clk == cnt_max_100khz) begin
            cnt_clk <= 10'd1;
            clk_div <= ~clk_div;
        end else 
            cnt_clk <= cnt_clk + 10'd1;
    end
    
    // �Ĵ����ݣ����⴫����;���ݲ��ȶ���
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_slave_addr_buf <= 8'b0000_0000; // 0λΪд����0
            r_slave_addr_buf <= 8'b0000_0001; // 0λΪ������1
            byte_addr_buf    <= 8'b0;
            w_data_buf       <= 8'b0;
        end else if (wr_pulse || rd_pulse) begin
            w_slave_addr_buf [7:1] <= slave_addr[6:0]; // ֻʹ��7λ��ַ
            r_slave_addr_buf [7:1] <= slave_addr[6:0]; // ֻʹ��7λ��ַ
            w_data_buf       <= tx_data[7:0];
            byte_addr_buf    <= reg_addr;
        end
    end
    
    // ״̬��
    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            state         <= IDLE;
            sda_oe        <= 1'b0; // SDAĬ��Ϊ����̬�����ⲿ����Ϊ�ߣ�
            sda_out       <= 1'b1; // SDAĬ�����1
            work_en       <= 1'b0;
            work_done     <= 1'b0;
            cnt_bit       <= 4'd0;
            rx_data       <= 32'h0;
            rx_data_valid <= 1'b0;
            status_reg    <= 32'h0;
            sccb_irq      <= 1'b0;
        end else
            case(state)
                //---------------------����----------------------//
                IDLE: begin
                    sda_oe    <= 1'b0; // SDAΪ����̬
                    sda_out   <= 1'b1; // ���1������̬��
                    work_en   <= 1'b0; // δ����
                    work_done <= 1'b0; // �����ɱ�־
                    status_reg[STAT_BUSY_BIT] <= 1'b0;  // ���æ״̬
                    status_reg[STAT_TRANS_DONE_BIT] <= 1'b0; // �����ɱ�־
                    
                    if (wr_pulse || rd_pulse) begin
                        state   <= START;
                        work_en <= 1'b1; // ��ʼ����
                        status_reg[STAT_BUSY_BIT] <= 1'b1;  // ����æ״̬
                    end
                end 
                
                //--------------------��ʼλ--------------------//
                START: begin
                    sda_oe <= 1'b1; // SDAΪ���ģʽ
                    rx_data_valid <= 1'b0; // ���������Ч��־
                    
                    if (scl_half_1) begin
                        sda_out <= 1'b0; // SDA�����ʼλ0
                        state <= W_SLAVE_ADDR;
                        cnt_bit <= 4'd0;
                    end else begin
                        sda_out <= 1'b1; // ����SDA�ߵ�ƽֱ��scl_half_1
                    end
                end
                
                //--------------7bit�ӵ�ַ+д����0---------------//
                W_SLAVE_ADDR: begin
                    sda_oe <= 1'b1; // SDAΪ���ģʽ
                    if (scl_half_0) begin
                        if (cnt_bit != 4'd8) begin
                            sda_out <= w_slave_addr_buf[7-cnt_bit]; // SDA����豸��ַ���Ӹߵ��ͣ�
                            cnt_bit <= cnt_bit + 4'd1;
                        end else begin
                            state   <= ACK1;
                            cnt_bit <= 4'd0;
                        end
                    end
                end
                
                //--------------------Ӧ��1---------------------//
                ACK1: begin 
                    sda_oe <= 1'b0; // SDAΪ����ģʽ���ȴ��ӻ�Ӧ��
                    
                    if (scl_ack_jump) 
                        state <= W_BYTE_ADDR;
                end
                
                //-----------------8bit�ֽڵ�ַ-----------------//
                W_BYTE_ADDR: begin
                    sda_oe <= 1'b1; // SDAΪ���ģʽ
                    if (scl_half_0) begin
                        if (cnt_bit != 4'd8) begin
                            sda_out <= byte_addr_buf[7-cnt_bit]; // SDA����ֽڵ�ַ���Ӹߵ��ͣ�
                            cnt_bit <= cnt_bit + 4'd1;
                        end else begin
                            state   <= ACK2;
                            cnt_bit <= 4'd0;
                        end
                    end
                end
                
                //--------------------Ӧ��2---------------------//
                ACK2: begin 
                    sda_oe <= 1'b0; // SDAΪ����ģʽ���ȴ��ӻ�Ӧ��
                    
                    if (scl_ack_jump) begin
                        if (rd_pulse || ctrl_reg[CTRL_READ_BIT]) begin
                            // ��������Ҫ��ֹͣ��������ʼ
                            state   <= STOP2;
                            sda_oe  <= 1'b1; // SDAתΪ���ģʽ
                            sda_out <= 1'b0; // ֹͣλ��Ҫ������������
                        end else begin
                            // д����ֱ�ӷ�������
                            state   <= W_DATA;
                        end
                    end
                end
                
                //--------------------д����--------------------//
                W_DATA: begin               
                    sda_oe <= 1'b1; // SDAΪ���ģʽ
                    if (scl_half_0) begin
                        if (cnt_bit != 4'd8) begin
                            sda_out <= w_data_buf[7-cnt_bit]; // SDA���д�����ݣ��Ӹߵ��ͣ�
                            cnt_bit <= cnt_bit + 4'd1;
                        end else begin
                            state   <= W_ACK;
                            cnt_bit <= 4'd0;
                        end
                    end
                end
                
                //-------------------дӦ��---------------------//
                W_ACK: begin 
                    sda_oe <= 1'b0; // SDAΪ����ģʽ���ȴ��ӻ�Ӧ��
                    
                    if (scl_ack_jump) begin
                        state   <= STOP;
                        sda_oe  <= 1'b1; // SDAתΪ���ģʽ
                        sda_out <= 1'b0; // ֹͣλ��Ҫ������������
                    end
                end
                
                //------------------ֹͣλ----------------------//
                STOP: begin
                    sda_oe <= 1'b1; // SDAΪ���ģʽ
                    // ���ô�����ɱ�־���жϣ�ͬʱ���æ״̬λ
                    status_reg[STAT_TRANS_DONE_BIT] <= 1'b1;
                    status_reg[STAT_BUSY_BIT] <= 1'b0;  // ���æ״̬
                    
                    if (scl_half_1) begin
                        sda_out   <= 1'b1; // SDA���ߣ����ֹͣλ
                        work_done <= 1'b1; // ���������ź���1
                        work_en   <= 1'b0; // ֹͣ����
                        state     <= IDLE;
                        
                        // �����ж��ź�
                        if (ctrl_reg[CTRL_IRQ_EN_BIT])
                            sccb_irq <= 1'b1;
                    end else begin
                        sda_out <= 1'b0; // SCL�ߵ�ƽǰSDA���ֵ�
                    end
                end
                
                //------------------�м�ֹͣλ------------------//
                STOP2: begin
                    sda_oe <= 1'b1; // SDAΪ���ģʽ
                    // ע���״̬����ı�work_en������Ϊ1����Ϊ����������û���
                    
                    if (scl_half_1) begin
                        sda_out <= 1'b1; // SDA���ߣ�����м�ֹͣλ
                        state <= START2;
                    end else begin
                        sda_out <= 1'b0; // SCL�ߵ�ƽǰSDA���ֵ�
                    end
                end
                
                //-------------------��ʼλ2--------------------//
                START2: begin
                    sda_oe <= 1'b1; // SDAΪ���ģʽ
                    // �ڴ�״̬����SCL�ߵ�ƽ��ֱ��SDA�½��ٿ�ʼSCLʱ��
                    
                    if (scl_half_1) begin
                        sda_out <= 1'b0; // SDA�����ʼλ0
                        state <= R_SLAVE_ADDR;
                        cnt_bit <= 4'd0;
                    end else begin
                        sda_out <= 1'b1; // SCL�ߵ�ƽǰSDA���ָߣ�ֱ�������
                    end
                end
                
                //--------------7bit�ӵ�ַ+������1---------------//
                R_SLAVE_ADDR: begin
                    sda_oe <= 1'b1; // SDAΪ���ģʽ
                    if (scl_half_0) begin
                        if (cnt_bit != 4'd8) begin
                            sda_out <= r_slave_addr_buf[7-cnt_bit]; // SDA����豸��ַ���Ӹߵ��ͣ�
                            cnt_bit <= cnt_bit + 4'd1;
                        end else begin
                            state   <= R_ACK;
                            cnt_bit <= 4'd0;
                        end
                    end
                end
                
                //-------------------��Ӧ��---------------------//
                R_ACK: begin 
                    sda_oe <= 1'b0; // SDAΪ����ģʽ���ȴ��ӻ�Ӧ��
                    
                    if (scl_ack_jump) 
                        state <= R_DATA;
                end
                
                //-----------------������-----------------//
                R_DATA: begin
                    sda_oe <= 1'b0; // SDAΪ����ģʽ����������
                    
                    if (scl_half_1 && cnt_bit!=4'd8) begin      
                        r_data_buf[7-cnt_bit] <= sda_i; // ��SCL�ߵ�ƽ�е��ȡ����
                        cnt_bit <= cnt_bit + 4'd1;
                    end 
                    
                    if (scl_ack_jump && cnt_bit==4'd8) begin          
                        rx_data <= {24'h0, r_data_buf}; // �����ȡ�����ݵ�����Ĵ���
                        rx_data_valid <= 1'b1;          // ����������Ч��־
                        state <= N_ACK;                 // ��ת����Ӧ��״̬
                        cnt_bit <= 4'd0;                // ����λ������
                    end
                end
                
                //--------------------��Ӧ��--------------------//  
                N_ACK: begin 
                    sda_oe <= 1'b1; // SDAΪ���ģʽ
                    
                    if (scl_half_0)
                        sda_out <= 1'b1; // ������Ӧ��(1)
                        
                    if (scl_ack_jump) begin
                        state <= STOP;
                        sda_out <= 1'b0; // ֹͣλ��Ҫ������������
                    end
                end
                
                default: state <= IDLE;
            endcase 
    end
    
endmodule 