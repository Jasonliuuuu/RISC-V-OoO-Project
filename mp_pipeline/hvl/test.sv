    .rvfi_valid(itf.valid),               // 1
    .rvfi_order(itf.order),               // 12345
    .rvfi_insn(itf.inst),                 // 0x00A28293
    .rvfi_rs1_addr(itf.rs1_addr),         // 5
    .rvfi_rs2_addr(itf.rs2_addr),         // 0
    .rvfi_rs1_rdata(itf.rs1_rdata),       // 0x14 
    .rvfi_rs2_rdata(itf.rs2_rdata),       // 0x00
    .rvfi_rd_addr(itf.rd_addr),           // 5
    .rvfi_rd_wdata(itf.rd_wdata),         // 0x1E (result of DUT)
    .rvfi_pc_rdata(itf.pc_rdata),         // 0x60000084
    .rvfi_pc_wdata(itf.pc_wdata),         // 0x60000088 (DUT next PC)
    .rvfi_mem_addr(itf.mem_addr),         // 0x00000000
    .rvfi_mem_rmask(itf.mem_rmask),       // 0b0000
    .rvfi_mem_wmask(itf.mem_wmask),       // 0b0000
    .rvfi_mem_rdata(itf.mem_rdata),       // 0x00000000
    .rvfi_mem_wdata(itf.mem_wdata),       // 0x00000000

    // Golden Model output
    .errcode(errcode)                     // 0 = correct, !0 = wrong




    riscv_formal_monitor_rv32imc_isa_spec ch0_isa_spec (
    .rvfi_valid(rvfi_valid),          // 1
    .rvfi_insn(rvfi_insn),            // 0x00A28293
    .rvfi_pc_rdata(rvfi_pc_rdata),    // 0x60000084
    .rvfi_rs1_rdata(rvfi_rs1_rdata),  // 0x14
    .rvfi_rs2_rdata(rvfi_rs2_rdata),  // 0x00
    .rvfi_mem_rdata(rvfi_mem_rdata),  // 0x00
    
    // ISA Spec expected output
    .spec_valid(ch0_spec_valid),
    .spec_trap(ch0_spec_trap),
    .spec_rs1_addr(ch0_spec_rs1_addr),    // expected rs1_addr
    .spec_rs2_addr(ch0_spec_rs2_addr),    // expected rs2_addr
    .spec_rd_addr(ch0_spec_rd_addr),      // expected rd_addr
    .spec_rd_wdata(ch0_spec_rd_wdata),    // expected rd_wdata
    .spec_pc_wdata(ch0_spec_pc_wdata),    // expected pc_wdata
    .spec_mem_addr(ch0_spec_mem_addr),    // expected mem_addr
    .spec_mem_rmask(ch0_spec_mem_rmask),  // expected mem_rmask
    .spec_mem_wmask(ch0_spec_mem_wmask),  // expected mem_wmask
    .spec_mem_wdata(ch0_spec_mem_wdata)   // expected mem_wdata
);