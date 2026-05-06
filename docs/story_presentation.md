# 演出系统设计

> **定位**：定义剧情内容的**演出管线**——有哪些演出方式、各自的触发机制、数据格式、渲染层级和模块归属。  
> **不包含**：具体剧情文案、对话内容。剧情数据填充参见 `story_design_draft.md` + `StoryEvents.lua`。

---

## 目录

1. [演出方式总览](#1-演出方式总览)
2. [每日开场演出](#2-每日开场演出)
3. [翻牌剧情事件](#3-翻牌剧情事件)
4. [里程碑对话](#4-里程碑对话)
5. [白夜气泡对话](#5-白夜气泡对话)
6. [NPC 地图对话](#6-npc-地图对话)
7. [暗面演出](#7-暗面演出)
8. [结局演出](#8-结局演出)
9. [演出层级与互斥规则](#9-演出层级与互斥规则)
10. [模块依赖关系](#10-模块依赖关系)
11. [实施状态](#11-实施状态)

---

## 1. 演出方式总览

游戏中的剧情通过 **7 种演出管线** 呈现给玩家，每种管线有不同的触发方式、表现形式和叙事职能：

| # | 演出方式 | 触发方式 | 表现形式 | 叙事职能 | 是否阻塞操作 |
|---|---------|---------|---------|---------|-------------|
| 1 | 每日开场 | 天数切换时自动 | DialogueSystem 全屏对话 | 主线剧情推进 | ✅ 阻塞 |
| 2 | 翻牌事件 | 翻开特定牌时条件匹配 | DialogueSystem 全屏对话 | 主线/支线剧情 + 选择 | ✅ 阻塞 |
| 3 | 里程碑对话 | 游戏动作首次达成时 | DialogueSystem 全屏对话 | 关键节点引导 + 叙事 | ✅ 阻塞 |
| 4 | 气泡对话 | 静止自动 / 点击白夜 | 角色头顶气泡 | 氛围 + 角色塑造 | ❌ 不阻塞 |
| 5 | NPC 对话 | 到达 NPC 格子 / 点击 | DialogueSystem 全屏对话 | 世界观补充 + 支线 | ✅ 阻塞 |
| 6 | 暗面演出 | 暗面内特定卡牌/遭遇 | DialogueSystem 全屏对话 | Boss/精英 + 碎片闪回 | ✅ 阻塞 |
| 7 | 结局演出 | 游戏结束判定后 | GameOver 画面 + 文案 | 结局呈现 | ✅ 阻塞（终态） |

**设计原则**：
- **条件驱动**：所有演出（除气泡外）复用 `StoryManager.checkCondition()` 条件引擎
- **数据与逻辑分离**：演出内容定义在纯数据模块中，触发逻辑在管理模块中
- **统一对话管线**：阻塞式演出统一通过 `DialogueSystem` 呈现，保证同一时刻只有一个阻塞式演出

---

## 2. 每日开场演出

### 2.1 概述

每天开始时，在 `DateTransition` 动画结束后、发牌前，自动检查并播放当日的开场剧情。这是承载**按天推进的主线叙事**的主要管线。

### 2.2 触发流程

```
GameFlow.advanceDay()
  → DateTransition 动画播放（黑屏 + 天数标题）
  → 动画结束回调
  → 查询每日开场事件表（条件匹配）
  → 匹配成功 → DialogueSystem.start()
  → 对话结束回调 → 继续发牌流程
  → 无匹配 → 直接发牌
```

### 2.3 数据格式

在 `StoryEvents.lua` 中，使用 `cardType = "morning"` 区分每日开场事件：

```lua
{
    id        = "morning_dayN",
    cardType  = "morning",           -- 区别于 "plot"/"clue"
    priority  = 10,
    onceFlag  = "morning_dayN_seen",
    condition = { ... },             -- 典型：min_day + max_day 锁定天数
    dialogue  = { ... },
    choiceEffects = { ... },         -- 可选：开场选择
    fragment  = "frag_XX",           -- 可选：自动获得碎片
}
```

### 2.4 条件设计模式

| 模式 | 条件示例 | 说明 |
|------|---------|------|
| 固定天数触发 | `{ min_day=1, max_day=1 }` | 仅第 N 天触发 |
| 天数 + 状态 | `{ all = { {min_day=6}, {not={baiye_available=true}} } }` | 白夜沉睡期间的特定天 |
| 天数 + 碎片 | `{ all = { {min_day=7}, {min_fragments=5} } }` | 碎片到位才触发的剧情 |
| 天气相关 | `{ all = { {min_day=2}, {weather="thunder"} } }` | 特定天气下的剧情变体 |

### 2.5 与现有模块的关系

| 模块 | 改动 |
|------|------|
| `StoryEvents.lua` | 新增 `cardType = "morning"` 事件数据 |
| `StoryEventManager.lua` | 新增 `queryMorningEvent()` 方法，复用 `triggerEvent()` |
| `GameFlow.lua` | `advanceDay()` 中 DateTransition 回调处插入查询 |
| `DialogueSystem.lua` | 无改动，复用 |

---

## 3. 翻牌剧情事件

### 3.1 概述

玩家翻开卡牌时，根据牌面类型（plot/clue）和当前故事状态，条件匹配后拦截正常事件流程，播放剧情对话。**这是目前已实现的最成熟的演出管线**。

### 3.2 触发流程

```
CardInteraction.onCardFlipped(card)
  → StoryEventManager.queryEvent(cardType, sm, ctx)
  → 匹配成功 → StoryEventManager.triggerEvent()
    → DialogueSystem.start(dialogue, portrait, onComplete, onChoiceSelected)
    → 玩家选择 → applyChoiceEffects()
    → 对话结束 → 收集碎片（如有）→ 恢复操作
  → 无匹配 → 走正常事件弹窗（EventPopup）
```

### 3.3 数据格式

```lua
{
    id            = "event_id",
    cardType      = "plot" | "clue",
    priority      = number,           -- 越小越优先
    onceFlag      = "flag_name",      -- 一次性事件
    condition     = { ... },
    dialogue      = { ... },
    choiceEffects = { [choiceId] = { effects, set_flags, baiye_trust_change, trigger_sleep } },
    fragment      = "frag_XX",        -- 可选
}
```

### 3.4 选择效果字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `effects` | `{san?, health?, money?, inspiration?}` | 资源增减 |
| `set_flags` | `string[]` | 设置故事 flag |
| `baiye_trust_change` | `int` | 信任度增减 |
| `trigger_sleep` | `int` | 触发白夜沉睡天数 |

### 3.5 现状

✅ 已实现完整管线（`StoryEventManager` → `DialogueSystem`）  
⬜ 数据层需扩充（当前 5 个事件，目标 15-20 个）

---

## 4. 里程碑对话

### 4.1 概述

里程碑对话是由**玩家动作/游戏状态首次达成**触发的一次性对话，独立于"按天推进"或"翻牌匹配"两条主管线。典型场景：首次进入暗面、首次打开商店、首次遭遇某类卡牌效果等。

与翻牌事件的区别：
- 翻牌事件由**牌面类型**驱动，匹配 `cardType`
- 里程碑对话由**游戏动作/状态变化**驱动，挂载在各模块的特定 hook 点

### 4.2 触发机制

```
游戏动作发生（如：进入暗面）
  → 目标模块调用 MilestoneManager.tryTrigger(hookId, sm, ctx)
  → 遍历该 hookId 下的里程碑事件列表
  → 条件匹配 + onceFlag 去重
  → 匹配成功 → DialogueSystem.start()
  → 对话结束 → 执行 effects → 恢复操作
  → 无匹配 → 继续正常流程
```

### 4.3 数据格式

```lua
-- MilestoneEvents.lua（纯数据模块）
return {
    -- hookId: 对应各模块中的挂载点标识
    [hookId] = {
        {
            id        = "milestone_xxx",
            priority  = 10,
            onceFlag  = "ms_xxx_seen",      -- 一次性触发（必填）
            condition = { ... },            -- 复用 StoryManager.checkCondition()
            dialogue  = { ... },            -- DialogueSystem 格式
            choiceEffects = { ... },        -- 可选
        },
        -- 同一 hookId 下可有多个里程碑，按 priority 排序取首个匹配
    },
}
```

### 4.4 Hook 点规划

各模块需在特定位置插入里程碑检查调用。下表列出系统级 hook 点（不绑定具体剧情内容）：

| hookId | 所在模块 | 插入位置 | 说明 |
|--------|---------|---------|------|
| `enter_dark_world` | DarkWorldFlow | `enterDarkWorld()` 完成后 | 首次/特定条件进入暗面 |
| `exit_dark_world` | DarkWorldFlow | `exitDarkWorld()` 完成后 | 首次脱出暗面 |
| `open_shop` | ShopPopup | `show()` 显示前 | 首次打开商店 |
| `use_item` | ActionMenu | 道具使用后 | 首次使用某类道具 |
| `resource_low` | ResourceBar | 资源变化后检测 | 某资源首次降至危险阈值 |
| `baiye_sleep` | StoryManager | `triggerSleep()` 后 | 白夜首次进入沉睡 |
| `baiye_return` | StoryManager | `wakeUp()` 后 | 白夜沉睡后首次回归 |
| `fragment_collect` | StoryManager | `addFragment()` 后 | 收集特定碎片 / 碎片达到阈值 |
| `chapter_enter` | StoryManager | 章节切换时 | 进入新章节 |

> hook 点可按需扩展——新增 hook 只需在目标模块调用 `MilestoneManager.tryTrigger()` 即可，不影响其他模块。

### 4.5 与现有一次性触发的关系

当前代码中已有零散的一次性触发模式：

| 现有模式 | 位置 | 方式 |
|---------|------|------|
| 精英/Boss 遭遇 | `DarkWorld.lua` | 直接 `hasFlag()` + 硬编码对话 |
| 碎片掉落 | `DarkWorld.lua` | `DARK_FRAG_DROPS` + per-drop flag |
| 翻牌 `onceFlag` | `StoryEventManager` | `triggerEvent()` 自动设 flag |

里程碑系统的目标是**统一这些模式**：将现有的硬编码一次性触发迁移为数据驱动的里程碑事件，复用同一套 `MilestoneManager.tryTrigger()` + `onceFlag` + `checkCondition()` 机制。

### 4.6 MilestoneManager 接口设计

```lua
-- MilestoneManager.lua
local M = {}

--- 尝试触发指定 hook 点的里程碑对话
--- @param hookId string          hook 点标识
--- @param sm table               StoryManager 状态
--- @param ctx table              上下文（day, chapter, resources 等）
--- @param onComplete function?   对话结束回调
--- @return boolean               是否有里程碑被触发
function M.tryTrigger(hookId, sm, ctx, onComplete) end

--- 检查指定 hook 点是否有可触发的里程碑（不执行，仅查询）
--- @return table|nil             匹配的事件或 nil
function M.query(hookId, sm, ctx) end

return M
```

### 4.7 与其他演出的互斥

- 里程碑对话使用 `DialogueSystem`，遵守 §9 的互斥规则
- 若触发时已有阻塞式演出（如翻牌事件正在播放），**排队等待**或**丢弃**（按 hook 点的 `queueable` 属性决定）
- 气泡不受影响（DialogueSystem 打开时气泡自动隐藏）

---

## 5. 白夜气泡对话

### 5.1 概述

白夜（及主角）头顶的轻量级气泡文字，**不阻塞游戏操作**，用于氛围营造和角色性格表达。玩家移动时自动关闭。

### 5.2 触发方式

| 触发 | 条件 | 冷却 |
|------|------|------|
| 静止自动 | 玩家静止 ≥ 4 秒 | 5 秒 |
| 点击角色 | 点击白夜/主角 | 1.5 秒 |
| 事件后 | 翻牌事件结束后推送上下文 | 无额外冷却 |

### 5.3 对话池结构

当前已实现三层对话池，需要新增**故事感知层**：

| 层 | 权重 | 数据来源 | 状态 |
|----|------|---------|------|
| 通用池 | 1× | `COMMON_LINES` 硬编码 | ✅ 已实现 |
| 地点池 | 2× | `LOCATION_LINES[location]` | ✅ 已实现 |
| 事件池 | 2× | `EVENT_LINES[eventType]` | ✅ 已实现 |
| **故事池** | **3×** | **条件匹配，按章节/信任度/碎片筛选** | ⬜ 待实现 |

### 5.4 故事感知池数据格式

```lua
STORY_LINES = {
    {
        condition = { chapter = "awakening", max_trust = 2 },
        lines = { "...", "..." },
    },
    {
        condition = { all = { {chapter="bonding"}, {min_trust=3} } },
        lines = { "...", "..." },
    },
    -- ...
}
```

### 5.5 实现要点

| 项 | 说明 |
|----|------|
| 条件判定 | `pickLine()` 中遍历 `STORY_LINES`，用 `StoryManager.checkCondition()` 过滤 |
| 状态注入 | `BubbleDialogue` 需要接收 `G.storyMgr` 引用（通过 init 或 update 参数传入） |
| 去重 | 可选：记录最近 N 条已显示文本，避免连续重复 |
| 白夜不可用时 | 沉睡期间只显示主角独白（通用池 + 地点池），不显示白夜相关文本 |

---

## 6. NPC 地图对话

### 6.1 概述

玩家在棋盘上遇到 NPC 时触发的对话。分为**现实世界 NPC** 和**暗面 NPC** 两类。

### 6.2 触发流程

```
CardInteraction.handleNormalModeClick()
  → 检测目标格子有 NPC
  → NPCManager.getDialogue(npcId, sm, ctx) 查询条件对话
  → DialogueSystem.start()
  → 对话结束 → 恢复操作
```

### 6.3 NPC 对话数据格式

```lua
NPC_DIALOGUES = {
    npc_id = {
        {
            condition = { ... },        -- 可选，nil = 默认对话
            priority  = 10,
            onceFlag  = "flag_name",    -- 可选，一次性对话
            dialogue  = { ... },
            choiceEffects = { ... },    -- 可选
        },
        -- 多套对话按 priority 排序，取第一个条件满足的
    },
}
```

### 6.4 设计要点

| 项 | 说明 |
|----|------|
| 条件对话 | 同一 NPC 在不同章节/状态下说不同内容，复用条件引擎 |
| 多套 fallback | 优先匹配带条件的对话，无匹配则使用 `condition = nil` 的默认对话 |
| NPC 出现条件 | NPC 本身的出现/消失也可通过条件控制（如某 flag 设置后 NPC 不再生成） |
| 对话后效果 | 复用 `StoryManager.applyChoiceEffects()` |

### 6.5 现状

| 类型 | 状态 |
|------|------|
| 暗面 NPC（猫妖、幽灵娘等） | ✅ 已实现（`DarkWorld.handleCardEffect` 中 `intel` 类型） |
| 现实 NPC — 琴馨 | ✅ 基础对话已实现 |
| 现实 NPC — 条件多套对话 | ⬜ 待实现 |
| 现实 NPC — 新角色（房东等） | ⬜ 待实现 |

---

## 7. 暗面演出

### 7.1 概述

暗面中的特殊演出，包括精英/Boss 遭遇、碎片拾取闪回、魔王低语。**不经过 StoryEventManager**，由 `DarkWorld.handleCardEffect()` 直接调用 `DialogueSystem`。

### 7.2 演出子类型

| 子类型 | 触发卡牌 | 条件 | 状态 |
|--------|---------|------|------|
| 精英遭遇 | `clue` | 白夜跟随 + 碎片≥4 + 未击败 | ✅ 已实现 |
| Boss 遭遇 | `abyss_core` | 白夜跟随 + 碎片≥9 + 未击败 | ✅ 已实现 |
| 碎片闪回 | `clue`（掉落碎片时） | `DARK_FRAG_DROPS` 配置匹配 | ⬜ 待实现 |
| 魔王低语 | 进入特定层/特定格子 | 章节/碎片条件 | ⬜ 待实现 |

### 7.3 碎片闪回设计

碎片通过 `DARK_FRAG_DROPS` 掉落后，附加一段简短对话展示碎片描述：

```
DarkWorld.tryDarkFragmentDrop()
  → StoryManager.addFragment() 成功
  → 查 StoryConfig.FRAGMENTS 取 desc 文本
  → DialogueSystem.start({ {speaker="记忆", text=desc} }, nil, resume)
```

### 7.4 魔王低语设计

低语通过气泡或短对话在暗面特定条件下触发：

| 方案 | 表现 | 优劣 |
|------|------|------|
| A: 气泡式 | 屏幕边缘淡入淡出文字，不阻塞 | 轻量，但容易被忽略 |
| B: 短对话 | 1-2 句 DialogueSystem 对话 | 有存在感，但打断探索节奏 |
| **C: 混合** | **常规低语用气泡，关键低语用短对话** | **推荐** |

---

## 8. 结局演出

### 8.1 概述

游戏结束时，根据 `EndingSystem.judge()` 的判定结果，展示结局画面和文案。

### 8.2 触发流程

```
GameFlow.checkVictory() / checkDefeat()
  → EndingSystem.judge(sm, ctx)
  → 返回结局数据 { id, title, subtitle, isVictory }
  → GameOver.show(endingData)
```

### 8.3 结局数据来源

结局定义在 `StoryConfig.ENDINGS` 中，包含 `title` 和 `subtitle` 文案。

### 8.4 可扩展方向

| 方向 | 说明 |
|------|------|
| 结局前对话 | 在 GameOver 画面前插入一段终章对话（通过每日开场或翻牌事件触发） |
| 结局 CG | 每个结局配一张 CG 图片（`assets/image/ending_xxx.png`） |
| 结局回顾 | 展示本局关键选择回顾（读取 flags 列表） |

### 8.5 现状

✅ 判定逻辑已实现（`EndingSystem.judge`）  
✅ `GameOver` 画面已实现基础展示  
⬜ 结局前对话、CG、回顾待实现

---

## 9. 演出层级与互斥规则

### 9.1 渲染层级（从底到顶）

```
3D 场景（棋盘、卡牌、Token、白夜）
  ↑ NanoVG 叠加层
  │  ├─ 暗面 HUD（DarkWorld.drawHUD）
  │  ├─ 气泡对话（BubbleDialogue.draw）        ← 不阻塞
  │  ├─ 资源栏 / 手牌 / 弹窗
  │  ├─ DialogueSystem.draw()                  ← 阻塞层
  │  ├─ GameOver.draw()                        ← 终态层
  │  └─ DateTransition.draw()                  ← 过渡层
```

### 9.2 互斥规则

| 规则 | 说明 |
|------|------|
| **同时只能有一个阻塞式演出** | DialogueSystem 播放时，不响应翻牌/移动/弹窗点击 |
| **气泡与对话共存** | 气泡不阻塞，DialogueSystem 打开时气泡自动隐藏 |
| **过渡优先** | DateTransition 播放时屏蔽所有输入 |
| **终态独占** | GameOver 显示后屏蔽所有其他演出 |

### 9.3 输入路由优先级

`main.lua` 的 `handleClick()` 按以下顺序分发点击，**先匹配先消费**：

```
DateTransition → TitleScreen → GameOver → DialogueSystem
→ DebugPanel → EventPopup → ShopPopup → HandPanel
→ CameraButton → DarkWorld → CardInteraction
```

**影响**：新增演出方式时，需要在此链中正确插入拦截点。

---

## 10. 模块依赖关系

```
StoryEvents.lua (纯数据: morning / plot / clue 事件)
  │
  ↓
StoryEventManager.lua (查询 + 触发)
  ├── queryEvent(cardType, sm, ctx)       ← 翻牌调用
  ├── queryMorningEvent(sm, ctx)          ← 每日开场调用 [待实现]
  └── triggerEvent(event, sm, rb, cb)     ← 统一触发
        │
        ↓
DialogueSystem.lua (全屏对话 UI)
  ├── start(dialogue, portrait, onComplete, onChoiceSelected)
  ├── update(dt) / draw(vg) / handleClick(x, y)
  └── 回调 → StoryManager.applyChoiceEffects()

BubbleDialogue.lua (气泡对话)
  ├── 独立运行，不经过 StoryEventManager
  ├── pickLine() 从多层对话池选取
  └── [待实现] 故事感知层: 读 StoryManager 状态过滤对话池

NPCManager (NPC 对话)
  ├── getDialogue(npcId, sm, ctx) [待实现: 条件多套对话]
  └── → DialogueSystem.start()

MilestoneEvents.lua (纯数据: 按 hookId 分组的里程碑事件)
  │
  ↓
MilestoneManager.lua (查询 + 触发)
  ├── tryTrigger(hookId, sm, ctx, cb)  ← 各模块 hook 点调用
  └── query(hookId, sm, ctx)           ← 仅查询不执行
        │
        ↓
      DialogueSystem.lua (复用)

DarkWorld.lua (暗面演出)
  ├── 精英/Boss: 直接调用 DialogueSystem
  ├── 碎片闪回: [待实现] addFragment 后触发短对话
  ├── 魔王低语: [待实现] 条件触发气泡或短对话
  └── [待迁移] 部分硬编码一次性触发 → MilestoneManager

GameFlow.lua (调度)
  ├── advanceDay() → [待实现] 查询每日开场 → triggerEvent
  └── checkVictory() → EndingSystem → GameOver
```

---

## 11. 实施状态

### 已完成 ✅

| 演出方式 | 管线 | 说明 |
|---------|------|------|
| 翻牌事件 | StoryEventManager → DialogueSystem | 完整管线，5 个事件 |
| 暗面精英/Boss | DarkWorld → DialogueSystem | 含选择和效果结算 |
| 气泡对话 | BubbleDialogue（通用/地点/事件池） | 不感知故事状态 |
| 暗面 NPC | DarkWorld intel 类型 | 固定对话 |
| 结局判定 | EndingSystem → GameOver | 基础展示 |

### 待实现 ⬜

| 优先级 | 演出方式 | 工作内容 |
|--------|---------|---------|
| **P0** | 每日开场 | StoryEventManager 新增 `queryMorningEvent()`；GameFlow 接入 |
| **P0** | 翻牌事件扩充 | StoryEvents 数据层补充至 15-20 个事件 |
| **P1** | 里程碑对话 | 新增 MilestoneManager + MilestoneEvents；各模块插入 hook 调用 |
| **P1** | 气泡故事感知 | BubbleDialogue 新增 `STORY_LINES` 条件池 + StoryManager 注入 |
| **P1** | 碎片闪回 | DarkWorld 碎片掉落后触发 Fragment desc 短对话 |
| **P2** | NPC 条件对话 | NPCManager 支持多套条件对话 + 新 NPC 数据 |
| **P2** | 魔王低语 | 暗面/现实中条件触发的环境文字 |
| **P3** | 结局演出增强 | 结局前对话、CG、选择回顾 |
