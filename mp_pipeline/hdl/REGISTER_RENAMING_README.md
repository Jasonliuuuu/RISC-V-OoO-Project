# Register Renaming Implementation Guide

## 📋 Overview

This document describes the **register renaming implementation** added to the base 5-stage pipelined RISC-V processor from the `main` branch. Register renaming eliminates false dependencies (WAR and WAW hazards) and enables better instruction-level parallelism.

---

## 🏗️ Architecture Summary

### Base Processor (main branch)
- **5-stage pipeline**: Fetch → Decode → Execute → Memory → Writeback
- **Architectural Register File (ARF)**: 32 registers (x0-x31)
- **Hazard handling**: Forwarding + stall on load-use hazards
- **Verified**: 90,000+ random instructions, 100% RV32I coverage

### Register Renaming Extension (rename-unit branch)
- **Physical Register File (PRF)**: 64 physical registers
- **Register Alias Table (RAT)**: Maps architectural → physical registers
- **Free List**: Tracks available physical registers
- **Rename Unit**: Manages allocation and deallocation
- **Commit-based recovery**: Old physical registers freed on commit

---

## 🧩 New Components

### 1. Physical Register File (`prf.sv`)

Replaces the architectural register file with a larger physical register file.

```systemverilog
module prf (
    input  logic        clk, rst,
    input  logic        we,
    input  logic [5:0]  wr_phys,      // 6-bit for 64 regs
    input  logic [31:0] wr_data,
    input  logic [5:0]  rd_phys_1,
    input  logic [5:0]  rd_phys_2,
    output logic [31:0] rd_data_1,
    output logic [31:0] rd_data_2
);
    logic [31:0] data [64];  // 64 physical registers
    
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 64; i++) data[i] <= '0;
        end else if (we && wr_phys != 6'd0) begin
            data[wr_phys] <= wr_data;
        end
    end
    
    assign rd_data_1 = (rd_phys_1 != 6'd0) ? data[rd_phys_1] : 32'd0;
    assign rd_data_2 = (rd_phys_2 != 6'd0) ? data[rd_phys_2] : 32'd0;
endmodule
```

**Key Features**:
- 64 registers (vs 32 in ARF)
- Dual-read, single-write ports
- Register 0 hardwired to zero

---

### 2. Free List (`free_list.sv`)

Manages the pool of available physical registers.

```systemverilog
module free_list (
    input  logic        clk, rst,
    // Allocation interface
    input  logic        alloc_valid,
    output logic [5:0]  alloc_phys,
    // Deallocation (commit) interface  
    input  logic        free_valid,
    input  logic [5:0]  free_phys,
    // Flush recovery interface
    input  logic [4:0]  flush_free_count,
    input  logic [5:0]  flush_free_phys [15:0],
    // Status
    output logic [5:0]  count
);
```

**Allocation Strategy**: FIFO circular buffer
- Allocates from `head`, increments head pointer
- Deallocates to `tail`, increments tail pointer
- Supports bulk deallocation on pipeline flush

**Critical Invariant**: `count` should never reach 0 during execution

---

### 3. Rename Unit (`rename_unit.sv`)

The core of the register renaming system. Manages the Register Alias Table (RAT) and coordinates with the free list.

```systemverilog
module rename_unit (
    input  logic        clk, rst,
    // Decode interface - lookup
    input  logic [4:0]  rs1_arch, rs2_arch, rd_arch,
    output logic [5:0]  rs1_phys, rs2_phys,
    output logic [5:0]  dest_phys_new,
    output logic [5:0]  dest_phys_old,
    input  logic        alloc_valid,
    // Writeback interface - commit
    input  logic        commit_we,
    input  logic [4:0]  commit_arch,
    input  logic [5:0]  commit_phys,
    input  logic [5:0]  commit_old_phys,
    // Flush interface
    input  logic        flush_pipeline,
    ...
);
```

**Register Alias Table (RAT)**:
```systemverilog
logic [5:0] rat [32];  // Maps x0-x31 to physical registers

//初始化：每個architectural register映射到對應的physical register
always_ff @(posedge clk) begin
    if (rst) begin
        for (int i = 0; i < 32; i++) rat[i] <= 6'(i);
    end
end
```

**Lookup (Decode Stage)**:
```systemverilog
assign rs1_phys = rat[rs1_arch];
assign rs2_phys = rat[rs2_arch];
assign dest_phys_old = rat[rd_arch];
```

**Allocation (Decode Stage)**:
```systemverilog
if (alloc_valid && rd_arch != 5'd0) begin
    rat[rd_arch] <= dest_phys_new;  // Update RAT to new phys reg
end
```

**Deallocation (Writeback/Commit)**:
```systemverilog
// Free the OLD physical register when instruction commits
if (commit_we) begin
    free_list.free_valid <= 1'b1;
    free_list.free_phys <= commit_old_phys;
end
```

---

## 🔄 Data Flow Through Pipeline

### Stage 1: Fetch
**Unchanged** from base processor.

---

### Stage 2: Decode
**Modified** to integrate register renaming:

```systemverilog
// Old (main branch):
output logic [31:0] rs1_v, rs2_v  // From architectural regfile

// New (rename-unit branch):
input  logic [5:0]  rs1_phys, rs2_phys      // From rename_unit (RAT)
input  logic [31:0] rs1_val, rs2_val         // From PRF
output logic [5:0]  dest_phys_new, dest_phys_old  // To pipeline
```

**Process**:
1. **Lookup** rs1, rs2, rd in rename_unit → get physical register numbers
2. **Allocate** new physical register for rd (if rd ≠ x0)
3. **Read** rs1_phys and rs2_phys from PRF
4. **Propagate** physical register numbers through pipeline

---

### Stage 3: Execute
**Minimal changes**:
- Forwarding now uses **physical** register numbers
- Branch resolution triggers flush (same as before)

---

### Stage 4: Memory
**Key Addition**: MEM/WB flush

```systemverilog
// Critical fix for speculation
assign mem_wb.valid = flush_pipeline ? 1'b0 : ex_mem.valid;
```

This prevents speculative instructions from committing after a flush.

---

### Stage 5: Writeback
**Modified** to commit to PRF and notify rename_unit:

```systemverilog
// Write to PRF (not architectural regfile)
assign prf_we = commit && regf_we_back;
assign prf_wr_phys = mem_wb.dest_phys_new;
assign prf_wr_data = regfilemux_out;

// Notify rename_unit to free old physical register
assign commit_we = commit && (mem_wb.dest_arch != 5'd0);
assign commit_arch = mem_wb.dest_arch;
assign commit_phys = mem_wb.dest_phys_new;
assign commit_old_phys = mem_wb.dest_phys_old;
```

---

## 🎯 Example: Register Renaming in Action

### Instruction Sequence
```assembly
1. ADD x1, x2, x3   # x1 = x2 + x3
2. SUB x4, x1, x5   # x4 = x1 - x5  (RAW hazard!)
3. ADD x1, x6, x7   # x1 = x6 + x7  (WAW hazard!)
4. MUL x8, x1, x9   # x8 = x1 * x9  (RAW hazard!)
```

### Without Register Renaming (main branch)
```
Inst 1: x1 = p1 (architectural x1)
Inst 2: RAW on x1 → need forwarding
Inst 3: WAW on x1 → must stall or serialize
Inst 4: RAW on x1 → need forwarding
```

### With Register Renaming (rename-unit branch)
```
Initial: x1 → p1

Decode Inst 1:
  rs1 = x2 → p2
  rs2 = x3 → p3  
  rd = x1 → allocate p33 (new mapping: x1 → p33)
  old_phys = p1

Decode Inst 2:
  rs1 = x1 → p33 (from RAT!)  ← No RAW hazard!
  rs2 = x5 → p5
  rd = x4 → allocate p34
  
Decode Inst 3:
  rs1 = x6 → p6
  rs2 = x7 → p7
  rd = x1 → allocate p35 (new mapping: x1 → p35)  ← No WAW hazard!
  old_phys = p33
  
Decode Inst 4:
  rs1 = x1 → p35 (latest mapping!)
  rs2 = x9 → p9
  rd = x8 → allocate p36
```

**Result**: All false dependencies eliminated!

---

## ⚠️ Critical Design Decisions

### 1. Eager Allocation at Decode
**Decision**: Allocate physical registers immediately in decode stage.

**Pros**:
- Simple, deterministic allocation
- RAT always up-to-date

**Cons**:
- **Register leaks** if speculative instructions are flushed
- Requires robust flush recovery mechanism

---

### 2. Commit-Based Deallocation
**Decision**: Free old physical registers only when instruction commits (writeback stage).

**Pros**:
- Ensures register contains valid data until no longer needed
- Safe for out-of-order commit (within constraints)

**Cons**:
- Delays register recycling
- Higher physical register pressure

---

### 3. Speculation Handling
**Decision**: Initially blocked speculative commits (FIX #6), later removed and relied on flush recovery.

**Evolution**:
```systemverilog
// Initial approach (FIX #6) - REMOVED
if (mem_wb.is_speculative) begin
    commit <= 1'b0;  // Block speculative commits
end

// Current approach: Allow speculative commits + flush recovery
// Flush returns allocated-but-not-committed phys regs to free list
```

---

## 🔧 Flush Recovery System

### Current Implementation: Pending Allocation FIFO (Option C)

**Data Structure**:
```systemverilog
typedef struct packed {
    logic       valid;
    logic [63:0] order;
    logic [4:0] arch_reg;
    logic [5:0] phys_reg;
    logic [5:0] old_phys;
    logic       is_spec;
} pending_alloc_entry_t;

pending_alloc_entry_t pending_allocs [16];
logic [3:0] pending_head, pending_tail;
logic [4:0] pending_count;
```

**Allocation Tracking (Push)**:
```systemverilog
if (alloc_valid && rd != 5'd0) begin
    pending_allocs[pending_head].valid    <= 1'b1;
    pending_allocs[pending_head].arch_reg <= rd;
    pending_allocs[pending_head].phys_reg <= dest_phys_new;
    pending_allocs[pending_head].old_phys <= dest_phys_old;
    pending_head <= pending_head + 1;
    pending_count <= pending_count + 1;
end
```

**Commit Tracking (Pop)**:
```systemverilog
if (commit_we && commit_arch != 5'd0) begin
    pending_allocs[pending_tail].valid <= 1'b0;
    pending_tail <= pending_tail + 1;
    pending_count <= pending_count - 1;
end
```

**Flush Recovery**:
```systemverilog
if (flush_pipeline) begin
    for (int i = 0; i < PENDING_ALLOC_DEPTH; i++) begin
        if (pending_allocs[i].valid) begin
            flush_free_phys[flush_free_count] <= pending_allocs[i].phys_reg;
            flush_free_count <= flush_free_count + 1;
        end
    end
    // Reset FIFO
    pending_head <= 4'd0;
    pending_tail <= 4'd0;
    pending_count <= 5'd0;
end
```

---

## 📊 Verification & Testing

### RVFI Modifications
Updated RVFI signals to track physical registers:

```systemverilog
// Writeback stage outputs
output logic [5:0]  dest_phys_new;   // NEW: for rename tracking
output logic [5:0]  dest_phys_old;   // NEW: for free list

// RVFI still reports ARCHITECTURAL registers
assign rvfi_rd_addr = mem_wb.dest_arch;  // Architectural x1-x31
assign rvfi_rd_wdata = (rvfi_rd_addr == 5'd0) ? 32'd0 : rd_v;
```

**Critical**: RVFI must show architectural state, not physical implementation.

---

### Debug Instrumentation
Added extensive logging:

```systemverilog
$display("[RENAME] x%0d: old=p%0d → new=p%0d", rd, old_phys, new_phys);
$display("[COMMIT] x%0d: free old p%0d", arch, old_phys);
$display("[FREE_LIST] alloc=p%0d, free=p%0d, count: %0d→%0d", ...);
$display("[FIFO PUSH] order=%0d x%0d→phys=%0d", order, arch, phys);
```

---

## 🚧 Known Limitations & Future Work

### Current Status
✅ **Implemented**:
- Physical register file (64 regs)
- Register Alias Table (RAT)
- Free list with allocation/deallocation
- Basic flush recovery (FIFO-based)
- RVFI integration

❌ **Known Issues**:
- FIFO push/pop mismatches due to out-of-order commits
- Free list exhaustion under certain workloads
- Shadow RS2 RVFI errors persist

### Recommended Next Steps

#### 1. Switch to Table-Based Pending Allocation Tracking
Replace FIFO with associative structure to handle out-of-order commits:

```systemverilog
// Instead of FIFO (head/tail), use valid bits + search
pending_alloc_entry_t pending_table [16];

// Commit: search for matching entry
for (int i = 0; i < 16; i++) begin
    if (pending_table[i].valid && 
        pending_table[i].arch_reg == commit_arch &&
        pending_table[i].phys_reg == commit_phys) begin
        pending_table[i].valid <= 1'b0;
        break;
    end
end
```

#### 2. Implement Reorder Buffer (ROB)
For true out-of-order execution and precise exceptions:
- Track instruction order
- Allow out-of-order completion
- Commit in-order

#### 3. Increase Physical Register Count
Consider 96 or 128 physical registers to reduce pressure.

---

## 📚 File Manifest

### New Files (rename-unit branch)
```
hdl/
├── prf.sv                    # Physical Register File
├── rename_unit.sv            # RAT + Rename Logic
├── free_list.sv              # Free List Manager
└── pipeline/
    ├── decode.sv             # Modified for renaming
    ├── writeback.sv          # Modified for commit
    └── memstage.sv           # Added MEM/WB flush
```

### Modified Files
```
hdl/
├── cpu.sv                    # Integrated rename_unit, prf, free_list
├── Forward.sv                # Updated for physical registers
└── pipeline/
    ├── execute.sv            # Pass phys regs through pipeline
    └── fetch.sv              # Unchanged
```

---

## 🔍 Key Takeaways

1. **Register renaming eliminates false dependencies** (WAR, WAW)
2. **Eager allocation** requires robust flush recovery
3. **Commit-based deallocation** ensures correctness but increases register pressure
4. **FIFO assumptions break** under flush-induced reordering
5. **Table-based tracking** recommended for production implementation

---

## 📖 References

- [Tomasulo's Algorithm](https://en.wikipedia.org/wiki/Tomasulo_algorithm)
- [Computer Architecture: A Quantitative Approach](https://www.elsevier.com/books/computer-architecture/hennessy/978-0-12-811905-1) - Hennessy & Patterson
- [Modern Processor Design](https://www.waveland.com/browse.php?t=392) - Shen & Lipasti
- Main branch baseline: `git checkout main`

---

*Last Updated: November 2025*  
*Author: Design Team*  
*Branch: `rename-unit`*
