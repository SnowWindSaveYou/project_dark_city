# Godot 版本升级追踪文档

> **目标**: 将 Lua 版 (main 分支) 的新功能同步到 Godot 版 (godot_scene_dev 分支)
>
> **原则**: Godot 版使用 JSON 数据驱动，Lua 版硬编码在代码中的数据需转为 JSON；只需数据结构和内容对齐，不改变架构风格
>
> **基准对比时间**: 2026-05-08
>
> **Lua 版 HEAD**: main `b3b634d` (fix: CardInteraction/EventPool/NPCManager)
>
> **Godot 版 HEAD**: godot_scene_dev `e7b9d21` (chore: 移除不应被追踪的文件)

---

## 整体差异概述

Lua 版在 Godot 版的卡牌棋盘基础上，增加了三大维度：

1. **叙事层** -- 故事系统 + 5 个结局 + 章节推进 + 记忆碎片
2. **平行世界** -- 暗面三层地牢 + 能量 + 幽灵AI + 精英/Boss + 碎片掉落
3. **角色生态** -- 白夜伴侣 + NPC 系统 (房东/猫) + 对话组/资源兑换

以及两个贯穿所有系统的新资源: `health`(健康/步数上限) 和 `inspiration`(灵感/影响怪物伤害和线索触发)。

---

## 一、全新系统 (Godot 版需新建)

### 1.1 故事系统核心 [P0]

- **Lua 来源**: `StoryManager.lua` + `StoryConfig.lua`
- **Godot 现状**: `autoload/story_manager.gd` 已有雏形 (条件引擎 14 种条件、线索管理、NPC 对话选择)，但缺少白夜状态、碎片系统、章节推进、动态天数
- **需要做的**:
  - [x] `story_manager.gd` 新增状态字段: `baiye_trust`(0-10), `baiye_power`(0-5), `sleep_days_left`, `fragments{}`, `currentChapter` ✅ P2.1
  - [x] `story_manager.gd` 新增条件类型: `min_trust`, `max_trust`, `min_fragments`, `baiye_available`, `chapter`, `weather`, `not`(取反) ✅ P2.2
  - [x] `story_manager.gd` 新增效果应用: `set_flags`(数组或字典), `baiye_trust_change`, `trigger_sleep`, `fragment_id`, `baiye_power_change`, `effects` ✅ P2.3
  - [x] `story_manager.gd` 新增 `get_max_days()`: 碎片 >= threshold 返回 extended_days, 否则 base_days ✅ P2.1
  - [x] `data/story_config.json` 更新: 章节(4)、结局(5)、碎片(10)、天数常量 ✅ P1.1-P1.7
  - [x] `game_data.gd` 更新: health/inspiration 资源 + current_weather + check_defeat/check_victory 适配 ✅ P2.4
  - [x] 新建 `scripts/core/ending_system.gd`: 优先级结局匹配 + 展示数据 + 画廊 ✅ P2.5

**Lua 数据详情** (需转为 JSON):

章节:
```
awakening: Day 1-3
bonding:   Day 4-7
truth:     Day 8-11
finale:    Day 12-14
```

结局 (按优先级):
```
companion  (p=10): acceptance flag + 10 碎片 -> victory
seal       (p=15): ending_seal flag -> victory
substitute (p=20): chose_merge flag -> victory
dark_lord  (p=30): chose_devour flag -> defeat
default    (p=99): 无条件 -> victory
```

碎片:
```
frag_01: 初遇       frag_06: 暗市秘密
frag_02: 暗巷回忆    frag_07: 商人的提示
frag_03: 录音带      frag_08: 面具之下
frag_04: 电话        frag_09: 深渊真相
frag_05: 守卫之战    frag_10: 觉醒
```

条件引擎原子 (在 Godot 已有的 14 种基础上新增):
```
min_trust, max_trust     -- 白夜信任度范围
min_fragments            -- 最少碎片数
baiye_available          -- 白夜可用 (非沉睡)
chapter                  -- 当前章节匹配
weather                  -- 天气匹配
not                      -- 取反包装器
```

---

### 1.2 多结局系统 [P0]

- **Lua 来源**: `EndingSystem.lua`
- **Godot 现状**: 仅有胜/败二元判定
- **需要做的**:
  - [x] 新建 `scripts/core/ending_system.gd` ✅ P2.5
  - [x] 遍历 `_endings` 按优先级返回首个匹配结局 ✅ P2.5
  - [x] `game_over_scene.gd` 改造: 支持 5 种结局展示 (不同标题/描述/配色) ✅ P5.2

---

### 1.3 里程碑事件系统 [P0]

- **Lua 来源**: `MilestoneManager.lua` + `data/milestone_events.lua`
- **Godot 现状**: 无
- **需要做的**:
  - [x] 新建 `data/milestone_events.json` ✅ P1
  - [x] 新建 `autoload/milestone_manager.gd` ✅ P3.1
  - [x] 实现: 按 hook_id 索引、query(最高优先级匹配)、try_trigger(onceFlag+信号) + on_event_complete(效果+碎片) ✅ P3.1
  - [x] 注册 MilestoneManager autoload 到 project.godot ✅ P3.1

**9 个 Hook 点**:
```
enter_dark_world   -- 首次进入暗面
exit_dark_world    -- 首次退出暗面
open_shop          -- 首次开商店
baiye_sleep        -- 白夜入睡时
baiye_return       -- 白夜返回时
fragment_collect   -- 收集碎片时
chapter_enter      -- 进入新章节时
resource_low       -- 资源危急时
use_item           -- 使用道具时
```

每个事件结构:
```json
{
  "id": "ms_enter_dark_first",
  "hookId": "enter_dark_world",
  "priority": 10,
  "conditions": { "flag": "..." },
  "onceFlag": "ms_enter_dark_first_done",
  "dialogue": [
    { "speaker": "白夜", "text": "..." },
    { "speaker": "苏柚", "text": "..." }
  ],
  "choiceEffects": { "set_flags": [...], "baiye_trust_change": 1 }
}
```

---

### 1.4 翻牌故事事件 [P0]

- **Lua 来源**: `StoryEvents.lua` + `StoryEventManager.lua`
- **Godot 现状**: 无
- **需要做的**:
  - [x] 新建 `data/story_events.json` ✅ P1
  - [x] 新建 `scripts/core/story_event_manager.gd` ✅ P3.2
  - [x] 实现: query_event(按 card_type + 条件匹配) + trigger_event + on_event_complete(效果+碎片+里程碑 hook) ✅ P3.2

**5 个翻牌故事事件**:
| ID | 触发条件 | 选择/效果 |
|----|---------|----------|
| `plot_newspaper` | Day 2+, 非 plot_newspaper_done | 研究: +1 trust +1 ins / 丢弃: -1 trust |
| `clue_graffiti` | Day 1+, 非 clue_graffiti_done | 收集碎片 frag_01 |
| `plot_phone_call` | Day 4+, bonding 章节, 非 done | 倾听: -1 trust +2 ins / 挂断: +2 trust, 碎片 frag_04 |
| `plot_mirror` | Day 3+, baiye_available, 非 done | 纯对话 |
| `clue_tape` | Day 6+, trust>=3, 非 done | 碎片 frag_03 |

---

### 1.5 早间事件 [P0]

- **Lua 来源**: `data/morning_events.lua`
- **Godot 现状**: 无
- **需要做的**:
  - [x] 新建 `data/morning_events.json` ✅ P1
  - [x] `story_event_manager.gd` 增加 query_morning_event / trigger_morning_event / on_morning_event_complete ✅ P3.2
  - [x] `story_manager.gd` 增加 `max_day` 条件支持 (晨间事件需要) ✅ P3.2

**7 个早间事件** (Day 1-7):
| Day | 内容 | 分支 |
|-----|------|------|
| 1 | 苏柚发现壁橱中的白夜 | 无 |
| 2 | 雷雨天，白夜害怕，首次肢体接触 | 无 |
| 3 | 与白夜训练 | 无 |
| 4 | 跟随行为建立 | 无 |
| 5 | 隔离暗示，保护 vs 控制 | 无 |
| 6 | 白夜沉睡 vs 清醒 (两个变体) | 条件分支 |
| 7 | 核心揭示: 棠的身份，苏柚是"替代模具" | 无 |

---

### 1.6 白夜角色 [P1]

- **Lua 来源**: `Baiye.lua`
- **Godot 现状**: 无
- **需要做的**:
  - [x] 新建 `scripts/visual/baiye.gd` ✅ P4.1
  - [x] 2D 数据层 (RefCounted + get_draw_data), 跟随 Token (指数衰减), 浮动/呼吸动画, 显隐过渡 ✅ P4.1
  - [x] 贴图: `image/白夜_chibi_20260506003802.png` ✅ P4.1
  - [x] 跟随条件: trust >= 3 AND available (非沉睡) ✅ P4.1

**关键参数**:
```
SPRITE_3D_H = 0.20      # Billboard 高度
OFFSET_X = -0.20         # Token 左侧偏移
OFFSET_Z = 0.14          # 略微前方
FOLLOW_SPEED = 4.0       # 跟随速度
BASE_Y = 0.30            # 基准浮空高度
SPIRIT_ALPHA = 0.50      # 半透明
浮动: Y sin(1.8Hz, 0.018amp) + X sin(1.1Hz, 0.010amp)
呼吸: scale 1.0 +/- 0.035
```

---

### 1.7 NPC 系统升级 [P1]

- **Lua 来源**: `NPCManager.lua` + `data/npc_dialogues.lua`
- **Godot 现状**: `npc_manager.gd` 有基础生成/移除/呼吸动画, 但无对话系统
- **需要做的**:
  - [x] 新建 `data/npc_dialogues.json` (房东 5 组 + 猫 5 组对话) ✅ P1
  - [x] `npc_manager.gd` 增加: 类型注册表(JSON)、多对话组随机、资源交易执行、每日冷却追踪、action_config、信号驱动 ✅ P4.2
  - [x] NPC 出场规则集成到 `game_flow.gd` ✅ P5.1

**NPC 出场规则**:
```
Day 1:  固定出 琴馨 (相机教学)
Day 2+: 50% 概率出 猫
Day 3+: 固定出 房东 (资源兑换)
```

**房东对话 (5 组)**:
| 组 | 主题 | 兑换 |
|----|------|------|
| 1 | 关心租客 | 2 health -> 3 san |
| 2 | 聊白夜 | 2 san -> 3 health |
| 3 | 谈天气 | 2 health -> 2 film |
| 4 | 纯寒暄 | 无 |
| 5 | 双向选择 | 2 health->2 san 或 2 san->2 health |

**猫对话 (5 组)**:
| 组 | 交互 | 效果 |
|----|------|------|
| 1 | 摸猫 / 蹲下看 | +1 san / 无 |
| 2 | 陪它 / 喂食 | +1 san / -5 money +2 san |
| 3 | 纯叙事 | 无 |
| 4 | 猫叼硬币 | +8 money / +1 san |
| 5 | 陪玩 / 只看 | +1 san / 无 |

---

### 1.8 音频管理器 [P2]

- **Lua 来源**: `AudioManager.lua`
- **Godot 现状**: ✅ 已完成 (P6)
- **已完成**:
  - [x] 新建 `autoload/audio_manager.gd` ✅ P6.2
  - [x] BGM 双播放器交叉淡入淡出 (1.5s 线性) ✅ P6.2
  - [x] SFX 对象池 (max 12), 音调随机化 (±4%), Combo 系统 (5 级, 每级 +6%) ✅ P6.2
  - [x] BGM/SFX 映射 (key→path), 15 个 SFX key ✅ P6.2
  - [x] AudioManager autoload 注册 ✅ P6.4a
  - [x] 集成到 game_flow / card_interaction / dark_world_flow ✅ P6.4c

---

### 1.9 调试面板 [P2]

- **Lua 来源**: `DebugPanel.lua`
- **Godot 现状**: ✅ 已完成 (P6)
- **已完成**:
  - [x] 新建 `scripts/ui/debug_panel.gd` ✅ P6.3
  - [x] F1 按键切换显隐 ✅ P6.3
  - [x] 状态显示: Day, Phase, State, SAN, Health, Inspiration, Trust, Power, Money, Film, Order, Fragments, Chapter, DarkActive, CardsRevealed ✅ P6.4b
  - [x] 13 个快捷按钮: enter_dark, insp_10/50, trust_up/down, power_up/max, clear_sleep, frag_1/4/9, reset_flags, next_day ✅ P6.4b
  - [x] 集成到 main.gd (信号连接 + _process 刷新) ✅ P6.4b

---

## 二、现有系统升级

### 2.1 game_flow.gd [P0]

- [x] NPC 出场逻辑: Day 3+ 房东 / 50% 猫 ✅ P5.1
- [x] 里程碑链调用: `baiye_return -> chapter_enter -> resource_low -> _begin_new_day` ✅ P5.1
- [x] 早间事件触发: `_try_morning_event()` 在天数过渡完成后调用 ✅ P5.1
- [x] 动态天数: 使用 `StoryManager.get_max_days()` 代替固定 `MAX_DAYS` ✅ P5.1
- [x] 每日资源回复: +1 san, +1 order, film→3, +10 money ✅ P5.1
- [x] 每日 NPC 清理: `npc_manager.reset_daily()` + `destroy_npc_nodes()` ✅ P5.1
- [x] 多结局判定: `EndingSystem.evaluate()` 替代二元胜/败 ✅ P5.1
- [x] 信号驱动对话: `event_dialogue_requested` 信号委托 main.gd 展示 ✅ P5.1
- [x] 子系统重置: `restart_game()` 重置 StoryManager/MilestoneManager/NPC/事件 ✅ P5.1

### 2.2 card_interaction.gd [P0]

- [x] BFS 自动寻路: 沿已翻开卡牌路径自动行走 (`_find_path()` + `_execute_auto_walk()`) ✅ P5.4
- [x] 故事事件拦截: plot/clue 牌 -> `StoryEventManager.query_event()` -> 对话路径 (`_try_story_event()`) ✅ P5.4
- [x] NPC 同格对话: 到达已翻开格子触发 `NPCManager.get_random_dialogue()` (`_try_npc_dialogue()`) ✅ P5.4
- [x] 道具使用: F4 键驱魔香, 从背包消耗 + 触发 `MilestoneManager.try_trigger("use_item")` ✅ P5.4
- [x] 兑换事件: hospital/park/gym 30% 触发概率, 复用 RiftPopup 自定义确认 (`_try_conversion_event()`) ✅ P5.4
- [x] 灵感阈值退化: `inspiration < 20` 时线索牌退化为 safe ✅ P5.4
- [x] 步数限制: `health` 值 = 每日最大步数 (`_steps_today` + `reset_daily_steps()`) ✅ P5.4
- [x] 地标光环: 地标周围 monster/trap 中和为 safe (已在 `board.gd._apply_landmark_aura()` 实现) ✅ 既有

### 2.3 dark_world.gd [P0]

- [x] 暗面碎片掉落: 按碎片数 + 最低层级决定 (frag_02~09) ✅ P5.5b-2 (`check_fragment_drop()`)
- [x] 精英守卫: 碎片>=4 + 白夜跟随 + clue 卡 -> 对话选择 -> 变身(消耗全部 power, 沉睡 3 天, 获 frag_05) ✅ P5.5b-2 (`check_elite_encounter()`)
- [x] 深渊 Boss: 碎片>=9 + 白夜跟随 -> 对话选择 -> 迎战(-3 san, 获 frag_10, 设 memory_complete) ✅ P5.5b-2 (`check_boss_encounter()`)
- [x] item 奖励池 (10 种, 含稀有属性上限): san+5(x2), money+15(x2), film+1(x2), ins+3(x2), sanMax+2(x1), healthMax+2(x1) ✅ P5.5b-2 (`roll_item_reward()`)
- [x] 层间通道: L2 双向通道 (去 L1 / 去 L3) ✅ P5.5b-3 (PASSAGE branch in flow)
- [x] 相机驱灵: 拍照消灭幽灵 (淡出动画) ✅ P5.5b-3 (`_handle_dark_camera()`)
- [x] 能量初始化: 进入时 energy = 当前 san 值 ✅ P5.5b-2 (`mini(san, max_energy)`)

### 2.4 dark_world_flow.gd [P1]

- [x] 白夜跟随判定: trust >= 3 AND available ✅ P5.5b-3 (`_baiye_following` + `should_show()`)
- [x] 里程碑 hook: enter_dark_world / exit_dark_world ✅ P5.5b-3 (`MilestoneManager.try_trigger()`)
- [x] 碎片掉落集成: CLUE 分支触发 `check_fragment_drop()` ✅ P5.5b-3
- [x] 精英遭遇集成: CLUE 分支触发 `check_elite_encounter()` ✅ P5.5b-3
- [x] Boss 遭遇集成: ABYSS_CORE 分支触发 `check_boss_encounter()` ✅ P5.5b-3
- [x] 道具奖池集成: ITEM 分支触发 `roll_item_reward()` ✅ P5.5b-3
- [x] L2 双向通道: PASSAGE 分支根据当前层选择方向 ✅ P5.5b-3
- [x] 遭遇对话系统: `_trigger_encounter_dialogue()` + `_apply_encounter_effects()` ✅ P5.5b-3

### 2.5 game_over_scene.gd [P1]

- [x] 支持 5 种结局展示 (不同标题/副标题/配色) ✅ P5.2
- [x] 结局来源: `EndingSystem.evaluate()` 通过 `game_flow.gd` 传入 ✅ P5.2
- [x] 向后兼容: 无结局数据时回退到旧版二元逻辑 ✅ P5.2
- [x] 光晕配色: 使用缓存的 `_title_color` 替代硬编码 safe/danger ✅ P5.2

---

## 三、数据文件变更

### 3.1 需更新的现有 JSON

| 文件 | 变更内容 | 状态 |
|------|---------|------|
| `data/game_config.json` | 新增 `health`/`inspiration` 资源 + `location_scarcity` | ✅ |
| `data/event_pool.json` | 新增 cemetery/gym 地点; 地点权重偏移; 怪物动态伤害公式; 兑换事件; 传送陷阱 | [ ] |
| `data/locations.json` | 同步 cemetery/gym; 更新安全地点效果 (park/gym/hospital->+health) | [ ] |
| `data/story_config.json` | 补充章节(4 阶段), 结局(5 个), 碎片(10 个), 天数常量 | [ ] |
| `data/dark_world.json` | 补充碎片掉落表, 精英/Boss 配置, item 奖励池, 层间通道 | [ ] |

### 3.2 需新建的 JSON

| 文件 | 内容 | 状态 |
|------|------|------|
| `data/npc_dialogues.json` | 房东 5 组 + 猫 5 组对话, 含兑换逻辑和回调配置 | [ ] |
| `data/milestone_events.json` | 9 个里程碑事件 (hook 点触发) | [ ] |
| `data/morning_events.json` | 7 个早间事件 (Day 1-7, 含分支) | [ ] |
| `data/story_events.json` | 5 个翻牌故事事件 | [ ] |

---

## 四、新增资源属性

两个贯穿所有系统的新资源:

| 资源 | 字段名 | 初始值 | 上限 | 影响范围 |
|------|--------|--------|------|---------|
| 健康 | `health` | 5 | 10 | CardInteraction(每日步数上限), EventPool(地点效果+health), NPC 兑换(health<->san), game_config |
| 灵感 | `inspiration` | 10 | -1(无上限) | EventPool(怪物伤害公式: `san-(2+min(3,floor((ins-10)/15)))`), CardInteraction(ins<20→线索退化为 safe), DarkWorld(层级解锁: 15/25/45), 故事事件奖励 |

**涉及改动的模块**:
- `game_config.json`: initial_resources / resource_caps 新增两项
- `game_data.gd`: resources 字典新增两项
- `resource_bar_scene.gd`: 显示新资源
- `enums.gd`: ResourceType 新增 HEALTH / INSPIRATION
- `event_handler.gd`: 怪物伤害公式引用 inspiration
- `card_interaction.gd`: 步数限制引用 health
- `board.gd` / `dark_world.gd`: 层级解锁引用 inspiration

---

## 五、实施计划

### Phase 1 - 数据基础 ✅
> 更新/新建所有 JSON 数据文件, game_config 新增 health/inspiration

- [x] 更新 `data/game_config.json`
- [x] 更新 `data/story_config.json`
- [x] 新建 `data/morning_events.json`
- [x] 新建 `data/story_events.json`
- [x] 新建 `data/milestone_events.json`
- [x] 新建 `data/npc_dialogues.json`
- [x] 更新 `data/event_pool.json`
- [x] 更新 `data/locations.json`
- [x] 更新 `data/dark_world.json`
- [x] `enums.gd` 新增 ResourceType.HEALTH / INSPIRATION

### Phase 2 - 故事核心 ✅
> StoryManager 升级 + StoryConfig + EndingSystem + 条件引擎扩展

- [x] `story_manager.gd` 升级: 白夜状态, 碎片, 章节, 动态天数, 新条件类型, 效果应用
- [x] 新建 `scripts/core/ending_system.gd`
- [x] `game_data.gd` 新增 health / inspiration 资源

### Phase 3 - 事件三层架构 ✅
> StoryEventManager + MilestoneManager + 早间事件

- [x] 新建 `scripts/core/story_event_manager.gd`
- [x] 新建 `autoload/milestone_manager.gd`
- [x] 事件触发与对话系统集成

### Phase 4 - 角色系统 ✅
> 白夜伴侣 + NPC 系统升级 (房东/猫)

- [x] 新建 `scripts/visual/baiye.gd`
- [x] `npc_manager.gd` 升级: 类型注册, 多对话组, 兑换, 每日冷却
- [x] 白夜贴图资源确认

### Phase 5 - 流程集成
> GameFlow / CardInteraction / DarkWorld 升级

- [x] `game_flow.gd` 升级 ✅ P5.1
- [x] `game_over_scene.gd` 升级 ✅ P5.2
- [x] `card_interaction.gd` 升级 ✅ P5.4
- [x] `card_config.gd` 升级 (fragment_drops/elite/boss/item_reward_pool 加载) ✅ P5.5b-1
- [x] `dark_world.gd` 升级 (get_npc_at, 碎片/精英/Boss/奖池, 能量=san) ✅ P5.5b-2
- [x] `dark_world_flow.gd` 升级 (白夜跟随, 里程碑hook, 碎片/精英/Boss/奖池/L2通道集成) ✅ P5.5b-3
- [x] 相机驱灵功能 (拍照消灭幽灵) ✅ P5.5b-3

### Phase 6 - 辅助系统 ✅
> AudioManager + DebugPanel

- [x] 新建 `autoload/audio_manager.gd` ✅ P6.2
- [x] 新建 `scripts/ui/debug_panel.gd` ✅ P6.3
- [x] AudioManager autoload 注册 ✅ P6.4a
- [x] DebugPanel 集成到 main.gd ✅ P6.4b
- [x] AudioManager 调用集成到 game_flow / card_interaction / dark_world_flow ✅ P6.4c

---

## 六、文件映射速查表

| Lua 文件 (main) | Godot 对应 | 状态 |
|-----------------|-----------|------|
| `StoryManager.lua` | `autoload/story_manager.gd` | ✅ P2 |
| `StoryConfig.lua` | `data/story_config.json` | ✅ P1 |
| `EndingSystem.lua` | `core/ending_system.gd` | ✅ P2.5 |
| `MilestoneManager.lua` | `autoload/milestone_manager.gd` | ✅ P3.1 |
| `StoryEvents.lua` | `data/story_events.json` | ✅ P1 |
| `StoryEventManager.lua` | `core/story_event_manager.gd` | ✅ P3.2 |
| `data/morning_events.lua` | `data/morning_events.json` | ✅ P1 |
| `data/milestone_events.lua` | `data/milestone_events.json` | ✅ P1 |
| `data/npc_dialogues.lua` | `data/npc_dialogues.json` | ✅ P1 |
| `Baiye.lua` | `visual/baiye.gd` | ✅ P4.1 |
| `NPCManager.lua` | `core/npc_manager.gd` | ✅ P4.2 |
| `AudioManager.lua` | `autoload/audio_manager.gd` | ✅ P6 |
| `DebugPanel.lua` | `ui/debug_panel.gd` | ✅ P6 |
| `GameFlow.lua` | `controllers/game_flow.gd` | ✅ P5.1 |
| `CardInteraction.lua` | `controllers/card_interaction.gd` | ✅ P5.4 |
| `DarkWorld.lua` | `core/dark_world.gd` | ✅ P5.5b-2 |
| `DarkWorldFlow.lua` | `controllers/dark_world_flow.gd` | ✅ P5.5b-3 |
| `EventPool.lua` | `data/event_pool.json` + `autoload/event_pool.gd` | 需更新 |
| `GameOver.lua` | `visual/game_over_scene.gd` | ✅ P5.2 |

---

---

## 七、修复日志

### 2026-05-08 遗留项修复 + 综合审计

**修复内容**:

1. **LOCATION_SCARCITY 运行时错误** — `card_manager.gd` 引用 `GameData.LOCATION_SCARCITY` 但该属性不存在
   - `data/game_config.json`: 新增 `location_scarcity` 字段 (`day_1_2:3, day_3_4:2, day_5_plus:1`)
   - `game_data.gd`: 新增 `LOCATION_SCARCITY` 属性声明 + `_load_game_config()` 加载逻辑

2. **Rule 1 `:=` 违规** — `game_data.gd` 的 `_load_game_config()` 中 3 处 `:=`
   - `var file := ...` → `var file: FileAccess = ...`
   - `var json := ...` → `var json: JSON = ...`
   - `var err := ...` → `var err: Error = ...`

3. **相机驱灵标记更新** — `_handle_dark_camera()` 已在 P5.5b-3 实现，tracker 中遗漏标记
   - Section 2.3 + Phase 5 两处 `[ ]` → `[x]`

**综合 porting rules 审计** (14 条规则, 51 个 .gd 文件):
- Rule 1 `:=` → ✅ 通过 (game_data.gd 已修复)
- Rule 2 autoload 命名 → ✅ 通过
- Rule 5 Array tween → ✅ 通过
- Rule 6 方法名冲突 → ✅ 通过
- Rule 7 _draw() 随机 → ✅ 通过
- Rule 9 truthy/falsy → ✅ 通过
- Rule 10 render_priority → ✅ 通过
- Rule 11 modulate 3D → ✅ 通过
- Rule 12 draw_string 对齐 → ✅ 通过
- Rule 13/14 Billboard/Sprite3D → N/A

*最后更新: 2026-05-08 (遗留项修复 + 综合审计)*
