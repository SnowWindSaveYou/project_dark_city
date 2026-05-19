# 暗面都市 — 设计变更日志

---

## v1.3 实施记录 (2026-05-18)

### 陷阱卡决策系统 + 事件弹窗修复

#### 背景

陷阱卡原本只有"立即扣除资源 → 显示结果"这一条路径，无法承载带选项的事件（例如"冒险拆解/放弃离开"类陷阱）。本次为陷阱卡接入与普通事件相同的决策弹窗，并同步修复了弹窗的两个关键 UI bug。

#### 变更详情

| 改动文件 | 变更内容 |
|---------|---------|
| `godot/scripts/controllers/card_interaction.gd` | `_handle_trap()` 重构：新增 `has_choices` 判断，有决策路径时效果延迟结算，通过 `_pending_trap_effects` 暂存；传送陷阱保持立即结算；新增成员变量 `_pending_trap_effects: Dictionary` |
| `godot/scripts/controllers/card_interaction.gd` | `_apply_choice_effects()` 的 `charge` 分支改为从 `_pending_trap_effects` 取值，应用后清空，防止重复结算 |
| `godot/scripts/controllers/dark_world_flow.gd` | 移除两处残留的 `EventHandler.EventType.CLUE` 引用（v1.2 已删除该枚举成员，这里漏改）；两处 `match` 分支改为仅保留 `DARK_CLUE` |
| `godot/scripts/ui/event_popup_scene.gd` | **修复**：选项点击回调不再调用 `dismiss()`/`_clear_choices_row()`，改由 `on_choice` 链式触发 `transition_to_result`，弹窗统一由结果视图的"知道了"按钮关闭 |
| `godot/scripts/ui/event_popup_scene.gd` | **修复**：`_populate_choices_row` 将选项行挂载到 `_right_vbox`（右栏）而非 `OuterVBox`（全宽），防止选项按钮覆盖左侧偏光图；新增 `SIZE_SHRINK_END` 垂直标志使选项行贴底对齐 |
| `godot/scripts/ui/event_popup_scene.gd` | 选项按钮布局微调：按钮高度 64→56，圆角 14→12，内边距收紧；标签字号 36→30；费用字号 26→22；始终使用 VBox 包裹主标签与费用标签 |

#### 数据文件说明

`godot/data/events.json` 的 `locations.*.clue[]` 数组为 v1.2 清理遗漏的死数据（明面 clue 类型已移除，无任何代码调用路径），不影响运行，可在后续数据整理时清除。

#### 明面陷阱卡处理流程（变更后）

```
翻开陷阱卡
  ↓
读取 event_id → 过滤有效 choices
  ├─ 无 choices（普通陷阱）
  │    ├─ 护身符 → 抵消 → 弹窗 → 关闭
  │    └─ 无护身符 → 立即扣资源 → 弹窗 → 关闭
  ├─ 有 choices（决策陷阱）
  │    └─ 暂存 _pending_trap_effects → 弹窗显示选项
  │         └─ 玩家选择 → _apply_choice_effects
  │              ├─ charge → 取 _pending_trap_effects 扣资源
  │              └─ 其他分支 → 各自处理
  └─ trap_subtype == "teleport"（传送陷阱）
       └─ 立即扣资源 → 弹窗 → 随机传送
```

---

## v1.2 实施记录 (2026-05-17)

### 明面卡牌系统重构：移除 clue 类型，plot 重定义为叙事推进格

#### 背景

原设计中明面存在 6 种卡牌类型（safe / monster / trap / reward / plot / clue）。clue（线索格）在明面可被直接触发，导致前世记忆碎片的获取过于容易，削弱了玩家探索暗面世界的动机。本次将明面 clue 类型完全移除，暗面专属 clue 保留不变，并将 plot 重定位为叙事推进格以填补空缺。

#### 变更详情

| 改动文件 | 变更内容 |
|---------|---------|
| `godot/data/card_config.json` | 移除 `event_weights.clue`，`plot` 权重 10→20；删除所有地点 `darkside_info.clue` 条目（10 个地点）；删除 `card_effects.clue`；删除 `event_texts.clue`，更新 `plot` 文本为叙事风格 3 条；`card_types` 删除 `"clue"` 条目，`plot` 标签改为"叙事" |
| `godot/scripts/controllers/card_interaction.gd` | 删除 clue 灵感阈值降级逻辑；表情映射 `"clue": "surprised"` → `"plot": "surprised"`；删除 clue 事件处理分支，叙事推进格统一走 plot 路径；positive 数组 `"clue"` → `"plot"` |
| `godot/scripts/lib/event_handler.gd` | 删除 `EventType.CLUE = 5`（`DARK_CLUE = 14` 保留）；删除 `parse_real_world_card` 的 clue 分支；删除类型映射函数中的 clue 条目；`get_event_type_name` 中 "剧情" → "叙事" |
| `godot/scripts/core/card_manager.gd` | 两处安全类型判断移除 `"clue"`（lines 181、218） |
| `godot/scripts/ui/bubble_dialogue.gd` | 删除 `"clue"` 对话数组（6 条），叙事推进格复用 `"plot"` 对话 |
| `godot/scripts/ui/event_popup_scene.gd` | 删除音效映射 `"clue": "evt_clue"` |
| `godot/scripts/autoload/card_image_map.gd` | `GENERIC` 图池：删除 `"clue"` 数组，5 张图片合并进 `"plot"`（共 10 张）；`LOCATION_EVENT_IMAGES` 各地点 `"clue"` 条目改为 `"plot"`（school 合并为数组）；`DARK_EVENT_ICONS["clue"]` 保留 |
| `godot/scripts/core/story_event_manager.gd` | 注释 `card_type: "plot" \| "clue"` → `card_type: "plot"` |
| `godot/scripts/autoload/story_manager.gd` | `pick_clue_event()` 注释更新，标明当前无调用方，预留为事件内决策系统接入点 |

#### 保留不变（暗面专属）

- `board.gd`：暗面地图生成中 `dark_type = "clue"` 格子分配逻辑
- `event_handler.gd`：`parse_dark_world_card` 中 `dark_type == "clue"` 处理分支
- `card_image_map.gd`：`DARK_EVENT_ICONS["clue"]` 暗面卡图标
- `story_manager.gd`：`_clue_events` 数据池、`pick_clue_event()` 函数（预留接口）
- `story_config.json`：`clue_events` 事件池（5 条明面线索事件，待事件内决策系统设计后接入）
- `audio_manager.gd`：`evt_clue` 音效资源（可供暗面线索翻开复用）

#### 明面卡牌类型（变更后）

| 类型 | 权重 | 说明 |
|------|------|------|
| safe | 30 | 安全格 |
| monster | 20 | 怪物格 |
| trap | 15 | 陷阱格 |
| reward | 15 | 奖励格 |
| plot | 20 | 叙事推进格（原 10，吸收原 clue 份额） |

---

## v1.1 实施记录 (2026-05-03)

> 以下记录 v1.1 changelog 各条目的代码落地状态。

### ✅ 已完成

#### 一、属性系统重构

| 条目 | 状态 | 改动文件 | 说明 |
|------|------|---------|------|
| 1.1 移除秩序值 | ✅ | ResourceBar / GameFlow / EventPopup / CardManager | `order` 属性从 `resources` 表、事件效果、日程奖励、失败条件中全部移除 |
| 1.2 新增健康 | ✅ | ResourceBar | `health` 属性 init=10, max=10, colorKey="safe"；失败条件 health≤0 已加入 GameFlow |
| 1.3 新增灵感 | ✅ | ResourceBar | `inspiration` 属性 init=10, max=999, colorKey="highlight" |
| 1.3 暗面灵感解锁 | ✅ | DarkWorld / DarkWorldFlow / GameFlow | 三层阈值 15/25/45；`canEnter()` / `isLayerUnlocked()` 改为灵感判断 |
| 1.4 暗面步数=理智值 | ✅ | DarkWorld / DarkWorldFlow | `layer.energy = ResourceBar.get("san")`，`maxEnergy` 同步传给 HUD |
| 1.5 胶卷拆分 | ✅ | ResourceBar | `dailyFilmData` (每日重置为3) + `permFilmData` (跨天)；`M.change("film",...)` 路由逻辑；`M.get("film")` 返回合计 |
| 1.5 每日胶卷重置 | ✅ | GameFlow `advanceDay()` | 每天补足 dailyFilm 到 3 |

#### 二、剧情时间线

| 条目 | 状态 | 改动文件 | 说明 |
|------|------|---------|------|
| 2.1 基础 7 天 | ✅ | GameFlow | `MAX_DAYS = 7` |

#### 三、角色成长系统

| 条目 | 状态 | 改动文件 | 说明 |
|------|------|---------|------|
| 上限提升 API | ✅ | ResourceBar | `M.setMax(key, newMax)` / `M.getMax(key)` 已就绪 |

#### 四、地点变更

| 条目 | 状态 | 改动文件 | 说明 |
|------|------|---------|------|
| 4.1 移除神社 | ✅ | Card / CardManager | `shrine` 从 LOCATION_INFO、LANDMARK_LOCATIONS、SCHEDULE_TEMPLATES 中移除 |
| 4.2 新增墓地 | ✅ | Card / CardManager | `cemetery` 加入 LOCATION_INFO、REGULAR_LOCATIONS、DARKSIDE_INFO、SCHEDULE_TEMPLATES |
| 4.3 新增健身房 | ✅ | Card / CardManager | `gym` 同上 |

#### 五、失败条件

| 条目 | 状态 | 改动文件 | 说明 |
|------|------|---------|------|
| 健康归零→失败 | ✅ | GameFlow `checkDefeat()` | `health ≤ 0` 判定已加入 |
| 秩序归零→移除 | ✅ | GameFlow | 不再检查 order |

#### 六、事件/惩罚调整

| 条目 | 状态 | 改动文件 | 说明 |
|------|------|---------|------|
| monster 移除 order 扣减 | ✅ | EventPopup | 仅保留 `san -2` |
| plot 奖励 order→inspiration | ✅ | EventPopup | `{ "inspiration", 1 }` |
| 未完成日程惩罚 | ✅ | CardManager `settleDay()` | `san/health/inspiration` 各 -1 |
| 日程奖励调整 | ✅ | CardManager | library→inspiration, police→san |

---

#### 七、步数/事件/怪物机制

| 条目 | 状态 | 改动文件 | 说明 |
|------|------|---------|------|
| #1 步数绑定 | ✅ | CardInteraction / GameFlow / main | 每日步数 = 当日开始时 health 值；`G.stepsUsed` 跟踪；`hasStepsRemaining()` 检查 |
| #2 健康/理智转换事件 | ✅ | CardInteraction | 医院(health→san) / 公园(san→health) / 健身房(san→health) 各 2:2 转换; 通用确认弹窗 |
| #3 灵感阈值线索 | ✅ | EventPopup | `hasClueToday` 标记 + 灵感≥阈值时 clue 降级为 safe |
| #4 怪物伤害缩放 | ✅ | EventPopup | `getMonsterEffects()` 基础 san-2; extra = min(3, floor((insp-10)/15)); health 0/-1/-2/-3 |
| #8 日程必选地点稀缺性 | ✅ | CardManager | `preSelectLocations()` 按天数递减每地点最大出现次数 (D1-2:3, D3-4:2, D5+:1) |
| #9 地点专属事件权重偏移 | ✅ | EventPopup | `LOCATION_WEIGHT_OFFSETS` 表; `pickWeightedEvent()` 加入地点修正 |

#### 八、角色成长 — 暗面专属道具 & 灵感道具

| 条目 | 状态 | 改动文件 | 说明 |
|------|------|---------|------|
| #6 暗面专属道具 | ✅ | ShopPopup / DarkWorld | `DARK_GOODS` 商品池: 暗影精华(san上限+2,¥25)、铁骨丹(health上限+2,¥25) + 暗面补给; `show(cx,cy,fn,{dark=true})` 启用暗面池; `DARK_SHOP_VARIANTS` 暗面商店名; `doPurchase` 支持 `sanMax`/`healthMax` 效果 |
| #7 灵感提升道具 | ✅ | ShopPopup / DarkWorld | 回响水晶(inspiration+5,¥20) 仅暗面商店; 暗面 item 奖励池加入 inspiration+3 (2/10 概率) |
| 暗面 item 奖励扩展 | ✅ | DarkWorld | 加权奖励池 10 项: 常规资源×2 + 灵感×2 + 上限提升×1(稀有) |
| orderManual 清理 | ✅ | ShopPopup | 移除已废弃的秩序手册道具、inventory key、CONSUMABLE_ITEMS 条目 |

### ❌ 未实现（需后续迭代）

| changelog 条目 | 原因 |
|---------------|------|
| **2.1 第二档 14 天**: 拼合真相碎片后延长 | `MAX_DAYS` 目前固定 7，需加碎片拼合→延长逻辑 |

---

## v1.1 (2026-05-03) — 属性重构 + 角色成长 + 地点调整

> 来源：项目会议记录

### 一、属性系统重构

#### 1.1 移除：秩序值 (Order)
- 从核心数值中移除秩序属性
- 移除"秩序归零 → 游戏失败"条件
- 原秩序相关的日程奖励改为对应地点的三维值（理智/健康/灵感）上限提升或即时恢复
- 未完成日程的惩罚从"扣秩序值"改为"扣除三维值（理智/健康/灵感各 -1）"

#### 1.2 新增：健康 (Health)
- **初始值**: 10，**上限**: 10（可通过道具/事件提升上限）
- **核心机制**: 健康归零 → 游戏失败（角色死亡）
- **步数绑定**: 当前健康值 = 明面世界每日可用步数上限（每天开始时按当日健康值决定）
- **转换机制**: 部分事件允许玩家选择在健康和理智之间转换（如"消耗 2 健康恢复 1 理智"）
- 需在对应地点的事件池中设计健康/理智转换事件

#### 1.3 新增：灵感 (Inspiration)
- **初始值**: 10，**上限**: 无上限（持续成长）
- **核心机制**:
  - 决定事件触发后能拿到什么级别的线索（事件有灵感阈值条件，未达到则无法触发）
  - 灵感越高，遇到的怪物伤害值越高（数值膨胀）
  - 暗面世界层级改为灵感值解锁（取代原天数解锁）
- **暗面解锁阈值**:
  - 第 1 层（表层·暗巷）: 灵感 ≥ 15
  - 第 2 层（中层·暗市）: 灵感 ≥ 25
  - 第 3 层（深层·暗渊）: 灵感 ≥ 45
- **获取方式**: 主要靠触发事件和道具提升，需设计灵感提升道具

#### 1.4 步数系统变更
- **明面世界**: 原设计步数不限 → 改为每日步数上限 = 当日开始时的健康值
- **暗面世界**: 原固定 10 步/层 → 改为当前理智值 = 暗面可用步数

#### 1.5 胶卷拆分
- 原"胶卷"拆分为两种:
  - **每日胶卷**: 每日重置为 3，不累积到第二天
  - **长期胶卷**: 可跨天留存，通过事件奖励和商店获取

### 二、剧情时间线调整

#### 2.1 两档制
- **第一档**: 7 天（基础游戏时长）
- **第二档**: 拼合第一块真相碎片后，延长至 14 天
- 统一 `game_design.md` 中的 MAX_DAYS（原为 3 天）与 `proj_design.md`（原为 7 天）的不一致

### 三、角色成长系统（新增）

- 通过事件成长，无经验值系统
- 可成长维度:
  - 理智/健康/灵感的上限提升
  - 灵感数值持续上升（解锁更深层事件/线索）
  - 长期胶卷积累
- **暗面专属道具**: 可增加理智/灵感/健康上限的道具（仅暗面商店售卖）
- **怪物数值膨胀**: 怪物伤害随玩家灵感值增长（高灵感 = 高风险高回报）
- **地点稀缺性**: 随天数增加，同一地点在棋盘上重复出现的次数减少（后期每地点最多出现 1 次，但日程对应地点保证出现）

### 四、地点变更

#### 4.1 移除：神社 (shrine)
- 从地标列表中移除，不做替换
- 地标从 3 个减少为 2 个（教堂、警察局）

#### 4.2 新增：墓地 (cemetery) — 普通地点
- 高危地点，怪物事件权重偏移较高
- 辅助玩家决策（明面世界中明显危险的节点）

#### 4.3 新增：健身房 (gym) — 普通地点
- 正面期望地点，有专属事件可触发健康属性升级
- 健康升级事件作为地点事件池的一部分（非必触发）

#### 4.4 地点专属事件池
- 在统一事件权重基础上，为每个地点加入偏移修正
- 例: 墓地 monster 权重上调；健身房有概率触发健康升级专属事件
- 辅助玩家通过地点类型判断风险/收益

### 五、失败条件更新

| 条件 | 结果 | 变更 |
|------|------|------|
| 理智归零 | 游戏失败 | 不变 |
| 健康归零 | 游戏失败 | **新增** |
| ~~秩序归零~~ | ~~游戏失败~~ | **移除** |
| 时间耗尽（7/14 天） | 游戏失败 | 天数调整 |

### 六、待定事项

- [ ] 灵感提升道具的具体设计（名称、价格、效果）
- [ ] 暗面专属道具列表（增加上限的道具类别）
- [ ] 健康/理智转换事件的具体设计和地点分配
- [ ] 14 天延长后的剧情节奏细化（第 8~14 天的事件安排）
- [ ] 怪物伤害随灵感增长的具体公式
- [ ] 地点专属事件权重偏移的具体数值
- [ ] 地点出现次数递减的具体规则（每几天递减一次，最低几次）
- [ ] 美术风格参考文档和草图整理

---

*文档维护说明: 每次设计变更请在此文件顶部追加新版本记录*
