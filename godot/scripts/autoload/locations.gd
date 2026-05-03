## Locations - 全局地点管理 (Autoload)
## 加载 data/locations.json，提供地点查询接口
extends Node

# ---------------------------------------------------------------------------
# 配置数据
# ---------------------------------------------------------------------------
var real_world: Dictionary = {}       # { loc_id: { label, icon, schedule, forced_type, event_pool, weight_mods, ... } }
var dark_layers: Array = []           # [ { name, unlock_day, unlock_fragments } ]
var dark_locations: Dictionary = {}   # { loc_name: { layer, dark_type, event_pool, weight_mods, ... } }
var rumors: Dictionary = {}           # { safe_texts: [...], danger_texts: [...] }

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load()

func _load() -> void:
	var data: Dictionary = _load_json("res://data/locations.json")
	if data.is_empty():
		push_error("Locations: locations.json 加载失败")
		return

	real_world     = data.get("real_world", {})
	dark_layers    = data.get("dark_world", {}).get("layers", [])
	dark_locations = data.get("dark_world", {}).get("locations", {})
	rumors         = data.get("rumors", {})

	_convert_data()

# ---------------------------------------------------------------------------
# 类型转换
# ---------------------------------------------------------------------------

func _convert_data() -> void:
	# real_world: schedule.reward → int, weight_mods → int, location_effect → int
	for loc_id in real_world:
		var loc: Dictionary = real_world[loc_id]
		# schedule reward
		var schedule: Dictionary = loc.get("schedule", {})
		if schedule.has("reward") and schedule["reward"] is Array and schedule["reward"].size() >= 2:
			schedule["reward"][1] = int(schedule["reward"][1])
		# weight_mods
		if loc.has("weight_mods"):
			loc["weight_mods"] = _convert_to_int_dict(loc["weight_mods"])
		# location_effect
		if loc.has("location_effect"):
			loc["location_effect"] = _convert_to_int_dict(loc["location_effect"])

	# dark_layers: unlock_day / unlock_fragments → int
	for i in range(dark_layers.size()):
		var layer: Dictionary = dark_layers[i]
		if layer.has("unlock_day"):
			layer["unlock_day"] = int(layer["unlock_day"])
		if layer.has("unlock_fragments"):
			layer["unlock_fragments"] = int(layer["unlock_fragments"])

	# dark_locations: layer → int, weight_mods → int
	for loc_name in dark_locations:
		var loc: Dictionary = dark_locations[loc_name]
		if loc.has("layer"):
			loc["layer"] = int(loc["layer"])
		if loc.has("weight_mods"):
			loc["weight_mods"] = _convert_to_int_dict(loc["weight_mods"])

# ---------------------------------------------------------------------------
# 现实世界查询
# ---------------------------------------------------------------------------

## 获取现实世界地点定义
func get_real_location(loc_id: String) -> Dictionary:
	if real_world.has(loc_id):
		var loc: Dictionary = real_world[loc_id].duplicate(true)
		loc["_id"] = loc_id
		return loc
	push_warning("Locations: 未知现实地点 '%s'" % loc_id)
	return {}

## 获取所有现实世界地点 ID
func get_real_location_ids() -> Array:
	return real_world.keys()

## 获取地点日程信息
func get_schedule(loc_id: String) -> Dictionary:
	var loc: Dictionary = real_world.get(loc_id, {})
	return loc.get("schedule", {})

## 获取地点的暗面显示覆盖（用于卡牌在暗面时的视觉）
func get_dark_display(loc_id: String) -> Dictionary:
	var loc: Dictionary = real_world.get(loc_id, {})
	return loc.get("dark_display", {})

## 获取地点的事件池列表
func get_real_event_pool(loc_id: String) -> Array:
	var loc: Dictionary = real_world.get(loc_id, {})
	return loc.get("event_pool", [])

## 获取地点的权重修正
func get_real_weight_mods(loc_id: String) -> Dictionary:
	var loc: Dictionary = real_world.get(loc_id, {})
	return loc.get("weight_mods", {})

## 获取地点的强制类型（home/shop/landmark 或 null）
func get_forced_type(loc_id: String):
	var loc: Dictionary = real_world.get(loc_id, {})
	return loc.get("forced_type", null)

## 获取地点的场所效果（如公园的 san +1）
func get_location_effect(loc_id: String) -> Dictionary:
	var loc: Dictionary = real_world.get(loc_id, {})
	return loc.get("location_effect", {})

## 判断地点是否为地标
func is_landmark(loc_id: String) -> bool:
	var loc: Dictionary = real_world.get(loc_id, {})
	return loc.get("is_landmark", false)

# ---------------------------------------------------------------------------
# 暗世界查询
# ---------------------------------------------------------------------------

## 获取暗世界地点定义
func get_dark_location(loc_name: String) -> Dictionary:
	if dark_locations.has(loc_name):
		var loc: Dictionary = dark_locations[loc_name].duplicate(true)
		loc["_name"] = loc_name
		return loc
	push_warning("Locations: 未知暗面地点 '%s'" % loc_name)
	return {}

## 获取指定层级的所有暗面地点
func get_dark_locations_by_layer(layer: int) -> Dictionary:
	var result: Dictionary = {}
	for loc_name in dark_locations:
		if dark_locations[loc_name].get("layer", -1) == layer:
			var loc: Dictionary = dark_locations[loc_name].duplicate(true)
			loc["_name"] = loc_name
			result[loc_name] = loc
	return result

## 获取暗世界层级信息
func get_dark_layer(layer_index: int) -> Dictionary:
	if layer_index >= 0 and layer_index < dark_layers.size():
		return dark_layers[layer_index].duplicate()
	return {}

## 获取暗世界层级数量
func get_dark_layer_count() -> int:
	return dark_layers.size()

## 获取暗面地点的事件池列表
func get_dark_event_pool(loc_name: String) -> Array:
	var loc: Dictionary = dark_locations.get(loc_name, {})
	return loc.get("event_pool", [])

## 获取暗面地点的权重修正
func get_dark_weight_mods(loc_name: String) -> Dictionary:
	var loc: Dictionary = dark_locations.get(loc_name, {})
	return loc.get("weight_mods", {})

# ---------------------------------------------------------------------------
# 传言查询
# ---------------------------------------------------------------------------

## 获取安全传言（格式化 %s 为地点名）
func get_safe_rumor(location_label: String) -> String:
	var texts: Array = rumors.get("safe_texts", [])
	if texts.is_empty():
		return "%s附近很平静" % location_label
	return texts[randi() % texts.size()] % location_label

## 获取危险传言（格式化 %s 为地点名）
func get_danger_rumor(location_label: String) -> String:
	var texts: Array = rumors.get("danger_texts", [])
	if texts.is_empty():
		return "%s有危险" % location_label
	return texts[randi() % texts.size()] % location_label

# ---------------------------------------------------------------------------
# 兼容层：供旧代码过渡
# ---------------------------------------------------------------------------

## 替代 CardConfig.location_info
func get_location_info() -> Dictionary:
	var info: Dictionary = {}
	for loc_id in real_world:
		var loc: Dictionary = real_world[loc_id]
		info[loc_id] = {
			"label": loc.get("label", loc_id),
			"icon": loc.get("icon", "📍"),
			"image_path": loc.get("image_path", "")
		}
	return info

## 替代 CardConfig.schedule_templates
func get_schedule_templates() -> Dictionary:
	var templates: Dictionary = {}
	for loc_id in real_world:
		var sched: Dictionary = real_world[loc_id].get("schedule", {})
		if not sched.is_empty():
			templates[loc_id] = sched
	return templates

# ---------------------------------------------------------------------------
# JSON 加载辅助
# ---------------------------------------------------------------------------

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Locations: 无法打开 %s" % path)
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("Locations: JSON 解析失败 %s: %s (行 %d)" % [path, json.get_error_message(), json.get_error_line()])
		return {}
	if not json.data is Dictionary:
		push_error("Locations: JSON 根节点必须是 Dictionary: %s" % path)
		return {}
	return json.data

func _convert_to_int_dict(d: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for k in d:
		result[k] = int(d[k])
	return result
