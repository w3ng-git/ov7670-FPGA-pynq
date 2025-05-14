`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// ģ������: mock_ov7670_sccb
// ����: ģ��OV7670����ͷSCCB���豸�ӿڣ�֧��˫��SDAͨ��
//////////////////////////////////////////////////////////////////////////////////

module mock_ov7670_sccb (
    input  wire       clk,      // ϵͳʱ��
    input  wire       rst_n,    // ��λ�źţ��͵�ƽ��Ч
    
    // SCCB�ӿ� - ˫��ͨ��
    input  wire       scl,      // SCLʱ����
    inout  wire       sda       // SDA�����ߣ�˫��
);

    // SCCBЭ��״̬
    localparam IDLE        = 0;
    localparam START       = 1;
    localparam ADDR        = 2;
    localparam ACK_ADDR    = 3;
    localparam REG_ADDR    = 4;
    localparam ACK_REG     = 5;
    localparam DATA        = 6;
    localparam ACK_DATA    = 7;
    localparam STOP        = 8;
    
    // �ڲ��Ĵ���
    reg [7:0] registers [0:255];
    initial begin
        registers[8'h0A] = 8'h76;  // PID
        registers[8'h0B] = 8'h73;  // VER
        registers[8'h12] = 8'h00;  // COM7
    end
    
    // ״̬������׷��
    reg [3:0]  state;
    reg [2:0]  bit_count;
    reg [7:0]  shift_reg;
    reg [7:0]  reg_addr;
    reg        is_read;
    reg        prev_scl;
    reg        prev_sda;
    
    // SCCBЭ�����
    reg        sccb_first_phase_done;  // ���SCCB��һ�׶��Ƿ����
    reg [7:0]  sccb_reg_addr;          // ����SCCB��һ�׶εļĴ�����ַ
    
    // SDA��������
    reg        sda_out;       // SDA���ֵ
    reg        sda_oe;        // SDA���ʹ��
    
    // SDA���߿��� - ��̬���
    assign sda = sda_oe ? sda_out : 1'bz;
    
    // ����״̬���
    wire start_cond  = scl && prev_sda && !sda;
    wire stop_cond   = scl && !prev_sda && sda;
    
    // ʱ�ӱ��ؼ��
    always @(posedge clk) begin
        if (!rst_n) begin
            prev_scl <= 1'b1;
            prev_sda <= 1'b1;
        end else begin
            prev_scl <= scl;
            prev_sda <= sda;
        end
    end
    
    // SDA������� - ��״̬�����룬ȷ�������ȶ���
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_out <= 1'b1;
            sda_oe <= 1'b0;
        end
        else begin
            // Ĭ�ϲ�����SDA�����ָ���̬
            sda_oe <= 1'b0;
            
            // �����ض�����������SDA:
            
            // 1. д������Ӧ��׶�
            if ((state == ACK_ADDR || state == ACK_REG || state == ACK_DATA) && !is_read) begin
                if (!scl && prev_scl) begin  // SCL�½���
                    sda_oe <= 1'b1;  // ����SDAΪ�ͣ���ʾACK
                    sda_out <= 1'b0;
                    $display("[%0t] MOCK_OV7670_SCCB: д���� - ����ACK", $time);
                end
            end
            
            // 2. �����������ݽ׶� - ֻ��ȷ���Ƕ��׶ζ������ҵ�ַ�ѱ�ȷ�Ϻ�
            else if (state == DATA && is_read && sccb_first_phase_done) begin
                if (!scl && prev_scl) begin  // SCL�½���
                    sda_oe <= 1'b1;  // ����SDA��������λ
                    sda_out <= shift_reg[7-bit_count];  // MSB����
                    $display("[%0t] MOCK_OV7670_SCCB: ���׶ζ����� - ��������λ %d = %b (0x%h)", 
                             $time, 7-bit_count, shift_reg[7-bit_count], shift_reg);
                end
            end
        end
    end
    
    // ״̬�� - ֧��˫��ͨ��
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_count <= 0;
            reg_addr <= 0;
            is_read <= 0;
            sccb_first_phase_done <= 0;
            sccb_reg_addr <= 0;
        end else begin
            // �����ʼ����
            if (start_cond) begin
                state <= ADDR;
                bit_count <= 0;
                shift_reg <= 0;
                $display("[%0t] MOCK_OV7670_SCCB: ��⵽��ʼ����", $time);
                
                // �����SCCB�ڶ��׶εĿ�ʼ
                if (sccb_first_phase_done) begin
                    $display("[%0t] MOCK_OV7670_SCCB: ��⵽SCCB�ڶ��׶ο�ʼ", $time);
                end
            end
            // ���ֹͣ����
            else if (stop_cond) begin
                state <= IDLE;
                $display("[%0t] MOCK_OV7670_SCCB: ��⵽ֹͣ����", $time);
                
                // �����SCCB��һ�׶εĽ���
                if (!sccb_first_phase_done && state == ACK_REG) begin
                    sccb_first_phase_done <= 1;
                    sccb_reg_addr <= reg_addr;
                    $display("[%0t] MOCK_OV7670_SCCB: SCCB��һ�׶���ɣ�����Ĵ�����ַ0x%h", $time, reg_addr);
                end
            end
            // SCL������ - ���ݲ�����
            else if (scl && !prev_scl) begin
                case (state)
                    ADDR: begin
                        if (bit_count < 7) begin
                            shift_reg <= {shift_reg[6:0], sda};
                            bit_count <= bit_count + 1;
                        end else begin
                            is_read <= sda;  // ��/дλ
                            bit_count <= 0;
                            state <= ACK_ADDR;
                            
                            // ����Ƿ���SCCB�ڶ��׶εĶ�����
                            if (sccb_first_phase_done && sda) begin
                                $display("[%0t] MOCK_OV7670_SCCB: SCCB�ڶ��׶ζ��������豸��ַ0x%h������־=%b", 
                                         $time, shift_reg, sda);
                                // ׼����������
                                shift_reg <= registers[sccb_reg_addr];
                                $display("[%0t] MOCK_OV7670_SCCB: ׼�����ͼĴ���[0x%h]=0x%h", 
                                         $time, sccb_reg_addr, registers[sccb_reg_addr]);
                            end else begin
                                $display("[%0t] MOCK_OV7670_SCCB: ���յ�ַ0x%h, R/W=%b", 
                                         $time, shift_reg, sda);
                            end
                            
                            // ����ַ�Ƿ�ƥ��
                            if (shift_reg == 7'h21) begin
                                // ��ACK��������SDAΪ�ͣ���ʾӦ��
                                $display("[%0t] MOCK_OV7670_SCCB: ��ַƥ��! ׼������ACK", $time);
                            end
                        end
                    end
                    
                    ACK_ADDR: begin
                        // �����SCCB�ڶ��׶εĶ�������ֱ�ӽ���DATA״̬
                        if (sccb_first_phase_done && is_read) begin
                            state <= DATA;
                            bit_count <= 0;
                            $display("[%0t] MOCK_OV7670_SCCB: SCCB�ڶ��׶Σ�׼�����ͼĴ���[0x%h]��ֵ", 
                                     $time, sccb_reg_addr);
                        end else begin
                            state <= is_read ? DATA : REG_ADDR;
                        end
                        $display("[%0t] MOCK_OV7670_SCCB: Ӧ���������", $time);
                    end
                    
                    REG_ADDR: begin
                        if (bit_count < 7) begin
                            shift_reg <= {shift_reg[6:0], sda};
                            bit_count <= bit_count + 1;
                        end else begin
                            reg_addr <= {shift_reg[6:0], sda};
                            bit_count <= 0;
                            state <= ACK_REG;
                            $display("[%0t] MOCK_OV7670_SCCB: ���ռĴ�����ַ0x%h",
                                     $time, {shift_reg[6:0], sda});
                        end
                    end
                    
                    ACK_REG: begin
                        state <= DATA;
                        $display("[%0t] MOCK_OV7670_SCCB: �Ĵ�����ַӦ���������", $time);
                    end
                    
                    DATA: begin
                        if (!is_read) begin
                            // д���� - ��������
                            if (bit_count < 7) begin
                                shift_reg <= {shift_reg[6:0], sda};
                                bit_count <= bit_count + 1;
                            end else begin
                                // д�������
                                registers[reg_addr] <= {shift_reg[6:0], sda};
                                bit_count <= 0;
                                state <= ACK_DATA;
                                $display("[%0t] MOCK_OV7670_SCCB: д��Ĵ���[0x%h]=0x%h", 
                                         $time, reg_addr, {shift_reg[6:0], sda});
                            end
                        end else begin
                            // ������ - �����������ݣ����ǲ���Ҫ��������ʲô
                            // ��Ϊ������SCL�½�������SDA
                            bit_count <= bit_count + 1;
                            if (bit_count == 7) begin
                                state <= ACK_DATA;
                                $display("[%0t] MOCK_OV7670_SCCB: ����������ɣ��ȴ�����ACK", $time);
                            end
                        end
                    end
                    
                    ACK_DATA: begin
                        if (!is_read) begin
                            state <= DATA;
                            reg_addr <= reg_addr + 1;  // �Զ������Ĵ�����ַ
                            $display("[%0t] MOCK_OV7670_SCCB: д����Ӧ���������", $time);
                        end else begin
                            // ��������ACK�������ṩ������Ƿ������ȡ
                            if (sda) begin
                                // NACK - ֹͣ��ȡ
                                state <= IDLE;
                                $display("[%0t] MOCK_OV7670_SCCB: ��������NACK��ֹͣ��ȡ", $time);
                            end else begin
                                // ACK - ������ȡ��һ���Ĵ���
                                state <= DATA;
                                reg_addr <= reg_addr + 1;
                                shift_reg <= registers[reg_addr + 1];
                                bit_count <= 0;
                                $display("[%0t] MOCK_OV7670_SCCB: ��������ACK��������ȡ�Ĵ���[0x%h]", 
                                         $time, reg_addr + 1);
                            end
                        end
                    end
                endcase
            end
        end
    end
endmodule 