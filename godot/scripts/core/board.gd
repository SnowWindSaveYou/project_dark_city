## Board - 棋盘管理器
## 对应原版 Board.lua
## 管理 5×5 卡牌网格的生成、布局和查询
class_name Board
extends RefCounted

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const ROWS: int = 5
const COLS: int = 5
const GAP: float = 0.12  # 卡牌间隔 (米)

## 牌堆位置 (3D 世界坐标)
const DECK_POS: Vector3 = Vector3(3.0, 0.0, -1.5)

## 陷阱子类型权重 (生成时随机分配)
const TRAP_SUBTYPE_WEIGHTS: Array = [
	["sanity",   30],  # 阴气侵蚀: san -1
	["money",    30],  # 财物散失: money -10
	["film",     20],  # 灵雾曝光: film -1
	["teleport", 20],  # 空间错位: 随机传送到未翻开格子
]

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

	var used_positions: Array = []  # Array of [row, col]

	# 1. 家 - 随机位置
	var home_positions: Array = _random_positions(1, [])
	home_row = home_positions[0][0]
	home_col = home_positions[0][1]
	used_positions.append([home_row, home_col])

	# 2. 地标 - 1~2 个
	var landmark_count: int = randi_range(1, 2)
	var landmark_positions: Array = _random_positions(landmark_count, used_positions)
	for pos in landmark_positions:
		used_positions.append(pos)

	# 3. 商店 - 1 个
	var shop_positions: Array = _random_positions(1, used_positions)
	for pos in shop_positions:
		used_positions.append(pos)

	# 3.5 裂隙 (暗面世界入口, 每张棋盘 1 个)
	var rift_positions: Array = _random_positions(1, used_positions)
	for pos in rift_positions:
		used_positions.append(pos)

	# 4. 地点池 (普通格子 + 裂隙也消耗池条目)
	var rift_count: int = rift_positions.size()
	var normal_slots: int = ROWS * COLS - used_positions.size() + rift_count
	var location_pool: Array = []
	var used_in_pool: Dictionary = {}

	# 地标和商店地点不应出现在普通格子
	var special_loc_set: Dictionary = { "home": true, "convenience": true }
	for lm_loc in Card.LANDMARK_LOCATIONS:
		special_loc_set[lm_loc] = true

	# 优先放入必选地点
	for loc in required_locations:
		if not used_in_pool.has(loc) and not special_loc_set.has(loc):
			location_pool.append(loc)
			used_in_pool[loc] = true

	# 回填：从 REGULAR_LOCATIONS 中选择未使用的地点
	var fill_candidates: Array = []
	for loc in Card.REGULAR_LOCATIONS:
		if not used_in_pool.has(loc):
			fill_candidates.append(loc)
	fill_candidates.shuffle()
	var fill_idx: int = 0

	while location_pool.size() < normal_slots:
		if fill_idx < fill_candidates.size():
			location_pool.append(fill_candidates[fill_idx])
			fill_idx += 1
		else:
			location_pool.append(Card.REGULAR_LOCATIONS[randi() % Card.REGULAR_LOCATIONS.size()])
	location_pool.shuffle()
	var loc_idx: int = 0

	# 5. 特殊位置映射
	var special_map: Dictionary = {}
	special_map["%d,%d" % [home_row, home_col]] = "home"
	for pos in landmark_positions:
		special_map["%d,%d" % [pos[0], pos[1]]] = "landmark"
	for pos in shop_positions:
		special_map["%d,%d" % [pos[0], pos[1]]] = "shop"
	for pos in rift_positions:
		special_map["%d,%d" % [pos[0], pos[1]]] = "rift"

	# 地标地点随机分配
	var landmark_locs: Array = Card.LANDMARK_LOCATIONS.duplicate()
	landmark_locs.shuffle()
	var lm_loc_idx: int = 0

	# 6. 填充棋盘
	for row in range(1, ROWS + 1):
		for col in range(1, COLS + 1):
			var key: String = "%d,%d" % [row, col]
			var special: String = special_map.get(key, "")
			var card_type: String
			var location: String

			if special == "home":
				card_type = "home"
				location = "home"
			elif special == "landmark":
				card_type = "landmark"
				location = landmark_locs[lm_loc_idx] if lm_loc_idx < landmark_locs.size() else "church"
				lm_loc_idx += 1
			elif special == "shop":
				card_type = "shop"
				location = "convenience"
			elif special == "rift":
				# 裂隙伪装成普通事件卡，用 has_rift 标记
				card_type = _weighted_random_event()
				if loc_idx < len(location_pool):
					location = location_pool[loc_idx]
					loc_idx += 1
				else:
					location = Card.REGULAR_LOCATIONS[randi() % Card.REGULAR_LOCATIONS.size()]
			else:
				if loc_idx >= len(location_pool):
					# 安全回退: 池耗尽时随机选地点
					location = Card.REGULAR_LOCATIONS[randi() % Card.REGULAR_LOCATIONS.size()]
				else:
					location = location_pool[loc_idx]
					loc_idx += 1
				card_type = _weighted_random_event()

			var card: Card = Card.create(location, card_type, row, col)
			# 陷阱子类型 (仅 trap 类型有)
			if card_type == "trap":
				card.trap_subtype = Board.random_trap_subtype()
			# 裂隙标记 (伪装成普通卡, 翻开后才知道有裂隙)
			if special == "rift":
				card.has_rift = true
			set_card(row, col, card)

	# 7. 地标光环: 净化相邻的 monster/trap → safe
	_apply_landmark_aura()

## 根据权重随机选取陷阱子类型
## TRAP_SUBTYPE_WEIGHTS: [[name, weight], ...] → w[0]=name, w[1]=weight
static func random_trap_subtype() -> String:
	var total: int = 0
	for w in TRAP_SUBTYPE_WEIGHTS:
		total += int(w[1])
	var roll: int = randi_range(1, total)
	var acc: int = 0
	for w in TRAP_SUBTYPE_WEIGHTS:
		acc += int(w[1])
		if roll <= acc:
			return str(w[0])
	return "sanity"

## 加权随机事件
func _weighted_random_event() -> String:
	var total: int = 0
	for w in Card.EVENT_WEIGHTS.values():
		total += w
	var roll: int = randi() % total
	var cumulative: int = 0
	for evt_type in Card.EVENT_WEIGHTS:
		cumulative += Card.EVENT_WEIGHTS[evt_type]
		if roll < cumulative:
			return evt_type
	return "safe"

## 随机取 count 个不重复位置 (排除 exclude 中的 [row,col])
func _random_positions(count: int, exclude: Array) -> Array:
	var positions: Array = []
	for r in range(1, ROWS + 1):
		for c in range(1, COLS + 1):
			var skip: bool = false
			for ex in exclude:
				if ex[0] == r and ex[1] == c:
					skip = true
					break
			if not skip:
				positions.append([r, c])
	positions.shuffle()
	return positions.slice(0, count)

## 地标光环
func _apply_landmark_aura() -> void:
	for r in range(1, ROWS + 1):
		for c in range(1, COLS + 1):
			var card: Card = get_card(r, c)
			if card == null:
				continue
			if not card.is_landmark():
				continue
			# 检查四方向相邻
			var neighbors: Array = [
				Vector2i(r - 1, c), Vector2i(r + 1, c),
				Vector2i(r, c - 1), Vector2i(r, c + 1),
			]
			for nb in neighbors:
				var nb_card: Card = get_card(nb.x, nb.y)
				if nb_card and (nb_card.type == "monster" or nb_card.type == "trap"):
					nb_card.type = "safe"

# ---------------------------------------------------------------------------
# 螺旋发牌顺序
# ---------------------------------------------------------------------------

## 返回螺旋序的 (row, col) 数组 (1-based)
func get_spiral_order() -> Array:
	var result: Array = []
	var top: int = 0
	var bottom: int = ROWS - 1
	var left: int = 0
	var right: int = COLS - 1

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
			var card: Card = get_card(r, c)
			if card and not card.is_flipped:
				result.append(card)
	return result

## 获取所有已翻开的指定类型卡
func get_flipped_cards_of_type(type_key: String) -> Array:
	var result: Array = []
	for r in range(1, ROWS + 1):
		for c in range(1, COLS + 1):
			var card: Card = get_card(r, c)
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
	var card: Card = get_card(row, col)
	if card:
		card.is_flipped = true

## 翻回卡牌 (拍照模式用)
func flip_back(row: int, col: int) -> void:
	var card: Card = get_card(row, col)
	if card:
		card.is_flipped = false

## 检查 (row,col) 是否在某个地标的光环范围内
func is_in_landmark_aura(row: int, col: int) -> bool:
	var neighbors: Array = [
		Vector2i(row - 1, col), Vector2i(row + 1, col),
		Vector2i(row, col - 1), Vector2i(row, col + 1),
	]
	for nb in neighbors:
		var nb_card: Card = get_card(nb.x, nb.y)
		if nb_card and nb_card.is_landmark():
			return true
	return false

# ---------------------------------------------------------------------------
# 暗面世界地图生成
# ---------------------------------------------------------------------------

## 暗面世界墙壁放置 + BFS 连通性检查
## 返回 2D bool 数组 is_wall[row-1][col-1]
static func generate_dark_walls(wall_count: int) -> Array:
	var is_wall: Array = []
	for r in range(ROWS):
		var row_arr: Array = []
		for _c in range(COLS):
			row_arr.append(false)
		is_wall.append(row_arr)

	# 所有位置随机排列
	var all_pos: Array = []
	for r in range(1, ROWS + 1):
		for c in range(1, COLS + 1):
			all_pos.append(Vector2i(r, c))
	all_pos.shuffle()

	var walls_placed: int = 0
	for pos in all_pos:
		if walls_placed >= wall_count:
			break
		var r: int = pos.x
		var c: int = pos.y
		# 中心保护 (入口)
		if r == 3 and c == 3:
			continue
		# 尝试放墙
		is_wall[r - 1][c - 1] = true
		# BFS 连通性检查: 从中心(3,3)出发
		var visited: Dictionary = {}
		var queue: Array = [Vector2i(3, 3)]
		visited[Vector2i(3, 3)] = true
		var head: int = 0
		while head < queue.size():
			var cur: Vector2i = queue[head]
			head += 1
			var dirs: Array = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
			for d in dirs:
				var nr: int = cur.x + d.x
				var nc: int = cur.y + d.y
				var npos: Vector2i = Vector2i(nr, nc)
				if nr >= 1 and nr <= ROWS and nc >= 1 and nc <= COLS \
						and not is_wall[nr - 1][nc - 1] and not visited.has(npos):
					visited[npos] = true
					queue.append(npos)
		# 检查所有非墙格子都能到达
		var all_reachable: bool = true
		for r2 in range(1, ROWS + 1):
			for c2 in range(1, COLS + 1):
				if not is_wall[r2 - 1][c2 - 1] and not visited.has(Vector2i(r2, c2)):
					all_reachable = false
					break
			if not all_reachable:
				break
		if all_reachable:
			walls_placed += 1
		else:
			is_wall[r - 1][c - 1] = false  # 回退
	return is_wall

## 生成暗面世界卡牌 (复用 5×5 网格)
## layer_data: { walkable, entry_row, entry_col, collected }
## dark_locations: { normal: [...], shop: [...], intel: [...], clue: [...], item: [...] }
## dark_config: { wall_count, layer_idx, passage_count, has_abyss_core, shop_count, ... }
func generate_dark_cards(layer_data: Dictionary, dark_locations: Dictionary, dark_config: Dictionary) -> void:
	clear()
	var layer_idx: int = dark_config.get("layer_idx", 1)

	# 1. 生成墙壁
	var wall_count: int = dark_config.get("wall_count", 5)
	var is_wall: Array = Board.generate_dark_walls(wall_count)

	# 2. 收集可通行位置
	var walkable_positions: Array = []
	var walkable: Array = []
	for r in range(ROWS):
		var row_walk: Array = []
		for c in range(COLS):
			if is_wall[r][c]:
				row_walk.append(false)
			else:
				row_walk.append(true)
				walkable_positions.append([r + 1, c + 1])
		walkable.append(row_walk)
	walkable_positions.shuffle()

	layer_data["walkable"] = walkable
	layer_data["entry_row"] = 3
	layer_data["entry_col"] = 3

	# 3. 分配暗面卡牌类型
	var assigned: Dictionary = {}
	assigned["3,3"] = "normal"  # 入口

	# 层间通道
	var passage_count: int = dark_config.get("passage_count", 0)
	var pass_placed: int = 0
	for pos in walkable_positions:
		if pass_placed >= passage_count:
			break
		var key: String = "%d,%d" % [pos[0], pos[1]]
		if not assigned.has(key) and not (pos[0] == 3 and pos[1] == 3):
			assigned[key] = "passage"
			pass_placed += 1

	# 深渊核心 (仅 L3)
	if dark_config.get("has_abyss_core", false):
		for pos in walkable_positions:
			var key: String = "%d,%d" % [pos[0], pos[1]]
			if not assigned.has(key) and not (pos[0] == 3 and pos[1] == 3):
				assigned[key] = "abyss_core"
				break

	# 商店
	var shop_count: int = dark_config.get("shop_count", 0)
	var shop_placed: int = 0
	for pos in walkable_positions:
		if shop_placed >= shop_count:
			break
		var key: String = "%d,%d" % [pos[0], pos[1]]
		if not assigned.has(key):
			assigned[key] = "shop"
			shop_placed += 1

	# 情报点
	var intel_count: int = dark_config.get("intel_count", 0)
	var intel_placed: int = 0
	for pos in walkable_positions:
		if intel_placed >= intel_count:
			break
		var key: String = "%d,%d" % [pos[0], pos[1]]
		if not assigned.has(key):
			assigned[key] = "intel"
			intel_placed += 1

	# 关卡
	var check_count: int = dark_config.get("checkpoint_count", 0)
	var check_placed: int = 0
	for pos in walkable_positions:
		if check_placed >= check_count:
			break
		var key: String = "%d,%d" % [pos[0], pos[1]]
		if not assigned.has(key):
			assigned[key] = "checkpoint"
			check_placed += 1

	# 线索
	var clue_count: int = dark_config.get("clue_count", randi_range(3, 5))
	var clue_placed: int = 0
	for pos in walkable_positions:
		if clue_placed >= clue_count:
			break
		var key: String = "%d,%d" % [pos[0], pos[1]]
		if not assigned.has(key):
			assigned[key] = "clue"
			clue_placed += 1

	# 道具
	var item_count: int = dark_config.get("item_count", randi_range(1, 3))
	var item_placed: int = 0
	for pos in walkable_positions:
		if item_placed >= item_count:
			break
		var key: String = "%d,%d" % [pos[0], pos[1]]
		if not assigned.has(key):
			assigned[key] = "item"
			item_placed += 1

	# 剩余全部设为 normal
	for pos in walkable_positions:
		var key: String = "%d,%d" % [pos[0], pos[1]]
		if not assigned.has(key):
			assigned[key] = "normal"

	# 4. 创建卡牌数据
	var locs: Dictionary = dark_locations
	var normal_names: Array = (locs.get("normal", []) as Array).duplicate()
	normal_names.shuffle()
	var normal_idx: int = 0

	home_row = 3
	home_col = 3

	for r in range(1, ROWS + 1):
		for c in range(1, COLS + 1):
			if not walkable[r - 1][c - 1]:
				set_card(r, c, null)  # 墙壁
			else:
				var key: String = "%d,%d" % [r, c]
				var dark_type: String = assigned.get(key, "normal")

				# 选择地点名
				var loc_name: String
				if dark_type == "normal":
					loc_name = normal_names[normal_idx % maxi(normal_names.size(), 1)]
					normal_idx += 1
				elif dark_type == "shop":
					var shop_locs: Array = locs.get("shop", [])
					loc_name = shop_locs[randi() % maxi(shop_locs.size(), 1)] if shop_locs.size() > 0 else "暗市"
				elif dark_type == "intel":
					var intel_locs: Array = locs.get("intel", [])
					loc_name = intel_locs[randi() % maxi(intel_locs.size(), 1)] if intel_locs.size() > 0 else "情报点"
				elif dark_type == "clue":
					var clue_locs: Array = locs.get("clue", [])
					loc_name = clue_locs[randi() % maxi(clue_locs.size(), 1)] if clue_locs.size() > 0 else "线索"
				elif dark_type == "item":
					var item_locs: Array = locs.get("item", [])
					loc_name = item_locs[randi() % maxi(item_locs.size(), 1)] if item_locs.size() > 0 else "道具"
				elif dark_type == "passage":
					loc_name = "崩塌阶梯" if layer_idx == 1 else "裂隙走廊"
				elif dark_type == "abyss_core":
					loc_name = "最深处"
				elif dark_type == "checkpoint":
					loc_name = "面具之门"
				else:
					loc_name = normal_names[normal_idx % maxi(normal_names.size(), 1)]
					normal_idx += 1

				var card: Card = Card.create_dark(dark_type, loc_name, r, c)

				# 恢复已收集状态
				var collected: Dictionary = layer_data.get("collected", {})
				if collected.has(key):
					card.dark_type = "normal"
					card.dark_name = "空走廊"
				set_card(r, c, card)

	print("[Board] Generated dark cards: layer=%d, walkable=%d, walls=%d" % [
		layer_idx, walkable_positions.size(), wall_count])
