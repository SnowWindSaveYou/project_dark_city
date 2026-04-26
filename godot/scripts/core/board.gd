## Board - 棋盘管理器
## 对应原版 Board.lua
## 管理 5×5 卡牌网格的生成、布局和查询
class_name Board
extends RefCounted

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const ROWS := 5
const COLS := 5
const GAP := 0.12  # 卡牌间隔 (米)

## 牌堆位置 (3D 世界坐标)
const DECK_POS := Vector3(3.0, 0.0, -1.5)

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var cards: Array = []  # 2D 数组 cards[row][col] → Card (1-based index via helper)
var token_row: int = 3
var token_col: int = 3

## 外部注入的必选地点 (日程系统要求出现在棋盘上)
var required_locations: Array = []

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _init() -> void:
	clear()

func clear() -> void:
	cards = []
	for r in range(ROWS):
		var row_arr: Array = []
		for _c in range(COLS):
			row_arr.append(null)
		cards.append(row_arr)
	token_row = 3
	token_col = 3

# ---------------------------------------------------------------------------
# 卡牌访问 (1-based 外部接口, 内部 0-based)
# ---------------------------------------------------------------------------

func get_card(row: int, col: int) -> Card:
	if row < 1 or row > ROWS or col < 1 or col > COLS:
		return null
	return cards[row - 1][col - 1]

func set_card(row: int, col: int, card: Card) -> void:
	if row >= 1 and row <= ROWS and col >= 1 and col <= COLS:
		cards[row - 1][col - 1] = card

# ---------------------------------------------------------------------------
# 卡牌生成
# ---------------------------------------------------------------------------

func generate_cards() -> void:
	clear()

	# 1. 分配特殊位置
	var special_positions := {}  # Vector2i → { location, type }

	# 家 - 固定中心 (3,3)
	special_positions[Vector2i(3, 3)] = { "location": "home", "type": "home" }

	# 商店 - 随机一个非中心格子
	var shop_pos := _random_empty_pos(special_positions)
	special_positions[shop_pos] = { "location": "shop", "type": "shop" }

	# 地标 - 3 个
	var landmarks := Card.LANDMARK_LOCATIONS.duplicate()
	landmarks.shuffle()
	for i in range(3):
		var pos := _random_empty_pos(special_positions)
		special_positions[pos] = { "location": landmarks[i], "type": "landmark" }

	# 2. 收集可用普通地点
	var available_locations := Card.REGULAR_LOCATIONS.duplicate()

	# 确保必选地点在可用列表前端
	for loc in required_locations:
		if loc in available_locations:
			available_locations.erase(loc)
			available_locations.push_front(loc)

	# 3. 生成剩余卡牌
	var loc_index := 0
	for r in range(1, ROWS + 1):
		for c in range(1, COLS + 1):
			var pos := Vector2i(r, c)
			if pos in special_positions:
				var info: Dictionary = special_positions[pos]
				set_card(r, c, Card.create(info["location"], info["type"], r, c))
			else:
				# 随机地点 (循环使用)
				var loc: String = available_locations[loc_index % available_locations.size()]
				loc_index += 1
				# 加权随机事件
				var evt: String = _weighted_random_event()
				set_card(r, c, Card.create(loc, evt, r, c))

	# 4. 地标光环: 净化相邻的 monster/trap → safe
	_apply_landmark_aura()

## 加权随机事件
func _weighted_random_event() -> String:
	var total := 0
	for w in Card.EVENT_WEIGHTS.values():
		total += w
	var roll := randi() % total
	var cumulative := 0
	for evt_type in Card.EVENT_WEIGHTS:
		cumulative += Card.EVENT_WEIGHTS[evt_type]
		if roll < cumulative:
			return evt_type
	return "safe"

## 随机选取空位
func _random_empty_pos(occupied: Dictionary) -> Vector2i:
	var attempts := 0
	while attempts < 100:
		var r := randi_range(1, ROWS)
		var c := randi_range(1, COLS)
		var pos := Vector2i(r, c)
		if pos not in occupied:
			return pos
		attempts += 1
	# fallback
	return Vector2i(1, 1)

## 地标光环
func _apply_landmark_aura() -> void:
	for r in range(1, ROWS + 1):
		for c in range(1, COLS + 1):
			var card := get_card(r, c)
			if card == null:
				continue
			if not card.is_landmark():
				continue
			# 检查四方向相邻
			var neighbors := [
				Vector2i(r - 1, c), Vector2i(r + 1, c),
				Vector2i(r, c - 1), Vector2i(r, c + 1),
			]
			for nb in neighbors:
				var nb_card := get_card(nb.x, nb.y)
				if nb_card and (nb_card.type == "monster" or nb_card.type == "trap"):
					nb_card.type = "safe"

# ---------------------------------------------------------------------------
# 螺旋发牌顺序
# ---------------------------------------------------------------------------

## 返回螺旋序的 (row, col) 数组 (1-based)
func get_spiral_order() -> Array:
	var result: Array = []
	var top := 0
	var bottom := ROWS - 1
	var left := 0
	var right := COLS - 1

	while top <= bottom and left <= right:
		# 上行 →
		for c in range(left, right + 1):
			result.append(Vector2i(top + 1, c + 1))
		top += 1
		# 右列 ↓
		for r in range(top, bottom + 1):
			result.append(Vector2i(r + 1, right + 1))
		right -= 1
		# 下行 ←
		if top <= bottom:
			for c in range(right, left - 1, -1):
				result.append(Vector2i(bottom + 1, c + 1))
			bottom -= 1
		# 左列 ↑
		if left <= right:
			for r in range(bottom, top - 1, -1):
				result.append(Vector2i(r + 1, left + 1))
			left += 1

	return result

# ---------------------------------------------------------------------------
# 位置计算
# ---------------------------------------------------------------------------

## 棋盘格子 (row, col) → 3D 世界坐标
func grid_to_world(row: int, col: int) -> Vector3:
	var total_w: float = COLS * Card.CARD_W + (COLS - 1) * GAP
	var total_h: float = ROWS * Card.CARD_H + (ROWS - 1) * GAP
	var start_x: float = -total_w / 2.0 + Card.CARD_W / 2.0
	var start_z: float = -total_h / 2.0 + Card.CARD_H / 2.0
	var x: float = start_x + (col - 1) * (Card.CARD_W + GAP)
	var z: float = start_z + (row - 1) * (Card.CARD_H + GAP)
	return Vector3(x, 0, z)

# ---------------------------------------------------------------------------
# 移动与邻接
# ---------------------------------------------------------------------------

## 检查 (r2, c2) 是否是 (r1, c1) 的相邻格 (上下左右)
func is_adjacent(r1: int, c1: int, r2: int, c2: int) -> bool:
	return (absi(r1 - r2) + absi(c1 - c2)) == 1

## 获取所有未翻开的卡
func get_unflipped_cards() -> Array:
	var result: Array = []
	for r in range(1, ROWS + 1):
		for c in range(1, COLS + 1):
			var card := get_card(r, c)
			if card and not card.is_flipped:
				result.append(card)
	return result

## 获取所有已翻开的指定类型卡
func get_flipped_cards_of_type(type_key: String) -> Array:
	var result: Array = []
	for r in range(1, ROWS + 1):
		for c in range(1, COLS + 1):
			var card := get_card(r, c)
			if card and card.is_flipped and card.type == type_key:
				result.append(card)
	return result

## 总卡牌数
func total_cards() -> int:
	return ROWS * COLS

## 家的位置 (固定中心 3,3)
var home_row: int = 3
var home_col: int = 3

## 翻开卡牌
func flip_card(row: int, col: int) -> void:
	var card := get_card(row, col)
	if card:
		card.is_flipped = true

## 翻回卡牌 (拍照模式用)
func flip_back(row: int, col: int) -> void:
	var card := get_card(row, col)
	if card:
		card.is_flipped = false

## 检查 (row,col) 是否在某个地标的光环范围内
func is_in_landmark_aura(row: int, col: int) -> bool:
	var neighbors := [
		Vector2i(row - 1, col), Vector2i(row + 1, col),
		Vector2i(row, col - 1), Vector2i(row, col + 1),
	]
	for nb in neighbors:
		var nb_card := get_card(nb.x, nb.y)
		if nb_card and nb_card.is_landmark():
			return true
	return false
