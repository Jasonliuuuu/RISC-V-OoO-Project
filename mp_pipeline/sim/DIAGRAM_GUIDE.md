# PowerPoint 图表制作指南

## 图表1: Register Renaming 总体架构
**用于：Slide 6**

### 布局：
```
使用SmartArt或形状：

┌─────────────────────────────────────────────────────┐
│              DECODE STAGE                           │
│                                                     │
│  ┌─────────────────┐      ┌──────────────┐        │
│  │  RENAME UNIT    │      │  FREE LIST   │        │
│  │     (RAT)       │◄─────┤   (FIFO)     │        │
│  │  32 entries:    │      │ 63 physical  │        │
│  │  arch → phys    │      │  registers   │        │
│  └────────┬────────┘      └──────────────┘        │
│           │                                        │
│           ▼                                        │
│  ┌──────────────────────────┐                     │
│  │    PRF (Physical         │                     │
│  │    Register File)        │                     │
│  │    64 × 32-bit          │                     │
│  └──────────────────────────┘                     │
└─────────────────────────────────────────────────────┘
          │
          ▼
    到 Execute Stage
```

**颜色方案：**
- RENAME UNIT: 蓝色 (#4A90E2)
- FREE LIST: 绿色 (#7ED321)
- PRF: 橙色 (#F5A623)

**箭头标签：**
1. Instruction → RENAME: "rs1_arch, rs2_arch, rd_arch"
2. RENAME → PRF: "rs1_phys, rs2_phys"
3. PRF → Execute: "rs1_val, rs2_val"
4. Writeback → RENAME: "Commit Update"
5. Writeback → FREE LIST: "Free old_phys"

---

## 图表2: Pipeline Flush 示意图
**用于：Slide 16**

### 制作方法（PowerPoint）：
1. 插入5个圆角矩形，横向排列
2. 在第4个矩形(MEM)上添加红色爆炸形状标"BRANCH!"
3. 在每两个矩形之间添加红色X和"FLUSH"标签

```
┌────┐  X   ┌────┐  X   ┌────┐  X   ┌────┐  X   ┌────┐
│ IF │FLUSH │ ID │FLUSH │ EX │FLUSH │MEM │FLUSH │ WB │
│    │      │    │      │    │      │ ⚡ │      │    │
└────┘      └────┘      └────┘      └────┘      └────┘
             ▲           ▲           ▲           ▲
             └───────────┴───────────┴───────────┘
                  flush_pipeline signal
```

**标签：**
- IF→ID: "if_id.valid = 0"
- ID→EX: "id_ex.valid = 0"
- EX→MEM: "ex_mem.valid = 0"
- MEM→WB: "mem_wb.valid = 0 ⭐CRITICAL!"

**颜色：**
- 矩形: 淡蓝、淡绿、淡黄、淡橙、淡紫
- FLUSH标记: 红色
- 信号箭头: 深红色

---

## 图表3: RAT 操作流程
**用于：Slide 7-8**

### 三栏布局：

```
┌──────────────────┐  ┌──────────────┐  ┌──────────────────┐
│  DECODE          │  │  EXECUTE     │  │  COMMIT          │
│  ─────────       │  │  ────────    │  │  ───────         │
│                  │  │              │  │                  │
│  Lookup RAT:     │  │  Compute:    │  │  Write PRF:      │
│  rs1→p15        │  │              │  │  PRF[p20]=result │
│  rs2→p8         │➜│  result =    │➜│                  │
│  rd→p10 (old)   │  │  PRF[15] +   │  │  Update RAT:     │
│                  │  │  PRF[8]      │  │  RAT[1]=p20     │
│  Allocate:       │  │              │  │                  │
│  new=p20        │  │              │  │  Free:           │
│                  │  │              │  │  old p10→FL     │
└──────────────────┘  └──────────────┘  └──────────────────┘
```

**制作建议：**
- 用SmartArt的"过程"模板
- 三个框用蓝→绿→橙渐变
- 箭头用粗黑线

---

## 图表4: 调试进展柱状图
**用于：Slide 18**

### 数据：
| 状态 | 指令数 | 颜色 |
|------|--------|------|
| Initial | 0 | 红色 |
| After Flush Fix | 34 | 黄色 |
| After AUIPC Fix | 38 | 绿色 |

### PowerPoint制作：
1. 插入 → 图表 → 柱状图
2. 输入上述数据
3. 添加数据标签
4. 在柱子上方添加箭头和文字：
   - "+34 (Flush logic)"
   - "+4 (AUIPC fix)"

---

## 图表5: Before/After 对比表
**用于：Slide 20**

### Excel/PowerPoint表格：

| 特性 | 原始设计 | Register Renaming |
|------|----------|-------------------|
| 寄存器数量 | 32 | 64 ✅ |
| 寄存器文件 | ARF | PRF |
| 映射机制 | 直接 | RAT |
| WAR Hazard | ❌ 存在 | ✅ 消除 |
| WAW Hazard | ❌ 存在 | ✅ 消除 |
| RAW Hazard | 存在 | 存在 |
| 并行度 | 有限 | ✅ 提高 |
| OoO支持 | ❌ 无 | ✅ 准备好 |
| 复杂度 | 简单 | 中等 |
| 面积/功耗 | 较低 | 较高 |

**格式化：**
- 左列灰色背景
- 右列绿色背景（淡）
- 使用✅和❌符号
- 交替行颜色

---

## 图表6: 代码统计 - 饼图
**用于：Slide 19**

### 新增模块（饼图）：
- rename_unit.sv: 100行 (49%) - 蓝色
- free_list.sv: 65行 (32%) - 绿色
- prf.sv: 37行 (18%) - 橙色
- 总计标签: "202 lines"

### 修改文件（横条图）：
```
cpu.sv        ████████████████████ 50
writeback.sv  ████████████████ 40
decode.sv     ████████████ 30
Forward.sv    ████████ 20
execute.sv    ████ 10
memstage.sv   ██ 5
```

---

## 图表7: 简单的数据流动画
**用于：多个slides**

### 用PowerPoint动画：
1. 创建带箭头的流程图
2. 添加"路径"动画
3. 箭头沿着路径移动
4. 配合讲解时间

示例流程：
```
Instruction
    ↓
Decode + RAT Lookup
    ↓
PRF Read
    ↓
Execute
    ↓
Writeback + Commit
    ↓
RAT Update + Free
```

---

## 制作工具推荐

### 在线工具（免费）：
1. **draw.io** (diagrams.net)
   - 专业流程图
   - 导出PNG/SVG
   
2. **Excalidraw**
   - 手绘风格图表
   - 简单直观

3. **Google Slides**
   - 协作编辑
   - 自动保存

### PowerPoint技巧：
1. **SmartArt**
   - 插入 → SmartArt
   - 选择"流程"或"关系"

2. **图标**
   - 插入 → 图标
   - 搜索"CPU", "chip", "database"

3. **对齐工具**
   - 选中多个对象
   - 格式 → 对齐 → 居中对齐

4. **配色方案**
   ```
   主色：#4A90E2 (蓝)
   辅色：#7ED321 (绿)
   强调：#F5A623 (橙)
   警告：#D0021B (红)
   背景：#FFFFFF (白)
   ```

---

## 快速制作步骤

### 10分钟快速版：
1. 使用PowerPoint内置SmartArt
2. 只做3个关键图：
   - 架构总览（Slide 6）
   - Pipeline Flush（Slide 16）
   - 进展柱状图（Slide 18）

### 30分钟完整版：
1. 所有7个图表都制作
2. 使用统一配色
3. 添加动画效果

### 专业版（1小时）：
1. 使用draw.io制作矢量图
2. 导出高清PNG
3. 在PowerPoint中添加动画
4. 统一字体和配色

---

## 示例slide建议

**Slide 6 - 架构图：**
- 占据整个slide的80%
- 简单标题在顶部
- 图表居中，四周留白

**Slide 16 - Pipeline Flush：**
- 图表占50%
- 下方留空间给bullet points说明

**Slide 18 - 数据：**
- 左侧柱状图（60%）
- 右侧bullet points总结（40%）
