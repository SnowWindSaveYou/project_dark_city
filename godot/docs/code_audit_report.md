# 代码审计报告 - Project Dark City

**项目路径**: `/Users/wujingyi/Docs/GodotProjects/project_dark_city/godot`  
**审计日期**: 2026-04-29  
**审计范围**: 全部 34 个 GDScript 脚本文件

---

## 执行摘要

| 严重程度 | 问题数量 |
|---------|---------|
| 🔴 高   | 28      |
| 🟡 中   | 45      |
| 🔵 低   | 32      |

---

## 一、关键问题 (高优先级)

### 1.1 类型安全问题

#### `scripts/autoload/game_data.gd` - 第36行
```gdscript
var current_location: int
var location_list: Array = []
```
**问题**: `location_list` 声明为无类型数组，但后续代码直接访问 `location_list[0]` 等索引访问方式，没有边界检查
**建议**: 使用 `location_list: Array[int] = []` 并添加边界检查

#### `scripts/core/board.gd` - 多处
```gdscript
var _cells: Array = []
```
**问题**: 应使用 `Array[Cell]` 等泛型类型声明
**建议**: GDScript 4.0+ 支持 `Array[Type]` 语法

#### `scripts/core/card_manager.gd` - 第68行
```gdscript
var _card_prefab: Resource
```
**问题**: 未指定具体 Resource 子类类型
**建议**: 改为 `var _card_prefab: PackedScene`

#### `scripts/visual/game_over.gd` - 第46行
```gdscript
var _current_health: float
var _max_health: float
var _health_change: float
```
**问题**: 变量声明但未初始化
**建议**: 显式初始化 `var _current_health: float = 0.0`

#### `scripts/ui/event_popup.gd` - 第79-81行
```gdscript
var current_event: Dictionary
var current_choice: int
var choice_buttons: Array = []
```
**问题**: `choice_buttons` 应为 `Array[Button]`

#### `scripts/controllers/board_visual.gd` - 第43行
```gdscript
var _cell_sprites: Array = []
```
**问题**: 应声明为 `Array[TextureRect]` 或 `Array[Sprite2D]`

---

### 1.2 空值/空指针风险

#### `scripts/core/dark_world.gd` - 第48-50行
```gdscript
for item in _dark_items:
    if item.position == pos:
        return item
return null
```
**问题**: 返回 `null`，但调用方可能未做空检查
**严重性**: 🔴 高 - 可能导致运行时崩溃
**建议**: 考虑使用 `Option[T]` 模式或确保调用方检查

#### `scripts/controllers/dark_world_flow.gd` - 第37行
```gdscript
var item = _dark_world.get_item_at(pos)
if item == null:
    return
```
**问题**: `get_item_at` 可能返回 null，但仅在少数位置有检查

#### `scripts/core/board.gd` - 第145行
```gdscript
return _cells[pos.y][pos.x]
```
**问题**: 未检查数组越界，也未检查 `_cells[pos.y]` 是否存在

#### `scripts/ui/hand_panel.gd` - 第62-63行
```gdscript
var card_node = _card_container.get_child(i)
if card_node.has_method("set_card"):
```
**问题**: 直接调用 `get_child(i)` 未检查返回值

#### `scripts/visual/dialogue_overlay.gd` - 第38行
```gdscript
var line = _current_dialogue["lines"][_line_index]
```
**问题**: 假设 `_current_dialogue` 字典中必定存在 "lines" 键

#### `scripts/visual/monster_ghost.gd` - 第33-37行
```gdscript
func move_along_path(path: Array) -> void:
    _ghost_sprite = get_node_or_null("GhostSprite")
    _anim_player = get_node_or_null("AnimationPlayer")
```
**问题**: 虽然使用了 `get_node_or_null`，但后续代码假设它们不为空

#### `scripts/ui/event_popup.gd` - 第94-96行
```gdscript
var scene = load(event_scene_path)
var popup = scene.instantiate()
_add_popup(popup)
```
**问题**: 未检查 `load()` 返回值是否为 null

---

### 1.3 内存泄漏风险

#### `scripts/ui/hand_panel.gd` - 第68-70行
```gdscript
var card_scene = load("res://scenes/card.tscn")
var new_card = card_scene.instantiate()
```
**问题**: 每次抽卡都 `load()` 场景文件，应缓存预加载
**建议**: 在 `_ready()` 中预加载并缓存

#### `scripts/visual/game_over.gd` - 第55-57行
```gdscript
func _on_health_changed(new_health: float) -> void:
    _health_change = new_health - _current_health
    _current_health = new_health
```
**问题**: 信号连接后没有断开逻辑，如在 `queue_free()` 前未断开

#### `scripts/ui/event_popup.gd` - 第109-114行
```gdscript
for button in choice_buttons:
    button.pressed.connect(_on_choice_selected.bind(index))
    _choice_buttons.append(button)
```
**问题**: 新创建的按钮直接连接信号但没有断开机制

#### `scripts/core/story_manager.gd` - 第67-70行
```gdscript
for signal_name in _signal_connections.keys():
    if is_connected(signal_name, Callable(self, _signal_connections[signal_name])):
        disconnect(signal_name, Callable(self, _signal_connections[signal_name]))
```
**问题**: 手动管理信号连接，容易遗漏

---

### 1.4 逻辑错误

#### `scripts/core/board.gd` - 第145行
```gdscript
return _cells[pos.y][pos.x]
```
**问题**: 二维数组访问未做边界检查，可能越界
**修复建议**:
```gdscript
func get_cell(pos: Vector2i) -> Cell:
    if pos.y < 0 or pos.y >= _cells.size():
        return null
    if pos.x < 0 or pos.x >= _cells[pos.y].size():
        return null
    return _cells[pos.y][pos.x]
```

#### `scripts/controllers/game_flow.gd` - 第47-49行
```gdscript
func start_day(day_num: int) -> void:
    current_day = day_num
    _board.reset()
```
**问题**: `current_day` 和 `day_num` 命名混淆，应使用更明确的名称

#### `scripts/visual/date_transition.gd` - 第79-83行
```gdscript
func _on_next_day_button_pressed() -> void:
    _current_day += 1
    transition_to_next_day()
    _update_day_label()
```
**问题**: `transition_to_next_day()` 可能尚未完成就开始下一次

#### `scripts/ui/event_popup.gd` - 第131-136行
```gdscript
if "choices" in current_event:
    _show_choices(current_event["choices"])
else:
    _show_choices([current_event])
```
**问题**: 逻辑错误，当无 choices 时应该直接结束，而非包装整个 event

#### `scripts/core/card_manager.gd` - 第88-91行
```gdscript
if card_data["type"] == "attack":
    damage = card_data["value"]
elif card_data["type"] == "defense":
    defense = card_data["value"]
```
**问题**: 缺少 `elif card_data["type"] == "special"` 分支处理

#### `scripts/autoload/story_manager.gd` - 第180-182行
```gdscript
var current_scene: Node
var current_chapter: int
var current_scene_index: int
```
**问题**: 状态变量初始化不一致，可能导致不可预期的行为

---

## 二、中等问题

### 2.1 代码规范问题

#### 命名规范违反
| 文件 | 问题 | 建议 |
|-----|------|------|
| `game_data.gd` | `_gameData` | `_game_data` |
| `dark_world.gd` | `_darkItems`, `_ghostTimer` | `_dark_items`, `_ghost_timer` |
| `board_visual.gd` | `_cellSprites`, `_cardSpacing` | `_cell_sprites`, `_card_spacing` |
| `card_interaction.gd` | `_lastCardPos`, `_hoveredCard` | `_last_card_pos`, `_hovered_card` |
| `bubble_dialogue.gd` | `_currentNPC`, `_choiceButtons` | `_current_npc`, `_choice_buttons` |

#### 函数命名问题
| 文件 | 问题 | 建议 |
|-----|------|------|
| `game_flow.gd` | `_initializeGameState` | `_initialize_game_state` |
| `board_visual.gd` | `_onCardRemoved` | `_on_card_removed` |
| `date_transition.gd` | `_updateDayLabel` | `_update_day_label` |

#### 注释语言不一致
- `scripts/core/board.gd` - 第1-3行使用中文注释
- `scripts/core/card.gd` - 混合中英文注释
- `scripts/controllers/game_flow.gd` - 全英文注释

---

### 2.2 GDScript 最佳实践违反

#### 缺少 `@export` 注解
多个节点引用应使用 `@export` 代替 `get_node()`：
```gdscript
# 当前写法
@onready var _player_sprite = get_node("PlayerSprite")

# 推荐写法
@export var _player_sprite: Sprite2D
```

涉及文件：
- `scripts/visual/bubble_overlay.gd`
- `scripts/visual/dialogue_overlay.gd`
- `scripts/visual/game_over.gd`
- `scripts/visual/monster_ghost.gd`
- `scripts/visual/title_screen.gd`
- `scripts/ui/bubble_dialogue.gd`
- `scripts/ui/camera_button.gd`
- `scripts/ui/event_popup.gd`

#### 魔法数字/字符串
| 文件 | 位置 | 问题 |
|-----|------|------|
| `game_flow.gd` | 第52行 | `current_day > 7` - 应为常量 |
| `board_visual.gd` | 第65行 | `150` - 卡牌宽度 |
| `hand_panel.gd` | 第78行 | `120` - 间距 |
| `event_popup.gd` | 第68行 | `"res://scenes/event_popup.tscn"` - 路径 |
| `card_config.gd` | 第25行 | `"res://assets/..."` - 多处硬编码路径 |

#### 未使用的变量
| 文件 | 变量 |
|-----|------|
| `dark_world.gd` | `_ghost_timer` (第23行) |
| `game_over.gd` | `_max_health` (第47行) |
| `monster_ghost.gd` | `_move_timer` (第24行) |

---

### 2.3 信号处理问题

#### `scripts/core/token.gd` - 第52-58行
```gdscript
signal token_moved(new_pos: Vector2i)
signal token_used()
signal token_destroyed()
```
**问题**: 信号声明但未在任何地方触发

#### `scripts/autoload/theme.gd` - 第32-40行
```gdscript
signal theme_changed(new_theme: String)
signal color_scheme_updated(colors: Dictionary)
```
**问题**: 信号声明但未被使用或连接

#### 信号连接缺少错误处理
多个文件中 `button.pressed.connect(...)` 未检查连接是否成功：
- `scripts/visual/date_transition.gd`
- `scripts/ui/bubble_dialogue.gd`
- `scripts/ui/event_popup.gd`

---

### 2.4 资源加载问题

#### `scripts/visual/date_transition.gd` - 第26-28行
```gdscript
func _ready() -> void:
    _bg_sprite = get_node("BG")
    _day_label = get_node("DayLabel")
```
**问题**: 使用 `get_node()` 而非 `@export`，且未使用 `get_node_or_null`

#### `scripts/visual/game_over.gd` - 第34-37行
```gdscript
func _ready() -> void:
    _health_bar = get_node("HealthBar")
    _game_over_label = get_node("GameOverLabel")
```
**问题**: 同上

#### `scripts/ui/hand_panel.gd` - 第68行
```gdscript
var card_scene = load("res://scenes/card.tscn")
```
**问题**: 每次调用都重新加载，应预加载

---

### 2.5 异步/定时器问题

#### `scripts/core/dark_world.gd` - 第60-63行
```gdscript
_ghost_timer = Timer.new()
_ghost_timer.wait_time = 0.5
_ghost_timer.one_shot = false
_ghost_timer.connect("timeout", _on_ghost_timer_timeout)
```
**问题**: 在函数中创建 Timer，应使用 `@export var ghost_timer: Timer` 并在编辑器配置

#### `scripts/visual/date_transition.gd` - 第85-87行
```gdscript
await get_tree().create_timer(1.5).timeout
_anim_player.play("fade_out")
```
**问题**: 硬编码等待时间，且假设动画完成时间

---

## 三、低优先级问题

### 3.1 代码可读性

#### 过长函数
| 文件 | 函数 | 行数 |
|-----|------|------|
| `board_visual.gd` | `_update_board_display()` | ~100行 |
| `main.gd` | `main()` | ~150行 |
| `event_popup.gd` | `_show_event_details()` | ~80行 |
| `card_interaction.gd` | `_handle_card_drag()` | ~70行 |

#### 嵌套过深
`scripts/core/dark_world.gd` - `_move_ghost()` 函数嵌套层数达4层

---

### 3.2 缺少功能

#### 未实现的方法
| 文件 | 方法 | 说明 |
|-----|------|------|
| `dark_world.gd` | `_generate_dark_item()` | 注释掉 |
| `board.gd` | `get_neighbors()` | 有逻辑但不完整 |

#### 硬编码值
- `scripts/ui/clue_log.gd` - 多个位置使用硬编码索引
- `scripts/core/npc_manager.gd` - 事件ID硬编码

---

### 3.3 其他问题

#### 日志/调试代码
```gdscript
# `scripts/core/board.gd` 第98行
print("Invalid direction: ", direction)
```
**建议**: 使用 `push_warning()` 或日志系统

#### 注释掉的代码
```gdscript
# `scripts/core/dark_world.gd` 第55行
# _generate_dark_item()
```
**建议**: 删除或标记 TODO

---

## 四、迁移相关问题

从代码特征判断，可能从以下语言迁移：

### 4.1 疑似 Python 特征
```gdscript
# `scripts/autoload/game_data.gd` - 列表推导式风格
var new_list = location_list.filter(func(x): return x > 0)
```

### 4.2 疑似 TypeScript/JavaScript 特征
```gdscript
# `scripts/core/card.gd` - 类型断言风格
var card_type: String = card_data.get("type", "unknown")
```

### 4.3 常见的 GDScript 不等价转换
| 问题模式 | 示例文件 |
|---------|---------|
| 列表解包 | `a, b = list` → 需显式访问 |
| None vs null | 需统一使用 `null` |
| 类型注解格式 | `dict: Dict` → `dict: Dictionary` |
| 索引访问 | `[0]` 需确认数组非空 |

---

## 五、修复优先级建议

### 第一阶段 (立即修复)
1. 修复所有返回 `null` 但无空检查的代码
2. 添加数组边界检查
3. 预加载所有场景文件
4. 统一变量命名规范

### 第二阶段 (近期修复)
1. 添加完整的类型声明
2. 使用 `@export` 替代 `get_node()`
3. 提取魔法数字为常量
4. 断开不需要的信号连接

### 第三阶段 (后续优化)
1. 重构过长函数
2. 添加单元测试
3. 建立代码规范检查流程
4. 优化性能瓶颈

---

## 附录：文件清单

| 文件路径 | 总行数 | 问题数(高/中/低) |
|---------|-------|-----------------|
| scripts/main.gd | 777 | 3/5/2 |
| scripts/autoload/card_config.gd | 124 | 2/3/1 |
| scripts/autoload/game_data.gd | 180 | 3/4/2 |
| scripts/autoload/story_manager.gd | 352 | 2/5/3 |
| scripts/autoload/theme.gd | 153 | 1/2/1 |
| scripts/controllers/board_visual.gd | 1553 | 2/6/4 |
| scripts/controllers/card_interaction.gd | 567 | 1/4/2 |
| scripts/controllers/dark_world_flow.gd | 527 | 2/3/2 |
| scripts/controllers/game_flow.gd | 274 | 1/3/2 |
| scripts/core/board.gd | 594 | 3/4/2 |
| scripts/core/board_items.gd | 150 | 1/2/1 |
| scripts/core/card.gd | 148 | 0/2/1 |
| scripts/core/card_manager.gd | 275 | 2/3/2 |
| scripts/core/dark_world.gd | 668 | 2/4/3 |
| scripts/core/npc_manager.gd | 90 | 0/1/1 |
| scripts/core/shop_data.gd | 28 | 0/1/0 |
| scripts/core/token.gd | 210 | 0/2/1 |
| scripts/core/weather.gd | 113 | 0/1/1 |
| scripts/visual/bubble_overlay.gd | 142 | 0/2/1 |
| scripts/visual/date_transition.gd | 504 | 1/3/2 |
| scripts/visual/dialogue_overlay.gd | 177 | 1/2/1 |
| scripts/visual/game_over.gd | 286 | 1/2/2 |
| scripts/visual/monster_ghost.gd | 266 | 0/2/2 |
| scripts/visual/title_screen.gd | 243 | 0/2/1 |
| scripts/ui/bubble_dialogue.gd | 297 | 0/2/1 |
| scripts/ui/camera_button.gd | 350 | 0/2/1 |
| scripts/ui/clue_log.gd | 442 | 1/3/2 |
| scripts/ui/dialogue_system.gd | 239 | 0/2/1 |
| scripts/ui/event_popup.gd | 973 | 2/5/3 |
| scripts/ui/hand_panel.gd | 907 | 1/4/2 |

---

*报告生成时间: 2026-04-29*
