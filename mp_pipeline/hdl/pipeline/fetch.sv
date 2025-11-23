module fetch 
    import rv32i_types::*;

(
    input logic clk,
    input logic rst,
    //========== BNEZ / JUMP ==========
    input logic br_en,
    input logic [31:0]  branch_pc,
    //========== I-mem 介面回傳 ==========
    input logic [31:0]  imem_rdata,
    input  logic        imem_resp,
    // ========== Pipeline control ==========
    input  logic        stall_signal,
    input  logic freeze_stall,
    input  logic flush_pipeline,  // Required port (flush handled in decode stage)
    // ========== The requestment to I-mem ==========
    output logic [31:0] imem_addr,
    output logic [3:0]  imem_rmask,
    // ========== 給decode的IF/ID ====================
    output var if_id_stage_reg_t  if_id_reg_before, 
    output logic [31:0] imem_rdata_id, 
    output logic        imem_resp_id
    
);
    logic ce_ifid; //clock enable
    assign ce_ifid = !(freeze_stall || stall_signal);


    logic [31:0] pc_reg;
    logic [1:0] just_flushed;  // 2-bit counter for detecting speculative window
    logic prev_flush;  // Track previous flush signal for falling edge detection
    
    // DEBUG: Cycle counter to distinguish different clock cycles
    logic [31:0] cycle_count;
    logic [31:0] prev_pc;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
            prev_pc <= 32'h60000000;
        end else begin
            cycle_count <= cycle_count + 1;
            prev_pc <= pc_reg;
        end
    end

    //read signal always 1
    assign imem_rmask = 4'b1111;

    // ============================================================
    // OPTION 1: Flush Falling Edge Timing with Counter
    // Start just_flushed counter when flush ENDS, not when it starts
    // This minimizes false positives (only 1 vs many)
    //
    // Timing:
    //   Cycle N:   flush=1, pc<=branch_pc, just_flushed<=0 (no change)
    //   Cycle N+1: flush=0 (falling edge!), just_flushed<=2 (START counter)
    //   Cycle N+2: just_flushed=2 → MARK SPECULATIVE
    //   Cycle N+3: just_flushed=1 → NOT speculative
    always_ff @(posedge clk) begin
        if (rst) begin
            pc_reg <= 32'h60000000;
            just_flushed <= 2'b00;
        end
        else if (freeze_stall) begin
            pc_reg <= pc_reg;
            just_flushed <= just_flushed;  // Hold counter during stall
        end
        // PRIORITY 1: Flush - jump to branch target
        else if (flush_pipeline) begin
            pc_reg <= branch_pc;
            just_flushed <= 2'b00;  // DON'T start counter yet!
            $display("[FETCH Cycle=%0d @%0t] PC UPDATE (FLUSH): 0x%08x → 0x%08x", 
                     cycle_count, $time, pc_reg, branch_pc);
        end
        // PRIORITY 2: Flush falling edge - START the hold counter
        else if (prev_flush && !flush_pipeline) begin
            pc_reg <= pc_reg;  // Hold at branch target
            just_flushed <= 2'b10;  // NOW start 2-cycle counter
            $display("[FETCH Cycle=%0d @%0t] FLUSH ENDS - START HOLD: PC=0x%08x", 
                     cycle_count, $time, pc_reg);
        end
        // PRIORITY 3: Counter = 2 (first hold cycle)
        else if (just_flushed == 2'b10) begin
            pc_reg <= pc_reg;  // HOLD PC
            just_flushed <= 2'b01;  // Decrement to 1
            $display("[FETCH Cycle=%0d @%0t] PC HOLD cycle 1: 0x%08x", 
                     cycle_count, $time, pc_reg);
        end
        // PRIORITY 4: Counter = 1 (second hold cycle)
        else if (just_flushed == 2'b01) begin
            pc_reg <= pc_reg;  // HOLD PC one more cycle
            just_flushed <= 2'b00;  // Clear counter
            $display("[FETCH Cycle=%0d @%0t] PC HOLD cycle 2: 0x%08x", 
                     cycle_count, $time, pc_reg);
        end
        // PRIORITY 5: Normal increment
        else begin
            pc_reg <= pc_reg + 4;
            just_flushed <= 2'b00;
            // DEBUG: Track PC updates in critical regions with cycle number
            if (pc_reg >= 32'h60000080 && pc_reg <= 32'h60000094) begin
                $display("[FETCH Cycle=%0d @%0t] PC UPDATE (NORMAL): 0x%08x → 0x%08x (flush=%b)", 
                         cycle_count, $time, pc_reg, pc_reg + 32'd4, flush_pipeline);
            end
            if (pc_reg >= 32'h6d333080 && pc_reg <= 32'h6d333094) begin
                $display("[FETCH Cycle=%0d @%0t] PC UPDATE (NORMAL): 0x%08x → 0x%08x (flush=%b)", 
                         cycle_count, $time, pc_reg, pc_reg + 32'd4, flush_pipeline);
            end
            if (pc_reg >= 32'hdb139d40 && pc_reg <= 32'hdb139d50) begin
                $display("[FETCH Cycle=%0d @%0t] PC UPDATE (NORMAL): 0x%08x → 0x%08x (flush=%b)", 
                         cycle_count, $time, pc_reg, pc_reg + 32'd4, flush_pipeline);
            end
        end
    end


    // DEBUG: Track actual PC register value changes
    always_ff @(posedge clk) begin
        if (!rst && pc_reg != prev_pc) begin
            if ((pc_reg >= 32'h60000080 && pc_reg <= 32'h60000094) ||
                (pc_reg >= 32'hdb139d40 && pc_reg <= 32'hdb139d50) ||
                (pc_reg >= 32'h2cc5fd40 && pc_reg <= 32'h2cc5fd50)) begin
                $display("[FETCH Cycle=%0d @%0t] *** ACTUAL PC CHANGED: 0x%08x → 0x%08x ***", 
                         cycle_count, $time, prev_pc, pc_reg);
            end
        end
    end

    // DEBUG: Track flush signal timing - CRITICAL for understanding PC update issue
    always_ff @(posedge clk) begin
        if (rst) begin
            prev_flush <= 1'b0;
        end else begin
            prev_flush <= flush_pipeline;
            
            // Track flush signal transitions with cycle counter
            if (flush_pipeline && !prev_flush) begin
                $display("[FETCH Cycle=%0d @%0t] !!! FLUSH STARTS: PC=0x%08x, br_pc=0x%08x !!!", 
                         cycle_count, $time, pc_reg, branch_pc);
            end
            if (!flush_pipeline && prev_flush) begin
                $display("[FETCH Cycle=%0d @%0t] !!! FLUSH ENDS: PC=0x%08x !!!", 
                         cycle_count, $time, pc_reg);
            end
        end
    end

    // DEBUG: Track what gets fetched
    always @(posedge clk) begin
        if (!rst && !freeze_stall) begin
            if ((pc_reg >= 32'h60000080 && pc_reg <= 32'h60000094) ||
                (pc_reg >= 32'h6d333080 && pc_reg <= 32'h6d333094) ||
                (pc_reg >= 32'hdb139d40 && pc_reg <= 32'hdb139d50) ||
                (pc_reg >= 32'h2cc5fd40 && pc_reg <= 32'h2cc5fd50)) begin
                $display("[FETCH @%0t] Fetching from PC=0x%08x, flush=%b", 
                         $time, pc_reg, flush_pipeline);
            end
        end
    end

    // Track previous cycle's flush state to detect first instruction after hold
    logic prev_just_flushed;
    always_ff @(posedge clk) begin
        if (rst) begin
            prev_just_flushed <= 1'b0;
        end
        else begin
            // Track if we were in hold last cycle
            prev_just_flushed <= (just_flushed > 2'b00);
        end
    end

    // ============================================================
    // IF/ID Stage Register - HARMLESS BUBBLES
    // ============================================================
    // KEY INSIGHT: Bubbles (valid=0) must be COMPLETELY harmless
    // - All flags that affect commit MUST be 0 when valid=0
    // - Only the FIRST real instruction after hold gets is_speculative=1
    // ============================================================
    always_comb begin
        // Declare local variables first (SystemVerilog requirement)
        logic is_bubble;
        logic flush_just_ended;
        
        if_id_reg_before.pc = pc_reg;
        
        // Detect flush falling edge (flush was 1, now 0) - critical transition cycle!
        // During this cycle, flush=0 but just_flushed hasn't updated from 0→2 yet
        flush_just_ended = prev_flush && !flush_pipeline;
        
        // Determine if this should be a bubble (invalid instruction)
        // - During PC hold cycles (just_flushed > 0): BUBBLE
        // - During flush: BUBBLE  
        // - During freeze stall: BUBBLE
        // - No imem response: BUBBLE
        // - **CRITICAL**: Flush just ended (transition cycle): BUBBLE
        is_bubble = (just_flushed > 2'b00) || flush_pipeline || freeze_stall || !imem_resp || flush_just_ended;
        
        if (is_bubble) begin
            // HARMLESS BUBBLE: All commit-affecting flags = 0
            if_id_reg_before.valid = 1'b0;
            if_id_reg_before.is_speculative = 1'b0;  // CRITICAL: no speculative contamination!
        end
        else begin
            // Real valid instruction
            if_id_reg_before.valid = 1'b1;
            
            // Mark as speculative if this is the FIRST instruction after flush hold
            // prev_just_flushed=1 means last cycle was in hold, this cycle is first real fetch
            if_id_reg_before.is_speculative = prev_just_flushed;
            
            // Debug: Show when we mark speculative
            if (prev_just_flushed) begin
                $display("[FETCH @%0t] SPEC_MARK (first after hold): PC=0x%h", 
                         $time, pc_reg);
            end
        end
        
        // Debug bubble logic for critical PCs
        if (pc_reg >= 32'hdb138de0 && pc_reg <= 32'hdb138df0) begin
            $display("[FETCH @%0t] PC=0x%h: flush=%b prev_flush=%b flush_just_ended=%b just_flushed=%d → is_bubble=%b valid=%b spec=%b",
                     $time, pc_reg, flush_pipeline, prev_flush, flush_just_ended, just_flushed,
                     is_bubble, if_id_reg_before.valid, if_id_reg_before.is_speculative);
        end
    end

    // Memory address calculation - also use flush_pipeline for consistency
    always_comb begin
        if (flush_pipeline) begin
            imem_addr = branch_pc;  // Fetch from branch target when flushing
        end
        else begin
            imem_addr = pc_reg;  // Normal fetch from current PC
        end
    end
// =============== IF -> ID inst/resp ================
    //把指令與有效為打一拍 條件與上面一致
    // Flush 時把inst -> NOP, resp -> 0, 避免鬼指令
    always_ff @(posedge clk) begin
        if (rst) begin
            imem_rdata_id <= 32'h0000_0013; //NOP: ADDI x0, x0, 0
            imem_resp_id <= 1'b0; 
        end
        else if (flush_pipeline) begin
            imem_rdata_id <= 32'h0000_0013; //無害化 (NOP)
            imem_resp_id <= 1'b0; 
        end
        else if (ce_ifid) begin
            imem_rdata_id <= imem_rdata; 
            imem_resp_id <= imem_resp; 
        end
        //else: HOLD
    end
    


    

   


endmodule

