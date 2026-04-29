## DarkWorld - 暗面世界主控制器
## 对应原版 DarkWorld.lua
## 3 层持久化地图 + 能量系统 + 小幽灵 AI + 进出/层间转移
## Godot 2D: 数据层，幽灵/NPC 节点 + HUD 绘制由 main.gd 统一处理
## 配置来源: CardConfig (加载自 data/dark_world.json + data/card_types.json)
class_name DarkWorld
extends RefCounted

# 引用天气系统
var _weather: WeatherSystem = null

## Main 引用 (用于跨模块通信)
var _main: Node = null

## 设置 Main 引用
func set_main(main_ref: Node) -> void:
	_main = main_ref

# ---------------------------------------------------------------------------
# 常量 (现从 CardConfig 动态读取，此处保留默认值以防配置缺失)
# @deprecated 建议使用 CardConfig 或 GameConfig 读取
# ---------------------------------------------------------------------------

## @deprecated 请使用 CardConfig.get_dw_max_energy()
const DEFAULT_MAX_ENERGY: int = 10
## @deprecated 建议使用 CardConfig.get_dw_ghost_san()
const DEFAULT_GHOST_SAN: int = -2
## @deprecated 建议使用 CardConfig.get_dw_ghost_count()
const DEFAULT_GHOST_COUNT: Array[int] = [2, 3, 2]
## @deprecated 建议使用 CardConfig.get_dw_ghost_chase_dist()
const DEFAULT_GHOST_CHASE_DIST: int = 2

# ---------------------------------------------------------------------------
# 幽灵数据
# ---------------------------------------------------------------------------

class GhostData:
	var row: int
	var col: int
	var alive: bool = true
	var tex_index: int = 0  # → CardConfig.get_dw_ghost_textures() 索引
	## 动画属性 (由 main.gd 驱动)
	var alpha: float = 1.0
	var float_phase: float = 0.0
	var screen_x: float = 0.0
	var screen_y: float = 0.0

# ---------------------------------------------------------------------------
# NPC 数据 (暗面世界专属, 不同于 NPCManager 的现实 NPC)
# ---------------------------------------------------------------------------

class DarkNPCData:
	var id: String
	var npc_name: String
	var row: int
	var col: int
	var tex_path: String
	var dialogue: Array  # Array of { "speaker": String, "text": String }

# ---------------------------------------------------------------------------
# 层级数据
# ---------------------------------------------------------------------------

class LayerData:
	var index: int            # 层级索引 (0-based internal)
	var unlocked: bool = false
	var generated: bool = false
	var walkable: Dictionary = {}  # "row,col" → bool
	var ghosts: Array = []    # Array of GhostData
	var npcs: Array = []      # Array of DarkNPCData
	var player_row: int = 2   # 0-based (对应 Board 中心 3行/3列)
	var player_col: int = 2
	var energy: int = DEFAULT_MAX_ENERGY
	var entry_row: int = 2
	var entry_col: int = 2
	var collected: Dictionary = {}  # "row,col" → true

# ---------------------------------------------------------------------------
# 实例状态
# ---------------------------------------------------------------------------

var active: bool = false
var current_layer: int = 0        # 0-based 内部索引
var layers: Array = []            # Array[LayerData] x3
var energy_flash: float = 0.0

## 暗面子状态: "idle" | "ready" | "moving" | "popup" | "transition"
## @deprecated 建议使用 Enums.DarkState 枚举
var dark_state: String = "idle"

## 裂隙位置 (现实世界, 1-based external)
var rift_row: int = 0
var rift_col: int = 0

## 退出回调
var _on_exit: Callable = Callable()

## 层间移动回调 (由 main.gd 注入)
var change_layer_callback: Callable = Callable()

## 退出请求回调 (由 main.gd 注入)
var exit_request_callback: Callable = Callable()

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _init() -> void:
	_weather = WeatherSystem.new()
	_reset_layers()

func _reset_layers() -> void:
	layers.clear()
	for i in range(3):
		var ld: LayerData = LayerData.new()
		ld.index = i
		layers.append(ld)

## 完全重置
func reset() -> void:
	_reset_layers()
	active = false
	current_layer = 0
	dark_state = "idle"
	energy_flash = 0.0
	if _weather:
		_weather.weather_duration = 0.0

# ---------------------------------------------------------------------------
# 层级查询 (配置来源: CardConfig / dark_world.json)
# ---------------------------------------------------------------------------

func can_enter(day_count: int) -> bool:
	var cfg: Dictionary = CardConfig.get_dw_layer_config(0)
	return day_count >= cfg.get("unlock_day", 999)

func is_layer_unlocked(layer_idx: int, day_count: int, fragments: int = 0) -> bool:
	if layer_idx < 0 or layer_idx >= 3:
		return false
	var cfg: Dictionary = CardConfig.get_dw_layer_config(layer_idx)
	return day_count >= cfg.get("unlock_day", 999) and fragments >= cfg.get("unlock_fragments", 0)

func get_energy() -> int:
	if layers.is_empty() or current_layer < 0 or current_layer >= layers.size():
		return 0
	return layers[current_layer].energy

func get_layer_name() -> String:
	var cfg: Dictionary = CardConfig.get_dw_layer_config(current_layer)
	return cfg.get("name", "")

func get_layer_data() -> LayerData:
	if layers.is_empty():
		return null
	return layers[current_layer]

# ---------------------------------------------------------------------------
# 暗面卡牌生成配置 (供 Board.generate_dark_cards 使用)
# ---------------------------------------------------------------------------

## 返回指定层的卡牌生成配置 (layer_idx 0-based)
## 配置来源: CardConfig.get_dw_layer_gen() → dark_world.json → layer_generation
func get_dark_config(layer_idx: int) -> Dictionary:
	var gen: Dictionary = CardConfig.get_dw_layer_gen(layer_idx)
	if gen.is_empty():
		# 兜底默认值
		return {
			"layer_idx": layer_idx,
			"wall_count": 5,
			"passage_count": 1,
			"shop_count": 0,
			"intel_count": 0,
			"checkpoint_count": 0,
			"clue_count": 3,
			"item_count": 1,
			"has_abyss_core": false,
		}
	gen["layer_idx"] = layer_idx
	return gen

## 获取指定层的地点名称池 (0-based)
## 配置来源: CardConfig.get_dw_location_pool() → dark_world.json → location_pools
func get_dark_locations(layer_idx: int) -> Dictionary:
	var pool: Dictionary = CardConfig.get_dw_location_pool(layer_idx)
	if pool.is_empty() and layer_idx != 0:
		return CardConfig.get_dw_location_pool(0)
	return pool

# ---------------------------------------------------------------------------
# 幽灵 & NPC 生成
# ---------------------------------------------------------------------------

## 为指定层生成幽灵数据 (在 Board 生成卡牌后调用)
## 配置来源: CardConfig.get_dw_ghost_count() / get_dw_ghost_textures()
func generate_ghosts(layer_idx: int) -> void:
	var layer: LayerData = layers[layer_idx]
	var ghost_count: int = CardConfig.get_dw_ghost_count(layer_idx)
	var ghost_textures: Array = CardConfig.get_dw_ghost_textures()

	# 收集可通行格子 (排除入口 2,2)
	var walkable_pos: Array = []
	for key in layer.walkable:
		if layer.walkable[key]:
			var parts: PackedStringArray = key.split(",")
			var r: int = int(parts[0])
			var c: int = int(parts[1])
			if not (r == 2 and c == 2):
				walkable_pos.append(Vector2i(r, c))
	walkable_pos.shuffle()

	layer.ghosts.clear()
	var count: int = mini(ghost_count, walkable_pos.size())
	for i in range(count):
		var gd: GhostData = GhostData.new()
		gd.row = walkable_pos[i].x
		gd.col = walkable_pos[i].y
		gd.alive = true
		if ghost_textures.size() > 0:
			gd.tex_index = randi() % ghost_textures.size()
		gd.float_phase = randf() * TAU
		layer.ghosts.append(gd)

## 为指定层生成 NPC 数据
## 配置来源: CardConfig.get_dw_npcs() → dark_world.json → npcs
func generate_npcs(layer_idx: int) -> void:
	var layer: LayerData = layers[layer_idx]
	var npc_defs: Array = CardConfig.get_dw_npcs(layer_idx)

	var walkable_pos: Array = []
	for key in layer.walkable:
		if layer.walkable[key]:
			var parts: PackedStringArray = key.split(",")
			var r: int = int(parts[0])
			var c: int = int(parts[1])
			if not (r == 2 and c == 2):
				walkable_pos.append(Vector2i(r, c))
	walkable_pos.shuffle()

	layer.npcs.clear()
	for i in range(npc_defs.size()):
		if i >= walkable_pos.size():
			break
		var def: Dictionary = npc_defs[i]
		var npc: DarkNPCData = DarkNPCData.new()
		npc.id = def["id"]
		npc.npc_name = def["name"]
		npc.row = walkable_pos[i].x
		npc.col = walkable_pos[i].y
		npc.tex_path = def["tex"]
		npc.dialogue = def["dialogue"]
		layer.npcs.append(npc)

## 一次性生成幽灵 + NPC + 标记 generated
func generate_overlay_data(layer_idx: int) -> void:
	generate_ghosts(layer_idx)
	generate_npcs(layer_idx)
	layers[layer_idx].generated = true

# ---------------------------------------------------------------------------
# 幽灵 AI
# ---------------------------------------------------------------------------

## 获取可通行邻居 (返回 Vector2i 数组)
func _get_walkable_neighbors(layer: LayerData, row: int, col: int) -> Array:
	var neighbors: Array = []
	var dirs: Array = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	for d in dirs:
		var nr: int = row + d.x
		var nc: int = col + d.y
		var key: String = "%d,%d" % [nr, nc]
		if layer.walkable.has(key) and layer.walkable[key]:
			neighbors.append(Vector2i(nr, nc))
	return neighbors

## 移动所有幽灵 (玩家移动后调用)
## 返回碰撞列表: Array of GhostData (已被标记为 alive=false)
func move_ghosts(player_row: int, player_col: int,
		old_player_row: int, old_player_col: int) -> Array:
	var layer: LayerData = layers[current_layer]
	var collisions: Array = []

	for ghost in layer.ghosts:
		if not ghost.alive:
			continue

		var neighbors: Array = _get_walkable_neighbors(layer, ghost.row, ghost.col)
		if neighbors.is_empty():
			continue

		var dist: int = absi(ghost.row - player_row) + absi(ghost.col - player_col)
		var target: Vector2i

		if dist <= CardConfig.get_dw_ghost_chase_dist():
			# 追逐模式: 100% 朝玩家
			var best_dist: int = 999
			target = neighbors[0]
			for nb in neighbors:
				var d: int = absi(nb.x - player_row) + absi(nb.y - player_col)
				if d < best_dist:
					best_dist = d
					target = nb
		else:
			# 游荡模式: 50% 朝玩家 / 50% 随机
			if randf() < 0.5:
				var best_dist: int = 999
				target = neighbors[0]
				for nb in neighbors:
					var d: int = absi(nb.x - player_row) + absi(nb.y - player_col)
					if d < best_dist:
						best_dist = d
						target = nb
			else:
				target = neighbors[randi() % neighbors.size()]

		var old_row: int = ghost.row
		var old_col: int = ghost.col
		ghost.row = target.x
		ghost.col = target.y

		# 碰撞检测: 幽灵走到玩家位置
		if ghost.row == player_row and ghost.col == player_col:
			ghost.alive = false
			collisions.append(ghost)
			continue

		# 互换位检测: 擦肩而过
		if old_row == player_row and old_col == player_col \
				and ghost.row == old_player_row and ghost.col == old_player_col:
			ghost.alive = false
			collisions.append(ghost)
			continue

	return collisions

## 检测玩家当前格子是否有幽灵 (移动到达后调用)
## 返回碰撞的 GhostData 或 null
func check_ghost_collision(player_row: int, player_col: int) -> GhostData:
	if layers.is_empty() or current_layer < 0 or current_layer >= layers.size():
		return null
	var layer: LayerData = layers[current_layer]
	for ghost in layer.ghosts:
		if ghost.alive and ghost.row == player_row and ghost.col == player_col:
			ghost.alive = false
			return ghost
	return null

# ---------------------------------------------------------------------------
# 进入/退出/层间移动
# ---------------------------------------------------------------------------

## 进入暗面世界 (由 main.gd 调用)
## rift_r / rift_c: 1-based (现实世界裂隙位置)
func enter(day_count: int, rift_r: int, rift_c: int,
		on_exit: Callable = Callable()) -> void:
	rift_row = rift_r
	rift_col = rift_c
	_on_exit = on_exit
	active = true

	# 确定进入层级
	if not layers[current_layer].generated:
		current_layer = 0

	# 解锁层级
	for i in range(3):
		if is_layer_unlocked(i, day_count, 0):
			layers[i].unlocked = true

	var layer: LayerData = layers[current_layer]
	layer.energy = CardConfig.get_dw_max_energy()
	dark_state = "transition"

## 暗面完全进入 (发牌完成后)
func on_enter_complete() -> void:
	dark_state = "ready"

## 开始退出 → 返回 { rift_row, rift_col }
## main.gd 负责收牌后调用 on_exit_complete()
func begin_exit() -> Dictionary:
	dark_state = "transition"
	return { "rift_row": rift_row, "rift_col": rift_col }

## 退出完成
func on_exit_complete() -> void:
	active = false
	dark_state = "idle"
	if _on_exit.is_valid():
		var cb: Callable = _on_exit
		_on_exit = Callable()
		cb.call()

## 层间移动 — 返回 { success, layer_name }
func begin_change_layer(target_layer: int, day_count: int) -> Dictionary:
	if target_layer < 0 or target_layer >= 3:
		return { "success": false, "layer_name": "" }
	if not layers[target_layer].unlocked:
		return { "success": false, "layer_name": "" }

	dark_state = "transition"
	current_layer = target_layer
	layers[current_layer].energy = CardConfig.get_dw_max_energy()

	return { "success": true, "layer_name": CardConfig.get_dw_layer_config(target_layer).get("name", "") }

## 新层发牌完成
func on_change_layer_complete() -> void:
	dark_state = "ready"

# ---------------------------------------------------------------------------
# 卡牌效果处理
# ---------------------------------------------------------------------------

## 处理踩上暗面卡牌的效果
## @deprecated 建议使用 EventHandler.parse_dark_world_card() 统一处理
## @param row: 1-based 坐标
## @param col: 1-based 坐标
## @return EventHandler.EventResult 统一事件结果
func handle_card_effect(card: Card, row: int, col: int, day_count: int) -> Dictionary:
	var layer: LayerData = layers[current_layer]
	var key: String = "%d,%d" % [row, col]

	# 标记为已收集
	if card.dark_collected:
		layer.collected[key] = true

	# 返回统一格式供 EventHandler 处理
	# 具体效果逻辑已移至 EventHandler.parse_dark_world_card()
	return {
		"type": card.dark_type,
		"data": {
			"card": card,
			"row": row,
			"col": col,
			"layer": current_layer,
			"dark_name": card.dark_name,
		}
	}

## 收集暗面卡牌 (线索/道具被拾取后调用)
## @param row: 1-based 坐标
## @param col: 1-based 坐标
## @param card: 可选的 Card 对象，用于更新卡牌显示状态
func collect_card(row: int, col: int, card: Card = null) -> void:
	var layer: LayerData = layers[current_layer]
	var key: String = "%d,%d" % [row, col]
	# 存储原始类型，用于重建棋盘时判断
	if card != null:
		layer.collected[key] = card.dark_type
	else:
		layer.collected[key] = "normal"
	
	# 如果提供了 card 对象，更新卡牌显示状态
	if card:
		card.dark_collected = true
		card.dark_type = "normal"
		card.dark_name = "空走廊"
		card.dark_icon = "🌑"

# ---------------------------------------------------------------------------
# 玩家移动处理 (核心流程, 由 main.gd 调用)
# ---------------------------------------------------------------------------

## 尝试移动到目标格子
## 返回 Dictionary: { "can_move": bool, "reason": String }
func try_move(target_row: int, target_col: int) -> Dictionary:
	var layer: LayerData = layers[current_layer]

	# 只能相邻格
	var dr: int = absi(target_row - layer.player_row)
	var dc: int = absi(target_col - layer.player_col)
	if dr + dc != 1:
		return { "can_move": false, "reason": "not_adjacent" }

	# 检查能量
	if layer.energy <= 0:
		return { "can_move": false, "reason": "no_energy" }

	return { "can_move": true, "reason": "" }

## 消耗能量并更新玩家位置 (移动动画开始前调用)
## 返回 { old_row, old_col }
func consume_move(target_row: int, target_col: int) -> Dictionary:
	var layer: LayerData = layers[current_layer]
	var old_row: int = layer.player_row
	var old_col: int = layer.player_col
	layer.energy -= 1
	energy_flash = 0.5
	dark_state = "moving"
	return { "old_row": old_row, "old_col": old_col }

## 移动完成 (Token 动画结束后调用)
func on_move_complete(target_row: int, target_col: int) -> void:
	var layer: LayerData = layers[current_layer]
	layer.player_row = target_row
	layer.player_col = target_col

## 将状态恢复为 ready (在所有效果处理完成后)
func set_ready() -> void:
	dark_state = "ready"

## 请求退出
func request_exit() -> void:
	if exit_request_callback.is_valid():
		exit_request_callback.call()

# ---------------------------------------------------------------------------
# 相机驱除幽灵
# ---------------------------------------------------------------------------

## 使用相机拍摄驱除指定格子的幽灵
## 返回被驱除的 GhostData 或 null
func handle_camera_shot(target_row: int, target_col: int) -> GhostData:
	if not active or dark_state != "ready":
		return null
	if layers.is_empty() or current_layer < 0 or current_layer >= layers.size():
		return null

	var layer: LayerData = layers[current_layer]
	for ghost in layer.ghosts:
		if ghost.alive and ghost.row == target_row and ghost.col == target_col:
			ghost.alive = false
			return ghost
	return null

# ---------------------------------------------------------------------------
# 每帧更新
# ---------------------------------------------------------------------------

func update(dt: float, _game_time: float) -> void:
	if not active:
		return

	if energy_flash > 0.0:
		energy_flash = maxf(0.0, energy_flash - dt * 2.0)

	# 更新天气系统
	if _weather:
		_weather.update(dt)

## 获取天气系统实例
func get_weather() -> WeatherSystem:
	return _weather
