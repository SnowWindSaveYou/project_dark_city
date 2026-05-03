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
var MAX_DAYS: int = 7
var INITIAL_RESOURCES: Dictionary = {}
var RESOURCE_MAX: Dictionary = {}
var RESOURCE_ICONS: Dictionary = {}
var DAILY_FILM: int = 3
var DEFEAT_CONDITIONS: Array = ["san", "health"]
var STEPS_FROM_HEALTH: bool = true
var CONVERSION_EVENTS: Dictionary = {}
var MONSTER_SCALING: Dictionary = {}
var LOCATION_SCARCITY: Dictionary = {}

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var resources: Dictionary = {}  # { "san": 10, "health": 10, "inspiration": 10, "money": 50, "film": 3 }

## 两级状态机
var game_phase: String = "title"  # "title" | "playing" | "gameover"
var demo_state: String = "idle"  # "idle"|"dealing"|"ready"|"flipping"|"popup"|"moving"|"photographing"|"exorcising"|"dialogue"|"rift_confirm"|"dark_world"

## 天数
var current_day: int = 0

## 步数系统 (每日步数 = 当日开始时的健康值)
var steps_remaining: int = 0
var steps_total: int = 0

## 胶卷拆分: dailyFilm (每日重置) + permFilm (永久累积)
var daily_film: int = 3
var perm_film: int = 0

## 统计
var cards_revealed: int = 0
var day_start_revealed: int = 0
var monsters_slain: int = 0
var photos_used: int = 0

## 道具栏 { "coffee": 2, "shield": 1, ... }
var inventory: Dictionary[String, int] = {}

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
		INITIAL_RESOURCES = { "san": 10, "health": 10, "inspiration": 10, "money": 50, "film": 3 }
		RESOURCE_MAX = { "san": 10, "health": 10, "inspiration": -1, "money": -1, "film": -1 }
		RESOURCE_ICONS = { "san": "🧠", "health": "❤️", "inspiration": "💡", "money": "💰", "film": "📷" }
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_warning("[GameData] Failed to parse game_config.json: %s" % json.get_error_message())
		return
	var data: Dictionary = json.data
	MAX_DAYS = int(data.get("max_days", 7))
	# int conversion for resource dicts
	var raw_init: Dictionary = data.get("initial_resources", {})
	for k in raw_init:
		INITIAL_RESOURCES[k] = int(raw_init[k])
	var raw_max: Dictionary = data.get("resource_max", {})
	for k in raw_max:
		RESOURCE_MAX[k] = int(raw_max[k])
	RESOURCE_ICONS = data.get("resource_icons", {})
	DAILY_FILM = int(data.get("daily_film", 3))
	DEFEAT_CONDITIONS = data.get("defeat_conditions", ["san", "health"])
	STEPS_FROM_HEALTH = data.get("steps_from_health", true)
	CONVERSION_EVENTS = data.get("conversion_events", {})
	MONSTER_SCALING = data.get("monster_scaling", {})
	LOCATION_SCARCITY = data.get("location_scarcity", {})
	print("[GameData] Loaded game_config.json: max_days=%d, resources=%s" % [MAX_DAYS, str(INITIAL_RESOURCES)])

func reset() -> void:
	resources = INITIAL_RESOURCES.duplicate()
	game_phase = "title"
	demo_state = "idle"
	current_day = 0
	steps_remaining = 0
	steps_total = 0
	daily_film = DAILY_FILM
	perm_film = 0
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

## 检查是否失败 (defeat_conditions 中任一资源 <= 0)
func check_defeat() -> bool:
	for key in DEFEAT_CONDITIONS:
		if resources.get(key, 0) <= 0:
			return true
	return false

## 检查是否胜利 (存活天数达到 MAX_DAYS)
func check_victory() -> bool:
	return current_day > MAX_DAYS

# ---------------------------------------------------------------------------
# 资源上限操作
# ---------------------------------------------------------------------------

## 获取资源上限 (-1 表示无上限)
func get_resource_max(key: String) -> int:
	return RESOURCE_MAX.get(key, -1)

## 设置资源上限 (用于暗面道具 sanMax/healthMax 增益)
func set_resource_max(key: String, value: int) -> void:
	RESOURCE_MAX[key] = value

## 修改资源上限 (delta 可正可负)
func modify_resource_max(key: String, delta: int) -> void:
	var current_max: int = RESOURCE_MAX.get(key, -1)
	if current_max < 0:
		return  # 无上限资源不可修改
	RESOURCE_MAX[key] = maxi(1, current_max + delta)

# ---------------------------------------------------------------------------
# 步数系统
# ---------------------------------------------------------------------------

## 初始化每日步数 (每日开始时调用)
func init_daily_steps() -> void:
	if STEPS_FROM_HEALTH:
		steps_total = resources.get("health", 10)
	else:
		steps_total = 10  # fallback
	steps_remaining = steps_total

## 消耗一步
func use_step() -> bool:
	if steps_remaining <= 0:
		return false
	steps_remaining -= 1
	return true

## 是否还有剩余步数
func has_steps_remaining() -> bool:
	return steps_remaining > 0

# ---------------------------------------------------------------------------
# 胶卷拆分系统
# ---------------------------------------------------------------------------

## 获取实际可用胶卷 (daily + perm)
func get_total_film() -> int:
	return daily_film + perm_film

## 每日重置胶卷 (daily 重置为 DAILY_FILM, perm 保留)
func reset_daily_film() -> void:
	daily_film = DAILY_FILM
	resources["film"] = get_total_film()

## 增加永久胶卷
func add_perm_film(count: int) -> void:
	perm_film += count
	resources["film"] = get_total_film()

## 消耗胶卷 (优先消耗 daily)
func consume_film(count: int = 1) -> bool:
	if get_total_film() < count:
		return false
	for _i in range(count):
		if daily_film > 0:
			daily_film -= 1
		else:
			perm_film -= 1
	resources["film"] = get_total_film()
	return true

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
