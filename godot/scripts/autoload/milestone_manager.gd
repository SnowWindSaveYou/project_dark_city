## MilestoneManager - 里程碑事件查询与触发 (Autoload)
## 根据 hookId + 条件引擎筛选首次触发的里程碑对话
## 数据从 data/milestone_events.json 加载
extends Node

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal milestone_triggered(event_id: String, hook_id: String)
signal milestone_dialogue_finished(event_id: String)

# ---------------------------------------------------------------------------
# 数据
# ---------------------------------------------------------------------------

## 按 hook_id 分组的事件索引: { "enter_dark_world": [evt1, evt2, ...], ... }
var _events_by_hook: Dictionary = {}

## 是否已加载
var _loaded: bool = false

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_events()

func _load_events() -> void:
	if _loaded:
		return

	var file := FileAccess.open("res://data/milestone_events.json", FileAccess.READ)
	if file == null:
		push_warning("[MilestoneManager] milestone_events.json not found")
		_loaded = true
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("[MilestoneManager] JSON parse error: %s" % json.get_error_message())
		_loaded = true
		return

	var data: Dictionary = json.data
	var events: Array = data.get("events", [])

	for evt in events:
		var hook: String = evt.get("hook_id", "")
		if hook == "":
			continue
		if not _events_by_hook.has(hook):
			_events_by_hook[hook] = []
		_events_by_hook[hook].append(evt)

	var hook_count: int = _events_by_hook.size()
	print("[MilestoneManager] Indexed %d events across %d hooks" % [events.size(), hook_count])
	_loaded = true

# ---------------------------------------------------------------------------
# 查询: 根据 hookId 返回匹配的最高优先级事件 (或 null)
# ---------------------------------------------------------------------------

## 查询当前 hook 点可触发的里程碑事件
## hook_id: hook 标识 (如 "enter_dark_world")
## 返回 Dictionary (事件数据) 或 null (无匹配)
func query(hook_id: String):
	if not _events_by_hook.has(hook_id):
		return null

	var pool: Array = _events_by_hook[hook_id]
	var candidates: Array = []

	for evt in pool:
		if StoryManager.check_condition(evt.get("condition")):
			candidates.append(evt)

	if candidates.is_empty():
		return null

	# 按 priority 排序 (越小越优先)
	candidates.sort_custom(func(a, b): return int(a.get("priority", 99)) < int(b.get("priority", 99)))

	# 取最高优先级 (最小 priority 值)
	var best_priority: int = int(candidates[0].get("priority", 99))
	var top_candidates: Array = []
	for evt in candidates:
		if int(evt.get("priority", 99)) == best_priority:
			top_candidates.append(evt)
		else:
			break

	# 同优先级随机选一个
	return top_candidates[randi() % top_candidates.size()]

# ---------------------------------------------------------------------------
# 触发: 设置 onceFlag + 应用效果 + 发射信号
# ---------------------------------------------------------------------------

## 尝试触发 hook 点的里程碑事件
## 返回 Dictionary (事件数据) 或 null (无匹配)
## 调用方负责展示对话 (通过返回的 event.dialogue)
func try_trigger(hook_id: String):
	var event = query(hook_id)
	if event == null:
		return null

	var event_id: String = event.get("id", "unknown")
	print("[MilestoneManager] Triggering milestone: %s (hook=%s)" % [event_id, hook_id])

	# 设置 onceFlag (防止重复触发)
	var once_flag: String = event.get("once_flag", "")
	if once_flag != "":
		StoryManager.set_flag(once_flag)

	# 发射信号
	milestone_triggered.emit(event_id, hook_id)

	return event

## 事件对话完成后调用 (应用效果、收集碎片)
## 通常在对话系统播放完 event.dialogue 后调用
func on_event_complete(event: Dictionary, chosen_choice_id: String = "") -> Dictionary:
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
			print("[MilestoneManager] Fragment from milestone: %s -> %s" % [event.get("id", ""), fragment_id])

	milestone_dialogue_finished.emit(event.get("id", ""))
	return result

# ---------------------------------------------------------------------------
# 重置
# ---------------------------------------------------------------------------

func reset() -> void:
	_events_by_hook.clear()
	_loaded = false
	_load_events()
	print("[MilestoneManager] Reset")
