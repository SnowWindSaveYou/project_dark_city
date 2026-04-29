## CardConfig - 统一配置加载器 (Autoload)
## 从 data/ 下多个 JSON 文件加载配置，并提供带 fallback 的查询接口
extends Node

# ---------------------------------------------------------------------------
# 配置数据 (按文件组织)
# ---------------------------------------------------------------------------
# real_world.json
var location_info: Dictionary = {}
var schedule_templates: Dictionary = {}
var rumor_safe_texts: Array = []
var rumor_danger_texts: Array = []

# card_types.json
var card_types: Dictionary = {}    # reality
var dark_card_types: Dictionary = {}  # dark

# events.json
var event_weights: Dictionary = {}
var card_effects: Dictionary = {}
var event_texts: Dictionary = {}
var trap_subtype_info: Dictionary = {}
var trap_subtype_texts: Dictionary = {}  # 兼容旧代码 { subtype: [text, ...] }
var darkside_info: Dictionary = {}  # 兼容旧代码 { loc: { type: {icon, label, image_path} } }
var _event_locations: Dictionary = {}  # per-location overrides

# shop.json
var shop_items: Dictionary = {}
var consumable_order: Array = []
var shop_variants: Array = []
var shop_refresh_cost: int = 5

# dark_world.json
var dw_constants: Dictionary = {}
var dw_layers: Array = []
var dw_location_pools: Dictionary = {}
var dw_npcs: Dictionary = {}
var dw_ghost_textures: Array = []
var dw_layer_generation: Dictionary = {}

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_load_real_world()
	_load_card_types()
	_load_events()
	_load_shop()
	_load_dark_world()

# ---------------------------------------------------------------------------
# 加载：real_world.json
# ---------------------------------------------------------------------------
func _load_real_world() -> void:
	var data: Dictionary = _load_json("res://data/real_world.json")
	if data.is_empty():
		return

	location_info      = data.get("locations", {})
	schedule_templates = data.get("schedule_templates", {})
	var rumors: Dictionary = data.get("rumors", {})
	rumor_safe_texts   = rumors.get("safe_texts", [])
	rumor_danger_texts = rumors.get("danger_texts", [])
	_convert_schedule_rewards()

# ---------------------------------------------------------------------------
# 加载：card_types.json
# ---------------------------------------------------------------------------
func _load_card_types() -> void:
	var data: Dictionary = _load_json("res://data/card_types.json")
	if data.is_empty():
		return
	card_types       = data.get("reality", {})
	dark_card_types  = data.get("dark", {})

# ---------------------------------------------------------------------------
# 加载：events.json (支持按地点覆盖)
# ---------------------------------------------------------------------------
func _load_events() -> void:
	var data: Dictionary = _load_json("res://data/events.json")
	if data.is_empty():
		return

	var defaults: Dictionary = data.get("defaults", {})
	event_weights     = defaults.get("weights", {})
	card_effects      = defaults.get("effects", {})
	event_texts       = defaults.get("texts", {})
	trap_subtype_info = defaults.get("trap_subtypes", {})
	# 填充 trap_subtype_texts 兼容层 (供 card.gd / event_popup.gd 使用)
	trap_subtype_texts.clear()
	for sub_name in trap_subtype_info:
		var sub: Dictionary = trap_subtype_info[sub_name]
		if sub.has("texts"):
			trap_subtype_texts[sub_name] = sub["texts"]
	_event_locations  = data.get("locations", {})

	# 构建 darkside_info 兼容层 (供 card.gd / event_popup.gd 使用)
	darkside_info.clear()
	for loc_name in _event_locations:
		var loc: Dictionary = _event_locations[loc_name]
		if loc.has("dark_display"):
			darkside_info[loc_name] = loc["dark_display"]

	_convert_events_to_int()

# ---------------------------------------------------------------------------
# 加载：shop.json
# ---------------------------------------------------------------------------
func _load_shop() -> void:
	var data: Dictionary = _load_json("res://data/shop.json")
	if data.is_empty():
		return

	shop_items        = data.get("items", {})
	consumable_order  = data.get("consumable_order", [])
	shop_variants     = data.get("variants", [])
	shop_refresh_cost = int(data.get("refresh_cost", 5))
	_convert_shop_to_int()

# ---------------------------------------------------------------------------
# 加载：dark_world.json
# ---------------------------------------------------------------------------
func _load_dark_world() -> void:
	var data: Dictionary = _load_json("res://data/dark_world.json")
	if data.is_empty():
		return

	dw_constants        = data.get("constants", {})
	dw_layers           = data.get("layers", [])
	dw_location_pools   = data.get("location_pools", {})
	dw_npcs             = data.get("npcs", {})
	dw_ghost_textures   = data.get("ghost_textures", [])
	dw_layer_generation = data.get("layer_generation", {})

# ---------------------------------------------------------------------------
# JSON 加载辅助
# ---------------------------------------------------------------------------
func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CardConfig: 无法打开 %s" % path)
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("CardConfig: JSON 解析失败 %s: %s (行 %d)" % [path, json.get_error_message(), json.get_error_line()])
		return {}
	if not json.data is Dictionary:
		push_error("CardConfig: JSON 根节点必须是 Dictionary: %s" % path)
		return {}
	return json.data

# ---------------------------------------------------------------------------
# 类型转换：JSON float → int
# ---------------------------------------------------------------------------
func _convert_to_int_dict(d: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for k in d:
		result[k] = int(d[k])
	return result

func _convert_events_to_int() -> void:
	for key in trap_subtype_info:
		var info: Dictionary = trap_subtype_info[key]
		if info.has("effect"):
			info["effect"] = _convert_to_int_dict(info["effect"])
	for key in card_effects:
		card_effects[key] = _convert_to_int_dict(card_effects[key])
	for key in event_weights:
		event_weights[key] = int(event_weights[key])

func _convert_schedule_rewards() -> void:
	for key in schedule_templates:
		var tmpl: Dictionary = schedule_templates[key]
		if tmpl.has("reward"):
			var reward: Array = tmpl["reward"]
			if reward.size() >= 2:
				reward[1] = int(reward[1])

func _convert_shop_to_int() -> void:
	for key in shop_items:
		var item: Dictionary = shop_items[key]
		if item.has("price"):
			item["price"] = int(item["price"])
		if item.has("effect"):
			item["effect"] = _convert_to_int_dict(item["effect"])

# ---------------------------------------------------------------------------
# 查询接口：事件系统 (支持按地点 fallback)
# ---------------------------------------------------------------------------

## 获取事件效果 — 优先取地点覆盖，否则取 default
func get_event_effect(event_type: String, location: String = "") -> Dictionary:
	if not location.is_empty() and _event_locations.has(location):
		var loc: Dictionary = _event_locations[location]
		if loc.has("effects") and loc["effects"].has(event_type):
			return _merge_dict(card_effects.get(event_type, {}), loc["effects"][event_type])
	return card_effects.get(event_type, {})

## 获取事件文本列表 — 优先取地点覆盖，否则取 default
func get_event_texts(event_type: String, location: String = "") -> Array:
	if not location.is_empty() and _event_locations.has(location):
		var loc: Dictionary = _event_locations[location]
		if loc.has("texts") and loc["texts"].has(event_type):
			return loc["texts"][event_type]
	return event_texts.get(event_type, [])

## 获取暗面地点显示信息（用于 darkside_info 兼容）
## 返回 { "icon": String, "label": String, "image_path": String } 或空 Dictionary
func get_dark_display(location: String, event_type: String) -> Dictionary:
	if _event_locations.has(location):
		var loc: Dictionary = _event_locations[location]
		if loc.has("dark_display") and loc["dark_display"].has(event_type):
			return loc["dark_display"][event_type]
	return {}

## 合并字典：base 为基础值，override 为覆盖值（override 优先级更高）
func _merge_dict(base: Dictionary, override: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate()
	for k in override:
		result[k] = override[k]
	return result

# ---------------------------------------------------------------------------
# 查询接口：暗面世界
# ---------------------------------------------------------------------------

func get_dw_max_energy() -> int:
	return dw_constants.get("max_energy", 10)

func get_dw_ghost_san_damage() -> int:
	return dw_constants.get("ghost_san_damage", 2)

func get_dw_ghost_chase_dist() -> int:
	return dw_constants.get("ghost_chase_dist", 2)

func get_dw_ghost_count(layer_idx: int) -> int:
	var arr: Array = dw_constants.get("ghost_count", [2, 3, 2])
	if layer_idx >= 0 and layer_idx < arr.size():
		return arr[layer_idx]
	return 2

func get_dw_layer_config(layer_idx: int) -> Dictionary:
	if layer_idx >= 0 and layer_idx < dw_layers.size():
		return dw_layers[layer_idx]
	return {}

func get_dw_location_pool(layer_idx: int) -> Dictionary:
	var key: String = str(layer_idx)
	return dw_location_pools.get(key, {})

func get_dw_npcs(layer_idx: int) -> Array:
	var key: String = str(layer_idx)
	return dw_npcs.get(key, [])

func get_dw_ghost_textures() -> Array:
	return dw_ghost_textures

## 获取层生成配置 (返回值中的 range 会自动 randi_range)
func get_dw_layer_gen(layer_idx: int) -> Dictionary:
	var key: String = str(layer_idx)
	var gen: Dictionary = dw_layer_generation.get(key, {})
	if gen.is_empty():
		return {}
	# 深拷贝，避免修改原数据
	var result: Dictionary = {}
	for k in gen:
		var v = gen[k]
		if v is Array and v.size() == 2:
			result[k] = randi_range(int(v[0]), int(v[1]))
		else:
			result[k] = v
	return result
