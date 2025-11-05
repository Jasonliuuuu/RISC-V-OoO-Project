// This class generates random valid RISC-V instructions to test your RISC-V cores.

class RandInst;
  // You will increment this number as you generate more random instruction types. Once finished, NUM_TYPES should be 9, for each opcode type in rv32i_opcode.
  localparam NUM_TYPES = 9;

  // Static seed for class-level randomization
  static int class_seed = 0;

  // You'll need this type to randomly generate variants of certain
  // instructions that have the funct7 field.
  typedef enum bit [6:0] {
    base    = 7'b0000000,
    variant = 7'b0100000
  } funct7_t;

  // Various ways RISC-V instruction words can be interpreted.
  // See page 104, Chapter 19 RV32/64G Instruction Set Listings
  // of the RISC-V v2.2 spec.
  typedef union packed {
    bit [31:0] word;

    struct packed {
      bit [11:0] i_imm;
      bit [4:0] rs1;
      bit [2:0] funct3;
      bit [4:0] rd;
      rv32i_opcode opcode;
    } i_type;

    struct packed {
      bit [6:0] funct7;
      bit [4:0] rs2;
      bit [4:0] rs1;
      bit [2:0] funct3;
      bit [4:0] rd;
      rv32i_opcode opcode;
    } r_type;

    struct packed {
      bit [11:5] imm_s_top;
      bit [4:0]  rs2;
      bit [4:0]  rs1;
      bit [2:0]  funct3;
      bit [4:0]  imm_s_bot;
      rv32i_opcode opcode;
    } s_type;

    struct packed {
      bit [11:5] imm_b_top;
      bit [4:0]  rs2;
      bit [4:0]  rs1;
      bit [2:0]  funct3;
      bit [4:0]  imm_b_bot;
      rv32i_opcode opcode;
    } b_type;
    
    struct packed {
      bit [31:12] imm;
      bit [4:0]  rd;
      rv32i_opcode opcode;
    } u_type;

    struct packed {
      bit [31:12] imm;
      bit [4:0]  rd;
      rv32i_opcode opcode;
    } j_type;

  } instr_t;

  rand instr_t instr;
  rand bit [NUM_TYPES-1:0] instr_type;

  // Make sure we have an even distribution of instruction types.
  constraint solve_order_c { solve instr_type before instr; }

  rand bit [2:0] func3;
  constraint solve_order_funct3_c {solve func3 before instr; }

  // ========================================
  // Constraints to avoid halt conditions
  // ========================================
  
  // 1. BEQ cannot be x0, x0
  constraint no_beq_x0_x0 {
    (instr[6:0] == 7'b1100011 && instr[14:12] == 3'b000) -> 
      (instr[19:15] != 5'b00000 || instr[24:20] != 5'b00000);
  }
  
  // 2. Branch offset cannot be 0
  constraint branch_offset_not_zero {
    (instr[6:0] == 7'b1100011) -> 
      ({instr[31], instr[7], instr[30:25], instr[11:8]} != 13'b0);
  }
  
  // 3. JAL rd cannot be x0
  constraint jal_not_x0 {
    (instr[6:0] == 7'b1101111) -> (instr[11:7] != 5'b00000);
  }
  
  // 4. JAL offset cannot be 0
  constraint jal_offset_not_zero {
    (instr[6:0] == 7'b1101111) -> 
      ({instr[31], instr[19:12], instr[20], instr[30:21]} != 21'b0);
  }
  
  // 5. JALR offset cannot be 0
  constraint jalr_offset_not_zero {
    (instr[6:0] == 7'b1100111) -> (instr[31:20] != 12'b0);
  }
  
  // 6. Avoid tight backward branches (prevent tight loops)
  constraint no_tight_backward_branch {
    (instr[6:0] == 7'b1100011 && instr[31] == 1'b1) -> (
      $signed({instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}) < -256
    );
  }
  
  // 7. Avoid tight backward JAL (prevent tight loops)
  constraint no_tight_jal_backward {
    (instr[6:0] == 7'b1101111 && instr[31] == 1'b1) -> (
      $signed({instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}) < -512
    );
  }

  // Pick one of the instruction types.
  constraint instr_type_c {
    $countones(instr_type) == 1; // Ensures one-hot.
  }

  // Constraints for actually generating instructions, given the type.
  constraint instr_c {
    instr.r_type.funct3 == func3; 
    
    // Reg-imm instructions
    instr_type[0] -> {
      instr.i_type.opcode == op_imm;
      instr.r_type.funct3 == sr -> {
        instr.r_type.funct7 inside {base, variant};
      }
      if (instr.r_type.funct3 == sll) {
        instr.r_type.funct7 == base;
      }
    }

    // Reg-reg instructions
    instr_type[1] -> { 
      instr.r_type.opcode == op_reg;
      if((instr.r_type.funct3 == add )||(instr.r_type.funct3 == sr)){
        instr.r_type.funct7 inside {base, variant};
      }
      else {
        instr.r_type.funct7 == base;
      }
    }
    
    // Store instructions
    instr_type[2] -> {
      instr.s_type.opcode == op_store;
      instr.s_type.funct3 inside {sw, sb, sh};
      instr.s_type.rs1 == 0;
      instr.s_type.imm_s_bot[1:0] == 2'b00;
    }

    // Load instructions
    instr_type[3] -> {
      instr.i_type.opcode == op_load;
      instr.i_type.funct3 inside {lb, lh, lw, lbu, lhu};
      instr.i_type.rs1 == 0;
      instr.i_type.i_imm[1:0] == 2'b00;
    }

    // Branch instructions
    instr_type[4] -> {
      instr.b_type.opcode == op_br;
      instr.b_type.funct3 inside {beq, bne, blt, bge, bltu, bgeu};
    }
    
    // JALR instructions
    instr_type[5] -> {
      instr.i_type.opcode == op_jalr;
      instr.i_type.funct3 == 3'b000;   
    }
    
    // JAL instructions
    instr_type[6] -> {
      instr.j_type.opcode == op_jal;    
    }
    
    // LUI instructions
    instr_type[7] -> {
      instr.u_type.opcode == op_lui;  
    }
    
    // AUIPC instructions
    instr_type[8] -> {
      instr.u_type.opcode == op_auipc;
    }
  }
  
  `include "../hvl/instr_cg.svh"

  // Constructor, make sure we construct the covergroup and set seed
  function new();
    instr_cg = new();
    
    // Set random seed for this object
    if (class_seed == 0) begin
      class_seed = $time + $random();
      this.srandom(class_seed);
      $display("RandInst: Setting initial seed to %0d", class_seed);
    end else begin
      class_seed++;
      this.srandom(class_seed);
    end
  endfunction : new

  // Whenever randomize() is called, sample the covergroup.
  function void post_randomize();
    instr_cg.sample(this.instr);
  endfunction : post_randomize
 
  // A nice part of writing constraints is that we get constraint checking
  // for free -- this function will check if a bit vector is a valid RISC-V
  // instruction (assuming you have written all the relevant constraints).
  function bit verify_valid_instr(instr_t inp);
    bit valid = 1'b0;
    this.instr = inp;
    for (int i = 0; i < NUM_TYPES; ++i) begin
      this.instr_type = 1 << i;
      if (this.randomize(null)) begin
        valid = 1'b1;
        break;
      end
    end
    return valid;
  endfunction : verify_valid_instr
  
endclass : RandInst