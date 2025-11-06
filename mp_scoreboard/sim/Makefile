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
VCOVER = /clear/apps/elec8/bin/vcover

# Flags
VLOG_FLAGS = -sv +acc -timescale 1ns/1ns -cover bcefst
VSIM_FLAGS = -voptargs=+acc -suppress 3829 -coverage

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
	@echo "Running random testbench with coverage..."
	$(VSIM) $(VSIM_FLAGS) -c \
		-onfinish stop \
		-do "run -all; coverage save vsim.ucdb; quit -f" \
		work.top_tb -l run/random_tb_sim.log
	@if [ -f vsim.ucdb ]; then \
		echo "Coverage database created: vsim.ucdb"; \
	else \
		echo "Warning: vsim.ucdb not created"; \
	fi

.PHONY: run_random_gui
run_random_gui: run/top_tb
	$(VSIM) $(VSIM_FLAGS) work.top_tb \
		-do "coverage save -onexit vsim.ucdb"

.PHONY: coverage
coverage:
	@if [ ! -f vsim.ucdb ]; then \
		echo "Error: vsim.ucdb not found. Run 'make run_random' first."; \
		exit 1; \
	fi
	@echo "Generating coverage report..."
	@rm -rf coverage_report
	/clear/apps/elec8/bin/vsim -c -viewcov vsim.ucdb \
		-do "coverage report -html -output coverage_report -detail -cvg; quit" 2>&1 | \
		grep -v "^#" || true
	@if [ -f coverage_report/index.html ]; then \
		echo "✓ Coverage report generated: coverage_report/index.html"; \
		echo "  Open with: firefox coverage_report/index.html"; \
	else \
		echo "HTML generation failed, creating text report..."; \
		/clear/apps/elec8/bin/vsim -c -viewcov vsim.ucdb \
			-do "coverage report -detail -cvg -output coverage.txt; quit"; \
		echo "✓ Text report: coverage.txt"; \
	fi

.PHONY: clean
clean:
	rm -rf work run transcript vsim.wlf *.log modelsim.ini vsim.ucdb coverage_report

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make run/top_tb      - Compile design"
	@echo "  make run_random      - Run random testbench with coverage"
	@echo "  make run_random_gui  - Run random testbench (GUI mode)"
	@echo "  make coverage        - Generate HTML coverage report"
	@echo "  make clean           - Clean all generated files"
