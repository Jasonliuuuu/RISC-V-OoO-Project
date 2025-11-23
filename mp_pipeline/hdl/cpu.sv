module cpu
    import rv32i_types::*;
    import forward_amux::*;
    import forward_bmux::*;
    import regfilemux::*;
(
    input   logic           clk,
    input   logic           rst,

    // IMEM
    output  logic   [31:0]  imem_addr,
    output  logic   [3:0]   imem_rmask,
    input   logic   [31:0]  imem_rdata,
    input   logic           imem_resp,

    // DMEM
    output  logic   [31:0]  dmem_addr,
    output  logic   [3:0]   dmem_rmask,
    output  logic   [3:0]   dmem_wmask,
    input   logic   [31:0]  dmem_rdata,
    output  logic   [31:0]  dmem_wdata,
    input   logic           dmem_resp
);

    // ============================================================
    // Pipeline registers
    // ============================================================
    if_id_stage_reg_t  if_id_reg_before, if_id_reg;
    id_ex_stage_reg_t  id_ex_reg_before, id_ex_reg;
    ex_mem_stage_reg_t ex_mem_reg_before, ex_mem_reg;
    mem_wb_stage_reg_t mem_wb_reg_before, mem_wb_reg;

    logic stall_signal, freeze_stall, flush_pipeline;

    logic [31:0] imem_rdata_id;
    logic        imem_resp_id;

    // Forwarding
    forward_a_sel_t forward_a_sel;
    forward_b_sel_t forward_b_sel;

    logic [31:0] regfilemux_out;
    logic [4:0]  rd_s_back;
    logic        regf_we_back;

    logic br_en_out;
    logic [31:0] branch_pc;

    // Forwarding signals from memory stage
    logic        mem_wb_br_en_forward;
    logic [31:0] mem_wb_alu_out_forward;
    logic [31:0] mem_wb_u_imm_forward;


    // ============================================================
    // Rename + PRF wires
    // ============================================================
    logic [5:0] rs1_phys_decode;
    logic [5:0] rs2_phys_decode;
    logic [5:0] dest_phys_new_decode;
    logic [5:0] dest_phys_old_decode;

    logic [31:0] rs1_val_prf;
    logic [31:0] rs2_val_prf;

    logic       commit_we;
    logic [4:0] commit_arch;
    logic [5:0] commit_phys;
    logic [5:0] commit_old_phys;

    // Free list signals
    logic       alloc_valid;
    logic [5:0] alloc_phys;
    logic       free_en;
    logic [5:0] free_phys;
    
    // ============================================================
    // Pending Allocation Tracking (Option C)
    // ============================================================
    localparam PENDING_ALLOC_DEPTH = 16;  // Max in-flight allocations
    
    typedef struct packed {
        logic        valid;
        logic [63:0] order;      // Instruction order (for debug/matching)
        logic [4:0]  arch_reg;   // Architectural register
        logic [5:0]  phys_reg;   // Allocated physical register
        logic [5:0]  old_phys;   // Previous mapping
        logic        is_spec;    // Is speculative
    } pending_alloc_entry_t;
    
    pending_alloc_entry_t pending_allocs [PENDING_ALLOC_DEPTH-1:0];
    logic [3:0] pending_head;   // Next slot to write (allocate)
    logic [3:0] pending_tail;   // Next slot to remove (commit)
    logic [4:0] pending_count;  // Number of pending allocations
    
    // Flush recovery signals
    logic [4:0] flush_free_count;     // Number of registers to return (0-16)
    logic [5:0] flush_free_phys [PENDING_ALLOC_DEPTH-1:0]; // Phys regs to return
    
    // Debug counters for allocation/free balance verification
    int unsigned global_alloc_count = 0;
    int unsigned global_free_count = 0;
    int unsigned global_flush_free_count = 0;

    // ============================================================
    // Free list
    // ============================================================
    free_list free_list_i(
        .clk(clk),
        .rst(rst),
        .alloc_en(1'b1),  // Always trying to allocate
        .alloc_phys(alloc_phys),
        .alloc_valid(alloc_valid),
        .free_en(free_en),
        .free_phys(free_phys),
        .flush_free_count(flush_free_count),
        .flush_free_phys(flush_free_phys)
    );

    // ============================================================
    // PRF
    // ============================================================
    prf prf_i(
        .clk(clk),
        .rst(rst),
        .rs1_phys(rs1_phys_decode),
        .rs2_phys(rs2_phys_decode),
        .rs1_val(rs1_val_prf),
        .rs2_val(rs2_val_prf),
        .we      (commit_we),
        .rd_phys (commit_phys),
        .rd_val  (regfilemux_out)
    );

    // ============================================================
    // Rename Unit (Option A)
    // ============================================================
    rename_unit RU (
        .clk(clk),
        .rst(rst),

        .rs1_arch (imem_rdata_id[19:15]),
        .rs2_arch (imem_rdata_id[24:20]),
        .rd_arch  (imem_rdata_id[11:7]),

        .alloc_valid (alloc_valid),
        .alloc_phys  (alloc_phys),

        .commit_we       (commit_we),
        .commit_arch     (commit_arch),
        .commit_phys     (commit_phys),
        .commit_old_phys (commit_old_phys),

        .rs1_phys (rs1_phys_decode),
        .rs2_phys (rs2_phys_decode),
        .new_phys (dest_phys_new_decode),
        .old_phys (dest_phys_old_decode),
        .rename_we(),

        .free_en  (free_en),
        .free_phys(free_phys)
    );

    // ============================================================
    // Fetch
    // ============================================================
    fetch fetch_i(
        .clk(clk),
        .rst(rst),
        .br_en(br_en_out),
        .branch_pc(branch_pc),
        .imem_rdata(imem_rdata),
        .imem_resp(imem_resp),
        .stall_signal(stall_signal),
        .freeze_stall(freeze_stall),
        .flush_pipeline(flush_pipeline),
        .imem_addr(imem_addr),
        .imem_rmask(imem_rmask),
        .if_id_reg_before(if_id_reg_before),
        .imem_rdata_id(imem_rdata_id),
        .imem_resp_id(imem_resp_id)
    );

    // ============================================================
    // Decode
    // ============================================================
    decode decode_i(
        .clk(clk),
        .rst(rst),
        .imem_rdata_id(imem_rdata_id),
        .imem_resp_id(imem_resp_id),
        .stall_signal(stall_signal),
        .freeze_stall(freeze_stall),
        .flush_pipeline(flush_pipeline),

        .rs1_phys(rs1_phys_decode),
        .rs2_phys(rs2_phys_decode),
        .dest_phys_new(dest_phys_new_decode),
        .dest_phys_old(dest_phys_old_decode),
        .rs1_val(rs1_val_prf),
        .rs2_val(rs2_val_prf),

        .if_id(if_id_reg),
        .id_ex(id_ex_reg_before)
    );

    // ============================================================
    // STEP 1-2: Pending Allocation FIFO with Flush Recovery
    // ============================================================
    // Push: when decode allocates (alloc_valid && rd!=0)
    // Pop: when instruction commits
    // FLUSH: Clear all speculative entries, return phys to free_list
    
    // Global order counter for tracking
    logic [63:0] global_order;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            // Clear FIFO
            for (int i = 0; i < PENDING_ALLOC_DEPTH; i++) begin
                pending_allocs[i].valid <= 1'b0;
            end
            pending_head <= 4'd0;
            pending_tail <= 4'd0;
            pending_count <= 5'd0;
            global_order <= 64'd0;
        end
        else if (flush_pipeline) begin
            // ====================
            // STEP 2: FLUSH RECOVERY
            // ====================
            // Clear all speculative pending entries and return their phys regs
            $display("[FIFO FLUSH] START: %0d pending entries", pending_count);
            
            // Scan FIFO for speculative entries
            for (int i = 0; i < PENDING_ALLOC_DEPTH; i++) begin
                if (pending_allocs[i].valid && pending_allocs[i].is_spec) begin
                    $display("[FIFO FLUSH] Clearing spec entry: order=%0d x%0d→phys=%0d",
                             pending_allocs[i].order, pending_allocs[i].arch_reg,
                             pending_allocs[i].phys_reg);
                    pending_allocs[i].valid <= 1'b0;
                end
            end
            
            // Reset FIFO pointers (simple approach: clear everything)
            // This is safe because flush should kill all in-flight instructions
            for (int i = 0; i < PENDING_ALLOC_DEPTH; i++) begin
                pending_allocs[i].valid <= 1'b0;
            end
            pending_head <= 4'd0;
            pending_tail <= 4'd0;
            pending_count <= 5'd0;
            
            $display("[FIFO FLUSH] END: FIFO reset, count→0");
        end
        else begin
            // ====================
            // PUSH: Track allocation
            // ====================
            if (imem_rdata_id[11:7] != 5'd0 && alloc_valid && !stall_signal && !freeze_stall) begin
                // ASSERTION: Don't allocate phys 0
                if (dest_phys_new_decode == 6'd0) begin
                    $error("[FIFO] ASSERTION FAILED: Allocated phys=0 for x%0d!", imem_rdata_id[11:7]);
                end
                
                // ASSERTION: FIFO not full
                if (pending_count >= PENDING_ALLOC_DEPTH) begin
                    $error("[FIFO] ASSERTION FAILED: FIFO full (count=%0d)", pending_count);
                end
                
                // Push to FIFO
                pending_allocs[pending_head].valid    <= 1'b1;
                pending_allocs[pending_head].order    <= global_order;
                pending_allocs[pending_head].arch_reg <= imem_rdata_id[11:7];
                pending_allocs[pending_head].phys_reg <= dest_phys_new_decode;
                pending_allocs[pending_head].old_phys <= dest_phys_old_decode;
                pending_allocs[pending_head].is_spec  <= if_id_reg.is_speculative;
                
                pending_head <= pending_head + 1;
                pending_count <= pending_count + 1;
                global_order <= global_order + 1;
                
                $display("[FIFO PUSH] order=%0d x%0d→phys=%0d (old=%0d) spec=%b, count: %0d→%0d", 
                         global_order, imem_rdata_id[11:7], dest_phys_new_decode, dest_phys_old_decode,
                         if_id_reg.is_speculative, pending_count, pending_count + 1);
            end
            
            // ====================
            // POP: Remove on commit
            // ====================
            if (commit_we && commit_arch != 5'd0) begin
                // ASSERTION: FIFO not empty
                if (!pending_allocs[pending_tail].valid || pending_count == 0) begin
                    $error("[FIFO] ASSERTION FAILED: Pop from empty FIFO! commit x%0d phys=%0d",
                           commit_arch, commit_phys);
                end
                else begin
                    // ASSERTION: Commit must match FIFO tail
                    if (pending_allocs[pending_tail].arch_reg != commit_arch) begin
                        $error("[FIFO] ASSERTION FAILED: arch mismatch - tail=x%0d commit=x%0d",
                               pending_allocs[pending_tail].arch_reg, commit_arch);
                    end
                    if (pending_allocs[pending_tail].phys_reg != commit_phys) begin
                        $error("[FIFO] ASSERTION FAILED: phys mismatch - tail=%0d commit=%0d",
                               pending_allocs[pending_tail].phys_reg, commit_phys);
                    end
                    
                    $display("[FIFO POP] order=%0d x%0d phys=%0d, count: %0d→%0d",
                             pending_allocs[pending_tail].order, commit_arch, commit_phys,
                             pending_count, pending_count - 1);
                    
                    pending_allocs[pending_tail].valid <= 1'b0;
                    pending_tail <= pending_tail + 1;
                    pending_count <= pending_count - 1;
                end
            end
        end
    end

    // ============================================================
    // Execute
    // ============================================================
    execute execute_i(
        .id_ex(id_ex_reg),
        .ex_mem(ex_mem_reg_before),
        .regfilemux_out_forward(regfilemux_out),
        .ex_mem_br_en_forward(mem_wb_br_en_forward),
        .ex_mem_alu_out_forward(mem_wb_alu_out_forward),
        .ex_mem_u_imm_forward(mem_wb_u_imm_forward),
        .forward_a_sel(forward_a_sel),
        .forward_b_sel(forward_b_sel),
        .flush_pipeline(flush_pipeline)
    );

    // ============================================================
    // Memory
    // ============================================================
    memory memory_i(
        .ex_mem(ex_mem_reg),
        .mem_wb(mem_wb_reg_before),
        .mem_wb_now(mem_wb_reg),
        .dmem_addr(dmem_addr),
        .dmem_rmask(dmem_rmask),
        .dmem_wmask(dmem_wmask),
        .dmem_wdata(dmem_wdata),
        .mem_wb_br_en(mem_wb_br_en_forward),
        .mem_wb_alu_out(mem_wb_alu_out_forward),
        .mem_wb_u_imm(mem_wb_u_imm_forward),
        .br_en_out(br_en_out),
        .branch_new_address(branch_pc),
        .flush_pipeline(flush_pipeline),

        .freeze_stall(freeze_stall)
    );

    // ============================================================
    // Writeback + RVFI
    // ============================================================
    writeback writeback(
        .clk(clk),
        .rst(rst),
        .mem_wb(mem_wb_reg),
        .dmem_rdata(dmem_rdata),
        .dmem_resp(dmem_resp),
        .freeze_stall(freeze_stall),

        .regfilemux_out(regfilemux_out),
        .rd_s_back(rd_s_back),
        .regf_we_back(regf_we_back),

        .rvfi_valid(rvfi_valid),
        .rvfi_order(rvfi_order),
        .rvfi_inst(rvfi_inst),
        .rvfi_rs1_addr(rvfi_rs1_addr),
        .rvfi_rs2_addr(rvfi_rs2_addr),
        .rvfi_rs1_rdata(rvfi_rs1_rdata),
        .rvfi_rs2_rdata(rvfi_rs2_rdata),
        .rvfi_rd_addr(rvfi_rd_addr),
        .rvfi_rd_wdata(rvfi_rd_wdata),
        .rvfi_pc_rdata(rvfi_pc_rdata),
        .rvfi_pc_wdata(rvfi_pc_wdata),
        .rvfi_dmem_addr(rvfi_dmem_addr),
        .rvfi_dmem_rmask(rvfi_dmem_rmask),
        .rvfi_dmem_wmask(rvfi_dmem_wmask),
        .rvfi_dmem_rdata(rvfi_dmem_rdata),
        .rvfi_dmem_wdata(rvfi_dmem_wdata)
    );

    // ============================================================
    // Commit → rename + free_list
    // ============================================================
    // Allow all valid instructions to commit (including speculative)
    // Flush recovery will handle returning physical registers from
    // flushed speculative instructions
    assign commit_we =
        (regf_we_back == 1'b1) &&
        (mem_wb_reg.valid == 1'b1) &&
        (~freeze_stall);

    assign commit_arch     = mem_wb_reg.dest_arch;
    assign commit_phys     = mem_wb_reg.dest_phys_new;
    assign commit_old_phys = mem_wb_reg.dest_phys_old;

    // ============================================================
    // Hazard Units
    // ============================================================
    forward forward_i(
        .id_ex(id_ex_reg),
        .ex_mem(ex_mem_reg),
        .mem_wb(mem_wb_reg),
        .forward_a_sel(forward_a_sel),
        .forward_b_sel(forward_b_sel)
    );

    stall stall_i(
        .id_ex(id_ex_reg_before),
        .ex_mem(ex_mem_reg_before),
        .stall_signal(stall_signal)
    );

    freeze freeze_i(
        .mem_wb(mem_wb_reg),
        .imem_resp(imem_resp),
        .dmem_resp(dmem_resp),
        .freeze_stall(freeze_stall)
    );

    // ============================================================
    // Pipeline Registers
   // ============================================================
    // CRITICAL FIX: All control signals must be register-based
    // is_speculative propagates register-to-register ONLY
    // ============================================================
    // Pipeline Register Updates
    // ============================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            if_id_reg  <= '0;
            id_ex_reg  <= '0;
            ex_mem_reg <= '0;
            mem_wb_reg <= '0;

        end
        else if (freeze_stall) begin
            // When memory stalls, keep all registers unchanged
            if_id_reg  <= if_id_reg;
            id_ex_reg  <= id_ex_reg;
            ex_mem_reg <= ex_mem_reg;
            mem_wb_reg  <= mem_wb_reg;

        end
        else begin
            // Normal case: latch _before outputs with same-cycle is_speculative propagation
            //CRITICAL: is_speculative comes from _before (about-to-be-latched), not registered (last cycle)
            // This ensures synchronous propagation without combinational paths between stages
            
            id_ex_stage_reg_t id_ex_next;
            ex_mem_stage_reg_t ex_mem_next;
            mem_wb_stage_reg_t mem_wb_next;
            
            // IF/ID: Clear on flush (like main branch)
            // This prevents old speculative instructions from propagating after branch resolves
            if_id_stage_reg_t if_id_next;
            if_id_next = (flush_pipeline ? '0 : if_id_reg_before);
            if_id_reg <= if_id_next;
            

 // ID/EX: Latch from _before, is_speculative from if_id_next (being latched THIS cycle)
            // CRITICAL: Use if_id_next (about-to-be-latched), NOT if_id_reg (old) or if_id_reg_before (decode output using old if_id)!
            id_ex_next = id_ex_reg_before;
            id_ex_next.is_speculative = if_id_next.is_speculative;
            id_ex_reg <= id_ex_next;
            
            // EX/MEM: Latch from _before, is_speculative from id_ex_reg_before (being latched THIS cycle)
            ex_mem_next = ex_mem_reg_before;
            ex_mem_next.is_speculative = id_ex_reg_before.is_speculative;
            ex_mem_reg <= ex_mem_next;
            
            // MEM/WB: Latch from _before, is_speculative from ex_mem_next (being latched THIS cycle)
            // CRITICAL: Use ex_mem_next (about-to-be-latched), NOT ex_mem_reg_before!
            // ex_mem_reg_before is combinational output from memstage which uses OLD ex_mem value,
            // causing is_speculative to lag by 1 cycle. We need same-cycle propagation!
            mem_wb_next = mem_wb_reg_before;
            mem_wb_next.is_speculative = ex_mem_next.is_speculative;
            mem_wb_reg <= mem_wb_next;

            // Debug AUIPC
            if (id_ex_reg_before.valid && id_ex_reg_before.opcode == 7'h17) begin
                $display("[CPU] AUIPC latching to ID/EX: PC=0x%h, alu_m1_sel=%b, imm=0x%h",
                         id_ex_reg_before.pc, id_ex_reg_before.alu_m1_sel, id_ex_reg_before.imm_out);
            end
            
            if (ex_mem_reg_before.valid && ex_mem_reg_before.opcode == 7'h17) begin
                $display("[CPU] AUIPC latching to EX/MEM: PC=0x%h, alu_out=0x%h",
                         ex_mem_reg_before.pc, ex_mem_reg_before.alu_out);
            end
            
            // Debug flush
            if (flush_pipeline) begin
                $display("[CPU] FLUSH active! Clearing pipeline stages");
            end
            
            // =================================================================
            // STEP 2: Flush Recovery from FIFO
            // =================================================================
            // Collect all pending allocations from FIFO and return to free_list
            
            flush_free_count = 5'd0;
            for (int i = 0; i < PENDING_ALLOC_DEPTH; i++) begin
                flush_free_phys[i] = 6'd0;
            end
            
            if (flush_pipeline) begin
                // Collect all valid pending allocations
                for (int i = 0; i < PENDING_ALLOC_DEPTH; i++) begin
                    if (pending_allocs[i].valid) begin
                        flush_free_phys[flush_free_count] = pending_allocs[i].phys_reg;
                        flush_free_count = flush_free_count + 1;
                        $display("[FLUSH RECOVERY] Returning phys=%0d (was for x%0d, order=%0d)",
                                 pending_allocs[i].phys_reg, pending_allocs[i].arch_reg,
                                 pending_allocs[i].order);
                    end
                end
                
                if (flush_free_count > 0) begin
                    $display("[FLUSH RECOVERY] Total %0d physical registers returned to free list", 
                             flush_free_count);
                end
                else begin
                    $display("[FLUSH RECOVERY] No pending allocations to return");
                end
            end
            
            // // Debug: Track is_speculative propagation for PC=0xdb138de0
            // if (if_id_reg_before.pc == 32'hdb138de0 || id_ex_reg_before.pc == 32'hdb138de0 ||
            //     ex_mem_reg_before.pc == 32'hdb138de0 || mem_wb_reg_before.pc == 32'hdb138de0) begin
            //     $display("[CPU Pipeline] IF/ID=0x%h(spec=%b) → ID/EX=0x%h(spec=%b) → EX/MEM=0x%h(spec=%b) → MEM/WB=0x%h(spec=%b)",
            //              if_id_reg_before.pc, if_id_reg_before.is_speculative,
            //              id_ex_reg_before.pc, id_ex_reg_before.is_speculative,
            //              ex_mem_reg_before.pc, ex_mem_reg_before.is_speculative,
            //              mem_wb_reg_before.pc, mem_wb_reg_before.is_speculative);
            // end
        end
    end

    // Debug: Trace rs2_v through pipeline registers for problematic PCs
    always @(posedge clk) begin
        // ID/EX register
        if (id_ex_reg_before.pc == 32'hdb0737f0 || id_ex_reg_before.pc == 32'hdb0737f8) begin
            $display("[PIPELINE @%0t] ID/EX: PC=0x%h valid=%b rs2_arch=%0d rs2_v=0x%h",
                     $time, id_ex_reg_before.pc, id_ex_reg_before.valid, 
                     id_ex_reg_before.rs2_arch, id_ex_reg_before.rs2_v);
        end
        // EX/MEM register  
        if (ex_mem_reg_before.pc == 32'hdb0737f0 || ex_mem_reg_before.pc == 32'hdb0737f8) begin
            $display("[PIPELINE @%0t] EX/MEM: PC=0x%h valid=%b rs2_arch=%0d rs2_v=0x%h",
                     $time, ex_mem_reg_before.pc, ex_mem_reg_before.valid,
                     ex_mem_reg_before.rs2_arch, ex_mem_reg_before.rs2_v);
        end
        // MEM/WB register
        if (mem_wb_reg_before.pc == 32'hdb0737f0 || mem_wb_reg_before.pc == 32'hdb0737f8) begin
            $display("[PIPELINE @%0t] MEM/WB: PC=0x%h valid=%b is_spec=%b rs2_arch=%0d rs2_v=0x%h",
                     $time, mem_wb_reg_before.pc, mem_wb_reg_before.valid, mem_wb_reg_before.is_speculative,
                     mem_wb_reg_before.rs2_arch, mem_wb_reg_before.rs2_v);
        end
    end

endmodule
