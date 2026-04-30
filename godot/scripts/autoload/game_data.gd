## GameData - 全局游戏数据 (Autoload)
## 管理资源、游戏阶段、统计等全局状态
extends Node

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal resource_changed(key: String, old_value: int, new_value: int)
signal game_phase_changed(old_phase: String, new_phase: String)
signal demo_state_changed(old_state: String, new_state: String)

# ---------------------------------------------------------------------------
# 数据表从 game_config.json 读取
# ---------------------------------------------------------------------------
var MAX_DAYS: int = 3
var INITIAL_RESOURCES: Dictionary = {}
var RESOURCE_MAX: Dictionary = {}
var RESOURCE_ICONS: Dictionary = {}

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var resources: Dictionary = {}  # { "san": 10, "order": 10, "money": 50, "film": 3 }

## 两级状态机
var game_phase: String = "title"  # "title" | "playing" | "gameover"
var demo_state: String = "idle"  # "idle"|"dealing"|"ready"|"flipping"|"popup"|"moving"|"photographing"|"exorcising"|"dialogue"|"rift_confirm"|"dark_world"

## 天数
var current_day: int = 0

## 统计
var cards_revealed: int = 0
var day_start_revealed: int = 0
var monsters_slain: int = 0
var photos_used: int = 0

## 道具栏 { "coffee": 2, "shield": 1, ... }
var inventory: Dictionary = {}

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	_load_game_config()
	reset()

func _load_game_config() -> void:
	var file := FileAccess.open("res://data/game_config.json", FileAccess.READ)
	if file == null:
		push_warning("[GameData] game_config.json not found, using defaults")
		INITIAL_RESOURCES = { "san": 10, "order": 10, "money": 50, "film": 3 }
		RESOURCE_MAX = { "san": 10, "order": 10, "money": -1, "film": -1 }
		RESOURCE_ICONS = { "san": "🧠", "order": "⚖️", "money": "💰", "film": "📷" }
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_warning("[GameData] Failed to parse game_config.json: %s" % json.get_error_message())
		return
	var data: Dictionary = json.data
	MAX_DAYS = int(data.get("max_days", 3))
	# int conversion for resource dicts
	var raw_init: Dictionary = data.get("initial_resources", {})
	for k in raw_init:
		INITIAL_RESOURCES[k] = int(raw_init[k])
	var raw_max: Dictionary = data.get("resource_max", {})
	for k in raw_max:
		RESOURCE_MAX[k] = int(raw_max[k])
	RESOURCE_ICONS = data.get("resource_icons", {})
	print("[GameData] Loaded game_config.json: max_days=%d, resources=%s" % [MAX_DAYS, str(INITIAL_RESOURCES)])

func reset() -> void:
	resources = INITIAL_RESOURCES.duplicate()
	game_phase = "title"
	demo_state = "idle"
	current_day = 0
	cards_revealed = 0
	day_start_revealed = 0
	monsters_slain = 0
	photos_used = 0
	inventory = {}
	# 重置剧情状态
	if StoryManager:
		StoryManager.reset()

# ---------------------------------------------------------------------------
# 资源操作
# ---------------------------------------------------------------------------

## 获取资源值
func get_resource(key: String) -> int:
	return resources.get(key, 0)

## 修改资源 (delta 可正可负)
func modify_resource(key: String, delta: int) -> void:
	var old_val: int = resources.get(key, 0)
	var new_val: int = old_val + delta
	var max_val: int = RESOURCE_MAX.get(key, -1)
	if max_val > 0:
		new_val = mini(new_val, max_val)
	new_val = maxi(new_val, 0)
	resources[key] = new_val
	resource_changed.emit(key, old_val, new_val)

## 设置资源绝对值
func set_resource(key: String, value: int) -> void:
	var old_val: int = resources.get(key, 0)
	var max_val: int = RESOURCE_MAX.get(key, -1)
	if max_val > 0:
		value = mini(value, max_val)
	value = maxi(value, 0)
	resources[key] = value
	resource_changed.emit(key, old_val, value)

## 应用效果字典 { "san": -2, "order": -1, ... }
func apply_effects(effects: Dictionary) -> void:
	for key in effects:
		modify_resource(key, effects[key])

# ---------------------------------------------------------------------------
# 状态机
# ---------------------------------------------------------------------------

func set_game_phase(new_phase: String) -> void:
	var old: String = game_phase
	game_phase = new_phase
	game_phase_changed.emit(old, new_phase)

func set_demo_state(new_state: String) -> void:
	var old: String = demo_state
	demo_state = new_state
	demo_state_changed.emit(old, new_state)

# ---------------------------------------------------------------------------
# 胜负判定
# ---------------------------------------------------------------------------

## 检查是否失败 (san 或 order <= 0)
func check_defeat() -> bool:
	return resources.get("san", 0) <= 0 or resources.get("order", 0) <= 0

## 检查是否胜利 (存活天数达到 MAX_DAYS)
func check_victory() -> bool:
	return current_day > MAX_DAYS

# ---------------------------------------------------------------------------
# 道具栏
# ---------------------------------------------------------------------------

func add_item(item_key: String, count: int = 1) -> void:
	inventory[item_key] = inventory.get(item_key, 0) + count

func remove_item(item_key: String, count: int = 1) -> bool:
	var current: int = inventory.get(item_key, 0)
	if current < count:
		return false
	inventory[item_key] = current - count
	if inventory[item_key] <= 0:
		inventory.erase(item_key)
	return true

func get_item_count(item_key: String) -> int:
	return inventory.get(item_key, 0)

func has_item(item_key: String) -> bool:
	return get_item_count(item_key) > 0

# ---------------------------------------------------------------------------
# 统计
# ---------------------------------------------------------------------------

func get_stats() -> Dictionary:
	return {
		"days_survived": current_day,
		"cards_revealed": cards_revealed,
		"monsters_slain": monsters_slain,
		"photos_used": photos_used,
	}
