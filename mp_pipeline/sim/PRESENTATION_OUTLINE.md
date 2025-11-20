# RISC-V Pipeline Register Renaming 實現報告
## PowerPoint 演示文稿大綱

---

## Slide 1: Title Slide

```
RISC-V Out-of-Order Pipeline
Register Renaming Implementation

姓名：[Your Name]
課程：ELEC411
日期：November 2025
```

**視覺建議:** 
- 背景：RISC-V logo或CPU架構圖
- 字體：大且清晰

---

## Slide 2: Agenda

```
目錄

1. 項目背景與動機
2. Register Renaming 基本概念
3. 架構設計
4. 實現細節
5. 調試與修復
6. 測試結果
7. 總結與未來工作
```

**視覺建議:**
- 使用編號列表
- 每項可以用不同顏色icon

---

## Slide 3: 項目背景

```
背景與動機

原始設計：
• 5-stage in-order pipeline
• 32個architectural registers
• 存在WAR和WAW hazards

目標：
✓ 實現register renaming機制
✓ 消除false dependencies
✓ 為亂序執行鋪路
✓ 提高指令級並行度（ILP）
```

**視覺建議:**
- 左側：原始架構簡圖
- 右側：目標架構簡圖
- 使用箭頭表示演進

---

## Slide 4: Register Renaming - 為什麼需要？

```
問題：False Dependencies

示例程序：
  add x1, x2, x3    # I1
  sub x4, x1, x5    # I2 (RAW - 真依賴)
  add x1, x6, x7    # I3 (WAW with I1)
  or  x8, x1, x9    # I4 (WAR with I1)

沒有Renaming:
  I3必須等I1完成 (WAW)
  I4必須等I1完成 (WAR)
  → 限制並行度！

有Renaming:
  I1: x1 → p10
  I3: x1 → p20 (不同的物理寄存器！)
  → I3和I1可以並行執行！
```

**視覺建議:**
- 使用兩列對比
- 紅色標記hazards
- 綠色標記解決方案

---

## Slide 5: Register Renaming 核心概念

```
核心機制

Architectural Registers (32個)
    ↓ 映射
Physical Registers (64個)

關鍵組件：
1. RAT (Register Alias Table)
   • 32 entries
   • 每個entry: arch reg → phys reg

2. Free List
   • FIFO隊列
   • 管理空閒物理寄存器

3. PRF (Physical Register File)
   • 64個32-bit寄存器
```

**視覺建議:**
- 中間畫一個大的映射圖
- RAT用表格形式
- Free List用隊列圖示

---

## Slide 6: 架構總覽

```
Register Renaming 架構

┌─────────────────────────────────────┐
│         DECODE STAGE                │
│                                     │
│  ┌──────────────┐  ┌──────────┐   │
│  │ RENAME_UNIT  │  │FREE_LIST │   │
│  │   (RAT)      │  │  (FIFO)  │   │
│  └──────────────┘  └──────────┘   │
│         ↓                ↓         │
│    物理寄存器號      分配/釋放      │
│         ↓                          │
│  ┌─────────────────┐               │
│  │      PRF        │               │
│  │    [0:63]       │               │
│  └─────────────────┘               │
└─────────────────────────────────────┘

數據流：
Decode → RAT查找 → PRF讀取 → Execute
                              ↓
Writeback → PRF寫入 → RAT更新 → Free List釋放
```

**視覺建議:**
- 使用流程圖
- 不同顏色區分不同階段

---

## Slide 7: RAT (Register Alias Table)

```
RAT 操作流程

初始化 (Reset):
  RAT[0] = p0
  RAT[1] = p1
  ...
  RAT[31] = p31
  (Identity mapping)

Decode查找:
  rs1_phys = RAT[rs1_arch]
  rs2_phys = RAT[rs2_arch]
  old_phys = RAT[rd_arch]

分配新物理寄存器:
  new_phys = FREE_LIST.allocate()
  (speculative, 不更新RAT)

Commit更新:
  RAT[rd_arch] = new_phys
  FREE_LIST.free(old_phys)
```

**視覺建議:**
- 展示RAT表格示例
- 用箭頭標示查找過程
- 用不同顏色標示speculative vs committed

---

## Slide 8: Free List 管理

```
Free List - FIFO Queue

初始化:
  Queue = [p1, p2, ..., p63]
  (p0保留給x0)
  head = 0, tail = 63, count = 63

分配 (Allocate):
  alloc_phys = queue[head]
  head++
  count--

釋放 (Free):
  queue[tail] = free_phys
  tail++
  count++

狀態檢查:
  alloc_valid = (count > 0)
```

**視覺建議:**
- 畫一個環形隊列圖
- 用動畫展示head/tail移動
- 標示分配和釋放操作

---

## Slide 9: 數據流示例

```
示例：add x1, x2, x3

Decode階段:
  1. 查RAT: rs1_phys=RAT[2]=p15, rs2_phys=RAT[3]=p8
  2. 讀PRF: rs1_val=PRF[p15], rs2_val=PRF[p8]
  3. 分配: new_phys=p20 (from Free List)
  4. 記錄: old_phys=RAT[1]=p10

Execute階段:
  result = rs1_val + rs2_val

Writeback階段:
  1. 寫PRF: PRF[p20] = result
  2. 更新RAT: RAT[1] = p20
  3. 釋放: FREE_LIST.free(p10)
```

**視覺建議:**
- 階段性展示，用動畫
- 每步用不同顏色高亮

---

## Slide 10: 實現 - 新增模塊

```
新增的HDL模塊

1. rename_unit.sv (100行)
   • RAT邏輯
   • Lookup和更新
   
2. free_list.sv (65行)
   • FIFO管理
   • 分配和釋放
   
3. prf.sv (37行)
   • 64個物理寄存器
   • 2讀1寫端口

總計：202行新代碼
```

**視覺建議:**
- 用圓餅圖顯示代碼分布
- 每個模塊用icon表示

---

## Slide 11: 實現 - 主要修改

```
主要修改的文件

文件              修改行數    主要內容
────────────────────────────────────────
cpu.sv              ~50     實例化新模塊、信號連接
writeback.sv        ~40     PRF寫入、commit邏輯
decode.sv           ~30     RAT lookup、PRF讀取
Forward.sv          ~20     物理寄存器號比較
execute.sv          ~10     傳遞物理寄存器號
memstage.sv         ~5      傳遞物理寄存器號
────────────────────────────────────────
總計修改：          ~155行
```

**視覺建議:**
- 橫條圖顯示各文件修改量
- 用不同顏色區分難度

---

## Slide 12: cpu.sv 修改詳解

```
cpu.sv - 頂層整合 (最複雜)

新增組件：
  rename_unit rename_unit_i(...)
  free_list free_list_i(...)
  prf prf_i(...)

新增信號：
  • rs1_phys, rs2_phys (物理寄存器號)
  • dest_phys_new, dest_phys_old
  • prf_rs1_val, prf_rs2_val (PRF讀取值)
  • alloc_valid, alloc_phys (Free List)
  • commit_we, commit_arch, commit_phys

移除：
  ❌ regfile regfile_i(...)
  (不再使用architectural register file)
```

**視覺建議:**
- 展示cpu.sv的方塊圖
- 綠色標示新增
- 紅色標示移除

---

## Slide 13: decode.sv 修改詳解

```
decode.sv - Decode階段關鍵修改

新增輸入：
  input [5:0] rs1_phys, rs2_phys      // from rename_unit
  input [5:0] dest_phys_new, dest_phys_old
  input [31:0] rs1_val, rs2_val        // from PRF

Pipeline Register傳遞：
  id_ex.rs1_phys = rs1_phys;
  id_ex.rs2_phys = rs2_phys;
  id_ex.rs1_v = rs1_val;    // 不再從regfile！
  id_ex.rs2_v = rs2_val;
  
  id_ex.dest_phys_new = dest_phys_new;
  id_ex.dest_phys_old = dest_phys_old;

提取Architectural Indices:
  id_ex.rs1_arch = imem_rdata_id[19:15];
  id_ex.rs2_arch = imem_rdata_id[24:20];
  id_ex.dest_arch = imem_rdata_id[11:7];
```

**視覺建議:**
- 展示decode.sv的輸入輸出
- 箭頭標示數據流

---

## Slide 14: writeback.sv 修改詳解

```
writeback.sv - Commit邏輯

PRF寫入：
  assign prf_we = commit && regf_we_back;
  assign prf_wr_phys = mem_wb.dest_phys_new;
  assign prf_wr_data = regfilemux_out;

Commit通知Rename Unit：
  assign commit_we = commit && (mem_wb.dest_arch != 0);
  assign commit_arch = mem_wb.dest_arch;
  assign commit_phys = mem_wb.dest_phys_new;
  assign commit_old_phys = mem_wb.dest_phys_old;

Free List釋放：
  (通過rename_unit間接實現)
  free_en = commit_we && (commit_arch != 0);
  free_phys = commit_old_phys;
```

**視覺建議:**
- 展示writeback的commit流程
- 時序圖顯示寫入和更新順序

---

## Slide 15: 調試過程 - 發現的Bug

```
調試發現的關鍵Bug

🐛 Bug #1: 不完整的Pipeline Flush
問題：只flush了部分stage
影響：Branch後錯誤指令仍commit
解決：實現完整4-stage flush (IF/ID, ID/EX, EX/MEM, MEM/WB)

🐛 Bug #2: AUIPC計算錯誤  
問題：alu_m2_sel缺少op_auipc
影響：AUIPC使用rs2而非imm
解決：將op_auipc添加到alu_m2_sel條件

結果：
  修復前: 0條指令執行
  修復後: 38條指令成功 ✅
```

**視覺建議:**
- 用紅色X標示bug
- 綠色勾標示修復
- 展示前後對比數據

---

## Slide 16: Pipeline Flush 修復

```
完整Pipeline Flush實現

修復前：
  只有decode產生flush信號
  → 其他stage的指令繼續執行 ❌

修復後：
  fetch.sv:    IF/ID flush (valid + inst)
  decode.sv:   ID/EX flush (valid)
  execute.sv:  EX/MEM flush (valid)
  memstage.sv: MEM/WB flush (valid) ⭐ 關鍵！

關鍵發現：
  commit條件 = mem_wb.valid && !freeze_stall
  → 必須flush MEM/WB，否則仍會commit！
```

**視覺建議:**
- Pipeline圖展示flush傳播
- 紅色標示未flush的stage
- 綠色標示已flush的stage

---

## Slide 17: AUIPC Bug 修復

```
AUIPC計算Bug分析

AUIPC語義：rd = PC + imm

Bug原因：
  decode.sv line 224-225:
  alu_m2_sel = (opcode in {store,load,imm,jalr}) ? 1 : 0
               ↑ 缺少op_auipc！

影響：
  alu_m2_sel = 0
  → alu_b = b_src (rs2的forwarded值)
  → AUIPC計算 PC + rs2 而不是 PC + imm ❌

修復：
  alu_m2_sel = (opcode in {AUIPC,store,load,imm,jalr}) ? 1:0
                            ↑ 添加！

結果：
  錯誤值: 0xa2499080
  正確值: 0x44594080 ✅
```

**視覺建議:**
- 代碼對比（修復前後）
- 計算流程圖

---

## Slide 18: 測試結果

```
驗證測試結果

測試環境：
  • QuestaSim/ModelSim
  • RVFI (RISC-V Formal Interface)
  • 約束隨機指令生成

進展：
  初始狀態:        0條指令 (失敗)
  Flush修復後:    34條指令
  AUIPC修復後:    38條指令 ✅
  
性能：
  IPC: ~0.69
  (合理，in-order pipeline with flush)

目標：
  長期目標: 60,000條指令
  當前狀態: 38條 (還有工作要做)
```

**視覺建議:**
- 進度條顯示38/60000
- 折線圖顯示修復進展

---

## Slide 19: 代碼統計

```
實現代碼統計

新增代碼：
  rename_unit.sv:    100行
  free_list.sv:       65行
  prf.sv:             37行
  ──────────────────────
  新模塊總計:        202行

修改代碼：
  cpu.sv:            ~50行
  writeback.sv:      ~40行
  decode.sv:         ~30行
  其他:              ~35行
  ──────────────────────
  修改總計:         ~155行

總工作量:           ~357行代碼
```

**視覺建議:**
- 堆疊條形圖
- 圓餅圖顯示比例

---

## Slide 20: 與原始設計對比

```
Register Renaming前後對比

                  原始設計    Register Renaming
────────────────────────────────────────────────
寄存器數量          32           64
寄存器文件         Regfile       PRF
映射機制           直接          RAT
物理寄存器分配      N/A         Free List
WAR Hazard         存在          消除 ✅
WAW Hazard         存在          消除 ✅
RAW Hazard         存在          存在 (真依賴)
並行潛力           有限          提高 ✅
亂序執行支持        無            準備好 ✅
硬件複雜度         簡單          中等
面積/功耗          較小          較大
```

**視覺建議:**
- 對比表格
- 勾和叉標示改進點

---

## Slide 21: 優點與代價

```
實現Trade-offs

✅ 優點：
  1. 消除False Dependencies (WAR, WAW)
  2. 提高指令級並行度
  3. 為亂序執行鋪路
  4. Forwarding邏輯更簡單
  5. 支持更多in-flight指令

⚠️ 代價：
  1. 硬件複雜度增加
     • RAT: 32 x 6-bit = 192 bits
     • Free List管理邏輯
  2. 物理寄存器數量翻倍 (32→64)
  3. 面積和功耗增加約100%
  4. 調試難度提高
  5. 需要精確的異常處理機制
```

**視覺建議:**
- 天平圖展示trade-off
- 綠色優點，黃色代價

---

## Slide 22: 文檔與資源

```
項目文檔

✓ DEBUG_SUMMARY_EN.md
  • 英文調試總結
  • 所有bug的詳細分析

✓ DEBUG_SUMMARY_ZH.md  
  • 中文調試總結
  • 完整的修復過程

✓ ARCHITECTURE_GUIDE.md
  • 16個模塊詳細說明
  • Register renaming架構
  • 數據流分析

GitHub Repository:
  github.com/Jasonliuuuu/RISC-V-OoO-Project
  Branch: rename-unit
```

**視覺建議:**
- 文檔圖標
- GitHub logo和鏈接

---

## Slide 23: 未來工作

```
下一步計劃

短期 (1-2週):
  □ 修復剩餘RVFI錯誤
  □ 達到60,000條指令執行
  □ 優化IPC性能

中期 (1個月):
  □ 實現真正的亂序執行
  □ 添加Reorder Buffer (ROB)
  □ 實現分支預測
  □ 添加Load/Store Queue

長期目標:
  □ Superscalar execution
  □ 多發射
  □ 高級優化技術
```

**視覺建議:**
- 時間軸展示
- 里程碑標記

---

## Slide 24: 經驗與收穫

```
技術收穫

1. 深入理解CPU微架構
   • Pipeline hazard處理
   • Register renaming機制
   • Out-of-order execution基礎

2. SystemVerilog設計能力
   • 大型項目管理
   • 模塊化設計
   • 信號連接管理

3. 調試技能提升
   • RVFI驗證方法
   • 手動代碼追踪
   • 系統性問題定位

4. 文檔撰寫
   • 技術文檔規範
   • 中英文技術寫作
```

**視覺建議:**
- 圖標代表不同技能
- 進度條顯示掌握程度

---

## Slide 25: 總結

```
項目總結

完成的工作 ✅：
  • 成功實現Register Renaming
  • 新增3個核心模塊 (357行代碼)
  • 修復2個關鍵bug
  • 從0到38條指令執行
  • 完整的技術文檔

技術亮點 ⭐：
  • RAT + Free List + PRF架構
  • 完整的4-stage pipeline flush
  • 準確的commit和恢復邏輯

貢獻：
  • 為亂序執行奠定基礎
  • 提供可擴展的架構
  • 詳細的實現文檔
```

**視覺建議:**
- 成就徽章
- 項目logo

---

## Slide 26: Q&A

```
Questions & Discussion

感謝聆聽！

聯絡方式：
  Email: [your-email]
  GitHub: github.com/Jasonliuuuu

項目資源：
  • 完整代碼：GitHub rename-unit branch
  • 技術文檔：sim/ARCHITECTURE_GUIDE.md
  • 調試報告：sim/DEBUG_SUMMARY_*.md
```

**視覺建議:**
- 簡潔的背景
- 聯絡信息清晰可見
- QR code鏈接到GitHub

---

## Bonus Slides (備用)

### Bonus 1: RAT詳細示例

```
RAT操作詳細示例

指令序列：
  add x1, x2, x3
  sub x4, x1, x5
  or  x1, x6, x7

初始RAT:
  x1→p10, x2→p15, x3→p8, x4→p6, x5→p12, x6→p3, x7→p9

執行過程：
  Inst1: Allocate p20 for x1
         RAT不變 (speculative)
         
  Inst2: Read p20 (forwarding from inst1)
         Allocate p21 for x4
         
  Inst1 commit: RAT[x1] = p20, free p10
  
  Inst3: Allocate p22 for x1
         
  Inst3 commit: RAT[x1] = p22, free p20
```

### Bonus 2: 性能分析

```
性能瓶頸分析

當前限制：
  1. In-order commit
     → 即使亂序執行，也必須按序commit
  
  2. 有限的物理寄存器 (64)
     → 限制in-flight指令數量
  
  3. 單發射
     → 每cycle只能發射1條指令

優化方向：
  • 增加物理寄存器到128
  • 實現真正的OoO commit (需要ROB)
  • 雙發射或四發射
```

---

## 使用說明

1. **直接使用PowerPoint:**
   - 每個Slide複製到新的PowerPoint slide
   - 根據"視覺建議"添加圖片和圖表
   
2. **使用Markdown工具:**
   - Marp, reveal.js, 或Slidev
   - 直接轉換Markdown為slides
   
3. **圖表生成:**
   - 可用draw.io, Lucidchart繪製架構圖
   - 用Excel/Google Sheets生成統計圖表

**建議時長:** 20-25分鐘演講
**總Slides數:** 26張 (含2張bonus)
