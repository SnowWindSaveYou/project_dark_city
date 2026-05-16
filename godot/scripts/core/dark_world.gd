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
# ---------------------------------------------------------------------------
# 层级数据
# ---------------------------------------------------------------------------

class LayerData:
	var index: int            # 层级索引 (0-based internal)
	var unlocked: bool = false
	var generated: bool = false
	var walkable: Dictionary = {}  # "row,col" → bool
	var ghosts: Array = []    # Array of GhostData
	## NPC 由 NPCManager 统一管理，此处不再单独存储
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

## 共享 NPCManager 引用（由外部注入，暗面和现实共用同一 manager）
var _npc_manager: NPCManager = null
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

func can_enter() -> bool:
	var cfg: Dictionary = CardConfig.get_dw_layer_config(0)
	return GameData.get_resource("inspiration") >= cfg.get("unlock_inspiration", 999)

## 通道是否可用: 当前层有可达目的地时显示 chibi
## - 向后(回上层): current_layer > 0, 始终可用
## - 向前(去下层): 检查下一层是否解锁
func can_use_passage(fragments: int = 0) -> bool:
	if current_layer > 0:
		return true  # 永远可以回上层
	return is_layer_unlocked(current_layer + 1, fragments)

func is_layer_unlocked(layer_idx: int, fragments: int = 0) -> bool:
	if layer_idx < 0 or layer_idx >= 3:
		return false
	var cfg: Dictionary = CardConfig.get_dw_layer_config(layer_idx)
	return GameData.get_resource("inspiration") >= cfg.get("unlock_inspiration", 999) \
		and fragments >= cfg.get("unlock_fragments", 0)

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

## 为指定层生成 NPC 数据，统一存入 npc_manager
## board 可选参数用于 bind_to_card NPC 定位（绑定到指定卡牌类型格子）
## 配置来源: CardConfig.get_dw_npcs() → dark_world.json → npcs
func generate_npcs(layer_idx: int, npc_manager: NPCManager, board = null) -> void:
	var layer: LayerData = layers[layer_idx]
	var npc_defs: Array = CardConfig.get_dw_npcs(layer_idx)

	# 构建 dark_type → 格子(0-based) 的索引（用于 bind_to_card）
	var card_type_pos: Dictionary = {}  # dark_type -> Array[Vector2i]
	if board != null:
		for r in range(1, Board.ROWS + 1):
			for c in range(1, Board.COLS + 1):
				var cd: Card = board.get_card(r, c)
				if cd != null and cd.dark_type != "" and cd.dark_type != "normal":
					if not card_type_pos.has(cd.dark_type):
						card_type_pos[cd.dark_type] = []
					card_type_pos[cd.dark_type].append(Vector2i(r - 1, c - 1))  # 转 0-based

	# 可行走位置（排除出生点）
	var walkable_pos: Array = []
	for key in layer.walkable:
		if layer.walkable[key]:
			var parts: PackedStringArray = key.split(",")
			var r: int = int(parts[0])
			var c: int = int(parts[1])
			if not (r == 2 and c == 2):
				walkable_pos.append(Vector2i(r, c))
	walkable_pos.shuffle()

	# 已被 bind_to_card NPC 占用的格子
	var occupied: Dictionary = {}

	# 辅助：注册并生成 NPC
	var _spawn = func(def: Dictionary, pos: Vector2i) -> void:
		var npc_id: String = def["id"]
		npc_manager._npc_types[npc_id] = {
			"name": def["name"],
			"tex_path": def["tex"],
			"dialogues": [def["dialogue"]],
			"sprite_scale": 1.0,
		}
		npc_manager.spawn_npc(npc_id, pos.x, pos.y)

	# 第一遍：bind_to_card NPC 精确放置
	for def in npc_defs:
		if def.has("bind_to_card"):
			var target_type: String = def["bind_to_card"]
			var candidates: Array = card_type_pos.get(target_type, [])
			if candidates.size() > 0:
				var pos: Vector2i = candidates[0]
				_spawn.call(def, pos)
				occupied["%d,%d" % [pos.x, pos.y]] = true

	# 第二遍：普通 NPC 随机放置（跳过占用格子）
	var free_idx: int = 0
	for def in npc_defs:
		if not def.has("bind_to_card"):
			# 找下一个未占用位置
			while free_idx < walkable_pos.size():
				var p: Vector2i = walkable_pos[free_idx]
				if not occupied.has("%d,%d" % [p.x, p.y]):
					break
				free_idx += 1
			if free_idx >= walkable_pos.size():
				break
			_spawn.call(def, walkable_pos[free_idx])
			free_idx += 1

## 一次性生成幽灵 + NPC + 标记 generated
## board 参数用于 bind_to_card NPC 定位
func generate_overlay_data(layer_idx: int, board = null) -> void:
	generate_ghosts(layer_idx)
	generate_npcs(layer_idx, _npc_manager, board)
	layers[layer_idx].generated = true

## 查询指定格子 (0-based) 是否有暗面 NPC，委托给 npc_manager
## 返回 { id, name, dialogue, tex } 或 {} (空字典)
func get_npc_at(row: int, col: int) -> Dictionary:
	if _npc_manager == null:
		return {}
	var npc: NPCManager.NPCData = _npc_manager.get_npc_at(row, col)
	if npc == null:
		return {}
	var type_cfg: Dictionary = _npc_manager._npc_types.get(npc.id, {})
	var dialogues: Array = type_cfg.get("dialogues", [])
	var dialogue: Array = dialogues[0] if dialogues.size() > 0 else []
	return {
		"id": npc.id,
		"name": npc.npc_name,
		"dialogue": dialogue,
		"tex": npc.tex_path,
	}

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
# 碎片掉落 / 精英遭遇 / Boss 遭遇 / 道具奖池
# ---------------------------------------------------------------------------

## 检查当前条件是否可以掉落碎片 (在踩到 clue 卡时调用)
## current_frags: 玩家已持有碎片数, flags: 全局 flag 字典
## 返回 frag_id (如 "frag_02") 或空字符串 (不掉落)
func check_fragment_drop(current_frags: int, flags: Dictionary) -> String:
	var drops: Array = CardConfig.get_dw_fragment_drops()
	var layer_1based: int = current_layer + 1
	for drop in drops:
		var min_f: int = int(drop.get("min_frags", 0))
		var layer_min: int = int(drop.get("layer_min", 1))
		var flag: String = drop.get("flag", "")
		# 条件: 碎片数 >= min_frags, 当前层 >= layer_min, flag 未设置
		if current_frags >= min_f and layer_1based >= layer_min:
			if flag.is_empty() or not flags.get(flag, false):
				return drop.get("frag_id", "")
	return ""

## 检查是否触发精英遭遇
## fragments: 碎片数, has_baiye: 白夜是否跟随, has_clue_card: 是否踩到线索卡
func check_elite_encounter(fragments: int, has_baiye: bool,
		has_clue_card: bool, flags: Dictionary) -> bool:
	var enc: Dictionary = CardConfig.get_dw_elite_encounter()
	if enc.is_empty():
		return false
	var cond: Dictionary = enc.get("conditions", {})
	if fragments < int(cond.get("min_fragments", 999)):
		return false
	if cond.get("requires_baiye_follow", false) and not has_baiye:
		return false
	if cond.get("requires_clue_card", false) and not has_clue_card:
		return false
	var not_flag: String = cond.get("not_flag", "")
	if not not_flag.is_empty() and flags.get(not_flag, false):
		return false
	return true

## 检查是否触发 Boss 遭遇
## fragments: 碎片数, has_baiye: 白夜是否跟随, has_abyss_core: 是否踩到深渊核心
func check_boss_encounter(fragments: int, has_baiye: bool,
		has_abyss_core: bool, flags: Dictionary) -> bool:
	var enc: Dictionary = CardConfig.get_dw_boss_encounter()
	if enc.is_empty():
		return false
	var cond: Dictionary = enc.get("conditions", {})
	if fragments < int(cond.get("min_fragments", 999)):
		return false
	if cond.get("requires_baiye_follow", false) and not has_baiye:
		return false
	if cond.get("requires_abyss_core", false) and not has_abyss_core:
		return false
	var not_flag: String = cond.get("not_flag", "")
	if not not_flag.is_empty() and flags.get(not_flag, false):
		return false
	return true

## 从道具奖池按权重随机抽取一项
## 返回 { res: String, amt: int, label: String } 或空 Dictionary
func roll_item_reward() -> Dictionary:
	var items: Array = CardConfig.get_dw_item_reward_pool()
	if items.is_empty():
		return {}
	var total_weight: int = 0
	for item in items:
		total_weight += int(item.get("weight", 1))
	if total_weight <= 0:
		return {}
	var roll: int = randi() % total_weight
	var cumulative: int = 0
	for item in items:
		cumulative += int(item.get("weight", 1))
		if roll < cumulative:
			return {
				"res": item.get("res", ""),
				"amt": int(item.get("amt", 0)),
				"label": item.get("label", ""),
			}
	# fallback (不应到达)
	var last = items[items.size() - 1]
	return { "res": last.get("res", ""), "amt": int(last.get("amt", 0)), "label": last.get("label", "") }

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
		if is_layer_unlocked(i, 0):
			layers[i].unlocked = true

	var layer: LayerData = layers[current_layer]
	# 能量 = min(当前san, max_energy)，san 越低探索越受限
	var max_e: int = CardConfig.get_dw_max_energy()
	var san: int = GameData.get_resource("san")
	layer.energy = mini(san, max_e)
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
	# 能量 = min(当前san, max_energy)
	var max_e: int = CardConfig.get_dw_max_energy()
	var san: int = GameData.get_resource("san")
	layers[current_layer].energy = mini(san, max_e)

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
