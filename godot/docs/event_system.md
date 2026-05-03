# 事件系统技术文档

> **版本**: v1.0 — 基于 Phase 6 重构完成后的最终架构
>
> **最后更新**: 2026-05-03

---

## 目录

1. [架构概览](#1-架构概览)
2. [数据文件](#2-数据文件)
   - 2.1 [event_pool.json](#21-event_pooljson)
   - 2.2 [locations.json](#22-locationsjson)
3. [核心模块](#3-核心模块)
   - 3.1 [EventPool (Autoload)](#31-eventpool-autoload)
   - 3.2 [Locations (Autoload)](#32-locations-autoload)
   - 3.3 [EventHandler (RefCounted)](#33-eventhandler-refcounted)
   - 3.4 [Board (RefCounted)](#34-board-refcounted)
   - 3.5 [Card (RefCounted)](#35-card-refcounted)
   - 3.6 [StoryManager (Autoload)](#36-storymanager-autoload)
4. [加权随机算法](#4-加权随机算法)
5. [条件系统](#5-条件系统)
6. [事件降级机制](#6-事件降级机制)
7. [暗世界分层设计](#7-暗世界分层设计)
8. [内容统计](#8-内容统计)
9. [数据流总览](#9-数据流总览)

---

## 1. 架构概览

事件系统采用 **数据驱动 + 地点感知** 架构，所有事件定义集中在 JSON 文件中，运行时通过 Autoload 单例提供查询接口。

```
┌─────────────────────────────────────────────────────┐
│                    数据层 (JSON)                      │
│  event_pool.json ←→ locations.json                   │
│  (事件定义)           (地点定义 + 事件池引用)           │
└───────────┬────────────────────┬────────────────────┘
            │                    │
            ▼                    ▼
┌───────────────────┐  ┌───────────────────┐
│  EventPool        │  │  Locations        │
│  (Autoload)       │  │  (Autoload)       │
│  事件查询/元信息   │  │  地点查询/权重修正 │
└───────────┬───────┘  └────────┬──────────┘
            │                    │
            ▼                    ▼
┌───────────────────────────────────────────┐
│  Board._weighted_random_event_for_location │
│  (两层加权随机 → 选定 event_id)             │
└───────────────────┬───────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────┐
│  Card.event_id                            │
│  (每张卡牌携带一个事件 ID)                  │
└───────────────────┬───────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────┐
│  EventHandler.resolve_event_by_id()       │
│  (解析事件 → 构建 EventResult)             │
│  EventHandler.execute_event()             │
│  (应用效果/弹窗/flags/clue)                │
└───────────────────────────────────────────┘
```

**核心组件职责**：

| 组件 | 类型 | 职责 |
|------|------|------|
| `EventPool` | Autoload | 加载 `event_pool.json`，提供事件定义查询 |
| `Locations` | Autoload | 加载 `locations.json`，提供地点/事件池/权重修正查询 |
| `EventHandler` | RefCounted | 统一事件解析与执行（明面/暗面共用） |
| `Board` | RefCounted | 棋盘生成，包含加权随机事件选取算法 |
| `Card` | RefCounted | 卡牌数据结构，通过 `event_id` 字段关联事件定义 |
| `StoryManager` | Autoload | 条件检查、剧情 flag 管理、线索收集 |

---

## 2. 数据文件

### 2.1 event_pool.json

路径：`data/event_pool.json`

顶层结构：

```json
{
  "event_types": { ... },
  "trap_subtypes": { ... },
  "base_weights": { ... },
  "events": { ... }
}
```

#### event_types — 事件类型元信息

定义所有事件类型的显示属性：

```json
{
  "safe":    { "icon": "🛡️", "label": "安全",   "color_key": "safe",    "is_blocking": false },
  "monster": { "icon": "👹", "label": "怪物遭遇", "color_key": "danger",  "is_blocking": false },
  "trap":    { "icon": "⚡", "label": "陷阱触发", "color_key": "danger",  "is_blocking": false },
  "shop":    { "icon": "🏪", "label": "商店",   "color_key": "info",    "is_blocking": true  },
  "clue":    { "icon": "🔍", "label": "线索发现", "color_key": "clue",    "is_blocking": false },
  "plot":    { "icon": "📖", "label": "剧情事件", "color_key": "plot",    "is_blocking": false },
  "item":    { "icon": "🎁", "label": "道具拾取", "color_key": "item",    "is_blocking": false },
  "reward":  { "icon": "💰", "label": "意外收获", "color_key": "item",    "is_blocking": false }
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `icon` | String | 显示图标 |
| `label` | String | 显示标签 |
| `color_key` | String | 颜色主题键（对应 `GameTheme`） |
| `is_blocking` | bool | 是否需要弹窗确认（如商店） |

#### trap_subtypes — 陷阱子类型

```json
{
  "sanity":   { "icon": "🌀", "label": "精神冲击", "effect": { "san": -3 },            "texts": [...] },
  "money":    { "icon": "💸", "label": "财物损失", "effect": { "money": -15 },          "texts": [...] },
  "film":     { "icon": "📷", "label": "胶卷损坏", "effect": { "film": -1 },            "texts": [...] },
  "teleport": { "icon": "🌀", "label": "空间扭曲", "effect": { "san": -1 },             "texts": [...] }
}
```

当事件定义中 `trap_subtype` 为 `"random"` 时，运行时从以上子类型中随机抽选。

#### base_weights — 类型基础权重

用于无事件池的 fallback 场景（旧逻辑兼容）：

```json
{
  "safe": 30, "monster": 20, "trap": 15,
  "shop": 10, "clue": 10, "plot": 5, "item": 5, "reward": 5
}
```

#### events — 事件定义

每个事件以唯一 ID 为键，包含以下字段：

```json
{
  "evt_safe_general": {
    "type": "safe",
    "world": ["real"],
    "base_weight": 25,
    "effects": {},
    "texts": ["这里一切正常。", "平静的时刻。"],
    "condition": null,
    "fallback_type": null,
    "set_flags": {},
    "clue_id": null,
    "trap_subtype": null,
    "item_rewards": null
  }
}
```

**字段说明**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | String | 是 | 事件类型（对应 `event_types` 的键） |
| `world` | Array[String] | 是 | 适用世界：`"real"` / `"dark"` / 两者都有 |
| `base_weight` | int | 是 | 基础概率权重（越大越容易被抽到） |
| `effects` | Dictionary | 是 | 资源效果，如 `{ "san": -2, "money": -10 }` |
| `texts` | Array[String] | 是 | 随机文本池（触发时随机选取一条显示） |
| `condition` | Dictionary/null | 否 | 触发前置条件（不满足则降级，见[条件系统](#5-条件系统)） |
| `fallback_type` | String/null | 否 | 条件不满足时降级为的事件类型（默认 `"safe"`） |
| `set_flags` | Dictionary | 否 | 触发后设置的剧情标记 |
| `clue_id` | String/null | 否 | 触发后收集的线索 ID |
| `trap_subtype` | String/null | 否 | 陷阱子类型（`"random"` 或具体键） |
| `item_rewards` | Array/null | 否 | 道具随机奖励池，格式 `[["san", 10], ["money", 20]]` |

#### 事件命名规范

| 前缀 | 含义 | 示例 |
|------|------|------|
| `evt_` | 通用事件 | `evt_safe_general`, `evt_monster_shadow` |
| `evt_loc_` | 地点专属事件 | `evt_loc_park_stroll`, `evt_loc_hospital_firstaid` |
| `evt_dark_` | 暗世界通用事件 | `evt_dark_normal`, `evt_dark_shop` |
| `evt_dark_L0_` | 暗世界 Layer 0 专属 | `evt_dark_L0_whisper` |
| `evt_dark_L1_` | 暗世界 Layer 1 专属 | `evt_dark_L1_mask_stalker` |
| `evt_dark_L2_` | 暗世界 Layer 2 专属 | `evt_dark_L2_void_gaze` |

---

### 2.2 locations.json

路径：`data/locations.json`

顶层结构：

```json
{
  "real_world": { ... },
  "dark_world": {
    "layers": [ ... ],
    "locations": { ... }
  },
  "rumors": { ... }
}
```

#### real_world — 现实世界地点

```json
{
  "park": {
    "label": "公园",
    "icon": "🌳",
    "is_landmark": false,
    "schedule": {
      "text": "一天辛苦了，去公园坐坐。",
      "reward": ["san", 2]
    },
    "event_pool": [
      "evt_safe_general", "evt_monster_shadow", "evt_trap_random",
      "evt_clue_graffiti", "evt_loc_park_stroll", "evt_loc_park_birdwatch",
      "evt_loc_park_oldman", "evt_loc_park_straycat"
    ],
    "weight_mods": { "safe": 10, "monster": -5 },
    "location_effect": { "san": 1 },
    "dark_display": { ... }
  }
}
```

**字段说明**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `label` | String | 地点显示名 |
| `icon` | String | 地点图标 |
| `is_landmark` | bool | 是否为地标（教堂/警局/神社） |
| `forced_type` | String/null | 强制事件类型（`"home"` / `"shop"` / `"landmark"`） |
| `schedule` | Dictionary | 日程安排（text + reward） |
| `event_pool` | Array[String] | **事件池**：该地点可触发的事件 ID 列表 |
| `weight_mods` | Dictionary | **权重修正**：`{ type: offset }`，叠加到事件的 `base_weight` 上 |
| `location_effect` | Dictionary | 场所效果（如公园 san+1） |
| `dark_display` | Dictionary | 暗面时的视觉覆盖 |

**8 个探索地点**：company（公司）、school（学校）、park（公园）、alley（小巷）、station（车站）、hospital（医院）、library（图书馆）、bank（银行）

**3 个地标**：church（教堂）、police（警局）、shrine（神社）

#### dark_world — 暗世界

**layers** — 层级定义：

```json
[
  { "name": "表层·暗巷", "unlock_day": 0, "unlock_fragments": 0 },
  { "name": "中层·暗市", "unlock_day": 3, "unlock_fragments": 3 },
  { "name": "深层·暗渊", "unlock_day": 6, "unlock_fragments": 6 }
]
```

**locations** — 暗面地点（共 46 个）：

```json
{
  "锈蚀小巷": {
    "layer": 0,
    "dark_type": "normal",
    "event_pool": ["evt_dark_L0_safe", "evt_dark_normal", "evt_dark_L0_whisper", "evt_dark_L0_loose_brick", "evt_dark_L0_scrap_find"],
    "weight_mods": {}
  },
  "回声茶馆": {
    "layer": 1,
    "dark_type": "normal",
    "event_pool": ["evt_dark_L1_safe", "evt_dark_normal", "evt_dark_L1_mask_stalker", "evt_dark_L1_echo_clue"],
    "weight_mods": { "clue": 5, "safe": 5 }
  }
}
```

暗面 `dark_type` 值：

| dark_type | 说明 | 数量 |
|-----------|------|------|
| `normal` | 普通探索点（有事件池） | 30 |
| `shop` | 暗面商店 | 3 |
| `checkpoint` | 检查点 | 3 |
| `passage` | 层间通道 | 2 |
| `clue` | 固定线索点 | 3 |
| `item` | 固定道具点 | 3 |
| `abyss_core` | 深渊核心（Boss） | 1 |
| `intel` | 情报商人 | 1 |

#### rumors — 传言

```json
{
  "safe_texts": ["有人说%s附近最近很平静。", ...],
  "danger_texts": ["听说%s附近出现了奇怪的影子...", ...]
}
```

`%s` 会被替换为地点名称。

---

## 3. 核心模块

### 3.1 EventPool (Autoload)

**文件**：`scripts/autoload/event_pool.gd`

加载 `event_pool.json`，提供全局事件查询。

**主要 API**：

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `get_event(event_id)` | Dictionary | 获取事件定义（含 `_id` 键） |
| `get_events_by_type(type)` | Array | 获取指定类型的所有事件 |
| `get_events_by_world(world)` | Array | 获取指定世界（`"real"` / `"dark"`）的所有事件 |
| `get_event_type_info(type)` | Dictionary | 获取事件类型元信息（icon/label/color） |
| `get_event_random_text(event_id)` | String | 从事件文本池随机取一条 |
| `get_event_effects(event_id)` | Dictionary | 获取事件效果（trap 类型自动处理子类型） |
| `is_blocking_type(type)` | bool | 判断是否为阻塞类型（需弹窗） |
| `get_trap_subtype(subtype)` | Dictionary | 获取陷阱子类型定义 |
| `get_random_trap_subtype()` | String | 随机获取一个陷阱子类型键 |

**兼容层 API**（供旧代码过渡）：

| 方法 | 说明 |
|------|------|
| `get_dark_event_info(dark_type)` | 替代 `CardConfig.get_dark_event_info()` |
| `get_dark_event_text(dark_type)` | 替代 `CardConfig.get_dark_event_text()` |

### 3.2 Locations (Autoload)

**文件**：`scripts/autoload/locations.gd`

加载 `locations.json`，提供地点与事件池查询。

**现实世界 API**：

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `get_real_location(loc_id)` | Dictionary | 获取地点完整定义 |
| `get_real_location_ids()` | Array | 获取所有地点 ID |
| `get_real_event_pool(loc_id)` | Array | 获取地点的事件 ID 列表 |
| `get_real_weight_mods(loc_id)` | Dictionary | 获取地点权重修正 |
| `get_forced_type(loc_id)` | Variant | 获取强制事件类型（home/shop 等） |
| `get_location_effect(loc_id)` | Dictionary | 获取场所效果 |
| `get_schedule(loc_id)` | Dictionary | 获取日程信息 |
| `is_landmark(loc_id)` | bool | 是否为地标 |

**暗世界 API**：

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `get_dark_location(loc_name)` | Dictionary | 获取暗面地点定义 |
| `get_dark_locations_by_layer(layer)` | Dictionary | 获取指定层级的所有暗面地点 |
| `get_dark_layer(layer_index)` | Dictionary | 获取层级信息（name/unlock_day/unlock_fragments） |
| `get_dark_layer_count()` | int | 层级总数（3） |
| `get_dark_event_pool(loc_name)` | Array | 获取暗面地点事件池 |
| `get_dark_weight_mods(loc_name)` | Dictionary | 获取暗面地点权重修正 |

**传言 API**：

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `get_safe_rumor(location_label)` | String | 格式化安全传言 |
| `get_danger_rumor(location_label)` | String | 格式化危险传言 |

### 3.3 EventHandler (RefCounted)

**文件**：`scripts/lib/event_handler.gd`

统一事件解析与执行引擎，Real World 和 Dark World 共用。

**EventType 枚举**：

```gdscript
enum EventType {
    NONE = 0,  SAFE = 1,  MONSTER = 2,  TRAP = 3,
    SHOP = 4,  CLUE = 5,  PLOT = 6,     ITEM = 7,
    INTEL = 8, CHECKPOINT = 9, PASSAGE = 10,
    ABYSS_CORE = 11, NPC_DIALOGUE = 12, PHOTO = 13,
    DARK_CLUE = 14, DARK_ITEM = 15
}
```

**EventResult 类**：

| 属性 | 类型 | 说明 |
|------|------|------|
| `event_type` | EventType | 事件类型枚举 |
| `is_blocking` | bool | 是否需要弹窗确认 |
| `auto_apply` | bool | 是否自动应用效果 |
| `effects` | Dictionary | 资源变化 `{ "san": -1, "money": -10 }` |
| `message` | String | 显示消息 |
| `popup_data` | Dictionary | 弹窗数据（可含 `set_flags`、`clue_id`） |
| `on_complete` | Callable | 完成回调 |

**主要入口方法**：

| 方法 | 说明 |
|------|------|
| `resolve_event_by_id(event_id, card?)` | **推荐入口** — 从 `event_id` 构建 `EventResult` |
| `parse_real_world_card(card)` | 从 Card 数据解析现实世界事件（兼容旧路径） |
| `parse_dark_world_card(card, row, col, day)` | 从 Card 数据解析暗世界事件（兼容旧路径） |
| `execute_event(result, card?)` | 执行事件效果（应用资源/flags/clue/弹窗） |

**`resolve_event_by_id` 处理流程**：

1. 从 `EventPool.get_event()` 获取事件定义
2. 解析 `type` → `EventType` 枚举
3. 计算效果（trap 走子类型逻辑，item 走随机奖励）
4. 随机选取显示文本
5. 处理阻塞/弹窗逻辑
6. 检查护盾（monster/trap 伤害抵消）
7. 传递 `set_flags` 和 `clue_id` 到 `popup_data`
8. 返回 `EventResult`

**`execute_event` 处理流程**：

1. 遍历 `effects`，调用 `GameData.modify_resource()` 应用资源变化
2. 检查 `popup_data.set_flags`，设置剧情标记（含 `current_chapter` 特殊处理）
3. 检查 `popup_data.clue_id`，收集线索
4. 显示 banner 消息（颜色根据事件类型区分）
5. 处理阻塞弹窗（商店/NPC 对话）
6. 执行完成回调

### 3.4 Board (RefCounted)

**文件**：`scripts/core/board.gd`

棋盘生成模块，包含地点感知的加权随机算法。

**核心方法**：`_weighted_random_event_for_location(location: String) -> Dictionary`

返回 `{ "type": String, "event_id": String }`，详见[加权随机算法](#4-加权随机算法)。

### 3.5 Card (RefCounted)

**文件**：`scripts/core/card.gd`

卡牌数据结构。

**事件相关字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `location` | String | 地点键 |
| `type` | String | 事件类型键 |
| `event_id` | String | 事件池事件 ID（关联 EventPool） |
| `is_dark` | bool | 是否为暗面卡牌 |
| `dark_type` | String | 暗面卡牌类型 |
| `trap_subtype` | String | 陷阱子类型 |

### 3.6 StoryManager (Autoload)

**文件**：`scripts/autoload/story_manager.gd`

提供条件检查、剧情 flag 管理和线索系统。

事件系统通过 `check_condition(cond)` 判断事件是否可触发，详见[条件系统](#5-条件系统)。

---

## 4. 加权随机算法

`Board._weighted_random_event_for_location()` 实现**两层加权随机**：

### 步骤 1：计算最终权重

```
final_weight = max(0, event.base_weight + location.weight_mods[event.type])
```

- `base_weight`：事件自身的基础权重（在 `event_pool.json` 中定义）
- `weight_mods`：地点对某类型的权重修正（在 `locations.json` 中定义）
- 最终权重为 0 的事件被排除

### 步骤 2：按类型汇总权重

将事件池中所有事件按 `type` 分组，同类型事件的 `final_weight` 求和：

```
type_weights = {
    "safe":    25 + 20 = 45,
    "monster": 18 + 15 = 33,
    "clue":    12,
    ...
}
```

### 步骤 3：第一层抽选 — 选事件类型

对 `type_weights` 做加权随机，抽出一个类型（如 `"monster"`）。

### 步骤 4：第二层抽选 — 选具体事件

在该类型的候选事件中，再按各自的 `final_weight` 做加权随机，抽出具体的 `event_id`。

### 示例

公园 (`park`) 的事件池配置：

```json
{
  "event_pool": ["evt_safe_general", "evt_monster_shadow", "evt_loc_park_stroll", "evt_loc_park_birdwatch"],
  "weight_mods": { "safe": 10, "monster": -5 }
}
```

计算过程：

| 事件 ID | type | base_weight | weight_mod | final_weight |
|---------|------|-------------|------------|--------------|
| evt_safe_general | safe | 25 | +10 | **35** |
| evt_loc_park_stroll | safe | 18 | +10 | **28** |
| evt_loc_park_birdwatch | safe | 16 | +10 | **26** |
| evt_monster_shadow | monster | 20 | -5 | **15** |

类型汇总：`safe = 89, monster = 15`

→ 公园抽到安全事件的概率 ≈ 85.6%，怪物 ≈ 14.4%

若抽到 `safe` 类型，再在 3 个 safe 事件中按权重 35:28:26 抽选具体事件。

---

## 5. 条件系统

通过 `StoryManager.check_condition(cond: Dictionary) -> bool` 实现。

### 支持的条件类型

| 条件键 | 值类型 | 说明 | 示例 |
|--------|--------|------|------|
| `flag` | String | 剧情标记存在 | `{ "flag": "met_npc_a" }` |
| `not_flag` | String | 剧情标记不存在 | `{ "not_flag": "boss_defeated" }` |
| `flag_eq` | Array[2] | 标记等于特定值 | `{ "flag_eq": ["chapter", "3"] }` |
| `has_clue` | String | 已收集指定线索 | `{ "has_clue": "clue_hospital" }` |
| `min_clues` | int | 线索数量 >= N | `{ "min_clues": 3 }` |
| `min_day` | int | 当前天数 >= N | `{ "min_day": 4 }` |
| `min_san` | int | 精神值 >= N | `{ "min_san": 30 }` |
| `max_san` | int | 精神值 <= N | `{ "max_san": 50 }` |
| `min_money` | int | 金钱 >= N | `{ "min_money": 20 }` |
| `min_order` | int | 秩序值 >= N | `{ "min_order": 3 }` |
| `has_item` | String | 拥有指定道具 | `{ "has_item": "camera" }` |
| `not_item` | String | 没有指定道具 | `{ "not_item": "shield" }` |
| `all` | Array | 所有子条件都满足（AND） | `{ "all": [{ "min_day": 3 }, { "flag": "x" }] }` |
| `any` | Array | 任一子条件满足（OR） | `{ "any": [{ "has_clue": "a" }, { "min_money": 50 }] }` |

### 条件在事件系统中的使用

```json
{
  "evt_loc_library_forbiddenbook": {
    "type": "clue",
    "condition": { "all": [{ "min_day": 5 }, { "flag": "library_card" }] },
    "fallback_type": "safe"
  }
}
```

当条件不满足时，该事件降级为 `fallback_type` 所指定的类型（见[事件降级机制](#6-事件降级机制)）。

---

## 6. 事件降级机制

`EventHandler._check_event_condition()` 在事件触发前检查条件：

```
事件被抽中
  ↓
检查 condition
  ↓
├── condition == null → 直接触发
├── check_condition() == true → 直接触发
└── check_condition() == false → 降级
      ↓
    fallback_type 存在？
    ├── 是 → 降级为 fallback_type（如 "safe"）
    └── 否 → 默认降级为 "safe"
```

**设计意义**：

- 高阶事件（需要特定进度才能触发）不会因为条件不满足而导致"什么都没发生"
- 降级为安全事件保证了玩家体验的连续性
- 允许设计师通过 `fallback_type` 精确控制降级行为

---

## 7. 暗世界分层设计

暗世界分为 3 层，每层有独立的事件池和难度梯度：

### Layer 0 — 表层·暗巷

| 特征 | 值 |
|------|------|
| 解锁条件 | 初始解锁 |
| 风险等级 | 低 |
| 地点数量 | 10 个 normal + 特殊点 |
| 代表事件 | `evt_dark_L0_whisper` (san:-1), `evt_dark_L0_scrap_find` (money:+8) |

### Layer 1 — 中层·暗市

| 特征 | 值 |
|------|------|
| 解锁条件 | Day 3 + 3 碎片 |
| 风险等级 | 中 |
| 地点数量 | 10 个 normal + 特殊点 |
| 代表事件 | `evt_dark_L1_mask_stalker` (san:-2, money:-5), `evt_dark_L1_black_market_find` (money:+15) |

### Layer 2 — 深层·暗渊

| 特征 | 值 |
|------|------|
| 解锁条件 | Day 6 + 6 碎片 |
| 风险等级 | 高 |
| 地点数量 | 10 个 normal + 特殊点 |
| 代表事件 | `evt_dark_L2_void_gaze` (san:-4, money:-10), `evt_dark_L2_abyssal_treasure` (money:+30, san:-1) |

### 难度递进对比

| 层级 | safe 权重 | monster 效果 | trap 效果 | reward 效果 |
|------|-----------|-------------|-----------|-------------|
| L0 | 35 | san:-1 | san:-1 | money:+8 |
| L1 | 28 | san:-2, money:-5 | san:-2 | money:+15 |
| L2 | 20 | san:-4, money:-10 | san:-3 | money:+30, san:-1 |

每层的 normal 地点通过 `weight_mods` 进一步个性化：

- 危险地点：`{ "monster": 12, "safe": -10 }`（如"凝视大厅"）
- 安全地点：`{ "safe": 5 }`（如"生锈水塔"）
- 线索地点：`{ "clue": 5, "safe": 5 }`（如"回声茶馆"）

---

## 8. 内容统计

### 事件总览

| 类别 | 数量 | 说明 |
|------|------|------|
| 通用现实世界事件 | 16 | safe/monster/trap/shop/clue/plot/item/reward 各类型 |
| 地点专属现实事件 | 32 | 8 个探索地点各 4 个专属事件 |
| 暗世界通用事件 | 12 | dark_normal/monster/trap/clue/shop 等 |
| 暗世界 L0 层事件 | 4 | safe/whisper/loose_brick/scrap_find |
| 暗世界 L1 层事件 | 5 | safe/mask_stalker/fog_trap/black_market_find/echo_clue |
| 暗世界 L2 层事件 | 5 | safe/void_gaze/reality_crack/abyssal_treasure/ancient_vision |
| 特殊事件 | 3 | passage/abyss_core/checkpoint |
| **总计** | **77** | |

### 地点总览

| 类别 | 数量 |
|------|------|
| 现实世界探索地点 | 8 |
| 现实世界地标 | 3 |
| 现实世界特殊（home/shop） | 2 |
| 暗世界 Layer 0 地点 | ~16 |
| 暗世界 Layer 1 地点 | ~15 |
| 暗世界 Layer 2 地点 | ~15 |
| **暗世界总计** | **46** |

---

## 9. 数据流总览

```
游戏开始
  │
  ▼
Board 生成棋盘
  │
  ├── 遍历每个格子
  │     │
  │     ▼
  │   确定地点 (location)
  │     │
  │     ▼
  │   Locations.get_real_event_pool(location)  → 事件 ID 列表
  │   Locations.get_real_weight_mods(location) → 权重修正
  │     │
  │     ▼
  │   _weighted_random_event_for_location()
  │   ├── EventPool.get_event(eid) 获取 base_weight
  │   ├── final_w = max(0, base_w + mod)
  │   ├── 第一层随机：选事件类型
  │   └── 第二层随机：选具体事件
  │     │
  │     ▼
  │   Card.event_id = 选中的事件 ID
  │   Card.type = 选中的事件类型
  │
  ▼
玩家翻开卡牌
  │
  ▼
EventHandler.resolve_event_by_id(card.event_id, card)
  │
  ├── EventPool.get_event(event_id)  → 事件定义
  ├── _check_event_condition(evt)    → 条件检查/降级
  ├── _build_result_from_event(evt)  → 构建 EventResult
  │     ├── 解析 effects / texts / set_flags / clue_id
  │     ├── trap → 子类型随机
  │     ├── item → 奖励随机
  │     └── 护盾检查
  │
  ▼
EventHandler.execute_event(result, card)
  │
  ├── GameData.modify_resource()     → 应用资源变化
  ├── StoryManager.set_flag()        → 设置剧情标记
  ├── StoryManager.collect_clue()    → 收集线索
  ├── VFX.action_banner()            → 显示消息
  └── 弹窗处理（商店/NPC 对话）
```
