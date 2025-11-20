# Pipeline 架構與 Register Renaming 實現說明

## 目錄
1. [HDL模塊功能說明](#hdl模塊功能說明)
2. [Register Renaming架構](#register-renaming架構)
3. [修改詳解](#修改詳解)
4. [數據流分析](#數據流分析)

---

## HDL模塊功能說明

### 📁 Pipeline Stages (hdl/pipeline/)

#### 1. **fetch.sv** - 取指階段
**功能：**
- 從instruction memory讀取指令
- 維護PC（程序計數器）
- 處理branch/jump的PC更新
- 實現pipeline flush（IF/ID flush）

**關鍵信號：**
- 輸入：`pc_next`（下一個PC值）、`flush_pipeline`
- 輸出：`if_id_reg`（IF/ID pipeline register）、`imem_rdata_id`（指令）

#### 2. **decode.sv** - 譯碼階段  
**功能：**
- 指令解碼（opcode, funct3, funct7）
- 生成立即數（I-type, S-type, B-type, U-type, J-type）
- 設置ALU、CMP、MUX控制信號
- **✨ Register renaming lookup（重要！）**
- 從PRF讀取物理寄存器值
- 實現ID/EX flush

**關鍵修改（Register Renaming）：**
```systemverilog
// 從rename_unit獲取物理寄存器號
input logic [5:0] rs1_phys, rs2_phys, dest_phys_new, dest_phys_old;

// 從PRF讀取物理寄存器值
input logic [31:0] rs1_val, rs2_val;

// 傳遞給pipeline
id_ex.rs1_phys = rs1_phys;  // 不是rs1_s！
id_ex.rs2_phys = rs2_phys;
id_ex.rs1_v = rs1_val;      // 直接從PRF來的值
id_ex.rs2_v = rs2_val;
```

#### 3. **execute.sv** - 執行階段
**功能：**
- ALU運算（add, sub, xor, or, and, sll, srl, sra）
- 比較器（CMP）用於branch判斷
- Forwarding邏輯處理數據hazard
- 計算branch目標地址
- 實現EX/MEM flush

**修改：**
- 傳遞物理寄存器號碼給下一階段
- Forwarding仍然基於物理寄存器號（不是architectural）

#### 4. **memstage.sv** - 記憶體訪問階段
**功能：**
- 處理load/store指令
- 計算記憶體地址
- 生成dmem控制信號（rmask, wmask）
- 檢測branch/jump → 產生`flush_pipeline`信號
- **✨ 實現MEM/WB flush（關鍵修復）**

**關鍵修改：**
```systemverilog
// MEM/WB flush實現
assign mem_wb.valid = flush_pipeline ? 1'b0 : ex_mem.valid;
```

#### 5. **writeback.sv** - 寫回階段
**功能：**
- 選擇寫回數據（ALU結果、load數據、PC+4等）
- **✨ 向PRF寫入結果**
- **✨ 通知rename_unit commit**
- 生成RVFI驗證信號

**關鍵修改（Register Renaming）：**
```systemverilog
// 寫入PRF（物理寄存器文件）
output logic        prf_we;
output logic [5:0]  prf_wr_phys;
output logic [31:0] prf_wr_data;

assign prf_we = commit && regf_we_back;
assign prf_wr_phys = mem_wb.dest_phys_new;  // 寫入新的物理寄存器
assign prf_wr_data = regfilemux_out;

// 通知rename_unit commit
output logic        commit_we;
output logic [4:0]  commit_arch;
output logic [5:0]  commit_phys;
output logic [5:0]  commit_old_phys;

assign commit_we = commit && (mem_wb.dest_arch != 5'd0);
assign commit_arch = mem_wb.dest_arch;
assign commit_phys = mem_wb.dest_phys_new;
assign commit_old_phys = mem_wb.dest_phys_old;
```

---

### 📁 Register Renaming 相關模塊

#### 6. **rename_unit.sv** - 寄存器重命名單元 ⭐
**功能：**
- 維護**RAT (Register Alias Table)**：architectural → physical映射
- 在decode階段：查找rs1/rs2的物理寄存器號
- 分配新物理寄存器給rd
- 在commit階段：更新RAT
- 返回舊的物理寄存器給free_list

**數據結構：**
```systemverilog
logic [5:0] RAT [31:0];  // 32個architectural → physical映射
```

**操作流程：**
1. **Decode階段查找：**
   ```systemverilog
   rs1_phys = RAT[rs1_arch];  // 查找rs1映射的物理寄存器
   rs2_phys = RAT[rs2_arch];
   old_phys = RAT[rd_arch];   // rd當前映射的舊物理寄存器
   ```

2. **分配新物理寄存器：**
   ```systemverilog
   if (alloc_valid && rd_arch != 0) begin
       new_phys = alloc_phys;  // 從free_list分配
       rename_we = 1'b1;
   end
   ```

3. **Commit階段更新：**
   ```systemverilog
   if (commit_we && commit_arch != 0) begin
       RAT[commit_arch] <= commit_phys;  // 更新映射
       free_phys = commit_old_phys;      // 返還舊物理寄存器
   end
   ```

#### 7. **free_list.sv** - 空閒物理寄存器列表
**功能：**
- 管理64個物理寄存器的分配和釋放
- FIFO隊列結構
- 提供物理寄存器給rename_unit

**初始化：**
```systemverilog
// Reset時：phys 1-63都是free（phys 0保留給x0）
for (i = 1; i < 64; i++)
    queue[i-1] <= i[5:0];
count <= 63;
```

**分配（Dequeue）：**
```systemverilog
alloc_phys = queue[head];
alloc_valid = (count > 0);
if (alloc_valid) head++;
```

**釋放（Enqueue）：**
```systemverilog
if (free_en) begin
    queue[tail] <= free_phys;
    tail++;
end
```

#### 8. **prf.sv** - Physical Register File (PRF)
**功能：**
- 64個32-bit物理寄存器
- 2個讀端口（rs1, rs2）
- 1個寫端口（rd）

**關鍵特性：**
```systemverilog
// 讀是組合邏輯（0延遲）
assign rs1_val = prf_mem[rs1_phys];
assign rs2_val = prf_mem[rs2_phys];

// 寫是時序邏輯（在writeback階段）
if (we && rd_phys != 6'd0)
    prf_mem[rd_phys] <= rd_val;
```

---

### 📁 其他支援模塊

#### 9. **cpu.sv** - 頂層模塊
**功能：**
- 實例化所有pipeline階段
- 實例化register renaming相關模塊
- 連接所有信號
- 實現pipeline register latching

**關鍵修改：**
```systemverilog
// 實例化register renaming模塊
rename_unit rename_unit_i(...);
free_list free_list_i(...);
prf prf_i(...);

// 不再使用原來的regfile（architectural register file）
// regfile regfile_i(...);  // 註釋掉
```

#### 10. **Forward.sv** - Forwarding單元
**功能：**
- 檢測數據hazard
- 生成forwarding控制信號
- 解決RAW (Read After Write) hazard

**修改：**
```systemverilog
// 現在比較物理寄存器號，不是architectural
if (id_ex.rs1_phys == ex_mem.dest_phys_new && ex_mem.regf_we)
    forward_a_sel = forward_amux::alu_out;
```

#### 11. **Load_hazard_stall.sv** - Load數據hazard處理
**功能：**
- 檢測load-use hazard
- 產生stall信號

#### 12. **freeze.sv** - 記憶體stall處理
**功能：**
- 當imem或dmem未響應時stall整個pipeline

#### 13. **alu.sv** - 算術邏輯單元
**功能：**
- 執行算術運算（add, sub）
- 邏輯運算（and, or, xor）
- 移位運算（sll, srl, sra）

#### 14. **cmp.sv** - 比較器
**功能：**
- Branch條件判斷（beq, bne, blt, bge, bltu, bgeu）

#### 15. **ir.sv** - Instruction Register
**功能：**
- 保存當前執行的指令

#### 16. **regfile.sv** - Architectural Register File (已廢棄)
**狀態：** ⚠️ 不再使用
- 在原始設計中提供32個architectural寄存器
- Register renaming實現後，被PRF取代
- 保留在代碼中但未實例化

---

## Register Renaming架構

### 核心概念

**問題：** 為什麼需要register renaming？
1. **消除WAW hazard** (Write After Write)
2. **消除WAR hazard** (Write After Read)  
3. **只保留真正的RAW hazard** (Read After Write - 真數據依賴)
4. **允許亂序執行**（雖然這個pipeline仍是in-order commit）

### 架構圖

```
┌─────────────────────────────────────────────────────────────┐
│                    DECODE STAGE                             │
│                                                             │
│  Instruction → Extract rs1_arch, rs2_arch, rd_arch         │
│                         ↓                                   │
│                  ┌──────────────┐                          │
│                  │ RENAME_UNIT  │                          │
│                  │              │                          │
│    ┌─────────────┤  RAT[32]     │←──────────────┐         │
│    │             │  [arch→phys] │               │         │
│    │             └──────────────┘               │         │
│    │                    ↓                       │         │
│    │           rs1_phys, rs2_phys       Commit  │         │
│    │           new_phys, old_phys       Update  │         │
│    │                    ↓                       │         │
│    │              ┌──────────┐                  │         │
│    └──Allocate───→│FREE_LIST │←───Free──────────┘         │
│                   │ FIFO[63] │                 WB         │
│                   └──────────┘                             │
│                         ↓                                  │
│                   alloc_phys                               │
│                         ↓                                  │
│              ┌─────────────────┐                          │
│              │      PRF        │                          │
│   Read ─────→│  [0:63][31:0]  │←──── Write (from WB)     │
│              │                 │                          │
│              └─────────────────┘                          │
│                    ↓                                      │
│            rs1_val, rs2_val                               │
│                    ↓                                      │
│              ID/EX Pipeline Reg                           │
└─────────────────────────────────────────────────────────────┘
```

### 數據流示例

假設執行：
```assembly
add x1, x2, x3  # instruction 1
add x4, x1, x5  # instruction 2
```

**Instruction 1 (add x1, x2, x3):**

1. **Decode階段：**
   ```
   rs1_arch = 2, rs2_arch = 3, rd_arch = 1
   
   Rename_unit查找：
   rs1_phys = RAT[2] = 15 (假設)
   rs2_phys = RAT[3] = 8
   old_phys = RAT[1] = 10 (x1當前映射到phys 10)
   
   Free_list分配：
   alloc_phys = 20 (新的物理寄存器)
   new_phys = 20
   
   PRF讀取：
   rs1_val = PRF[15]
   rs2_val = PRF[8]
   ```

2. **Execute階段：**
   ```
   result = rs1_val + rs2_val
   ```

3. **Writeback階段：**
   ```
   PRF[20] = result  (寫入新物理寄存器)
   
   Commit到rename_unit：
   RAT[1] = 20  (更新x1映射到phys 20)
   
   Free_list釋放：
   free_phys = 10  (舊的phys 10可以重用)
   ```

**Instruction 2 (add x4, x1, x5):**

1. **Decode階段：**
   ```
   rs1_arch = 1, rs2_arch = 5, rd_arch = 4
   
   Rename_unit查找：
   rs1_phys = RAT[1] = 20 (已更新！指向inst1的結果)
   rs2_phys = RAT[5] = 12
   old_phys = RAT[4] = 6
   
   Free_list分配：
   alloc_phys = 21
   new_phys = 21
   ```

✅ **消除了hazard！** inst2直接讀取phys 20，無需forwarding或stall！

---

## 修改詳解

### 總共添加的代碼量

| 文件 | 新增行數 | 主要修改 |
|------|---------|----------|
| **rename_unit.sv** | **100行** (全新) | RAT邏輯、commit更新 |
| **free_list.sv** | **65行** (全新) | FIFO管理物理寄存器 |
| **prf.sv** | **37行** (全新) | 64個物理寄存器 |
| **cpu.sv** | **~50行** | 實例化新模塊、信號連接 |
| **decode.sv** | **~30行** | 接入rename_unit和PRF |
| **writeback.sv** | **~40行** | PRF寫入、commit通知 |
| **Forward.sv** | **~20行** | 物理寄存器號比較 |
| **execute.sv** | **~10行** | 傳遞物理寄存器號 |
| **memstage.sv** | **~5行** | 傳遞物理寄存器號 |
| **總計** | **~357行** | |

### 主要修改的地方及原因

#### 🔥 **修改最多：cpu.sv (~50行)**

**原因：**
1. 需要實例化3個新模塊（rename_unit, free_list, prf）
2. 連接大量新增信號（~30個信號）
3. 移除舊的regfile實例化
4. 添加pipeline register中的物理寄存器字段

**關鍵代碼：**
```systemverilog
// 新增信號聲明
logic [5:0] rs1_phys, rs2_phys, dest_phys_new, dest_phys_old;
logic [31:0] prf_rs1_val, prf_rs2_val;
logic       alloc_valid;
logic [5:0] alloc_phys;
logic       free_en;
logic [5:0] free_phys;
logic       prf_we;
logic [5:0] prf_wr_phys;
logic [31:0] prf_wr_data;
logic       commit_we;
logic [4:0] commit_arch;
logic [5:0] commit_phys, commit_old_phys;

// 實例化
rename_unit rename_unit_i(
    .clk(clk), .rst(rst),
    .rs1_arch(/*...*/),
    .rs2_arch(/*...*/),
    // ... 很多信號
);

free_list free_list_i(/*...*/);
prf prf_i(/*...*/);
```

#### 🔥 **writeback.sv (~40行)**

**原因：**
1. 需要寫入PRF而不是regfile
2. 需要commit通知給rename_unit
3. 返回舊物理寄存器給free_list
4. RVFI信號也需要更新

**關鍵修改：**
```systemverilog
// 新增輸出
output logic prf_we;
output logic [5:0] prf_wr_phys;
output logic [31:0] prf_wr_data;

output logic commit_we;
output logic [4:0] commit_arch;
output logic [5:0] commit_phys;
output logic [5:0] commit_old_phys;

// 實現
assign prf_we = commit && regf_we_back;
assign prf_wr_phys = mem_wb.dest_phys_new;
assign prf_wr_data = regfilemux_out;

assign commit_we = commit && (mem_wb.dest_arch != 5'd0);
assign commit_arch = mem_wb.dest_arch;
assign commit_phys = mem_wb.dest_phys_new;
assign commit_old_phys = mem_wb.dest_phys_old;
```

#### 🔥 **decode.sv (~30行)**

**原因：**
1. 需要接收rename_unit的查找結果
2. 需要接收PRF的讀取值
3. 需要傳遞architectural register號給rename_unit
4. 需要在pipeline register中添加物理寄存器字段

**關鍵修改：**
```systemverilog
// 新增輸入
input logic [5:0] rs1_phys, rs2_phys;
input logic [5:0] dest_phys_new, dest_phys_old;
input logic [31:0] rs1_val, rs2_val;

// 傳遞給ID/EX
id_ex.rs1_phys = rs1_phys;
id_ex.rs2_phys = rs2_phys;
id_ex.dest_phys_new = dest_phys_new;
id_ex.dest_phys_old = dest_phys_old;

id_ex.rs1_v = rs1_val;  // 從PRF來
id_ex.rs2_v = rs2_val;

// 提取architectural indices（給rename_unit）
id_ex.rs1_arch = imem_rdata_id[19:15];
id_ex.rs2_arch = imem_rdata_id[24:20];
id_ex.dest_arch = imem_rdata_id[11:7];
```

---

## 為什麼這樣設計？

### ✅ 優點

1. **消除False Dependencies**
   - WAR和WAW hazard完全消除
   - 只剩真數據依賴（RAW）

2. **提高並行度**
   - 多個指令可以同時寫不同的物理寄存器
   - 為未來的亂序執行做準備

3. **Forwarding更簡單**
   - 基於物理寄存器號比較
   - 不需要考慮architectural register的複雜性

4. **擴展性好**
   - 64個物理寄存器 vs 32個architectural寄存器
   - 可以支持更多in-flight指令

### ⚠️ 代價

1. **硬件複雜度增加**
   - 需要RAT（32 x 6-bit = 192 bits）
   - 需要Free List管理邏輯
   - PRF比regfile大一倍（64 vs 32）

2. **面積和功耗增加**
   - 更多寄存器
   - 更多邏輯門

3. **調試更困難**
   - Architectural state vs Physical state
   - 需要RVFI正確報告

---

## 總結

**Register Renaming的核心價值：**
通過將architectural registers映射到更多的physical registers，消除了false dependencies，為高性能pipeline（特別是亂序執行）鋪平了道路。

**實現關鍵：**
1. **Decode階段**：查RAT + 讀PRF + 從Free List分配
2. **Execute階段**：使用物理寄存器號
3. **Writeback階段**：寫PRF + 更新RAT + 釋放舊物理寄存器

**修改重點：**
- cpu.sv最多（實例化和連接）
- writeback.sv次之（commit邏輯）
- decode.sv第三（lookup邏輯）
