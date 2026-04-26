## CardManager - 日程与传闻管理器
## 对应原版 CardManager.lua
class_name CardManager
extends RefCounted

# ---------------------------------------------------------------------------
# 日程模板
# ---------------------------------------------------------------------------
const SCHEDULE_TEMPLATES := {
	"company":    { "verb": "拍摄公司照片", "reward": { "money": 10 } },
	"park":       { "verb": "在公园取景",   "reward": { "san": 1 } },
	"hospital":   { "verb": "调查医院档案", "reward": { "money": 8 } },
	"school":     { "verb": "记录学校传闻", "reward": { "order": 1 } },
	"station":    { "verb": "追踪车站线索", "reward": { "money": 12 } },
	"market":     { "verb": "拍摄商场橱窗", "reward": { "money": 8 } },
	"shrine":     { "verb": "参拜神社",     "reward": { "san": 2 } },
	"alley":      { "verb": "探索巷子深处", "reward": { "money": 15 } },
	"lighthouse": { "verb": "登上灯塔瞭望", "reward": { "order": 2, "san": 1 } },
	"library":    { "verb": "查阅图书馆文献", "reward": { "order": 1 } },
	"temple":     { "verb": "在教堂祈祷",   "reward": { "san": 2 } },
	"home":       { "verb": "回家整理笔记", "reward": { "san": 1, "order": 1 } },
}

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------

## 当天日程列表
## 每个元素: { "location": "park", "verb": "在公园取景", "reward": { "san": 1 }, "status": "pending" }
var schedules: Array = []

## 传闻列表
## 每个元素: { "type": "safe"|"danger", "text": "..." }
var rumors: Array = []

## 延期日程 (留到下一天)
var _deferred_schedules: Array = []

# ---------------------------------------------------------------------------
# 每日生成
# ---------------------------------------------------------------------------

## 生成今日日程和传闻
func generate_daily(_day_count: int) -> void:
	schedules = []
	rumors = []

	# 追加昨日延期日程
	for deferred in _deferred_schedules:
		deferred["status"] = "pending"
		schedules.append(deferred)
	_deferred_schedules = []

	# 已用地点 (避免重复)
	var used_locations: Array = []
	for s in schedules:
		used_locations.append(s["location"])

	# 随机 3 个新日程
	var available := SCHEDULE_TEMPLATES.keys().duplicate()
	available.shuffle()
	var added := 0
	for loc in available:
		if added >= 3:
			break
		if loc in used_locations:
			continue
		var tmpl: Dictionary = SCHEDULE_TEMPLATES[loc]
		schedules.append({
			"location": loc,
			"verb": tmpl["verb"],
			"reward": tmpl["reward"].duplicate(),
			"status": "pending",
		})
		used_locations.append(loc)
		added += 1

	# 生成 1 条传闻 (占位，实际内容由棋盘生成后补充)
	# 具体逻辑在 Board 生成后由 main 调用 add_rumor()

## 获取日程需要的地点 (注入棋盘生成)
func pre_select_locations() -> Array:
	var locations: Array = []
	for s in schedules:
		if s["location"] not in Card.LANDMARK_LOCATIONS \
			and s["location"] != "home" \
			and s["location"] != "shop":
			locations.append(s["location"])
	return locations

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

## 根据棋盘数据生成初始传闻
func generate_rumor_from_board(board: Board) -> void:
	# 随机挑一个安全或危险的地点作为提示
	var safe_cards: Array = []
	var danger_cards: Array = []
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card := board.get_card(r, c)
			if card == null or card.type in ["home", "shop", "landmark"]:
				continue
			if card.type == "safe":
				safe_cards.append(card)
			elif card.type in ["monster", "trap"]:
				danger_cards.append(card)

	if randf() < 0.5 and safe_cards.size() > 0:
		var card: Card = safe_cards[randi() % safe_cards.size()]
		var loc_info := card.get_location_info()
		add_rumor("safe", "📍 听说 " + loc_info["label"] + " 附近还算安全")
	elif danger_cards.size() > 0:
		var card: Card = danger_cards[randi() % danger_cards.size()]
		var loc_info := card.get_location_info()
		add_rumor("danger", "⚠️ 有人说 " + loc_info["label"] + " 附近有不好的东西")

# ---------------------------------------------------------------------------
# 日终结算
# ---------------------------------------------------------------------------

## 结算当天日程，返回结算结果
## 返回: { "completed": [...], "deferred": [...], "pending_penalty": int }
func settle_day() -> Dictionary:
	var result := {
		"completed": [],
		"deferred": [],
		"pending_penalty": 0,
	}

	_deferred_schedules = []

	for s in schedules:
		match s["status"]:
			"completed":
				result["completed"].append(s)
			"deferred":
				result["deferred"].append(s)
				_deferred_schedules.append(s.duplicate())
			"pending":
				result["pending_penalty"] += 1

	return result

# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func get_pending_count() -> int:
	var count := 0
	for s in schedules:
		if s["status"] == "pending":
			count += 1
	return count

func get_completed_count() -> int:
	var count := 0
	for s in schedules:
		if s["status"] == "completed":
			count += 1
	return count
