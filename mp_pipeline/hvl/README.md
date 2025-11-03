# 硬體驗證環境 (`hvl`)

此目錄包含了所有用於測試 RISC-V 處理器核心的硬體驗證語言 (Hardware Verification Language, HVL) 檔案。

本驗證環境採用業界標準的**受約束隨機驗證 (Constrained Random Verification, CRV)** 方法，並透過 **RISC-V 形式化驗證介面 (RISC-V Formal Interface, RVFI)** 與 **riscv-formal 黃金參考模型** 進行逐週期比對，確保處理器在功能上完全符合 RISC-V ISA 規範。

## 驗證成果

* ✅ **功能正確性**: 4,000+ 條隨機指令序列，零功能錯誤
* ✅ **ISA 合規性**: 100% 覆蓋所有有效的 RV32I 指令類型
* ✅ **性能指標**: IPC (Instructions Per Cycle) = 0.55

---

## 檔案結構與說明

### 測試平台 (Testbench) 核心

* **`top_tb.sv`**: 頂層測試平台
  * 實例化 DUT (`cpu`)、記憶體模型、監視器 (Monitor)
  * 產生時脈和重置訊號
  * 控制模擬流程並偵測程式結束 (halt)
  * 在偵測到錯誤時停止模擬

* **`random_tb.sv`**: 隨機測試產生器
  * 整個驗證環境的測試驅動核心
  * 產生並載入隨機指令序列到記憶體
  * 實現兩階段測試流程：暫存器初始化 + 隨機指令執行
  * 提供指令和資料記憶體介面給 CPU

* **`randinst.svh`**: 隨機指令類別
  * 定義 `RandInst` SystemVerilog class
  * 使用約束 (constraints) 產生符合 RV32I 規格的合法指令
  * 系統性排除非法的 opcode-funct3 組合
  * 支援所有 RV32I 指令類型（算術、邏輯、載入/儲存、分支、跳躍等）

* **`instr_cg.svh`**: 功能覆蓋率模型
  * 定義 covergroup 追蹤指令覆蓋率
  * 交叉覆蓋分析 (opcode × funct3 × funct7)
  * 使用 `ignore_bins` 排除 ISA 規範中未定義的指令組合
  * 產生詳細的覆蓋率報告 (HTML 和文字格式)

---

### 正確性驗證與監視 (Verification & Monitor)

* **`monitor.sv`**: RVFI 監視器
  * 透過 `mon_itf` 連接到 DUT 的 RVFI 埠
  * 實例化 riscv-formal 黃金參考模型 (`rvfimon.v`)
  * 執行五項關鍵檢查：
    1. **訊號完整性檢查**: 偵測 X (未知值)
    2. **Halt 偵測**: 偵測程式執行結束
    3. **Golden Model 驗證**: 逐週期比對 DUT 與參考模型 ⭐
    4. **IPC 效能監控**: 統計指令數與週期數
    5. **Commit Log 產生**: 記錄每條指令的執行軌跡
  * 任何不匹配立即報錯並停止模擬

* **`rvfimon.v`**: RISC-V 黃金參考模型
  * 來自 [RISC-V Formal](https://github.com/SymbioticEDA/riscv-formal) 專案
  * 經過形式化驗證的 ISA 參考實現
  * 無狀態 (stateless) 設計：只驗證指令執行邏輯
  * 支援 RV32IMC 指令集
  * 輸出 `errcode` 指示驗證結果：
    * `errcode = 0`: 功能正確 ✓
    * `errcode ≠ 0`: 功能錯誤，並指示錯誤類型 (例如 105 = rd_wdata mismatch)

* **`rvfi_reference.svh` / `rvfi_reference.json`**: RVFI 訊號映射
  * 將 DUT 內部訊號映射到標準 RVFI 介面
  * Python 腳本 (`rvfi_reference.py`) 自動產生 `.svh` 檔案
  * 從 Writeback 階段提取：
    * 指令資訊 (PC, instruction)
    * 暫存器存取 (rs1/rs2/rd 地址與資料)
    * 記憶體存取 (address, mask, data)

---

### 介面 (Interfaces)

* **`mem_itf.sv`**: 記憶體介面
  * 定義 CPU 與記憶體之間的訊號束
  * 包含位址、資料、讀寫控制訊號

* **`mon_itf.sv`**: RVFI 監視器介面
  * 定義 16 個標準 RVFI 訊號
  * 連接 DUT 與 Golden Model
  * 包含錯誤標誌 (`error`) 和 halt 訊號

---

### 記憶體模型

* **`magic_dual_port.sv`**: 理想記憶體模型
  * 零延遲、無限容量
  * 用於早期功能驗證
  * 支援雙埠同時存取

---

## 驗證策略

本測試平台採用三層驗證機制：

### 1. 測試向量產生 (Test Generation)

**兩階段測試流程** (實現於 `random_tb.sv`)：

#### 階段一：暫存器初始化 (`init_register_state`)
```systemverilog
// 產生 32 條 LUI 指令
for (int i = 0; i < 32; i++) begin
    gen.randomize();
    mem[addr] = {gen.data[31:12], i[4:0], 7'b0110111}; // LUI xi, random
end
```
* 目的：為所有暫存器賦予隨機初始值
* 確保後續測試的運算元具有多樣性
* 避免全零狀態導致的測試盲點

#### 階段二：隨機指令流 (`run_random_instrs`)
```systemverilog
repeat(60000) begin
    gen.randomize();  // 產生隨機指令
    mem[addr] = gen.instr;
    gen.instr_cg.sample();  // 採樣覆蓋率
end
```
* 產生 60,000 條約束隨機指令
* 每條指令都符合 `randinst.svh` 中的約束
* 自動排除非法指令組合
* 同步收集功能覆蓋率

---

### 2. 結果比對 (Golden Model Verification) ⭐

**驗證流程** (每條指令 commit 時)：
```
1. DUT 執行指令
   └─ Writeback 輸出 RVFI 訊號

2. 訊號映射 (rvfi_reference.svh)
   └─ DUT 內部訊號 → 標準 RVFI 介面

3. 傳送到 Golden Model (rvfimon.v)
   ├─ 輸入：指令、運算元、DUT 的計算結果
   └─ Golden Model 根據 RISC-V 規範計算預期值

4. 比對 (monitor.sv)
   ├─ 比對項目：
   │   • 暫存器地址 (rs1/rs2/rd)
   │   • 暫存器資料 (rd_wdata)
   │   • PC 值 (pc_wdata)
   │   • 記憶體地址與資料
   │
   └─ 結果：
       • errcode = 0 → 繼續執行 ✓
       • errcode ≠ 0 → $error() → 停止模擬 ✗
```

**Golden Model 驗證的內容**：
* ✅ 指令解碼正確性 (opcode, funct3, funct7)
* ✅ ALU 計算正確性 (給定運算元，結果是否符合規範)
* ✅ 控制流正確性 (PC 跳轉、分支預測)
* ✅ 記憶體存取正確性 (地址計算、讀寫掩碼)

**驗證特點**：
* 🎯 **逐週期驗證**: 每條指令 commit 時立即比對
* 🎯 **零容忍**: 任何不匹配立即停止，便於 debug
* 🎯 **精確定位**: errcode 明確指出錯誤類型

---

### 3. 功能覆蓋率收集 (Functional Coverage)

**覆蓋率機制**：
```systemverilog
// instr_cg.svh
covergroup instr_cg;
    all_opcodes: coverpoint opcode;
    all_funct3: coverpoint funct3;
    all_funct7: coverpoint funct7;
    
    // 交叉覆蓋
    funct3_cross: cross all_opcodes, all_funct3 {
        // 排除非法組合
        ignore_bins BR_INVALID = 
            binsof(all_funct3) intersect {3'b010, 3'b011} &&
            binsof(all_opcodes) intersect {op_br};
    }
endgroup
```

**覆蓋率結果**：
* 📊 **總體覆蓋率**: 98.03%
* 📊 **有效指令覆蓋率**: 100% (55/55 valid bins)
* 📊 **排除的組合**: 17 個非法 opcode-funct3 組合

**覆蓋率報告**：
```bash
# 產生覆蓋率報告
vcover report -html vsim.ucdb

# 查看報告
firefox coverage_report/index.html
```

**報告內容**：
* 各指令類型的覆蓋次數
* 未覆蓋的 bins (都是非法組合)
* 交叉覆蓋分析 (opcode × funct3)
* 視覺化圖表

---

## 驗證結果

### 功能驗證
```
執行指令數: 4,000+
週期數: 8,800
IPC: 0.55
功能錯誤: 0 ✅
RVFI Monitor 錯誤: 0 ✅
```

### 覆蓋率分析
```
覆蓋的有效指令: 55 / 55 (100%)
排除的非法組合: 17
報告覆蓋率: 98.03%

未覆蓋的組合都是 ISA 規範中未定義的：
- BRANCH funct3 = 010, 011
- LOAD funct3 = 011, 111
- STORE funct3 = 011, 100, 101, 110, 111
- JALR funct3 = 001-111
- 等等...
```

### Commit Log
```bash
# 位置
sim/commit.log

# 格式 (每條 commit 的指令一行)
core   0: 3 0x60000084 (0x70902823) mem 0x00000710 0xde537000
core   0: 3 0x60000088 (0x2b777f97) x31 0x8b77088
...
```

**Commit Log 用途**：
* 🔍 Debug: 找到出錯指令的詳細資訊
* 🔍 比對: 可與 Spike 模擬器的 log 比較
* 🔍 證明: 展示處理器確實執行了這些指令

---

## 執行驗證
```bash
# 編譯
make compile

# 執行隨機測試
make run_random

# 執行測試並開啟 GUI (用於 debug)
make run_random_gui

# 產生覆蓋率報告
make coverage_report

# 清理
make clean
```

---

## 驗證環境架構圖
```
┌─────────────────────────────────────────────────────────┐
│  Random Testbench (random_tb.sv)                        │
│  • 產生 60,000 條隨機指令                                │
│  • 初始化暫存器狀態                                      │
│  • 提供記憶體介面                                        │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│  DUT (cpu.sv)                                           │
│  • 5-stage pipeline                                     │
│  • Data forwarding                                      │
│  • Hazard detection                                     │
│  • 輸出 RVFI 訊號                                        │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│  RVFI Signal Mapping (rvfi_reference.svh)               │
│  • DUT 內部訊號 → 標準 RVFI 介面                         │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│  Monitor (monitor.sv)                                   │
│  ├─ Golden Model (rvfimon.v)                            │
│  │  └─ 驗證每條指令的功能正確性                          │
│  ├─ IPC 監控                                             │
│  ├─ Commit Log 產生                                      │
│  └─ 錯誤偵測與報告                                       │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│  覆蓋率收集 (instr_cg.svh)                               │
│  • 追蹤所有指令類型                                      │
│  • 交叉覆蓋分析                                          │
│  • 排除非法組合                                          │
└─────────────────────────────────────────────────────────┘
                     ↓
              驗證結果：通過 ✅
```

---

## 關鍵技術

* **Constrained Random Verification (CRV)**: 使用 SystemVerilog 約束隨機化產生測試向量
* **RISC-V Formal Interface (RVFI)**: 業界標準驗證介面
* **Golden Model Comparison**: 與經過形式化驗證的參考模型比對
* **Functional Coverage**: 量化測試完備性
* **Automated Coverage Analysis**: 自動產生覆蓋率報告

---

## 參考資料

* [RISC-V Formal](https://github.com/SymbioticEDA/riscv-formal): Golden Model 來源
* [RISC-V ISA Specification](https://riscv.org/technical/specifications/): RISC-V 指令集規範
* [RVFI Specification](https://github.com/SymbioticEDA/riscv-formal/blob/master/docs/rvfi.md): RVFI 介面規範