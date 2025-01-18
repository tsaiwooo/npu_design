 #======================================================
#
# Synopsys Synthesis Scripts (Design Vision dctcl mode)
#
#======================================================

#======================================================
#  Set Libraries
#======================================================
set search_path    {./ \
			./../RTL \
		    /usr/cad/synopsys/synthesis/2019.12/libraries/syn/ \
                   /usr/cad/cell_lib/CBDK45_FreePDK_TSRI_v1.1/lib/ 
	    	   }

set synthetic_library {dw_foundation.sldb}
set link_library {* dw_foundation.sldb standard.sldb freepdk45_v1_t0.db}
set target_library {freepdk45_v1_t0.db}

#======================================================
#  Global Parameters
#======================================================
set DESIGN "npu"
set hdlin_ff_always_sync_set_reset true
set CYCLE 7.0

#======================================================
#  Read RTL Code
#======================================================

# read_sverilog {
analyze -f sverilog -define {synthesis=1} {
    npu.v
    axi_stream_output.v
    axi_stream_input.v
    element_wise.v
    GEMM.v
    multi_sram.v
    mac.v
	sram.v
    convolution.v
    sram_controller.v
    MultiplyByQuantizedMultiplier.v
    RoundingDivideByPOT.v
    exp.v
    reciprocal_over_1.v
	sram_64bits.v
}
# analyze -f sverilog npu.v
elaborate npu
current_design npu

#======================================================
#  Elaborate Design (展開參數化模組)
#======================================================
# elaborate npu -parameters {MAX_MACS=64 ADDR_WIDTH=13 DATA_WIDTH=8 C_AXIS_TDATA_WIDTH=8 C_AXIS_MDATA_WIDTH=8 MAX_CHANNELS=64 NUM_CHANNELS_WIDTH=$clog2(MAX_CHANNELS+1) QUANT_WIDTH=32}

#======================================================
#  Global Setting
#======================================================
set_wire_load_mode top

#======================================================
#  Set Design Constraints
#======================================================
# create_clock -name "clk" -period $CYCLE clk 
# set_input_delay  [ expr $CYCLE*0.5 ] -clock clk [all_inputs]
# set_output_delay [ expr $CYCLE*0.5 ] -clock clk [all_outputs]
# set_input_delay 0 -clock clk clk
# set_load 0.05 [all_outputs]
read_sdc constraints.sdc

#======================================================
#  Link the Design
#======================================================
# define_black_box sram_64bits
# define_black_box sram
link


#======================================================
#  Optimization
#======================================================
uniquify
set_fix_multiple_port_nets -all -buffer_constants
compile_ultra

#======================================================
#  Output Reports 
#======================================================
check_design > Report/npu.check
report_timing >  Report/npu.timing
report_area >  Report/npu.area
report_resource >  Report/npu.resource
report_power > Report/$DESIGN\.power

#======================================================
#  Change Naming Rule
#======================================================
set bus_inference_style "%s\[%d\]"
set bus_naming_style "%s\[%d\]"
set hdlout_internal_busses true

change_names -hierarchy -rule verilog

define_name_rules name_rule -allowed "a-z A-Z 0-9 _" -max_length 255 -type cell
define_name_rules name_rule -allowed "a-z A-Z 0-9 _[]" -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
change_names -hierarchy -rules name_rule

#======================================================
#  Output Results
#======================================================

set verilogout_higher_designs_first true
write -format verilog -output Netlist/npu_SYN.v -hierarchy
write_sdf -version 2.1 -context verilog -load_delay cell Netlist/npu_SYN.sdf
report_area
report_timing
#======================================================
#  Finish and Quit
#======================================================
# exit
