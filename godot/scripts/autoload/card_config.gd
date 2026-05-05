## CardConfig - 统一配置加载器 (Autoload)
## 从 data/ 下多个 JSON 文件加载配置，并提供带 fallback 的查询接口
##
## ⚠️ 迁移状态 (Phase 6):
## - location_info / schedule_templates / rumor_*
##   → 已迁移到 Locations (data/locations.json)，CardConfig 委托 Locations 获取
## - event_weights / card_effects / event_texts / trap_subtype_* / dark_texts
##   → 已迁移到 EventPool (data/event_pool.json)，本文件保留作为 fallback
## - card_types / dark_card_types
##   → 已迁移到 EventPool (event_types / dark_card_types)，CardConfig 委托获取
## - shop_* / dw_*
##   → 尚未迁移，仍由 CardConfig 独占管理
extends Node

# ---------------------------------------------------------------------------
# 配置数据 (按文件组织)
# ---------------------------------------------------------------------------
# 地点数据（委托 Locations autoload，原 real_world.json）
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
var dark_texts: Dictionary = {}  # 暗面事件文本 { type: {icon, label, texts: []} }
var _event_defaults: Dictionary = {}  # events.json defaults 原始数据 (含 inspiration_clue_threshold 等)

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
var dw_item_reward_pool: Array = []  # 暗面道具奖励池 (加权)

# shop.json (暗面商店)
var dark_items: Dictionary = {}       # 暗面专属道具
var dark_variants: Array = []         # 暗面商店变体

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
# 加载：地点数据（委托 Locations autoload）
# ---------------------------------------------------------------------------
func _load_real_world() -> void:
	# real_world.json 已删除，数据统一由 Locations (data/locations.json) 管理
	location_info      = Locations.get_location_info()
	schedule_templates = Locations.get_schedule_templates()
	rumor_safe_texts   = Locations.rumors.get("safe_texts", [])
	rumor_danger_texts = Locations.rumors.get("danger_texts", [])

# ---------------------------------------------------------------------------
# 加载：卡牌类型（委托 EventPool autoload，原 card_types.json）
# ---------------------------------------------------------------------------
func _load_card_types() -> void:
	# card_types.json 已删除，数据统一由 EventPool (data/event_pool.json) 管理
	card_types      = EventPool.event_types
	dark_card_types = EventPool.dark_card_types

# ---------------------------------------------------------------------------
# 加载：events.json (仅保留 effects/texts/inspiration_clue_threshold)
# 已迁移字段委托 EventPool / Locations 获取
# ---------------------------------------------------------------------------
func _load_events() -> void:
	var data: Dictionary = _load_json("res://data/events.json")
	if data.is_empty():
		return

	var defaults: Dictionary = data.get("defaults", {})
	_event_defaults   = defaults  # 保留原始引用供 get_event_config() 使用
	card_effects      = defaults.get("effects", {})
	event_texts       = defaults.get("texts", {})

	# weights → 委托 EventPool.base_weights
	event_weights     = EventPool.base_weights

	# trap_subtypes → 委托 EventPool.trap_subtypes
	trap_subtype_info = EventPool.trap_subtypes
	trap_subtype_texts.clear()
	for sub_name in trap_subtype_info:
		var sub: Dictionary = trap_subtype_info[sub_name]
		if sub.has("texts"):
			trap_subtype_texts[sub_name] = sub["texts"]

	# darkside_info → 委托 Locations.get_dark_display()
	darkside_info.clear()
	for loc_id in Locations.get_real_location_ids():
		var dd: Dictionary = Locations.get_dark_display(loc_id)
		if not dd.is_empty():
			darkside_info[loc_id] = dd

	# dark_texts → 委托 EventPool（get_dark_event_info / get_dark_event_text）
	# 保留空字典，旧代码通过 CardConfig.get_dark_event_info() 访问时会 fallback 到 EventPool
	dark_texts = {}

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
	dark_items        = data.get("dark_items", {})
	dark_variants     = data.get("dark_variants", [])
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
	dw_item_reward_pool = data.get("item_reward_pool", [])

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
	# trap_subtype_info / event_weights 已由 EventPool 完成转换
	for key in card_effects:
		card_effects[key] = _convert_to_int_dict(card_effects[key])


func _convert_shop_to_int() -> void:
	for key in shop_items:
		var item: Dictionary = shop_items[key]
		if item.has("price"):
			item["price"] = int(item["price"])
		if item.has("effect"):
			item["effect"] = _convert_to_int_dict(item["effect"])
	for key in dark_items:
		var item: Dictionary = dark_items[key]
		if item.has("price"):
			item["price"] = int(item["price"])
		if item.has("effect"):
			item["effect"] = _convert_to_int_dict(item["effect"])

# ---------------------------------------------------------------------------
# 查询接口：事件系统（兼容层，委托 EventPool）
# ---------------------------------------------------------------------------

## @deprecated 请使用 EventPool.get_dark_event_info()
## 获取暗面事件文本信息 — 委托 EventPool
func get_dark_event_info(dark_type: String) -> Dictionary:
	return EventPool.get_dark_event_info(dark_type)

## @deprecated 请使用 EventPool.get_dark_event_text()
## 获取暗面事件随机文本 — 委托 EventPool
func get_dark_event_text(dark_type: String) -> String:
	return EventPool.get_dark_event_text(dark_type)

# ---------------------------------------------------------------------------
# 查询接口：暗面世界
# ---------------------------------------------------------------------------

## 获取事件配置 (events.json defaults 层级)
func get_event_config() -> Dictionary:
	return _event_defaults

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

## 获取暗面道具奖励池 (加权随机选取一个, 返回 [resource, amount])
func get_dw_item_reward_pool() -> Array:
	if dw_item_reward_pool.is_empty():
		return []
	# 加权随机
	var total_weight: float = 0.0
	for entry in dw_item_reward_pool:
		total_weight += float(entry.get("weight", 1))
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for entry in dw_item_reward_pool:
		cumulative += float(entry.get("weight", 1))
		if roll <= cumulative:
			return [entry.get("resource", "san"), int(entry.get("amount", 1))]
	# fallback: 返回最后一个
	var last: Dictionary = dw_item_reward_pool[dw_item_reward_pool.size() - 1]
	return [last.get("resource", "san"), int(last.get("amount", 1))]

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
