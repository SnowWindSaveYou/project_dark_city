# 暗面都市 — 剧情与线索系统 策划指南

> 本文档面向策划，介绍如何通过编辑配置文件来管理游戏的剧情事件、线索收集、NPC 对话和章节推进。
> **所有剧情内容都在一个 JSON 文件中**，无需修改代码。

---

## 目录

1. [系统总览](#1-系统总览)
2. [配置文件位置](#2-配置文件位置)
3. [核心概念](#3-核心概念)
4. [章节 (chapters)](#4-章节-chapters)
5. [线索定义 (clues)](#5-线索定义-clues)
6. [剧情事件 (plot_events)](#6-剧情事件-plot_events)
7. [线索事件 (clue_events)](#7-线索事件-clue_events)
8. [暗世界线索事件 (dark_clue_events)](#8-暗世界线索事件-dark_clue_events)
9. [NPC 对话 (npc_dialogues)](#9-npc-对话-npc_dialogues)
10. [条件系统详解](#10-条件系统详解)
11. [Flag 机制详解](#11-flag-机制详解)
12. [事件选择机制 (权重随机)](#12-事件选择机制-权重随机)
13. [完整工作流程](#13-完整工作流程)
14. [常见问题](#14-常见问题)

---

## 1. 系统总览

```
┌─────────────────────────────────────────────────┐
│              story_config.json                  │
│                                                 │
│  chapters ──── 章节定义 & 解锁条件              │
│  clues ─────── 线索定义 (名称/描述/分类/图标)   │
│  plot_events ─ 翻牌「剧情」时触发的事件池       │
│  clue_events ─ 翻牌「线索」时触发的事件池       │
│  dark_clue_events ─ 暗世界探索中的线索事件池    │
│  npc_dialogues ─── NPC 对话组 (条件分支)        │
│                                                 │
└──────────────┬──────────────────────────────────┘
               │ 运行时加载
               ▼
┌─────────────────────────────────────────────────┐
│            StoryManager (代码层)                 │
│                                                 │
│  flags{} ────── 全局状态标记 (flag 字典)        │
│  collected_clues[] ── 已收集线索列表            │
│  current_chapter ──── 当前章节 ID               │
│                                                 │
│  ● 条件求值  → 判断事件/对话是否可触发          │
│  ● 权重随机  → 从可用事件中选一个               │
│  ● 效果应用  → 设置 flag + 收集线索             │
│                                                 │
└─────────────────────────────────────────────────┘
```

**核心循环**: 玩家翻牌/探索 → 系统筛选满足条件的事件 → 按权重随机选一个 → 显示文本 → 设置 flag + 收集线索 → 下次筛选时条件变化 → 新事件解锁

---

## 2. 配置文件位置

```
godot/data/story_config.json
```

用任意文本编辑器打开即可编辑。修改后保存，重新运行游戏即可生效。

**JSON 格式注意事项**:
- 字符串用双引号 `"text"` 
- 最后一个元素后面**不要**加逗号
- 可以用 VS Code 等编辑器的 JSON 格式化功能检查语法

---

## 3. 核心概念

| 概念 | 说明 | 举例 |
|------|------|------|
| **Flag** | 全局布尔/值标记，记录玩家的进度状态 | `"found_photo": true` |
| **线索 (Clue)** | 可收集的信息碎片，有分类和描述 | `"clue_old_photo"` |
| **条件 (Condition)** | 判断某事件是否可触发的逻辑表达式 | `{ "flag": "found_photo" }` |
| **权重 (Weight)** | 事件被选中的相对概率 | weight=15 比 weight=10 更容易被选中 |
| **章节 (Chapter)** | 剧情进度阶段 | `"prologue"`, `"chapter1"` |

---

## 4. 章节 (chapters)

章节定义了剧情的大阶段。

```json
"chapters": {
    "prologue": {
        "name": "序章：迷雾降临",
        "unlock": null
    },
    "chapter1": {
        "name": "第一章：失踪者的痕迹",
        "unlock": { "flag": "prologue_done" }
    },
    "chapter2": {
        "name": "第二章：暗面之下",
        "unlock": { "all": [{ "flag": "chapter1_done" }, { "min_clues": 5 }] }
    }
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `键名` (如 `"prologue"`) | string | 章节 ID，代码中引用的唯一标识 |
| `name` | string | 显示名称 |
| `unlock` | condition 或 null | 解锁条件。null = 初始解锁 |

**如何触发章节切换**: 在事件的 `set_flags` 中设置特殊键 `"current_chapter"`:
```json
{
    "set_flags": { "current_chapter": "chapter1" }
}
```

### 添加新章节

1. 在 `chapters` 中添加新的键值对
2. 在某个事件的 `set_flags` 中加入 `"current_chapter": "新章节ID"`
3. 确保 `unlock` 条件在逻辑上可达

---

## 5. 线索定义 (clues)

线索是玩家在游戏中收集到的信息碎片，会显示在线索日志面板中。

```json
"clues": {
    "clue_old_photo": {
        "name": "泛黄照片",
        "desc": "一张模糊的合影，背面写着一个日期。照片中的人面容模糊，但似乎都穿着某种制服。",
        "category": "人物",
        "icon": "📷"
    }
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `键名` (如 `"clue_old_photo"`) | string | 线索 ID，在事件中通过 `clue_id` 引用 |
| `name` | string | 线索名称，显示在线索日志中 |
| `desc` | string | 线索描述文本 |
| `category` | string | 分类标签，用于线索日志的分类 Tab |
| `icon` | string | 显示图标 (Emoji) |

### 目前使用的分类

| 分类 | 说明 | 
|------|------|
| 人物 | 与特定人物相关的线索 |
| 现场 | 现场发现的物证 |
| 文献 | 文字记录、日记等 |
| 遗物 | 神秘物品、符文等 |

> 分类名称可以自由定义，系统会自动收集所有出现过的分类生成 Tab 标签。

### 添加新线索

1. 在 `clues` 中添加新条目，填写 name/desc/category/icon
2. 记住线索 ID（键名），后续在事件中引用
3. 在某个事件中设置 `"clue_id": "你的线索ID"`

---

## 6. 剧情事件 (plot_events)

玩家翻开「剧情牌」时，从该事件池中选择一个触发。

```json
"plot_events": [
    {
        "id": "plot_find_photo",
        "condition": { "not_flag": "found_photo" },
        "weight": 15,
        "text": "一张泛黄的照片从缝隙中滑落。照片背面有人匆匆写下了一行字——'他们知道了'。",
        "set_flags": { "found_photo": true },
        "clue_id": "clue_old_photo"
    }
]
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | string | 是 | 事件唯一标识 (仅用于调试/排查) |
| `condition` | condition 或 null | 是 | 触发条件。null = 无条件，总是候选 |
| `weight` | int | 是 | 权重值，越大被选中概率越高 |
| `text` | string | 是 | 显示给玩家的文本 |
| `set_flags` | object | 是 | 触发后设置的 flag，`{}` 表示无 |
| `clue_id` | string 或 null | 是 | 附带的线索 ID，null = 不附带线索 |

### 设计技巧

- **一次性事件**: 用 `not_flag` 条件 + `set_flags` 标记已触发
  ```json
  "condition": { "not_flag": "found_photo" },
  "set_flags": { "found_photo": true }
  ```
  → 找到照片后此事件不再出现

- **后续事件**: 用 `flag` 条件引用前置事件设置的 flag
  ```json
  "condition": { "flag": "found_symbol" }
  ```
  → 只有找到符文后才会出现

- **兜底事件**: `condition: null` + 较低 weight，保证总有内容
  ```json
  "condition": null,
  "weight": 8,
  "text": "你注意到一个不寻常的细节..."
  ```

---

## 7. 线索事件 (clue_events)

玩家翻开「线索牌」时，从该事件池中选择一个触发。结构与 plot_events 完全相同。

```json
"clue_events": [
    {
        "id": "clue_blood_trail",
        "condition": { "not_flag": "found_blood" },
        "weight": 12,
        "text": "你在角落发现了干涸的血迹...",
        "clue_id": "clue_blood_stain",
        "set_flags": { "found_blood": true }
    }
]
```

> plot_events 和 clue_events 的区别仅在于**由哪种牌触发**，数据格式完全一样。

---

## 8. 暗世界线索事件 (dark_clue_events)

玩家在暗世界探索中发现「线索」时触发。结构同上。

```json
"dark_clue_events": [
    {
        "id": "dark_clue_tape",
        "condition": { "not_flag": "found_tape" },
        "weight": 12,
        "text": "你在暗世界的角落发现了一卷老式磁带...",
        "clue_id": "clue_audio_tape",
        "set_flags": { "found_tape": true }
    }
]
```

---

## 9. NPC 对话 (npc_dialogues)

每个 NPC 可以有多组对话，系统会根据条件自动选择最匹配的一组。

```json
"npc_dialogues": {
    "nekomata": [
        {
            "condition": null,
            "lines": [
                { "speaker": "双尾猫妖", "text": "喵~你也迷路了吗？" },
                { "speaker": "双尾猫妖", "text": "小心那些飘来飘去的家伙..." }
            ]
        },
        {
            "condition": { "min_clues": 2 },
            "lines": [
                { "speaker": "双尾猫妖", "text": "喵？你身上的气息变了..." }
            ]
        },
        {
            "condition": { "flag": "found_symbol" },
            "lines": [
                { "speaker": "双尾猫妖", "text": "你看到那些符号了？喵..." }
            ]
        }
    ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `键名` (如 `"nekomata"`) | string | NPC ID，代码中引用的标识 |
| `condition` | condition 或 null | 该对话组的触发条件 |
| `lines` | array | 对话内容列表 |
| `lines[].speaker` | string | 说话者名称 (显示名) |
| `lines[].text` | string | 对话文本 |

### 对话选择规则

**从数组末尾往前匹配**，选中第一个满足条件的对话组。

这意味着：
- **越靠后的对话优先级越高**
- `condition: null` 的对话放在**最前面**作为默认兜底
- 越特殊/越后期的对话放在**越后面**

```
数组位置:  [0]默认对话  [1]收集2线索后  [2]找到符文后
匹配方向:  ←──────────────────────────── 从后往前检查
```

举例：如果玩家同时满足 `min_clues: 2` 和 `flag: found_symbol`，会选择 `[2]`（靠后的那个）。

### 添加新 NPC

1. 在 `npc_dialogues` 中添加新的键值对
2. NPC ID 需要与代码中的 NPC 类型标识对应
3. 至少提供一组 `condition: null` 的默认对话

### 现有 NPC ID

| ID | 名称 | 说明 |
|----|------|------|
| `nekomata` | 双尾猫妖 | 友好向导，提供线索提示 |
| `ghost_girl` | 幽灵娘 | 神秘角色，暗示背景故事 |
| `faceless` | 无脸商人 | 商店NPC，有隐藏剧情 |
| `mask_user` | 面具使 | 提供深层剧情信息 |

---

## 10. 条件系统详解

条件 (condition) 是整个系统的核心，用于控制事件、对话、章节的触发时机。

### 基础条件

| 条件类型 | 格式 | 含义 | 示例 |
|---------|------|------|------|
| 无条件 | `null` | 总是满足 | `"condition": null` |
| Flag 存在 | `{ "flag": "key" }` | 该 flag 已设置且非 false | `{ "flag": "found_photo" }` |
| Flag 不存在 | `{ "not_flag": "key" }` | 该 flag 未设置或为 false | `{ "not_flag": "found_photo" }` |
| Flag 等于值 | `{ "flag_eq": ["key", value] }` | flag 值等于指定值 | `{ "flag_eq": ["trust_level", 3] }` |
| 拥有线索 | `{ "has_clue": "id" }` | 已收集该线索 | `{ "has_clue": "clue_old_photo" }` |
| 最少线索数 | `{ "min_clues": N }` | 已收集线索数 >= N | `{ "min_clues": 3 }` |
| 最少天数 | `{ "min_day": N }` | 当前游戏天数 >= N | `{ "min_day": 2 }` |

### 组合条件

| 类型 | 格式 | 含义 |
|------|------|------|
| 全部满足 (AND) | `{ "all": [条件1, 条件2, ...] }` | 所有子条件都为真 |
| 任一满足 (OR) | `{ "any": [条件1, 条件2, ...] }` | 至少一个子条件为真 |

### 组合示例

```json
// 需要完成第一章 且 收集至少5个线索
{
    "all": [
        { "flag": "chapter1_done" },
        { "min_clues": 5 }
    ]
}

// 找到照片 或 找到日记 (任一即可)
{
    "any": [
        { "flag": "found_photo" },
        { "flag": "found_diary" }
    ]
}

// 复杂组合: 第2天之后 且 (找到符文 或 收集了3个线索)
{
    "all": [
        { "min_day": 2 },
        { "any": [
            { "flag": "found_symbol" },
            { "min_clues": 3 }
        ]}
    ]
}
```

### 多条件简写

在同一个对象中写多个基础条件，等价于 `all`:

```json
// 以下两种写法等价:
{ "min_day": 2, "not_flag": "found_diary" }
// 等价于
{ "all": [{ "min_day": 2 }, { "not_flag": "found_diary" }] }
```

> 注意：同一对象中不能有两个同类型条件（如两个 `flag`），此时必须用 `all` 数组。

---

## 11. Flag 机制详解

Flag 是系统的"记忆"，记录玩家的所有进度状态。

### Flag 的生命周期

```
事件触发 → set_flags → Flag 写入 → 条件引用 → 影响后续事件
```

### 常用模式

**模式 1: 一次性事件锁**
```json
{
    "condition": { "not_flag": "found_photo" },
    "set_flags": { "found_photo": true }
}
```
效果: 第一次触发后设置 flag，之后不再满足条件

**模式 2: 前置依赖链**
```json
// 事件A: 发现符文
{ "set_flags": { "found_symbol": true } }

// 事件B: 需要先发现符文
{ "condition": { "flag": "found_symbol" } }

// 事件C: 需要A和B都完成
{ "condition": { "all": [{ "flag": "found_symbol" }, { "flag": "symbol_trail" }] } }
```

**模式 3: 章节切换**
```json
{
    "set_flags": { 
        "prologue_done": true,
        "current_chapter": "chapter1"
    }
}
```
`current_chapter` 是特殊键，会自动触发章节切换。

### Flag 命名建议

| 前缀 | 用途 | 示例 |
|------|------|------|
| `found_` | 发现了某物 | `found_photo`, `found_symbol` |
| `met_` | 遇到了某人 | `met_ghost_girl` |
| `done_` / `_done` | 完成了某事 | `prologue_done` |
| `know_` | 知道了某信息 | `know_truth` |
| `has_` | 拥有某物 | `has_key` |
| `count_` | 计数类 | `count_visits` |

### 注意事项

- Flag 在一次游玩中持续存在，直到「开始新游戏」时重置
- Flag 可以存任意类型的值 (布尔、数字、字符串)，但通常用布尔 `true`
- 存档/读档会保留所有 Flag 状态

---

## 12. 事件选择机制 (权重随机)

当玩家触发某个事件池（如翻剧情牌）时，系统的选择流程:

```
第一步: 条件过滤
  遍历事件池中所有事件
  剔除 condition 不满足的事件
  得到候选列表

第二步: 加权随机
  根据各事件的 weight 值进行加权随机抽取
  weight 越大 → 被选中的概率越高
  
第三步: 执行效果
  显示选中事件的 text
  执行 set_flags
  收集 clue_id 对应的线索
```

### 权重概率计算

假设有 3 个候选事件:

| 事件 | weight | 实际概率 |
|------|--------|---------|
| A | 10 | 10/(10+15+8) = 30.3% |
| B | 15 | 15/(10+15+8) = 45.5% |
| C | 8  | 8/(10+15+8) = 24.2% |

### 权重设计建议

| weight 范围 | 建议用途 |
|------------|---------|
| 5-8 | 兜底/氛围事件，出现频率低 |
| 10 | 标准事件 |
| 12-15 | 重要剧情/线索事件，希望玩家更容易触发 |
| 20+ | 关键节点事件，高概率触发 |

---

## 13. 完整工作流程

### 添加一条新的剧情线

以"添加一个关于地下室密室的剧情线"为例:

#### 步骤 1: 定义相关线索

```json
// 在 "clues" 中添加
"clue_secret_room_key": {
    "name": "生锈钥匙",
    "desc": "一把锈迹斑斑的铜钥匙，上面刻着一个奇怪的数字。",
    "category": "遗物",
    "icon": "🔑"
},
"clue_secret_room_note": {
    "name": "密室便条",
    "desc": "地下密室中发现的便条：'实验在此进行。代号：暗面计划。'",
    "category": "文献",
    "icon": "📝"
}
```

#### 步骤 2: 创建发现钥匙的事件

```json
// 在 "plot_events" 或 "clue_events" 中添加
{
    "id": "plot_find_key",
    "condition": { "not_flag": "found_key" },
    "weight": 12,
    "text": "一把锈迹斑斑的钥匙从墙壁裂缝中掉了出来，上面似乎刻着什么……",
    "set_flags": { "found_key": true },
    "clue_id": "clue_secret_room_key"
}
```

#### 步骤 3: 创建发现密室的后续事件

```json
{
    "id": "plot_secret_room",
    "condition": { "flag": "found_key" },
    "weight": 15,
    "text": "你用那把钥匙打开了一扇隐藏的门。里面是一间布满灰尘的密室，桌上留着一张便条……",
    "set_flags": { "entered_secret_room": true },
    "clue_id": "clue_secret_room_note"
}
```

#### 步骤 4: 让 NPC 对此做出反应

```json
// 在某个 NPC 的对话数组末尾添加（放在最后 = 高优先级）
{
    "condition": { "flag": "entered_secret_room" },
    "lines": [
        { "speaker": "面具使", "text": "你找到了那个地方……" },
        { "speaker": "面具使", "text": "那里曾经是一切的起点。" }
    ]
}
```

#### 步骤 5: 验证

- 保存 JSON 文件
- 运行游戏
- 翻牌直到触发钥匙事件
- 再翻牌触发密室事件
- 去暗世界找 NPC 确认对话变化
- 打开线索日志确认新线索已收录

---

## 14. 常见问题

### Q: 为什么某个事件一直不出现？

**检查 condition**: 可能条件不满足。确认需要的 flag 是否已被其他事件设置。

**检查 weight**: 权重太低可能被其他事件"压"住。提高 weight 或降低竞争事件的 weight。

**检查 not_flag**: 如果用了一次性锁，确认该 flag 还未被设置。

### Q: 为什么 NPC 对话没有变化？

NPC 对话从数组**末尾往前**匹配。确认：
1. 新对话放在了数组**靠后**的位置
2. 对话的 condition 已满足
3. 没有更靠后的对话组也满足条件（会优先选那个）

### Q: 如何让事件只出现一次？

用 `not_flag` + `set_flags` 组合:
```json
"condition": { "not_flag": "my_event_done" },
"set_flags": { "my_event_done": true }
```

### Q: 如何让事件在特定天数后才出现？

```json
"condition": { "min_day": 3 }
```
从第 3 天开始此事件才会进入候选池。

### Q: 如何让事件需要收集一定数量线索后才出现？

```json
"condition": { "min_clues": 5 }
```

### Q: JSON 格式报错怎么办？

常见问题:
- 最后一个元素后多了逗号 `,`
- 字符串没有用双引号
- 括号/花括号不匹配

建议使用 VS Code 打开 JSON 文件，它会自动标注语法错误。

### Q: 可以用什么工具编辑 JSON？

推荐:
- **VS Code** — 有语法高亮和错误检查
- **Notepad++** — 轻量编辑器
- **在线 JSON 编辑器** — 如 jsoneditoronline.org

---

## 附录: 当前数据一览

### 已定义线索 (8个)

| ID | 名称 | 分类 | 图标 |
|----|------|------|------|
| clue_old_photo | 泛黄照片 | 人物 | 📷 |
| clue_blood_stain | 干涸血迹 | 现场 | 🩸 |
| clue_diary_page | 日记残页 | 文献 | 📄 |
| clue_strange_symbol | 奇异符文 | 遗物 | 🔮 |
| clue_missing_poster | 寻人启事 | 人物 | 📋 |
| clue_broken_talisman | 碎裂护符 | 遗物 | 🧿 |
| clue_audio_tape | 录音磁带 | 文献 | 📼 |
| clue_dark_map | 暗面地图残片 | 遗物 | 🗺️ |

### 已定义 Flag

| Flag 名 | 设置来源 | 被谁引用 |
|---------|---------|---------|
| `found_photo` | plot_find_photo | plot_whisper(?) / ghost_girl对话 |
| `found_symbol` | plot_symbol_wall | plot_whisper / clue_talisman / nekomata对话 |
| `symbol_trail` | plot_whisper | — |
| `found_missing_poster` | plot_missing_person | — |
| `felt_rumble` | plot_deep_rumble | mask_user对话 |
| `found_blood` | clue_blood_trail | — |
| `found_diary` | clue_diary | — |
| `found_talisman` | clue_talisman | faceless对话 |
| `found_tape` | dark_clue_tape | — |
| `found_dark_map` | dark_clue_map | — |
| `prologue_done` | (待设置) | chapter1 解锁 |
| `chapter1_done` | (待设置) | chapter2 解锁 |

### 事件触发链路图

```
游戏开始 (prologue)
│
├── 翻「剧情牌」
│   ├── [无条件] 墙壁纹路 (plot_intro_inscription)
│   ├── [首次] 发现照片 → flag: found_photo → 线索: 泛黄照片
│   ├── [首次] 发现符文 → flag: found_symbol → 线索: 奇异符文
│   ├── [需found_symbol] 符文箭头 → flag: symbol_trail
│   ├── [第2天起] 寻人启事 → flag: found_missing_poster → 线索: 寻人启事
│   └── [3+线索] 地底震动 → flag: felt_rumble
│
├── 翻「线索牌」
│   ├── [无条件] 奇怪脚印 (无线索)
│   ├── [首次] 干涸血迹 → 线索: 干涸血迹
│   ├── [第2天+首次] 日记残页 → 线索: 日记残页
│   ├── [需found_symbol+首次] 碎裂护符 → 线索: 碎裂护符
│   └── [无条件] 不寻常细节 (无线索，兜底)
│
├── 暗世界探索「线索」
│   ├── [首次] 录音磁带 → 线索: 录音磁带
│   ├── [3+线索+首次] 暗面地图 → 线索: 暗面地图残片
│   └── [无条件] 气息信息 (无线索，兜底)
│
└── NPC 对话 (根据 flag/线索数变化)
    ├── 双尾猫妖: 默认 / 2+线索 / found_symbol
    ├── 幽灵娘: 默认 / found_photo / 5+线索
    ├── 无脸商人: 默认 / found_talisman
    └── 面具使: 默认 / 5+线索 / felt_rumble
```

---

*文档版本: v1.0*
*最后更新: 2026-04-28*
