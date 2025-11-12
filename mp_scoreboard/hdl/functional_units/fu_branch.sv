/**
 * ============================================================================
 * 分支功能单元 (Branch Functional Unit)
 * ============================================================================
 * 功能：
 * - 执行 RISC-V 分支指令 (BEQ, BNE, BLT, BGE, BLTU, BGEU)
 * - 执行 JAL 和 JALR 无条件跳转指令
 * - 计算分支条件是否满足
 * - 计算分支目标地址
 * - 单周期执行
 *
 * 输出：
 * - 分支是否跳转
 * - 分支目标地址 (通过 flush 信号传递给 Fetch)
 * - 返回地址 (对于 JAL/JALR)
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
    logic [31:0] target_addr;
    logic [31:0] return_addr;

    assign a_signed   = signed'(current_inst.vj);
    assign b_signed   = signed'(current_inst.vk);
    assign a_unsigned = unsigned'(current_inst.vj);
    assign b_unsigned = unsigned'(current_inst.vk);

    always_comb begin
        br_taken = 1'b0;
        target_addr = current_inst.pc + 4;  // 默认：不跳转，继续下一条
        return_addr = current_inst.pc + 4;  // JAL/JALR 返回地址

        if (valid) begin
            case (current_inst.opcode)
                op_br: begin
                    // 条件分支指令
                    case (current_inst.funct3)
                        3'b000: br_taken = (a_unsigned == b_unsigned);       // BEQ
                        3'b001: br_taken = (a_unsigned != b_unsigned);       // BNE
                        3'b100: br_taken = (a_signed < b_signed);            // BLT
                        3'b101: br_taken = (a_signed >= b_signed);           // BGE
                        3'b110: br_taken = (a_unsigned < b_unsigned);        // BLTU
                        3'b111: br_taken = (a_unsigned >= b_unsigned);       // BGEU
                        default: br_taken = 1'b0;
                    endcase
                    // 确保4字节对齐（对于只支持32位指令的实现）
                    target_addr = (current_inst.pc + current_inst.imm) & 32'hfffffffc;
                end

                op_jal: begin
                    // JAL: 无条件跳转，目标地址 = PC + J_imm
                    // 确保4字节对齐（对于只支持32位指令的实现）
                    br_taken = 1'b1;
                    target_addr = (current_inst.pc + current_inst.imm) & 32'hfffffffc;
                end

                op_jalr: begin
                    // JALR: 无条件跳转，目标地址 = (rs1 + imm) & ~3
                    // 注意：对于只支持32位指令的实现，必须4字节对齐（清除最低2位）
                    // 如果支持压缩指令，则应该是 & ~1（2字节对齐）
                    br_taken = 1'b1;
                    target_addr = (current_inst.vj + current_inst.imm) & 32'hfffffffc;
                end

                default: br_taken = 1'b0;
            endcase
        end
    end

    // 输出分支/跳转信号
    assign branch_taken = valid && br_taken;
    assign branch_target = target_addr;

    // ========================================================================
    // Complete 阶段
    // ========================================================================
    assign fu_if.complete_valid = valid;

    always_comb begin
        fu_if.complete_data = '0;

        if (valid) begin
            fu_if.complete_data.valid     = 1'b1;
            fu_if.complete_data.pc        = current_inst.pc;
            fu_if.complete_data.inst      = current_inst.inst;
            fu_if.complete_data.order     = current_inst.order;
            fu_if.complete_data.rs1_addr  = current_inst.fj;
            fu_if.complete_data.rs2_addr  = current_inst.fk;
            fu_if.complete_data.rs1_rdata = current_inst.vj;
            fu_if.complete_data.rs2_rdata = current_inst.vk;

            // JAL/JALR 写返回地址到 rd，分支不写寄存器
            if (current_inst.opcode == op_jal || current_inst.opcode == op_jalr) begin
                fu_if.complete_data.rd   = current_inst.fi;
                fu_if.complete_data.data = return_addr;  // PC + 4
            end else begin
                fu_if.complete_data.rd   = 5'b0;  // 分支不写寄存器
                fu_if.complete_data.data = 32'b0;
            end

            // pc_wdata: 下一条指令的 PC
            fu_if.complete_data.pc_wdata = br_taken ? target_addr : (current_inst.pc + 4);
        end
    end

endmodule : fu_branch
