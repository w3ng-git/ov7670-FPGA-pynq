`timescale 1 ns / 1 ps

	module w3_sccb_v1_0 #
	(
		// Users to add parameters here
		parameter integer C_SCCB_FREQ_KHZ = 100,        // SCCB时钟频率，默认100KHz
        parameter integer C_CLK_FREQ_MHZ = 100,        // 系统时钟频率，默认100MHz
        // SCCB接口板级设置
        parameter SCCB_BOARD_INTERFACE = "Custom",     

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 5
	)
	(
		// Users to add ports here
		// SCCB接口
		(* X_INTERFACE_INFO = "xilinx.com:interface:iic:1.0 SCCB SCL_O" *)
		(* X_INTERFACE_PARAMETER = "BOARD.ASSOCIATED_PARAM SCCB_BOARD_INTERFACE" *)
		output wire scl_o,                // SCL输出
		(* X_INTERFACE_INFO = "xilinx.com:interface:iic:1.0 SCCB SCL_I" *)
		input  wire scl_i,                // SCL输入
		(* X_INTERFACE_INFO = "xilinx.com:interface:iic:1.0 SCCB SCL_T" *)
		output wire scl_t,                // SCL三态控制
		(* X_INTERFACE_INFO = "xilinx.com:interface:iic:1.0 SCCB SDA_O" *)
		output wire sda_o,                // SDA输出
		(* X_INTERFACE_INFO = "xilinx.com:interface:iic:1.0 SCCB SDA_I" *)
		input  wire sda_i,                // SDA输入
		(* X_INTERFACE_INFO = "xilinx.com:interface:iic:1.0 SCCB SDA_T" *)
		output wire sda_t,                // SDA三态控制
		(* X_INTERFACE_INFO = "xilinx.com:interface:interrupt:1.0 SCCB_IRQ INTERRUPT" *)
		output wire sccb_irq,              // 中断信号

		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
		input wire  s00_axi_aclk,
		input wire  s00_axi_aresetn,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input wire [2 : 0] s00_axi_awprot,
		input wire  s00_axi_awvalid,
		output wire  s00_axi_awready,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input wire  s00_axi_wvalid,
		output wire  s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire  s00_axi_bvalid,
		input wire  s00_axi_bready,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input wire [2 : 0] s00_axi_arprot,
		input wire  s00_axi_arvalid,
		output wire  s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire  s00_axi_rvalid,
		input wire  s00_axi_rready
	);
// Instantiation of Axi Bus Interface S00_AXI
	w3_sccb_v1_0_S00_AXI # ( 
		.C_SCCB_FREQ_KHZ(C_SCCB_FREQ_KHZ),
		.C_CLK_FREQ_MHZ(C_CLK_FREQ_MHZ),
		.C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
	) w3_sccb_v1_0_S00_AXI_inst (
		// SCCB接口
		.scl_o(scl_o),
		.scl_i(scl_i),
		.scl_t(scl_t),
		.sda_o(sda_o),
		.sda_i(sda_i),
		.sda_t(sda_t),
		.sccb_irq(sccb_irq),

		// AXI接口
		.S_AXI_ACLK(s00_axi_aclk),
		.S_AXI_ARESETN(s00_axi_aresetn),
		.S_AXI_AWADDR(s00_axi_awaddr),
		.S_AXI_AWPROT(s00_axi_awprot),
		.S_AXI_AWVALID(s00_axi_awvalid),
		.S_AXI_AWREADY(s00_axi_awready),
		.S_AXI_WDATA(s00_axi_wdata),
		.S_AXI_WSTRB(s00_axi_wstrb),
		.S_AXI_WVALID(s00_axi_wvalid),
		.S_AXI_WREADY(s00_axi_wready),
		.S_AXI_BRESP(s00_axi_bresp),
		.S_AXI_BVALID(s00_axi_bvalid),
		.S_AXI_BREADY(s00_axi_bready),
		.S_AXI_ARADDR(s00_axi_araddr),
		.S_AXI_ARPROT(s00_axi_arprot),
		.S_AXI_ARVALID(s00_axi_arvalid),
		.S_AXI_ARREADY(s00_axi_arready),
		.S_AXI_RDATA(s00_axi_rdata),
		.S_AXI_RRESP(s00_axi_rresp),
		.S_AXI_RVALID(s00_axi_rvalid),
		.S_AXI_RREADY(s00_axi_rready)
	);

	// Add user logic here

	// User logic ends

	endmodule