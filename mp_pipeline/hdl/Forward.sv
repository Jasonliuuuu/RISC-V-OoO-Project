module forward
    import rv32i_types::*;
    import forward_amux::*;
    import forward_bmux::*;
(
    input  id_ex_stage_reg_t  id_ex,      // current EX stage input
    input  ex_mem_stage_reg_t ex_mem,     // one stage ahead
    input  mem_wb_stage_reg_t mem_wb,     // two stages ahead (WB)

    output forward_a_sel_t forward_a_sel,
    output forward_b_sel_t forward_b_sel
);

    // ============================================================
    // Physical tag comparisons
    // ============================================================

    // ID/EX → EX stage operands (needs rs1_phys, rs2_phys)
    logic [5:0] rs1_tag, rs2_tag;
    assign rs1_tag = id_ex.rs1_phys;
    assign rs2_tag = id_ex.rs2_phys;

    // EX/MEM write-back physical reg (alu_out path)
    logic [5:0] ex_dest_phys;
    assign ex_dest_phys = ex_mem.dest_phys_new;

    // MEM/WB write-back physical reg (regfilemux_out path)
    logic [5:0] wb_dest_phys;
    assign wb_dest_phys = mem_wb.dest_phys_new;

    // Whether EX/MEM is really writing back
    logic ex_writes;
    assign ex_writes = ex_mem.regf_we;

    // Whether WB stage is writing back
    logic wb_writes;
    assign wb_writes = mem_wb.regf_we;

    // ============================================================
    // Forwarding for rs1
    // Priority: WB → EX/MEM → (PRF default)
    // ============================================================
    always_comb begin
        forward_a_sel = forward_amux::rs1_v;  // default: PRF value

        // Priority 1: MEM/WB forwarding (final writeback value)
        if (wb_writes && (wb_dest_phys != 0) &&
            (wb_dest_phys == rs1_tag)) begin
            forward_a_sel = forward_amux::regfilemux_out;
        end

        // Priority 2: EX/MEM forwarding (alu_out / br_en / u_imm)
        else if (ex_writes && (ex_dest_phys != 0) &&
                 (ex_dest_phys == rs1_tag)) begin
            // ALU result forwarding
            forward_a_sel = forward_amux::alu_out;
        end
    end

    // ============================================================
    // Forwarding for rs2
    // Priority: WB → EX/MEM → (PRF default)
    // ============================================================
    always_comb begin
        forward_b_sel = forward_bmux::rs2_v;  // default

        // Priority 1: WB forwarding
        if (wb_writes && (wb_dest_phys != 0) &&
            (wb_dest_phys == rs2_tag)) begin
            forward_b_sel = forward_bmux::regfilemux_out;
        end

        // Priority 2: EX/MEM forwarding
        else if (ex_writes && (ex_dest_phys != 0) &&
                 (ex_dest_phys == rs2_tag)) begin
            forward_b_sel = forward_bmux::alu_out;
        end
    end

endmodule
