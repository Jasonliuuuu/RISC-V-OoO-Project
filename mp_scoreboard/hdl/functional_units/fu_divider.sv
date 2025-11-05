/**
 * ============================================================================
 * 除法器功能单元 (Divider Functional Unit)
 * ============================================================================
 * 功能：
 * - 执行 RISC-V M 扩展的除法和取模指令
 * - 长延迟执行 (LATENCY_DIV = 10 cycles)
 * - 模拟真实硬件中除法器的延迟
 *
 * 支持的操作 (funct3):
 * - DIV  (100): 有符号除法
 * - DIVU (101): 无符号除法
 * - REM  (110): 有符号取模
 * - REMU (111): 无符号取模
 *
 * 识别方式：
 * - opcode = op_reg (0110011)
 * - funct7 = 7'b0000001 (M extension)
 * - funct3[2] = 1 (除法，0 表示乘法)
 * ============================================================================
 */

module fu_divider
    import rv32i_types::*;
    (
        input  logic        clk,
        input  logic        rst,
        fu_interface.fu     fu_if
    );

    // ========================================================================
    // 内部状态机和计数器
    // ========================================================================
    fu_status_t     current_inst;       // 当前执行的指令
    logic           busy;               // 除法器忙碌
    logic [3:0]     cycle_count;        // 延迟周期计数器
    logic [63:0]    div_result;         // 除法结果 (商+余数)

    assign fu_if.issue_ready = !busy;
    assign fu_if.exec_busy = busy;

    // ========================================================================
    // 除法器控制逻辑
    // ========================================================================
    always_ff @(posedge clk) begin
        if (rst || fu_if.flush) begin
            busy <= 1'b0;
            cycle_count <= '0;
            current_inst <= '0;
            div_result <= '0;

        end else if (fu_if.issue_valid && fu_if.issue_ready) begin
            // Issue 新除法指令
            busy <= 1'b1;
            cycle_count <= LATENCY_DIV - 1;  // 延迟 10 周期
            current_inst <= fu_if.issue_data;
            // 计算除法 (组合逻辑，但结果要延迟输出)
            div_result <= compute_division(fu_if.issue_data);

        end else if (busy) begin
            // 倒计时
            if (cycle_count == 0) begin
                busy <= 1'b0;  // 完成
            end else begin
                cycle_count <= cycle_count - 1;
            end
        end
    end

    // ========================================================================
    // 除法计算函数 (组合逻辑)
    // ========================================================================
    function automatic logic [63:0] compute_division(fu_status_t inst);
        logic signed   [31:0] a_s, b_s, quotient_s, remainder_s;
        logic unsigned [31:0] a_u, b_u, quotient_u, remainder_u;

        a_s = signed'(inst.vj);
        b_s = signed'(inst.vk);
        a_u = unsigned'(inst.vj);
        b_u = unsigned'(inst.vk);

        case (inst.funct3)
            3'b100: begin  // DIV: 有符号除法
                if (b_s == 0) begin
                    quotient_s = -1;  // 除以零
                end else if (a_s == 32'sh80000000 && b_s == -1) begin
                    quotient_s = 32'sh80000000;  // 溢出情况
                end else begin
                    quotient_s = a_s / b_s;
                end
                return {32'b0, quotient_s};
            end

            3'b101: begin  // DIVU: 无符号除法
                if (b_u == 0) begin
                    quotient_u = 32'hFFFFFFFF;
                end else begin
                    quotient_u = a_u / b_u;
                end
                return {32'b0, quotient_u};
            end

            3'b110: begin  // REM: 有符号取模
                if (b_s == 0) begin
                    remainder_s = a_s;
                end else if (a_s == 32'sh80000000 && b_s == -1) begin
                    remainder_s = 0;
                end else begin
                    remainder_s = a_s % b_s;
                end
                return {32'b0, remainder_s};
            end

            3'b111: begin  // REMU: 无符号取模
                if (b_u == 0) begin
                    remainder_u = a_u;
                end else begin
                    remainder_u = a_u % b_u;
                end
                return {32'b0, remainder_u};
            end

            default: return 64'bx;
        endcase
    endfunction

    // ========================================================================
    // Complete 阶段
    // ========================================================================
    assign fu_if.complete_valid = (busy && cycle_count == 0);

    always_comb begin
        fu_if.complete_data = '0;

        if (busy && cycle_count == 0) begin
            fu_if.complete_data.valid     = 1'b1;
            fu_if.complete_data.rd        = current_inst.fi;
            fu_if.complete_data.data      = div_result[31:0];
            fu_if.complete_data.pc        = current_inst.pc;
            fu_if.complete_data.inst      = current_inst.inst;
            fu_if.complete_data.order     = current_inst.order;
            fu_if.complete_data.rs1_addr  = current_inst.fj;
            fu_if.complete_data.rs2_addr  = current_inst.fk;
            fu_if.complete_data.rs1_rdata = current_inst.vj;
            fu_if.complete_data.rs2_rdata = current_inst.vk;
            fu_if.complete_data.pc_wdata  = current_inst.pc + 4;
        end
    end

endmodule : fu_divider
