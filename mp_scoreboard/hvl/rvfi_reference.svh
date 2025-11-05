always_comb begin
    mon_itf.valid = dut.writeback.rvfi_valid;
    mon_itf.order = dut.writeback.rvfi_order;
    mon_itf.inst = dut.writeback.rvfi_inst;
    mon_itf.rs1_addr = dut.writeback.rvfi_rs1_addr;
    mon_itf.rs2_addr = dut.writeback.rvfi_rs2_addr;
    mon_itf.rs1_rdata = dut.writeback.rvfi_rs1_rdata;
    mon_itf.rs2_rdata = dut.writeback.rvfi_rs2_rdata;
    mon_itf.rd_addr = dut.writeback.rvfi_rd_addr;
    mon_itf.rd_wdata = dut.writeback.rvfi_rd_wdata;
    mon_itf.pc_rdata = dut.writeback.rvfi_pc_rdata;
    mon_itf.pc_wdata = dut.writeback.rvfi_pc_wdata;
    mon_itf.mem_addr = dut.writeback.rvfi_dmem_addr;
    mon_itf.mem_rmask = dut.writeback.rvfi_dmem_rmask;
    mon_itf.mem_wmask = dut.writeback.rvfi_dmem_wmask;
    mon_itf.mem_rdata = dut.writeback.rvfi_dmem_rdata;
    mon_itf.mem_wdata = dut.writeback.rvfi_dmem_wdata;
end
