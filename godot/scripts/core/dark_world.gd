## DarkWorld - 暗面世界主控制器
## 对应原版 DarkWorld.lua
## 3 层持久化地图 + 能量系统 + 小幽灵 AI + 进出/层间转移
## Godot 2D: 数据层，幽灵/NPC 节点 + HUD 绘制由 main.gd 统一处理
class_name DarkWorld
extends RefCounted

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

const MAX_ENERGY := 10       # 每层独立能量
const GHOST_SAN := -2        # 幽灵碰撞扣理智
const GHOST_COUNT: Array[int] = [2, 3, 2]  # 各层幽灵数量
const GHOST_CHASE_DIST := 2  # 曼哈顿距离 ≤ 此值 100% 追逐

## 层级配置
const LAYER_CONFIG: Array[Dictionary] = [
	{ "name": "表层·暗巷", "unlock_day": 2, "unlock_fragments": 0 },
	{ "name": "中层·暗市", "unlock_day": 4, "unlock_fragments": 0 },
	{ "name": "深层·暗渊", "unlock_day": 6, "unlock_fragments": 1 },
]

## 暗面地点名称池 (按层级, 0-indexed)
const DARK_LOCATIONS: Array[Dictionary] = [
	# Layer 0 (表层·暗巷)
	{
		"normal": ["锈蚀小巷", "断灯走廊", "裂墙弄堂", "落灰阶梯", "无名死路",
				   "潮湿拐角", "暗影墙根", "废弃车库", "野猫巢穴", "塌陷天桥"],
		"shop":   [],
		"intel":  [],
		"clue":   ["旧档案室", "碎纸堆", "褪色涂鸦"],
		"item":   ["废弃背包", "暗格"],
	},
	# Layer 1 (中层·暗市)
	{
		"normal": ["无光集市", "影子摊位", "假面人群", "沉默柜台", "回声茶馆",
				   "钟表废铺", "药粉小巷", "纸灯笼路", "地下水渠", "迷雾广场"],
		"shop":   ["无光集市", "暗巷当铺"],
		"intel":  ["回声茶馆", "低语井"],
		"clue":   ["密封信件", "帐本残页", "暗号墙"],
		"item":   ["上锁匣子", "遗落药包"],
	},
	# Layer 2 (深层·暗渊)
	{
		"normal": ["崩塌深穴", "骨架走廊", "回声深渊", "凝视大厅", "泣血石室",
				   "虚无阶梯", "裂缝祭坛", "悬浮残桥", "镜像迷宫", "最终长廊"],
		"shop":   [],
		"intel":  [],
		"clue":   ["深渊碑文", "模糊日记", "封印遗物"],
		"item":   ["黑曜石碎片"],
	},
]

## 暗面 NPC 配置 (按层级, 0-indexed)
const DARK_NPCS: Array[Array] = [
	# Layer 0: 双尾猫妖
	[
		{ "id": "nekomata", "name": "双尾猫妖",
		  "tex": "res://assets/image/怪物_双尾猫妖v3_20260426071805.png",
		  "dialogue": [
			  { "speaker": "双尾猫妖", "text": "喵~你也迷路了吗？这里的巷子会自己改变方向的……" },
			  { "speaker": "双尾猫妖", "text": "小心那些飘来飘去的家伙，它们可不像我这么友好。" },
			  { "speaker": "双尾猫妖", "text": "要是走不动了就回去吧，反正下次来还是这条路。" },
		  ],
		},
	],
	# Layer 1: 幽灵娘 + 无脸商人
	[
		{ "id": "ghost_girl", "name": "幽灵娘",
		  "tex": "res://assets/image/怪物_幽灵娘v3_20260426072315.png",
		  "dialogue": [
			  { "speaker": "幽灵娘", "text": "……你在找什么？" },
			  { "speaker": "幽灵娘", "text": "她留下过很多东西，散落在各个角落里……" },
			  { "speaker": "幽灵娘", "text": "那些碎片……拼在一起也许能看到些什么。" },
		  ],
		},
		{ "id": "faceless", "name": "无脸商人",
		  "tex": "res://assets/image/怪物_无脸商人_20260426071011.png",
		  "dialogue": [
			  { "speaker": "无脸商人", "text": "……" },
			  { "speaker": "无脸商人", "text": "只认钱。不问来历。" },
			  { "speaker": "无脸商人", "text": "想要什么……自己看。" },
		  ],
		},
	],
	# Layer 2: 面具使
	[
		{ "id": "mask_user", "name": "面具使",
		  "tex": "res://assets/image/edited_怪物_面具使v3_20260426073034.png",
		  "dialogue": [
			  { "speaker": "面具使", "text": "到这里来的人……都在找什么东西。" },
			  { "speaker": "面具使", "text": "最深处有一个地方……但你需要足够的碎片。" },
			  { "speaker": "面具使", "text": "去看看吧，如果你觉得自己准备好了的话。" },
		  ],
		},
	],
]

## 小幽灵贴图
const GHOST_TEXTURES: Array[String] = [
	"res://assets/image/小幽灵_愤怒v2_20260426073743.png",
	"res://assets/image/小幽灵_开心v2_20260426073756.png",
	"res://assets/image/小幽灵_狡猾v2_20260426073758.png",
	"res://assets/image/小幽灵_委屈v2_20260426073907.png",
	"res://assets/image/小幽灵_瞌睡v2_20260426073910.png",
]

# ---------------------------------------------------------------------------
# 幽灵数据
# ---------------------------------------------------------------------------

class GhostData:
	var row: int
	var col: int
	var alive: bool = true
	var tex_index: int = 0  # → GHOST_TEXTURES 索引
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
	var energy: int = MAX_ENERGY
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
	_reset_layers()

func _reset_layers() -> void:
	layers.clear()
	for i in range(3):
		var ld := LayerData.new()
		ld.index = i
		layers.append(ld)

## 完全重置
func reset() -> void:
	_reset_layers()
	active = false
	current_layer = 0
	dark_state = "idle"
	energy_flash = 0.0

# ---------------------------------------------------------------------------
# 层级查询
# ---------------------------------------------------------------------------

func can_enter(day_count: int) -> bool:
	return day_count >= LAYER_CONFIG[0]["unlock_day"]

func is_layer_unlocked(layer_idx: int, day_count: int, fragments: int = 0) -> bool:
	if layer_idx < 0 or layer_idx >= 3:
		return false
	var cfg: Dictionary = LAYER_CONFIG[layer_idx]
	return day_count >= cfg["unlock_day"] and fragments >= cfg["unlock_fragments"]

func get_energy() -> int:
	if layers.is_empty() or current_layer < 0 or current_layer >= layers.size():
		return 0
	return layers[current_layer].energy

func get_layer_name() -> String:
	return LAYER_CONFIG[current_layer]["name"]

func get_layer_data() -> LayerData:
	if layers.is_empty():
		return null
	return layers[current_layer]

# ---------------------------------------------------------------------------
# 暗面卡牌生成配置 (供 Board.generate_dark_cards 使用)
# ---------------------------------------------------------------------------

## 返回指定层的卡牌生成配置 (layer_idx 0-based)
func get_dark_config(layer_idx: int) -> Dictionary:
	if layer_idx == 0:
		return {
			"layer_idx": 0,
			"wall_count": randi_range(5, 7),
			"passage_count": 1,
			"shop_count": 0,
			"intel_count": 0,
			"checkpoint_count": 0,
			"clue_count": randi_range(3, 5),
			"item_count": randi_range(1, 3),
			"has_abyss_core": false,
		}
	elif layer_idx == 1:
		return {
			"layer_idx": 1,
			"wall_count": randi_range(4, 6),
			"passage_count": 2,
			"shop_count": randi_range(1, 2),
			"intel_count": randi_range(1, 2),
			"checkpoint_count": randi_range(1, 2),
			"clue_count": randi_range(3, 5),
			"item_count": randi_range(1, 3),
			"has_abyss_core": false,
		}
	else:
		return {
			"layer_idx": 2,
			"wall_count": randi_range(6, 8),
			"passage_count": 0,
			"shop_count": 0,
			"intel_count": 0,
			"checkpoint_count": randi_range(1, 2),
			"clue_count": randi_range(3, 5),
			"item_count": randi_range(1, 3),
			"has_abyss_core": true,
		}

## 获取指定层的地点名称池 (0-based)
func get_dark_locations(layer_idx: int) -> Dictionary:
	if layer_idx < 0 or layer_idx >= DARK_LOCATIONS.size():
		return DARK_LOCATIONS[0]
	return DARK_LOCATIONS[layer_idx]

# ---------------------------------------------------------------------------
# 幽灵 & NPC 生成
# ---------------------------------------------------------------------------

## 为指定层生成幽灵数据 (在 Board 生成卡牌后调用)
func generate_ghosts(layer_idx: int) -> void:
	var layer: LayerData = layers[layer_idx]
	var ghost_count: int = GHOST_COUNT[layer_idx]

	# 收集可通行格子 (排除入口 2,2)
	var walkable_pos: Array = []
	for key in layer.walkable:
		if layer.walkable[key]:
			var parts: PackedStringArray = key.split(",")
			var r := int(parts[0])
			var c := int(parts[1])
			if not (r == 2 and c == 2):
				walkable_pos.append(Vector2i(r, c))
	walkable_pos.shuffle()

	layer.ghosts.clear()
	var count := mini(ghost_count, walkable_pos.size())
	for i in range(count):
		var gd := GhostData.new()
		gd.row = walkable_pos[i].x
		gd.col = walkable_pos[i].y
		gd.alive = true
		gd.tex_index = randi() % GHOST_TEXTURES.size()
		gd.float_phase = randf() * TAU
		layer.ghosts.append(gd)

## 为指定层生成 NPC 数据
func generate_npcs(layer_idx: int) -> void:
	var layer: LayerData = layers[layer_idx]
	var npc_defs: Array = DARK_NPCS[layer_idx]

	var walkable_pos: Array = []
	for key in layer.walkable:
		if layer.walkable[key]:
			var parts: PackedStringArray = key.split(",")
			var r := int(parts[0])
			var c := int(parts[1])
			if not (r == 2 and c == 2):
				walkable_pos.append(Vector2i(r, c))
	walkable_pos.shuffle()

	layer.npcs.clear()
	for i in range(npc_defs.size()):
		if i >= walkable_pos.size():
			break
		var def: Dictionary = npc_defs[i]
		var npc := DarkNPCData.new()
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
		var nr := row + d.x
		var nc := col + d.y
		var key := "%d,%d" % [nr, nc]
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

		var neighbors := _get_walkable_neighbors(layer, ghost.row, ghost.col)
		if neighbors.is_empty():
			continue

		var dist := absi(ghost.row - player_row) + absi(ghost.col - player_col)
		var target: Vector2i

		if dist <= GHOST_CHASE_DIST:
			# 追逐模式: 100% 朝玩家
			var best_dist := 999
			target = neighbors[0]
			for nb in neighbors:
				var d := absi(nb.x - player_row) + absi(nb.y - player_col)
				if d < best_dist:
					best_dist = d
					target = nb
		else:
			# 游荡模式: 50% 朝玩家 / 50% 随机
			if randf() < 0.5:
				var best_dist := 999
				target = neighbors[0]
				for nb in neighbors:
					var d := absi(nb.x - player_row) + absi(nb.y - player_col)
					if d < best_dist:
						best_dist = d
						target = nb
			else:
				target = neighbors[randi() % neighbors.size()]

		var old_row := ghost.row
		var old_col := ghost.col
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
	layer.energy = MAX_ENERGY
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
		var cb := _on_exit
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
	layers[current_layer].energy = MAX_ENERGY

	return { "success": true, "layer_name": LAYER_CONFIG[target_layer]["name"] }

## 新层发牌完成
func on_change_layer_complete() -> void:
	dark_state = "ready"

# ---------------------------------------------------------------------------
# 卡牌效果处理
# ---------------------------------------------------------------------------

## 处理踩上暗面卡牌的效果
## 返回 { "type": String, "data": Variant } 供 main.gd 执行 VFX / 弹窗
## type: "none" | "npc_dialogue" | "shop" | "intel" | "checkpoint" |
##       "clue" | "item" | "passage" | "abyss_core"
func handle_card_effect(card: Card, row: int, col: int,
		day_count: int) -> Dictionary:
	var layer: LayerData = layers[current_layer]
	var key := "%d,%d" % [row, col]

	# NPC 对话检测
	for npc in layer.npcs:
		if npc.row == row and npc.col == col and not npc.dialogue.is_empty():
			dark_state = "popup"
			return {
				"type": "npc_dialogue",
				"data": {
					"dialogue": npc.dialogue,
					"tex": npc.tex_path,
					"npc_name": npc.npc_name,
				},
			}

	var dark_type: String = card.dark_type

	if dark_type == "normal":
		return { "type": "none", "data": null }

	elif dark_type == "shop":
		dark_state = "popup"
		return { "type": "shop", "data": { "name": card.dark_name } }

	elif dark_type == "intel":
		return { "type": "intel", "data": { "cost": 15 } }

	elif dark_type == "checkpoint":
		return { "type": "checkpoint", "data": { "name": card.dark_name } }

	elif dark_type == "clue" and not card.dark_collected:
		card.dark_collected = true
		layer.collected[key] = true
		# 清除线索标记 (变为普通暗巷)
		var old_name := card.dark_name
		card.dark_type = "normal"
		card.dark_name = "空走廊"
		card.dark_icon = "🌑"
		card.dark_label = "暗巷"
		return { "type": "clue", "data": { "name": old_name } }

	elif dark_type == "item" and not card.dark_collected:
		card.dark_collected = true
		layer.collected[key] = true
		# 随机奖励
		var rewards: Array = [["san", 10], ["money", 20], ["film", 1]]
		var pick: Array = rewards[randi() % rewards.size()]
		card.dark_type = "normal"
		card.dark_name = "空走廊"
		card.dark_icon = "🌑"
		card.dark_label = "暗巷"
		return { "type": "item", "data": { "resource": pick[0], "amount": pick[1] } }

	elif dark_type == "passage":
		var target_layer := -1
		if current_layer == 0:
			target_layer = 1
		elif current_layer == 1:
			# L2 双通道 → 由 main.gd 判断 passage 序号
			target_layer = -1  # 需要 main.gd 传入 passage_index
		elif current_layer == 2:
			target_layer = 1

		return { "type": "passage", "data": { "target_layer": target_layer } }

	elif dark_type == "abyss_core":
		return { "type": "abyss_core", "data": null }

	return { "type": "none", "data": null }

# ---------------------------------------------------------------------------
# 玩家移动处理 (核心流程, 由 main.gd 调用)
# ---------------------------------------------------------------------------

## 尝试移动到目标格子
## 返回 Dictionary: { "can_move": bool, "reason": String }
func try_move(target_row: int, target_col: int) -> Dictionary:
	var layer: LayerData = layers[current_layer]

	# 只能相邻格
	var dr := absi(target_row - layer.player_row)
	var dc := absi(target_col - layer.player_col)
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
	var old_row := layer.player_row
	var old_col := layer.player_col
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
