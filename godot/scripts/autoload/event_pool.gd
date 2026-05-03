## EventPool - 全局事件池 (Autoload)
## 加载 data/event_pool.json，提供事件查询接口
extends Node

# ---------------------------------------------------------------------------
# 配置数据
# ---------------------------------------------------------------------------
var event_types: Dictionary = {}      # { type_key: { icon, label, color_key, is_blocking } }
var trap_subtypes: Dictionary = {}    # { subtype_key: { icon, label, effect, texts, image_path } }
var base_weights: Dictionary = {}     # { type_key: int }
var events: Dictionary = {}           # { event_id: { type, world, base_weight, effects, texts, ... } }

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load()

func _load() -> void:
	var data: Dictionary = _load_json("res://data/event_pool.json")
	if data.is_empty():
		push_error("EventPool: event_pool.json 加载失败")
		return

	event_types   = data.get("event_types", {})
	trap_subtypes = data.get("trap_subtypes", {})
	base_weights  = data.get("base_weights", {})
	events        = data.get("events", {})

	_convert_data()

# ---------------------------------------------------------------------------
# 类型转换
# ---------------------------------------------------------------------------

func _convert_data() -> void:
	# base_weights → int
	for k in base_weights:
		base_weights[k] = int(base_weights[k])

	# events 内部字段
	for eid in events:
		var evt: Dictionary = events[eid]
		# base_weight → int
		if evt.has("base_weight"):
			evt["base_weight"] = int(evt["base_weight"])
		# effects → int
		if evt.has("effects") and evt["effects"] is Dictionary:
			evt["effects"] = _convert_to_int_dict(evt["effects"])
		# set_flags 保留原样 (bool/int/string)
		# item_rewards → int
		if evt.has("item_rewards") and evt["item_rewards"] is Array:
			for i in range(evt["item_rewards"].size()):
				var pair: Array = evt["item_rewards"][i]
				if pair.size() >= 2:
					pair[1] = int(pair[1])

	# trap_subtypes → int
	for k in trap_subtypes:
		var sub: Dictionary = trap_subtypes[k]
		if sub.has("effect") and sub["effect"] is Dictionary:
			sub["effect"] = _convert_to_int_dict(sub["effect"])

# ---------------------------------------------------------------------------
# 查询接口
# ---------------------------------------------------------------------------

## 获取事件定义（含 event_id 键）
func get_event(event_id: String) -> Dictionary:
	if events.has(event_id):
		var evt: Dictionary = events[event_id].duplicate()
		evt["_id"] = event_id
		return evt
	push_warning("EventPool: 未知事件 '%s'" % event_id)
	return {}

## 获取指定 type 的所有事件
func get_events_by_type(type: String) -> Array:
	var result: Array = []
	for eid in events:
		if events[eid].get("type", "") == type:
			var evt: Dictionary = events[eid].duplicate()
			evt["_id"] = eid
			result.append(evt)
	return result

## 获取指定 world 的所有事件
func get_events_by_world(world: String) -> Array:
	var result: Array = []
	for eid in events:
		var worlds: Array = events[eid].get("world", [])
		if worlds.has(world):
			var evt: Dictionary = events[eid].duplicate()
			evt["_id"] = eid
			result.append(evt)
	return result

## 获取事件类型元信息
func get_event_type_info(type: String) -> Dictionary:
	return event_types.get(type, {})

## 获取陷阱子类型定义
func get_trap_subtype(subtype: String) -> Dictionary:
	return trap_subtypes.get(subtype, {})

## 获取随机陷阱子类型 key
func get_random_trap_subtype() -> String:
	var keys: Array = trap_subtypes.keys()
	if keys.is_empty():
		return ""
	return keys[randi() % keys.size()]

## 获取事件的随机文本
func get_event_random_text(event_id: String) -> String:
	var evt: Dictionary = events.get(event_id, {})
	var texts: Array = evt.get("texts", [])
	if texts.size() > 0:
		return texts[randi() % texts.size()]
	return "发生了什么..."

## 判断事件类型是否为阻塞类型
func is_blocking_type(type: String) -> bool:
	var info: Dictionary = event_types.get(type, {})
	return info.get("is_blocking", false)

## 获取事件效果（考虑 trap_subtype）
func get_event_effects(event_id: String) -> Dictionary:
	var evt: Dictionary = events.get(event_id, {})
	var effects: Dictionary = evt.get("effects", {})
	# trap 类型且效果为空时，走子类型逻辑
	if evt.get("type", "") == "trap" and effects.is_empty():
		var sub_key: String = evt.get("trap_subtype", "")
		if sub_key == "random":
			sub_key = get_random_trap_subtype()
		var sub: Dictionary = trap_subtypes.get(sub_key, {})
		return sub.get("effect", {})
	return effects

# ---------------------------------------------------------------------------
# 兼容层：暗面事件信息（供旧代码过渡）
# ---------------------------------------------------------------------------

## 获取暗面事件类型的显示信息（替代 CardConfig.get_dark_event_info）
func get_dark_event_info(dark_type: String) -> Dictionary:
	# dark_type 映射到 event_types (如 "shop" → event_types["shop"])
	var info: Dictionary = event_types.get(dark_type, {})
	if info.is_empty():
		return {}
	# 查找该类型的暗面事件获取 texts
	var texts: Array = []
	for eid in events:
		var evt: Dictionary = events[eid]
		if evt.get("type", "") == dark_type and evt.get("world", []).has("dark"):
			texts.append_array(evt.get("texts", []))
	return {
		"icon": info.get("icon", "❓"),
		"label": info.get("label", dark_type),
		"texts": texts
	}

## 获取暗面事件随机文本（替代 CardConfig.get_dark_event_text）
func get_dark_event_text(dark_type: String) -> String:
	var info: Dictionary = get_dark_event_info(dark_type)
	var texts: Array = info.get("texts", [])
	if texts.size() > 0:
		return texts[randi() % texts.size()]
	return "发生了什么..."

# ---------------------------------------------------------------------------
# JSON 加载辅助
# ---------------------------------------------------------------------------

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("EventPool: 无法打开 %s" % path)
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("EventPool: JSON 解析失败 %s: %s (行 %d)" % [path, json.get_error_message(), json.get_error_line()])
		return {}
	if not json.data is Dictionary:
		push_error("EventPool: JSON 根节点必须是 Dictionary: %s" % path)
		return {}
	return json.data

func _convert_to_int_dict(d: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for k in d:
		result[k] = int(d[k])
	return result
