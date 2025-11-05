/**
 * ============================================================================
 * Load/Store 功能单元 (Load/Store Functional Unit)
 * ============================================================================
 * 功能：
 * - 执行 RISC-V Load 和 Store 指令
 * - 计算内存访问地址
 * - 与数据内存接口交互
 * - 处理字节/半字/字访问和对齐
 *
 * Load 指令 (opcode = op_load):
 * - LB/LBU: 加载字节
 * - LH/LHU: 加载半字
 * - LW: 加载字
 *
 * Store 指令 (opcode = op_store):
 * - SB: 存储字节
 * - SH: 存储半字
 * - SW: 存储字
 * ============================================================================
 */

module fu_load_store
    import rv32i_types::*;
    (
        input  logic        clk,
        input  logic        rst,
        fu_interface.fu     fu_if,

        // ====================================================================
        // 数据内存接口
        // ====================================================================
        output logic [31:0] dmem_addr,      // 内存地址
        output logic [3:0]  dmem_rmask,     // 读掩码
        output logic [3:0]  dmem_wmask,     // 写掩码
        input  logic [31:0] dmem_rdata,     // 读数据
        output logic [31:0] dmem_wdata,     // 写数据
        input  logic        dmem_resp       // 内存响应
    );

    // ========================================================================
    // 内部状态
    // ========================================================================
    typedef enum logic [1:0] {
        IDLE,           // 空闲状态
        ADDR_CALC,      // 地址计算 (单周期)
        MEM_ACCESS      // 等待内存响应
    } state_t;

    state_t         state, next_state;
    fu_status_t     current_inst;
    logic           valid;
    logic [31:0]    mem_address;        // 计算出的内存地址
    logic [31:0]    load_result;        // Load 指令的结果

    assign fu_if.issue_ready = (state == IDLE);
    assign fu_if.exec_busy = (state != IDLE);

    // ========================================================================
    // 状态机控制
    // ========================================================================
    always_ff @(posedge clk) begin
        if (rst || fu_if.flush) begin
            state <= IDLE;
            valid <= 1'b0;
            current_inst <= '0;
        end else begin
            state <= next_state;

            if (fu_if.issue_valid && fu_if.issue_ready) begin
                valid <= 1'b1;
                current_inst <= fu_if.issue_data;
            end else if (state == MEM_ACCESS && dmem_resp) begin
                valid <= 1'b0;  // 完成
            end
        end
    end

    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (fu_if.issue_valid) begin
                    next_state = ADDR_CALC;
                end
            end

            ADDR_CALC: begin
                next_state = MEM_ACCESS;
            end

            MEM_ACCESS: begin
                if (dmem_resp) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // ========================================================================
    // 地址计算: addr = Rs1 + imm (S-type 或 I-type)
    // ========================================================================
    always_comb begin
        if (current_inst.opcode == op_store) begin
            // Store: 使用 S-type immediate
            mem_address = current_inst.vj + current_inst.imm;
        end else begin
            // Load: 使用 I-type immediate
            mem_address = current_inst.vj + current_inst.imm;
        end
    end

    // ========================================================================
    // 内存访问控制
    // ========================================================================
    always_comb begin
        dmem_addr  = mem_address & 32'hFFFFFFFC;  // 4 字节对齐
        dmem_rmask = 4'b0000;
        dmem_wmask = 4'b0000;
        dmem_wdata = 32'b0;

        if (state == MEM_ACCESS) begin
            if (current_inst.opcode == op_load) begin
                // ============================================================
                // Load 指令：生成读掩码
                // ============================================================
                case (current_inst.funct3)
                    3'b000, 3'b100: begin  // LB/LBU: 字节
                        dmem_rmask = 4'b0001 << mem_address[1:0];
                    end
                    3'b001, 3'b101: begin  // LH/LHU: 半字
                        dmem_rmask = 4'b0011 << mem_address[1:0];
                    end
                    3'b010: begin          // LW: 字
                        dmem_rmask = 4'b1111;
                    end
                    default: dmem_rmask = 4'b0000;
                endcase

            end else if (current_inst.opcode == op_store) begin
                // ============================================================
                // Store 指令：生成写掩码和写数据
                // ============================================================
                case (current_inst.funct3)
                    3'b000: begin  // SB: 字节
                        dmem_wmask = 4'b0001 << mem_address[1:0];
                        dmem_wdata = current_inst.vk << (mem_address[1:0] * 8);
                    end
                    3'b001: begin  // SH: 半字
                        dmem_wmask = 4'b0011 << mem_address[1:0];
                        dmem_wdata = current_inst.vk << (mem_address[1:0] * 8);
                    end
                    3'b010: begin  // SW: 字
                        dmem_wmask = 4'b1111;
                        dmem_wdata = current_inst.vk;
                    end
                    default: dmem_wmask = 4'b0000;
                endcase
            end
        end
    end

    // ========================================================================
    // Load 数据处理：符号扩展和字节选择
    // ========================================================================
    always_comb begin
        load_result = 32'b0;

        if (current_inst.opcode == op_load && dmem_resp) begin
            logic [31:0] shifted_data;
            shifted_data = dmem_rdata >> (mem_address[1:0] * 8);

            case (current_inst.funct3)
                3'b000: begin  // LB: 有符号字节
                    load_result = {{24{shifted_data[7]}}, shifted_data[7:0]};
                end
                3'b001: begin  // LH: 有符号半字
                    load_result = {{16{shifted_data[15]}}, shifted_data[15:0]};
                end
                3'b010: begin  // LW: 字
                    load_result = shifted_data;
                end
                3'b100: begin  // LBU: 无符号字节
                    load_result = {24'b0, shifted_data[7:0]};
                end
                3'b101: begin  // LHU: 无符号半字
                    load_result = {16'b0, shifted_data[15:0]};
                end
                default: load_result = 32'bx;
            endcase
        end
    end

    // ========================================================================
    // Complete 阶段
    // ========================================================================
    assign fu_if.complete_valid = (state == MEM_ACCESS && dmem_resp);

    always_comb begin
        fu_if.complete_data = '0;

        if (state == MEM_ACCESS && dmem_resp) begin
            fu_if.complete_data.valid     = 1'b1;
            fu_if.complete_data.pc        = current_inst.pc;
            fu_if.complete_data.inst      = current_inst.inst;
            fu_if.complete_data.order     = current_inst.order;
            fu_if.complete_data.rs1_addr  = current_inst.fj;
            fu_if.complete_data.rs2_addr  = current_inst.fk;
            fu_if.complete_data.rs1_rdata = current_inst.vj;
            fu_if.complete_data.rs2_rdata = current_inst.vk;

            if (current_inst.opcode == op_load) begin
                // Load: 写回寄存器
                fu_if.complete_data.rd        = current_inst.fi;
                fu_if.complete_data.data      = load_result;
                fu_if.complete_data.pc_wdata  = current_inst.pc + 4;
                fu_if.complete_data.mem_addr  = mem_address;
                fu_if.complete_data.mem_rmask = dmem_rmask;
                fu_if.complete_data.mem_rdata = dmem_rdata;
            end else begin
                // Store: 不写回寄存器
                fu_if.complete_data.rd        = 5'b0;
                fu_if.complete_data.data      = 32'b0;
                fu_if.complete_data.pc_wdata  = current_inst.pc + 4;
                fu_if.complete_data.mem_addr  = mem_address;
                fu_if.complete_data.mem_wmask = dmem_wmask;
                fu_if.complete_data.mem_wdata = dmem_wdata;
            end
        end
    end

endmodule : fu_load_store
