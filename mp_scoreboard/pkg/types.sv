/**
 * ============================================================================
 * Scoreboard 架构处理器 - 类型定义文件
 * ============================================================================
 * 本文件定义了 Scoreboard 架构所需的所有数据类型和常量
 * 包括：功能单元类型、Scoreboard 状态表、寄存器状态、指令队列、CDB 等
 * ============================================================================
 */

package rv32i_types;

    // ========================================================================
    // RISC-V 基础类型定义
    // ========================================================================

    // RISC-V 操作码枚举
    typedef enum logic [6:0] {
        op_lui   = 7'b0110111,  // 加载立即数到高位 (Load Upper Immediate)
        op_auipc = 7'b0010111,  // 将立即数加到 PC (Add Upper Immediate to PC)
        op_jal   = 7'b1101111,  // 跳转并链接 (Jump and Link)
        op_jalr  = 7'b1100111,  // 间接跳转并链接 (Jump and Link Register)
        op_br    = 7'b1100011,  // 条件分支 (Branch)
        op_load  = 7'b0000011,  // 内存加载 (Load)
        op_store = 7'b0100011,  // 内存存储 (Store)
        op_imm   = 7'b0010011,  // 立即数 ALU 操作 (Immediate ALU)
        op_reg   = 7'b0110011   // 寄存器 ALU 操作 (Register ALU)
    } rv32i_opcode;

    // ALU 操作类型
    typedef enum logic [2:0] {
        alu_add  = 3'b000,  // 加法/减法
        alu_sll  = 3'b001,  // 逻辑左移
        alu_slt  = 3'b010,  // 有符号比较
        alu_sltu = 3'b011,  // 无符号比较
        alu_xor  = 3'b100,  // 异或
        alu_srl  = 3'b101,  // 逻辑右移/算术右移
        alu_or   = 3'b110,  // 或
        alu_and  = 3'b111   // 与
    } alu_ops;

    // 分支操作类型
    typedef enum logic [2:0] {
        beq  = 3'b000,  // 相等分支
        bne  = 3'b001,  // 不等分支
        blt  = 3'b100,  // 小于分支 (有符号)
        bge  = 3'b101,  // 大于等于分支 (有符号)
        bltu = 3'b110,  // 小于分支 (无符号)
        bgeu = 3'b111   // 大于等于分支 (无符号)
    } branch_funct3_t;

    // Load 操作类型
    typedef enum logic [2:0] {
        lb  = 3'b000,  // 加载字节 (有符号扩展)
        lh  = 3'b001,  // 加载半字 (有符号扩展)
        lw  = 3'b010,  // 加载字
        lbu = 3'b100,  // 加载字节 (无符号扩展)
        lhu = 3'b101   // 加载半字 (无符号扩展)
    } load_funct3_t;

    // Store 操作类型
    typedef enum logic [2:0] {
        sb = 3'b000,  // 存储字节
        sh = 3'b001,  // 存储半字
        sw = 3'b010   // 存储字
    } store_funct3_t;

    // 算术/逻辑操作 funct3 (用于 op_imm 和 op_reg)
    typedef enum bit [2:0] {
        add  = 3'b000,  // 加法/减法 (check bit 30 for sub if op_reg opcode)
        sll  = 3'b001,  // 逻辑左移
        slt  = 3'b010,  // 有符号比较
        sltu = 3'b011,  // 无符号比较
        axor = 3'b100,  // 异或
        sr   = 3'b101,  // 右移 (check bit 30 for logical/arithmetic)
        aor  = 3'b110,  // 或
        aand = 3'b111   // 与
    } arith_funct3_t;

    // ========================================================================
    // Scoreboard 架构专用类型定义
    // ========================================================================

    // ------------------------------------------------------------------------
    // 功能单元 (Functional Unit) 类型枚举
    // ------------------------------------------------------------------------
    typedef enum logic [2:0] {
        FU_ALU_INT    = 3'b000,  // 整数 ALU (可实例化多个)
        FU_MUL        = 3'b001,  // 乘法器功能单元
        FU_DIV        = 3'b010,  // 除法器功能单元
        FU_LOAD       = 3'b011,  // Load 功能单元
        FU_STORE      = 3'b100,  // Store 功能单元
        FU_BRANCH     = 3'b101,  // Branch 功能单元
        FU_NONE       = 3'b111   // 未分配功能单元
    } fu_type_t;

    // ------------------------------------------------------------------------
    // 功能单元数量配置
    // 根据性能需求可以调整各类型 FU 的数量
    // ------------------------------------------------------------------------
    localparam int NUM_FU_ALU    = 2;  // 2 个整数 ALU (提高并行度)
    localparam int NUM_FU_MUL    = 1;  // 1 个乘法器 (多周期操作)
    localparam int NUM_FU_DIV    = 1;  // 1 个除法器 (多周期操作)
    localparam int NUM_FU_LS     = 1;  // 1 个 Load/Store 单元
    localparam int NUM_FU_BR     = 1;  // 1 个 Branch 单元
    localparam int TOTAL_FU      = NUM_FU_ALU + NUM_FU_MUL + NUM_FU_DIV +
                                   NUM_FU_LS + NUM_FU_BR;  // 总共 6 个 FU

    // FU ID 位宽 (用于索引功能单元数组)
    localparam int FU_ID_WIDTH = $clog2(TOTAL_FU + 1);  // 至少 3 bits
    typedef logic [FU_ID_WIDTH-1:0] fu_id_t;

    // ------------------------------------------------------------------------
    // Scoreboard 功能单元状态条目
    // 每个功能单元维护一个状态条目，记录当前正在执行的指令信息
    // ------------------------------------------------------------------------
    typedef struct packed {
        // === 功能单元基本状态 ===
        logic           busy;           // FU 是否正在使用 (忙碌标志)
        fu_type_t       fu_type;        // FU 类型 (ALU/MUL/DIV/LS/BR)
        rv32i_opcode    opcode;         // 指令操作码

        // === 寄存器依赖信息 ===
        logic [4:0]     fi;             // 目标寄存器 (destination register)
        logic [4:0]     fj;             // 源寄存器 1 (source register 1)
        logic [4:0]     fk;             // 源寄存器 2 (source register 2)

        // === RAW 依赖追踪 ===
        fu_id_t         qj;             // 生产 Fj 的 FU ID (哪个 FU 会写入 Rs1)
        fu_id_t         qk;             // 生产 Fk 的 FU ID (哪个 FU 会写入 Rs2)
        logic           rj;             // Fj 是否就绪 (Rs1 数据是否可用)
        logic           rk;             // Fk 是否就绪 (Rs2 数据是否可用)

        // === 操作数值 ===
        logic [31:0]    vj;             // Fj 的值 (Rs1 的实际数据)
        logic [31:0]    vk;             // Fk 的值 (Rs2 的实际数据)
        logic [31:0]    imm;            // 立即数 (用于 I/S/B/U/J 型指令)

        // === 指令追踪信息 (用于调试和验证) ===
        logic [31:0]    pc;             // 指令的程序计数器
        logic [31:0]    inst;           // 原始指令编码 (用于 RVFI)
        logic [63:0]    order;          // 指令序号 (用于 RVFI 乱序追踪)
        logic [2:0]     funct3;         // funct3 字段
        logic [6:0]     funct7;         // funct7 字段

        // === 有效位 ===
        logic           valid;          // 该状态条目是否有效
    } fu_status_t;

    // ------------------------------------------------------------------------
    // 寄存器结果状态表 (Register Result Status)
    // 追踪每个寄存器是否有待写入的结果，以及由哪个 FU 产生
    // 用于 WAW 和 RAW 依赖检测
    // ------------------------------------------------------------------------
    typedef struct packed {
        logic           pending;        // 是否有 FU 将要写入此寄存器
        fu_id_t         fu_id;          // 哪个 FU 会写入 (生产者 FU)
    } reg_status_t;

    // ------------------------------------------------------------------------
    // 指令队列条目 (Instruction Queue Entry)
    // 从 Fetch 阶段到 Issue 阶段的缓冲队列
    // ------------------------------------------------------------------------
    typedef struct packed {
        logic [31:0]    inst;           // 指令编码
        logic [31:0]    pc;             // 程序计数器
        logic [63:0]    order;          // 指令序号 (按 Fetch 顺序递增)
        logic           valid;          // 条目是否有效
    } iq_entry_t;

    // 指令队列配置参数
    localparam int IQ_DEPTH = 8;  // 指令队列深度 (可容纳 8 条指令)

    // ------------------------------------------------------------------------
    // Common Data Bus (CDB) 条目
    // 当功能单元完成执行后，通过 CDB 广播结果
    // 所有等待该结果的 FU 和寄存器堆会监听 CDB
    // ------------------------------------------------------------------------
    typedef struct packed {
        // === 写回信息 ===
        logic           valid;          // CDB 上是否有有效数据
        fu_id_t         fu_id;          // 数据来自哪个 FU
        logic [4:0]     rd;             // 目标寄存器
        logic [31:0]    data;           // 写回数据 (ALU 结果、Load 数据等)

        // === 指令追踪信息 ===
        logic [31:0]    pc;             // 指令 PC
        logic [31:0]    inst;           // 指令编码
        logic [63:0]    order;          // 指令序号

        // === RVFI 验证接口信号 ===
        logic [4:0]     rs1_addr;       // 源寄存器 1 地址
        logic [4:0]     rs2_addr;       // 源寄存器 2 地址
        logic [31:0]    rs1_rdata;      // 源寄存器 1 读取数据
        logic [31:0]    rs2_rdata;      // 源寄存器 2 读取数据
        logic [31:0]    pc_wdata;       // 下一条 PC 值

        // === 内存访问信息 (仅用于 Load/Store) ===
        logic [31:0]    mem_addr;       // 内存地址
        logic [3:0]     mem_rmask;      // 内存读掩码
        logic [3:0]     mem_wmask;      // 内存写掩码
        logic [31:0]    mem_rdata;      // 内存读数据
        logic [31:0]    mem_wdata;      // 内存写数据
    } cdb_entry_t;

    // ------------------------------------------------------------------------
    // 指令解码后的立即数类型
    // ------------------------------------------------------------------------
    typedef struct packed {
        logic [31:0]    i_imm;          // I 型立即数
        logic [31:0]    s_imm;          // S 型立即数
        logic [31:0]    b_imm;          // B 型立即数
        logic [31:0]    u_imm;          // U 型立即数
        logic [31:0]    j_imm;          // J 型立即数
    } imm_t;

    // ------------------------------------------------------------------------
    // 功能单元执行延迟配置
    // 用于模拟真实硬件中不同操作的执行时间
    // ------------------------------------------------------------------------
    localparam int LATENCY_ALU   = 1;   // ALU 单周期
    localparam int LATENCY_MUL   = 3;   // 乘法器 3 周期
    localparam int LATENCY_DIV   = 10;  // 除法器 10 周期
    localparam int LATENCY_LOAD  = 1;   // Load (cache hit 假设 1 周期)
    localparam int LATENCY_STORE = 1;   // Store 1 周期
    localparam int LATENCY_BR    = 1;   // Branch 1 周期

endpackage : rv32i_types
