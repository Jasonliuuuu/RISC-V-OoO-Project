always_comb begin
    mon_itf.valid = dut.monitor_valid;
    mon_itf.order = dut.monitor_order;
    mon_itf.inst = dut.monitor_inst;
    mon_itf.rs1_addr = dut.monitor_rs1_addr;
    mon_itf.rs2_addr = dut.monitor_rs2_addr;
    mon_itf.rs1_rdata = dut.monitor_rs1_rdata;
    mon_itf.rs2_rdata = dut.monitor_rs2_rdata;
    mon_itf.rd_addr = dut.monitor_rd_addr;
    mon_itf.rd_wdata = dut.monitor_rd_wdata;
    mon_itf.pc_rdata = dut.monitor_pc_rdata;
    mon_itf.pc_wdata = dut.monitor_pc_wdata;
    mon_itf.mem_addr = dut.monitor_mem_addr;
    mon_itf.mem_rmask = dut.monitor_mem_rmask;
    mon_itf.mem_wmask = dut.monitor_mem_wmask;
    mon_itf.mem_rdata = dut.monitor_mem_rdata;
    mon_itf.mem_wdata = dut.monitor_mem_wdata;
end
