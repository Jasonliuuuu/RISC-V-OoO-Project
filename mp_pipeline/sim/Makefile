SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

PKG_SRCS := $(PWD)/../pkg/types.sv
HDL_SRCS := $(shell find $(PWD)/../hdl -name '*.sv')
HVL_SRCS := $(shell find $(PWD)/../hvl -name '*.sv' -o -name '*.v')
HDRS := $(shell find $(PWD)/../hvl -name '*.svh')
SRCS := $(PKG_SRCS) $(HDL_SRCS) $(HVL_SRCS)

# QuestaSim/ModelSim 的路径
VSIM = /clear/apps/elec8/bin/vsim
VLOG = /clear/apps/elec8/bin/vlog
VLIB = /clear/apps/elec8/bin/vlib

# Flags
VLOG_FLAGS = -sv +acc -timescale 1ns/1ns
VSIM_FLAGS = -voptargs=+acc -suppress 3829

WORK_LIB = work

.PHONY: create_lib
create_lib:
	@mkdir -p run
	@if [ ! -d "$(WORK_LIB)" ]; then $(VLIB) $(WORK_LIB); fi

run/top_tb: create_lib $(SRCS) $(HDRS)
	python3 ../bin/rvfi_reference.py
	$(VLOG) $(VLOG_FLAGS) -work $(WORK_LIB) $(SRCS) +incdir+../hvl +incdir+../pkg -l run/top_tb_compile.log
	@echo "Compilation successful"

.PHONY: run_random
run_random: run/top_tb
	$(VSIM) $(VSIM_FLAGS) -c -do "run -all; quit -f" work.top_tb -l run/random_tb_sim.log

.PHONY: run_random_gui
run_random_gui: run/top_tb
	$(VSIM) $(VSIM_FLAGS) work.top_tb

.PHONY: clean
clean:
	rm -rf work run transcript vsim.wlf *.log modelsim.ini

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make sim/top_tb      - Compile design"
	@echo "  make run_random      - Run random testbench (no GUI)"
	@echo "  make run_random_gui  - Run random testbench (with GUI)"
	@echo "  make clean           - Clean all generated files"