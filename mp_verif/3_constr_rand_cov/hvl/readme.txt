randinst.svh	定義隨機產生 RISC-V 指令的條件（constrained random）
instr_cg.svh	定義用來追蹤哪些 instruction fields 被 cover 過的 covergroup
tb.sv	測試平台（testbench），用來執行 randinst 並收集 coverage 數據
