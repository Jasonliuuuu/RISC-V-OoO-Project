/**
 * ============================================================================
 * 功能单元接口 (Functional Unit Interface)
 * ============================================================================
 * 功能：
 * - 定义 Scoreboard 与各功能单元之间的标准接口
 * - 使用 SystemVerilog interface 提高模块化和可重用性
 * - 支持三个阶段：Issue、Execute、Complete
 *
 * 接口信号：
 * - Issue 阶段: Scoreboard 向 FU 发射新指令
 * - Execute 阶段: FU 执行指令
 * - Complete 阶段: FU 完成执行，向 CDB 发送结果
 * ============================================================================
 */

interface fu_interface
    import rv32i_types::*;
    ();

    // ========================================================================
    // Issue 阶段信号 (Scoreboard → FU)
    // ========================================================================
    logic           issue_valid;        // Scoreboard 发射新指令到 FU
    fu_status_t     issue_data;         // 发射的指令完整信息
    logic           issue_ready;        // FU 准备好接受新指令 (FU → Scoreboard)

    // ========================================================================
    // Execute 阶段信号 (FU 内部状态)
    // ========================================================================
    logic           exec_busy;          // FU 正在执行指令 (忙碌状态)

    // ========================================================================
    // Complete 阶段信号 (FU → Scoreboard/CDB)
    // ========================================================================
    logic           complete_valid;     // FU 完成执行，结果有效
    cdb_entry_t     complete_data;      // 完成的结果数据 (将广播到 CDB)

    // ========================================================================
    // 控制信号
    // ========================================================================
    logic           flush;              // 全局 Flush 信号 (分支预测错误)

    // ========================================================================
    // Modport 定义 (定义不同模块的视角)
    // ========================================================================

    // === FU 侧视角 (功能单元使用) ===
    modport fu (
        // FU 输入信号
        input  issue_valid,             // 接收 Issue 请求
        input  issue_data,              // 接收指令数据
        input  flush,                   // 接收 Flush 信号

        // FU 输出信号
        output issue_ready,             // 报告准备状态
        output exec_busy,               // 报告忙碌状态
        output complete_valid,          // 报告完成状态
        output complete_data            // 输出结果
    );

    // === Scoreboard 侧视角 (Scoreboard 控制器使用) ===
    modport scoreboard (
        // Scoreboard 输出信号
        output issue_valid,             // 发射指令
        output issue_data,              // 提供指令数据
        output flush,                   // 发起 Flush

        // Scoreboard 输入信号
        input  issue_ready,             // 监测 FU 准备状态
        input  exec_busy,               // 监测 FU 忙碌状态
        input  complete_valid,          // 接收完成通知
        input  complete_data            // 接收结果数据
    );

endinterface : fu_interface
