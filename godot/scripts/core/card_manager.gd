## CardManager - 日程与传闻管理器
## 对应原版 CardManager.lua
class_name CardManager
extends RefCounted

# ---------------------------------------------------------------------------
# 数据表从 CardConfig autoload 读取 (schedule_templates, rumor_*_texts)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------

## 当天日程列表
## 每个元素: { "location": "park", "verb": "在公园取景", "reward": { "san": 1 }, "status": "pending" }
var schedules: Array = []

## 传闻列表
## 每个元素: { "type": "safe"|"danger", "text": "..." }
var rumors: Array = []

## 延期日程 (留到下一天, 最多 1 张)
var _deferred_schedules: Array = []

## 预选地点缓存
var _pre_selected: Array = []

# ---------------------------------------------------------------------------
# 每日生成
# ---------------------------------------------------------------------------

## 生成今日日程和传闻 (在 Board.generate_cards 之后调用)
func generate_daily(_board: Board) -> void:
	schedules = []
	rumors = []

	# 加入前一天推迟的日程 (最多 1 张, 其地点已在预选列表中)
	var deferred_count: int = 0
	if _deferred_schedules.size() > 0:
		var ds: Dictionary = _deferred_schedules[0].duplicate()
		ds["status"] = "pending"
		schedules.append(ds)
		deferred_count = 1
	_deferred_schedules = []

	# 从预选地点中生成剩余日程卡
	var max_schedules: int = 3 + deferred_count
	var used_locations: Dictionary = {}
	for s in schedules:
		used_locations[s["location"]] = true

	for loc in _pre_selected:
		if schedules.size() >= max_schedules:
			break
		if not used_locations.has(loc) and CardConfig.schedule_templates.has(loc):
			var tmpl: Dictionary = CardConfig.schedule_templates[loc]
			var loc_info: Dictionary = CardConfig.location_info.get(loc, {})
			schedules.append({
				"location": loc,
				"verb": tmpl["verb"],
				"icon": loc_info.get("icon", "📋"),
				"reward": tmpl["reward"].duplicate(),
				"status": "pending",
			})
			used_locations[loc] = true

	# 清空预选缓存
	_pre_selected = []

	# 传闻由 main 在棋盘生成后调用 generate_rumor_from_board() 补充

## 预选今天日程所需的地点 (在 Board.generate_cards 之前调用)
## 返回地点列表，Board 需保证这些地点出现在棋盘上
func pre_select_locations() -> Array:
	# 排除地标和商店 (它们有专用格子)
	var exclude_set: Dictionary = { "convenience": true }
	for lm_loc in Card.LANDMARK_LOCATIONS:
		exclude_set[lm_loc] = true

	var all_locs: Array = []
	for loc in CardConfig.schedule_templates.keys():
		if not exclude_set.has(loc):
			all_locs.append(loc)
	all_locs.shuffle()

	var required: Array = []
	var used: Dictionary = {}

	# 昨天推迟的日程地点
	if _deferred_schedules.size() > 0:
		var def_loc: String = _deferred_schedules[0]["location"]
		required.append(def_loc)
		used[def_loc] = true

	# 选 3 个新地点
	var needed: int = 3
	for loc in all_locs:
		if needed <= 0:
			break
		if not used.has(loc):
			required.append(loc)
			used[loc] = true
			needed -= 1

	# 缓存预选结果
	_pre_selected = required
	return required

# ---------------------------------------------------------------------------
# 日程交互
# ---------------------------------------------------------------------------

## 标记日程完成 (玩家到达目标地点)
func complete_schedule_at(location: String) -> Dictionary:
	for s in schedules:
		if s["location"] == location and s["status"] == "pending":
			s["status"] = "completed"
			return s
	return {}

## 切换延期状态
func toggle_defer(index: int) -> void:
	if index < 0 or index >= schedules.size():
		return
	var s: Dictionary = schedules[index]
	if s["status"] == "completed":
		return  # 已完成不可延期
	s["status"] = "deferred" if s["status"] == "pending" else "pending"

# ---------------------------------------------------------------------------
# 传闻
# ---------------------------------------------------------------------------

## 添加传闻
func add_rumor(rumor_type: String, text: String) -> void:
	rumors.append({ "type": rumor_type, "text": text })

## 根据棋盘数据生成初始传闻 (1 条)
func generate_rumor_from_board(board: Board) -> void:
	var candidates: Array = []
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = board.get_card(r, c)
			if card == null or card.location == "home":
				continue
			if not card.is_flipped:
				candidates.append(card)
	candidates.shuffle()

	for card in candidates:
		var is_safe: bool = card.type in ["safe", "reward", "plot", "clue", "landmark"]
		var loc_info: Dictionary = card.get_location_info()
		var label: String = loc_info.get("label", "未知")
		var templates: Array = CardConfig.rumor_safe_texts if is_safe else CardConfig.rumor_danger_texts
		var text: String = templates[randi() % templates.size()] % label
		rumors.append({
			"location": card.location,
			"label": label,
			"icon": loc_info.get("icon", "📋"),
			"is_safe": is_safe,
			"text": text,
		})
		break  # 只生成 1 条

## 从棋盘中添加额外传闻 (线索事件触发)
func add_rumor_from_board(board: Board) -> bool:
	# 已有传闻的地点集合
	var covered: Dictionary = {}
	for r in rumors:
		covered[r["location"]] = true

	var candidates: Array = []
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = board.get_card(r, c)
			if card and card.location != "home" \
					and not card.is_flipped and not covered.has(card.location):
				candidates.append(card)
	if candidates.is_empty():
		return false

	var pick: Card = candidates[randi() % candidates.size()]
	var is_safe: bool = pick.type in ["safe", "reward", "plot", "clue", "landmark"]
	var loc_info: Dictionary = pick.get_location_info()
	var label: String = loc_info.get("label", "未知")
	var templates: Array = CardConfig.rumor_safe_texts if is_safe else CardConfig.rumor_danger_texts
	var text: String = templates[randi() % templates.size()] % label
	rumors.append({
		"location": pick.location,
		"label": label,
		"icon": loc_info.get("icon", "📋"),
		"is_safe": is_safe,
		"text": text,
	})
	return true

## 查询指定地点是否有传闻
func get_rumor_for(location: String) -> Dictionary:
	for r in rumors:
		if r["location"] == location:
			return r
	return {}

# ---------------------------------------------------------------------------
# 日终结算
# ---------------------------------------------------------------------------

## 结算日程卡，返回资源变化列表 [[resKey, delta], ...]
func settle_day() -> Array:
	var effects: Array = []
	_deferred_schedules = []

	for s in schedules:
		match s["status"]:
			"completed":
				# 完成: 发奖励
				var reward: Array = s["reward"]
				effects.append([reward[0], reward[1]])
			"deferred":
				# 推迟: 累积到明天 (最多 1 张)
				if _deferred_schedules.size() == 0:
					_deferred_schedules.append(s.duplicate())
			_:
				# 未完成且未推迟: 扣秩序值 -3
				effects.append(["order", -3])

	# 清空传闻 (仅当天有效)
	rumors = []
	return effects

# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func get_pending_count() -> int:
	var count: int = 0
	for s in schedules:
		if s["status"] == "pending":
			count += 1
	return count

func get_completed_count() -> int:
	var count: int = 0
	for s in schedules:
		if s["status"] == "completed":
			count += 1
	return count

## 获取日程完成统计 → [completed, total]
func get_progress() -> Array:
	var completed: int = 0
	var total: int = schedules.size()
	for s in schedules:
		if s["status"] == "completed":
			completed += 1
	return [completed, total]

## 重置所有状态 (新游戏)
func reset() -> void:
	schedules = []
	rumors = []
	_deferred_schedules = []
	_pre_selected = []
