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
signal fragment_collected(fragment_id: String, total: int)
signal baiye_trust_changed(old_val: int, new_val: int)
signal baiye_sleep_started(days: int)
signal baiye_woke_up()

# ---------------------------------------------------------------------------
# 配置数据 (从 story_config.json 加载)
# ---------------------------------------------------------------------------
var _chapters: Dictionary = {}
var _clue_defs: Dictionary = {}       # clue_id → { name, desc, category, icon, [full_text, chapter, order] }
var _plot_events: Array = []          # [{ condition, weight, text, set_flags, clue_id }]
var _clue_events: Array = []          # [{ condition, weight, text, clue_id, set_flags }]
var _npc_dialogues: Dictionary = {}   # npc_id → [{ condition, lines }]
var _dark_clue_events: Array = []     # [{ condition, weight, text, clue_id, set_flags }]
var _endings: Array = []              # [{ id, title, subtitle, priority, conditions, is_victory }]
var _day_constants: Dictionary = {}   # { base_days, extended_days, extend_threshold }

## 前世记忆碎片的 category 标识 (用于区分碎片类线索)
const FRAGMENT_CATEGORY: String = "前世记忆"

# ---------------------------------------------------------------------------
# 运行时状态
# ---------------------------------------------------------------------------
var flags: Dictionary = {}
var collected_clues: Array = []       # Array of clue_id (String)，包含所有类型（实物线索 + 前世记忆碎片）
var current_chapter: String = "awakening"

# --- 白夜状态 ---
var baiye_trust: int = 0              # 信任度 0-10
var baiye_power: int = 0              # 力量等级 0-5
var sleep_days_left: int = 0          # 沉睡剩余天数 (0 = 可用)

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_story_config()

func _load_story_config() -> void:
	var file: FileAccess = FileAccess.open("res://data/story_config.json", FileAccess.READ)
	if file == null:
		push_warning("[StoryManager] story_config.json not found, using empty config")
		return

	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("[StoryManager] JSON parse error: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return

	var data: Dictionary = json.data
	if not data is Dictionary:
		push_warning("[StoryManager] JSON root must be Dictionary")
		return

	# 章节: 数组 → 字典 (id 为 key) 方便按 id 查找
	var chapters_arr: Array = data.get("chapters", [])
	_chapters = {}
	for ch in chapters_arr:
		if ch is Dictionary and ch.has("id"):
			_chapters[ch["id"]] = ch

	_clue_defs        = data.get("clues", {})
	_plot_events      = data.get("plot_events", [])
	_clue_events      = data.get("clue_events", [])
	_npc_dialogues    = data.get("npc_dialogues", {})
	_dark_clue_events = data.get("dark_clue_events", [])
	_endings          = data.get("endings", [])
	_day_constants    = data.get("day_constants", { "base_days": 7, "extended_days": 14, "extend_threshold": 5 })

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

	# endings 按 priority 排序 (升序, 低 priority = 高优先级)
	_endings.sort_custom(func(a, b): return int(a.get("priority", 99)) < int(b.get("priority", 99)))

	var frag_count: int = 0
	for cid in _clue_defs:
		if _clue_defs[cid].get("category", "") == FRAGMENT_CATEGORY:
			frag_count += 1
	print("[StoryManager] Loaded: %d chapters, %d clues (%d 前世记忆 + %d 实物), %d plot_events, %d clue_events, %d npc_dialogues, %d endings" % [
		_chapters.size(), _clue_defs.size(), frag_count, _clue_defs.size() - frag_count,
		_plot_events.size(), _clue_events.size(), _npc_dialogues.size(), _endings.size()])

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
	for cid in collected_clues:
		var cat: String = _clue_defs.get(cid, {}).get("category", "未分类")
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
## { "max_day": N }        → GameData.current_day <= N
## { "min_san": N }        → GameData.get_resource("san") >= N
## { "max_san": N }        → GameData.get_resource("san") <= N
## { "min_money": N }      → GameData.get_resource("money") >= N
## { "min_order": N }      → GameData.get_resource("order") >= N (legacy)
## { "min_inspiration": N }→ GameData.get_resource("inspiration") >= N
## { "min_health": N }     → GameData.get_resource("health") >= N
## { "has_item": "key" }   → GameData.has_item(key)
## { "not_item": "key" }   → not GameData.has_item(key)
## { "min_trust": N }      → baiye_trust >= N
## { "max_trust": N }      → baiye_trust <= N
## { "min_fragments": N }  → get_fragment_count() >= N
## { "baiye_available": v }→ is_baiye_available() == v
## { "chapter": "id" }     → current_chapter == id
## { "weather": "type" }   → GameData.current_weather == type
## { "not": {sub} }        → not check_condition(sub)
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

	if cond.has("max_day"):
		return GameData.current_day <= int(cond["max_day"])

	# --- Phase 4: 资源/道具条件扩展 ---
	if cond.has("min_san"):
		return GameData.get_resource("san") >= int(cond["min_san"])

	if cond.has("max_san"):
		return GameData.get_resource("san") <= int(cond["max_san"])

	if cond.has("min_money"):
		return GameData.get_resource("money") >= int(cond["min_money"])

	if cond.has("min_order"):
		return GameData.get_resource("order") >= int(cond["min_order"])

	if cond.has("min_inspiration"):
		return GameData.get_resource("inspiration") >= int(cond["min_inspiration"])

	if cond.has("min_health"):
		return GameData.get_resource("health") >= int(cond["min_health"])

	# --- 白夜 / 碎片 / 章节 / 天气条件 ---
	if cond.has("min_trust"):
		return baiye_trust >= int(cond["min_trust"])

	if cond.has("max_trust"):
		return baiye_trust <= int(cond["max_trust"])

	if cond.has("min_fragments"):
		return get_fragment_count() >= int(cond["min_fragments"])

	if cond.has("baiye_available"):
		var want: bool = cond["baiye_available"]
		if want is bool:
			return is_baiye_available() == want
		return is_baiye_available()

	if cond.has("chapter"):
		return current_chapter == str(cond["chapter"])

	if cond.has("weather"):
		return GameData.current_weather == str(cond["weather"])

	# --- 取反包装器 ---
	if cond.has("not"):
		return not check_condition(cond["not"])

	if cond.has("has_item"):
		return GameData.has_item(str(cond["has_item"]))

	if cond.has("not_item"):
		return not GameData.has_item(str(cond["not_item"]))

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

## 根据当前天数自动推进章节 (day_range 驱动)
func update_chapter_by_day() -> void:
	var day: int = GameData.current_day
	for chapter_id in _chapters:
		var ch: Dictionary = _chapters[chapter_id]
		var dr: Array = ch.get("day_range", [])
		if dr.size() >= 2 and day >= int(dr[0]) and day <= int(dr[1]):
			if chapter_id != current_chapter:
				set_chapter(chapter_id)
			return

func _check_chapter_progression() -> void:
	update_chapter_by_day()

func get_chapter_name() -> String:
	var chapter: Dictionary = _chapters.get(current_chapter, {})
	return chapter.get("name", current_chapter)

func get_chapter_info() -> Dictionary:
	return _chapters.get(current_chapter, {})

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
# 白夜状态管理
# ---------------------------------------------------------------------------

func modify_baiye_trust(delta: int) -> void:
	var old_val: int = baiye_trust
	baiye_trust = clampi(baiye_trust + delta, 0, 10)
	if old_val != baiye_trust:
		baiye_trust_changed.emit(old_val, baiye_trust)

func set_baiye_trust(value: int) -> void:
	var old_val: int = baiye_trust
	baiye_trust = clampi(value, 0, 10)
	if old_val != baiye_trust:
		baiye_trust_changed.emit(old_val, baiye_trust)

func modify_baiye_power(delta: int) -> void:
	baiye_power = clampi(baiye_power + delta, 0, 5)

func is_baiye_available() -> bool:
	return sleep_days_left <= 0

## 触发白夜沉睡 (持续 N 天)
func trigger_baiye_sleep(days: int = 2) -> void:
	sleep_days_left = maxi(days, 1)
	baiye_sleep_started.emit(sleep_days_left)

## 每天调用: 递减沉睡天数
func advance_baiye_sleep() -> void:
	if sleep_days_left > 0:
		sleep_days_left -= 1
		if sleep_days_left <= 0:
			baiye_woke_up.emit()

# ---------------------------------------------------------------------------
# 碎片系统 (alias 层 — 底层统一使用 collected_clues)
# ---------------------------------------------------------------------------

## 收集前世记忆碎片，直接写入 collected_clues（不经过 collect_clue，避免多触发 clue_collected 信号）
func collect_fragment(fragment_id: String) -> bool:
	if fragment_id in collected_clues:
		return false
	collected_clues.append(fragment_id)
	fragment_collected.emit(fragment_id, get_fragment_count())
	return true

func has_fragment(fragment_id: String) -> bool:
	return has_clue(fragment_id)

## 统计已收集的前世记忆碎片数量 (category == FRAGMENT_CATEGORY)
func get_fragment_count() -> int:
	var count: int = 0
	for cid in collected_clues:
		if _clue_defs.get(cid, {}).get("category", "") == FRAGMENT_CATEGORY:
			count += 1
	return count

## 获取碎片定义信息，alias → get_clue_info
func get_fragment_info(fragment_id: String) -> Dictionary:
	return get_clue_info(fragment_id)

## 获取所有前世记忆碎片 (定义 + 是否已收集)，按 order 排序
func get_all_fragments() -> Array:
	var result: Array = []
	for cid in _clue_defs:
		var entry: Dictionary = _clue_defs[cid]
		if entry.get("category", "") == FRAGMENT_CATEGORY:
			result.append({"id": cid, "info": entry, "collected": has_clue(cid)})
	result.sort_custom(func(a, b):
		return a["info"].get("order", 99) < b["info"].get("order", 99))
	return result

# ---------------------------------------------------------------------------
# 动态天数
# ---------------------------------------------------------------------------

## 获取最大天数: 碎片 >= threshold → extended_days, 否则 base_days
func get_max_days() -> int:
	var threshold: int = int(_day_constants.get("extend_threshold", 5))
	if get_fragment_count() >= threshold:
		return int(_day_constants.get("extended_days", 14))
	return int(_day_constants.get("base_days", 7))

# ---------------------------------------------------------------------------
# 应用事件效果
# ---------------------------------------------------------------------------

## 应用事件中的全部效果
## 支持: set_flags, clue_id, baiye_trust_change, trigger_sleep, fragment_id,
##       baiye_power_change, resource_effects
## 返回 { "clue_name", "is_new_clue", "fragment_name", "is_new_fragment" }
func apply_event_effects(event: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"clue_name": "",
		"is_new_clue": false,
		"fragment_name": "",
		"is_new_fragment": false,
	}

	# 设置 flag
	var set_flags = event.get("set_flags", {})
	if set_flags is Dictionary:
		for key in set_flags:
			if key == "current_chapter":
				set_chapter(str(set_flags[key]))
			else:
				set_flag(key, set_flags[key])
	elif set_flags is Array:
		# 支持数组形式: ["flag_a", "flag_b"]
		for f in set_flags:
			set_flag(str(f), true)

	# 收集线索
	var clue_id = event.get("clue_id")
	if clue_id != null and str(clue_id) != "":
		var is_new: bool = collect_clue(str(clue_id))
		var info: Dictionary = get_clue_info(str(clue_id))
		result["clue_name"] = info.get("name", clue_id)
		result["is_new_clue"] = is_new

	# 白夜信任度变化
	var trust_change = event.get("baiye_trust_change")
	if trust_change != null:
		modify_baiye_trust(int(trust_change))

	# 白夜力量变化
	var power_change = event.get("baiye_power_change")
	if power_change != null:
		modify_baiye_power(int(power_change))

	# 触发白夜沉睡
	var sleep = event.get("trigger_sleep")
	if sleep != null:
		var days: int = int(sleep) if sleep is float or sleep is int else 2
		trigger_baiye_sleep(days)

	# 收集碎片
	var fragment_id = event.get("fragment_id")
	if fragment_id != null and str(fragment_id) != "":
		var is_new: bool = collect_fragment(str(fragment_id))
		var info: Dictionary = get_fragment_info(str(fragment_id))
		result["fragment_name"] = info.get("name", fragment_id)
		result["is_new_fragment"] = is_new

	# 资源效果 (choice_effects 中的 effects 字典)
	var res_effects: Dictionary = event.get("effects", {})
	if not res_effects.is_empty():
		GameData.apply_effects(res_effects)

	return result

## 应用选择效果 (story_events.json 的 choice_effects)
## choice_effect 结构与 event 类似, 直接复用 apply_event_effects
func apply_choice_effects(choice_effect: Dictionary) -> Dictionary:
	return apply_event_effects(choice_effect)

# ---------------------------------------------------------------------------
# 生命周期
# ---------------------------------------------------------------------------

func reset() -> void:
	flags.clear()
	collected_clues.clear()
	current_chapter = "awakening"
	baiye_trust = 0
	baiye_power = 0
	sleep_days_left = 0

## 存档
func save_state() -> Dictionary:
	return {
		"flags": flags.duplicate(),
		"collected_clues": collected_clues.duplicate(),
		"current_chapter": current_chapter,
		"baiye_trust": baiye_trust,
		"baiye_power": baiye_power,
		"sleep_days_left": sleep_days_left,
	}

## 读档 (兼容旧存档: 将 collected_fragments dict 的 key 合并入 collected_clues)
func load_state(data: Dictionary) -> void:
	flags = data.get("flags", {}).duplicate()
	collected_clues = data.get("collected_clues", []).duplicate()
	# 旧存档迁移：collected_fragments 是 dict，将其 key 追加到 collected_clues
	var old_frags: Dictionary = data.get("collected_fragments", {})
	for fid in old_frags:
		if not (fid in collected_clues):
			collected_clues.append(fid)
	current_chapter = data.get("current_chapter", "awakening")
	baiye_trust = int(data.get("baiye_trust", 0))
	baiye_power = int(data.get("baiye_power", 0))
	sleep_days_left = int(data.get("sleep_days_left", 0))
