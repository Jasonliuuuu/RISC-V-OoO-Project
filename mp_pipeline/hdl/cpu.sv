module cpu
    import rv32i_types::*;
    import forward_amux::*;
    import forward_bmux::*;
    import regfilemux::*;
(
    input   logic           clk,
    input   logic           rst,

    // IMEM
    output  logic   [31:0]  imem_addr,
    output  logic   [3:0]   imem_rmask,
    input   logic   [31:0]  imem_rdata,
    input   logic           imem_resp,

    // DMEM
    output  logic   [31:0]  dmem_addr,
    output  logic   [3:0]   dmem_rmask,
    output  logic   [3:0]   dmem_wmask,
    input   logic   [31:0]  dmem_rdata,
    output  logic   [31:0]  dmem_wdata,
    input   logic           dmem_resp
);

    // ============================================================
    // Pipeline registers
    // ============================================================
    if_id_stage_reg_t  if_id_reg_before, if_id_reg;
    id_ex_stage_reg_t  id_ex_reg_before, id_ex_reg;
    ex_mem_stage_reg_t ex_mem_reg_before, ex_mem_reg;
    mem_wb_stage_reg_t mem_wb_reg_before, mem_wb_reg;

    logic stall_signal, freeze_stall, flushing_inst;

    logic [31:0] imem_rdata_id;
    logic        imem_resp_id;

    // Forwarding
    forward_a_sel_t forward_a_sel;
    forward_b_sel_t forward_b_sel;

    logic [31:0] regfilemux_out;
    logic [4:0]  rd_s_back;
    logic        regf_we_back;

    logic br_en_out;
    logic [31:0] branch_pc;

    // Forwarding signals from memory stage
    logic        mem_wb_br_en_forward;
    logic [31:0] mem_wb_alu_out_forward;
    logic [31:0] mem_wb_u_imm_forward;


    // ============================================================
    // Rename + PRF wires
    // ============================================================
    logic [5:0] rs1_phys_decode;
    logic [5:0] rs2_phys_decode;
    logic [5:0] dest_phys_new_decode;
    logic [5:0] dest_phys_old_decode;

    logic [31:0] rs1_val_prf;
    logic [31:0] rs2_val_prf;

    logic       commit_we;
    logic [4:0] commit_arch;
    logic [5:0] commit_phys;
    logic [5:0] commit_old_phys;

    logic       free_en;
    logic [5:0] free_phys;

    // ============================================================
    // Free list
    // ============================================================
    logic [5:0] alloc_phys;
    logic       alloc_valid;

    free_list free_list_i(
        .clk(clk),
        .rst(rst),
        .alloc_phys(alloc_phys),
        .alloc_valid(alloc_valid),
        .free_en(free_en),
        .free_phys(free_phys)
    );

    // ============================================================
    // PRF
    // ============================================================
    prf prf_i(
        .clk(clk),
        .rst(rst),
        .rs1_phys(rs1_phys_decode),
        .rs2_phys(rs2_phys_decode),
        .rs1_val(rs1_val_prf),
        .rs2_val(rs2_val_prf),
        .we      (commit_we),
        .rd_phys (commit_phys),
        .rd_val  (regfilemux_out)
    );

    // ============================================================
    // Rename Unit (Option A)
    // ============================================================
    rename_unit RU (
        .clk(clk),
        .rst(rst),

        .rs1_arch (imem_rdata_id[19:15]),
        .rs2_arch (imem_rdata_id[24:20]),
        .rd_arch  (imem_rdata_id[11:7]),

        .alloc_valid (alloc_valid),
        .alloc_phys  (alloc_phys),

        .commit_we       (commit_we),
        .commit_arch     (commit_arch),
        .commit_phys     (commit_phys),
        .commit_old_phys (commit_old_phys),

        .rs1_phys (rs1_phys_decode),
        .rs2_phys (rs2_phys_decode),
        .new_phys (dest_phys_new_decode),
        .old_phys (dest_phys_old_decode),
        .rename_we(),

        .free_en  (free_en),
        .free_phys(free_phys)
    );

    // ============================================================
    // Fetch
    // ============================================================
    fetch fetch_i(
        .clk(clk),
        .rst(rst),
        .br_en(br_en_out),
        .branch_pc(branch_pc),
        .imem_rdata(imem_rdata),
        .imem_resp(imem_resp),
        .stall_signal(stall_signal),
        .freeze_stall(freeze_stall),
        .flushing_inst(flushing_inst),
        .imem_addr(imem_addr),
        .imem_rmask(imem_rmask),
        .if_id_reg_before(if_id_reg_before),
        .imem_rdata_id(imem_rdata_id),
        .imem_resp_id(imem_resp_id)
    );

    // ============================================================
    // Decode
    // ============================================================
    decode decode_i(
        .clk(clk),
        .rst(rst),
        .imem_rdata_id(imem_rdata_id),
        .imem_resp_id(imem_resp_id),
        .stall_signal(stall_signal),
        .freeze_stall(freeze_stall),
        .flushing_inst(flushing_inst),

        .rs1_phys(rs1_phys_decode),
        .rs2_phys(rs2_phys_decode),
        .dest_phys_new(dest_phys_new_decode),
        .dest_phys_old(dest_phys_old_decode),
        .rs1_val(rs1_val_prf),
        .rs2_val(rs2_val_prf),

        .if_id(if_id_reg),
        .id_ex(id_ex_reg_before)
    );

    // ============================================================
    // Execute
    // ============================================================
    execute execute_i(
        .id_ex(id_ex_reg),
        .ex_mem(ex_mem_reg_before),
        .regfilemux_out_forward(regfilemux_out),
        .ex_mem_br_en_forward(mem_wb_br_en_forward),
        .ex_mem_alu_out_forward(mem_wb_alu_out_forward),
        .ex_mem_u_imm_forward(mem_wb_u_imm_forward),
        .forward_a_sel(forward_a_sel),
        .forward_b_sel(forward_b_sel),
        .flushing_inst(flushing_inst)
    );

    // ============================================================
    // Memory
    // ============================================================
    memory memory_i(
        .ex_mem(ex_mem_reg),
        .mem_wb(mem_wb_reg_before),
        .mem_wb_now(mem_wb_reg),
        .dmem_addr(dmem_addr),
        .dmem_rmask(dmem_rmask),
        .dmem_wmask(dmem_wmask),
        .dmem_wdata(dmem_wdata),
        .mem_wb_br_en(mem_wb_br_en_forward),
        .mem_wb_alu_out(mem_wb_alu_out_forward),
        .mem_wb_u_imm(mem_wb_u_imm_forward),
        .br_en_out(br_en_out),
        .branch_new_address(branch_pc),
        .flushing_inst(flushing_inst),
        .freeze_stall(freeze_stall)
    );

    // ============================================================
    // Writeback + RVFI
    // ============================================================
    writeback writeback(
        .clk(clk),
        .rst(rst),
        .mem_wb(mem_wb_reg),
        .dmem_rdata(dmem_rdata),
        .dmem_resp(dmem_resp),
        .freeze_stall(freeze_stall),
        .regfilemux_out(regfilemux_out),
        .rd_s_back(rd_s_back),
        .regf_we_back(regf_we_back),

        .rvfi_valid(rvfi_valid),
        .rvfi_order(rvfi_order),
        .rvfi_inst(rvfi_inst),
        .rvfi_rs1_addr(rvfi_rs1_addr),
        .rvfi_rs2_addr(rvfi_rs2_addr),
        .rvfi_rs1_rdata(rvfi_rs1_rdata),
        .rvfi_rs2_rdata(rvfi_rs2_rdata),
        .rvfi_rd_addr(rvfi_rd_addr),
        .rvfi_rd_wdata(rvfi_rd_wdata),
        .rvfi_pc_rdata(rvfi_pc_rdata),
        .rvfi_pc_wdata(rvfi_pc_wdata),
        .rvfi_dmem_addr(rvfi_dmem_addr),
        .rvfi_dmem_rmask(rvfi_dmem_rmask),
        .rvfi_dmem_wmask(rvfi_dmem_wmask),
        .rvfi_dmem_rdata(rvfi_dmem_rdata),
        .rvfi_dmem_wdata(rvfi_dmem_wdata)
    );

    // ============================================================
    // Commit → rename + free_list
    // ============================================================
    assign commit_we =
        (regf_we_back == 1'b1) &&
        (mem_wb_reg.valid == 1'b1) &&
        (~freeze_stall);

    assign commit_arch     = mem_wb_reg.dest_arch;
    assign commit_phys     = mem_wb_reg.dest_phys_new;
    assign commit_old_phys = mem_wb_reg.dest_phys_old;

    // ============================================================
    // Hazard Units
    // ============================================================
    forward forward_i(
        .id_ex(id_ex_reg),
        .ex_mem(ex_mem_reg),
        .mem_wb(mem_wb_reg),
        .forward_a_sel(forward_a_sel),
        .forward_b_sel(forward_b_sel)
    );

    stall stall_i(
        .id_ex(id_ex_reg_before),
        .ex_mem(ex_mem_reg_before),
        .stall_signal(stall_signal)
    );

    freeze freeze_i(
        .mem_wb(mem_wb_reg),
        .imem_resp(imem_resp),
        .dmem_resp(dmem_resp),
        .freeze_stall(freeze_stall)
    );

    // ============================================================
    // Pipeline Register Updates
    // ============================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            if_id_reg  <= '0;
            id_ex_reg  <= '0;
            ex_mem_reg <= '0;
            mem_wb_reg <= '0;
        end
        else if (freeze_stall) begin
            // When memory stalls, keep all registers unchanged
            if_id_reg  <= if_id_reg;
            id_ex_reg  <= id_ex_reg;
            ex_mem_reg <= ex_mem_reg;
            mem_wb_reg <= mem_wb_reg;
        end
        else begin
            // Normal case: latch _before outputs into actual pipeline registers
            if_id_reg  <= if_id_reg_before;
            id_ex_reg  <= id_ex_reg_before;
            ex_mem_reg <= ex_mem_reg_before;
            mem_wb_reg <= mem_wb_reg_before;
        end
    end

endmodule
