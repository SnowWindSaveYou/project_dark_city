# 地点与事件系统重构计划

## 一、现有系统问题总结

| # | 问题 | 现状 | 影响 |
|---|------|------|------|
| 1 | **地点无差异化** | 13个明面地点共用全局 `event_weights`(safe:30/monster:20/trap:15/reward:15/plot:10/clue:10)，效果来自全局 `card_effects`，所有地点体验雷同 | 玩家去任何地方感受一样 |
| 2 | **概率无法细调** | `events.json` 的 `defaults.weights` 是唯一一份，无 per-location 偏移 | 无法调控难度曲线 |
| 3 | **条件约束分散** | `StoryManager` 有 `check_condition()`(flag/not_flag/min_clues/min_day/has_clue/all/any)，但仅在 `story_config.json` 的 plot/clue 事件中使用；明面卡牌事件(monster/trap/reward)完全无条件约束 | 高级玩家无法被筛选事件 |
| 4 | **明暗双轨** | `EventHandler` 有 `parse_real_world_card()` 和 `parse_dark_world_card()` 两套独立逻辑；`card_interaction.gd` 还有第三条内联路径处理明面事件 | 维护成本高，逻辑易不一致 |
| 5 | **暗面地点无差异** | `dark_world.json` 的 `location_pools` 仅是名称池，事件效果完全由 `dark_type` 决定，不同具名地点无任何效果差异 | 暗面探索体验重复 |
| 6 | **卡牌生成不感知地点** | `Board._weighted_random_event()` 只看全局权重，不知道当前卡牌的 location | 地点配置无法影响卡牌类型生成 |

## 二、设计目标

1. **每个地点有专属事件池**：不同地点引用不同事件，效果真实不同（不是换皮）
2. **概率可单独配置**：基于基准值 ± 偏移，可全局也可局部调控
3. **统一条件约束**：所有事件都支持 condition 字段，不满足时降级为 safe
4. **明暗格式统一**：同一套事件数据结构、同一套解析入口
5. **暗面具名地点独立**：每个暗面地点有独立事件池和概率偏移

## 三、数据结构设计

### 3.1 新增文件: `data/event_pool.json`

所有事件的单一来源定义。

```jsonc
{
  "$schema_comment": "全局事件池 — 所有事件统一定义，明面/暗面共用格式",

  // --- 事件分类枚举（替代 EventHandler.EventType 硬编码） ---
  "event_types": {
    "safe":       { "icon": "✨", "label": "安全",   "color_key": "safe",       "is_blocking": false },
    "home":       { "icon": "🏠", "label": "家",     "color_key": "safe",       "is_blocking": false },
    "landmark":   { "icon": "🏛️", "label": "地标",   "color_key": "highlight",  "is_blocking": false },
    "shop":       { "icon": "🛒", "label": "商店",   "color_key": "info",       "is_blocking": true  },
    "monster":    { "icon": "👻", "label": "怪物",   "color_key": "danger",     "is_blocking": false },
    "trap":       { "icon": "⚡", "label": "陷阱",   "color_key": "warning",    "is_blocking": false },
    "reward":     { "icon": "💎", "label": "奖励",   "color_key": "highlight",  "is_blocking": false },
    "plot":       { "icon": "📖", "label": "剧情",   "color_key": "plot",       "is_blocking": false },
    "clue":       { "icon": "🔍", "label": "线索",   "color_key": "info",       "is_blocking": false },
    "photo":      { "icon": "📸", "label": "相片",   "color_key": "safe",       "is_blocking": false },
    "rift":       { "icon": "🌀", "label": "裂隙",   "color_key": "dark_accent","is_blocking": false },
    "intel":      { "icon": "👁️", "label": "情报点", "color_key": "plot",       "is_blocking": false },
    "checkpoint": { "icon": "🚧", "label": "关卡",   "color_key": "warning",    "is_blocking": false },
    "item":       { "icon": "📦", "label": "道具",   "color_key": "highlight",  "is_blocking": false },
    "passage":    { "icon": "🕳️", "label": "通道",   "color_key": "dark_passage","is_blocking": false },
    "abyss_core": { "icon": "💀", "label": "深渊核心","color_key": "dark_abyss","is_blocking": false }
  },

  // --- 陷阱子类型定义（独立于事件，由 trap 类事件引用） ---
  "trap_subtypes": {
    "sanity":   { "icon": "😱", "label": "阴气侵蚀", "effect": { "san": -1 },   "texts": [...] },
    "money":    { "icon": "💸", "label": "财物散失", "effect": { "money": -10 }, "texts": [...] },
    "film":     { "icon": "📷", "label": "灵雾曝光", "effect": { "film": -1 },   "texts": [...] },
    "teleport": { "icon": "🌀", "label": "空间错位", "effect": {},              "texts": [...] }
  },

  // --- 基准权重（全局默认，可被 location 的 weight_mods 覆盖） ---
  "base_weights": {
    "safe": 30, "monster": 20, "trap": 15,
    "reward": 15, "plot": 10, "clue": 10
  },

  // ============================================================
  // 事件定义（核心）
  // ============================================================
  "events": {
    // ---- 明面: safe ----
    "evt_safe_rest": {
      "type": "safe",
      "world": ["real"],
      "base_weight": 30,
      "effects": {},
      "texts": [
        "周围一片宁静，什么也没有发生。",
        "微风拂过，带来一丝安心的感觉。",
        "这里很安全，可以稍作休息。"
      ],
      "condition": null,
      "fallback_type": null   // 不满足条件时的降级类型, null=直接降为 safe
    },

    // ---- 明面: monster (不同怪物效果不同) ----
    "evt_monster_shadow": {
      "type": "monster",
      "world": ["real"],
      "base_weight": 20,
      "effects": { "san": -2, "order": -1 },
      "texts": [
        "阴影从角落窜出，一股寒意直冲脑门...",
        "黑暗中传来沉重的呼吸声，越来越近...",
        "地板上浮现诡异的符文，空气凝固了..."
      ],
      "condition": null,
      "fallback_type": "safe"
    },
    "evt_monster_whisper": {
      "type": "monster",
      "world": ["real"],
      "base_weight": 12,
      "effects": { "san": -3, "money": -5 },
      "texts": [
        "耳边传来低语，理智在流失...",
        "有什么东西在窥视你，钱包莫名变轻了..."
      ],
      "condition": { "min_day": 2 },   // 第2天起才出现
      "fallback_type": "safe"
    },

    // ---- 明面: trap ----
    "evt_trap_generic": {
      "type": "trap",
      "world": ["real"],
      "base_weight": 15,
      "effects": {},              // 由 trap_subtype 决定
      "trap_subtype": "random",   // "random" = 生成时从 trap_subtypes 随机选取
      "texts": [
        "脚下突然传来咔嚓声，是陷阱！",
        "一股无形的力量困住了你的脚步...",
        "周围的墙壁开始缓缓合拢..."
      ],
      "condition": null,
      "fallback_type": "safe"
    },

    // ---- 明面: reward ----
    "evt_reward_supply": {
      "type": "reward",
      "world": ["real"],
      "base_weight": 15,
      "effects": { "money": 15, "film": 1 },
      "texts": [...],
      "condition": null,
      "fallback_type": "safe"
    },

    // ---- 明面: plot (条件化的剧情事件) ----
    "evt_plot_inscription": {
      "type": "plot",
      "world": ["real"],
      "base_weight": 10,
      "effects": { "san": -1 },
      "texts": ["墙壁上隐约浮现出奇异的纹路..."],
      "condition": null,
      "set_flags": {},
      "clue_id": null,
      "fallback_type": "safe"
    },
    "evt_plot_find_photo": {
      "type": "plot",
      "world": ["real"],
      "base_weight": 15,
      "effects": { "san": -1 },
      "texts": ["一张泛黄的照片从缝隙中滑落..."],
      "condition": { "not_flag": "found_photo" },
      "set_flags": { "found_photo": true },
      "clue_id": "clue_old_photo",
      "fallback_type": "safe"
    },

    // ---- 明面: clue ----
    "evt_clue_footprints": {
      "type": "clue",
      "world": ["real"],
      "base_weight": 10,
      "effects": { "order": 1 },
      "texts": ["地上有一串奇怪的脚印..."],
      "condition": null,
      "set_flags": {},
      "clue_id": null,
      "fallback_type": "safe"
    },

    // ---- 暗面: normal ----
    "evt_dark_normal": {
      "type": "safe",
      "world": ["dark"],
      "base_weight": 40,
      "effects": {},
      "texts": ["空荡荡的走廊，什么也没有。"],
      "condition": null,
      "fallback_type": null
    },

    // ---- 暗面: shop ----
    "evt_dark_shop": {
      "type": "shop",
      "world": ["dark"],
      "base_weight": 10,
      "effects": {},
      "texts": ["这里有神秘的商人..."],
      "condition": null,
      "is_blocking": true,
      "fallback_type": "safe"
    },

    // ---- 暗面: clue ----
    "evt_dark_clue_tape": {
      "type": "clue",
      "world": ["dark"],
      "base_weight": 12,
      "effects": { "san": 1 },
      "texts": ["你在暗世界的角落发现了一卷老式磁带..."],
      "condition": { "not_flag": "found_tape" },
      "set_flags": { "found_tape": true },
      "clue_id": "clue_audio_tape",
      "fallback_type": "safe"
    },

    // ---- 暗面: item ----
    "evt_dark_item_random": {
      "type": "item",
      "world": ["dark"],
      "base_weight": 10,
      "effects": {},            // 运行时随机: san+10 / money+20 / film+1
      "item_rewards": [["san", 10], ["money", 20], ["film", 1]],
      "texts": ["发现了散落的物品..."],
      "condition": null,
      "fallback_type": "safe"
    },

    // ---- 暗面: passage / checkpoint / abyss_core ----
    "evt_dark_passage": {
      "type": "passage",
      "world": ["dark"],
      "base_weight": 10,
      "effects": {},
      "condition": null,
      "is_blocking": true,
      "fallback_type": "safe"
    },
    "evt_dark_checkpoint": {
      "type": "checkpoint",
      "world": ["dark"],
      "base_weight": 10,
      "effects": {},
      "texts": ["一扇古老的大门矗立在此..."],
      "condition": null,
      "fallback_type": "safe"
    },
    "evt_dark_abyss": {
      "type": "abyss_core",
      "world": ["dark"],
      "base_weight": 10,
      "effects": {},
      "texts": ["这里是暗面世界的最深处..."],
      "condition": null,
      "fallback_type": "safe"
    }
    // ... 更多事件按需添加
  }
}
```

**关键字段说明：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | string | 是 | 事件分类，对应 event_types 中的 key |
| `world` | ["real"] / ["dark"] / ["real","dark"] | 是 | 可出现的世界 |
| `base_weight` | int | 是 | 基准权重，地点可通过 weight_mods 调整 |
| `effects` | { res: delta } | 是 | 资源效果，{} 表示无效果或由子类型决定 |
| `texts` | string[] | 是 | 随机显示文本 |
| `condition` | object / null | 否 | 触发约束，复用 StoryManager.check_condition() 格式 |
| `fallback_type` | string / null | 否 | 条件不满足时降级为的事件 type，null = 降为 safe |
| `set_flags` | { key: value } | 否 | 触发后设置的 flag |
| `clue_id` | string / null | 否 | 触发后收集的线索 |
| `is_blocking` | bool | 否 | 是否需要弹窗确认（覆盖 event_types 的默认值） |
| `trap_subtype` | string | 否 | 仅 trap 类: "random" 或指定子类型 key |
| `item_rewards` | [[res, val], ...] | 否 | 仅暗面 item 类: 随机奖励池 |

### 3.2 新增文件: `data/locations.json`

统一地点配置（明面+暗面），替代 `real_world.json` 中的 locations + `events.json` 中的 locations + `card_config.json` 中的 location_info。

```jsonc
{
  "$schema_comment": "统一地点配置 — 明面和暗面地点的事件池、概率偏移、显示信息",

  "real_world": {
    "home": {
      "label": "家",
      "icon": "🏠",
      "image_path": "",
      "schedule": {
        "verb": "在家休息",
        "reward": ["san", 1]
      },
      // 家是特殊格子，固定 safe 类型，不需要事件池
      "forced_type": "home",
      "weight_mods": {},
      "event_pool": []
    },

    "convenience": {
      "label": "便利店",
      "icon": "🏪",
      "image_path": "",
      "schedule": { "verb": "去便利店购物", "reward": ["money", 5] },
      "forced_type": "shop",
      "weight_mods": {},
      "event_pool": []
    },

    "church": {
      "label": "教堂",
      "icon": "⛪",
      "image_path": "",
      "is_landmark": true,
      "schedule": { "verb": "去教堂祈祷", "reward": ["san", 1] },
      "forced_type": "landmark",
      "weight_mods": {},
      "event_pool": []
    },

    "police": {
      "label": "警察局",
      "icon": "🚔",
      "image_path": "",
      "is_landmark": true,
      "schedule": { "verb": "去警察局报案", "reward": ["order", 1] },
      "forced_type": "landmark",
      "weight_mods": {},
      "event_pool": []
    },

    "shrine": {
      "label": "神社",
      "icon": "⛩️",
      "image_path": "",
      "is_landmark": true,
      "schedule": { "verb": "去神社参拜", "reward": ["san", 1] },
      "forced_type": "landmark",
      "weight_mods": {},
      "event_pool": []
    },

    "company": {
      "label": "公司",
      "icon": "🏢",
      "image_path": "",
      "schedule": { "verb": "去公司上班", "reward": ["money", 10] },
      "forced_type": null,          // 普通格子，随机事件
      "event_pool": [
        "evt_safe_rest",
        "evt_monster_shadow",
        "evt_monster_whisper",
        "evt_trap_generic",
        "evt_reward_supply",
        "evt_plot_inscription",
        "evt_plot_find_photo",
        "evt_clue_footprints"
      ],
      "weight_mods": {
        "monster": 5,     // 公司稍危险
        "trap": 5,
        "reward": -5,
        "plot": 5
      },
      "location_effect": {},        // 到达时附加效果（可选）
      "dark_display": {             // 暗面变体显示（迁移自 events.json locations.*.dark_display）
        "safe":   { "icon": "🏢", "label": "空荡办公室" },
        "monster":{ "icon": "🕴️", "label": "影子上司" },
        "trap":   { "icon": "📋", "label": "无尽加班令" },
        "reward": { "icon": "💼", "label": "遗落的公文包" },
        "plot":   { "icon": "🖥️", "label": "异常邮件" },
        "clue":   { "icon": "📂", "label": "机密档案" }
      }
    },

    "school": {
      "label": "学校",
      "icon": "🏫",
      "image_path": "",
      "schedule": { "verb": "去学校上课", "reward": ["money", 8] },
      "forced_type": null,
      "event_pool": [
        "evt_safe_rest",
        "evt_monster_shadow",
        "evt_trap_generic",
        "evt_reward_supply",
        "evt_plot_find_photo",
        "evt_clue_footprints"
      ],
      "weight_mods": {
        "monster": -5,
        "clue": 5,
        "safe": 5
      },
      "dark_display": { ... }
    },

    "park": {
      "label": "公园",
      "icon": "🌳",
      "image_path": "",
      "schedule": { "verb": "去公园散步", "reward": ["san", 1] },
      "forced_type": null,
      "event_pool": [
        "evt_safe_rest",
        "evt_monster_shadow",
        "evt_trap_generic",
        "evt_reward_supply",
        "evt_clue_footprints"
      ],
      "weight_mods": {
        "monster": -10,      // 公园安全
        "safe": 10,
        "trap": -5,
        "clue": 5
      },
      "location_effect": { "san": 1 },   // 到达公园恢复1点san
      "dark_display": { ... }
    },

    "alley": {
      "label": "小巷",
      "icon": "🌙",
      "image_path": "",
      "schedule": { "verb": "穿过小巷", "reward": ["money", 8] },
      "forced_type": null,
      "event_pool": [
        "evt_safe_rest",
        "evt_monster_shadow",
        "evt_monster_whisper",
        "evt_trap_generic",
        "evt_reward_supply",
        "evt_plot_inscription",
        "evt_clue_footprints"
      ],
      "weight_mods": {
        "monster": 15,       // 小巷危险!
        "trap": 10,
        "safe": -15,
        "reward": -5
      },
      "dark_display": { ... }
    },

    "station": { ... },
    "hospital": { ... },
    "library": { ... },
    "bank": { ... }
  },

  "dark_world": {
    // 层级元数据（迁移自 dark_world.json layers）
    "layers": [
      { "name": "表层·暗巷", "unlock_day": 2, "unlock_fragments": 0 },
      { "name": "中层·暗市", "unlock_day": 4, "unlock_fragments": 0 },
      { "name": "深层·暗渊", "unlock_day": 6, "unlock_fragments": 1 }
    ],

    // 具名地点配置
    "locations": {
      "锈蚀小巷": {
        "layer": 0,
        "dark_type": "normal",
        "event_pool": [
          "evt_dark_normal"
        ],
        "weight_mods": {},
        "dark_display": null      // 普通格子无需变体显示
      },
      "旧档案室": {
        "layer": 0,
        "dark_type": "clue",
        "event_pool": [
          "evt_dark_clue_tape",
          "evt_dark_clue_map"
        ],
        "weight_mods": { "clue": 10 },
        "condition": { "min_clues": 1 },   // 地点级约束
        "dark_display": { "clue": { "icon": "📂", "label": "旧档案室" } }
      },
      "无光集市": {
        "layer": 1,
        "dark_type": "normal",
        "event_pool": [
          "evt_dark_normal"
        ],
        "weight_mods": {},
        "dark_display": null
      },
      "暗巷当铺": {
        "layer": 1,
        "dark_type": "shop",
        "event_pool": [
          "evt_dark_shop"
        ],
        "weight_mods": {},
        "dark_display": { "shop": { "icon": "🏪", "label": "暗巷当铺" } }
      },
      "深渊碑文": {
        "layer": 2,
        "dark_type": "clue",
        "event_pool": [
          "evt_dark_clue_tape",
          "evt_dark_clue_map"
        ],
        "weight_mods": { "clue": 15 },
        "condition": { "min_clues": 3 },
        "dark_display": { "clue": { "icon": "🔮", "label": "深渊碑文" } }
      },
      "最深处": {
        "layer": 2,
        "dark_type": "abyss_core",
        "event_pool": [ "evt_dark_abyss" ],
        "weight_mods": {},
        "dark_display": { "abyss_core": { "icon": "💀", "label": "最深处" } }
      }
      // ... 更多暗面地点
    }
  }
}
```

**关键字段说明：**

| 字段 | 适用 | 说明 |
|------|------|------|
| `forced_type` | 明面 | 固定卡牌类型（home/shop/landmark），不参与随机 |
| `event_pool` | 两者 | 该地点可用的事件 ID 列表，从 event_pool.json 中引用 |
| `weight_mods` | 两者 | 按事件 type 的概率偏移，最终 = base_weight + weight_mods[type] |
| `location_effect` | 明面 | 到达时附加资源效果 |
| `condition` | 暗面 | 地点级约束，不满足则该地点的特定事件降级为 safe |
| `dark_display` | 明面 | 暗面变体显示信息（迁移自 events.json locations） |
| `schedule` | 明面 | 日程模板（迁移自 real_world.json） |
| `is_landmark` | 明面 | 是否地标 |

### 3.3 条件约束统一格式

所有事件和地点共用 `StoryManager.check_condition()` 已有格式，新增资源约束：

```jsonc
{
  // --- 已有（StoryManager.check_condition 已支持） ---
  "flag": "key",
  "not_flag": "key",
  "flag_eq": ["key", value],
  "has_clue": "clue_id",
  "min_clues": 3,
  "min_day": 2,
  "all": [{ ... }, { ... }],
  "any": [{ ... }, { ... }],

  // --- 新增 ---
  "min_san": 3,              // 理智 >= 3
  "max_san": 8,              // 理智 <= 8
  "min_money": 20,           // 金钱 >= 20
  "min_order": 5,            // 秩序 >= 5
  "has_item": "shield",      // 持有道具
  "not_item": "exorcism"     // 不持有道具
}
```

### 3.4 概率计算

```
最终权重 = max(0, event.base_weight + location.weight_mods[event.type] + global_modifier)
```

- `global_modifier`: 全局调控值，可按天数/难度变化
- 若 weight_mods 中某 type 设为 -99，等效于禁止该类型
- 权重计算后按类型分组汇总，再按汇总权重抽选类型 → 在该类型的候选事件中按各自 base_weight 抽选具体事件

## 四、脚本修改计划

### 4.1 新增 Autoload: `EventPool` (`scripts/autoload/event_pool.gd`)

**职责**：加载 `data/event_pool.json`，提供事件查询接口

```
核心属性:
  - event_types: Dictionary       # 事件分类定义
  - trap_subtypes: Dictionary     # 陷阱子类型
  - base_weights: Dictionary      # 基准权重
  - events: Dictionary            # 事件定义 { event_id: {...} }

核心方法:
  - get_event(event_id: String) -> Dictionary
  - get_events_by_type(type: String) -> Array[Dictionary]
  - get_events_by_world(world: String) -> Array[Dictionary]
  - get_event_type_info(type: String) -> Dictionary
  - get_trap_subtype(subtype: String) -> Dictionary
```

### 4.2 新增 Autoload: `Locations` (`scripts/autoload/locations.gd`)

**职责**：加载 `data/locations.json`，提供地点配置查询

```
核心属性:
  - real_locations: Dictionary    # 明面地点配置
  - dark_layers: Array            # 暗面层级元数据
  - dark_locations: Dictionary    # 暗面地点配置

核心方法:
  - get_real_location(loc_id: String) -> Dictionary
  - get_dark_location(loc_name: String) -> Dictionary
  - get_real_location_ids() -> Array[String]
  - get_dark_locations_by_layer(layer: int) -> Dictionary
  - get_schedule(loc_id: String) -> Dictionary
  - get_dark_display(loc_id: String) -> Dictionary
```

### 4.3 重构: `EventHandler` (`scripts/lib/event_handler.gd`)

**核心变更**：合并 `parse_real_world_card()` 和 `parse_dark_world_card()` 为统一入口

```
删除:
  - parse_real_world_card()
  - parse_dark_world_card()
  - _card_type_to_event_type()
  - _dark_type_to_event_type()

新增:
  - resolve_event(location_id: String, world: String) -> EventResult
    1. 查询地点配置 → 获取 event_pool + weight_mods
    2. 遍历 event_pool，检查 condition → 不满足则降级为 safe
    3. 计算最终权重 (base_weight + weight_mods)
    4. 加权随机抽选一个事件
    5. 构建 EventResult

  - _filter_valid_events(event_ids: Array) -> Array[Dictionary]
    遍历事件ID，check_condition()，不满足的按 fallback_type 降级

  - _calc_final_weights(candidates: Array, weight_mods: Dictionary) -> Dictionary
    计算 { event_id: final_weight }

  - _weighted_pick(candidates: Array, weights: Dictionary) -> Dictionary
    按权重随机选取一个事件

  - _build_result(event_def: Dictionary) -> EventResult
    从事件定义构造 EventResult

保留:
  - EventResult 内部类
  - EventType 枚举（改为从 EventPool.event_types 动态映射）
  - get_emotion_for_event()
  - is_blocking_type()
  - execute_event()
  - parse_npc_dialogue()
```

### 4.4 重构: `CardConfig` (`scripts/autoload/card_config.gd`)

**变更**：删除已迁移到 EventPool / Locations 的字段和方法，保留 shop 相关

```
删除:
  - location_info          → 迁移到 Locations
  - schedule_templates     → 迁移到 Locations
  - rumor_safe_texts       → 迁移到 Locations 或保留
  - rumor_danger_texts     → 迁移到 Locations 或保留
  - event_weights          → 迁移到 EventPool
  - card_effects           → 迁移到 EventPool
  - event_texts            → 迁移到 EventPool
  - trap_subtype_info      → 迁移到 EventPool
  - trap_subtype_texts     → 迁移到 EventPool
  - darkside_info          → 迁移到 Locations
  - dark_texts             → 迁移到 EventPool
  - _event_locations       → 迁移到 Locations
  - get_event_effect()     → 迁移到 EventPool
  - get_event_texts()      → 迁移到 EventPool
  - get_dark_display()     → 迁移到 Locations
  - get_dark_event_info()  → 迁移到 EventPool
  - get_dark_event_text()  → 迁移到 EventPool
  - _load_events()         → 删除（由 EventPool 加载）
  - _load_real_world()     → 删除（由 Locations 加载）

保留:
  - shop_items, consumable_order, shop_variants, shop_refresh_cost
  - card_types, dark_card_types
  - dw_constants, dw_layers, dw_location_pools, dw_npcs, dw_ghost_textures, dw_layer_generation
  - _load_card_types()
  - _load_shop()
  - _load_dark_world()
  - 所有 dark_world 查询方法
```

### 4.5 修改: `Board` (`scripts/core/board.gd`)

**核心变更**：`_weighted_random_event()` 改为地点感知

```
修改 _weighted_random_event(location: String) -> String:
  1. 从 Locations 获取该地点的 event_pool + weight_mods
  2. 按 event_pool 中的事件分组计算类型权重
  3. 加权随机选类型 → 在该类型的候选事件中再随机选一个
  4. 返回事件 ID（而非 type 字符串）

修改 generate_cards():
  - 普通格子的卡牌生成需要传入 location
  - 卡牌的 type 仍保留（兼容渲染和交互），但新增 event_id 字段
  - 特殊格子 (home/shop/landmark) 从 location 的 forced_type 获取
```

### 4.6 修改: `Card` (`scripts/core/card.gd`)

**核心变更**：新增 `event_id` 字段，效果查询优先走事件定义

```
新增属性:
  - var event_id: String = ""      # 具体事件 ID（用于从 EventPool 查效果/文本）

修改 get_effects():
  - 优先从 EventPool.get_event(event_id).effects 获取
  - fallback 到 CardConfig（兼容过渡）

修改 get_event_text():
  - 优先从 EventPool.get_event(event_id).texts 获取
  - fallback 到 CardConfig

修改 get_darkside_info():
  - 优先从 Locations.get_dark_display(location) 获取
  - fallback 到 CardConfig.darkside_info

修改工厂方法:
  - Card.create(loc, evt_type, r, c) → 新增 event_id 参数
  - Card.create_dark(dt, dn, r, c) → 新增 event_id 参数
```

### 4.7 修改: `CardInteraction` (`scripts/controllers/card_interaction.gd`)

**核心变更**：翻牌效果统一走 EventHandler

```
修改 _on_card_flipped():
  - 剧情事件(plot): 不再直接调用 StoryManager.pick_plot_event()
    改为由 EventHandler 在 resolve_event() 中处理（事件定义已包含 set_flags/clue_id）
  - 线索事件(clue): 同上
  - 怪物(monster)/陷阱(trap): 效果从 event_id 对应的事件定义获取
  - 整体简化: 如果 event_id 非空，效果由事件定义驱动；否则 fallback 旧逻辑
```

### 4.8 修改: `StoryManager` (`scripts/autoload/story_manager.gd`)

**核心变更**：扩展 check_condition() 支持资源约束

```
修改 check_condition():
  新增条件类型:
  - "min_san":   GameData.get_resource("san") >= N
  - "max_san":   GameData.get_resource("san") <= N
  - "min_money": GameData.get_resource("money") >= N
  - "min_order": GameData.get_resource("order") >= N
  - "has_item":  GameData.has_item(key)
  - "not_item":  not GameData.has_item(key)

保留:
  - plot_events / clue_events / dark_clue_events 仍保留在 story_config.json
    （剧情事件内容庞大，不适合全量迁移到 event_pool.json）
  - pick_plot_event() / pick_clue_event() / pick_dark_clue_event() 保留
    但当 card 有 event_id 时，EventHandler 应优先使用 event_id 对应的事件定义
```

### 4.9 修改: `DarkWorldFlow` (`scripts/controllers/dark_world_flow.gd`)

```
修改事件解析:
  - _event_handler.parse_dark_world_card() → _event_handler.resolve_event(location_name, "dark")
  - 暗面卡牌生成时从 Locations.dark_locations 获取 event_pool
```

### 4.10 修改: `BoardVisual` / `EventPopupScene` / UI 层

```
影响面小:
  - board_visual.gd: card.get_location_info() 不变（接口保留）
  - event_popup_scene.gd: CardConfig.darkside_info → Locations.get_dark_display()
  - photo_popup.gd: 同上
  - hand_panel.gd: StoryManager.get_clue_count() 不变
```

## 五、数据文件变更汇总

| 文件 | 操作 | 说明 |
|------|------|------|
| `data/event_pool.json` | **新增** | 全局事件定义（替代 events.json 中的 defaults + story_config.json 中的部分事件） |
| `data/locations.json` | **新增** | 统一地点配置（替代 real_world.json + events.json 中的 locations） |
| `data/events.json` | **删除** | 内容迁移到 event_pool.json + locations.json |
| `data/real_world.json` | **删除** | 内容迁移到 locations.json |
| `data/card_config.json` | **删除** | 内容迁移到 event_pool.json + locations.json，shop 部分保留在 shop.json |
| `data/story_config.json` | **保留但精简** | plot_events / clue_events / dark_clue_events 保留（内容庞大），chapters / clues / npc_dialogues 保留 |
| `data/dark_world.json` | **保留但精简** | layers 元数据迁移到 locations.json，location_pools 迁移到 locations.json，npcs/ghost/layer_generation 保留 |
| `data/shop.json` | **保留** | 无变更 |
| `data/game_config.json` | **保留** | 无变更 |
| `data/card_types.json` | **保留** | 无变更（事件类型定义迁移到 event_pool.json 的 event_types） |

## 六、实施步骤

### Phase 1: 基础设施 (不破坏现有功能)

1. 新增 `data/event_pool.json`，将现有 `events.json` 的 defaults 迁入
2. 新增 `data/locations.json`，将 `real_world.json` + `events.json` locations 迁入
3. 新增 `EventPool` autoload，加载 event_pool.json
4. 新增 `Locations` autoload，加载 locations.json
5. 在 `project.godot` 注册两个新 autoload

### Phase 2: Card & Board 改造

6. `Card` 新增 `event_id` 字段，修改工厂方法和效果查询
7. `Board._weighted_random_event()` 改为地点感知，从 Locations + EventPool 获取配置
8. `Board.generate_cards()` 使用 Locations 获取 forced_type 和 event_pool

### Phase 3: EventHandler 统一入口

9. `EventHandler` 新增 `resolve_event()` 方法
10. `CardInteraction._on_card_flipped()` 改为走 EventHandler 统一入口
11. `DarkWorldFlow` 改为走 EventHandler 统一入口

### Phase 4: StoryManager 条件扩展

12. `StoryManager.check_condition()` 新增资源/道具约束
13. 事件降级逻辑: condition 不满足 → fallback_type → safe

### Phase 5: 清理旧代码

14. `CardConfig` 删除已迁移的字段和方法
15. 删除 `data/events.json`、`data/real_world.json`、`data/card_config.json`
16. `dark_world.json` 精简（删除已迁移的 layers/location_pools）
17. 全局搜索确认无遗漏引用

### Phase 6: 内容填充

18. 为每个明面地点配置差异化事件池和 weight_mods
19. 为每个暗面地点配置独立事件池
20. 添加更多条件化事件（如 min_day:2 / min_clues:3 / has_item 等）

## 七、风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| CardConfig 被大量引用，删除后编译报错 | 高 | 中 | Phase 5 清理前全局搜索确认，CardConfig 保留 shop/dark_world 的字段 |
| 暗面卡牌生成逻辑复杂，改造可能引入 bug | 中 | 高 | 暗面地点的事件池可以先只配类型级事件（即所有 normal 共用 evt_dark_normal），后续再细化 |
| 条件降级为 safe 后玩家体验变差（全是安全格） | 低 | 中 | 可以设计 fallback 链：clue 不满足→plot 不满足→safe，保证有趣事件优先 |
| event_pool.json 文件过大 | 低 | 低 | 事件数量预计 50-100 个，JSON 大小可控 |

## 八、不涉及的改动

- 商店系统 (shop.json / ShopPopupScene)
- 棋盘视觉层 (BoardVisual)
- 资源系统 (GameData)
- 驱魔/拍照机制 (CardInteraction 的相机模式)
- 幽灵 AI (DarkWorld.GhostData)
- NPC 对话 (StoryManager.npc_dialogues)
- 天气系统
