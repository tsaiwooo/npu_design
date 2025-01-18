# Makefile for VCS Simulation and Verdi Waveform

# Define directories
RTL_DIR = RTL
TESTBENCH_DIR = testbench

# Define design module
DESIGN_FILE = npu.v
TESTBENCH_FILE = tb_npu3.v

# Define source files
DESIGN_SRC = $(RTL_DIR)/$(DESIGN_FILE) $(RTL_DIR)/GEMM.v $(RTL_DIR)/element_wise.v \
			 $(RTL_DIR)/multi_sram.v $(RTL_DIR)/mac.v  $(RTL_DIR)/sram.v $(RTL_DIR)/axi_stream_output.v \
			 $(RTL_DIR)/axi_stream_input.v $(RTL_DIR)/convolution.v $(RTL_DIR)/sram_controller.v \
			 $(RTL_DIR)/MultiplyByQuantizedMultiplier.v $(RTL_DIR)/RoundingDivideByPOT.v \
			 $(RTL_DIR)/exp.v $(RTL_DIR)/reciprocal_over_1.v $(RTL_DIR)/FIFO.v $(RTL_DIR)/sram_64bits.v \
			 

# DESIGN_ALL = $(RTL_DIR)/*.v
TB_SRC = $(TESTBENCH_DIR)/$(TESTBENCH_FILE)

# Define output files
SIMV = simv
VCS_DUMP = vcs.vcd
VERDI_DUMP = verdi.fsdb

# VCS and Verdi commands
VCS = bash vcs
VERDI = verdi

# Verdi PLI path
VERDI_PATH = /usr/cad/synopsys/verdi/2024.09/share/PLI/VCS/linux64

# Compilation flags for VCS
CPU_NUMS=$(shell nproc --all)
VCS_FLAGS = -full64 -sverilog --debug_acc+all -debug_acc+dmptf +plusarg_save -line -j$(CPU_NUMS) 
# VCS_FLAGS = -full64 -sverilog --debug_acc+all -debug_acc+dmptf +plusarg_save +lint=all -line -j$(CPU_NUMS) 
# +vcs+vcdpluson \
            # -P $(VERDI_PATH)/novas.tab $(VERDI_PATH)/pli.a

# Simulation flags
SIM_FLAGS = +access+r

# Include and Define flags
INC_FLAGS = +incdir+$(PWD)/$(TESTBENCH_DIR) +incdir+$(PWD)/$(RTL_DIR)
DEFINE_FLAGS = +define+RTL

# Targets
all: clean compile simulate

# Compile the design and testbench
compile:
	@echo "Compiling design and testbench..."
# $(VCS) $(VCS_FLAGS) $(INC_FLAGS) $(DEFINE_FLAGS) $(RTL_DIR)/MultiplyByQuantizedMultiplier.v  $(TB_SRC) -o $(SIMV)
	$(VCS) $(VCS_FLAGS) $(INC_FLAGS) $(DEFINE_FLAGS) $(DESIGN_SRC)  $(TB_SRC) -o $(SIMV)

# Run the simulation
simulate: compile
	@echo "Running simulation..."
	./$(SIMV) $(SIM_FLAGS) +vcs+dumpvars+$(VCS_DUMP)

# View the waveform in Verdi
verdi:
	@echo "Launching Verdi..."
# echo "$(RTL_DIR)/FIFO.v " > filelist.f
	echo "$(DESIGN_SRC) " > filelist.f
	echo "$(TB_SRC)" >> filelist.f
	$(VERDI) $(VERDI_FLAGS) -ssf $(VERDI_DUMP) -f filelist.f &

# Clean up intermediate and output files
clean:
	@echo "Cleaning up..."
	rm -rf csrc DVEfiles simv.daidir ucli.key $(SIMV) $(VCS_DUMP) $(VERDI_DUMP) *.log *.vpd *.vcd filelist.f tmp_dir_* verdi.fsdb.*

.PHONY: all compile simulate verdi clean
