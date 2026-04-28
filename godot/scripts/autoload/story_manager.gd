## StoryManager - 剧情 & 线索管理器 (Autoload)
## 提供 Flag 管理、线索收集、条件求值系统
## 所有剧情内容从 data/story_config.json 加载，策划可直接编辑
extends Node

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal flag_changed(key: String, value: Variant)
signal clue_collected(clue_id: String)
signal chapter_changed(old_chapter: String, new_chapter: String)

# ---------------------------------------------------------------------------
# 配置数据 (从 story_config.json 加载)
# ---------------------------------------------------------------------------
var _chapters: Dictionary = {}
var _clue_defs: Dictionary = {}       # clue_id → { name, desc, category, icon }
var _plot_events: Array = []          # [{ condition, weight, text, set_flags, clue_id }]
var _clue_events: Array = []          # [{ condition, weight, text, clue_id, set_flags }]
var _npc_dialogues: Dictionary = {}   # npc_id → [{ condition, lines }]
var _dark_clue_events: Array = []     # [{ condition, weight, text, clue_id, set_flags }]

# ---------------------------------------------------------------------------
# 运行时状态
# ---------------------------------------------------------------------------
var flags: Dictionary = {}
var collected_clues: Array = []       # Array of clue_id (String)
var current_chapter: String = "prologue"

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_story_config()

func _load_story_config() -> void:
	var file := FileAccess.open("res://data/story_config.json", FileAccess.READ)
	if file == null:
		push_warning("[StoryManager] story_config.json not found, using empty config")
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("[StoryManager] JSON parse error: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return

	var data: Dictionary = json.data
	if not data is Dictionary:
		push_warning("[StoryManager] JSON root must be Dictionary")
		return

	_chapters         = data.get("chapters", {})
	_clue_defs        = data.get("clues", {})
	_plot_events      = data.get("plot_events", [])
	_clue_events      = data.get("clue_events", [])
	_npc_dialogues    = data.get("npc_dialogues", {})
	_dark_clue_events = data.get("dark_clue_events", [])

	# weight 转 int
	for evt in _plot_events:
		if evt.has("weight"):
			evt["weight"] = int(evt["weight"])
	for evt in _clue_events:
		if evt.has("weight"):
			evt["weight"] = int(evt["weight"])
	for evt in _dark_clue_events:
		if evt.has("weight"):
			evt["weight"] = int(evt["weight"])

	print("[StoryManager] Loaded: %d chapters, %d clues, %d plot_events, %d clue_events, %d npc_dialogues" % [
		_chapters.size(), _clue_defs.size(), _plot_events.size(),
		_clue_events.size(), _npc_dialogues.size()])

# ---------------------------------------------------------------------------
# Flag CRUD
# ---------------------------------------------------------------------------

func set_flag(key: String, value: Variant = true) -> void:
	var old = flags.get(key)
	flags[key] = value
	if old != value:
		flag_changed.emit(key, value)
		# 章节推进检查
		_check_chapter_progression()

func get_flag(key: String, default: Variant = null) -> Variant:
	return flags.get(key, default)

func has_flag(key: String) -> bool:
	var val = flags.get(key)
	if val == null:
		return false
	if val is bool:
		return val
	return true

func remove_flag(key: String) -> void:
	if flags.has(key):
		flags.erase(key)
		flag_changed.emit(key, null)

# ---------------------------------------------------------------------------
# 线索收集
# ---------------------------------------------------------------------------

## 收集线索 (去重)，返回是否为新线索
func collect_clue(clue_id: String) -> bool:
	if clue_id in collected_clues:
		return false
	collected_clues.append(clue_id)
	clue_collected.emit(clue_id)
	return true

func has_clue(clue_id: String) -> bool:
	return clue_id in collected_clues

func get_clue_count() -> int:
	return collected_clues.size()

## 获取线索定义信息
func get_clue_info(clue_id: String) -> Dictionary:
	return _clue_defs.get(clue_id, {})

## 按分类获取已收集的线索
func get_clues_by_category(category: String) -> Array:
	var result: Array = []
	for cid in collected_clues:
		var info: Dictionary = _clue_defs.get(cid, {})
		if info.get("category", "") == category:
			result.append({"id": cid, "info": info})
	return result

## 获取所有已收集线索 (带定义信息)
func get_all_clues() -> Array:
	var result: Array = []
	for cid in collected_clues:
		var info: Dictionary = _clue_defs.get(cid, {})
		result.append({"id": cid, "info": info})
	return result

## 获取所有线索分类
func get_clue_categories() -> Array:
	var cats: Dictionary = {}
	for cid in _clue_defs:
		var cat: String = _clue_defs[cid].get("category", "未分类")
		cats[cat] = true
	return cats.keys()

# ---------------------------------------------------------------------------
# 条件求值
# ---------------------------------------------------------------------------

## 递归条件求值
## cond 格式: null | Dictionary
## null → true (无条件)
## { "flag": "key" }       → has_flag(key)
## { "flag_eq": ["k", v] } → get_flag(k) == v
## { "not_flag": "key" }   → not has_flag(key)
## { "has_clue": "id" }    → has_clue(id)
## { "min_clues": N }      → collected_clues.size() >= N
## { "min_day": N }        → GameData.current_day >= N
## { "all": [...] }        → all sub-conditions true
## { "any": [...] }        → any sub-condition true
func check_condition(cond) -> bool:
	if cond == null:
		return true
	if not cond is Dictionary:
		return true

	if cond.has("flag"):
		return has_flag(cond["flag"])

	if cond.has("flag_eq"):
		var pair: Array = cond["flag_eq"]
		if pair.size() >= 2:
			return get_flag(pair[0]) == pair[1]
		return false

	if cond.has("not_flag"):
		return not has_flag(cond["not_flag"])

	if cond.has("has_clue"):
		return has_clue(cond["has_clue"])

	if cond.has("min_clues"):
		return collected_clues.size() >= int(cond["min_clues"])

	if cond.has("min_day"):
		return GameData.current_day >= int(cond["min_day"])

	if cond.has("all"):
		var subs: Array = cond["all"]
		for sub in subs:
			if not check_condition(sub):
				return false
		return true

	if cond.has("any"):
		var subs: Array = cond["any"]
		for sub in subs:
			if check_condition(sub):
				return true
		return false

	# 未知条件类型 → 默认为真
	push_warning("[StoryManager] Unknown condition type: %s" % str(cond))
	return true

# ---------------------------------------------------------------------------
# 事件选择 (条件过滤 + 加权随机)
# ---------------------------------------------------------------------------

## 从事件列表中选择一个满足条件的事件 (加权随机)
## 返回 Dictionary (事件数据) 或 {} (无可用事件)
func pick_event(event_list: Array) -> Dictionary:
	var candidates: Array = []
	var total_weight: int = 0
	for evt in event_list:
		if check_condition(evt.get("condition")):
			var w: int = int(evt.get("weight", 10))
			candidates.append({"event": evt, "weight": w})
			total_weight += w

	if candidates.is_empty() or total_weight <= 0:
		return {}

	var roll: int = randi() % total_weight
	var cumulative: int = 0
	for c in candidates:
		cumulative += c["weight"]
		if roll < cumulative:
			return c["event"]
	return candidates[-1]["event"]

## 选择剧情事件 (翻牌 plot 类型时调用)
func pick_plot_event() -> Dictionary:
	return pick_event(_plot_events)

## 选择线索事件 (翻牌 clue 类型时调用)
func pick_clue_event() -> Dictionary:
	return pick_event(_clue_events)

## 选择暗世界线索事件
func pick_dark_clue_event() -> Dictionary:
	return pick_event(_dark_clue_events)

# ---------------------------------------------------------------------------
# NPC 对话选择
# ---------------------------------------------------------------------------

## 获取 NPC 的当前对话 (取第一个满足条件的对话组)
## 返回 Array of { speaker, text } 或空数组
func get_npc_dialogue(npc_id: String) -> Array:
	var dialogue_list: Array = _npc_dialogues.get(npc_id, [])
	if dialogue_list.is_empty():
		return []

	# 从后往前查找，优先匹配最具体的条件
	for i in range(dialogue_list.size() - 1, -1, -1):
		var entry: Dictionary = dialogue_list[i]
		if check_condition(entry.get("condition")):
			return entry.get("lines", [])

	return []

# ---------------------------------------------------------------------------
# 章节管理
# ---------------------------------------------------------------------------

func _check_chapter_progression() -> void:
	for chapter_id in _chapters:
		if chapter_id == current_chapter:
			continue
		var chapter: Dictionary = _chapters[chapter_id]
		var unlock_cond = chapter.get("unlock")
		if unlock_cond != null and check_condition(unlock_cond):
			# 找到了一个已解锁但不是当前章节的章节
			# 简单逻辑: 按配置顺序取最后一个已解锁的
			pass

	# v1 简化: 不自动推进章节，由事件的 set_flags 驱动
	# 例如 set_flags: { "current_chapter": "chapter1" } 可手动触发

func get_chapter_name() -> String:
	var chapter: Dictionary = _chapters.get(current_chapter, {})
	return chapter.get("name", current_chapter)

## 手动设置章节
func set_chapter(chapter_id: String) -> void:
	if chapter_id == current_chapter:
		return
	if not _chapters.has(chapter_id):
		push_warning("[StoryManager] Unknown chapter: %s" % chapter_id)
		return
	var old: String = current_chapter
	current_chapter = chapter_id
	chapter_changed.emit(old, chapter_id)

# ---------------------------------------------------------------------------
# 应用事件效果
# ---------------------------------------------------------------------------

## 应用事件中的 set_flags + clue_id
## 返回 { "clue_name": String or "", "is_new_clue": bool }
func apply_event_effects(event: Dictionary) -> Dictionary:
	var result: Dictionary = { "clue_name": "", "is_new_clue": false }

	# 设置 flag
	var set_flags: Dictionary = event.get("set_flags", {})
	for key in set_flags:
		# 特殊处理章节切换
		if key == "current_chapter":
			set_chapter(str(set_flags[key]))
		else:
			set_flag(key, set_flags[key])

	# 收集线索
	var clue_id = event.get("clue_id")
	if clue_id != null and clue_id != "":
		var is_new: bool = collect_clue(clue_id)
		var info: Dictionary = get_clue_info(clue_id)
		result["clue_name"] = info.get("name", clue_id)
		result["is_new_clue"] = is_new

	return result

# ---------------------------------------------------------------------------
# 生命周期
# ---------------------------------------------------------------------------

func reset() -> void:
	flags.clear()
	collected_clues.clear()
	current_chapter = "prologue"

## 存档 (预留)
func save_state() -> Dictionary:
	return {
		"flags": flags.duplicate(),
		"collected_clues": collected_clues.duplicate(),
		"current_chapter": current_chapter,
	}

## 读档 (预留)
func load_state(data: Dictionary) -> void:
	flags = data.get("flags", {}).duplicate()
	collected_clues = data.get("collected_clues", []).duplicate()
	current_chapter = data.get("current_chapter", "prologue")
