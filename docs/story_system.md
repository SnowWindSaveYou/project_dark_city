# 故事系统 (Story System) — 系统文档

> **版本**: v2.0  
> **依赖文档**: [game_design.md](game_design.md) · [story_system_upgrade_design.md](story_system_upgrade_design.md)  
> **故事原稿**: [story_design_draft.md](story_design_draft.md)  

---

## 目录

1. [系统概述](#1-系统概述)
2. [白夜同伴系统](#2-白夜同伴系统)
3. [条件系统扩展](#3-条件系统扩展)
4. [玩家选择系统 (DialogueSystem)](#4-玩家选择系统-dialoguesystem)
5. [记忆碎片系统](#5-记忆碎片系统)
6. [章节系统](#6-章节系统)
7. [多结局系统](#7-多结局系统)
8. [动态游戏时长](#8-动态游戏时长)
9. [天气条件](#9-天气条件)
10. [暗面改造](#10-暗面改造)
11. [数据结构汇总](#11-数据结构汇总)
12. [模块依赖关系](#12-模块依赖关系)
13. [实施路线](#13-实施路线)

---

## 1. 系统概述

### 1.1 背景

故事系统将游戏叙事从占位的"失踪者调查线"升级为**白夜情感线**——一条围绕灵体同伴"白夜"展开的多结局叙事。核心要素：

| 要素 | 说明 |
|------|------|
| **白夜** | 全程陪伴的灵体同伴，与主角形成共生/依赖/冲突关系 |
| **记忆碎片** | 10 片前世记忆，逐步恢复驱动角色认知转变 |
| **多结局** | 4 条故事结局 + 1 条兜底结局，由玩家选择和状态决定 |
| **14 天叙事** | 苏醒与恐惧 → 磨合与依存 → 真相与决裂 → 终章抉择 |

### 1.2 设计原则

1. **条件驱动，非状态机** — 白夜的行为差异完全由事件 condition（天数 / 碎片数 / 信任度）驱动，不需要独立状态枚举
2. **数据归属最小化** — 白夜数据嵌入 StoryManager，不创建独立 BaiyeManager，避免循环依赖
3. **复用优先** — 碎片复用独立收集机制，选择复用 DialogueSystem 的 choices 对话分支，结局复用 GameOver 流程
4. **叙事即事件** — 所有剧情推进（包括白夜变身、魔王战斗）都通过事件系统实现，不引入独立战斗系统

### 1.3 系统架构总览

```
┌──────────────────────────────────────────────────────────────────┐
│                        故事系统模块                               │
├──────────────────┬───────────────────────────────────────────────┤
│  StoryConfig     │  数据：天数常量 / 章节定义 / 结局定义 / 碎片定义  │
│  StoryManager    │  核心：白夜数据 / 碎片追踪 / 条件引擎 / 章节管理  │
│  StoryEvents     │  数据：剧情事件定义 (对话 + 选择 + 碎片)        │
│  StoryEventManager│  逻辑：事件查询 / 条件过滤 / 触发对话          │
│  DialogueSystem  │  复用：Gal 对话 UI + 内嵌选择分支              │
│  EndingSystem    │  新增：多结局判定                              │
│  Baiye           │  新增：白夜视觉表现 / 跟随 / 动画              │
│  DarkWorld       │  改造：白夜跟随 / 变身 / 碎片获取              │
│  DarkWorldFlow   │  改造：暗面进出流程 + 白夜跟随注入              │
│  DebugPanel      │  工具：开发调试面板 (信任/碎片/flags 等)        │
└──────────────────┴───────────────────────────────────────────────┘
```

---

## 2. 白夜同伴系统

### 2.1 核心属性

白夜的状态由三个数值属性描述，存储在 StoryManager 中：

| 属性 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `baiye_trust` | int | 0 – 10 | 信任度，影响白夜行为和结局判定 |
| `baiye_power` | int | 0 – 5 | 蓄积力量，用于暗面变身 |
| `sleep_days_left` | int | 0 – ∞ | 沉睡剩余天数，> 0 表示白夜不可用 |

### 2.2 可用性判定

```
白夜可用 = sleep_days_left <= 0 AND 未设置 "ending_seal" flag
```

- 沉睡期间（`sleep_days_left > 0`）：白夜不出现，无法进入暗面，触发孤独类事件
- 被封印后（`ending_seal` flag）：白夜永久不可用，走"永囚深渊"结局线

**实现**: `StoryManager.isBaiyeAvailable(sm)`

### 2.3 行为差异映射

白夜在故事中表现出的行为变化（胆怯 → 依赖 → 偏执 → 觉醒 → 沉睡），本质上由 condition 组合决定：

| 叙事阶段 | 驱动条件 | 表现 |
|---------|---------|------|
| 胆怯躲藏（第 1-2 天） | `min_day: 1` + `max_trust: 2` | 缩在角落、不敢跟随 |
| 主动依赖（第 3-4 天） | `min_trust: 3` + `min_day: 3` | 主动训练、钻被窝 |
| 控制欲（第 5 天） | `min_fragments: 7` + `min_trust: 5` + `min_day: 5` | 阻止出门、摔手机 |
| 变身击退敌人 | 碎片 5 的选择事件 | 消耗全部 power，沉睡 3 天 |
| 偏执摔手机 | `min_fragments: 7` + `min_day: 8` | 阻止社交 |
| 恢复记忆后真诚 | `min_fragments: 10` | 坦白一切 |
| 沉睡中 | `not: { baiye_available: true }` | 不出现 |
| 被封印 | `flag: ending_seal` | 永久消失 |

### 2.4 信任度变化来源

信任度通过 `StoryManager.addTrust(sm, amount)` 结算，典型来源：

| 来源 | 典型变化 |
|------|---------|
| 日常互动事件（白夜做饭、陪伴） | +1 |
| 关键选择（接纳白夜） | +3 ~ +5 |
| 负面选择（拒绝、伤害） | -2 ~ -5 |
| 吞噬白夜 | -10 |

**实际调用路径**: 事件 `choiceEffects` 中配置 `baiye_trust_change` → `StoryManager.applyChoiceEffects()` → `addTrust()`

### 2.5 沉睡机制

沉睡通过 `StoryManager.applyChoiceEffects()` 的 `trigger_sleep` 字段触发：

```
事件选择触发 trigger_sleep: N
  → sm.sleep_days_left = N
  → 白夜不可用，暗面跟随关闭
  → 每日终结算时 StoryManager.tickSleep(sm)：sleep_days_left -= 1
  → sleep_days_left 归零 → 白夜恢复可用
```

---

## 3. 条件系统扩展

故事系统在 StoryManager 条件引擎 (`checkCondition`) 基础上支持以下条件类型：

### 3.1 条件一览

| 条件字段 | 类型 | 说明 | 示例 |
|---------|------|------|------|
| `min_day` | int | 当前天数 >= N | `{ min_day = 2 }` |
| `min_trust` | int | 信任度 >= N | `{ min_trust = 3 }` |
| `max_trust` | int | 信任度 <= N | `{ max_trust = 2 }` |
| `baiye_available` | bool | 白夜是否可用 | `{ baiye_available = true }` |
| `min_fragments` | int | 碎片收集数 >= N | `{ min_fragments = 7 }` |
| `weather` | string | 当前天气匹配 | `{ weather = "thunder" }` |
| `chapter` | string | 当前章节匹配 | `{ chapter = "bonding" }` |
| `flag` | string | flag 已设置 | `{ flag = "seen_newspaper" }` |
| `not_flag` | string | flag 未设置 | `{ not_flag = "elite_defeated" }` |

### 3.2 组合条件

| 组合器 | 说明 | 示例 |
|--------|------|------|
| `all` | AND，所有子条件为 true | `{ all = { ... } }` |
| `any` | OR，任一子条件为 true | `{ any = { ... } }` |
| `not` | NOT，子条件取反 | `{ ["not"] = { ... } }` |

### 3.3 复合条件示例

```lua
-- 白夜做饭事件：需要白夜在、信任度 2+、第 2 天起
condition = { all = {
    { baiye_available = true },
    { min_trust = 2 },
    { min_day = 2 },
}}

-- 白夜沉睡期间的孤独事件
condition = { ["not"] = { baiye_available = true } }

-- 雷雨夜白夜钻被窝
condition = { all = {
    { weather = "thunder" },
    { baiye_available = true },
    { min_trust = 1 },
}}
```

### 3.4 条件判定流程

```
StoryManager.checkCondition(sm, cond, ctx):
  ├── cond == nil            → true (无条件 = 总是通过)
  ├── cond.all               → 所有子条件均为 true
  ├── cond.any               → 任一子条件为 true
  ├── cond["not"]            → 子条件取反
  ├── cond.flag              → hasFlag(sm, value)
  ├── cond.not_flag          → !hasFlag(sm, value)
  ├── cond.min_day           → ctx.dayCount >= value
  ├── cond.min_trust         → sm.baiye_trust >= value
  ├── cond.max_trust         → sm.baiye_trust <= value
  ├── cond.baiye_available   → isBaiyeAvailable(sm) == value
  ├── cond.min_fragments     → getFragmentCount(sm) >= value
  ├── cond.weather           → ctx.weather == value
  └── cond.chapter           → sm.currentChapter == value
```

---

## 4. 玩家选择系统 (DialogueSystem)

### 4.1 设计决策

选择系统**复用 DialogueSystem 的内嵌 choices**，而非创建独立的 ChoicePopup。这保持了 "剧情用 Gal 对话系统，选择分支也基于此" 的原则。

### 4.2 触发方式

选择通过 **StoryEventManager** 或 **DarkWorld 内联对话** 触发：

1. **翻牌触发**: `CardInteraction` → `StoryEventManager.queryEvent()` → `triggerEvent()` → `DialogueSystem.start()`
2. **暗面触发**: `DarkWorld.handleCardEffect()` → 直接调用 `DialogueSystem.start()` (精英/Boss 遭遇)

### 4.3 事件数据格式 (StoryEvents.lua)

```lua
{
    id       = "plot_newspaper",
    cardType = "plot",        -- 绑定翻牌类型 "plot" | "clue"
    priority = 10,            -- 越小越优先 (同优先级随机选一)
    onceFlag = "seen_newspaper",  -- 触发后设置此 flag 防止重复
    condition = { all = {
        { min_day = 2 },
        { not_flag = "seen_newspaper" },
    }},
    -- 对话数据: 直接传给 DialogueSystem.start()
    dialogue = {
        { speaker = "旁白", text = "你发现一张旧报纸。" },
        { speaker = "白夜", text = "你要仔细看看吗？",
          choices = {
              { label = "仔细研究", choiceId = "study" },
              { label = "丢掉它",   choiceId = "discard" },
          },
        },
    },
    -- 选择效果: 按 choiceId 索引
    choiceEffects = {
        study   = { set_flags = { "studied_paper" }, baiye_trust_change = 1,
                    effects = { inspiration = 1 } },
        discard = { baiye_trust_change = -1 },
    },
    -- 对话结束后自动收集的碎片 (可选)
    fragment = "frag_01",
}
```

### 4.4 Choice 效果字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `effects` | table | 资源变化（san / health / money / inspiration） |
| `set_flags` | table | 设置故事 flag（数组格式 `{"flag1"}` 或字典格式 `{flag1=true}`） |
| `baiye_trust_change` | int | 信任度变化 |
| `trigger_sleep` | int | 触发白夜沉睡天数 |

效果统一通过 `StoryManager.applyChoiceEffects(sm, choice, resourceBar)` 结算。

### 4.5 选择流程

```
翻开含选择的卡牌
  → StoryEventManager.queryEvent() 匹配事件
  → StoryEventManager.triggerEvent() 启动对话
    → DialogueSystem.start(dialogue, portrait, onComplete, onChoiceSelected)
    → 玩家看到对话文本，遇到 choices 时显示选项按钮
    → 选中选项 → onChoiceSelected(index, choiceData) 回调
      → 根据 choiceId 查找 choiceEffects → applyChoiceEffects()
    → 对话结束 → onComplete() 回调
      → 收集碎片 (如有 fragment 字段)
      → 恢复游戏操作
```

### 4.6 暗面内联选择 (DarkWorld)

暗面精英/Boss 遭遇也使用 DialogueSystem，但不经过 StoryEventManager，而是在 `DarkWorld.handleCardEffect()` 中直接调用：

```lua
DialogueSystem.start(dialogueLines, nil, onComplete, onChoiceSelected)
```

详见 §10.2。

---

## 5. 记忆碎片系统

### 5.1 设计目标

10 片记忆碎片替代原有线索系统，承担双重职能：

1. **叙事驱动** — 每片碎片携带前世描述文本，逐步揭示白夜与主角的真实关系
2. **游戏门锁** — 碎片收集数 >= 5 时延展至 14 天（见 §8）

### 5.2 碎片数据格式 (StoryConfig.FRAGMENTS)

```lua
{
    id      = "frag_01",
    name    = "碎片·初遇",
    chapter = "awakening",
    order   = 1,
    desc    = "模糊的闪回画面：你和一个身影站在废墟之上。",
}
```

### 5.3 碎片字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 唯一标识 (frag_01 ~ frag_10) |
| `name` | string | 碎片名称 |
| `chapter` | string | 所属章节 |
| `desc` | string | 简短描述 |
| `order` | int | 碎片编号 1-10 |

### 5.4 收集流程

```
翻开含碎片的卡牌 / 暗面碎片掉落
  → StoryManager.addFragment(sm, fragId) (去重)
  → 碎片加入已收集 map (sm.fragments[fragId] = true)
  → 弹出 VFX 提示 (暗面碎片) 或 对话闪回 (事件碎片)
  → 检查碎片总数 → >= 5 自动延展天数（见 §8）
```

### 5.5 碎片存储机制

碎片使用**独立的 map 结构**存储，不与旧线索系统共享：

| API | 说明 |
|-----|------|
| `StoryManager.addFragment(sm, fragId)` | 收集碎片，返回 isNew |
| `StoryManager.getFragmentCount(sm)` | 已收集碎片总数 |
| `StoryManager.hasFragment(sm, fragId)` | 是否已收集某碎片 |

存储结构: `sm.fragments = { frag_01 = true, frag_03 = true, ... }`

---

## 6. 章节系统

### 6.1 章节结构

游戏叙事分为 4 章，覆盖 14 天：

| 章节 ID | 名称 | 天数范围 | 解锁条件 |
|---------|------|---------|---------|
| `awakening` | 苏醒与恐惧 | 第 1-3 天 | 游戏开始 |
| `bonding` | 磨合与依存 | 第 4-7 天 | `dayCount >= 4` |
| `truth` | 真相与决裂 | 第 8-11 天 | `dayCount >= 8` (需碎片 >= 5 延展) |
| `finale` | 终章抉择 | 第 12-14 天 | `dayCount >= 12` |

### 6.2 章节对事件的影响

事件可通过 `chapter` 字段限制只在特定章节出现：

```lua
{
    id       = "plot_phone_call",
    condition = { all = {
        { min_day = 4 },
        { chapter = "bonding" },  -- 仅在"磨合与依存"章节出现
        { not_flag = "seen_phone_call" },
    }},
}
```

- `chapter` 条件为空或不设置 → 不限章节
- 条件引擎中 `chapter` 是**字符串匹配** (`sm.currentChapter == value`)

### 6.3 章节推进逻辑

```lua
-- StoryManager.updateChapter(sm, dayCount)
-- 遍历 StoryConfig.CHAPTERS，找到 dayCount 在 dayRange 范围内的章节
-- 超出所有章节范围 → 保持 "finale"
```

章节推进完全由天数范围驱动，不依赖碎片或信任度。

---

## 7. 多结局系统

### 7.1 结局一览

| 结局 ID | 名称 | 条件 | 优先级 | 基调 |
|---------|------|------|--------|------|
| `companion` | 灵体相伴 | `chose_acceptance` + 排他 + 碎片>=10 | 10 (最高) | 治愈线 |
| `seal` | 永囚深渊 | `flag: ending_seal` | 15 | 斩断线 |
| `substitute` | 代餐完成 | `flag: chose_merge` | 20 | 悲壮线 |
| `dark_lord` | 新魔王 | `flag: chose_devour` | 30 | 黑化线 |
| `default` | 迷雾中的日常 | 无条件（兜底） | 99 (最低) | 未完待续 |

### 7.2 判定流程

游戏结束时 (`EndingSystem.judge(sm, ctx)`)：

```
1. 遍历 StoryConfig.ENDINGS (按 priority 升序排列)
2. 取第一个 StoryManager.checkCondition() 为 true 的结局
3. 若全部不满足 → 使用 conditions == nil 的兜底结局 ("迷雾中的日常")
4. 返回结局数据 → GameOver 展示
```

### 7.3 结局数据格式 (StoryConfig.ENDINGS)

```lua
{
    id         = "companion",
    title      = "灵体相伴",
    subtitle   = "白夜化为微弱的灵光，留在你身边……",
    priority   = 10,
    conditions = { all = {
        { flag = "chose_acceptance" },
        { not_flag = "chose_merge" },
        { not_flag = "chose_devour" },
        { min_fragments = 10 },
    }},
    isVictory  = true,
}
```

### 7.4 结局触发方式

结局 flag 主要通过**终章选择事件**设置：

| 选择 | 设置的 flag | 对应结局 |
|------|-----------|---------|
| "我不会变成她，但我也不会离开你" | `chose_acceptance` | 灵体相伴 |
| "让我变成她吧" | `chose_merge` | 代餐完成 |
| "吞噬白夜的力量" | `chose_devour` | 新魔王 |
| 与魔王协议封印白夜 | `ending_seal` | 永囚深渊 |
| 无特殊选择 | 无 | 迷雾中的日常 |

---

## 8. 动态游戏时长

### 8.1 两档制设计

| 阶段 | 天数 | 内容 | 解锁条件 |
|------|------|------|---------|
| **基础期** | 1 – 7 天 | 所有玩家经历，目标存活 | 游戏开始 |
| **延展期** | 8 – 14 天 | 终章叙事，真相与抉择 | 碎片 >= 5 |

### 8.2 延展触发流程

```
每日结算时调用 StoryManager.getMaxDays(sm):
  ├── getFragmentCount(sm) >= EXTEND_THRESHOLD (5)
  │     → 返回 EXTENDED_DAYS (14)
  │
  └── 碎片 < 5
        → 返回 BASE_DAYS (7)
        → 第 7 天结束 → 游戏结束
        → 判定结局（通常为 "迷雾中的日常"）
```

### 8.3 设计意图

碎片收集既是叙事驱动，也是游戏延长的门锁：
- **不探索** → 只能活 7 天，看到"迷雾中的日常"结局
- **充分探索** → 体验完整 14 天故事，解锁 4 条真正结局

### 8.4 实现细节

**常量定义** (`StoryConfig`):
```lua
M.BASE_DAYS         = 7    -- 基础游戏天数
M.EXTENDED_DAYS     = 14   -- 延展后天数
M.EXTEND_THRESHOLD  = 5    -- 碎片延展阈值
```

**天数判定** (`StoryManager.getMaxDays(sm)`):
```lua
function M.getMaxDays(sm)
    if M.getFragmentCount(sm) >= StoryConfig.EXTEND_THRESHOLD then
        return StoryConfig.EXTENDED_DAYS
    end
    return StoryConfig.BASE_DAYS
end
```

**调用方** (`GameFlow`):
```lua
local function getMaxDays()
    if G.storyMgr then
        return StoryManager.getMaxDays(G.storyMgr)
    end
    return 7
end
```

### 8.5 稀缺度曲线

延展期的资源稀缺度需要独立配置：

| 天数段 | 每日可用地点数 |
|--------|-------------|
| 第 1-2 天 | 3 |
| 第 3-5 天 | 2 |
| 第 6-7 天 | 2 |
| 第 8-10 天 | 2 |
| 第 11-14 天 | 1 |

---

## 9. 天气条件

### 9.1 与故事的关联

天气影响特定事件的触发，例如雷雨夜白夜怕雷钻进被窝：

```lua
{
    id        = "evt_home_thunder_night",
    condition = { weather = "thunder" },
    dialogue  = {
        { speaker = "旁白", text = "雷声轰鸣，白夜缩成一团钻进了你的被窝……" },
    },
}
```

### 9.2 条件用法

```lua
{ weather = "thunder" }    -- 雷雨天
{ weather = "rain" }       -- 下雨天
{ weather = "sunny" }      -- 晴天
{ weather = "fog" }        -- 迷雾天
```

天气条件通过 `ctx.weather` 上下文参数传入条件引擎。

---

## 10. 暗面改造

### 10.1 白夜在暗面的影响

白夜对暗面探索的影响由 StoryManager 的数值组合决定：

| 条件 | 暗面效果 |
|------|---------|
| `sleep_days_left > 0` | **无法跟随**（可进入暗面但白夜不跟随） |
| 信任 < 3 | 可进入，白夜不敢跟随，独自探索 |
| 信任 >= 3 且可用 | 白夜跟随：解锁精英/Boss 遭遇，碎片掉落 |
| 碎片 >= 4 + 白夜跟随 | 可触发精英遭遇 |
| 碎片 >= 9 + 白夜跟随 | 可触发 Boss 遭遇 |

**白夜跟随条件** (DarkWorldFlow):
```lua
baiyeFollowDark = StoryManager.isBaiyeAvailable(G.storyMgr)
    and G.storyMgr.baiye_trust >= 3
G.baiyeFollowDark = baiyeFollowDark  -- 记录到共享状态
```

### 10.2 精英与 Boss 遭遇

遭遇通过 DarkWorld.handleCardEffect() 在 `clue`/`abyss_core` 卡牌处理中拦截，使用 DialogueSystem 展示选择：

**精英遭遇** (clue 卡触发):
| 条件 | `G.baiyeFollowDark` + `fragments >= 4` + `not_flag "elite_defeated"` |
|------|------|
| 选项 A "让白夜变身击退" | 设置 `elite_defeated` flag，消耗全部 power，`sleep_days_left = 3`，收集 `frag_05` |
| 选项 B "撤退" | 退出暗面 (`M.requestExit()`) |

**Boss 遭遇** (abyss_core 卡触发):
| 条件 | `G.baiyeFollowDark` + `fragments >= 9` + `not_flag "boss_defeated"` |
|------|------|
| 选项 A "正面迎战" | 设置 `boss_defeated` flag，`san -3`，收集 `frag_10`，设置 `memory_complete` |
| 选项 B "先撤退" | 退出暗面 |

**退出处理**: 退出选项在 `onChoiceSelected` 中设置 `retreatChosen = true`，然后在 `onComplete` 回调中调用 `M.requestExit()`，避免与对话动画冲突。

### 10.3 暗面碎片掉落

暗面 `clue` 类型卡牌可额外掉落碎片，通过 `DARK_FRAG_DROPS` 配置表驱动：

```lua
local DARK_FRAG_DROPS = {
    { minFrags = 1, layerMin = 1, fragId = "frag_02", flag = "dark_frag_02" },
    { minFrags = 3, layerMin = 2, fragId = "frag_06", flag = "dark_frag_06" },
    { minFrags = 5, layerMin = 2, fragId = "frag_07", flag = "dark_frag_07" },
    { minFrags = 6, layerMin = 3, fragId = "frag_08", flag = "dark_frag_08" },
    { minFrags = 8, layerMin = 3, fragId = "frag_09", flag = "dark_frag_09" },
}
```

掉落逻辑 (`tryDarkFragmentDrop()`):
```
正常 clue 卡效果结算后:
  → 遍历 DARK_FRAG_DROPS
  → 找到第一个满足 minFrags + layerMin + 未设置 flag 的条目
  → 设置 flag，收集碎片，显示 VFX 提示
```

---

## 11. 数据结构汇总

### 11.1 StoryManager 实例字段 (`sm = StoryManager.new()`)

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `baiye_trust` | int | 0 | 信任度 0-10 |
| `baiye_power` | int | 0 | 蓄积力量 0-5 |
| `sleep_days_left` | int | 0 | 沉睡剩余天数 |
| `flags` | table | `{}` | flag 系统 (`key → true`) |
| `fragments` | table | `{}` | 碎片收集 (`fragId → true`) |
| `currentChapter` | string | `"awakening"` | 当前章节 ID |

### 11.2 StoryManager API

| 方法 | 返回 | 说明 |
|------|------|------|
| `M.new()` | table | 创建新实例 |
| `M.reset(sm)` | void | 重置全部状态 |
| `M.addTrust(sm, amount)` | void | 增减信任度 (clamp 0-10) |
| `M.addPower(sm, amount)` | void | 增减力量 (clamp 0-5) |
| `M.usePower(sm, cost)` | bool | 消耗力量，不足返回 false |
| `M.isBaiyeAvailable(sm)` | bool | 白夜是否可用 |
| `M.tickSleep(sm)` | void | 每日递减沉睡天数 |
| `M.setFlag(sm, flag)` | void | 设置 flag |
| `M.hasFlag(sm, flag)` | bool | 查询 flag |
| `M.addFragment(sm, fragId)` | bool | 收集碎片，返回 isNew |
| `M.getFragmentCount(sm)` | int | 已收集碎片总数 |
| `M.hasFragment(sm, fragId)` | bool | 是否已收集某碎片 |
| `M.updateChapter(sm, dayCount)` | void | 根据天数更新章节 |
| `M.getMaxDays(sm)` | int | 获取当前最大天数 (7 或 14) |
| `M.checkCondition(sm, cond, ctx)` | bool | 递归条件判定 |
| `M.applyChoiceEffects(sm, choice, resourceBar)` | void | 应用选择效果 |

### 11.3 StoryEvents 事件字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 唯一标识 |
| `cardType` | string | 绑定翻牌类型 `"plot"` / `"clue"` |
| `priority` | number | 越小越优先 (同优先级随机) |
| `onceFlag` | string? | 触发后设置此 flag 防止重复 |
| `condition` | table? | 条件表 (nil = 无条件) |
| `dialogue` | table[] | DialogueSystem 对话数据 |
| `choiceEffects` | table? | 按 choiceId 索引的效果表 |
| `fragment` | string? | 对话结束后自动收集的碎片 ID |

### 11.4 StoryConfig 常量

| 字段 | 值 | 说明 |
|------|-----|------|
| `BASE_DAYS` | 7 | 基础游戏天数 |
| `EXTENDED_DAYS` | 14 | 延展后天数 |
| `EXTEND_THRESHOLD` | 5 | 碎片延展阈值 |
| `CHAPTERS` | table[] | 4 个章节定义 |
| `ENDINGS` | table[] | 5 个结局定义 |
| `FRAGMENTS` | table[] | 10 个碎片定义 |

---

## 12. 模块依赖关系

```
StoryConfig (纯数据)
  └── 定义: BASE_DAYS / EXTENDED_DAYS / CHAPTERS / ENDINGS / FRAGMENTS

StoryManager (核心状态)
  ├── 引用 StoryConfig (常量)
  ├── 白夜数据 (trust / power / sleep)
  ├── 碎片追踪 (fragments map)
  ├── 条件判定 (checkCondition)
  ├── 章节管理 (updateChapter)
  └── 动态天数 (getMaxDays)

StoryEvents (纯数据)
  └── 定义: 剧情事件列表 (对话 + 选择 + 碎片)

StoryEventManager (事件查询/触发)
  ├── 引用 StoryEvents (事件数据)
  ├── 引用 StoryManager (条件判定)
  └── 引用 DialogueSystem (启动对话)

EndingSystem (结局判定)
  ├── 引用 StoryConfig (结局定义)
  └── 引用 StoryManager (条件判定)

CardInteraction (翻牌集成)
  ├── 引用 StoryEventManager (查询/触发剧情事件)
  └── 传入 G.storyMgr + ResourceBar

DarkWorld (暗面集成)
  ├── 引用 StoryManager (碎片/flag/power/trust)
  ├── 引用 DialogueSystem (精英/Boss 对话)
  └── 读取 G_.baiyeFollowDark (白夜跟随状态)

DarkWorldFlow (暗面流程)
  ├── 引用 DarkWorld (注入 gameState)
  ├── 引用 StoryManager (判断白夜可用性)
  └── 计算 baiyeFollowDark 并写入 G

GameFlow (日终结算)
  ├── 引用 StoryManager.getMaxDays() (天数判定)
  ├── 引用 StoryManager.tickSleep() (沉睡倒计时)
  └── 引用 EndingSystem.judge() (结局判定)

Baiye (白夜表现)
  └── 视觉: 显示/隐藏/跟随动画

DebugPanel (开发工具)
  ├── 读写 G.storyMgr (信任/碎片/flags)
  ├── 引用 ResourceBar (灵感调整)
  └── 回调: enterDarkWorld / advanceDay
```

---

## 13. 实施路线

### Phase 1: 基础骨架 ✅ 已完成

| 序号 | 任务 | 涉及模块 | 状态 |
|------|------|---------|------|
| 1 | StoryConfig 定义天数/章节/结局/碎片常量 | StoryConfig | ✅ |
| 2 | StoryManager 白夜字段 + 条件引擎 + 碎片追踪 | StoryManager | ✅ |
| 3 | EndingSystem 多结局判定 | EndingSystem | ✅ |
| 4 | GameFlow 集成动态天数 | GameFlow | ✅ |

### Phase 2: 剧情数据迁移 ✅ 已完成

| 序号 | 任务 | 涉及模块 | 状态 |
|------|------|---------|------|
| 1 | StoryEvents 事件数据定义 (5 个初始事件) | StoryEvents | ✅ |
| 2 | StoryEventManager 事件查询/触发 | StoryEventManager | ✅ |
| 3 | CardInteraction 翻牌集成 (plot/clue) | CardInteraction | ✅ |
| 4 | StoryManager 条件系统扩展 (chapter/max_trust 等) | StoryManager | ✅ |

### Phase 3: 暗面改造 ✅ 已完成

| 序号 | 任务 | 涉及模块 | 状态 |
|------|------|---------|------|
| 1 | 暗面白夜跟随效果 | DarkWorldFlow, Baiye | ✅ |
| 2 | 暗面碎片掉落 (DARK_FRAG_DROPS) | DarkWorld | ✅ |
| 3 | 精英遭遇 (clue 卡拦截 + DialogueSystem 选择) | DarkWorld | ✅ |
| 4 | Boss 遭遇 (abyss_core 卡拦截 + DialogueSystem 选择) | DarkWorld | ✅ |

### 开发工具 ✅ 已完成

| 序号 | 任务 | 涉及模块 | 状态 |
|------|------|---------|------|
| 1 | DebugPanel 调试面板 (KEY_1 切换) | DebugPanel, main | ✅ |

### Phase 4: 内容填充 + 打磨 🔲 待开始

| 序号 | 任务 |
|------|------|
| 1 | 文案按模板补全所有地点剧情事件 (StoryEvents) |
| 2 | 碎片描述文本润色 (StoryConfig.FRAGMENTS) |
| 3 | 结局文案细化 (StoryConfig.ENDINGS) |
| 4 | 全流程测试 + 数值平衡 |
