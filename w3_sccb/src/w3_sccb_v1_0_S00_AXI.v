`timescale 1 ns / 1 ps

	module w3_sccb_v1_0_S00_AXI #
	(
		// Users to add parameters here
		parameter integer C_SCCB_FREQ_KHZ = 100,        // SCCBʱ��Ƶ�ʣ�Ĭ��100KHz
		parameter integer C_CLK_FREQ_MHZ = 100,        // ϵͳʱ��Ƶ�ʣ�Ĭ��100MHz

		// User parameters ends
		// Do not modify the parameters beyond this line

		// Width of S_AXI data bus
		parameter integer C_S_AXI_DATA_WIDTH	= 32,
		// Width of S_AXI address bus
		parameter integer C_S_AXI_ADDR_WIDTH	= 5
	)
	(
		// Users to add ports here
		// SCCB�ӿ�
		output wire scl_o,                // SCL���
		input  wire scl_i,                // SCL����
		output wire scl_t,                // SCL��̬����
		output wire sda_o,                // SDA���
		input  wire sda_i,                // SDA����
		output wire sda_t,                // SDA��̬����
		output wire sccb_irq,              // �ж��ź�

		// User ports ends
		// Do not modify the ports beyond this line

		// Global Clock Signal
		input wire  S_AXI_ACLK,
		// Global Reset Signal. This Signal is Active LOW
		input wire  S_AXI_ARESETN,
		// Write address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
		// Write channel Protection type. This signal indicates the
    		// privilege and security level of the transaction, and whether
    		// the transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_AWPROT,
		// Write address valid. This signal indicates that the master signaling
    		// valid write address and control information.
		input wire  S_AXI_AWVALID,
		// Write address ready. This signal indicates that the slave is ready
    		// to accept an address and associated control signals.
		output wire  S_AXI_AWREADY,
		// Write data (issued by master, acceped by Slave) 
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
		// Write strobes. This signal indicates which byte lanes hold
    		// valid data. There is one write strobe bit for each eight
    		// bits of the write data bus.    
		input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
		// Write valid. This signal indicates that valid write
    		// data and strobes are available.
		input wire  S_AXI_WVALID,
		// Write ready. This signal indicates that the slave
    		// can accept the write data.
		output wire  S_AXI_WREADY,
		// Write response. This signal indicates the status
    		// of the write transaction.
		output wire [1 : 0] S_AXI_BRESP,
		// Write response valid. This signal indicates that the channel
    		// is signaling a valid write response.
		output wire  S_AXI_BVALID,
		// Response ready. This signal indicates that the master
    		// can accept a write response.
		input wire  S_AXI_BREADY,
		// Read address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
		// Protection type. This signal indicates the privilege
    		// and security level of the transaction, and whether the
    		// transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_ARPROT,
		// Read address valid. This signal indicates that the channel
    		// is signaling valid read address and control information.
		input wire  S_AXI_ARVALID,
		// Read address ready. This signal indicates that the slave is
    		// ready to accept an address and associated control signals.
		output wire  S_AXI_ARREADY,
		// Read data (issued by slave)
		output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
		// Read response. This signal indicates the status of the
    		// read transfer.
		output wire [1 : 0] S_AXI_RRESP,
		// Read valid. This signal indicates that the channel is
    		// signaling the required read data.
		output wire  S_AXI_RVALID,
		// Read ready. This signal indicates that the master can
    		// accept the read data and response information.
		input wire  S_AXI_RREADY
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
	
	// �Ĵ�����ַ����
	localparam CTRL_REG_ADDR      = 3'h0;  // ���ƼĴ�����ַ
	localparam STATUS_REG_ADDR    = 3'h1;  // ״̬�Ĵ�����ַ
	localparam TX_DATA_REG_ADDR   = 3'h2;  // �������ݼĴ�����ַ
	localparam RX_DATA_REG_ADDR   = 3'h3;  // �������ݼĴ�����ַ
	localparam ADDR_REG_ADDR      = 3'h4;  // �豸��ַ�Ĵ�����ַ
	localparam SLAVE_REG_ADDR     = 3'h5;  // �ӻ��Ĵ�����ַ

	// AXI4LITE signals
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
	reg  	axi_awready;
	reg  	axi_wready;
	reg [1 : 0] 	axi_bresp;
	reg  	axi_bvalid;
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
	reg  	axi_arready;
	reg [C_S_AXI_DATA_WIDTH-1 : 0] 	axi_rdata;
	reg [1 : 0] 	axi_rresp;
	reg  	axi_rvalid;

	// Example-specific design signals
	// local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	// ADDR_LSB is used for addressing 32/64 bit registers/memories
	// ADDR_LSB = 2 for 32 bits (n downto 2)
	// ADDR_LSB = 3 for 64 bits (n downto 3)
	localparam integer ADDR_LSB = $clog2(C_S_AXI_DATA_WIDTH/8);
	localparam integer OPT_MEM_ADDR_BITS = 2;
	//----------------------------------------------
	//-- Signals for user logic register space example
	//------------------------------------------------
	//-- Number of Slave Registers 6
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg2;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg3;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg4;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg5;
	wire	 slv_reg_rden;
	wire	 slv_reg_wren;
	reg [C_S_AXI_DATA_WIDTH-1:0]	 reg_data_out;
	integer	 byte_index;
	reg	 aw_en;

	// ����Ľ�������
	reg [31:0] latched_rx_data;
	reg        data_latched;

	// I/O Connections assignments
	assign S_AXI_AWREADY	= axi_awready;
	assign S_AXI_WREADY	= axi_wready;
	assign S_AXI_BRESP	= axi_bresp;
	assign S_AXI_BVALID	= axi_bvalid;
	assign S_AXI_ARREADY	= axi_arready;
	assign S_AXI_RDATA	= axi_rdata;
	assign S_AXI_RRESP	= axi_rresp;
	assign S_AXI_RVALID	= axi_rvalid;
	// Implement axi_awready generation
	// axi_awready is asserted for one S_AXI_ACLK clock cycle when both
	// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
	// de-asserted when reset is low.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awready <= 1'b0;
	      aw_en <= 1'b1;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          // slave is ready to accept write address when 
	          // there is a valid write address and write data
	          // on the write address and data bus. This design 
	          // expects no outstanding transactions. 
	          axi_awready <= 1'b1;
	          aw_en <= 1'b0;
	        end
	        else if (S_AXI_BREADY && axi_bvalid)
	            begin
	              aw_en <= 1'b1;
	              axi_awready <= 1'b0;
	            end
	      else           
	        begin
	          axi_awready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_awaddr latching
	// This process is used to latch the address when both 
	// S_AXI_AWVALID and S_AXI_WVALID are valid. 

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awaddr <= 0;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          // Write Address latching 
	          axi_awaddr <= S_AXI_AWADDR;
	        end
	    end 
	end       

	// Implement axi_wready generation
	// axi_wready is asserted for one S_AXI_ACLK clock cycle when both
	// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
	// de-asserted when reset is low. 

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_wready <= 1'b0;
	    end 
	  else
	    begin    
	      if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en )
	        begin
	          // slave is ready to accept write data when 
	          // there is a valid write address and write data
	          // on the write address and data bus. This design 
	          // expects no outstanding transactions. 
	          axi_wready <= 1'b1;
	        end
	      else
	        begin
	          axi_wready <= 1'b0;
	        end
	    end 
	end       

	// Implement memory mapped register select and write logic generation
	// The write data is accepted and written to memory mapped registers when
	// axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
	// select byte enables of slave registers while writing.
	// These registers are cleared when reset (active low) is applied.
	// Slave register write enable is asserted when valid address and data are available
	// and the slave is ready to accept the write address and write data.
	assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      slv_reg0 <= 0;
	      slv_reg1 <= 0;
	      slv_reg2 <= 0;
	      slv_reg3 <= 0;
	      slv_reg4 <= 0;
	      slv_reg5 <= 0;
	    end 
	  else begin
	    if (slv_reg_wren)
	      begin
	        case ( axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	          3'h0:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes 
	                // Slave register 0
	                slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          3'h1:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes 
	                // Slave register 1
	                slv_reg1[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          3'h2:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes 
	                // Slave register 2
	                slv_reg2[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          3'h3:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes 
	                // Slave register 3
	                slv_reg3[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          3'h4:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes 
	                // Slave register 4
	                slv_reg4[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          3'h5:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes 
	                // Slave register 5
	                slv_reg5[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          default : begin
	                      slv_reg0 <= slv_reg0;
	                      slv_reg1 <= slv_reg1;
	                      slv_reg2 <= slv_reg2;
	                      slv_reg3 <= slv_reg3;
	                      slv_reg4 <= slv_reg4;
	                      slv_reg5 <= slv_reg5;
	                    end
	        endcase
	      end
	  end
	end    

	// Implement write response logic generation
	// The write response and response valid signals are asserted by the slave 
	// when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
	// This marks the acceptance of address and indicates the status of 
	// write transaction.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_bvalid  <= 0;
	      axi_bresp   <= 2'b0;
	    end 
	  else
	    begin    
	      if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID)
	        begin
	          // indicates a valid write response is available
	          axi_bvalid <= 1'b1;
	          axi_bresp  <= 2'b0; // 'OKAY' response 
	        end                   // work error responses in future
	      else
	        begin
	          if (S_AXI_BREADY && axi_bvalid) 
	            //check if bready is asserted while bvalid is high) 
	            //(there is a possibility that bready is always asserted high)   
	            begin
	              axi_bvalid <= 1'b0; 
	            end  
	        end
	    end
	end   

	// Implement axi_arready generation
	always @(posedge S_AXI_ACLK) begin
		if (!S_AXI_ARESETN) begin
			axi_arready <= 1'b0;
			axi_araddr <= 0;
		end
		else begin
			// �򻯵�ַ�����߼�����Ҫ��rvalid����
			if (~axi_arready && S_AXI_ARVALID) begin
				axi_arready <= 1'b1;
				axi_araddr <= S_AXI_ARADDR;
			end
			else begin
				axi_arready <= 1'b0;
			end
		end
	end

	// Implement axi_rvalid generation
	always @(posedge S_AXI_ACLK) begin
		if (!S_AXI_ARESETN) begin
			axi_rvalid <= 1'b0;
			axi_rresp <= 2'b0;
			axi_rdata <= 32'h0;
		end
		else begin
			// ���������κ�ʱ�򿴵���ַ��Ч��׼������
			if (S_AXI_ARVALID && ~axi_rvalid) begin
				axi_rvalid <= 1'b1;
				axi_rresp <= 2'b0; // 'OKAY' response
				
				// ֱ��ʹ�������ַ��������axi_araddr
				case (S_AXI_ARADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
					CTRL_REG_ADDR: axi_rdata <= slv_reg0;        // 3'h0
					STATUS_REG_ADDR: axi_rdata <= status_from_sccb;  // 3'h1
					TX_DATA_REG_ADDR: axi_rdata <= slv_reg2;     // 3'h2
					RX_DATA_REG_ADDR: axi_rdata <= data_latched ? {24'h0, latched_rx_data[7:0]} : 32'h0;  // 3'h3, ֻ���ص�8λ
					ADDR_REG_ADDR: axi_rdata <= slv_reg4;        // 3'h4
					SLAVE_REG_ADDR: axi_rdata <= slv_reg5;       // 3'h5
					default: axi_rdata <= 32'h0;                  // δ�����ַ����0
				endcase
			end
			else if (axi_rvalid && S_AXI_RREADY) begin
				// ���ݱ����ܺ����������Ч��־
				axi_rvalid <= 1'b0;
			end
		end
	end

	// Implement memory mapped register select and read logic generation
	// Slave register read enable is asserted when valid address is available
	// and the slave is ready to accept the read address.
	assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;

	// Add user logic here

	// --------------------------------
	// SCCB����������߼�
	// --------------------------------
	
	// д����Ͷ������ź�
	reg  wr_pulse;
	reg  rd_pulse;
	
	// ����д����Ͷ�����
	always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
		if (!S_AXI_ARESETN) begin
			wr_pulse <= 1'b0;
			rd_pulse <= 1'b0;
		end
		else begin
			// �����ƼĴ���д��
			if (slv_reg_wren && (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == CTRL_REG_ADDR)) begin
				// ���д����ƼĴ����ĵ�0λΪ1������д����
				if (S_AXI_WSTRB[0] && S_AXI_WDATA[CTRL_START_BIT])
					wr_pulse <= 1'b1;
				// ���д����ƼĴ����ĵ�1λΪ1�����ɶ�����
				if (S_AXI_WSTRB[0] && S_AXI_WDATA[CTRL_READ_BIT])
					rd_pulse <= 1'b1;
			end
			else begin
				// ����ֻ����һ��ʱ������
				wr_pulse <= 1'b0;
				rd_pulse <= 1'b0;
			end
		end
	end
	
	// ��sccb_controller����״ֵ̬������
	wire [C_S_AXI_DATA_WIDTH-1:0] status_from_sccb;
	wire [C_S_AXI_DATA_WIDTH-1:0] rx_data_from_sccb;
	wire rx_data_valid_from_sccb;
	
	// ʵ����SCCB������
	sccb_controller #(
		.C_SCCB_FREQ_KHZ(C_SCCB_FREQ_KHZ),
		.C_CLK_FREQ_MHZ(C_CLK_FREQ_MHZ)
	) sccb_controller_inst (
		.clk             (S_AXI_ACLK),
		.rst_n           (S_AXI_ARESETN),
		.ctrl_reg        (slv_reg0),           // ���ƼĴ���
		.status_reg      (status_from_sccb),    // ״̬�Ĵ���
		.tx_data         (slv_reg2),           // �������ݼĴ���
		.rx_data         (rx_data_from_sccb),   // �������ݼĴ���
		.rx_data_valid   (rx_data_valid_from_sccb), // ����������Ч��־
		.slave_addr      (slv_reg4[7:0]),      // �豸��ַ�Ĵ���
		.reg_addr        (slv_reg5[7:0]),      // �ӻ��Ĵ�����ַ
		.wr_pulse        (wr_pulse),           // д����
		.rd_pulse        (rd_pulse),           // ������
		.scl_o           (scl_o),              // SCL���
		.scl_i           (scl_i),              // SCL����
		.scl_t           (scl_t),              // SCL��̬����
		.sda_o           (sda_o),              // SDA���
		.sda_i           (sda_i),              // SDA����
		.sda_t           (sda_t),              // SDA��̬����
		.sccb_irq         (sccb_irq)              // �ж��ź�
	);

	// ������յ�������
	always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
		if (!S_AXI_ARESETN) begin
			latched_rx_data <= 32'h0;
			data_latched <= 1'b0;
		end
		else begin
			// �����������������Чʱ��������
			if (status_from_sccb[STAT_TRANS_DONE_BIT] && rx_data_valid_from_sccb) begin
				latched_rx_data <= {24'h0, rx_data_from_sccb[7:0]};  // ȷ����24λΪ0
				data_latched <= 1'b1;
			end
			// ����ʼ�µĴ���ʱ��������־������
			else if (status_from_sccb[STAT_BUSY_BIT]) begin
				data_latched <= 1'b0;
				latched_rx_data <= 32'h0;  // �������������
			end
		end
	end

	// User logic ends

	endmodule