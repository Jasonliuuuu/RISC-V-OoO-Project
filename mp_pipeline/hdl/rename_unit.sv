module rename_unit(
    input  logic clk,
    input  logic rst,

    // ====== Architectural registers from decode ======
    input  logic [4:0] rs1_arch,
    input  logic [4:0] rs2_arch,
    input  logic [4:0] rd_arch,

    // ====== Free list allocate interface ======
    input  logic       alloc_valid,
    input  logic [5:0] alloc_phys,

    // ====== Commit interface (from WB) ======
    input  logic       commit_we,
    input  logic [4:0] commit_arch,
    input  logic [5:0] commit_phys,      // dest_phys_new
    input  logic [5:0] commit_old_phys,  // dest_phys_old

    // ====== Output to decode ======
    output logic [5:0] rs1_phys,
    output logic [5:0] rs2_phys,
    output logic [5:0] new_phys,
    output logic [5:0] old_phys,
    output logic       rename_we,

    // ====== Free list return ======
    output logic       free_en,
    output logic [5:0] free_phys
);

    // ============================================================
    //              Register Alias Table (RAT)
    // ============================================================
    logic [5:0] RAT [31:0];

    // ============================================================
    //                   Reset: Identity map
    // ============================================================
    integer i;
    always_ff @(posedge clk) begin
        if (rst) begin
            RAT[0] <= 6'd0;
            for (i = 1; i < 32; i++) begin
                RAT[i] <= i[5:0];
            end
        end
        else begin
            // =====================================================
            //                Commit: update RAT
            // =====================================================
            // CRITICAL: Never allow phys_reg 0 to be committed to non-zero arch regs
            // phys_reg 0 is reserved for architectural x0, using it for other regs
            // will cause incorrect register reads (always returning 0)
            if (commit_we && commit_arch != 0 && commit_phys != 0) begin
                RAT[commit_arch] <= commit_phys;
                // Track ALL RAT updates to verify correctness
                $display("[RAT UPDATE @%0t] x%0d: phys %0d → %0d (commit)", 
                         $time, commit_arch, RAT[commit_arch], commit_phys);
            end
            else if (commit_we && commit_arch != 0 && commit_phys == 0) begin
                // Blocked commit - this should NOT happen if allocation is correct!
                $error("[RAT ERROR] Attempted commit of phys=0 to x%0d (current phys=%0d)", 
                       commit_arch, RAT[commit_arch]);
            end
        end
    end


    // ============================================================
    //          RAT Snapshot for preventing RAW hazard
    // ============================================================
    // CRITICAL ARCHITECTURAL FIX:
    // To prevent Read-After-Write hazard where combinational RAT lookup
    // sees same-cycle commit updates, we maintain a snapshot of RAT
    // that decode reads from. This ensures decode sees the RAT state
    // from the PREVIOUS cycle, not mid-cycle updates.
    //
    // This maintains in-order pipeline semantics while preventing
    // delta-cycle re-evaluation issues in combinational logic.
    
    logic [5:0] RAT_snapshot [31:0];
    
    // Capture RAT state at each clock edge (for next cycle's decode)
    always_ff @(posedge clk) begin
        if (rst) begin
            // Initialize snapshot to identity mapping
            RAT_snapshot[0] <= 6'd0;
            for (int j = 1; j < 32; j++) begin
                RAT_snapshot[j] <= j[5:0];
            end
        end
        else begin
            // Capture current RAT state for next cycle
            RAT_snapshot <= RAT;
        end
    end

    // ============================================================
    //          Decode: RAT lookup (from snapshot)
    // ============================================================
    // Read from snapshot instead of live RAT to avoid seeing
    // same-cycle commits (delta cycle re-evaluation)
    
    always_comb begin
        // Lookup from SNAPSHOT (previous cycle's RAT state)
        rs1_phys = RAT_snapshot[rs1_arch];
        rs2_phys = RAT_snapshot[rs2_arch];
        old_phys = RAT_snapshot[rd_arch];
        
        // Debug RAT lookup
        if (rs2_arch == 26 || rs2_arch == 8) begin
            $display("[RAT SNAPSHOT] rs2_arch=%0d → rs2_phys=%0d (snapshot[26]=%0d snapshot[8]=%0d RAT[26]=%0d RAT[8]=%0d)", 
                     rs2_arch, rs2_phys, RAT_snapshot[26], RAT_snapshot[8], RAT[26], RAT[8]);
        end
    end

    // ============================================================
    //               Allocate physical register
    // ============================================================
    always_comb begin
        if (rd_arch == 5'd0) begin
            new_phys  = 6'd0;
            rename_we = 1'b0;
        end
        else if (alloc_valid) begin
            new_phys  = alloc_phys;
            rename_we = 1'b1;
            // Track allocations
            $display("[ALLOCATION] x%0d gets new phys=%0d (old phys=%0d)", 
                     rd_arch, alloc_phys, RAT_snapshot[rd_arch]);
        end
        else begin
            new_phys  = 6'd0;
            rename_we = 1'b0;
            // ERROR: alloc_valid is false but we need a register!
            if (rd_arch != 5'd0) begin
                $error("[ALLOCATION ERROR] Free list empty! Cannot allocate for x%0d", rd_arch);
            end
        end
    end

    // ============================================================
    //               Free list return at commit
    // ============================================================
    always_comb begin
        if (commit_we && commit_arch != 0) begin
            free_en   = 1'b1;
            free_phys = commit_old_phys;
            // Track register returns
            $display("[FREE] Returning phys=%0d (was mapped to x%0d)", 
                     commit_old_phys, commit_arch);
        end
        else begin
            free_en   = 1'b0;
            free_phys = 6'd0;
        end
    end

endmodule
