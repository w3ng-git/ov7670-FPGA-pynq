`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// 模块名称: mock_ov7670_sccb
// 描述: 模拟OV7670摄像头SCCB从设备接口，支持双向SDA通信
//////////////////////////////////////////////////////////////////////////////////

module mock_ov7670_sccb (
    input  wire       clk,      // 系统时钟
    input  wire       rst_n,    // 复位信号，低电平有效
    
    // SCCB接口 - 双向通信
    input  wire       scl,      // SCL时钟线
    inout  wire       sda       // SDA数据线，双向
);

    // SCCB协议状态
    localparam IDLE        = 0;
    localparam START       = 1;
    localparam ADDR        = 2;
    localparam ACK_ADDR    = 3;
    localparam REG_ADDR    = 4;
    localparam ACK_REG     = 5;
    localparam DATA        = 6;
    localparam ACK_DATA    = 7;
    localparam STOP        = 8;
    
    // 内部寄存器
    reg [7:0] registers [0:255];
    initial begin
        registers[8'h0A] = 8'h76;  // PID
        registers[8'h0B] = 8'h73;  // VER
        registers[8'h12] = 8'h00;  // COM7
    end
    
    // 状态和数据追踪
    reg [3:0]  state;
    reg [2:0]  bit_count;
    reg [7:0]  shift_reg;
    reg [7:0]  reg_addr;
    reg        is_read;
    reg        prev_scl;
    reg        prev_sda;
    
    // SCCB协议跟踪
    reg        sccb_first_phase_done;  // 标记SCCB第一阶段是否完成
    reg [7:0]  sccb_reg_addr;          // 保存SCCB第一阶段的寄存器地址
    
    // SDA驱动控制
    reg        sda_out;       // SDA输出值
    reg        sda_oe;        // SDA输出使能
    
    // SDA总线控制 - 三态输出
    assign sda = sda_oe ? sda_out : 1'bz;
    
    // 总线状态检测
    wire start_cond  = scl && prev_sda && !sda;
    wire stop_cond   = scl && !prev_sda && sda;
    
    // 时钟边沿检测
    always @(posedge clk) begin
        if (!rst_n) begin
            prev_scl <= 1'b1;
            prev_sda <= 1'b1;
        end else begin
            prev_scl <= scl;
            prev_sda <= sda;
        end
    end
    
    // SDA输出控制 - 与状态机分离，确保数据稳定性
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_out <= 1'b1;
            sda_oe <= 1'b0;
        end
        else begin
            // 默认不驱动SDA，保持高阻态
            sda_oe <= 1'b0;
            
            // 仅在特定条件下驱动SDA:
            
            // 1. 写操作的应答阶段
            if ((state == ACK_ADDR || state == ACK_REG || state == ACK_DATA) && !is_read) begin
                if (!scl && prev_scl) begin  // SCL下降沿
                    sda_oe <= 1'b1;  // 驱动SDA为低，表示ACK
                    sda_out <= 1'b0;
                    $display("[%0t] MOCK_OV7670_SCCB: 写操作 - 发送ACK", $time);
                end
            end
            
            // 2. 读操作的数据阶段 - 只在确认是二阶段读操作且地址已被确认后
            else if (state == DATA && is_read && sccb_first_phase_done) begin
                if (!scl && prev_scl) begin  // SCL下降沿
                    sda_oe <= 1'b1;  // 驱动SDA发送数据位
                    sda_out <= shift_reg[7-bit_count];  // MSB优先
                    $display("[%0t] MOCK_OV7670_SCCB: 二阶段读操作 - 发送数据位 %d = %b (0x%h)", 
                             $time, 7-bit_count, shift_reg[7-bit_count], shift_reg);
                end
            end
        end
    end
    
    // 状态机 - 支持双向通信
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_count <= 0;
            reg_addr <= 0;
            is_read <= 0;
            sccb_first_phase_done <= 0;
            sccb_reg_addr <= 0;
        end else begin
            // 检测起始条件
            if (start_cond) begin
                state <= ADDR;
                bit_count <= 0;
                shift_reg <= 0;
                $display("[%0t] MOCK_OV7670_SCCB: 检测到起始条件", $time);
                
                // 如果是SCCB第二阶段的开始
                if (sccb_first_phase_done) begin
                    $display("[%0t] MOCK_OV7670_SCCB: 检测到SCCB第二阶段开始", $time);
                end
            end
            // 检测停止条件
            else if (stop_cond) begin
                state <= IDLE;
                $display("[%0t] MOCK_OV7670_SCCB: 检测到停止条件", $time);
                
                // 如果是SCCB第一阶段的结束
                if (!sccb_first_phase_done && state == ACK_REG) begin
                    sccb_first_phase_done <= 1;
                    sccb_reg_addr <= reg_addr;
                    $display("[%0t] MOCK_OV7670_SCCB: SCCB第一阶段完成，保存寄存器地址0x%h", $time, reg_addr);
                end
            end
            // SCL上升沿 - 数据采样点
            else if (scl && !prev_scl) begin
                case (state)
                    ADDR: begin
                        if (bit_count < 7) begin
                            shift_reg <= {shift_reg[6:0], sda};
                            bit_count <= bit_count + 1;
                        end else begin
                            is_read <= sda;  // 读/写位
                            bit_count <= 0;
                            state <= ACK_ADDR;
                            
                            // 检查是否是SCCB第二阶段的读操作
                            if (sccb_first_phase_done && sda) begin
                                $display("[%0t] MOCK_OV7670_SCCB: SCCB第二阶段读操作，设备地址0x%h，读标志=%b", 
                                         $time, shift_reg, sda);
                                // 准备发送数据
                                shift_reg <= registers[sccb_reg_addr];
                                $display("[%0t] MOCK_OV7670_SCCB: 准备发送寄存器[0x%h]=0x%h", 
                                         $time, sccb_reg_addr, registers[sccb_reg_addr]);
                            end else begin
                                $display("[%0t] MOCK_OV7670_SCCB: 接收地址0x%h, R/W=%b", 
                                         $time, shift_reg, sda);
                            end
                            
                            // 检查地址是否匹配
                            if (shift_reg == 7'h21) begin
                                // 在ACK周期驱动SDA为低，表示应答
                                $display("[%0t] MOCK_OV7670_SCCB: 地址匹配! 准备发送ACK", $time);
                            end
                        end
                    end
                    
                    ACK_ADDR: begin
                        // 如果是SCCB第二阶段的读操作，直接进入DATA状态
                        if (sccb_first_phase_done && is_read) begin
                            state <= DATA;
                            bit_count <= 0;
                            $display("[%0t] MOCK_OV7670_SCCB: SCCB第二阶段，准备发送寄存器[0x%h]的值", 
                                     $time, sccb_reg_addr);
                        end else begin
                            state <= is_read ? DATA : REG_ADDR;
                        end
                        $display("[%0t] MOCK_OV7670_SCCB: 应答周期完成", $time);
                    end
                    
                    REG_ADDR: begin
                        if (bit_count < 7) begin
                            shift_reg <= {shift_reg[6:0], sda};
                            bit_count <= bit_count + 1;
                        end else begin
                            reg_addr <= {shift_reg[6:0], sda};
                            bit_count <= 0;
                            state <= ACK_REG;
                            $display("[%0t] MOCK_OV7670_SCCB: 接收寄存器地址0x%h",
                                     $time, {shift_reg[6:0], sda});
                        end
                    end
                    
                    ACK_REG: begin
                        state <= DATA;
                        $display("[%0t] MOCK_OV7670_SCCB: 寄存器地址应答周期完成", $time);
                    end
                    
                    DATA: begin
                        if (!is_read) begin
                            // 写操作 - 接收数据
                            if (bit_count < 7) begin
                                shift_reg <= {shift_reg[6:0], sda};
                                bit_count <= bit_count + 1;
                            end else begin
                                // 写操作完成
                                registers[reg_addr] <= {shift_reg[6:0], sda};
                                bit_count <= 0;
                                state <= ACK_DATA;
                                $display("[%0t] MOCK_OV7670_SCCB: 写入寄存器[0x%h]=0x%h", 
                                         $time, reg_addr, {shift_reg[6:0], sda});
                            end
                        end else begin
                            // 读操作 - 主机接收数据，我们不需要在这里做什么
                            // 因为我们在SCL下降沿驱动SDA
                            bit_count <= bit_count + 1;
                            if (bit_count == 7) begin
                                state <= ACK_DATA;
                                $display("[%0t] MOCK_OV7670_SCCB: 发送数据完成，等待主机ACK", $time);
                            end
                        end
                    end
                    
                    ACK_DATA: begin
                        if (!is_read) begin
                            state <= DATA;
                            reg_addr <= reg_addr + 1;  // 自动递增寄存器地址
                            $display("[%0t] MOCK_OV7670_SCCB: 写数据应答周期完成", $time);
                        end else begin
                            // 读操作的ACK由主机提供，检查是否继续读取
                            if (sda) begin
                                // NACK - 停止读取
                                state <= IDLE;
                                $display("[%0t] MOCK_OV7670_SCCB: 主机发送NACK，停止读取", $time);
                            end else begin
                                // ACK - 继续读取下一个寄存器
                                state <= DATA;
                                reg_addr <= reg_addr + 1;
                                shift_reg <= registers[reg_addr + 1];
                                bit_count <= 0;
                                $display("[%0t] MOCK_OV7670_SCCB: 主机发送ACK，继续读取寄存器[0x%h]", 
                                         $time, reg_addr + 1);
                            end
                        end
                    end
                endcase
            end
        end
    end
endmodule 