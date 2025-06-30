#======================================================
#
# Synopsys Design Compiler Synthesis Script (dctcl mode)
#======================================================
#
#  開啟多核心加速
#  - multithreading_mode: 開啟內部多執行緒模式
#  - set_option -threads: 指定要使用的執行緒數
#  - OMP_NUM_THREADS: 部分底層模組會讀取此環境變數
#======================================================
set multithreading_mode on
set_option -threads 64
set ::env(OMP_NUM_THREADS) 64 
 
 #======================================================
#
# Synopsys Synthesis Scripts (Design Vision dctcl mode)
#
#======================================================

#======================================================
#  Set Libraries
#======================================================
# set search_path    {./ \
# 			./../RTL \
# 		    /usr/cad/synopsys/synthesis/2019.12/libraries/syn/ \
#                    /usr/cad/cell_lib/CBDK45_FreePDK_TSRI_v1.1/lib/ 
# 	    	   }

# set synthetic_library {dw_foundation.sldb}
# set link_library {* dw_foundation.sldb standard.sldb freepdk45_v1_t0.db}
# set target_library {freepdk45_v1_t0.db}

set search_path "
    ./ \
    ./../RTL \
    /usr/cad/synopsys/synthesis/2024.09/libraries/syn/ \
    /usr/cad/synopsys/synthesis/2024.09/dw \
    /home/tsaijb/saed_28nm/CORE/RVT/SAED32_EDK/lib/stdcell_rvt/db_nldm \
    /usr/cad/synopsys/synthesis/cur/dw/sim_ver
"

# 指定合成用的標準 cell library
set synthetic_library {dw_foundation.sldb}
set link_library {* dw_foundation.sldb standard.sldb saed32rvt_tt1p05v25c.db}
# set target_library {saed32rvt_ff0p95v25c.db}
set target_library {saed32rvt_tt1p05v25c.db}

#======================================================
#  Global Parameters
#======================================================
set DESIGN "npu"
set hdlin_ff_always_sync_set_reset true
set CYCLE 7.0

#======================================================
#  Read RTL Code
#======================================================
analyze -f sverilog -define {synthesis=1} {
    npu.v
    axi_stream_output.v
    axi_stream_input.v
    element_wise.v
    GEMM.v
    multi_sram.v
    mac.v
    convolution.v
    sram_controller.v
    MultiplyByQuantizedMultiplier.v
    MultiplyByQuantizedMultiplierSmallerThanOneExp.v
    RoundingDivideByPOT.v
    exp.v
    reciprocal_over_1.v
	sram_64bits.v
    op_decoder.v
    repacker.v
    ADD.v
    ADD_Element.v
    SUB.v
    SUB_Element.v
    MUL.v
    MUL_Element.v
    broadcast_unit.v
    DW_mult_pipe.v
    DW02_mult.v
    params.vh
}
# analyze -f sverilog npu.v
elaborate $DESIGN
current_design $DESIGN

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
# set_multicycle_path -setup 2 -through {exp_pipeline/*}

# ---------- Fan‑out constraint (legacy‑safe) ----------
set_max_fanout 20 [get_ports s00_axis_aresetn]
# 1. 取出所有 net
set all_nets   [get_nets -hier]
# 2. 去掉 clock net
# 2. 去掉 clock net (舊版無 all_clock_nets，改用 filter)
set clk_nets [get_nets -hier -filter {is_clock == true}]
set tmp_nets [remove_from_collection $all_nets $clk_nets]
# 3. 去掉 constant net
set const_nets [get_nets -hier -filter {is_constant == true}]
set tmp_nets2  [remove_from_collection $tmp_nets $const_nets]
# 4. 再去掉 top‑level I/O port net (output 無法設 fanout)
set port_nets  [get_nets -hier -filter {is_port == true}]
set data_nets  [remove_from_collection $tmp_nets2 $port_nets]
# 5. 只有非空才設 max_fanout，避免 CMD‑036 及 UID‑91
if {[sizeof_collection $data_nets] > 0} {
    set_max_fanout 64 $data_nets
}

#======================================================
#  Link the Design
#======================================================
# define_black_box sram_64bits
# define_black_box sram
set hdlin_infer_multibit_memories true 
# 把 clock 過濾掉再設限制
# set all_non_clk_inputs [remove_from_collection [all_inputs] [get_ports clk]]
# set_max_fanout 128 $all_non_clk_inputs

link


#======================================================
#  Optimization
#======================================================
uniquify
set_fix_multiple_port_nets -all -buffer_constants
set_max_delay $CYCLE -from [all_registers] -to [all_registers]
# 限制 transition 不超過 0.3ns，cap 不超過 0.05pF
set_max_transition 0.3 [current_design]
set_max_capacitance 0.05 [current_design]
set_optimize_registers true
set_dont_touch DW_mult_pipe_*
set_false_path -from s00_axis_aresetn
set_false_path -from m00_axis_aresetn
compile_ultra -gate_clock -timing_high_effort
# compile_ultra 

##############################
# 6. Post‑compile fan‑out check (legacy) #
##############################
set hi_fan [get_nets -hier -filter {fanout > 64 && is_clock == false && is_constant == false}]
puts "[sizeof_collection $hi_fan] nets still have fanout >64 after compile"
foreach n $hi_fan {
    set f [get_attribute $n fanout]
    if {$f <= 96} {
        insert_buffer -gate BUFX4_RVT $n
    } elseif {$f <= 160} {
        insert_buffer -gate BUFX8_RVT $n
    } else {
        insert_buffer -gate BUFX12_RVT $n
    }
}


#======================================================
#  Output Reports 
#======================================================
check_design > Report/$DESIGN\.check
report_timing  >  Report/$DESIGN\.timing
# report_timing -path full -max_paths 10 >  Report/npu.timing
report_area >  Report/$DESIGN\.area
report_resource >  Report/$DESIGN\.resource
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
write -format verilog -output Netlist/$DESIGN\_SYN.v -hierarchy
write_sdf -version 2.1 -context verilog -load_delay cell Netlist/$DESIGN\_SYN.sdf
report_area
report_timing
# report_reference -hierarchy
# report_timing -max_paths 10
#======================================================
#  Finish and Quit
#======================================================
# exit
#==========================