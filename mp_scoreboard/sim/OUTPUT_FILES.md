# MP Scoreboard 輸出文件說明

## 概述

運行 `make run_random` 後，驗證環境會自動生成多個輸出文件，用於記錄編譯、仿真和覆蓋率信息。

---

## 運行後生成的文件

### 1. 編譯相關文件

#### `run/top_tb_compile.log`
- **位置**: `mp_scoreboard/sim/run/`
- **生成時機**: 運行 `make run/top_tb` 或 `make run_random` 時
- **內容**:
  - QuestaSim/ModelSim 編譯輸出
  - 所有編譯警告和錯誤
  - 文件編譯順序
  - 編譯時間統計
- **用途**: 調試編譯錯誤

**示例內容**:
```
QuestaSim-64 vlog 2023.2 Compiler 2023.04 Apr 11 2023
-- Compiling package rv32i_types
-- Compiling module regfile
-- Compiling module fetch
...
Compilation successful
```

---

### 2. 仿真相關文件

#### `run/random_tb_sim.log`
- **位置**: `mp_scoreboard/sim/run/`
- **大小**: ~1 MB（60,000 條指令）
- **生成時機**: 運行 `make run_random` 時
- **內容**:
  - QuestaSim/ModelSim 仿真控制台輸出
  - 進度報告（每 1000 條指令）
  - RVFI 監控器輸出
  - 錯誤和警告信息
  - 性能統計（IPC、總週期數等）
- **用途**:
  - 調試仿真錯誤
  - 查看測試進度
  - 分析性能指標

**示例內容**:
```
# run -all
# dut commit No.0, rd_s: x06, rd: 0x00000000
# dut commit No.1000, rd_s: x10, rd: 0x3050a004
# Progress: 10000 / 60000 instructions completed
# Progress: 20000 / 60000 instructions completed
...
# SUCCESS: Completed 60000 instructions!
# Monitor: Total IPC: 0.856
# ** Note: $finish    : top_tb.sv(72)
```

---

### 3. 執行追蹤文件

#### `commit.log`
- **位置**: `mp_scoreboard/sim/` （根目錄）
- **大小**: ~3 MB（60,000 條指令）
- **生成時機**: 運行仿真時自動生成（由 `monitor.sv` 生成）
- **內容**:
  - 每條 committed 指令的完整執行記錄
  - PC 地址
  - 指令編碼
  - 寄存器寫入（如果有）
  - 內存訪問（Load/Store）
- **格式**: Spike 兼容的提交日誌格式
- **用途**:
  - 與 Spike 的黃金模型比對
  - 調試指令執行順序
  - 驗證亂序執行的正確性

**格式說明**:
```
core   0: 3 0x<PC> (0x<INST>) [x<RD>  0x<RD_DATA>] [mem 0x<ADDR> 0x<DATA>]
```

**示例內容**:
```
core   0: 3 0x60000000 (0x003c9333) x6  0x00000000
core   0: 3 0x60000004 (0xd050a517) x10 0x3050a004
core   0: 3 0x60000008 (0xec61f137) x2  0xec61f000
core   0: 3 0x6000000c (0xf17f81b7) x3  0xf17f8000
core   0: 3 0x60000010 (0x42499237) x4  0x42499000
core   0: 3 0x60000080 (0xd43b04e7) x9  0x60000084
core   0: 3 0xf2332d42 (0xab004003) mem 0xfffffab0
core   0: 3 0xf2332d46 (0x07dbdf63)
core   0: 3 0xf226773a (0x50d01c23) mem 0x00000518 0xe000
```

**字段說明**:
- `core 0`: 核心編號（單核系統）
- `3`: 特權級別（3 = Machine mode）
- `0x60000000`: PC 地址
- `(0x003c9333)`: 指令編碼
- `x6 0x00000000`: 寫入寄存器 x6，值為 0x00000000
- `mem 0xfffffab0`: Load 指令，讀取內存地址 0xfffffab0
- `mem 0x00000518 0xe000`: Store 指令，寫入地址 0x00000518，值為 0xe000

---

### 4. 覆蓋率文件

#### `vsim.ucdb`
- **位置**: `mp_scoreboard/sim/`
- **大小**: ~130 KB
- **生成時機**: 運行 `make run_random` 時
- **內容**:
  - 二進制覆蓋率數據庫
  - 行覆蓋率、分支覆蓋率、條件覆蓋率等
  - 功能覆蓋率（指令類型、寄存器使用等）
- **用途**: 生成覆蓋率報告

**使用方法**:
```bash
# 生成 HTML 覆蓋率報告
make coverage

# 查看覆蓋率報告
firefox coverage_report/index.html
```

---

### 5. 覆蓋率報告

#### `coverage_report/` 目錄
- **位置**: `mp_scoreboard/sim/coverage_report/`
- **生成時機**: 運行 `make coverage` 時
- **內容**:
  - HTML 格式的詳細覆蓋率報告
  - `index.html`: 報告首頁
  - 各模塊的詳細覆蓋率分析
  - 源代碼註釋（顯示哪些行被執行）
- **用途**:
  - 分析測試覆蓋率
  - 識別未測試的代碼路徑
  - 驗證測試完整性

#### `coverage_summary.txt`
- **位置**: `mp_scoreboard/sim/`
- **生成時機**: 運行 `make coverage` 時
- **內容**: 文本格式的覆蓋率摘要
- **用途**: 快速查看覆蓋率統計

---

### 6. 其他輔助文件

#### `transcript`
- **位置**: `mp_scoreboard/sim/`
- **內容**: ModelSim/QuestaSim 命令歷史記錄
- **用途**: 調試 GUI 會話

#### `vsim.wlf`
- **位置**: `mp_scoreboard/sim/`
- **內容**: 波形數據庫（如果使用 GUI 模式）
- **用途**: 查看信號波形

#### `work/` 目錄
- **位置**: `mp_scoreboard/sim/work/`
- **內容**: ModelSim/QuestaSim 編譯後的設計庫
- **用途**: 中間編譯產物

---

## 運行流程和文件生成

### 步驟 1: 編譯
```bash
make run/top_tb
```

**生成文件**:
- ✅ `run/top_tb_compile.log`
- ✅ `work/` 目錄

---

### 步驟 2: 運行仿真
```bash
make run_random
```

**生成文件**:
- ✅ `run/random_tb_sim.log` - 仿真日誌
- ✅ `commit.log` - 指令執行追蹤（**重要**）
- ✅ `vsim.ucdb` - 覆蓋率數據庫
- ✅ `transcript` - 命令歷史

---

### 步驟 3: 生成覆蓋率報告
```bash
make coverage
```

**生成文件**:
- ✅ `coverage_report/` 目錄（HTML 報告）
- ✅ `coverage_summary.txt` 文本摘要

---

## 文件對比：mp_pipeline vs mp_scoreboard

| 文件 | mp_pipeline | mp_scoreboard | 說明 |
|------|------------|---------------|------|
| `commit.log` | ✅ 3.0 MB | ✅ ~3 MB | 指令追蹤日誌 |
| `run/random_tb_sim.log` | ✅ 979 KB | ✅ ~1 MB | 仿真日誌 |
| `run/top_tb_compile.log` | ✅ 19 KB | ✅ ~20 KB | 編譯日誌 |
| `vsim.ucdb` | ✅ 130 KB | ✅ ~130 KB | 覆蓋率數據庫 |
| `coverage_report/` | ✅ | ✅ | 覆蓋率 HTML 報告 |
| `coverage_summary.txt` | ✅ | ✅ | 覆蓋率文本摘要 |

**結論**: mp_scoreboard 與 mp_pipeline 的輸出文件**完全一致**！

---

## 檢查輸出文件

運行完成後，使用以下命令檢查生成的文件：

```bash
cd mp_scoreboard/sim

# 查看所有生成的文件
ls -lh *.log commit.log vsim.ucdb

# 查看 run 目錄
ls -lh run/

# 查看覆蓋率報告
ls -lh coverage_report/

# 快速查看 commit.log（前 20 行）
head -20 commit.log

# 檢查指令數量
wc -l commit.log

# 檢查仿真是否成功
tail -50 run/random_tb_sim.log
```

---

## commit.log 的重要性

`commit.log` 是驗證處理器正確性的**關鍵文件**：

### 1. 與 Spike 比對
```bash
# 使用 Spike 生成參考日誌
spike --log-commits --log=spike.log /path/to/program.elf

# 比對兩個日誌（確認處理器行為正確）
diff commit.log spike.log
```

### 2. 驗證亂序執行
- 即使指令亂序執行，`commit.log` 記錄的是 **commit 順序**
- 應該與程序順序一致
- 可以驗證 Scoreboard 的正確性

### 3. 調試指令執行
- 定位哪條指令出錯
- 檢查寄存器值的變化
- 追蹤內存訪問

---

## 清理生成的文件

```bash
cd mp_scoreboard/sim

# 清理所有生成的文件
make clean

# 會刪除：
# - work/ 目錄
# - run/ 目錄
# - commit.log
# - vsim.ucdb
# - coverage_report/
# - *.log 文件
# - transcript
```

---

## 故障排除

### 問題 1: commit.log 沒有生成

**可能原因**:
- 仿真沒有運行或崩潰
- monitor.sv 中的 $fopen 失敗

**解決方法**:
```bash
# 檢查仿真日誌
cat run/random_tb_sim.log | grep -i error

# 確認 monitor.sv 包含 commit.log 生成代碼
grep "commit.log" ../hvl/monitor.sv
```

---

### 問題 2: commit.log 文件過小

**可能原因**:
- 仿真提前終止
- 處理器 hang 住

**解決方法**:
```bash
# 檢查指令數量
wc -l commit.log

# 查看仿真結束原因
tail -100 run/random_tb_sim.log
```

---

### 問題 3: 覆蓋率文件沒有生成

**可能原因**:
- 編譯時沒有啟用覆蓋率 (-cover bcefst)
- 仿真時沒有保存覆蓋率

**解決方法**:
```bash
# 檢查 Makefile 中的 VLOG_FLAGS
grep "cover" Makefile

# 重新運行帶覆蓋率的仿真
make clean
make run_random
```

---

## 預期輸出總結

運行 `make run_random` 成功後，應該看到：

```
mp_scoreboard/sim/
├── commit.log              # ✅ ~3 MB，60,000 條指令記錄
├── vsim.ucdb               # ✅ ~130 KB，覆蓋率數據
├── transcript              # ✅ 命令歷史
├── run/
│   ├── top_tb_compile.log  # ✅ ~20 KB，編譯日誌
│   └── random_tb_sim.log   # ✅ ~1 MB，仿真日誌
└── work/                   # ✅ 編譯庫
```

運行 `make coverage` 後，額外生成：

```
mp_scoreboard/sim/
├── coverage_report/        # ✅ HTML 報告目錄
│   └── index.html
└── coverage_summary.txt    # ✅ 文本摘要
```

---

**文檔版本**: 1.0
**最後更新**: 2025-11-06
**作者**: Claude Code
