# Simulation Results & Current Status

## 📊 Executive Summary

This document summarizes the verification and testing of the register renaming implementation, including:
- ✅ **Successes**: Problems solved and fixes implemented
- ⚠️ **Current Issues**: Why we cannot complete 60,000 instructions
- 🔧 **Next Steps**: Planned solutions

---

## ✅ Achievements & Problems Solved

### 1. RVFI Verification Infrastructure
**Status**: ✅ **WORKING**

- Implemented complete RVFI interface
- Integrated riscv-formal golden model (`rvfimon.v`)
- Added comprehensive signal integrity checks
- Created automated commit.log generation

**Reference**: See `hvl/RVFI_VERIFICATION_GUIDE.md`

---

### 2. x0 Register Handling  
**Problem**: RVFI error "mismatch in rd_wdata" when writing to x0

**Root Cause**: RVFI specification requires `rd_wdata == 0` when `rd_addr == 0`, but our implementation didn't enforce this.

**Solution** (Fixed in `writeback.sv`):
```systemverilog
// Before:
assign rvfi_rd_wdata = rd_v;

// After:
assign rvfi_rd_wdata = (rvfi_rd_addr == 5'd0) ? 32'd0 : rd_v;
```

**Result**: ✅ x0 writes now comply with RISC-V and RVFI specifications

---

### 3. Speculative Instruction Handling (FIX #6)
**Problem**: Register leaks when speculative instructions were blocked from committing

**Initial Approach (FIX #6)**: Block speculative commits
```systemverilog
if (mem_wb.is_speculative) begin
    commit <= 1'b0;  // Don't commit speculative instructions
end
```

**Issue**: Caused register leaks - physical registers allocated but never freed

**Evolution**: 
1. FIX #6 removed
2. Allowed speculative commits
3. Implemented flush recovery mechanism

**Result**: ⚠️ Partially solved, see "Current Issues" below

---

### 4. MEM/WB Pipeline Flush
**Problem**: Speculative instructions in MEM/WB stage were still committing after flush

**Root Cause**: Missing flush signal propagation to writeback stage

**Solution** (Fixed in `memstage.sv`):
```systemverilog
// Critical addition
assign mem_wb.valid = flush_pipeline ? 1'b0 : ex_mem.valid;
```

**Result**: ✅ Prevents speculative instructions from committing

---

### 5. RVFI Shadow Register Mismatches
**Problem**: "mismatch with shadow rs2" errors

**Diagnosis**:
- Shadow registers track architectural state in golden model
- Mismatches indicate forwarding or register file corruption
- Often caused by out-of-order commits or incorrect flush recovery

**Status**: ⚠️ **PARTIALLY RESOLVED** - Some cases fixed, others persist (see Current Issues)

---

## ⚠️ Current Critical Issues

### Issue #1: Free List Exhaustion
**Symptom**: Simulation stops after ~200-300 instructions due to free list count reaching zero

**Evidence**:
```
[FREE_LIST] alloc=1, free=0, count: 58→57
[FREE_LIST] alloc=1, free=0, count: 57→56
...
[FREE_LIST] alloc=1, free=0, count: 1→0
ERROR: Free list exhausted!
```

**Root Cause**: **Imbalance between allocations and deallocations**

#### Allocation Count > Deallocation Count Because:
1. **Eager allocation** at decode stage
2. **Delayed deallocation** at commit (writeback) stage  
3. **Pipeline flushes** discard speculative instructions without freeing registers
4. **Flush recovery mechanism incomplete**

#### Current Flush Recovery (FIFO-based):
```systemverilog
// On flush: return all pending allocations
if (flush_pipeline) begin
    for (int i = 0; i < PENDING_ALLOC_DEPTH; i++) begin
        if (pending_allocs[i].valid) begin
            flush_free_phys[flush_free_count] = pending_allocs[i].phys_reg;
            flush_free_count++;
        end
    end
end
```

**Observation**:
- Free list count increases after flushes (e.g., 50 → 58)
- But not enough to sustain execution
- Free list still exhausts within 300 instructions

---

### Issue #2: FIFO Push/Pop Ordering Violations
**Symptom**: Assertion failures on every commit

**Evidence**:
```
[FIFO] ASSERTION FAILED: arch mismatch - tail=x25 commit=x26
[FIFO] ASSERTION FAILED: phys mismatch - tail=61 commit=6  
[FIFO] ASSERTION FAILED: Pop from empty FIFO! commit x7 phys=x
```

**Root Cause**: **FIFO assumes in-order commit, but flushes break this assumption**

#### Why FIFO Fails:
```
Timeline:
1. Allocate: x25→p61 (order 54)
2. Allocate: x16→p62 (order 55)
3. Allocate: x29→p63 (order 56)
4. *** FLUSH happens ***
5. Commit arrives: x26 (different instruction!)
6. FIFO expects: x25 (tail of FIFO)
7. MISMATCH!
```

**Fundamental Problem**: 
- FIFO is FIFO (first-in-first-out)
- Flushes cause some instructions to be skipped
- Commits arrive out of original allocation order
- FIFO tail doesn't match committing instruction

---

### Issue #3: Persistent RVFI Shadow RS2 Errors
**Symptom**: "mismatch with shadow rs2" (error code 132)

**Possible Causes**:
1. Incorrect forwarding logic
2. PRF write enable issues  
3. Register allocation/deallocation bugs
4. Pending allocation tracking errors

**Status**: ⚠️ **UNDER INVESTIGATION**

Likely related to free list exhaustion and FIFO ordering issues.

---

## 🎯 Target: 60,000 Instructions

### Why We're Stuck

**Current Achievement**: ~200-300 instructions before free list exhaustion

**Remaining**: 59,700-59,800 instructions (99.5% incomplete)

**Blocker**: Free list exhaustion → No physical registers available → Cannot decode new instructions → Simulation deadlock

---

## 🔧 Planned Solutions

### Solution #1: Replace FIFO with Table-Based Tracking (HIGH PRIORITY)

**Current Problem**: FIFO cannot handle out-of-order commits

**Proposed Solution**: Associative pending allocation table

```systemverilog
// Instead of FIFO with head/tail pointers
typedef struct packed {
    logic       valid;
    logic [63:0] order;
    logic [4:0] arch_reg;
    logic [5:0] phys_reg;
    logic [5:0] old_phys;
    logic       is_spec;
} pending_alloc_entry_t;

pending_alloc_entry_t pending_table [PENDING_DEPTH];  // Use valid bits, not FIFO

// On allocation: find empty slot
for (int i = 0; i < PENDING_DEPTH; i++) begin
    if (!pending_table[i].valid) begin
        pending_table[i] <= new_entry;
        pending_table[i].valid <= 1'b1;
        break;
    end
end

// On commit: search for matching entry by arch_reg + phys_reg
for (int i = 0; i < PENDING_DEPTH; i++) begin
    if (pending_table[i].valid && 
        pending_table[i].arch_reg == commit_arch &&
        pending_table[i].phys_reg == commit_phys) begin
        pending_table[i].valid <= 1'b0;  // Remove entry
        break;
    end
end

// On flush: scan all valid entries, return spec ones
for (int i = 0; i < PENDING_DEPTH; i++) begin
    if (pending_table[i].valid && pending_table[i].is_spec) begin
        flush_free_phys[flush_count] = pending_table[i].phys_reg;
        pending_table[i].valid <= 1'b0;
        flush_count++;
    end
end
```

**Advantages**:
- ✅ No ordering assumption
- ✅ Handles out-of-order commits naturally
- ✅ Direct lookup by arch+phys match
- ✅ Same flush recovery logic

**Complexity**: Medium (1-2 days implementation)

---

### Solution #2: Increase Physical Register Count (MEDIUM PRIORITY)

**Current**: 64 physical registers

**Proposed**: 96 or 128 physical registers

**Rationale**:
- More registers → Less pressure on free list
- Buys time for flush recovery to work
- Industry standard: 128-256 physical registers for out-of-order cores

**Tradeoff**: 
- Larger PRF → More area
- Wider address buses (7-bit vs 6-bit)

**Implementation**: Low complexity (configuration change)

 ---

### Solution #3: Add Assertions and Invariant Checks (HIGH PRIORITY)

**Needed Checks**:
```systemverilog
// 1. Never allocate physical register 0
assert property (@(posedge clk) (alloc_valid && rd != 0) |-> (alloc_phys != 0));

// 2. Free list count never exceeds total physical registers
assert property (@(posedge clk) (count <= PHYS_REGS - 1));

// 3. Balance check: allocations = frees + in_use
property balance_check;
    @(posedge clk) disable iff (rst)
    (global_alloc_count == global_free_count + global_in_use_count);
endproperty

// 4. No double-free
assert property (@(posedge clk) (free_valid |-> !free_list_contains(free_phys)));
```

**Purpose**: Catch bugs early before catastrophicfailure

---

### Solution #4: Implement Reorder Buffer (ROB) (LONG-TERM)

**Current**: Instructions commit in decode order (with flush exceptions)

**Proposed**: True out-of-order completion with in-order commit via ROB

**Benefits**:
- ✅ Precise exception handling
- ✅ Clean separation of speculation and commitment
- ✅ More robust flush recovery
- ✅ Industry-standard approach

**Complexity**: High (1-2 weeks implementation)

**Reference**: Tomasulo's Algorithm, modern superscalar processors

---

## 📈 Simulation Statistics (Current)

### Successful Runs (Base 5-stage, main branch):
```
Instructions Committed: 90,108
Cycles:                 155,350  
IPC:                    0.58
RVFI Errors:            0
Coverage:               98.03% (100% of legal RV32I space)
```

### Register Renaming Branch (rename-unit):
```
Instructions Committed: ~200-300  
Cycles:                 ~500-1000
Free List Exhaustion:   YES (count → 0)
RVFI Errors:            Shadow RS2 mismatches
Primary Blocker:        FIFO ordering + free list exhaustion
```

---

## 🗺️ Roadmap to 60K Instructions

### Phase 1: Fix Flush Recovery (Week 1)
- [ ] Implement table-based pending allocation tracking
- [ ] Remove FIFO head/tail logic
- [ ] Add assertions for allocation/deallocation balance
- [ ] Test with simple programs (no branches)

### Phase 2: Stress Testing (Week 2)
- [ ] Run with branch-heavy code  
- [ ] Monitor free list count under stress
- [ ] Verify RVFI shadow register tracking
- [ ] Achieve 1,000+ instructions

### Phase 3: Full Random Test (Week 3)
- [ ] Run 60,000 constrained random instructions
- [ ] Validate 100% correctness vs golden model
- [ ] Generate coverage report
- [ ] Document final results

### Phase 4: Optimization (Optional)
- [ ] Increase physical registers if needed
- [ ] Consider ROB implementation
- [ ] Performance tuning (IPC improvement)

---

## 📊Debug Instrumentation

### Current Debug Messages
```systemverilog
// Free list tracking
$display("[FREE_LIST] alloc=%0d, free=%0d, count: %0d→%0d", ...);

// Rename unit tracking  
$display("[RENAME] x%0d: old=p%0d → new=p%0d", rd, old, new);

// Commit tracking
$display("[COMMIT] x%0d: phys=p%0d, free old=p%0d", arch, phys, old);

// FIFO tracking
$display("[FIFO PUSH] order=%0d x%0d→phys=%0d (old=%0d) spec=%b", ...);
$display("[FIFO POP] order=%0d x%0d phys=%0d", ...);

// Flush recovery
$display("[FLUSH RECOVERY] Returning phys=%0d (was for x%0d)", ...);
$display("[FLUSH RECOVERY] Total %0d registers returned", count);
```

### Recommended Additional Logs
```systemverilog
// Allocation/deallocation totals
$display("[BALANCE] Total: alloc=%0d free=%0d in_use=%0d", 
         global_alloc, global_free, global_alloc - global_free);

// Pending allocation table status
$display("[PENDING] Valid entries: %0d, Max depth: %0d", valid_count, max_depth);

// Critical events
$display("[CRITICAL] Free list count = %0d (threshold: 5)", count);
```

---

## 🐛 Known Bugs & Workarounds

### Bug#1: FIFO Assertion Failures
**Severity**: HIGH  
**Workaround**: Comment out assertions (not recommended for production)  
**Proper Fix**: Table-based tracking (Solution #1)

### Bug #2: Free List Exhaustion
**Severity**: CRITICAL  
**Workaround**: Reduce test size (defeats purpose)  
**Proper Fix**: Fix flush recovery + increase phys regs

### Bug #3: Shadow RS2 Mismatches
**Severity**: MEDIUM  
**Workaround**: None (blocks RVFI verification)  
**Proper Fix**: Debug after fixing #1 and #2

---

## 📁 Test Files & Logs

### Key Files
- `sim/commit.log` - Execution trace (Spike format)
- `run/random_tb_sim.log` - Simulation output
- `coverage_report/index.html` - Coverage report
- `vsim.wlf` - Waveform database

### Example Workflow
```bash
# Clean and recompile
make clean
make compile

# Run simulation (currently fails at ~300 instructions)
make run_random

# Check commit.log
tail -100 sim/commit.log

# Analyze free list behavior
grep "FREE_LIST" run/random_tb_sim.log | tail -50

# View waveforms
vsim -view vsim.wlf
```

---

## 🎓 Lessons Learned

1. **FIFO is wrong data structure** for pending allocation tracking when flushes cause reordering
2. **Eager allocation + delayed deallocation** creates register pressure
3. **Flush recovery is critical** and more complex than initially thought
4. **Assertions are essential** for catching imbalances early
5. **Shadow register tracking** in RVFI is powerful for finding forwarding bugs

---

## 📚 References

### Internal Documents
- `hdl/REGISTER_RENAMING_README.md` - Implementation details
- `hvl/RVFI_VERIFICATION_GUIDE.md` - RVFI system documentation  
- `sim/ARCHITECTURE_GUIDE.md` - Architecture overview

### External Resources
- [Tomasulo's Algorithm](https://en.wikipedia.org/wiki/Tomasulo_algorithm)
- [Register Renaming Survey](https://www.cl.cam.ac.uk/teaching/1617/ACS/notes/2-renaming.pdf)
- [RISC-V Formal Spec](https://github.com/SymbioticEDA/riscv-formal)

---

## 🤝 Contributors

Special thanks to debugging session participants who identified:
- x0 register RVFI compliance issue
- MEM/WB flush missing
- FIFO ordering fundamental limitation
- Free list exhaustion root cause

---

*Last Updated: November 2025*  
*Status: IN PROGRESS - Blocked on flush recovery*  
*Next Milestone: Table-based pending allocation*
