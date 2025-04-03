# RISC-V-Processor

This project implements a 32-bit RISC-V processor with both pipelined and out-of-order versions. It also includes support for memory hierarchy, simulation, synthesis, and formal verification.

## 🔁 Project Structure

### `mp_setup/`
This is the **setup environment**. It helps you become familiar with the design flow:
- RTL simulation with QuestaSim
- Linting using Spyglass
- Synthesis flow using Design Compiler
- Directories:
  - `hdl/`: RTL source files for testing
  - `hvl/`: Testbenches and simulation drivers
  - `synth/`: Synthesis scripts (e.g. `synthesis.tcl`)
  - `lint/`: Spyglass scripts for static lint check
  - `sim/`: Simulation Makefile and logs
  - `doc/`: Contains diagrams and flow documentation

### `mp_pipeline/`
Implements a **pipelined in-order RISC-V processor**.
- `hdl/`: Main processor modules
- `sim/`, `synth/`: Simulation and synthesis support
- `testcode/`: Simple assembly or test programs

### `mp_cache/`
Implements a basic **memory hierarchy**:
- Instruction and data cache (I$ and D$)
- May include SRAM or tag logic for set-associative caches

### `mp_verif/`
Verification infrastructure:
- SystemVerilog testbench framework
- Constrained random instruction generation (`randinst.svh`)
- Functional coverage model (`instr_cg.svh`)
- RVFI-based verification and Spike trace comparison
- Sub-tasks:
  - `sv_refresher/`: LFSR module
  - `common_issues/`: Buggy ALU to debug and fix
  - `comb_loop/`: Fix combinational loop
  - `constr_rand_cov/`: Write constraints and coverage
  - `main_verif/`: Run verification on a multicycle RISC-V CPU

### `out-of-order-final-version/`
Implements the **final out-of-order RISC-V processor**, including:
- Tomasulo-style execution
- Reservation stations, ROB, and renaming logic
- Integrated instruction and data memory
- Complete RTL files and simulation support

---

## 🔧 Design Flow

1. **RTL Coding**: Design modules in SystemVerilog (found in `hdl/`)
2. **Linting**: Use Spyglass (e.g., `make lint`) to catch structural RTL issues
3. **Simulation**: Run testbenches with Questa (`make run_alu_tb`)
4. **Synthesis**: Use Design Compiler with `.lib` and `.db` files to synthesize and check timing
5. **Formal Verification**: Use RVFI and Spike for functional correctness
6. **Final Integration**: Combine everything into the `out-of-order-final-version`

---

## 📦 Requirements

- Synopsys Spyglass (for linting)
- Synopsys Design Compiler (for synthesis)
- QuestaSim (for simulation)
- Spike (for golden RISC-V trace comparison)
- Python/Make (build automation)

---

## ✍️ Author

**Tsung-Yu Liu**  
Rice University · Master of Electrical & Computer Engineering  
Email: jason890418123@gmail.com  
GitHub: [@Jasonliuuuu](https://github.com/Jasonliuuuu)
