class_name StoryEventManager
extends RefCounted

## StoryEventManager - 翻牌故事事件 + 晨间事件 查询与触发
## 数据从 data/story_events.json 和 data/morning_events.json 加载
## 使用 StoryManager 条件引擎筛选, MilestoneManager 触发级联 hook

# ---------------------------------------------------------------------------
# 数据
# ---------------------------------------------------------------------------

## 翻牌故事事件列表
var _story_events: Array = []

## 晨间事件列表
var _morning_events: Array = []

## 夜谈事件列表
var _evening_events: Array = []

## 中段事件列表
var _mid_day_events: Array = []

## 是否已加载
var _loaded: bool = false

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _init() -> void:
	_load_data()

func _load_data() -> void:
	if _loaded:
		return

	# 加载 story_events.json
	var f1 := FileAccess.open("res://data/story_events.json", FileAccess.READ)
	if f1 != null:
		var json1 := JSON.new()
		if json1.parse(f1.get_as_text()) == OK and json1.data is Dictionary:
			_story_events = json1.data.get("events", [])
		f1.close()

	# 加载 morning_events.json
	var f2 := FileAccess.open("res://data/morning_events.json", FileAccess.READ)
	if f2 != null:
		var json2 := JSON.new()
		if json2.parse(f2.get_as_text()) == OK and json2.data is Dictionary:
			_morning_events = json2.data.get("events", [])
		f2.close()

	# 加载 evening_events.json
	var f3 := FileAccess.open("res://data/evening_events.json", FileAccess.READ)
	if f3 != null:
		var json3 := JSON.new()
		if json3.parse(f3.get_as_text()) == OK and json3.data is Dictionary:
			_evening_events = json3.data.get("events", [])
		f3.close()

	# 加载 mid_day_events.json
	var f4 := FileAccess.open("res://data/mid_day_events.json", FileAccess.READ)
	if f4 != null:
		var json4 := JSON.new()
		if json4.parse(f4.get_as_text()) == OK and json4.data is Dictionary:
			_mid_day_events = json4.data.get("events", [])
		f4.close()

	print("[StoryEventManager] Loaded %d story events, %d morning events, %d evening events, %d mid-day events" % [
		_story_events.size(), _morning_events.size(), _evening_events.size(), _mid_day_events.size()])
	_loaded = true

# ---------------------------------------------------------------------------
# 翻牌事件查询
# ---------------------------------------------------------------------------

## 查询当前可触发的翻牌故事事件
## card_type: "plot" | "clue"
## 返回 Dictionary (事件数据) 或 null (无匹配)
func query_event(card_type: String):
	var candidates: Array = []

	for evt in _story_events:
		if evt.get("card_type", "") != card_type:
			continue
		if StoryManager.check_condition(evt.get("condition")):
			candidates.append(evt)

	if candidates.is_empty():
		return null

	# 按 priority 排序 (越小越优先)
	candidates.sort_custom(func(a, b): return int(a.get("priority", 99)) < int(b.get("priority", 99)))

	# 取最高优先级
	var best_priority: int = int(candidates[0].get("priority", 99))
	var top_candidates: Array = []
	for evt in candidates:
		if int(evt.get("priority", 99)) == best_priority:
			top_candidates.append(evt)
		else:
			break

	var pick = top_candidates[randi() % top_candidates.size()]
	print("[StoryEventManager] Matched event: %s (priority=%d, total_candidates=%d)" % [
		pick.get("id", ""), int(pick.get("priority", 99)), candidates.size()])
	return pick

# ---------------------------------------------------------------------------
# 翻牌事件触发
# ---------------------------------------------------------------------------

## 触发翻牌故事事件 (设置 onceFlag)
## 返回事件数据; 调用方负责展示对话
func trigger_event(event: Dictionary) -> Dictionary:
	var event_id: String = event.get("id", "unknown")
	print("[StoryEventManager] Triggering event: %s" % event_id)

	# 设置 onceFlag
	var once_flag: String = event.get("once_flag", "")
	if once_flag != "":
		StoryManager.set_flag(once_flag)

	return event

## 事件对话完成后调用 (应用效果、收集碎片、触发里程碑 hook)
## chosen_choice_id: 玩家选择的 choice_id (空串 = 无选择)
func on_event_complete(event: Dictionary, chosen_choice_id: String = "") -> Dictionary:
	var result: Dictionary = {
		"clue_name": "",
		"is_new_clue": false,
		"fragment_name": "",
		"is_new_fragment": false,
	}

	# 应用选择效果
	if chosen_choice_id != "" and event.has("choice_effects"):
		var choice_effects: Dictionary = event.get("choice_effects", {})
		if choice_effects.has(chosen_choice_id):
			var eff: Dictionary = choice_effects[chosen_choice_id]
			var was_sleeping: bool = StoryManager.sleep_days_left > 0
			var eff_result: Dictionary = StoryManager.apply_choice_effects(eff)
			result.merge(eff_result, true)

			# 里程碑: 选择导致白夜沉睡时触发 hook
			if not was_sleeping and StoryManager.sleep_days_left > 0:
				MilestoneManager.try_trigger("baiye_sleep")

	# 碎片收集
	var fragment_id: String = event.get("fragment", "")
	if fragment_id != "":
		var is_new: bool = StoryManager.collect_fragment(fragment_id)
		if is_new:
			var info: Dictionary = StoryManager.get_fragment_info(fragment_id)
			result["fragment_name"] = info.get("name", fragment_id)
			result["is_new_fragment"] = true
			print("[StoryEventManager] Fragment collected: %s -> %s" % [event.get("id", ""), fragment_id])

			# 里程碑: 碎片收集 hook
			MilestoneManager.try_trigger("fragment_collect")

	return result

# ---------------------------------------------------------------------------
# 晨间事件查询
# ---------------------------------------------------------------------------

## 查询当前可触发的晨间事件
## 返回 Dictionary (事件数据) 或 null (无匹配)
func query_morning_event():
	var candidates: Array = []

	for evt in _morning_events:
		if StoryManager.check_condition(evt.get("condition")):
			candidates.append(evt)

	if candidates.is_empty():
		return null

	# 按 priority 排序 (越小越优先)
	candidates.sort_custom(func(a, b): return int(a.get("priority", 99)) < int(b.get("priority", 99)))

	var best_priority: int = int(candidates[0].get("priority", 99))
	var top_candidates: Array = []
	for evt in candidates:
		if int(evt.get("priority", 99)) == best_priority:
			top_candidates.append(evt)
		else:
			break

	var pick = top_candidates[randi() % top_candidates.size()]
	print("[StoryEventManager] Morning event matched: %s (priority=%d)" % [
		pick.get("id", ""), int(pick.get("priority", 99))])
	return pick

## 触发晨间事件 (设置 onceFlag)
## 返回事件数据; 调用方负责展示对话
func trigger_morning_event(event: Dictionary) -> Dictionary:
	print("[StoryEventManager] Triggering morning event: %s" % event.get("id", ""))

	var once_flag: String = event.get("once_flag", "")
	if once_flag != "":
		StoryManager.set_flag(once_flag)

	return event

## 晨间事件对话完成后调用 (应用效果、收集碎片)
func on_morning_event_complete(event: Dictionary, chosen_choice_id: String = "") -> Dictionary:
	var result: Dictionary = {
		"fragment_name": "",
		"is_new_fragment": false,
	}

	# 应用选择效果
	if chosen_choice_id != "" and event.has("choice_effects"):
		var choice_effects: Dictionary = event.get("choice_effects", {})
		if choice_effects.has(chosen_choice_id):
			var eff: Dictionary = choice_effects[chosen_choice_id]
			var eff_result: Dictionary = StoryManager.apply_choice_effects(eff)
			result.merge(eff_result, true)

	# 碎片收集
	var fragment_id: String = event.get("fragment", "")
	if fragment_id != "":
		var is_new: bool = StoryManager.collect_fragment(fragment_id)
		if is_new:
			var info: Dictionary = StoryManager.get_fragment_info(fragment_id)
			result["fragment_name"] = info.get("name", fragment_id)
			result["is_new_fragment"] = true
			print("[StoryEventManager] Fragment from morning: %s -> %s" % [event.get("id", ""), fragment_id])

	return result

# ---------------------------------------------------------------------------
# 夜谈事件查询与触发
# ---------------------------------------------------------------------------

## 查询当前可触发的夜谈事件
## 返回 Dictionary (事件数据) 或 null (无匹配)
func query_evening_event():
	var candidates: Array = []

	for evt in _evening_events:
		if StoryManager.check_condition(evt.get("condition")):
			candidates.append(evt)

	if candidates.is_empty():
		return null

	# 按 priority 排序 (越小越优先)
	candidates.sort_custom(func(a, b): return int(a.get("priority", 99)) < int(b.get("priority", 99)))

	var best_priority: int = int(candidates[0].get("priority", 99))
	var top_candidates: Array = []
	for evt in candidates:
		if int(evt.get("priority", 99)) == best_priority:
			top_candidates.append(evt)
		else:
			break

	var pick = top_candidates[randi() % top_candidates.size()]
	print("[StoryEventManager] Evening event matched: %s (priority=%d)" % [
		pick.get("id", ""), int(pick.get("priority", 99))])
	return pick

## 触发夜谈事件 (设置 once_flag)
## 返回事件数据; 调用方负责展示对话
func trigger_evening_event(event: Dictionary) -> Dictionary:
	print("[StoryEventManager] Triggering evening event: %s" % event.get("id", ""))

	var once_flag: String = event.get("once_flag", "")
	if once_flag != "":
		StoryManager.set_flag(once_flag)

	return event

## 夜谈事件对话完成后调用 (应用选择效果)
func on_evening_event_complete(event: Dictionary, chosen_choice_id: String = "") -> void:
	if chosen_choice_id != "" and event.has("choice_effects"):
		var choice_effects: Dictionary = event.get("choice_effects", {})
		if choice_effects.has(chosen_choice_id):
			var eff: Dictionary = choice_effects[chosen_choice_id]
			StoryManager.apply_choice_effects(eff)

# ---------------------------------------------------------------------------
# 中段事件查询与触发
# 触发时机：玩家抵达当日目标地点后
#   1. 优先查 hook_id="daily_goal_<location>" (地点专属, priority 越小越优先)
#   2. 无匹配则查 hook_id="daily_goal_any" (通用兜底)
#   3. 仍无则返回 null (静默)
# ---------------------------------------------------------------------------

## 查询中段可触发事件
## location: 地点 key 字符串 (如 "hospital", "park")
## 返回 Dictionary (事件数据) 或 null (无匹配)
func query_mid_event(location: String):
	# 第一轮：地点专属 hook
	var specific_hook := "daily_goal_" + location
	var result = _pick_mid_candidates(specific_hook)
	if result != null:
		return result

	# 第二轮：通用兜底 hook
	return _pick_mid_candidates("daily_goal_any")

## 内部辅助：筛选指定 hook_id 的候选事件并随机取一个
func _pick_mid_candidates(hook_id: String):
	var candidates: Array = []

	for evt in _mid_day_events:
		if evt.get("hook_id", "") != hook_id:
			continue
		if StoryManager.check_condition(evt.get("condition")):
			candidates.append(evt)

	if candidates.is_empty():
		return null

	# 按 priority 排序 (越小越优先)
	candidates.sort_custom(func(a, b): return int(a.get("priority", 99)) < int(b.get("priority", 99)))

	var best_priority: int = int(candidates[0].get("priority", 99))
	var top_candidates: Array = []
	for evt in candidates:
		if int(evt.get("priority", 99)) == best_priority:
			top_candidates.append(evt)
		else:
			break

	var pick = top_candidates[randi() % top_candidates.size()]
	print("[StoryEventManager] Mid-day event matched: %s (hook=%s, priority=%d)" % [
		pick.get("id", ""), hook_id, int(pick.get("priority", 99))])
	return pick

## 触发中段事件 (设置 once_flag)
## 返回事件数据; 调用方负责展示对话
func trigger_mid_event(event: Dictionary) -> Dictionary:
	print("[StoryEventManager] Triggering mid-day event: %s" % event.get("id", ""))

	var once_flag: String = event.get("once_flag", "")
	if once_flag != "":
		StoryManager.set_flag(once_flag)

	return event

## 中段事件对话完成后调用 (应用选择效果、收集碎片)
func on_mid_event_complete(event: Dictionary, chosen_choice_id: String = "") -> Dictionary:
	var result: Dictionary = {
		"fragment_name": "",
		"is_new_fragment": false,
	}

	# 应用选择效果
	if chosen_choice_id != "" and event.has("choice_effects"):
		var choice_effects: Dictionary = event.get("choice_effects", {})
		if choice_effects.has(chosen_choice_id):
			var eff: Dictionary = choice_effects[chosen_choice_id]
			var eff_result: Dictionary = StoryManager.apply_choice_effects(eff)
			result.merge(eff_result, true)

	# 碎片收集
	var fragment_id: String = event.get("fragment", "")
	if fragment_id != "":
		var is_new: bool = StoryManager.collect_fragment(fragment_id)
		if is_new:
			var info: Dictionary = StoryManager.get_fragment_info(fragment_id)
			result["fragment_name"] = info.get("name", fragment_id)
			result["is_new_fragment"] = true
			print("[StoryEventManager] Fragment from mid-day: %s -> %s" % [event.get("id", ""), fragment_id])

	return result

# ---------------------------------------------------------------------------
# 重置
# ---------------------------------------------------------------------------

func reset() -> void:
	_story_events.clear()
	_morning_events.clear()
	_evening_events.clear()
	_mid_day_events.clear()
	_loaded = false
	_load_data()
	print("[StoryEventManager] Reset")
