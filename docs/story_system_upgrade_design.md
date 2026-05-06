# 剧情系统升级设计 — 支持白夜剧情线

## 一、背景

当前游戏剧情为占位内容（失踪者调查线），需替换为白夜情感线故事。故事稿的核心要素：

- **白夜**：全程陪伴的灵体同伴，与主角形成共生/依赖/冲突关系
- **记忆碎片**（10片）：前世记忆逐步恢复，驱动角色认知转变
- **多结局**（4条）：灵体相伴 / 代餐完成 / 新魔王 / 永囚深渊
- **14天叙事**：苏醒与恐惧 → 磨合与依存 → 真相与决裂 → 终章抉择

当前系统无法承载以上要素，需要系统性升级。

---

## 二、系统总览

```
┌──────────────────────────────────────────────────────────────┐
│                        新增/改动模块                          │
├──────────────┬───────────────────────────────────────────────┤
│  GameData    │  扩展：动态天数（base/extended）               │
│  ChoicePopup │  玩家选择弹窗（扩展 EventPopupScene）          │
│  EndingSystem│  多结局判定 + 结局场景                        │
│  StoryManager│  扩展：白夜数据(trust/power/sleep) / 碎片系统 / 天气条件 / 信任条件 / 章节 │
│  EventPopup  │  扩展：事件选择分支 / 碎片闪回                 │
│  DarkWorld   │  改造：白夜变身 / 碎片获取                    │
└──────────────┴───────────────────────────────────────────────┘
```

注意：**不需要独立的 BaiyeManager autoload**。白夜的行为差异完全由事件 condition 驱动（天数、碎片数、信任度），不需要状态机。

---

## 三、白夜数据 — 嵌入 StoryManager

### 3.1 设计原则

白夜在故事稿中的行为变化（胆怯→依赖→偏执→觉醒→沉睡）本质上是**天数 + 碎片数 + 信任度 + 特定事件flag**的组合结果。白夜没有独立AI，它的"状态"完全由事件文本来呈现，事件本身已有 condition 系统。

因此：
- 不需要白夜状态枚举，事件 condition 直接用 `min_day` / `min_fragments` / `min_trust` 组合
- 不需要独立 autoload，白夜数据放在 StoryManager（主要消费者，避免跨 autoload 循环依赖）
- `sleep_days_left > 0` 就等于"沉睡中"，不需要额外 flag
- 封印走结局 flag `ending_seal`，不需要 `baiye_sealed`

**为什么不放 GameData**：GameData 职责是核心资源（san/health/money/film/inspiration）和游戏状态。白夜的信任度/力量/沉睡是剧情层数据，与核心资源无关，且全部由 StoryManager 的条件系统和事件结算消费。放 GameData 会导致 `GameData.is_baiye_available()` 反向查询 `StoryManager.has_flag()`，形成循环依赖。

### 3.2 StoryManager 新增字段

```gdscript
# story_manager.gd 新增

# 白夜数据
var baiye_trust: int = 0          # 信任度 0-10
var baiye_power: int = 0          # 蓄积力量 0-5，用于暗面变身
var sleep_days_left: int = 0      # 沉睡剩余天数，>0 表示沉睡中

signal baiye_trust_changed(old_value: int, new_value: int)

func add_trust(amount: int) -> void:
    var old = baiye_trust
    baiye_trust = clampi(baiye_trust + amount, 0, 10)
    if old != baiye_trust:
        baiye_trust_changed.emit(old, baiye_trust)

func add_power(amount: int) -> void:
    baiye_power = clampi(baiye_power + amount, 0, 5)

func use_power(cost: int) -> bool:
    if baiye_power >= cost:
        baiye_power -= cost
        return true
    return false

func is_baiye_available() -> bool:
    return sleep_days_left <= 0 and not has_flag("ending_seal")

func tick_sleep() -> void:
    if sleep_days_left > 0:
        sleep_days_left -= 1
```

### 3.3 事件的白夜条件 — 用现有 condition 系统

事件不需要 `requires_baiye` / `baiye_state` 等专有字段，直接用 condition：

```jsonc
// 白夜做饭（需要白夜在、信任度2+、第2天起）
{
  "id": "evt_home_baiye_porridge",
  "type": "safe",
  "condition": { "all": [
    { "baiye_available": true },
    { "min_trust": 2 },
    { "min_day": 2 }
  ]},
  "effects": { "san": 1 },
  "set_flags": {},
  "baiye_trust_change": 1
}

// 白夜偏执阻止出门（碎片7+、第5天起、信任度够了才会管你）
{
  "id": "evt_home_baiye_control",
  "type": "trap",
  "condition": { "all": [
    { "baiye_available": true },
    { "min_fragments": 7 },
    { "min_trust": 5 },
    { "min_day": 5 }
  ]},
  "effects": { "san": -1 },
  "set_flags": {},
  "baiye_trust_change": 0
}

// 白夜沉睡期间的孤独事件（白夜不在时才触发）
{
  "id": "evt_home_baiye_nightmare",
  "type": "monster",
  "condition": { "not": { "baiye_available": true } },
  "effects": { "san": -2 },
  "texts": ["你做了一个噩梦——自己站在废墟上，手握刺穿白夜胸膛的剑。"],
  "set_flags": {}
}
```

### 3.4 StoryManager 条件系统新增

```gdscript
# StoryManager.check_condition() 新增:

# 信任度条件
if cond.has("min_trust"):
    return baiye_trust >= int(cond["min_trust"])

# 白夜是否可用（非沉睡、非封印）
if cond.has("baiye_available"):
    var expected: bool = cond["baiye_available"]
    return is_baiye_available() == expected

# 逻辑取反（支持"白夜不在时"等场景）
if cond.has("not"):
    return not check_condition(cond["not"])
```

### 3.5 事件结算时的信任度变化

事件数据保留 `baiye_trust_change` 字段（int，可正可负），在 `StoryManager.apply_event_effects()` 中结算。已有 `apply_event_effects()` 处理 `set_flags` + `clue_id`，扩展即可：

```gdscript
func apply_event_effects(event: Dictionary) -> Dictionary:
    # ... 现有的 set_flags + clue_id 逻辑 ...

    # 新增：信任度变化
    var trust_change: int = int(event.get("baiye_trust_change", 0))
    if trust_change != 0:
        add_trust(trust_change)

    # 新增：沉睡触发（变身事件设置）
    var sleep_trigger: int = int(event.get("trigger_sleep", 0))
    if sleep_trigger > 0:
        sleep_days_left = sleep_trigger

    return result
```

### 3.6 白夜行为差异与 condition 的映射

| 故事稿中的白夜行为 | 实际驱动条件 |
|---|---|
| 胆怯躲藏（第1-2天） | `{ "min_day": 1 }` + `{ "max_trust": 2 }` |
| 主动训练、依赖（第3-4天） | `{ "min_trust": 3 }` + `{ "min_day": 3 }` |
| 控制欲（第5天） | `{ "min_fragments": 7 }` + `{ "min_trust": 5 }` + `{ "min_day": 5 }` |
| 变身击退敌人 | 碎片5的选择事件，选择后 `set_flags: { baiye_transformed: true }` + `trigger_sleep: 3` |
| 偏执摔手机 | `{ "min_fragments": 7 }` + `{ "min_day": 8 }` |
| 恢复记忆后真诚 | `{ "min_fragments": 10 }` |
| 沉睡中 | `{ "not": { "baiye_available": true } }` |
| 被封印 | `{ "flag": "ending_seal" }` |

---

## 四、ChoicePopup — 玩家选择系统

### 4.1 设计目标

故事稿中关键节点需要玩家选择（接受/拒绝白夜、封印/融合/吞噬等），选择影响 flag、资源、结局走向。

### 4.2 数据格式 — event_pool.json 事件增加 choices

```jsonc
{
  "id": "evt_choice_final_decision",
  "type": "plot",
  "world": ["real"],
  "base_weight": 100,
  "texts": ["你想起了一切。白夜站在你面前，等待你的回答。"],
  "condition": { "all": [{ "flag": "memory_complete" }, { "min_fragments": 10 }] },
  "is_choice": true,
  "choices": [
    {
      "label": "我不会变成她，但我也不会离开你",
      "effects": { "san": 2 },
      "set_flags": { "chose_acceptance": true, "ending_spirit": true },
      "baiye_trust_change": 5
    },
    {
      "label": "让我变成她吧",
      "effects": { "inspiration": 3 },
      "set_flags": { "chose_merge": true, "ending_substitute": true },
      "baiye_trust_change": 0
    },
    {
      "label": "吞噬白夜的力量",
      "effects": { "san": -5, "inspiration": 10 },
      "set_flags": { "chose_devour": true, "ending_demon": true },
      "baiye_trust_change": -10
    }
  ],
  "set_flags": {},
  "clue_id": null,
  "fallback_type": "safe"
}
```

### 4.3 UI 设计

在 `EventPopupScene` 基础上扩展：

```
┌─────────────────────────────────────────────┐
│  📖  终章抉择                                │
│                                              │
│  你想起了一切。白夜站在你面前，              │
│  等待你的回答。                              │
│                                              │
│  ┌─────────────────────────────────────┐     │
│  │ 我不会变成她，但我也不会离开你       │     │
│  └─────────────────────────────────────┘     │
│  ┌─────────────────────────────────────┐     │
│  │ 让我变成她吧                         │     │
│  └─────────────────────────────────────┘     │
│  ┌─────────────────────────────────────┐     │
│  │ 吞噬白夜的力量                       │     │
│  └─────────────────────────────────────┘     │
└─────────────────────────────────────────────┘
```

- 选择按钮数量 2-3 个
- 选中后执行对应 `effects` + `set_flags` + `baiye_trust_change`
- `is_blocking: true`（选择前不能操作棋盘）

### 4.4 代码改动

- `EventPopupScene` 增加 `_choice_container: VBoxContainer`，当 `is_choice == true` 时显示选项按钮
- `CardInteraction` / `EventHandler` 解析事件时检测 `is_choice`，走选择分支逻辑
- 选择结果通过信号回调处理

---

## 五、EndingSystem — 多结局系统

### 5.1 结局定义

```jsonc
// data/endings.json (新增)
{
  "endings": [
    {
      "id": "ending_spirit",
      "name": "灵体相伴",
      "desc": "白夜变成普通的灵体失去大部分力量，但保留了情感。一人一灵继续生活……",
      "condition": { "all": [{ "flag": "ending_spirit" }, { "not_flag": "ending_substitute" }, { "not_flag": "ending_demon" }] },
      "priority": 10
    },
    {
      "id": "ending_substitute",
      "name": "代餐完成",
      "desc": "主角融合前世记忆，变成了'她'。白夜恢复人类形态，但主角每日对镜梳妆时，总觉得自己在演别人……",
      "condition": { "flag": "ending_substitute" },
      "priority": 20
    },
    {
      "id": "ending_demon",
      "name": "新魔王",
      "desc": "主角吞噬白夜，成为新魔王。暗面扩张，整栋居民楼被侵蚀……",
      "condition": { "flag": "ending_demon" },
      "priority": 30
    },
    {
      "id": "ending_seal",
      "name": "永囚深渊",
      "desc": "主角和魔王达成协议，将白夜永久封印回暗面。公寓空了，雷雨夜不会再有人钻被窝……",
      "condition": { "all": [{ "flag": "ending_seal" }, { "not_flag": "ending_spirit" }] },
      "priority": 15
    },
    {
      "id": "ending_survive",
      "name": "迷雾中的日常",
      "desc": "7天过去了，你活了下来。但记忆的碎片仍散落在暗面深处，白夜仍在等待……",
      "condition": null,
      "priority": 0
    }
  ]
}
```

### 5.2 判定逻辑

游戏结束时（存活到 `get_max_days()` 或 san/health 归零）：

1. 遍历所有结局，按 `priority` 降序排列
2. 取第一个 `check_condition()` 为真的结局
3. 如果全部不满足，使用 `condition == null` 的兜底结局
4. 进入结局场景

### 5.3 结局场景

新增 `scenes/ending_scene.tscn`：
- 全屏展示结局标题 + 描述文本 + 氛围图
- "重新开始" 按钮

---

## 六、记忆碎片系统 — 替换现有线索

### 6.1 碎片定义

将 `story_config.json` 的 `clues` 替换为 `fragments`：

```jsonc
"fragments": {
  "frag_01": {
    "name": "并肩的背影",
    "desc": "模糊的闪回画面：你和一个身影站在废墟之上，身后是燃烧的城。",
    "category": "前世记忆",
    "icon": "🧩",
    "flashback": "你和白夜并肩站在魔王城废墟上，它还不是怪物，是一个有着金色眼睛的少年。他说：'我会一直守着你。'",
    "pain_effect": { "san": -1 },
    "order": 1
  }
  // ... 共10片
}
```

### 6.2 与线索系统的关系

碎片**复用**线索系统的收集/去重/信号机制，仅扩展以下内容：

| 现有字段 | 碎片扩展 |
|---------|---------|
| `clue_id` / `collect_clue()` | 保留，碎片也走 `collect_clue()` |
| `collected_clues` | 保留，碎片ID也存入此数组 |
| `get_clue_count()` | 直接反映碎片收集数 |
| — | **新增** `flashback` 字段：收集时弹出的闪回文本 |
| — | **新增** `pain_effect` 字段：收集时的幻痛效果 |
| — | **新增** `order` 字段：碎片编号（1-10） |
| — | **新增** `min_fragments` 条件：`check_condition({ "min_fragments": N })` |

### 6.3 代码改动

- `StoryManager` 新增 `min_fragments` 条件支持（等价于 `min_clues`，但语义明确）
- `StoryManager` 新增 `get_fragment_count()` 和 `get_fragments_ordered()` 方法
- 事件弹出时检测 `flashback` 字段，触发闪回弹窗（复用 EventPopup，类型为 `flashback`）
- 闪回弹窗额外显示 `pain_effect` 资源变化

### 6.4 条件系统新增

```gdscript
# StoryManager.check_condition() 新增:
if cond.has("min_fragments"):
    return get_fragment_count() >= int(cond["min_fragments"])
```

---

## 七、章节系统重写

### 7.1 新章节结构

```jsonc
"chapters": {
  "prologue": {
    "name": "序章：迷雾降临",
    "unlock": null,
    "days": [1],
    "fragment_range": [0, 2]
  },
  "act1": {
    "name": "第一幕：苏醒与恐惧",
    "unlock": { "min_day": 1 },
    "days": [1, 2],
    "fragment_range": [1, 2]
  },
  "act2": {
    "name": "第二幕：磨合与依存",
    "unlock": { "all": [{ "min_fragments": 2 }, { "min_trust": 3 }] },
    "days": [3, 7],
    "fragment_range": [3, 7]
  },
  "act3": {
    "name": "第三幕：真相与决裂",
    "unlock": { "min_fragments": 7 },
    "days": [7, 12],
    "fragment_range": [8, 10]
  },
  "finale": {
    "name": "终章：抉择",
    "unlock": { "all": [{ "min_fragments": 10 }, { "flag": "memory_complete" }] },
    "days": [13, 14],
    "fragment_range": [10, 10]
  }
}
```

### 7.2 章节对事件的影响

每个事件可加 `chapter` 字段限制只在特定章节出现：

```jsonc
"chapter": ["act1", "act2"]  // 仅在第一幕和第二幕出现
```

事件选择时额外过滤：当前章节在事件的 `chapter` 数组中（`chapter` 为空则不限）。

---

## 八、天气条件扩展

### 8.1 条件系统新增

```gdscript
# StoryManager.check_condition() 新增:
if cond.has("weather"):
    return Weather.current_weather == cond["weather"]
```

### 8.2 使用示例

```jsonc
{
  "id": "evt_home_thunder_night",
  "condition": { "weather": "thunder" },
  "texts": ["雷声轰鸣，白夜缩成一团钻进了你的被窝……"]
}
```

当前 `Weather` 类已有 `current_weather` 属性，直接读取即可。

---

## 九、动态游戏时长 — 7天生存 + 14天延展

### 9.1 设计思路

- **基础期**（1-7天）：所有玩家经历，目标是存活。7天结束时若未收集全碎片，进入"迷雾中的日常"结局
- **延展期**（8-14天）：收集全10片碎片后解锁，进入终章抉择。这7天承载真相与决裂的叙事
- **设计意图**：碎片收集既是叙事驱动，也是游戏延长的门锁——不探索就只能活7天，探索够了才能看到完整故事

### 9.2 GameData 改动

```gdscript
# game_config.json
{
  "max_days_base": 7,
  "max_days_extended": 14,
  // ... 其余字段不变
}

# game_data.gd 新增
var days_extended: bool = false

signal extension_unlocked

func get_max_days() -> int:
    if days_extended:
        return _config.get("max_days_extended", 14)
    return _config.get("max_days_base", 7)

## 检查是否满足延展条件（碎片全收集）
func check_extension() -> void:
    if not days_extended and StoryManager.get_fragment_count() >= 10:
        days_extended = true
        extension_unlocked.emit()

## 暗面进入条件（委托 StoryManager）
func can_enter_dark_world() -> bool:
    return StoryManager.is_baiye_available()
```

### 9.3 延展触发流程

```
第7天日终结算:
├── 碎片 < 10 → 游戏结束 → 判定结局（通常为"迷雾中的日常"）
└── 碎片 >= 10 → days_extended = true
    ├── 弹出剧情提示："记忆涌来，你想起了一切……"
    ├── 第8天开始，继续游戏
    └── 解锁终章事件池 + 选择事件
```

### 9.4 game_config.json 稀缺度与缩放

```jsonc
{
  "max_days_base": 7,
  "max_days_extended": 14,
  "location_scarcity": {
    "day_1_2": 3,
    "day_3_5": 2,
    "day_6_7": 2,
    "day_8_10": 2,
    "day_11_14": 1
  },
  "monster_scaling": {
    "base_san": -2,
    "inspiration_base": 10,
    "inspiration_step": 15,
    "max_extra_damage": 4,
    "health_damage_table": [0, -1, -2, -3, -3]
  }
}
```

### 9.5 需要联动调整

| 项目 | 改动 |
|-----|------|
| `game_config.json` | max_days_base=7, max_days_extended=14, 稀缺度曲线扩展 |
| `game_data.gd` | 新增 `days_extended` + `get_max_days()` + `check_extension()` + `can_enter_dark_world()` |
| `story_manager.gd` | 新增 `baiye_trust` / `baiye_power` / `sleep_days_left` + 白夜方法 + 条件扩展 |
| `card_manager.gd` | 日程数量读取 `get_max_days()` 而非硬编码 |
| `dark_world.json` | 暗面层级解锁阈值不变（灵感15/25/45），碎片主要在暗面获取 |
| `game_flow.gd` | 日终结算时调用 `check_extension()` + `tick_sleep()` |

---

## 十、暗面改造

### 10.1 白夜在暗面的影响

白夜的影响由 `StoryManager` 的 `baiye_trust` / `sleep_days_left` / `baiye_power` 数值组合决定，而非状态枚举：

| 条件 | 暗面效果 |
|-----|---------|
| `sleep_days_left > 0` | 无法进入暗面 |
| `min_trust < 3` + `min_day <= 2` | 可进入，但白夜不敢跟随，主角独自探索 |
| `min_trust >= 3` | 白夜跟随，每层揭示1个安全格子，可变身1次（消耗 power） |
| `min_fragments >= 7` + `min_trust >= 5` | 白夜跟随但偏执，每次移动额外消耗1 san |
| `min_fragments >= 10` | 白夜完整能力：揭示安全格子 + 变身 + 免疫暗面 san 衰减 |
| `flag: ending_seal` | 暗面不稳定，san 持续衰减 |

这些效果在 `dark_world_flow.gd` 中通过读取 StoryManager 字段实现，不需要状态机。

### 10.2 白夜变身

故事稿中白夜变身出现过2次：
- 第6天：为夺取第五片碎片变身击退精英怪物，代价是沉睡数天
- 第9-13天：两人打败魔王

这些都是**叙事事件**，不需要独立的战斗系统。用现有的选择事件机制实现：

| 场景 | 实现 |
|-----|------|
| 精英怪物（碎片5） | 暗面 encounter 事件，`is_choice: true`：<br>选项A"让白夜变身"→ effects: {san: -1}, set_flags: {baiye_transformed: true}, trigger_sleep: 3, 获得碎片<br>选项B"撤退"→ 无收益退出暗面 |
| 魔王（碎片10） | 深层 abyss_core 事件，`is_choice: true`：<br>选项A"正面迎战"→ effects: {san: -3}, set_flags: {demon_defeated: true}, 获得最终碎片<br>选项B"先撤退"→ 退出暗面，下次再挑战 |
| 其他战斗场景 | 用现有暗面幽灵碰撞机制（san-2）即可 |

白夜变身的效果简化为：当前格子幽灵被击退，碰撞伤害该次减半。变身消耗全部 power，变身后 `sleep_days_left = 3`（通过事件的 `trigger_sleep: 3` 字段设置）。不需要额外的战斗UI或回合制系统。

### 10.3 碎片在暗面的获取

暗面 `clue` 类型卡牌改为可掉落碎片，`dark_clue_events` 扩展 `fragment_id` 字段：

```jsonc
{
  "id": "dark_frag_05",
  "condition": { "min_fragments": 4, "not_flag": "frag_05_collected" },
  "weight": 14,
  "text": "暗面深处，一段被封印的记忆向你涌来……",
  "fragment_id": "frag_05",
  "set_flags": { "frag_05_collected": true }
}
```

---

## 十一、改动文件清单

| 优先级 | 文件 | 改动类型 | 改动内容 |
|--------|------|---------|---------|
| P0 | `scripts/autoload/game_data.gd` | 修改 | 新增 days_extended + get_max_days() + check_extension() + can_enter_dark_world() |
| P0 | `scripts/ui/event_popup_scene.gd` | 修改 | 增加选择分支 UI |
| P0 | `data/endings.json` | **新增** | 结局定义 |
| P0 | `scripts/autoload/ending_manager.gd` | **新增** | 结局判定 + 结局场景切换 |
| P0 | `data/game_config.json` | 修改 | max_days_base/extended, 稀缺度/缩放调整 |
| P1 | `scripts/autoload/story_manager.gd` | 修改 | 新增 baiye_trust/power/sleep_days_left + 白夜方法 + 条件系统扩展: min_trust / baiye_available / not / min_fragments / weather / chapter |
| P1 | `data/story_config.json` | 修改 | 章节重写为4幕、线索替换为碎片、NPC对话改为白夜对话 |
| P1 | `scripts/core/board.gd` | 修改 | 事件选择增加章节过滤 |
| P1 | `scripts/lib/event_handler.gd` | 修改 | 解析 choices / baiye_trust_change / 碎片幻痛 |
| P1 | `scripts/controllers/card_interaction.gd` | 修改 | 选择分支回调、信任度结算 |
| P1 | `scripts/controllers/game_flow.gd` | 修改 | 日终结算: check_extension() + StoryManager.tick_sleep() |
| P1 | `data/event_pool.json` | 修改 | 事件 condition 用 min_trust/baiye_available 替代 requires_baiye/baiye_state |
| P2 | `scripts/core/dark_world.gd` | 修改 | 白夜跟随/变身效果（读 StoryManager 字段） |
| P2 | `scripts/controllers/dark_world_flow.gd` | 修改 | 暗面进入条件检查、碎片获取 |
| P2 | `data/dark_world.json` | 修改 | 暗面碎片事件、层级解锁阈值 |
| P2 | `scenes/ending_scene.tscn` | **新增** | 结局展示场景 |
| P2 | `scripts/ui/clue_log.gd` | 修改 | 碎片闪回查看 |

---

## 十二、实施阶段

### Phase 1: 基础骨架（P0）

1. `GameData` 新增动态天数 + `can_enter_dark_world()`
2. `StoryManager` 新增白夜字段（trust/power/sleep）+ 方法
3. `EventPopupScene` 增加选择分支 UI
4. 创建 `EndingManager` + `endings.json`
5. `game_config.json` 动态天数配置
6. 验证：白夜信任度可增减、选择弹窗可交互、结局可判定、天数可延展

### Phase 2: 剧情数据迁移（P1）

1. `story_config.json` 章节重写 + 碎片替换线索
2. `StoryManager` 扩展条件系统（min_trust / baiye_available / not / min_fragments / weather / chapter）
3. `event_pool.json` 事件 condition 改写
4. `Board` / `EventHandler` 集成 condition 过滤 + 信任度结算
5. 验证：翻牌出现白夜相关事件、碎片可收集、章节正确推进

### Phase 3: 暗面改造（P2）

1. 暗面白夜跟随效果（读 StoryManager 字段）
2. 白夜变身机制（消耗 power → sleep_days_left）
3. 暗面碎片掉落
4. 验证：暗面有白夜参与效果、碎片可在暗面获取

### Phase 4: 内容填充 + 打磨

1. 文案按模板补全所有地点事件（含5个缺失地点）
2. 碎片闪回文本润色
3. 结局文案细化
4. 全流程测试 + 数值平衡
