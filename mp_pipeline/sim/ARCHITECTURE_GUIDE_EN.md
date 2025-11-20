# Pipeline Architecture & Register Renaming Implementation Guide

## Table of Contents
1. [HDL Module Functions](#hdl-module-functions)
2. [Register Renaming Architecture](#register-renaming-architecture)
3. [Implementation Details](#implementation-details)
4. [Data Flow Analysis](#data-flow-analysis)

---

## HDL Module Functions

### 📁 Pipeline Stages (hdl/pipeline/)

#### 1. **fetch.sv** - Instruction Fetch Stage
**Functions:**
- Fetch instructions from instruction memory
- Maintain PC (Program Counter)
- Handle branch/jump PC updates
- Implement pipeline flush (IF/ID flush)

**Key Signals:**
- Inputs: `pc_next` (next PC value), `flush_pipeline`
- Outputs: `if_id_reg` (IF/ID pipeline register), `imem_rdata_id` (instruction)

#### 2. **decode.sv** - Instruction Decode Stage  
**Functions:**
- Instruction decoding (opcode, funct3, funct7)
- Generate immediates (I-type, S-type, B-type, U-type, J-type)
- Set ALU, CMP, MUX control signals
- **✨ Register renaming lookup (Important!)**
- Read physical register values from PRF
- Implement ID/EX flush

**Key Modifications (Register Renaming):**
```systemverilog
// Get physical register numbers from rename_unit
input logic [5:0] rs1_phys, rs2_phys, dest_phys_new, dest_phys_old;

// Read physical register values from PRF
input logic [31:0] rs1_val, rs2_val;

// Pass to pipeline
id_ex.rs1_phys = rs1_phys;  // Not rs1_s!
id_ex.rs2_phys = rs2_phys;
id_ex.rs1_v = rs1_val;      // Values directly from PRF
id_ex.rs2_v = rs2_val;
```

#### 3. **execute.sv** - Execute Stage
**Functions:**
- ALU operations (add, sub, xor, or, and, sll, srl, sra)
- Comparator (CMP) for branch decisions
- Forwarding logic for data hazards
- Compute branch target address
- Implement EX/MEM flush

**Modifications:**
- Pass physical register numbers to next stage
- Forwarding based on physical register numbers (not architectural)

#### 4. **memstage.sv** - Memory Access Stage
**Functions:**
- Handle load/store instructions
- Calculate memory addresses
- Generate dmem control signals (rmask, wmask)
- Detect branch/jump → generate `flush_pipeline` signal
- **✨ Implement MEM/WB flush (Critical fix)**

**Key Modification:**
```systemverilog
// MEM/WB flush implementation
assign mem_wb.valid = flush_pipeline ? 1'b0 : ex_mem.valid;
```

#### 5. **writeback.sv** - Writeback Stage
**Functions:**
- Select writeback data (ALU result, load data, PC+4, etc.)
- **✨ Write to PRF**
- **✨ Notify rename_unit of commit**
- Generate RVFI verification signals

**Key Modifications (Register Renaming):**
```systemverilog
// Write to PRF (Physical Register File)
output logic        prf_we;
output logic [5:0]  prf_wr_phys;
output logic [31:0] prf_wr_data;

assign prf_we = commit && regf_we_back;
assign prf_wr_phys = mem_wb.dest_phys_new;  // Write to new physical register
assign prf_wr_data = regfilemux_out;

// Notify rename_unit of commit
output logic        commit_we;
output logic [4:0]  commit_arch;
output logic [5:0]  commit_phys;
output logic [5:0]  commit_old_phys;

assign commit_we = commit && (mem_wb.dest_arch != 5'd0);
assign commit_arch = mem_wb.dest_arch;
assign commit_phys = mem_wb.dest_phys_new;
assign commit_old_phys = mem_wb.dest_phys_old;
```

---

### 📁 Register Renaming Related Modules

#### 6. **rename_unit.sv** - Register Renaming Unit ⭐
**Functions:**
- Maintain **RAT (Register Alias Table)**: architectural → physical mapping
- In decode stage: lookup physical register numbers for rs1/rs2
- Allocate new physical register for rd
- In commit stage: update RAT
- Return old physical register to free_list

**Data Structure:**
```systemverilog
logic [5:0] RAT [31:0];  // 32 architectural → physical mappings
```

**Operation Flow:**
1. **Decode Stage Lookup:**
   ```systemverilog
   rs1_phys = RAT[rs1_arch];  // Find physical register for rs1
   rs2_phys = RAT[rs2_arch];
   old_phys = RAT[rd_arch];   // Current old physical register for rd
   ```

2. **Allocate New Physical Register:**
   ```systemverilog
   if (alloc_valid && rd_arch != 0) begin
       new_phys = alloc_phys;  // Allocated from free_list
       rename_we = 1'b1;
   end
   ```

3. **Commit Stage Update:**
   ```systemverilog
   if (commit_we && commit_arch != 0) begin
       RAT[commit_arch] <= commit_phys;  // Update mapping
       free_phys = commit_old_phys;      // Return old physical register
   end
   ```

#### 7. **free_list.sv** - Free Physical Register List
**Functions:**
- Manage allocation and deallocation of 64 physical registers
- FIFO queue structure
- Provide physical registers to rename_unit

**Initialization:**
```systemverilog
// At reset: phys 1-63 are free (phys 0 reserved for x0)
for (i = 1; i < 64; i++)
    queue[i-1] <= i[5:0];
count <= 63;
```

**Allocate (Dequeue):**
```systemverilog
alloc_phys = queue[head];
alloc_valid = (count > 0);
if (alloc_valid) head++;
```

**Free (Enqueue):**
```systemverilog
if (free_en) begin
    queue[tail] <= free_phys;
    tail++;
end
```

#### 8. **prf.sv** - Physical Register File (PRF)
**Functions:**
- 64 × 32-bit physical registers
- 2 read ports (rs1, rs2)
- 1 write port (rd)

**Key Features:**
```systemverilog
// Read is combinational (0 delay)
assign rs1_val = prf_mem[rs1_phys];
assign rs2_val = prf_mem[rs2_phys];

// Write is sequential (in writeback stage)
if (we && rd_phys != 6'd0)
    prf_mem[rd_phys] <= rd_val;
```

---

### 📁 Other Supporting Modules

#### 9. **cpu.sv** - Top-Level Module
**Functions:**
- Instantiate all pipeline stages
- Instantiate register renaming related modules
- Connect all signals
- Implement pipeline register latching

**Key Modifications:**
```systemverilog
// Instantiate register renaming modules
rename_unit rename_unit_i(...);
free_list free_list_i(...);
prf prf_i(...);

// No longer using original regfile (architectural register file)
// regfile regfile_i(...);  // Commented out
```

#### 10. **Forward.sv** - Forwarding Unit
**Functions:**
- Detect data hazards
- Generate forwarding control signals
- Resolve RAW (Read After Write) hazards

**Modification:**
```systemverilog
// Now compare physical register numbers, not architectural
if (id_ex.rs1_phys == ex_mem.dest_phys_new && ex_mem.regf_we)
    forward_a_sel = forward_amux::alu_out;
```

#### 11. **Load_hazard_stall.sv** - Load Data Hazard Handler
**Functions:**
- Detect load-use hazards
- Generate stall signal

#### 12. **freeze.sv** - Memory Stall Handler
**Functions:**
- Stall entire pipeline when imem or dmem doesn't respond

#### 13. **alu.sv** - Arithmetic Logic Unit
**Functions:**
- Arithmetic operations (add, sub)
- Logic operations (and, or, xor)
- Shift operations (sll, srl, sra)

#### 14. **cmp.sv** - Comparator
**Functions:**
- Branch condition evaluation (beq, bne, blt, bge, bltu, bgeu)

#### 15. **ir.sv** - Instruction Register
**Functions:**
- Store current executing instruction

#### 16. **regfile.sv** - Architectural Register File (Deprecated)
**Status:** ⚠️ No longer used
- Provided 32 architectural registers in original design
- Replaced by PRF after register renaming implementation
- Kept in code but not instantiated

---

## Register Renaming Architecture

### Core Concepts

**Question:** Why do we need register renaming?
1. **Eliminate WAW hazard** (Write After Write)
2. **Eliminate WAR hazard** (Write After Read)  
3. **Keep only true RAW hazard** (Read After Write - true data dependency)
4. **Enable out-of-order execution** (although this pipeline still commits in-order)

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    DECODE STAGE                             │
│                                                             │
│  Instruction → Extract rs1_arch, rs2_arch, rd_arch         │
│                         ↓                                   │
│                  ┌──────────────┐                          │
│                  │ RENAME_UNIT  │                          │
│                  │              │                          │
│    ┌─────────────┤  RAT[32]     │←──────────────┐         │
│    │             │  [arch→phys] │               │         │
│    │             └──────────────┘               │         │
│    │                    ↓                       │         │
│    │           rs1_phys, rs2_phys       Commit  │         │
│    │           new_phys, old_phys       Update  │         │
│    │                    ↓                       │         │
│    │              ┌──────────┐                  │         │
│    └──Allocate───→│FREE_LIST │←───Free──────────┘         │
│                   │ FIFO[63] │                 WB         │
│                   └──────────┘                             │
│                         ↓                                  │
│                   alloc_phys                               │
│                         ↓                                  │
│              ┌─────────────────┐                          │
│              │      PRF        │                          │
│   Read ─────→│  [0:63][31:0]  │←──── Write (from WB)     │
│              │                 │                          │
│              └─────────────────┘                          │
│                    ↓                                      │
│            rs1_val, rs2_val                               │
│                    ↓                                      │
│              ID/EX Pipeline Reg                           │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow Example

Assume executing:
```assembly
add x1, x2, x3  # instruction 1
add x4, x1, x5  # instruction 2
```

**Instruction 1 (add x1, x2, x3):**

1. **Decode Stage:**
   ```
   rs1_arch = 2, rs2_arch = 3, rd_arch = 1
   
   Rename_unit lookup:
   rs1_phys = RAT[2] = 15 (assume)
   rs2_phys = RAT[3] = 8
   old_phys = RAT[1] = 10 (x1 currently mapped to phys 10)
   
   Free_list allocation:
   alloc_phys = 20 (new physical register)
   new_phys = 20
   
   PRF read:
   rs1_val = PRF[15]
   rs2_val = PRF[8]
   ```

2. **Execute Stage:**
   ```
   result = rs1_val + rs2_val
   ```

3. **Writeback Stage:**
   ```
   PRF[20] = result  (write to new physical register)
   
   Commit to rename_unit:
   RAT[1] = 20  (update x1 mapping to phys 20)
   
   Free_list release:
   free_phys = 10  (old phys 10 can be reused)
   ```

**Instruction 2 (add x4, x1, x5):**

1. **Decode Stage:**
   ```
   rs1_arch = 1, rs2_arch = 5, rd_arch = 4
   
   Rename_unit lookup:
   rs1_phys = RAT[1] = 20 (Already updated! Points to inst1's result)
   rs2_phys = RAT[5] = 12
   old_phys = RAT[4] = 6
   
   Free_list allocation:
   alloc_phys = 21
   new_phys = 21
   ```

✅ **Hazard Eliminated!** inst2 directly reads phys 20, no forwarding or stall needed!

---

## Implementation Details

### Total Lines of Code Added

| File | Lines Added | Main Content |
|------|------------|--------------|
| **rename_unit.sv** | **100 lines** (new) | RAT logic, commit update |
| **free_list.sv** | **65 lines** (new) | FIFO management for physical registers |
| **prf.sv** | **37 lines** (new) | 64 physical registers |
| **cpu.sv** | **~50 lines** | Instantiate new modules, signal connections |
| **decode.sv** | **~30 lines** | Interface with rename_unit and PRF |
| **writeback.sv** | **~40 lines** | PRF write, commit notification |
| **Forward.sv** | **~20 lines** | Physical register number comparison |
| **execute.sv** | **~10 lines** | Pass physical register numbers |
| **memstage.sv** | **~5 lines** | Pass physical register numbers |
| **Total** | **~357 lines** | |

### Most Modified Files and Reasons

#### 🔥 **Most Modified: cpu.sv (~50 lines)**

**Reasons:**
1. Need to instantiate 3 new modules (rename_unit, free_list, prf)
2. Connect many new signals (~30 signals)
3. Remove old regfile instantiation
4. Add physical register fields to pipeline registers

**Key Code:**
```systemverilog
// New signal declarations
logic [5:0] rs1_phys, rs2_phys, dest_phys_new, dest_phys_old;
logic [31:0] prf_rs1_val, prf_rs2_val;
logic       alloc_valid;
logic [5:0] alloc_phys;
logic       free_en;
logic [5:0] free_phys;
logic       prf_we;
logic [5:0] prf_wr_phys;
logic [31:0] prf_wr_data;
logic       commit_we;
logic [4:0] commit_arch;
logic [5:0] commit_phys, commit_old_phys;

// Instantiation
rename_unit rename_unit_i(
    .clk(clk), .rst(rst),
    .rs1_arch(/*...*/),
    .rs2_arch(/*...*/),
    // ... many signals
);

free_list free_list_i(/*...*/);
prf prf_i(/*...*/);
```

#### 🔥 **writeback.sv (~40 lines)**

**Reasons:**
1. Need to write to PRF instead of regfile
2. Need to notify rename_unit of commit
3. Return old physical register to free_list
4. RVFI signals also need updates

**Key Modifications:**
```systemverilog
// New outputs
output logic prf_we;
output logic [5:0] prf_wr_phys;
output logic [31:0] prf_wr_data;

output logic commit_we;
output logic [4:0] commit_arch;
output logic [5:0] commit_phys;
output logic [5:0] commit_old_phys;

// Implementation
assign prf_we = commit && regf_we_back;
assign prf_wr_phys = mem_wb.dest_phys_new;
assign prf_wr_data = regfilemux_out;

assign commit_we = commit && (mem_wb.dest_arch != 5'd0);
assign commit_arch = mem_wb.dest_arch;
assign commit_phys = mem_wb.dest_phys_new;
assign commit_old_phys = mem_wb.dest_phys_old;
```

#### 🔥 **decode.sv (~30 lines)**

**Reasons:**
1. Need to receive lookup results from rename_unit
2. Need to receive read values from PRF
3. Need to pass architectural register numbers to rename_unit
4. Need to add physical register fields to pipeline registers

**Key Modifications:**
```systemverilog
// New inputs
input logic [5:0] rs1_phys, rs2_phys;
input logic [5:0] dest_phys_new, dest_phys_old;
input logic [31:0] rs1_val, rs2_val;

// Pass to ID/EX
id_ex.rs1_phys = rs1_phys;
id_ex.rs2_phys = rs2_phys;
id_ex.dest_phys_new = dest_phys_new;
id_ex.dest_phys_old = dest_phys_old;

id_ex.rs1_v = rs1_val;  // From PRF
id_ex.rs2_v = rs2_val;

// Extract architectural indices (for rename_unit)
id_ex.rs1_arch = imem_rdata_id[19:15];
id_ex.rs2_arch = imem_rdata_id[24:20];
id_ex.dest_arch = imem_rdata_id[11:7];
```

---

## Why This Design?

### ✅ Advantages

1. **Eliminate False Dependencies**
   - WAR and WAW hazards completely eliminated
   - Only true data dependencies (RAW) remain

2. **Increase Parallelism**
   - Multiple instructions can write to different physical registers simultaneously
   - Prepare for future out-of-order execution

3. **Simpler Forwarding**
   - Based on physical register number comparison
   - No need to consider architectural register complexity

4. **Good Scalability**
   - 64 physical registers vs 32 architectural registers
   - Can support more in-flight instructions

### ⚠️ Trade-offs

1. **Increased Hardware Complexity**
   - Need RAT (32 x 6-bit = 192 bits)
   - Need Free List management logic
   - PRF is twice as large as regfile (64 vs 32)

2. **Increased Area and Power**
   - More registers
   - More logic gates

3. **More Difficult Debugging**
   - Architectural state vs Physical state
   - Need RVFI to report correctly

---

## Important Note: IPC Impact in In-Order Pipeline

### ⚠️ Critical Understanding

For a **pure in-order pipeline**, register renaming **does NOT** improve IPC!

**Why?**
- In-order issue → instructions always issued in order
- In-order execution → instructions always execute in order
- In-order commit → instructions always commit in order
- WAR/WAW hazards naturally handled by in-order constraint

**True Value of Register Renaming:**
1. ✅ **Preparation for Out-of-Order execution** (main reason)
2. ✅ **Learning modern processor architecture**
3. ✅ **Infrastructure for future optimization**
4. ✅ **Simplifies future forwarding logic**

**Expected IPC improvement:**
- Current in-order: ~0.69
- After implementing OoO: ~1.2-1.5+ (theoretical)

Register renaming is a **necessary foundation** for OoO execution, not an immediate performance optimization for in-order pipelines.

---

## Summary

**Core Value of Register Renaming:**
By mapping architectural registers to more physical registers, false dependencies are eliminated, paving the way for high-performance pipelines (especially out-of-order execution).

**Implementation Keys:**
1. **Decode Stage**: Query RAT + Read PRF + Allocate from Free List
2. **Execute Stage**: Use physical register numbers
3. **Writeback Stage**: Write PRF + Update RAT + Release old physical register

**Modification Focus:**
- cpu.sv most (instantiation and connection)
- writeback.sv second (commit logic)
- decode.sv third (lookup logic)
