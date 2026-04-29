# 剧情系统 & 线索系统 — 设计方案

## 一、设计目标

1. **Flag 管理机制** — 全局标记系统，记录剧情进度、已触发事件、解锁状态
2. **线索收集系统** — 具名线索条目，可分类浏览，支持配置文件定义
3. **条件化剧情事件** — 翻牌/暗世界事件根据 flag 状态动态选择
4. **条件化 NPC 对话** — NPC 台词根据 flag/线索/天数变化
5. **策划友好** — 所有内容通过 `story_config.json` 配置，无需改代码

## 二、架构概览

```
data/story_config.json               <- 策划编辑的配置文件
scripts/autoload/story_manager.gd    <- 新 Autoload (Flag + 线索 + 条件求值)
scripts/ui/clue_log.gd              <- 线索日志 UI
```

### Autoload 加载顺序

```
CardConfig -> GameTheme -> StoryManager -> GameData
```

StoryManager 在 GameData 之前，因为 GameData.new_game() 需要调用 StoryManager.reset()。

## 三、StoryManager Autoload 接口

```gdscript
extends Node

signal flag_changed(key: String, value: Variant)
signal clue_collected(clue_id: String)

var flags: Dictionary = {}
var collected_clues: Array = []
var current_chapter: String = "prologue"

# Flag CRUD
func set_flag(key: String, value: Variant = true) -> void
func get_flag(key: String, default: Variant = null) -> Variant
func has_flag(key: String) -> bool
func remove_flag(key: String) -> void

# 线索
func collect_clue(clue_id: String) -> void   # 去重 + 发信号
func has_clue(clue_id: String) -> bool
func get_clues_by_category(cat: String) -> Array
func get_all_clues() -> Array

# 条件求值
func check_condition(cond) -> bool  # null=true; Dictionary=递归求值

# 生命周期
func reset() -> void                # new_game() 时调用
func save_state() -> Dictionary     # 存档预留
func load_state(data: Dictionary)   # 读档预留
```

## 四、story_config.json 结构

```json
{
  "chapters": {
    "prologue": { "name": "序章", "unlock": null },
    "chapter1": { "name": "第一章", "unlock": { "flag": "prologue_done" } }
  },
  "clues": {
    "clue_old_photo":   { "name": "泛黄照片", "desc": "一张模糊的合影...", "category": "人物", "icon": "photo" },
    "clue_blood_stain": { "name": "血迹样本", "desc": "干涸的血迹",       "category": "现场", "icon": "blood" }
  },
  "plot_events": [
    {
      "condition": null, "weight": 10,
      "text": "你在角落发现了神秘文字...",
      "set_flags": { "found_inscription": true }, "clue_id": null
    },
    {
      "condition": { "flag": "found_inscription" }, "weight": 15,
      "text": "文字发光，你看到了幻象...",
      "set_flags": { "vision_seen": true }, "clue_id": "clue_old_photo"
    }
  ],
  "clue_events": [
    { "condition": null, "weight": 10, "text": "废墟中发现线索", "clue_id": "clue_blood_stain", "set_flags": {} }
  ],
  "npc_dialogues": {
    "npc_layer1_0": [
      { "condition": null, "lines": ["你也来到了这里...", "小心暗处的东西。"] },
      { "condition": { "flag": "found_inscription" }, "lines": ["你看到了那些文字？", "它们不是人类写的..."] }
    ]
  },
  "dark_clue_events": [
    { "condition": null, "weight": 10, "text": "暗世界线索浮现...", "clue_id": "clue_diary_page", "set_flags": {} }
  ]
}
```

## 五、条件系统格式

check_condition(cond) 递归求值:

| 格式 | 含义 |
|------|------|
| `null` | 始终为真 |
| `{ "flag": "key" }` | flag 存在且 truthy |
| `{ "flag_eq": ["key", val] }` | flag == val |
| `{ "not_flag": "key" }` | flag 不存在或 falsy |
| `{ "has_clue": "id" }` | 已收集该线索 |
| `{ "min_clues": N }` | 收集线索数 >= N |
| `{ "min_day": N }` | 当前天数 >= N |
| `{ "all": [...] }` | AND 组合 |
| `{ "any": [...] }` | OR 组合 |

## 六、需修改的现有文件

| # | 文件 | 修改内容 |
|---|------|---------|
| 1 | `project.godot` | 注册 StoryManager autoload (在 GameData 之前) |
| 2 | `game_data.gd` | new_game() 调用 StoryManager.reset() |
| 3 | `card_interaction.gd` | plot/clue 翻牌查 story_config 选事件、设 flag、收集线索 |
| 4 | `dark_world.gd` | NPC 对话改为条件查找 (替代硬编码数组) |
| 5 | `dark_world_flow.gd` | 暗世界 clue 事件改为条件选择 |
| 6 | `event_popup.gd` | 显示线索获得提示 (可选增强) |
| 7 | `hand_panel.gd` | 添加"线索日志"入口按钮 |

## 七、实施步骤

1. 创建 `story_manager.gd` — Flag/Clue/Condition 核心逻辑 + 加载 JSON
2. 创建 `story_config.json` — 占位内容 (少量线索和事件)
3. 注册 autoload — project.godot + game_data.gd 联动 reset
4. 集成 `card_interaction.gd` — plot/clue 事件条件化选择
5. 集成 `dark_world.gd` — NPC 对话条件化
6. 集成 `dark_world_flow.gd` — 暗世界线索事件条件化
7. 创建线索日志 UI — clue_log.gd + hand_panel 入口
8. 全流程测试

## 八、验证方法

- 新游戏 -> 翻 plot 牌 -> 检查 flag 是否设置
- 再翻 plot 牌 -> 检查是否出现条件事件 (因 flag 已设置)
- 翻 clue 牌 -> 检查线索是否收集 + 日志 UI 显示
- 进暗世界 -> NPC 对话是否根据 flag 变化
- 重新开始 -> 确认所有状态已重置
