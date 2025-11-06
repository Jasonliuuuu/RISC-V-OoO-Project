/**
 * ============================================================================
 * ALU 功能单元 (ALU Functional Unit)
 * ============================================================================
 * 功能：
 * - 执行 RISC-V 整数算术和逻辑运算
 * - 支持 R 型指令 (op_reg) 和 I 型立即数指令 (op_imm)
 * - 单周期执行延迟 (LATENCY_ALU = 1)
 * - 可实例化多个 ALU 以提高指令级并行度
 *
 * 支持的操作：
 * - 加法/减法 (ADD/SUB/ADDI)
 * - 逻辑运算 (AND/OR/XOR/ANDI/ORI/XORI)
 * - 移位 (SLL/SRL/SRA/SLLI/SRLI/SRAI)
 * - 比较 (SLT/SLTU/SLTI/SLTIU)
 * ============================================================================
 */

module fu_alu
    import rv32i_types::*;
    (
        input  logic        clk,        // 时钟信号
        input  logic        rst,        // 复位信号
        fu_interface.fu     fu_if       // FU 接口 (使用 fu modport)
    );

    // ========================================================================
    // 内部流水线寄存器
    // ========================================================================
    fu_status_t     current_inst;       // 当前正在执行的指令信息
    logic           valid;              // 当前指令是否有效

    // ========================================================================
    // Ready 信号：ALU 单周期，只要不忙就准备好
    // ========================================================================
    assign fu_if.issue_ready = !valid;

    // ========================================================================
    // 指令接收和流水线控制
    // ========================================================================
    always_ff @(posedge clk) begin
        if (rst || fu_if.flush) begin
            // ----------------------------------------------------------------
            // 复位或 Flush：清空流水线
            // ----------------------------------------------------------------
            valid <= 1'b0;
            current_inst <= '0;

        end else if (fu_if.issue_valid && fu_if.issue_ready) begin
            // ----------------------------------------------------------------
            // Issue：接收新指令
            // ----------------------------------------------------------------
            valid <= 1'b1;
            current_inst <= fu_if.issue_data;

        end else if (valid) begin
            // ----------------------------------------------------------------
            // Complete：单周期后完成
            // ----------------------------------------------------------------
            valid <= 1'b0;  // 下个周期释放 FU
        end
    end

    // ========================================================================
    // 忙碌信号
    // ========================================================================
    assign fu_if.exec_busy = valid;

    // ========================================================================
    // ALU 计算逻辑 (组合逻辑)
    // ========================================================================
    logic [31:0] alu_result;            // ALU 计算结果
    logic [31:0] operand_a, operand_b;  // 操作数

    // 操作数 A：根据指令类型选择
    // - AUIPC/JAL/JALR: 使用 PC
    // - 其他: 使用 Rs1 (Vj)
    assign operand_a = (current_inst.opcode == op_auipc ||
                        current_inst.opcode == op_jal ||
                        current_inst.opcode == op_jalr) ?
                       current_inst.pc : current_inst.vj;

    // 操作数 B：根据指令类型选择
    // - R 型 (op_reg): 使用 Rs2 (Vk)
    // - I 型 (op_imm): 使用立即数 (imm)
    // - JAL/JALR: 使用 4 (link address offset)
    // - 其他: 使用立即数
    always_comb begin
        if (current_inst.opcode == op_jal || current_inst.opcode == op_jalr) begin
            operand_b = 32'd4;
        end else if (current_inst.opcode == op_reg) begin
            operand_b = current_inst.vk;
        end else begin
            operand_b = current_inst.imm;
        end
    end

    // ------------------------------------------------------------------------
    // ALU 操作执行
    // 根据 funct3 和 funct7 确定具体操作
    // ------------------------------------------------------------------------
    logic signed   [31:0] as, bs;       // 有符号操作数
    logic unsigned [31:0] au, bu;       // 无符号操作数

    assign as = signed'(operand_a);
    assign bs = signed'(operand_b);
    assign au = unsigned'(operand_a);
    assign bu = unsigned'(operand_b);

    always_comb begin
        alu_result = 32'b0;  // 默认值

        if (valid) begin
            // 根据 funct3 选择操作
            unique case (current_inst.funct3)
                // ============================================================
                // ADD/SUB (funct3 = 000)
                // ============================================================
                3'b000: begin
                    if (current_inst.opcode == op_reg && current_inst.funct7[5]) begin
                        // SUB: funct7[5] = 1
                        alu_result = au - bu;
                    end else begin
                        // ADD/ADDI: funct7[5] = 0 或 I-type
                        alu_result = au + bu;
                    end
                end

                // ============================================================
                // SLL/SLLI - 逻辑左移 (funct3 = 001)
                // ============================================================
                3'b001: begin
                    alu_result = au << bu[4:0];  // 只使用低 5 位作为移位量
                end

                // ============================================================
                // SLT/SLTI - 有符号比较 (funct3 = 010)
                // ============================================================
                3'b010: begin
                    alu_result = (as < bs) ? 32'd1 : 32'd0;
                end

                // ============================================================
                // SLTU/SLTIU - 无符号比较 (funct3 = 011)
                // ============================================================
                3'b011: begin
                    alu_result = (au < bu) ? 32'd1 : 32'd0;
                end

                // ============================================================
                // XOR/XORI - 异或 (funct3 = 100)
                // ============================================================
                3'b100: begin
                    alu_result = au ^ bu;
                end

                // ============================================================
                // SRL/SRLI/SRA/SRAI - 右移 (funct3 = 101)
                // ============================================================
                3'b101: begin
                    if (current_inst.funct7[5]) begin
                        // SRA/SRAI: 算术右移 (保留符号位)
                        alu_result = unsigned'(as >>> bu[4:0]);
                    end else begin
                        // SRL/SRLI: 逻辑右移 (填充 0)
                        alu_result = au >> bu[4:0];
                    end
                end

                // ============================================================
                // OR/ORI - 或 (funct3 = 110)
                // ============================================================
                3'b110: begin
                    alu_result = au | bu;
                end

                // ============================================================
                // AND/ANDI - 与 (funct3 = 111)
                // ============================================================
                3'b111: begin
                    alu_result = au & bu;
                end

                default: alu_result = 32'bx;  // 非法操作
            endcase
        end
    end

    // ========================================================================
    // Complete 阶段：输出结果到 CDB
    // ========================================================================
    assign fu_if.complete_valid = valid;

    always_comb begin
        // 默认清空输出
        fu_if.complete_data = '0;

        if (valid) begin
            // DEBUG: Trace LUI instruction completion
            if (current_inst.opcode == op_lui) begin
                $display("[DEBUG ALU] @%0t LUI Complete: inst=%h, opcode=%b, fj=%0d, fk=%0d, vj=%h, imm=%h, operand_a=%h, operand_b=%h, alu_result=%h",
                         $time, current_inst.inst, current_inst.opcode, current_inst.fj, current_inst.fk,
                         current_inst.vj, current_inst.imm, operand_a, operand_b, alu_result);
            end

            // ----------------------------------------------------------------
            // 填充 CDB 数据
            // ----------------------------------------------------------------
            fu_if.complete_data.valid     = 1'b1;
            fu_if.complete_data.rd        = current_inst.fi;
            fu_if.complete_data.data      = alu_result;
            fu_if.complete_data.pc        = current_inst.pc;
            fu_if.complete_data.inst      = current_inst.inst;
            fu_if.complete_data.order     = current_inst.order;

            // RVFI 验证信号
            fu_if.complete_data.rs1_addr  = current_inst.fj;
            fu_if.complete_data.rs2_addr  = current_inst.fk;
            fu_if.complete_data.rs1_rdata = current_inst.vj;
            fu_if.complete_data.rs2_rdata = current_inst.vk;

            // pc_wdata 根据指令类型计算
            // JAL: PC + imm
            // JALR: (Rs1 + imm) & ~1
            // 其他: PC + 4
            if (current_inst.opcode == op_jal) begin
                fu_if.complete_data.pc_wdata = current_inst.pc + current_inst.imm;
            end else if (current_inst.opcode == op_jalr) begin
                fu_if.complete_data.pc_wdata = (current_inst.vj + current_inst.imm) & ~32'b1;
            end else begin
                fu_if.complete_data.pc_wdata = current_inst.pc + 4;
            end

            // ALU 不访问内存
            fu_if.complete_data.mem_addr  = '0;
            fu_if.complete_data.mem_rmask = '0;
            fu_if.complete_data.mem_wmask = '0;
            fu_if.complete_data.mem_rdata = '0;
            fu_if.complete_data.mem_wdata = '0;
        end
    end

endmodule : fu_alu
