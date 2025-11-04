module random_tb
  import rv32i_types::*;
  (
    mem_itf.mem itf_i,
    mem_itf.mem itf_d
  );
  
    `include "../hvl/randinst.svh"
    
    RandInst gen = new();
    
    bit [31:0] instruction_memory [bit[31:0]];
    bit [31:0] base_addr = 32'h60000000;
    int seed;
    
    initial begin
        // ========================================
        // 真正的随机种子
        // ========================================
        seed = $time ^ $random();
        
        if (!$value$plusargs("ntb_random_seed=%d", seed)) begin
            seed = $time ^ $random();
        end
        
        $srandom(seed);
        
        $display("==============================================");
        $display("Random seed: %0d", seed);
        $display("To reproduce: +ntb_random_seed=%0d", seed);
        $display("==============================================");
    end
    
    task init_register_state();
        bit [31:0] addr;
        
        addr = base_addr;
        
        $display("==============================================");
        $display("Initializing registers with 32 LUI instructions...");
        $display("==============================================");
        
        for (int i = 0; i < 32; ++i) begin
            // ========================================
            // 使用对象的 randomize() 方法（正确方式）
            // ========================================
            gen.randomize() with {
                instr.j_type.opcode == op_lui;
                instr.j_type.rd == i[4:0];
            };
            
            instruction_memory[addr] = gen.instr.word;
            addr += 4;
            
            if (i % 8 == 7) begin
                $display("  Initialized registers x%0d - x%0d", i-7, i);
            end
        end
        
        $display("Register initialization complete!");
    endtask : init_register_state
    
    task generate_instructions();
        bit [31:0] addr;
        
        addr = base_addr + 32*4;
        
        $display("==============================================");
        $display("Generating 60,000 random instructions...");
        $display("==============================================");
        
        for (int i = 0; i < 60000; i++) begin
            // ========================================
            // 每次生成新的随机指令
            // ========================================
            gen.randomize();
            instruction_memory[addr] = gen.instr.word;
            addr += 4;
            
            if ((i + 1) % 10000 == 0) begin
                $display("  Generated %0d / 60000 instructions", i + 1);
            end
        end
        
        // 添加 halt
        instruction_memory[addr] = 32'h00000063;
        
        $display("==============================================");
        $display("Instruction generation complete!");
        $display("Total instructions in memory: 60,032");
        $display("Address range: 0x%h - 0x%h", base_addr, addr);
        $display("==============================================");
    endtask : generate_instructions
    
    task respond_to_requests();
        forever begin
            @(posedge itf_i.clk);
            
            if (itf_i.rmask == 4'b1111) begin
                automatic bit [31:0] aligned_addr = {itf_i.addr[31:2], 2'b00};
                
                if (instruction_memory.exists(aligned_addr)) begin
                    itf_i.rdata <= instruction_memory[aligned_addr];
                end else begin
                    gen.randomize();
                    instruction_memory[aligned_addr] = gen.instr.word;
                    itf_i.rdata <= gen.instr.word;
                    $display("Info: Dynamically generated instruction at PC=0x%h", aligned_addr);
                end
                
                itf_i.resp <= 1'b1;
            end else begin
                itf_i.resp <= 1'b0;
            end
            
            if (|itf_d.rmask) begin
                gen.randomize();
                itf_d.rdata <= gen.instr.word;
                itf_d.resp <= 1'b1;
            end else if (|itf_d.wmask) begin
                itf_d.resp <= 1'b1;
            end else begin
                itf_d.resp <= 1'b0;
            end
        end
    endtask : respond_to_requests
    
    initial begin
        itf_i.resp = 1'b0;
        itf_d.resp = 1'b0;
        
        @(negedge itf_i.rst);
        @(posedge itf_i.clk);
        @(posedge itf_i.clk);
        
        init_register_state();
        generate_instructions();
        
        $display("");
        $display("██████╗  █████╗ ███╗   ██╗██████╗  ██████╗ ███╗   ███╗");
        $display("██╔══██╗██╔══██╗████╗  ██║██╔══██╗██╔═══██╗████╗ ████║");
        $display("██████╔╝███████║██╔██╗ ██║██║  ██║██║   ██║██╔████╔██║");
        $display("██╔══██╗██╔══██║██║╚██╗██║██║  ██║██║   ██║██║╚██╔╝██║");
        $display("██║  ██║██║  ██║██║ ╚████║██████╔╝╚██████╔╝██║ ╚═╝ ██║");
        $display("╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝  ╚═════╝ ╚═╝     ╚═╝");
        $display("");
        $display("Starting CPU execution...");
    end
    
    initial begin
        @(negedge itf_i.rst);
        respond_to_requests();
    end

endmodule : random_tb