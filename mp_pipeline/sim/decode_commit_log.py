#!/usr/bin/env python3
"""
RISC-V Instruction Decoder for commit.log
Converts instruction encodings to human-readable assembly format
"""

import sys
import re

def decode_register(reg_num):
    """Convert register number to register name"""
    if reg_num == 0:
        return "zero"
    elif reg_num == 1:
        return "ra"
    elif reg_num == 2:
        return "sp"
    elif reg_num == 3:
        return "gp"
    elif reg_num == 4:
        return "tp"
    elif reg_num in range(5, 8):
        return f"t{reg_num - 5}"
    elif reg_num in range(8, 10):
        return f"s{reg_num - 8}"
    elif reg_num in range(10, 18):
        return f"a{reg_num - 10}"
    elif reg_num in range(18, 28):
        return f"s{reg_num - 16}"
    elif reg_num in range(28, 32):
        return f"t{reg_num - 25}"
    else:
        return f"x{reg_num}"

def sign_extend(value, bits):
    """Sign extend a value from bits to 32 bits"""
    sign_bit = 1 << (bits - 1)
    return (value & (sign_bit - 1)) - (value & sign_bit)

def decode_instruction(inst):
    """Decode a 32-bit RISC-V instruction"""
    opcode = inst & 0x7F
    rd = (inst >> 7) & 0x1F
    funct3 = (inst >> 12) & 0x7
    rs1 = (inst >> 15) & 0x1F
    rs2 = (inst >> 20) & 0x1F
    funct7 = (inst >> 25) & 0x7F
    
    # R-type instructions
    if opcode == 0x33:  # OP
        if funct7 == 0x00:
            if funct3 == 0x0:
                return f"add {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x1:
                return f"sll {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x2:
                return f"slt {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x3:
                return f"sltu {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x4:
                return f"xor {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x5:
                return f"srl {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x6:
                return f"or {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x7:
                return f"and {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
        elif funct7 == 0x20:
            if funct3 == 0x0:
                return f"sub {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x5:
                return f"sra {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
        elif funct7 == 0x01:  # M extension
            if funct3 == 0x0:
                return f"mul {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x1:
                return f"mulh {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x2:
                return f"mulhsu {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x3:
                return f"mulhu {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x4:
                return f"div {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x5:
                return f"divu {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x6:
                return f"rem {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
            elif funct3 == 0x7:
                return f"remu {decode_register(rd)}, {decode_register(rs1)}, {decode_register(rs2)}"
    
    # I-type instructions (arithmetic)
    elif opcode == 0x13:  # OP-IMM
        imm = sign_extend((inst >> 20) & 0xFFF, 12)
        if funct3 == 0x0:
            return f"addi {decode_register(rd)}, {decode_register(rs1)}, {imm}"
        elif funct3 == 0x2:
            return f"slti {decode_register(rd)}, {decode_register(rs1)}, {imm}"
        elif funct3 == 0x3:
            return f"sltiu {decode_register(rd)}, {decode_register(rs1)}, {imm}"
        elif funct3 == 0x4:
            return f"xori {decode_register(rd)}, {decode_register(rs1)}, {imm}"
        elif funct3 == 0x6:
            return f"ori {decode_register(rd)}, {decode_register(rs1)}, {imm}"
        elif funct3 == 0x7:
            return f"andi {decode_register(rd)}, {decode_register(rs1)}, {imm}"
        elif funct3 == 0x1:
            shamt = (inst >> 20) & 0x1F
            return f"slli {decode_register(rd)}, {decode_register(rs1)}, {shamt}"
        elif funct3 == 0x5:
            shamt = (inst >> 20) & 0x1F
            if funct7 == 0x00:
                return f"srli {decode_register(rd)}, {decode_register(rs1)}, {shamt}"
            elif funct7 == 0x20:
                return f"srai {decode_register(rd)}, {decode_register(rs1)}, {shamt}"
    
    # Load instructions
    elif opcode == 0x03:  # LOAD
        imm = sign_extend((inst >> 20) & 0xFFF, 12)
        if funct3 == 0x0:
            return f"lb {decode_register(rd)}, {imm}({decode_register(rs1)})"
        elif funct3 == 0x1:
            return f"lh {decode_register(rd)}, {imm}({decode_register(rs1)})"
        elif funct3 == 0x2:
            return f"lw {decode_register(rd)}, {imm}({decode_register(rs1)})"
        elif funct3 == 0x4:
            return f"lbu {decode_register(rd)}, {imm}({decode_register(rs1)})"
        elif funct3 == 0x5:
            return f"lhu {decode_register(rd)}, {imm}({decode_register(rs1)})"
    
    # S-type instructions (Store)
    elif opcode == 0x23:  # STORE
        imm = sign_extend(((inst >> 25) << 5) | ((inst >> 7) & 0x1F), 12)
        if funct3 == 0x0:
            return f"sb {decode_register(rs2)}, {imm}({decode_register(rs1)})"
        elif funct3 == 0x1:
            return f"sh {decode_register(rs2)}, {imm}({decode_register(rs1)})"
        elif funct3 == 0x2:
            return f"sw {decode_register(rs2)}, {imm}({decode_register(rs1)})"
    
    # B-type instructions (Branch)
    elif opcode == 0x63:  # BRANCH
        imm = sign_extend(
            ((inst >> 31) << 12) |
            (((inst >> 7) & 0x1) << 11) |
            (((inst >> 25) & 0x3F) << 5) |
            (((inst >> 8) & 0xF) << 1),
            13
        )
        if funct3 == 0x0:
            return f"beq {decode_register(rs1)}, {decode_register(rs2)}, {imm}"
        elif funct3 == 0x1:
            return f"bne {decode_register(rs1)}, {decode_register(rs2)}, {imm}"
        elif funct3 == 0x4:
            return f"blt {decode_register(rs1)}, {decode_register(rs2)}, {imm}"
        elif funct3 == 0x5:
            return f"bge {decode_register(rs1)}, {decode_register(rs2)}, {imm}"
        elif funct3 == 0x6:
            return f"bltu {decode_register(rs1)}, {decode_register(rs2)}, {imm}"
        elif funct3 == 0x7:
            return f"bgeu {decode_register(rs1)}, {decode_register(rs2)}, {imm}"
    
    # U-type instructions
    elif opcode == 0x37:  # LUI
        imm = inst & 0xFFFFF000
        return f"lui {decode_register(rd)}, 0x{imm >> 12:x}"
    
    elif opcode == 0x17:  # AUIPC
        imm = inst & 0xFFFFF000
        return f"auipc {decode_register(rd)}, 0x{imm >> 12:x}"
    
    # J-type instructions
    elif opcode == 0x6F:  # JAL
        imm = sign_extend(
            ((inst >> 31) << 20) |
            (((inst >> 12) & 0xFF) << 12) |
            (((inst >> 20) & 0x1) << 11) |
            (((inst >> 21) & 0x3FF) << 1),
            21
        )
        return f"jal {decode_register(rd)}, {imm}"
    
    elif opcode == 0x67:  # JALR
        imm = sign_extend((inst >> 20) & 0xFFF, 12)
        return f"jalr {decode_register(rd)}, {decode_register(rs1)}, {imm}"
    
    # System instructions
    elif opcode == 0x73:
        if funct3 == 0x0:
            if inst == 0x00000073:
                return "ecall"
            elif inst == 0x00100073:
                return "ebreak"
            elif inst == 0x30200073:
                return "mret"
            elif inst == 0x10500073:
                return "wfi"
        # CSR instructions
        csr = (inst >> 20) & 0xFFF
        if funct3 == 0x1:
            return f"csrrw {decode_register(rd)}, 0x{csr:x}, {decode_register(rs1)}"
        elif funct3 == 0x2:
            return f"csrrs {decode_register(rd)}, 0x{csr:x}, {decode_register(rs1)}"
        elif funct3 == 0x3:
            return f"csrrc {decode_register(rd)}, 0x{csr:x}, {decode_register(rs1)}"
        elif funct3 == 0x5:
            return f"csrrwi {decode_register(rd)}, 0x{csr:x}, {rs1}"
        elif funct3 == 0x6:
            return f"csrrsi {decode_register(rd)}, 0x{csr:x}, {rs1}"
        elif funct3 == 0x7:
            return f"csrrci {decode_register(rd)}, 0x{csr:x}, {rs1}"
    
    # Fence instructions
    elif opcode == 0x0F:
        if funct3 == 0x0:
            return "fence"
        elif funct3 == 0x1:
            return "fence.i"
    
    # Unknown instruction
    return f"unknown (0x{inst:08x})"

def parse_commit_log_line(line):
    """Parse a line from commit.log"""
    # Format 1: core   0: 3 0x60000000 (0x003c9333) x6  0x00000000 (with register write)
    pattern1 = r'core\s+(\d+):\s+(\d+)\s+(0x[0-9a-fA-F]+)\s+\((0x[0-9a-fA-F]+)\)\s+(\w+)\s+(0x[0-9a-fA-F]+)'
    match = re.match(pattern1, line)
    
    if match:
        core = match.group(1)
        cycle = match.group(2)
        pc = match.group(3)
        inst_hex = match.group(4)
        reg = match.group(5)
        value = match.group(6)
        
        # Decode instruction
        inst = int(inst_hex, 16)
        decoded = decode_instruction(inst)
        
        return {
            'core': core,
            'cycle': cycle,
            'pc': pc,
            'inst_hex': inst_hex,
            'decoded': decoded,
            'reg': reg,
            'value': value
        }
    
    # Format 2: core   0: 3 0xf244261e (0x49e7fc63) (without register write - branch/store)
    pattern2 = r'core\s+(\d+):\s+(\d+)\s+(0x[0-9a-fA-F]+)\s+\((0x[0-9a-fA-F]+)\)'
    match = re.match(pattern2, line)
    
    if match:
        core = match.group(1)
        cycle = match.group(2)
        pc = match.group(3)
        inst_hex = match.group(4)
        
        # Decode instruction
        inst = int(inst_hex, 16)
        decoded = decode_instruction(inst)
        
        return {
            'core': core,
            'cycle': cycle,
            'pc': pc,
            'inst_hex': inst_hex,
            'decoded': decoded,
            'reg': None,
            'value': None
        }
    
    return None

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 decode_commit_log.py <commit.log> [output_file]")
        print("  If output_file is not specified, output will be printed to stdout")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    try:
        with open(input_file, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: File '{input_file}' not found")
        sys.exit(1)
    
    results = []
    for line_num, line in enumerate(lines, 1):
        line = line.strip()
        if not line:
            continue
        
        parsed = parse_commit_log_line(line)
        if parsed:
            # Format output based on whether there's a register write
            if parsed['reg'] and parsed['value']:
                # Format: PC: instruction  ->  reg = value
                output_line = f"{parsed['pc']}: {parsed['decoded']:50s}  ->  {parsed['reg']} = {parsed['value']}"
            else:
                # Format: PC: instruction (no register write)
                output_line = f"{parsed['pc']}: {parsed['decoded']}"
            results.append(output_line)
        else:
            results.append(f"# Failed to parse line {line_num}: {line}")

    
    # Output results
    if output_file:
        with open(output_file, 'w') as f:
            for line in results:
                f.write(line + '\n')
        print(f"Decoded {len(results)} instructions to {output_file}")
    else:
        for line in results:
            print(line)

if __name__ == "__main__":
    main()
