# 硬體驗證環境 (`hvl`)

此目錄包含了所有用於測試 RISC-V 處理器核心的硬體驗證語言 (Hardware Verification Language, HVL) 檔案。

本驗證環境採用了業界標準的**受約束隨機驗證 (Constrained Random Verification, CRV)** 方法，並透過 **RISC-V 驗證介面 (RISC-V Verification Interface, RVFI)** 與一個黃金參考模型 (Golden Reference Model) 進行比對，以確保處理器設計的正確性。

## 檔案結構與說明

以下是 `hvl` 目錄中各個關鍵檔案的角色說明：

### 測試平台 (Testbench) 核心
* `top_tb.sv`: **頂層測試平台**。這是整個模擬的進入點，負責實例化 DUT (待測設計，也就是 `cpu`)、記憶體模型、監視器 (Monitor)，並產生時脈 (clock) 和重置 (reset) 訊號。
* `random_tb.sv`: **隨機測試產生器**。這不僅僅是一個記憶體模型，更是測試的核心驅動者。它負責向 CPU 的指令和資料埠提供隨機生成的指令，並包含兩個主要的測試階段。
* `randinst.svh`: **隨機指令類別**。定義了一個名為 `RandInst` 的 SystemVerilog `class`。這是隨機化的心臟，使用**約束 (constraints)** 來產生所有符合 RISC-V 規格的指令。
* `instr_cg.svh`: **功能覆蓋率模型**。定義了一個 `covergroup`，用來追蹤和記錄在隨機測試過程中，哪些指令類型、操作碼和運算元組合已經被測試過，幫助我們評估測試的完備性。

### 正確性比對與監視 (Checker & Monitor)
* `monitor.sv`: **監視器**。此模組透過 `mon_itf` 連接到 DUT 的 RVFI 埠，負責捕獲每一條被執行的指令的詳細資訊，並計算 IPC 等效能指標。
* `rvfimon.v`: **RISC-V 黃金參考模型**。這是一個由 RISC-V Formal 專案產生的 Verilog 模型。給定一條指令及其運算元，它能計算出**正確的**執行結果。`monitor.sv` 會將 DUT 的實際輸出與此模型的預期輸出進行比對。
* `rvfi_reference.svh` / `rvfi_reference.json`: **RVFI 連接器**。這兩個檔案定義了如何將 DUT 的 `writeback` 階段的訊號連接到監視器的 RVFI 介面上。`.json` 檔案被一個 Python 腳本用來自動產生 `.svh` 檔案中的連接邏輯。

### 介面 (Interfaces)
* `mem_itf.sv`: 定義了 CPU 和記憶體之間的通訊訊號束 (bundle)。
* `mon_itf.sv`: 定義了 RVFI 的訊號束，用於連接 DUT 和 `monitor.sv`。

### 備用記憶體模型
* `magic_dual_port.sv`: 一個理想的、零延遲的雙埠記憶體模型，用於早期功能驗證。
* `ordinary_dual_port.sv`: 一個更接近真實的記憶體模型，模擬了存取延遲和簡單的快取行為。

---

## 驗證策略

本測試平台的驗證流程主要分為三個部分：

### 1. 測試向量產生 (Test Generation)

測試由 `random_tb.sv` 主導，分為兩個階段：

* **階段一：暫存器初始化 (`init_register_state`)**
    在測試開始時，會先產生 32 條 `LUI` 指令，依序寫入 `x0` 至 `x31` 暫存器。這確保了在隨機測試開始前，所有暫存器都含有隨機的初始值，使後續的計算指令更有意義。

* **階段二：隨機指令流 (`run_random_instrs`)**
    初始化完成後，測試平台會進入一個長達數萬次的迴圈。在每一次迴圈中，它都會呼叫 `gen.randomize()` 來產生一條全新的、符合 `randinst.svh` 中所有約束的隨機指令，並將其送入 CPU。

### 2. 結果比對 (Response Checking)

驗證的核心在於比對。

1.  DUT (`cpu`) 在每條指令執行完畢後，會透過 **RVFI** 介面 (`mon_itf`) 輸出該指令的執行細節（例如寫回哪個暫存器、寫回什麼值、下一個 PC 是多少等）。
2.  `monitor.sv` 會捕獲這些來自 DUT 的實際結果。
3.  同時，`monitor.sv` 也會將相同的指令資訊送給 `rvfimon.v` (黃金模型) 進行運算。
4.  最後，`monitor.sv` 會比對 **DUT 的實際結果** 與 **黃金模型的預期結果**。如果不一致，就會報錯。

### 3. 功能覆蓋率收集 (Functional Coverage)

在 `randomize()` 被呼叫的同時，`instr_cg.svh` 中的 `covergroup` 會被觸發取樣 (`sample`)。模擬結束後，可以產生覆蓋率報告，讓我們清楚地看到：
* 哪些指令**已經被**充分測試。
* 哪些指令或指令組合**從未出現過**，代表測試存在漏洞。

這為我們提供了數據化的指標來評估隨機測試的品質，並指導我們如何調整約束以彌補測試的不足。