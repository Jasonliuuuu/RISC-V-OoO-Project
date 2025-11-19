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
            if (commit_we && commit_arch != 0) begin
                RAT[commit_arch] <= commit_phys;
            end
        end
    end

    // ============================================================
    //          Decode: RAT lookup (pure combinational)
    // ============================================================
    always_comb begin
        rs1_phys = RAT[rs1_arch];
        rs2_phys = RAT[rs2_arch];
        old_phys = RAT[rd_arch];
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
        end
        else begin
            new_phys  = 6'd0;
            rename_we = 1'b0;
        end
    end

    // ============================================================
    //               Free list return at commit
    // ============================================================
    always_comb begin
        if (commit_we && commit_arch != 0) begin
            free_en   = 1'b1;
            free_phys = commit_old_phys;
        end
        else begin
            free_en   = 1'b0;
            free_phys = 6'd0;
        end
    end

endmodule
