# Makefile for VCS Simulation and Verdi Waveform

# Define directories
RTL_DIR = RTL
TESTBENCH_DIR = testbench
DW_DIR = /usr/cad/synopsys/synthesis/cur/dw/sim_ver

# Define design module
DESIGN_FILE = npu.v
TESTBENCH_FILE = tb_model.sv
# TESTBENCH_FILE = tb_exp.v

# Define source files
DESIGN_SRC = $(RTL_DIR)/$(DESIGN_FILE) $(RTL_DIR)/GEMM.v $(RTL_DIR)/element_wise.v \
			 $(RTL_DIR)/multi_sram.v $(RTL_DIR)/mac.v  $(RTL_DIR)/axi_stream_output.v \
			 $(RTL_DIR)/axi_stream_input.v $(RTL_DIR)/convolution.v $(RTL_DIR)/sram_controller.v \
			 $(RTL_DIR)/MultiplyByQuantizedMultiplier.v $(RTL_DIR)/RoundingDivideByPOT.v \
			 $(RTL_DIR)/exp.v $(RTL_DIR)/reciprocal_over_1.v $(RTL_DIR)/FIFO.v $(RTL_DIR)/sram_64bits.v \
			 $(RTL_DIR)/ADD.v $(RTL_DIR)/ADD_Element.v $(RTL_DIR)/MultiplyByQuantizedMultiplierSmallerThanOneExp.v \
			 $(RTL_DIR)/axi4_lite_decoder.v $(RTL_DIR)/SUB.v $(RTL_DIR)/SUB_Element.v \
			 $(RTL_DIR)/MUL.v $(RTL_DIR)/MUL_Element.v $(RTL_DIR)/repacker.v $(RTL_DIR)/op_decoder.v \
			 $(RTL_DIR)/broadcast_unit.v $(DW_DIR)/DW_mult_pipe.v $(DW_DIR)/DW02_mult.v
			 

# DESIGN_ALL = $(RTL_DIR)/*.v
TB_SRC = $(TESTBENCH_DIR)/$(TESTBENCH_FILE)

# Define output files
SIMV = simv
VCS_DUMP = vcs.vcd
VERDI_DUMP = verdi.fsdb

# VCS and Verdi commands
VCS = bash vcs
VERDI = verdi

# DC timing debug
DC = dc_shell
TCL_SCRIPT = debug_timing.tcl
LOG = debug_timing.log

# Verdi PLI path
VERDI_PATH = /usr/cad/synopsys/verdi/2024.09/share/PLI/VCS/linux64
DW_LIB_DIR = /usr/cad/synopsys/synthesis/cur/dw/sim_ver
# Compilation flags for VCS
CPU_NUMS=$(shell nproc --all)
VCS_FLAGS = -full64 -sverilog --debug_acc+all -debug_acc+dmptf +plusarg_save -line -j$(CPU_NUMS) \
			-y $(DW_LIB_DIR) \
			+libext+.v \
			-timescale=1ns/1ps
# GATE_SIM FLAGS
STD_CELL_V = /home/tsaijb/saed_28nm/CORE/RVT/SAED32_EDK/lib/stdcell_rvt/verilog/saed32nm.v
GATE_FLAGS = -full64 -sverilog --debug_acc+all -debug_acc+dmptf +plusarg_save -line -j$(CPU_NUMS) \
			-y $(DW_LIB_DIR) \
			+libext+.v \
			-v $(STD_CELL_V) \
			-timescale=1ns/1ps 
# VCS_FLAGS = -full64 -sverilog --debug_acc+all -debug_acc+dmptf +plusarg_save +lint=all -line -j$(CPU_NUMS) 
# +vcs+vcdpluson \
            # -P $(VERDI_PATH)/novas.tab $(VERDI_PATH)/pli.a

# Simulation flags
SIM_FLAGS = +access+r

# Include and Define flags
INC_FLAGS = +incdir+$(PWD)/$(TESTBENCH_DIR) +incdir+$(PWD)/$(RTL_DIR) 
DEFINE_FLAGS = +define+RTL +define+SIMULATION

# GATE_FILE
GATE_NAME = npu
GATE_PATH = ./02_SYN/Netlist
GATE_FILE = $(GATE_PATH)/$(GATE_NAME)_SYN.v
# Targets
all: clean compile simulate

# Compile the design and testbench
compile:
	@echo "Compiling design and testbench..."
# $(VCS) $(VCS_FLAGS) $(INC_FLAGS) $(DEFINE_FLAGS) $(RTL_DIR)/ADD.v $(RTL_DIR)/ADD_Element.v  $(TB_SRC) -o $(SIMV)
# $(VCS) $(VCS_FLAGS) $(INC_FLAGS) $(DEFINE_FLAGS) $(RTL_DIR)/broadcast_unit.v  $(TB_SRC) -o $(SIMV)
	$(VCS) $(VCS_FLAGS) $(INC_FLAGS) $(DEFINE_FLAGS) $(DESIGN_SRC)  $(TB_SRC) -o $(SIMV)

# Run the simulation
simulate: compile
	@echo "Running simulation..."
	./$(SIMV) $(SIM_FLAGS) +vcs+dumpvars+$(VCS_DUMP)

GATE_SIM:
	@echo "Running gate-level simulation..."
	$(VCS) $(GATE_FLAGS) $(INC_FLAGS) $(DEFINE_FLAGS) $(GATE_FILE) $(TB_SRC) -o $(SIMV)
	./$(SIMV) $(SIM_FLAGS) +vcs+dumpvars+$(VCS_DUMP)
# View the waveform in Verdi
verdi:
	@echo "Launching Verdi..."
# echo "$(RTL_DIR)/repacker.v" > filelist.f
	echo "$(TB_SRC)" > filelist.f
	echo "$(DESIGN_SRC) " >> filelist.f
	$(VERDI) $(VERDI_FLAGS) -ssf $(VERDI_DUMP) -f filelist.f &

synthesis:
	@echo "Running synthesis..."
	cd 02_SYN && time ./01_syn

timing_debug:
	@echo "===> Running DC for quick timing debug..."
	$(DC) -f $(TCL_SCRIPT) | tee $(LOG)
# Clean up intermediate and output files
clean:
	@echo "Cleaning up..."
	rm -rf csrc DVEfiles simv.daidir ucli.key $(SIMV) $(VCS_DUMP) $(VERDI_DUMP) *.log *.vpd *.vcd filelist.f tmp_dir_* verdi.fsdb.*

.PHONY: all compile simulate verdi clean
