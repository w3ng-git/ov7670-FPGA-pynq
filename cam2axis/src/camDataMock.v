/*
 * OV7670 Camera Mock Module - dual-frame version
 *
 * Generates two complete 640×480 RGB565 frames with accurate VSYNC/HREF timing.
 * For debug convenience, each pixel carries its Y (row) and X (column) indexes
 * modulo-100:
 *   - First byte  (even PCLK)  → row   (0-99)
 *   - Second byte (odd  PCLK)  → column (0-99)
 * This makes it easy to trace scan position with an 8-bit logic analyzer while
 * preserving correct OV7670 signal behaviour.
 */

`timescale 1ns / 1ps

module camDataMock #(
    // ----- user-configurable parameters ------------------------------------
    parameter PCLK_FREQ_MHZ   = 24,   // PCLK frequency (nominal)
    parameter FRAME_WIDTH     = 8,    // Active pixels per line (默认8列)
    parameter FRAME_HEIGHT    = 4,    // Active lines per frame (默认4行)
    parameter FRAMES_TO_SEND  = 10    // Number of frames to emit before halt
)(
    // ----- inputs ----------------------------------------------------------
    input  wire xclk,                 // 24 MHz clock provided to OV7670
    input  wire reset_n,              // Asynchronous reset, active-low
    input  wire enable,               // Start transmission when 1

    // ----- OV7670-compatible outputs --------------------------------------
    output reg  pclk,                 // Pixel clock (≈?×xclk)
    output reg  vsync,                // Vertical sync - high for 3 tLINE
    output reg  href,                 // Horizontal reference - high during pixels
    output reg  [7:0] data_out,       // Pixel byte stream (RGB565)
    output reg  frame_done,           // High once FRAMES_TO_SEND frames sent
    output reg  [1:0] current_frame   // Current frame being transmitted (1-based)
);

    // ----------------------------------------------------------------------
    //  Timing constants (datasheet default window, RGB565)
    //  All values expressed in PCLK cycles (horizontal) or lines (vertical)
    // ----------------------------------------------------------------------
    // localparam H_FRONT_PORCH  = 80;

    localparam H_ACTIVE      = FRAME_WIDTH * 2;   // 1280 bytes
    localparam H_FRONT_PORCH = 16;
    localparam H_SYNC        = 19;
    localparam H_BACK_PORCH  = 144 - H_FRONT_PORCH - H_SYNC; // 109
    localparam H_TOTAL       = H_FRONT_PORCH + H_ACTIVE
                         + H_BACK_PORCH + H_SYNC;        // 1424

    // localparam H_ACTIVE       = FRAME_WIDTH;   // 640
    // localparam H_BACK_PORCH   = 45;
    // localparam H_SYNC         = 19;
    // localparam H_TOTAL        = H_FRONT_PORCH + H_ACTIVE + H_BACK_PORCH + H_SYNC; // 784

    localparam V_SYNC         = 3;
    localparam V_BACK_PORCH   = 17;
    localparam V_ACTIVE       = FRAME_HEIGHT;  // 480
    localparam V_FRONT_PORCH  = 10;
    localparam V_TOTAL        = V_SYNC + V_BACK_PORCH + V_ACTIVE + V_FRONT_PORCH; // 510

    // ----------------------------------------------------------------------
    //  Internal counters & state
    // ----------------------------------------------------------------------
    reg  [11:0] h_count;        // 0?783
    reg   [9:0] v_count;        // 0?509
    reg   [1:0] frame_cnt;      // Counts completed frames

    // convenience wires - current pixel coordinate inside active window
    wire [9:0] cur_pix_x = (h_count - H_FRONT_PORCH) >> 1; // divide by 2 bytes/px
    wire [9:0] cur_pix_y =  v_count - (V_SYNC + V_BACK_PORCH);

    // coordinate modulo-100 for debug pattern
    wire  [6:0] row_mod = cur_pix_y % 100; // 0?99 fits in 7 bits
    wire  [6:0] col_mod = cur_pix_x % 100;

    // ----------------------------------------------------------------------
    //  Generate PCLK (? × XCLK while transmitting)
    // ----------------------------------------------------------------------
    always @(posedge xclk or negedge reset_n) begin
        if (!reset_n) begin
            pclk <= 1'b0;
        end else if (enable && !frame_done) begin
            pclk <= ~pclk;              // divide-by-2 toggle while active
        end else begin
            pclk <= 1'b0;               // hold low when idle
        end
    end

    // ----------------------------------------------------------------------
    //  Main state machine - runs on PCLK (移到下降沿)
    // ----------------------------------------------------------------------
    always @(negedge pclk or negedge reset_n) begin
        if (!reset_n) begin
            h_count     <= 0;
            v_count     <= 0;
            frame_cnt   <= 0;
            vsync       <= 1'b0;
            href        <= 1'b0;
            data_out    <= 8'h00;
            frame_done  <= 1'b0;
            current_frame <= 2'd1;   // 从第1帧开始
        end
        else if (enable && !frame_done) begin
            // ----------- Horizontal counter --------------------------------
            if (h_count == H_TOTAL - 1) begin
                h_count <= 0;
                // -------- Vertical counter --------------------------------
                if (v_count == V_TOTAL - 1) begin
                    v_count <= 0;
                    frame_cnt <= frame_cnt + 1;
                    // 更新当前帧计数（如果不是最后一帧）
                    if (frame_cnt == FRAMES_TO_SEND - 1)
                        frame_done <= 1'b1; // all requested frames done
                    else
                        current_frame <= frame_cnt + 2'd2; // 更新为下一帧编号（当前帧+1）
                end else begin
                    v_count <= v_count + 1;
                end
            end else begin
                h_count <= h_count + 1;
            end

            // ----------- Signal generation ---------------------------------
            // VSYNC: high for first 3 lines of every frame
            // 在每帧的开始有3行VSYNC高电平信号(V_SYNC=3)
            // 两帧之间的空闲时间 = V_FRONT_PORCH + V_SYNC + V_BACK_PORCH = 10 + 3 + 17 = 30行
            // 这确保了帧与帧之间有足够的时间间隔用于同步
            vsync <= (v_count < V_SYNC);

            // HREF: high during active pixel window of active lines
            href <= ( (v_count >= (V_SYNC + V_BACK_PORCH)) &&
                      (v_count <  (V_SYNC + V_BACK_PORCH + V_ACTIVE)) &&
                      (h_count >=  H_FRONT_PORCH) &&
                      (h_count <   H_FRONT_PORCH + H_ACTIVE) );

            // ----------- Pixel data pattern --------------------------------
            // 遵循RGB565格式：每个像素需要两个字节，因此占用两个连续的PCLK周期
            // 数据仅在href为高的周期有效，否则数据总线为0
            if (href) begin
                if (h_count[0] == 1'b0)       // even PCLK → first byte of pixel (高8位)
                    data_out <= {1'b0,row_mod}; // pad to 8 bits
                else                          // odd PCLK → second byte (低8位)
                    data_out <= {1'b0,col_mod};
            end else begin
                data_out <= 8'h00;            // 当href为低时，确保数据总线为0
            end
        end
    end
endmodule
