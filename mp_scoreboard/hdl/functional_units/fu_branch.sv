/**
 * ============================================================================
 * 分支功能单元 (Branch Functional Unit)
 * ============================================================================
 * 功能：
 * - 执行 RISC-V 分支指令 (BEQ, BNE, BLT, BGE, BLTU, BGEU)
 * - 计算分支条件是否满足
 * - 计算分支目标地址
 * - 单周期执行
 *
 * 输出：
 * - 分支是否跳转
 * - 分支目标地址 (通过 flush 信号传递给 Fetch)
 * ============================================================================
 */

module fu_branch
    import rv32i_types::*;
    (
        input  logic        clk,
        input  logic        rst,
        fu_interface.fu     fu_if,

        // 分支结果输出 (到 Fetch 阶段)
        output logic        branch_taken,       // 分支是否跳转
        output logic [31:0] branch_target       // 分支目标地址
    );

    // ========================================================================
    // 内部寄存器
    // ========================================================================
    fu_status_t     current_inst;
    logic           valid;

    assign fu_if.issue_ready = !valid;
    assign fu_if.exec_busy = valid;

    // ========================================================================
    // 流水线控制
    // ========================================================================
    always_ff @(posedge clk) begin
        if (rst || fu_if.flush) begin
            valid <= 1'b0;
            current_inst <= '0;
        end else if (fu_if.issue_valid && fu_if.issue_ready) begin
            valid <= 1'b1;
            current_inst <= fu_if.issue_data;
        end else if (valid) begin
            valid <= 1'b0;  // 单周期完成
        end
    end

    // ========================================================================
    // 分支条件计算 (组合逻辑)
    // ========================================================================
    logic br_taken;
    logic signed   [31:0] a_signed, b_signed;
    logic unsigned [31:0] a_unsigned, b_unsigned;

    assign a_signed   = signed'(current_inst.vj);
    assign b_signed   = signed'(current_inst.vk);
    assign a_unsigned = unsigned'(current_inst.vj);
    assign b_unsigned = unsigned'(current_inst.vk);

    always_comb begin
        br_taken = 1'b0;

        if (valid) begin
            case (current_inst.funct3)
                3'b000: br_taken = (a_unsigned == b_unsigned);       // BEQ
                3'b001: br_taken = (a_unsigned != b_unsigned);       // BNE
                3'b100: br_taken = (a_signed < b_signed);            // BLT
                3'b101: br_taken = (a_signed >= b_signed);           // BGE
                3'b110: br_taken = (a_unsigned < b_unsigned);        // BLTU
                3'b111: br_taken = (a_unsigned >= b_unsigned);       // BGEU
                default: br_taken = 1'b0;
            endcase
        end
    end

    // 分支目标地址 = PC + B_imm
    assign branch_taken = valid && br_taken;
    assign branch_target = current_inst.pc + current_inst.imm;

    // ========================================================================
    // Complete 阶段
    // ========================================================================
    assign fu_if.complete_valid = valid;

    always_comb begin
        fu_if.complete_data = '0;

        if (valid) begin
            fu_if.complete_data.valid     = 1'b1;
            fu_if.complete_data.rd        = 5'b0;  // 分支不写寄存器
            fu_if.complete_data.data      = 32'b0;
            fu_if.complete_data.pc        = current_inst.pc;
            fu_if.complete_data.inst      = current_inst.inst;
            fu_if.complete_data.order     = current_inst.order;
            fu_if.complete_data.rs1_addr  = current_inst.fj;
            fu_if.complete_data.rs2_addr  = current_inst.fk;
            fu_if.complete_data.rs1_rdata = current_inst.vj;
            fu_if.complete_data.rs2_rdata = current_inst.vk;
            fu_if.complete_data.pc_wdata  = br_taken ? branch_target : (current_inst.pc + 4);
        end
    end

endmodule : fu_branch
