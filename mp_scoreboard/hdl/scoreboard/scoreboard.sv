/**
 * ============================================================================
 * Scoreboard 主控制逻辑 (Scoreboard Main Control Logic)
 * ============================================================================
 * 功能：
 * - 管理所有功能单元的状态
 * - 检测和解决数据冒险 (RAW, WAW, WAR)
 * - Issue 逻辑：从指令队列取指令并分配到空闲的 FU
 * - Read Operands 逻辑：检查操作数是否就绪
 * - Write Result 逻辑：通过 CDB 更新等待的 FU
 *
 * Scoreboard 表结构：
 * 1. Functional Unit Status Table: 每个 FU 的状态
 * 2. Register Result Status Table: 每个寄存器的生产者 FU
 *
 * 四个阶段：
 * 1. Issue: 分配 FU，检测 WAW
 * 2. Read Operands: 检测 RAW，等待操作数就绪
 * 3. Execution: FU 执行 (在各 FU 模块内部)
 * 4. Write Result: 通过 CDB 广播结果，更新等待的 FU
 * ============================================================================
 */

module scoreboard
    import rv32i_types::*;
    #(
        parameter int NUM_FU = TOTAL_FU
    )
    (
        input  logic        clk,
        input  logic        rst,

        // ====================================================================
        // 指令队列接口
        // ====================================================================
        input  iq_entry_t   iq_data,        // 队首指令
        input  logic        iq_empty,       // 队列为空
        output logic        iq_deq,         // 出队信号

        // ====================================================================
        // 寄存器堆接口 (用于读取操作数)
        // ====================================================================
        output logic [4:0]  rf_rs1_addr,    // Rs1 地址
        output logic [4:0]  rf_rs2_addr,    // Rs2 地址
        input  logic [31:0] rf_rs1_data,    // Rs1 数据
        input  logic [31:0] rf_rs2_data,    // Rs2 数据

        // ====================================================================
        // 功能单元接口 (连接所有 FU)
        // ====================================================================
        fu_interface.scoreboard fu_if [NUM_FU],

        // ====================================================================
        // Common Data Bus (来自 CDB 仲裁器)
        // ====================================================================
        input  cdb_entry_t  cdb_data,       // CDB 数据
        input  logic        cdb_valid,      // CDB 有效

        // ====================================================================
        // Flush 信号 (分支预测错误)
        // ====================================================================
        input  logic        flush,          // 全局 Flush 信号
        output logic        flush_out       // 传播到 FU
    );

    // ========================================================================
    // Scoreboard 表结构
    // ========================================================================
    fu_status_t     fu_status [NUM_FU];     // 功能单元状态表
    reg_status_t    reg_result [32];        // 寄存器结果状态表

    // ========================================================================
    // 中间信号数组 (用于在 always 块中访问接口数组)
    // ========================================================================
    logic fu_issue_ready [NUM_FU];          // FU issue ready 信号
    logic fu_complete_valid [NUM_FU];       // FU complete valid 信号

    // 将 flush 信号传播到所有 FU
    genvar g;
    generate
        for (g = 0; g < NUM_FU; g++) begin : gen_flush
            assign fu_if[g].flush = flush;
            // 连接中间信号
            assign fu_issue_ready[g] = fu_if[g].issue_ready;
            assign fu_complete_valid[g] = fu_if[g].complete_valid;
        end
    endgenerate
    assign flush_out = flush;

    // ========================================================================
    // Issue 逻辑 (组合逻辑)
    // ========================================================================
    logic           can_issue;          // 是否可以 Issue
    fu_id_t         target_fu;          // 目标 FU ID
    logic [4:0]     rs1, rs2, rd;       // 指令的寄存器字段
    rv32i_opcode    opcode;             // 指令操作码
    logic [2:0]     funct3;
    logic [6:0]     funct7;

    // 解码指令字段
    assign opcode = rv32i_opcode'(iq_data.inst[6:0]);
    assign funct3 = iq_data.inst[14:12];
    assign funct7 = iq_data.inst[31:25];
    assign rs1    = iq_data.inst[19:15];
    assign rs2    = iq_data.inst[24:20];
    assign rd     = iq_data.inst[11:7];

    // 立即数解码
    logic [31:0] i_imm, s_imm, b_imm, u_imm, j_imm;
    assign i_imm = {{21{iq_data.inst[31]}}, iq_data.inst[30:20]};
    assign s_imm = {{21{iq_data.inst[31]}}, iq_data.inst[30:25], iq_data.inst[11:7]};
    assign b_imm = {{20{iq_data.inst[31]}}, iq_data.inst[7], iq_data.inst[30:25], iq_data.inst[11:8], 1'b0};
    assign u_imm = {iq_data.inst[31:12], 12'b0};
    assign j_imm = {{12{iq_data.inst[31]}}, iq_data.inst[19:12], iq_data.inst[20], iq_data.inst[30:21], 1'b0};

    // ========================================================================
    // 根据指令类型确定需要的 FU 类型
    // ========================================================================
    fu_type_t required_fu_type;

    always_comb begin
        required_fu_type = FU_ALU_INT;  // 默认

        case (opcode)
            op_reg, op_imm: begin
                // 检查是否是 M 扩展指令 (乘法/除法)
                if (funct7 == 7'b0000001) begin
                    // M extension
                    if (funct3[2]) begin
                        required_fu_type = FU_DIV;   // DIV/DIVU/REM/REMU
                    end else begin
                        required_fu_type = FU_MUL;   // MUL/MULH/MULHSU/MULHU
                    end
                end else begin
                    required_fu_type = FU_ALU_INT;
                end
            end

            op_load:  required_fu_type = FU_LOAD;
            op_store: required_fu_type = FU_STORE;
            op_br:    required_fu_type = FU_BRANCH;

            // JAL/JALR/LUI/AUIPC 也使用 ALU
            default:  required_fu_type = FU_ALU_INT;
        endcase
    end

    // ========================================================================
    // 寻找空闲的对应类型 FU
    // ========================================================================
    always_comb begin
        can_issue = 1'b0;
        target_fu = '0;

        if (!iq_empty) begin
            // 遍历所有 FU，找到空闲的目标类型 FU
            for (int i = 0; i < NUM_FU; i++) begin
                if (fu_status[i].fu_type == required_fu_type &&
                    !fu_status[i].busy &&
                    fu_issue_ready[i]) begin

                    // 检查 WAW 冒险：目标寄存器是否有待写入
                    if (rd == 0 || !reg_result[rd].pending) begin
                        can_issue = 1'b1;
                        target_fu = fu_id_t'(i);
                        break;  // 找到第一个满足条件的 FU
                    end
                end
            end
        end
    end

    // Issue 出队信号
    assign iq_deq = can_issue;

    // ========================================================================
    // RAW 冒险检查与操作数准备
    // ========================================================================
    logic [31:0]    operand_j, operand_k;   // 操作数值
    logic           ready_j, ready_k;       // 操作数是否就绪
    fu_id_t         producer_j, producer_k; // 操作数生产者 FU

    // 寄存器堆读地址
    assign rf_rs1_addr = rs1;
    assign rf_rs2_addr = rs2;

    // Rs1 (Fj) 依赖检查
    always_comb begin
        if (rs1 == 0) begin
            // x0 寄存器始终为 0
            ready_j = 1'b1;
            operand_j = 32'b0;
            producer_j = '0;
        end else if (reg_result[rs1].pending) begin
            // RAW 冒险：Rs1 有待写入的结果
            ready_j = 1'b0;
            operand_j = 32'b0;
            producer_j = reg_result[rs1].fu_id;
        end else begin
            // 从寄存器堆读取
            ready_j = 1'b1;
            operand_j = rf_rs1_data;
            producer_j = '0;
        end
    end

    // Rs2 (Fk) 依赖检查
    always_comb begin
        if (rs2 == 0) begin
            ready_k = 1'b1;
            operand_k = 32'b0;
            producer_k = '0;
        end else if (reg_result[rs2].pending) begin
            ready_k = 1'b0;
            operand_k = 32'b0;
            producer_k = reg_result[rs2].fu_id;
        end else begin
            ready_k = 1'b1;
            operand_k = rf_rs2_data;
            producer_k = '0;
        end
    end

    // ========================================================================
    // Issue 到目标 FU (时序逻辑)
    // ========================================================================
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            // ----------------------------------------------------------------
            // 复位或 Flush：清空所有表
            // ----------------------------------------------------------------
            for (int i = 0; i < NUM_FU; i++) begin
                fu_status[i] <= '0;
                // 设置 FU 类型 (静态配置)
                if (i < NUM_FU_ALU) begin
                    fu_status[i].fu_type <= FU_ALU_INT;
                end else if (i < NUM_FU_ALU + NUM_FU_MUL) begin
                    fu_status[i].fu_type <= FU_MUL;
                end else if (i < NUM_FU_ALU + NUM_FU_MUL + NUM_FU_DIV) begin
                    fu_status[i].fu_type <= FU_DIV;
                end else if (i < NUM_FU_ALU + NUM_FU_MUL + NUM_FU_DIV + NUM_FU_LS) begin
                    fu_status[i].fu_type <= FU_LOAD;  // Load/Store 共用
                end else begin
                    fu_status[i].fu_type <= FU_BRANCH;
                end
            end

            for (int i = 0; i < 32; i++) begin
                reg_result[i] <= '0;
            end

        end else begin
            // ----------------------------------------------------------------
            // Issue 阶段：分配指令到 FU
            // ----------------------------------------------------------------
            if (can_issue) begin
                fu_status[target_fu].busy   <= 1'b1;
                fu_status[target_fu].opcode <= opcode;
                fu_status[target_fu].fi     <= rd;
                fu_status[target_fu].fj     <= rs1;
                fu_status[target_fu].fk     <= rs2;
                fu_status[target_fu].qj     <= producer_j;
                fu_status[target_fu].qk     <= producer_k;
                fu_status[target_fu].rj     <= ready_j;
                fu_status[target_fu].rk     <= ready_k;
                fu_status[target_fu].vj     <= operand_j;
                fu_status[target_fu].vk     <= operand_k;
                fu_status[target_fu].pc     <= iq_data.pc;
                fu_status[target_fu].inst   <= iq_data.inst;
                fu_status[target_fu].order  <= iq_data.order;
                fu_status[target_fu].funct3 <= funct3;
                fu_status[target_fu].funct7 <= funct7;
                fu_status[target_fu].valid  <= 1'b1;

                // 立即数选择
                case (opcode)
                    op_imm, op_load, op_jalr: fu_status[target_fu].imm <= i_imm;
                    op_store:                 fu_status[target_fu].imm <= s_imm;
                    op_br:                    fu_status[target_fu].imm <= b_imm;
                    op_lui, op_auipc:         fu_status[target_fu].imm <= u_imm;
                    op_jal:                   fu_status[target_fu].imm <= j_imm;
                    default:                  fu_status[target_fu].imm <= 32'b0;
                endcase

                // 更新寄存器结果状态表
                if (rd != 0) begin
                    reg_result[rd].pending <= 1'b1;
                    reg_result[rd].fu_id   <= target_fu;
                end
            end

            // ----------------------------------------------------------------
            // CDB Broadcast: 更新等待该结果的 FU
            // ----------------------------------------------------------------
            if (cdb_valid) begin
                // 清除寄存器结果状态
                if (cdb_data.rd != 0 && reg_result[cdb_data.rd].pending &&
                    reg_result[cdb_data.rd].fu_id == cdb_data.fu_id) begin
                    reg_result[cdb_data.rd].pending <= 1'b0;
                end

                // 更新所有等待此结果的 FU
                for (int i = 0; i < NUM_FU; i++) begin
                    if (fu_status[i].busy) begin
                        // 检查 Fj
                        if (!fu_status[i].rj && fu_status[i].qj == cdb_data.fu_id) begin
                            fu_status[i].rj <= 1'b1;
                            fu_status[i].vj <= cdb_data.data;
                        end

                        // 检查 Fk
                        if (!fu_status[i].rk && fu_status[i].qk == cdb_data.fu_id) begin
                            fu_status[i].rk <= 1'b1;
                            fu_status[i].vk <= cdb_data.data;
                        end
                    end
                end
            end

            // ----------------------------------------------------------------
            // 清除已完成的 FU
            // ----------------------------------------------------------------
            for (int i = 0; i < NUM_FU; i++) begin
                if (fu_complete_valid[i]) begin
                    fu_status[i].busy  <= 1'b0;
                    fu_status[i].valid <= 1'b0;
                end
            end
        end
    end

    // ========================================================================
    // Issue 信号到 FU 接口 (组合逻辑)
    // ========================================================================
    generate
        for (g = 0; g < NUM_FU; g++) begin : gen_issue
            always_comb begin
                fu_if[g].issue_valid = (can_issue && target_fu == g);

                if (can_issue && target_fu == g) begin
                    fu_if[g].issue_data = fu_status[target_fu];
                    // 更新即将发射的数据
                    fu_if[g].issue_data.busy   = 1'b1;
                    fu_if[g].issue_data.opcode = opcode;
                    fu_if[g].issue_data.fi     = rd;
                    fu_if[g].issue_data.fj     = rs1;
                    fu_if[g].issue_data.fk     = rs2;
                    fu_if[g].issue_data.qj     = producer_j;
                    fu_if[g].issue_data.qk     = producer_k;
                    fu_if[g].issue_data.rj     = ready_j;
                    fu_if[g].issue_data.rk     = ready_k;
                    fu_if[g].issue_data.vj     = operand_j;
                    fu_if[g].issue_data.vk     = operand_k;
                    fu_if[g].issue_data.pc     = iq_data.pc;
                    fu_if[g].issue_data.inst   = iq_data.inst;
                    fu_if[g].issue_data.order  = iq_data.order;
                    fu_if[g].issue_data.funct3 = funct3;
                    fu_if[g].issue_data.funct7 = funct7;
                end else begin
                    fu_if[g].issue_data = '0;
                end
            end
        end
    endgenerate

endmodule : scoreboard
