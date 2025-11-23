# RVFI Verification System - Complete Guide

## 📋 Table of Contents
1. [Overview](#overview)
2. [What is RVFI?](#what-is-rvfi)
3. [System Architecture](#system-architecture)
4. [Signal Mapping](#signal-mapping)
5. [Golden Model Comparison](#golden-model-comparison)
6. [Monitor Functions](#monitor-functions)
7. [Error Detection](#error-detection)
8. [Commit Log Generation](#commit-log-generation)
9. [Debugging Guide](#debugging-guide)

---

## 🎯 Overview

The RVFI (RISC-V Formal Interface) verification system provides **cycle-accurate, instruction-by-instruction validation** of your processor's correctness by comparing it against a **golden reference model**.

### Key Components
```
Your Processor → RVFI Signals → Monitor → Golden Model → Pass/Fail + commit.log
```

---

## 🔍 What is RVFI?

**RVFI = RISC-V Formal Interface**

RVFI is a **standardized interface** that allows formal verification tools to monitor and verify RISC-V processor implementations. It was developed as part of the [riscv-formal](https://github.com/SymbioticEDA/riscv-formal) project.

### Why RVFI?
- ✅ **Specification-based**: Compares against ISA spec, not another processor
- ✅ **Instruction-level**: Validates every committed instruction
- ✅ **Comprehensive**: Checks registers, memory, PC, and all state changes
- ✅ **Formal**: Mathematically proven correct reference model

### NOT Spike!
⚠️ **Important**: We do NOT compare against Spike. We compare against **riscv-formal's golden model** (`rvfimon.v`), which is a Verilog implementation of the RISC-V ISA specification.

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Your Processor (cpu.sv)                       │
│  ┌────────┬────────┬─────────┬─────────┬──────────────────┐    │
│  │ Fetch  │ Decode │ Execute │ Memory  │ Writeback        │    │
│  └────────┴────────┴─────────┴─────────┴────────┬─────────┘    │
│                                                   │              │
│                                    rvfi_valid,    │              │
│                                    rvfi_order,    │              │
│                                    rvfi_rd_wdata, │              │
│                                    etc...         │              │
└───────────────────────────────────────────────────┼──────────────┘
                                                    │
                                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│         Signal Mapping (rvfi_reference.svh)                      │
│  mon_itf.valid     = dut.writeback.rvfi_valid                   │
│  mon_itf.rd_wdata  = dut.writeback.rvfi_rd_wdata                │
│  ...                                                             │
└───────────────────────────────────────┬─────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Monitor (monitor.sv)                           │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ 1. Signal Integrity Check                              │    │
│  │    - Detect 'x (unknown) values                        │    │
│  │    - Verify signal validity                            │    │
│  └────────────────────────────────────────────────────────┘    │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ 2. Golden Model Comparison (rvfimon.v)                 │    │
│  │    ┌──────────────────────────────────────────────┐   │    │
│  │    │ ISA Spec Implementation                      │   │    │
│  │    │ - Decodes your instruction                   │   │    │
│  │    │ - Computes expected results                  │   │    │
│  │    │ - Returns spec_rd_wdata, spec_pc_wdata, etc.│   │    │
│  │    └──────────────────────────────────────────────┘   │    │
│  │    Compare: rvfi_rd_wdata  vs  spec_rd_wdata           │    │
│  │    Compare: rvfi_pc_wdata  vs  spec_pc_wdata           │    │
│  │    Compare: rvfi_rs1_rdata vs  shadow_rs1_rdata        │    │
│  │    ...                                                  │    │
│  │    ──────────────────────────────────────────────      │    │
│  │    Output: errcode (0=pass, ≠0=error)                  │    │
│  └────────────────────────────────────────────────────────┘    │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ 3. Commit Log Generation                               │    │
│  │    - Record every committed instruction                │    │
│  │    - Write to commit.log in Spike format               │    │
│  └────────────────────────────────────────────────────────┘    │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ 4. Performance Monitoring                              │    │
│  │    - Track IPC (Instructions Per Cycle)                │    │
│  │    - Count instructions and cycles                     │    │
│  └────────────────────────────────────────────────────────┘    │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                 ┌────────┴─────────┐
                 │                  │
            errcode == 0       errcode != 0
                 │                  │
                 ▼                  ▼
         ┌──────────────┐   ┌────────────────────┐
         │ Continue     │   │ Display Error      │
         │ Write commit │   │ Stop Simulation    │
         └──────────────┘   └────────────────────┘
```

---

## 📡 Signal Mapping

### File: `rvfi_reference.svh`

This file maps your processor's RVFI signals to the monitor interface.

```systemverilog
always_comb begin
    // Core control signals
    mon_itf.valid     = dut.writeback.rvfi_valid;      // Instruction commit valid
    mon_itf.order     = dut.writeback.rvfi_order;      // Instruction serial number
    mon_itf.inst      = dut.writeback.rvfi_inst;       // Instruction encoding
    
    // Source register signals
    mon_itf.rs1_addr  = dut.writeback.rvfi_rs1_addr;   // rs1 register address
    mon_itf.rs2_addr  = dut.writeback.rvfi_rs2_addr;   // rs2 register address
    mon_itf.rs1_rdata = dut.writeback.rvfi_rs1_rdata;  // rs1 register data
    mon_itf.rs2_rdata = dut.writeback.rvfi_rs2_rdata;  // rs2 register data
    
    // Destination register signals
    mon_itf.rd_addr   = dut.writeback.rvfi_rd_addr;    // rd register address
    mon_itf.rd_wdata  = dut.writeback.rvfi_rd_wdata;   // rd register write data
    
    // Program counter signals
    mon_itf.pc_rdata  = dut.writeback.rvfi_pc_rdata;   // Current PC
    mon_itf.pc_wdata  = dut.writeback.rvfi_pc_wdata;   // Next PC
    
    // Memory access signals
    mon_itf.mem_addr  = dut.writeback.rvfi_dmem_addr;  // Memory address
    mon_itf.mem_rmask = dut.writeback.rvfi_dmem_rmask; // Read byte mask
    mon_itf.mem_wmask = dut.writeback.rvfi_dmem_wmask; // Write byte mask
    mon_itf.mem_rdata = dut.writeback.rvfi_dmem_rdata; // Memory read data
    mon_itf.mem_wdata = dut.writeback.rvfi_dmem_wdata; // Memory write data
end
```

### Signal Requirements

#### ⚠️ Critical Rule: x0 Register
```systemverilog
// When writing to x0 (zero register):
if (rvfi_rd_addr == 5'd0) begin
    rvfi_rd_wdata MUST be 32'd0
end
```

**Why?** x0 is hardwired to zero in RISC-V. The golden model enforces this invariant.

**Implementation** (in `writeback.sv`):
```systemverilog
assign rvfi_rd_wdata = (rvfi_rd_addr == 5'd0) ? 32'd0 : rd_v;
```

---

## 🎯 Golden Model Comparison

### How It Works

The golden model (`riscv_formal_monitor_rv32imc`) is instantiated in `monitor.sv`:

```systemverilog
riscv_formal_monitor_rv32imc monitor(
    .clock              (itf.clk),
    .reset              (itf.rst),
    
    // Input: Your processor's RVFI signals
    .rvfi_valid         (itf.valid),
    .rvfi_order         (itf.order),
    .rvfi_insn          (itf.inst),
    .rvfi_rs1_addr      (itf.rs1_addr),
    .rvfi_rs2_addr      (itf.rs2_addr),
    .rvfi_rs1_rdata     (itf.rs1_addr ? itf.rs1_rdata : 32'd0),
    .rvfi_rs2_rdata     (itf.rs2_addr ? itf.rs2_rdata : 32'd0),
    .rvfi_rd_addr       (itf.rd_addr),
    .rvfi_rd_wdata      (itf.rd_addr ? itf.rd_wdata : 5'd0),
    .rvfi_pc_rdata      (itf.pc_rdata),
    .rvfi_pc_wdata      (itf.pc_wdata),
    .rvfi_mem_addr      ({itf.mem_addr[31:2], 2'b0}),
    .rvfi_mem_rmask     (itf.mem_rmask),
    .rvfi_mem_wmask     (itf.mem_wmask),
    .rvfi_mem_rdata     (itf.mem_rdata),
    .rvfi_mem_wdata     (itf.mem_wdata),
    .rvfi_mem_extamo    (1'b0),
    
    // Output: Error code
    .errcode            (errcode)
);
```

### What Gets Compared?

For **every committed instruction**, the golden model checks:

| Check Type | Your Signal | Golden Model Signal | Error Code |
|:-----------|:------------|:-------------------|:-----------|
| **Instruction Decode** | rvfi_insn | spec_valid | - |
| **Trap Status** | rvfi_trap | spec_trap | 101 |
| **RS1 Address** | rvfi_rs1_addr | spec_rs1_addr | 102 |
| **RS2 Address** | rvfi_rs2_addr | spec_rs2_addr | 103 |
| **RD Address** | rvfi_rd_addr | spec_rd_addr | 104 |
| **RD Write Data** | rvfi_rd_wdata | spec_rd_wdata | 105 |
| **PC Next Value** | rvfi_pc_wdata | spec_pc_wdata | 106 |
| **Memory Address** | rvfi_mem_addr | spec_mem_addr | 107 |
| **Memory Write Mask** | rvfi_mem_wmask | spec_mem_wmask | 108 |
| **Memory Read Mask** | rvfi_mem_rmask | spec_mem_rmask | 110-113 |
| **Memory Write Data** | rvfi_mem_wdata | spec_mem_wdata | 120-123 |
| **Shadow PC** | rvfi_pc_rdata | shadow_pc | 130 |
| **Shadow RS1** | rvfi_rs1_rdata | shadow_xregs[rs1] | 131 |
| **Shadow RS2** | rvfi_rs2_rdata | shadow_xregs[rs2] | 132 |

### Golden Model Process

For each instruction:

1. **Decode**: Parse `rvfi_insn` to determine instruction type
2. **Compute**: Calculate expected results based on:
   - Instruction opcode
   - Source operands (rs1_rdata, rs2_rdata)
   - Immediate values
   - Current PC
3. **Compare**: Check if your results match expected results
4. **Track**: Update shadow registers for next instruction

### Shadow Register Tracking

The golden model maintains **shadow registers** to track architectural state:

```verilog
// Shadow registers (maintained by golden model)
reg [31:0] shadow_xregs [0:31];      // GPR shadow
reg [31:0] shadow_xregs_valid;       // Valid bits
reg [31:0] shadow_pc;                // PC shadow

// Update shadow on every commit
always @(posedge clock) begin
    if (ro0_rvfi_valid) begin
        shadow_xregs_valid[ro0_rvfi_rd_addr] <= 1;
        shadow_xregs[ro0_rvfi_rd_addr] <= ro0_rvfi_rd_wdata;
        shadow_pc <= ro0_rvfi_pc_wdata;
    end
end

// Check RS1 against shadow
if (shadow_rs1_valid && shadow_rs1_rdata != ro0_rvfi_rs1_rdata) begin
    error(131, "mismatch with shadow rs1");
end
```

**Purpose**: Detect forwarding errors and register file corruption.

---

## 🔧 Monitor Functions

The monitor (`monitor.sv`) performs **5 critical functions**:

### 1️⃣ Signal Integrity Check

**Purpose**: Detect 'x (unknown) values in RVFI signals

```systemverilog
always @(posedge itf.clk iff (!itf.rst && itf.valid)) begin
    if ($isunknown(itf.order)) begin
        $error("RVFI Interface Error: order contains 'x");
        itf.error <= 1'b1;
    end
    if ($isunknown(itf.rd_addr)) begin
        $error("RVFI Interface Error: rd_addr contains 'x");
        itf.error <= 1'b1;
    end
    // ... checks for all signals
end
```

**When This Fails**:
- ❌ Uninitialized registers
- ❌ Timing violations
- ❌ Missing signal assignments

---

### 2️⃣ Halt Detection

**Purpose**: Detect program termination

```systemverilog
always @(posedge itf.clk) begin
    if ((!itf.rst && itf.valid) && 
        ((itf.pc_rdata == itf.pc_wdata)      // PC unchanged (infinite loop)
        || (itf.inst == 32'h00000063)        // Special halt instruction
        || (itf.inst == 32'h0000006f)        // JAL to self
        || (itf.inst == 32'hF0002013))) begin
        itf.halt <= 1'b1;
    end
end
```

---

### 3️⃣ Golden Model Verification

**Purpose**: Compare against ISA specification

```systemverilog
always @(posedge itf.clk) begin
    if (errcode != 0) begin
        $error("RVFI Monitor Error");
        itf.error <= 1'b1;
    end
end
```

**Error Codes**: See [Error Detection](#error-detection) section.

---

### 4️⃣ Performance Monitoring

**Purpose**: Track IPC (Instructions Per Cycle)

```systemverilog
longint inst_count = 0;
longint cycle_count = 0;
real ipc = 0;

always @(posedge itf.clk) begin
    cycle_count += 1;
    if (!itf.rst && itf.valid) begin
        inst_count += 1;
    end
end

// Calculate IPC
ipc = real'(inst_count) / cycle_count;
```

---

### 5️⃣ Commit Log Generation

**Purpose**: Record execution trace in Spike format

```systemverilog
int fd;
initial fd = $fopen("./commit.log", "w");

always @(posedge itf.clk) begin
    if(itf.valid) begin
        // Format: core 0: 3 0x<PC> (0x<inst>) x<rd> 0x<rd_data> [mem ...]
        $fwrite(fd, "core   0: 3 0x%h (0x%h)", itf.pc_rdata, itf.inst);
        
        if (itf.rd_addr != 0) begin
            $fwrite(fd, " x%0d 0x%h", itf.rd_addr, itf.rd_wdata);
        end
        
        if (itf.mem_rmask != 0 || itf.mem_wmask != 0) begin
            $fwrite(fd, " mem 0x%h", mem_addr);
        end
        
        $fwrite(fd, "\n");
    end
end
```

**Output Example**:
```
core   0: 3 0x60000000 (0x00028117) x2  0x60028000
core   0: 3 0x60000004 (0x00112023) mem 0x60028000 0x00000000
core   0: 3 0x60000008 (0x00011083) x1  0x00000000 mem 0x60028000
```

---

## 🚨 Error Detection

### Common Error Codes

| Code | Error Message | Meaning | Common Causes |
|:-----|:-------------|:--------|:--------------|
| **101** | mismatch in trap | Trap flag incorrect | Exception handling |
| **102** | mismatch in rs1_addr | Wrong rs1 address | Decode error |
| **103** | mismatch in rs2_addr | Wrong rs2 address | Decode error |
| **104** | mismatch in rd_addr | Wrong rd address | Decode error |
| **105** | mismatch in rd_wdata | **Wrong ALU/result** | **ALU bug, forwarding error** |
| **106** | mismatch in pc_wdata | Wrong next PC | Branch/jump error |
| **107** | mismatch in mem_addr | Wrong memory address | Address calculation |
| **108** | mismatch in mem_wmask | Wrong write mask | Store instruction bug |
| **110-113** | mismatch in mem_rmask | Wrong read mask | Load instruction bug |
| **120-123** | mismatch in mem_wdata | Wrong store data | Store data error |
| **130** | mismatch with shadow pc | PC tracking error | Control flow bug |
| **131** | mismatch with shadow rs1 | **RS1 corruption** | **Forwarding, register file** |
| **132** | mismatch with shadow rs2 | **RS2 corruption** | **Forwarding, register file** |
| **133** | expected intr after trap | Missing interrupt | Trap handling |
| **60000+** | ROB error | Order/valid error | RVFI ordering issue |
| **61000+** | ROB order error | Order mismatch | Instruction skipped/duplicated |

### Most Common Errors (Your Debugging Focus)

#### 1. Error 105: mismatch in rd_wdata
**Meaning**: Your processor computed the wrong result

**Debug Steps**:
```
1. Check which instruction failed (look at PC and inst in error message)
2. Manually calculate expected result
3. Check ALU logic for that operation
4. Verify forwarding paths
5. Check if rd_addr == 0 (must force rd_wdata to 0!)
```

#### 2. Error 131/132: mismatch with shadow rs1/rs2
**Meaning**: Source register has wrong value

**Debug Steps**:
```
1. Check previous instructions that wrote to this register
2. Verify register file write enable logic
3. Check forwarding logic (MEM→EX, WB→EX)
4. Verify RAT (Register Alias Table) if using register renaming
5. Check if register was properly committed
```

#### 3. Error 106: mismatch in pc_wdata
**Meaning**: Next PC is wrong

**Debug Steps**:
```
1. Check branch condition evaluation
2. Verify branch target calculation (PC + imm)
3. Check JAL/JALR target calculation
4. Verify PC+4 for normal instructions
```

---

## 📝 Commit Log Generation

### Format

The monitor generates `commit.log` in **Spike-compatible format**:

```
core   0: 3 0x<PC> (0x<instruction>) [x<rd> 0x<rd_data>] [mem 0x<addr> [0x<data>]]
```

### Examples

#### 1. ALU Instruction
```
core   0: 3 0x60000000 (0x00550533) x10 0x0000002a
```
- PC: `0x60000000`
- Instruction: `0x00550533` (ADD x10, x10, x5)
- Result: x10 = `0x0000002a`

#### 2. Load Instruction
```
core   0: 3 0x60000004 (0x00012083) x1  0xcafebabe mem 0x60001000
```
- PC: `0x60000004`
- Instruction: `0x00012083` (LW x1, 0(x2))
- Result: x1 = `0xcafebabe`
- Memory: Read from `0x60001000`

#### 3. Store Instruction
```
core   0: 3 0x60000008 (0x00112023) mem 0x60001004 0xdeadbeef
```
- PC: `0x60000008`
- Instruction: `0x00112023` (SW x1, 0(x2))
- Memory: Write `0xdeadbeef` to `0x60001004`

#### 4. Branch Instruction (not taken)
```
core   0: 3 0x6000000c (0x00208063)
```
- No register write
- No memory access
- Next instruction should be at PC+4

#### 5. Branch Instruction (taken)
```
core   0: 3 0x60000010 (0xfe0098e3)
core   0: 3 0x60000000 (0x00028117) x2  0x60028000
```
- First line: Branch instruction
- Second line: PC jumped to `0x60000000` (not PC+4!)

---

## 🐛 Debugging Guide

### When RVFI Fails

#### Step 1: Read the Error Message
```
-------- RVFI Monitor error 105 in channel 0: monitor at time 1000 --------
Error message: mismatch in rd_wdata
rvfi_valid = 1
rvfi_order = 32
rvfi_insn = 00a50533
rvfi_rd_addr = a
rvfi_rd_wdata = 00000014
spec_rd_wdata = 0000001e
```

**Interpretation**:
- Error 105: Wrong result
- Instruction #32 failed
- Instruction: `0x00a50533` = ADD x10, x10, x10
- Your result: `0x00000014` (20 in decimal)
- Expected: `0x0000001e` (30 in decimal)

#### Step 2: Find in commit.log
```bash
# Find the failing instruction
grep "0x00a50533" commit.log

# Or find by order number
sed -n '32p' commit.log
```

#### Step 3: Check Waveform
```tcl
# In QuestaSim
add wave -position end sim:/top_tb/dut/writeback/rvfi_*
# Look at time when rvfi_order == 32
```

#### Step 4: Verify Calculation
```
ADD x10, x10, x10
If x10 = 10 (0xA), result should be 20 (0x14) ✓ Your value
If spec expects 30 (0x1e), then x10 should have been 15

→ Check: Why is x10 = 10 instead of 15?
→ Look at previous instruction that wrote x10
```

### Common Issues and Fixes

#### Issue 1: "mismatch with shadow rs2" on every instruction
**Cause**: Register file not updating correctly
**Fix**: Check register file write enable logic

#### Issue 2: Error 60000+
**Cause**: `rvfi_order` not incrementing correctly
**Fix**: Ensure order increments by 1 for each committed instruction

#### Issue 3: Error 130 (shadow pc mismatch)
**Cause**: PC not updating to `rvfi_pc_wdata` from previous instruction
**Fix**: Check PC update logic

#### Issue 4: All rd_wdata show as 'x
**Cause**: Combinational loop or uninitialized signal
**Fix**: Check for proper register assignments in writeback stage

---

## 📊 Verification Flow Summary

```
Every Clock Cycle:
├─ If rvfi_valid == 1:
│  ├─ 1. Check for 'x values → Error if found
│  ├─ 2. Send to Golden Model
│  │  ├─ Decode instruction
│  │  ├─ Compute expected results
│  │  ├─ Compare with your results
│  │  └─ Return errcode
│  ├─ 3. If errcode != 0:
│  │  ├─ Display error message
│  │  └─ Stop simulation
│  ├─ 4. If errcode == 0:
│  │  ├─ Write to commit.log
│  │  ├─ Update shadow registers
│  │  └─ Continue
│  └─ 5. Update IPC counters
└─ Continue to next cycle
```

---

## ✅ Best Practices

### 1. Always Initialize RVFI Signals
```systemverilog
// Bad
logic [31:0] rvfi_rd_wdata;

// Good
logic [31:0] rvfi_rd_wdata = 32'd0;
```

### 2. Force x0 to Zero
```systemverilog
assign rvfi_rd_wdata = (rvfi_rd_addr == 5'd0) ? 32'd0 : actual_data;
```

### 3. Use Proper Order Numbering
```systemverilog
// Increment order for EVERY committed instruction
always_ff @(posedge clk) begin
    if (rst)
        order <= 64'd0;
    else if (commit_valid)
        order <= order + 64'd1;
end
```

### 4. Align Memory Addresses
```systemverilog
// Golden model expects 4-byte aligned addresses
assign rvfi_mem_addr = {dmem_addr[31:2], 2'b0};
```

---

## 📚 References

- [RVFI Specification](https://github.com/SymbioticEDA/riscv-formal/blob/master/docs/rvfi.md)
- [riscv-formal GitHub](https://github.com/SymbioticEDA/riscv-formal)
- [RISC-V ISA Manual](https://riscv.org/technical/specifications/)

---

## 🎓 Summary

**RVFI provides**:
- ✅ Instruction-by-instruction verification
- ✅ Comprehensive state checking
- ✅ Automated error detection
- ✅ Execution trace logging

**Your job**:
- ✅ Output correct RVFI signals from writeback stage
- ✅ Ensure signals reflect architectural state
- ✅ Follow RISC-V ISA specification exactly

**Monitor's job**:
- ✅ Check signal integrity
- ✅ Compare against golden model
- ✅ Generate commit log
- ✅ Report errors immediately

**When it works**: Silent operation, commit.log grows, simulation completes  
**When it fails**: Loud error message, simulation stops at first mismatch

---

*Last Updated: November 2025*
