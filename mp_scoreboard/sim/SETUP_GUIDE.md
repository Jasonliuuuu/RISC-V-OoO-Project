# MP Scoreboard 驗證環境設置指南

## 環境設置完成 ✓

您的 mp_scoreboard 驗證環境已經完全設置好了！

### 已創建的文件

1. **`sim/Makefile`** - 完整的編譯和運行腳本
2. **`bin/rvfi_reference.py`** - RVFI 參考生成腳本
3. **`hvl/rvfi_reference.svh`** - 自動生成的 RVFI 連接文件

### 目錄結構

```
mp_scoreboard/
├── bin/
│   └── rvfi_reference.py          # RVFI 參考生成器
├── hdl/
│   ├── cpu.sv                      # 主 CPU 模組
│   ├── regfile.sv                  # 寄存器文件
│   ├── functional_units/           # 功能單元 (ALU, MUL, DIV, BR)
│   ├── pipeline/                   # 流水線階段
│   └── scoreboard/                 # Scoreboard 控制邏輯
├── hvl/
│   ├── top_tb.sv                   # 頂層測試平台
│   ├── random_tb.sv                # 隨機測試生成器
│   ├── monitor.sv                  # RVFI 監控器
│   ├── rvfi_reference.json         # RVFI 信號映射
│   ├── rvfi_reference.svh          # 自動生成的 RVFI 連接
│   ├── rvfimon.v                   # RISC-V 正式驗證接口
│   ├── instr_cg.svh                # 指令覆蓋率
│   └── randinst.svh                # 隨機指令生成
├── pkg/
│   └── types.sv                    # 類型定義
└── sim/
    ├── Makefile                    # 編譯和運行腳本
    └── SETUP_GUIDE.md              # 本文檔

```

## 使用方法

### 前置條件

確保您的系統上已安裝 QuestaSim/ModelSim：

```bash
# 檢查工具是否可用
which vsim vlog vlib
```

如果工具不在 PATH 中，Makefile 已配置為使用 `/clear/apps/elec8/bin/` 路徑。

### 快速開始

1. **進入 sim 目錄**：
   ```bash
   cd mp_scoreboard/sim
   ```

2. **查看可用命令**：
   ```bash
   make help
   ```

3. **運行隨機測試（推薦）**：
   ```bash
   make run_random
   ```
   這將：
   - 編譯所有 HDL 和 HVL 文件
   - 運行隨機指令測試
   - 生成覆蓋率數據庫 (vsim.ucdb)

4. **生成覆蓋率報告**：
   ```bash
   make coverage
   ```
   報告將生成在 `coverage_report/index.html`

5. **GUI 模式運行**：
   ```bash
   make run_random_gui
   ```

### Makefile 目標說明

| 目標 | 說明 |
|------|------|
| `make run/top_tb` | 僅編譯設計，不運行仿真 |
| `make run_random` | 運行隨機測試並生成覆蓋率（命令行模式）|
| `make run_random_gui` | 運行隨機測試（GUI 模式）|
| `make coverage` | 生成 HTML 覆蓋率報告 |
| `make clean` | 清理所有生成的文件 |
| `make help` | 顯示幫助信息 |

### 編譯流程

Makefile 會自動處理以下步驟：

1. **創建工作庫**：創建 ModelSim 工作庫和運行目錄
2. **生成 RVFI 連接**：運行 `rvfi_reference.py` 生成 `rvfi_reference.svh`
3. **編譯文件**：編譯所有 .sv 和 .v 文件，包括：
   - Package 文件 (`pkg/types.sv`)
   - HDL 設計文件 (`hdl/**/*.sv`)
   - HVL 驗證文件 (`hvl/**/*.sv`, `hvl/**/*.v`)
4. **運行仿真**：執行測試平台並收集覆蓋率

### 驗證功能

這個環境支持：

1. **隨機指令生成**：
   - 自動生成 RV32I 指令序列
   - 支持所有 ALU、載入/存儲、分支、MUL、DIV 指令

2. **RVFI 監控**：
   - 自動檢查指令執行正確性
   - 驗證寄存器寫入、記憶體訪問、PC 更新

3. **功能覆蓋率**：
   - 指令類型覆蓋率
   - 寄存器使用覆蓋率
   - 交叉覆蓋率（指令類型 × 寄存器）

4. **代碼覆蓋率**：
   - 行覆蓋率 (Line Coverage)
   - 分支覆蓋率 (Branch Coverage)
   - 條件覆蓋率 (Condition Coverage)
   - 狀態機覆蓋率 (FSM Coverage)
   - 切換覆蓋率 (Toggle Coverage)

### 預期輸出

成功運行後，您應該看到：

```
Running random testbench with coverage...
...
# ** Note: Test Completed Successfully!
Coverage database created: vsim.ucdb
```

覆蓋率報告生成後：

```
✓ Coverage report generated: coverage_report/index.html
  Open with: firefox coverage_report/index.html
```

## 驗證狀態

根據之前的驗證報告 (`hvl/verification_report_2025_11_3.md`)：

- **指令測試數量**：60,000+ 條隨機指令
- **代碼覆蓋率**：98.03%
- **功能覆蓋率**：100% (所有指令類型)
- **錯誤數**：0
- **Scoreboard 功能**：完全實現並驗證

## 故障排除

### 問題：編譯錯誤

1. 確保所有 HDL 文件存在於 `hdl/` 目錄
2. 確保所有 HVL 文件存在於 `hvl/` 目錄
3. 檢查 `pkg/types.sv` 是否存在

### 問題：找不到 vlog/vsim

1. 檢查工具路徑：`which vlog vsim`
2. 如果需要，修改 Makefile 中的工具路徑：
   ```makefile
   VSIM = /path/to/your/vsim
   VLOG = /path/to/your/vlog
   VLIB = /path/to/your/vlib
   ```

### 問題：rvfi_reference.py 錯誤

確保 `hvl/rvfi_reference.json` 存在且格式正確。這個文件定義了 RVFI 信號的映射。

## 下一步

1. 運行 `make run_random` 進行完整驗證
2. 檢查 `run/random_tb_sim.log` 查看詳細日誌
3. 使用 `make coverage` 生成覆蓋率報告
4. 如果需要調試，使用 `make run_random_gui` 打開 GUI

## 支持的設計特性

本驗證環境支持以下 Scoreboard CPU 特性：

- ✓ RV32I 基礎指令集
- ✓ Scoreboard 結構化危害檢測
- ✓ 多功能單元並行執行 (ALU, MUL, DIV, BR)
- ✓ 載入/存儲指令
- ✓ 分支指令和跳轉
- ✓ 寄存器依賴管理

---

**設置完成日期**：2025-11-06
**驗證環境版本**：1.0
