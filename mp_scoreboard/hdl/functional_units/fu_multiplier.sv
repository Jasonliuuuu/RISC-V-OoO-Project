/**
 * ============================================================================
 * 乘法器功能单元 (Multiplier Functional Unit)
 * ============================================================================
 * 功能：
 * - 执行 RISC-V M 扩展的乘法指令
 * - 多周期执行延迟 (LATENCY_MUL = 3 cycles)
 * - 模拟真实硬件中乘法器的流水线延迟
 *
 * 支持的操作 (funct3):
 * - MUL    (000): 32-bit × 32-bit → 低 32 位结果
 * - MULH   (001): 有符号 × 有符号 → 高 32 位结果
 * - MULHSU (010): 有符号 × 无符号 → 高 32 位结果
 * - MULHU  (011): 无符号 × 无符号 → 高 32 位结果
 *
 * 识别方式：
 * - opcode = op_reg (0110011)
 * - funct7 = 7'b0000001 (M extension 标识)
 * - funct3[2] = 0 (乘法，1 表示除法)
 * ============================================================================
 */

module fu_multiplier
    import rv32i_types::*;
    (
        input  logic        clk,        // 时钟信号
        input  logic        rst,        // 复位信号
        fu_interface.fu     fu_if       // FU 接口
    );

    // ========================================================================
    // 内部流水线寄存器 (3 级流水线模拟延迟)
    // ========================================================================
    fu_status_t     stage1_inst, stage2_inst, stage3_inst;
    logic           stage1_valid, stage2_valid, stage3_valid;
    logic [63:0]    stage1_result, stage2_result, stage3_result;

    // ========================================================================
    // Ready 信号：只有 stage1 空闲才能接受新指令
    // ========================================================================
    assign fu_if.issue_ready = !stage1_valid;

    // ========================================================================
    // 忙碌信号：任何一级流水线有效就表示忙碌
    // ========================================================================
    assign fu_if.exec_busy = stage1_valid || stage2_valid || stage3_valid;

    // ========================================================================
    // 流水线控制逻辑
    // ========================================================================
    always_ff @(posedge clk) begin
        if (rst || fu_if.flush) begin
            // ----------------------------------------------------------------
            // 复位或 Flush：清空所有流水级
            // ----------------------------------------------------------------
            stage1_valid <= 1'b0;
            stage2_valid <= 1'b0;
            stage3_valid <= 1'b0;
            stage1_inst  <= '0;
            stage2_inst  <= '0;
            stage3_inst  <= '0;
            stage1_result <= '0;
            stage2_result <= '0;
            stage3_result <= '0;

        end else begin
            // ----------------------------------------------------------------
            // 流水线推进
            // ----------------------------------------------------------------
            // Stage 3 → Complete
            stage3_valid  <= stage2_valid;
            stage3_inst   <= stage2_inst;
            stage3_result <= stage2_result;

            // Stage 2 → Stage 3
            stage2_valid  <= stage1_valid;
            stage2_inst   <= stage1_inst;
            stage2_result <= stage1_result;

            // Stage 1 (Issue → Stage 1)
            if (fu_if.issue_valid && fu_if.issue_ready) begin
                stage1_valid <= 1'b1;
                stage1_inst  <= fu_if.issue_data;
                // 乘法计算在 Stage 1 完成 (组合逻辑)
                stage1_result <= mul_result;
            end else begin
                stage1_valid <= 1'b0;
            end
        end
    end

    // ========================================================================
    // 乘法器计算逻辑 (组合逻辑)
    // ========================================================================
    logic [63:0] mul_result;            // 64-bit 乘法结果
    logic signed   [31:0] mul_a_signed;
    logic signed   [31:0] mul_b_signed;
    logic unsigned [31:0] mul_a_unsigned;
    logic unsigned [31:0] mul_b_unsigned;

    assign mul_a_signed   = signed'(fu_if.issue_data.vj);
    assign mul_b_signed   = signed'(fu_if.issue_data.vk);
    assign mul_a_unsigned = unsigned'(fu_if.issue_data.vj);
    assign mul_b_unsigned = unsigned'(fu_if.issue_data.vk);

    always_comb begin
        mul_result = 64'b0;

        if (fu_if.issue_valid) begin
            // 根据 funct3 选择乘法类型
            unique case (fu_if.issue_data.funct3)
                // ============================================================
                // MUL/MULH: 有符号 × 有符号
                // ============================================================
                3'b000, 3'b001: begin
                    mul_result = mul_a_signed * mul_b_signed;
                end

                // ============================================================
                // MULHSU: 有符号 × 无符号
                // ============================================================
                3'b010: begin
                    mul_result = mul_a_signed * $signed({1'b0, mul_b_unsigned});
                end

                // ============================================================
                // MULHU: 无符号 × 无符号
                // ============================================================
                3'b011: begin
                    mul_result = mul_a_unsigned * mul_b_unsigned;
                end

                default: mul_result = 64'bx;
            endcase
        end
    end

    // ========================================================================
    // Complete 阶段：输出结果到 CDB
    // ========================================================================
    assign fu_if.complete_valid = stage3_valid;

    always_comb begin
        fu_if.complete_data = '0;

        if (stage3_valid) begin
            // ----------------------------------------------------------------
            // 选择输出结果：低 32 位或高 32 位
            // ----------------------------------------------------------------
            logic [31:0] result_32;

            if (stage3_inst.funct3 == 3'b000) begin
                // MUL: 返回低 32 位
                result_32 = stage3_result[31:0];
            end else begin
                // MULH/MULHSU/MULHU: 返回高 32 位
                result_32 = stage3_result[63:32];
            end

            // ----------------------------------------------------------------
            // 填充 CDB 数据
            // ----------------------------------------------------------------
            fu_if.complete_data.valid     = 1'b1;
            fu_if.complete_data.rd        = stage3_inst.fi;
            fu_if.complete_data.data      = result_32;
            fu_if.complete_data.pc        = stage3_inst.pc;
            fu_if.complete_data.inst      = stage3_inst.inst;
            fu_if.complete_data.order     = stage3_inst.order;

            // RVFI 验证信号
            fu_if.complete_data.rs1_addr  = stage3_inst.fj;
            fu_if.complete_data.rs2_addr  = stage3_inst.fk;
            fu_if.complete_data.rs1_rdata = stage3_inst.vj;
            fu_if.complete_data.rs2_rdata = stage3_inst.vk;
            fu_if.complete_data.pc_wdata  = stage3_inst.pc + 4;

            // 乘法器不访问内存
            fu_if.complete_data.mem_addr  = '0;
            fu_if.complete_data.mem_rmask = '0;
            fu_if.complete_data.mem_wmask = '0;
            fu_if.complete_data.mem_rdata = '0;
            fu_if.complete_data.mem_wdata = '0;
        end
    end

endmodule : fu_multiplier
