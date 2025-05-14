`timescale 1ns / 1ps

module w3_sccb_tb;

    // ʱ�Ӻ͸�λ�ź�
    reg         clk;
    reg         rst_n;
    
    // AXI4-Lite�ӿ��ź�
    reg [4:0]   s_axi_awaddr;   // 5λ��ַ���ߣ�C_S00_AXI_ADDR_WIDTH��
    reg [2:0]   s_axi_awprot;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg [31:0]  s_axi_wdata;    // 32λ�������ߣ�C_S00_AXI_DATA_WIDTH��
    reg [3:0]   s_axi_wstrb;    // 4λдѡͨ
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg [4:0]   s_axi_araddr;   // 5λ��ַ����
    reg [2:0]   s_axi_arprot;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;    // 32λ��������
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;
    
    // SCCB�ӿ��ź�
    wire        scl_o;          // SCL���
    wire        scl_i;          // SCL����
    wire        scl_t;          // SCL��̬����
    wire        sda_o;          // SDA���
    wire        sda_i;          // SDA����
    wire        sda_t;          // SDA��̬����
    wire        sccb_irq;        // �ж��ź�
    
    // SCCB�����ź�
    wire        scl;            // SCCBʱ����
    wire        sda;            // SCCB������
    
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
    
    // ����ģ��SCCB����
    assign scl = scl_t ? 1'b1 : scl_o;
    assign scl_i = scl;
    
    // �޸�SDA�������ӣ�֧��˫�����ݴ���
    // �����豸�ʹ��豸��������ʱ��SDA���ָߵ�ƽ
    // ����һ�豸�����͵�ƽʱ��SDAΪ�͵�ƽ�������߼���
    assign sda = sda_t ? 1'bz : sda_o;  // ���豸����SDA
    assign sda_i = sda;
    
    // SCCB����״̬���
    reg prev_mon_scl, prev_mon_sda;
    
    always @(posedge clk) begin
        prev_mon_scl <= scl;
        prev_mon_sda <= sda;
        
        // ���SCL��SDA�仯
        if (scl != prev_mon_scl || sda != prev_mon_sda) begin
            $display("[%0t] SCCB����״̬: SCL=%b, SDA=%b", $time, scl, sda);
        end
        
        // �����ʼ��ֹͣ����
        if (scl && prev_mon_sda && !sda)
            $display("[%0t] SCCB����: ��⵽��ʼ���� ��", $time);
        if (scl && !prev_mon_sda && sda)
            $display("[%0t] SCCB����: ��⵽ֹͣ���� ��", $time);
            
        // ��SCL�����ز���SDA
        if (scl && !prev_mon_scl)
            $display("[%0t] SCCB����: SCL��ʱSDA=%b (���ݲ���)", $time, sda);
    end
    
    // �Ĵ���ƫ��������
    localparam CTRL_REG_ADDR      = 3'h0;  // ���ƼĴ�����ַ
    localparam STATUS_REG_ADDR    = 3'h1;  // ״̬�Ĵ�����ַ
    localparam TX_DATA_REG_ADDR   = 3'h2;  // �������ݼĴ�����ַ
    localparam RX_DATA_REG_ADDR   = 3'h3;  // �������ݼĴ�����ַ
    localparam ADDR_REG_ADDR      = 3'h4;  // �豸��ַ�Ĵ�����ַ
    localparam SLAVE_REG_ADDR     = 3'h5;  // �ӻ��Ĵ�����ַ
    
    // OV7670����ͷ��ַ
    localparam OV7670_ADDR        = 8'h42 >> 1;  // OV7670��ַ��0x42 >> 1 = 0x21��
    
    // ��������ر���
    reg [31:0] read_data;       // �洢��SCCB��ȡ������
    
    // OV7670���üĴ�����ַ
    localparam REG_COM7      = 8'h12;   // ���ƼĴ���7
    localparam REG_COM10     = 8'h15;   // ���ƼĴ���10
    localparam REG_PID       = 8'h0A;   // ��ƷID���ֽ�
    localparam REG_VER       = 8'h0B;   // ��ƷID���ֽ�
    localparam REG_CLKRC     = 8'h11;   // ʱ�ӿ���
    localparam REG_RGB444    = 8'h8C;   // RGB444����
    localparam REG_COM1      = 8'h04;   // ���ƼĴ���1
    
    // ʵ����mock_ov7670_sccbģ��
    mock_ov7670_sccb mock_ov7670_sccb_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .scl      (scl),
        .sda      (sda)
    );
    
    // ʵ���������Ե�SCCBģ��
    w3_sccb_v1_0 #(
        .C_SCCB_FREQ_KHZ(100),         // ʹ��100KHz���ʽ��в���
        .C_CLK_FREQ_MHZ(100),         // ϵͳʱ��100MHz
        .C_S00_AXI_DATA_WIDTH(32),    // AXI���ݿ��32λ
        .C_S00_AXI_ADDR_WIDTH(5)      // AXI��ַ���5λ
    ) w3_sccb_v1_0_inst (
        // SCCB�ӿ�
        .scl_o(scl_o),
        .scl_i(scl_i),
        .scl_t(scl_t),
        .sda_o(sda_o),
        .sda_i(sda_i),
        .sda_t(sda_t),
        .sccb_irq(sccb_irq),
        
        // AXI�ӿ�
        .s00_axi_aclk(clk),
        .s00_axi_aresetn(rst_n),
        .s00_axi_awaddr(s_axi_awaddr),
        .s00_axi_awprot(s_axi_awprot),
        .s00_axi_awvalid(s_axi_awvalid),
        .s00_axi_awready(s_axi_awready),
        .s00_axi_wdata(s_axi_wdata),
        .s00_axi_wstrb(s_axi_wstrb),
        .s00_axi_wvalid(s_axi_wvalid),
        .s00_axi_wready(s_axi_wready),
        .s00_axi_bresp(s_axi_bresp),
        .s00_axi_bvalid(s_axi_bvalid),
        .s00_axi_bready(s_axi_bready),
        .s00_axi_araddr(s_axi_araddr),
        .s00_axi_arprot(s_axi_arprot),
        .s00_axi_arvalid(s_axi_arvalid),
        .s00_axi_arready(s_axi_arready),
        .s00_axi_rdata(s_axi_rdata),
        .s00_axi_rresp(s_axi_rresp),
        .s00_axi_rvalid(s_axi_rvalid),
        .s00_axi_rready(s_axi_rready)
    );
    
    // ʱ������
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHzʱ��
    end
    
    // ����ƽ̨��ʼ��
    initial begin
        // ��ʼ���ź�
        rst_n = 0;
        s_axi_awvalid = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;
        s_axi_wstrb = 4'hF;
        read_data = 0;
        
        // �ͷŸ�λ
        #100;
        rst_n = 1;
        #100;
        
        // ����SCCB��д�������
        test_sccb_write_then_read();
        
        // Ҳ���Ե������Զ�����
        // test_sccb_read();
        
        // �������
        #5000;
        $display("[%0t] �������!", $time);
        $finish;
    end
    
    // AXIд����
    task axi_write;
        input [4:0]  addr;
        input [31:0] data;
        integer resp_timeout;
        begin
            $display("[%0t] AXIд������ʼ - ��ַ:0x%h, ����:0x%h", $time, addr, data);
        
            // ����ַ������׼����
            s_axi_awaddr = {addr, 2'b00}; // �ֶ���
            s_axi_awprot = 3'b000;
            s_axi_wdata = data;
            s_axi_wstrb = 4'b1111; // д�������ֽ�
            
            // ͬʱ������Ч�ź�
            @(posedge clk);
            s_axi_awvalid = 1'b1;
            s_axi_wvalid = 1'b1;
            s_axi_bready = 1'b1;
            
            // �ȴ�����ͨ�����������
            while (!(s_axi_awready && s_axi_wready)) begin
                @(posedge clk);
            end
            
            // ����ͨ����������ֺ�ͬʱ������Ч�ź�
            @(posedge clk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;
            $display("[%0t] AXI��ַ������ͨ������ͬʱ���", $time);
            
            // �ȴ���Ӧ����ӳ�ʱ����
            resp_timeout = 0;
            
            // ʹ�ü�ѭ���ȴ���Ӧ��ʱ
            while (!s_axi_bvalid && resp_timeout < 100) begin
                @(posedge clk);
                resp_timeout = resp_timeout + 1;
            end
            
            if (s_axi_bvalid) begin
                @(posedge clk);
                s_axi_bready = 1'b0; // ȷ����Ӧ���
                @(posedge clk);
                s_axi_bready = 1'b1; // �ָ�Ĭ��״̬
                $display("[%0t] AXI��Ӧͨ�����ֳɹ�", $time);
            end else begin
                $display("[%0t] ����: AXI��Ӧͨ�����ֳ�ʱ! ǿ�Ƽ���ִ��", $time);
            end
            
            // �����ӳ٣�ȷ����������
            @(posedge clk);
            @(posedge clk);
            
            $display("[%0t] AXIд������� - ��ַ:0x%h, ����:0x%h, ��Ӧ��ʱ=%0d", $time, addr, data, resp_timeout);
        end
    endtask
    
    // AXI������
    task axi_read;
        input  [4:0]  addr;
        output [31:0] data;
        integer resp_timeout;
        begin
            $display("[%0t] AXI��������ʼ - ��ַ:0x%h", $time, addr);
        
            // ׼����ַ
            s_axi_araddr = {addr, 2'b00}; // �ֶ���
            s_axi_arprot = 3'b000;
            
            // ��ַͨ��
            @(posedge clk);
            s_axi_arvalid = 1'b1;
            s_axi_rready = 1'b1;
            
            // �ȴ���ַͨ���������
            wait(s_axi_arready);
            @(posedge clk);
            s_axi_arvalid = 1'b0;
            $display("[%0t] AXI����ַͨ���������", $time);
            
            // �ȴ�����ͨ�����֣���ӳ�ʱ����
            resp_timeout = 0;
            
            // ʹ�ü�ѭ���ȴ���Ӧ��ʱ
            while (!s_axi_rvalid && resp_timeout < 100) begin
                @(posedge clk);
                resp_timeout = resp_timeout + 1;
            end
            
            if (s_axi_rvalid) begin
                data = s_axi_rdata;
                @(posedge clk);
                s_axi_rready = 1'b0; // ��ɶ�ȡ
                @(posedge clk);
                s_axi_rready = 1'b1; // �ָ�Ĭ��״̬
                $display("[%0t] AXI������ͨ�����ֳɹ�", $time);
            end else begin
                data = 32'hDEADDEAD; // ����ʱ��������ֵ
                $display("[%0t] ����: AXI������ͨ�����ֳ�ʱ! ���ش�������", $time);
            end
            
            // �����ӳ٣�ȷ����������
            @(posedge clk);
            @(posedge clk);
            
            $display("[%0t] AXI��������� - ��ַ:0x%h, ����:0x%h, ��Ӧ��ʱ=%0d", $time, addr, data, resp_timeout);
        end
    endtask
    
    // �ȴ������������
    task wait_transfer_done;
        reg [31:0] status;
        integer timeout_count;
        begin
            timeout_count = 0;
            $display("[%0t] ��ʼ�ȴ�SCCB�������", $time);
            #1000; // �ȵȴ�һС��ʱ��
            
            // ���״ֱ̬����æ��ʱ
            status[0] = 1'b1; // ��ʼ��Ϊæ״̬
            while (status[0] == 1'b1 && timeout_count < 1000) begin
                axi_read(STATUS_REG_ADDR, status);
                $display("[%0t] �ȴ��������: ״̬�Ĵ���=0x%h, æ��־=%b, ��ɱ�־=%b, ����=%d", 
                         $time, status, status[0], status[1], timeout_count);
                #1000; // �ȴ�1000��ʱ�䵥λ
                timeout_count = timeout_count + 1;
            end
            
            if (timeout_count >= 1000) begin
                $display("[%0t] ����: �ȴ�������ɳ�ʱ! ���״̬=0x%h", $time, status);
            end else begin
                $display("[%0t] ���������: ״̬�Ĵ���=0x%h", $time, status);
            end
        end
    endtask
    
    // SCCB��������������
    task test_sccb_read;
        begin
            $display("[%0t] ��ʼSCCB����������", $time);
            
            // 1. �����豸��ַ (OV7670��ַ)
            axi_write(ADDR_REG_ADDR, OV7670_ADDR);
            #100;
            
            // 2. ���üĴ�����ַ (��ȡ��ƷID)
            axi_write(SLAVE_REG_ADDR, REG_PID);
            #100;
            
            // 3. ���ÿ��ƼĴ��� - ����������
            axi_write(CTRL_REG_ADDR, (1 << CTRL_READ_BIT) | (1 << CTRL_STOP_BIT));
            
            // �ȴ�SCCB�������
            wait_transfer_done();
            

            // 4. ��ȡ״̬�Ĵ�������鴫���Ƿ����
            axi_read(STATUS_REG_ADDR, read_data);
            $display("[%0t] SCCB��������״̬�Ĵ���ֵ: 0x%h", $time, read_data);
            
            // 5. ��ȡ���յ�������
            axi_read(RX_DATA_REG_ADDR, read_data);
            $display("[%0t] SCCB���������յ�������: 0x%h (����ֵ: 0x76)", $time, read_data);
            
            // ��֤��ȡ���Ĳ�ƷID�Ƿ���ȷ
            if (read_data[7:0] == 8'h76) begin
                $display("[%0t] SCCB���������Գɹ�! ��ȡ����ȷ�Ĳ�ƷID: 0x%h", $time, read_data[7:0]);
            end else begin
                $display("[%0t] SCCB����������ʧ��! ��ȡ������Ĳ�ƷID: 0x%h������ֵ: 0x76", $time, read_data[7:0]);
            end
        end
    endtask
    
    // SCCBд������������
    task test_sccb_write;
        input [7:0] reg_addr;
        input [7:0] data;
        begin
            $display("[%0t] ��ʼSCCBд�������� - �Ĵ�����ַ:0x%h, ����:0x%h", $time, reg_addr, data);
            
            // 1. �����豸��ַ (OV7670��ַ)
            axi_write(ADDR_REG_ADDR, OV7670_ADDR);
            #100;
            
            // 2. ����Ҫд��ļĴ�����ַ
            axi_write(SLAVE_REG_ADDR, reg_addr);
            #100;
            
            // 3. ����Ҫ���͵�����
            axi_write(TX_DATA_REG_ADDR, data);
            #100;
            
            // 4. ���ÿ��ƼĴ��� - ����д����������λ+ֹͣλ��
            axi_write(CTRL_REG_ADDR, (1 << CTRL_START_BIT) | (1 << CTRL_STOP_BIT));
            
            // �ȴ�SCCB�������
            wait_transfer_done();

            #10000;
            
            // 5. ��ȡ״̬�Ĵ�������鴫���Ƿ����
            axi_read(STATUS_REG_ADDR, read_data);
            $display("[%0t] SCCBд������״̬�Ĵ���ֵ: 0x%h", $time, read_data);
            
            if (read_data[STAT_TRANS_DONE_BIT] && !read_data[STAT_ACK_ERR_BIT]) begin
                $display("[%0t] SCCBд�����ɹ���� - �Ĵ���[0x%h]=0x%h", $time, reg_addr, data);
            end else begin
                $display("[%0t] SCCBд����ʧ��! ״̬�Ĵ���=0x%h", $time, read_data);
            end
        end
    endtask
    
    // SCCB��д�����������
    task test_sccb_write_then_read;
        reg [7:0] test_reg_addr;
        reg [7:0] test_data;
        reg [31:0] read_value;
        begin
            $display("[%0t] ��ʼSCCB��д�������", $time);
            
            // ѡ��һ�����ԼĴ�����ַ (ѡ��COM7�Ĵ������в���)
            test_reg_addr = REG_COM7;
            test_data = 8'hA5;  // ��������ģʽ�����Ի��������ض�ֵ
            
            // ��һ������д������
            test_sccb_write(test_reg_addr, test_data);
            #2000;  // �ȴ��ȶ�
            
            // �ڶ��������д���Ƿ�ɹ���ͨ����ȡ��֤��
            // 1. �����豸��ַ
            axi_write(ADDR_REG_ADDR, OV7670_ADDR);
            #100;
            
            // 2. ���üĴ�����ַ
            axi_write(SLAVE_REG_ADDR, test_reg_addr);
            #100;
            
            // 3. ���ÿ��ƼĴ��� - ����������
            axi_write(CTRL_REG_ADDR, (1 << CTRL_READ_BIT) | (1 << CTRL_STOP_BIT));
            
            // �ȴ�SCCB�������
            wait_transfer_done();
            
            // 4. ��ȡ״̬�Ĵ�������鴫���Ƿ����
            axi_read(STATUS_REG_ADDR, read_value);
            $display("[%0t] SCCB��������״̬�Ĵ���ֵ: 0x%h", $time, read_value);
            
            // 5. ��ȡ���յ�������
            axi_read(RX_DATA_REG_ADDR, read_value);
            $display("[%0t] SCCB���������յ�������: 0x%h (����ֵ: 0x%h)", $time, read_value[7:0], test_data);
            
            // ��֤��ȡ���������Ƿ���д��ֵƥ��
            if (read_value[7:0] == test_data) begin
                $display("[%0t] SCCB��д������Գɹ�! ��ȡ����ȷ������: 0x%h", $time, read_value[7:0]);
            end else begin
                $display("[%0t] SCCB��д�������ʧ��! ��ȡ��������: 0x%h������ֵ: 0x%h", 
                         $time, read_value[7:0], test_data);
            end
            
            // ������ԣ��ٲ���һ�ζ�ȡPID�Ĵ���
            $display("[%0t] ���Ӳ��� - ��ȡPID�Ĵ���", $time);
            
            // 1. �����豸��ַ (OV7670��ַ)
            axi_write(ADDR_REG_ADDR, OV7670_ADDR);
            #100;
            
            // 2. ���üĴ�����ַ (��ȡ��ƷID)
            axi_write(SLAVE_REG_ADDR, REG_PID);
            #100;
            
            // 3. ���ÿ��ƼĴ��� - ����������
            axi_write(CTRL_REG_ADDR, (1 << CTRL_READ_BIT) | (1 << CTRL_STOP_BIT));
            
            // �ȴ�SCCB�������
            wait_transfer_done();
            
            // 4. ��ȡ״̬�Ĵ�������鴫���Ƿ����
            axi_read(STATUS_REG_ADDR, read_value);
            $display("[%0t] PID��������״̬�Ĵ���ֵ: 0x%h", $time, read_value);
            
            // 5. ��ȡ���յ�������
            axi_read(RX_DATA_REG_ADDR, read_value);
            $display("[%0t] PID���������յ�������: 0x%h (����ֵ: 0x76)", $time, read_value[7:0]);
            
            // ��֤��ȡ���Ĳ�ƷID�Ƿ���ȷ
            if (read_value[7:0] == 8'h76) begin
                $display("[%0t] PID���������Գɹ�! ��ȡ����ȷ�Ĳ�ƷID: 0x%h", $time, read_value[7:0]);
            end else begin
                $display("[%0t] PID����������ʧ��! ��ȡ������Ĳ�ƷID: 0x%h������ֵ: 0x76", $time, read_value[7:0]);
            end
        end
    endtask

endmodule 