# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "C_CLK_FREQ_MHZ" -parent ${Page_0}
  ipgui::add_param $IPINST -name "C_S00_AXI_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "C_S00_AXI_DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "C_SCCB_FREQ_KHZ" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SCCB_BOARD_INTERFACE" -parent ${Page_0}


}

proc update_PARAM_VALUE.C_CLK_FREQ_MHZ { PARAM_VALUE.C_CLK_FREQ_MHZ } {
	# Procedure called to update C_CLK_FREQ_MHZ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_CLK_FREQ_MHZ { PARAM_VALUE.C_CLK_FREQ_MHZ } {
	# Procedure called to validate C_CLK_FREQ_MHZ
	return true
}

proc update_PARAM_VALUE.C_S00_AXI_ADDR_WIDTH { PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
	# Procedure called to update C_S00_AXI_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_ADDR_WIDTH { PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
	# Procedure called to validate C_S00_AXI_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.C_S00_AXI_DATA_WIDTH { PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to update C_S00_AXI_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_DATA_WIDTH { PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to validate C_S00_AXI_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.C_SCCB_FREQ_KHZ { PARAM_VALUE.C_SCCB_FREQ_KHZ } {
	# Procedure called to update C_SCCB_FREQ_KHZ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_SCCB_FREQ_KHZ { PARAM_VALUE.C_SCCB_FREQ_KHZ } {
	# Procedure called to validate C_SCCB_FREQ_KHZ
	return true
}

proc update_PARAM_VALUE.SCCB_BOARD_INTERFACE { PARAM_VALUE.SCCB_BOARD_INTERFACE } {
	# Procedure called to update SCCB_BOARD_INTERFACE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SCCB_BOARD_INTERFACE { PARAM_VALUE.SCCB_BOARD_INTERFACE } {
	# Procedure called to validate SCCB_BOARD_INTERFACE
	return true
}


proc update_MODELPARAM_VALUE.C_SCCB_FREQ_KHZ { MODELPARAM_VALUE.C_SCCB_FREQ_KHZ PARAM_VALUE.C_SCCB_FREQ_KHZ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_SCCB_FREQ_KHZ}] ${MODELPARAM_VALUE.C_SCCB_FREQ_KHZ}
}

proc update_MODELPARAM_VALUE.C_CLK_FREQ_MHZ { MODELPARAM_VALUE.C_CLK_FREQ_MHZ PARAM_VALUE.C_CLK_FREQ_MHZ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_CLK_FREQ_MHZ}] ${MODELPARAM_VALUE.C_CLK_FREQ_MHZ}
}

proc update_MODELPARAM_VALUE.SCCB_BOARD_INTERFACE { MODELPARAM_VALUE.SCCB_BOARD_INTERFACE PARAM_VALUE.SCCB_BOARD_INTERFACE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SCCB_BOARD_INTERFACE}] ${MODELPARAM_VALUE.SCCB_BOARD_INTERFACE}
}

proc update_MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH { MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S00_AXI_DATA_WIDTH}] ${MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH { MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S00_AXI_ADDR_WIDTH}] ${MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH}
}

