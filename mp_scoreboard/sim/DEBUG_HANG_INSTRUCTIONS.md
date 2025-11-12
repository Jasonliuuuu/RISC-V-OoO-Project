# 處理器掛起調試指南 (Processor Hang Debug Guide)

## 概述

我已經添加了全面的調試追蹤來識別處理器在指令 34 後掛起的原因。由於本地環境沒有 QuestaSim/ModelSim 工具，請在您的服務器（jade、zorite 或 agate）上運行模擬。

## 已添加的調試追蹤

### 1. Scoreboard 監控 (`scoreboard.sv`)
- **每 1000 個週期輸出一次**狀態摘要：
  - 指令隊列狀態（空/滿）
  - Issue 條件（can_issue、target_fu、WAW hazard）
  - 所有功能單元的忙碌狀態
  - 下一條待發射的指令信息

- **死鎖檢測**：
  - 如果超過 10000 個週期沒有指令完成，輸出錯誤警告
  - 顯示指令隊列和功能單元的狀態

### 2. Load/Store FU 監控 (`fu_load_store.sv`)
- **狀態轉換追蹤**：每次狀態改變時輸出
- **內存等待監控**：
  - 如果在 MEM_ACCESS 狀態等待 `dmem_resp` 超過 100 個週期，每 100 週期輸出一次警告
  - 顯示操作碼、地址、讀/寫掩碼

### 3. Fetch 階段監控 (`fetch.sv`)
- **指令隊列滿阻塞**：
  - 如果因隊列滿而阻塞超過 100 個週期，每 100 週期輸出一次
  - 顯示當前 PC 和等待的指令

- **內存響應等待**：
  - 如果等待 `imem_resp` 超過 1000 個週期，每 1000 週期輸出一次
  - 顯示當前 PC

## 運行步驟

### 1. 確保使用最新代碼

```bash
git checkout claude/setup-validation-environment-011CUoUBBDxkSBpcknCMqjhw
git pull origin claude/setup-validation-environment-011CUoUBBDxkSBpcknCMqjhw
```

### 2. 清理並運行模擬

```bash
cd mp_scoreboard/sim
make clean
make run_random 2>&1 | tee debug_output.log
```

**注意**：模擬會超時掛起，這是預期的。我們需要調試輸出。

### 3. 查看調試輸出

模擬結束後（或在超時前按 Ctrl+C），檢查關鍵信息：

```bash
# 查看 Scoreboard 的週期狀態
grep "DEBUG SCOREBOARD" debug_output.log | tail -20

# 查看 Load/Store FU 的等待狀態
grep "DEBUG LS_FU" debug_output.log | tail -20

# 查看 Fetch 階段的阻塞狀態
grep "DEBUG FETCH" debug_output.log | tail -20

# 查看死鎖檢測信息
grep "ERROR" debug_output.log
```

## 預期的調試輸出格式

### Scoreboard 輸出示例：
```
[DEBUG SCOREBOARD] @50000000 Cycle 1000:
  IQ: empty=0, full=0, deq_en=1
  Issue: can_issue=1, target_fu=2, waw_hazard=0
  FU Busy: [0]=1 [1]=0 [2]=1 [3]=0 [4]=0 [5]=0
  Next Inst: pc=60000088, inst=00052283, opcode=0000011
```

### Load/Store FU 輸出示例：
```
[DEBUG LS_FU] @50000000 State: IDLE -> ADDR_CALC
[DEBUG LS_FU] @50010000 State: ADDR_CALC -> MEM_ACCESS
[DEBUG LS_FU] @55000000 Waiting for dmem_resp for 500 cycles
  opcode=0000011, addr=10000004, rmask=1111, wmask=0000
```

### Fetch 輸出示例：
```
[DEBUG FETCH] @50000000 IQ full, stalled for 200 cycles
  PC=60000090, waiting inst=00a12023
```

## 關鍵診斷問題

基於調試輸出，我們可以診斷出：

### 情況 1：指令隊列滿且永不排空
**症狀**：
- Fetch 顯示 "IQ full, stalled"
- Scoreboard 顯示 "IQ: empty=0, full=1, deq_en=0"
- 所有 FU 可能忙碌

**原因**：Scoreboard 無法發射指令（WAW hazard 或無可用 FU）

### 情況 2：Load/Store 卡在等待內存響應
**症狀**：
- Load/Store FU 顯示 "Waiting for dmem_resp"
- FU[4] 或 FU[5] 一直忙碌
- CDB 沒有新的完成信號

**原因**：內存接口問題或內存模型錯誤

### 情況 3：所有 FU 忙碌但沒有完成
**症狀**：
- Scoreboard 顯示所有 FU busy
- 沒有 CDB 廣播（cdb_valid=0）
- 觸發死鎖檢測

**原因**：某個 FU 卡住，無法完成或釋放資源

### 情況 4：WAW Hazard 阻止發射
**症狀**：
- Scoreboard 顯示 "waw_hazard=1"
- 指令隊列不為空但無法發射
- 某個 FU 忙碌且目標寄存器衝突

**原因**：RAT 更新邏輯問題或 FU 完成但未清除狀態

## 提供給我的信息

請提供以下信息，這樣我可以分析根本原因：

1. **完整的調試日誌**：
   ```bash
   # 將完整日誌壓縮（如果太大）
   tail -2000 debug_output.log > debug_tail.log
   ```

2. **關鍵摘要**：
   ```bash
   echo "=== Scoreboard Status ===" > debug_summary.txt
   grep "DEBUG SCOREBOARD" debug_output.log | tail -10 >> debug_summary.txt

   echo "=== Load/Store FU ===" >> debug_summary.txt
   grep "DEBUG LS_FU" debug_output.log >> debug_summary.txt

   echo "=== Fetch Stage ===" >> debug_summary.txt
   grep "DEBUG FETCH" debug_output.log >> debug_summary.txt

   echo "=== Errors ===" >> debug_summary.txt
   grep "ERROR" debug_output.log >> debug_summary.txt

   cat debug_summary.txt
   ```

3. **最後幾條完成的指令**：
   ```bash
   tail -50 commit.log
   ```

## 下一步

一旦我收到調試輸出，我將：
1. 識別確切的卡住位置（Fetch、IQ、Scoreboard、FU 或內存）
2. 定位根本原因代碼
3. 實施修復
4. 驗證處理器可以完成所有 60,000 條指令

## 快速測試命令

如果您想快速檢查掛起位置，運行：

```bash
cd mp_scoreboard/sim
make clean
timeout 60s make run_random 2>&1 | tee quick_debug.log
grep -E "DEBUG|ERROR|RVFI" quick_debug.log | tail -100
```

這將在 60 秒後超時並顯示最後 100 行調試信息。
