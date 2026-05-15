## NPCManager - NPC 管理模块
## 对应原版 NPCManager.lua + npc_dialogues.lua
## 管理棋盘上的 NPC 精灵，同格偏移，点击交互
## 支持: NPC 类型注册表(JSON)、多组随机对话、每日冷却、资源交易
## Godot 2D: 数据层，绘制由 main.gd _draw() 统一处理
class_name NPCManager
extends RefCounted

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------

## 资源交易成功时发出 (用于 UI 弹幕/音效)
signal trade_executed(banner_text: String)
## 交易失败 (资源不足 / 每日已用)
signal trade_failed(reason: String)
## 非交易动作完成 (pet/look/gift 等)
signal action_executed(action: String, banner_text: String)

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

## 同格偏移 (Token 左移, NPC 右移)
const SHARE_OFFSET: float = 18.0  # 像素

const DATA_PATH: String = "res://data/npc_dialogues.json"

# ---------------------------------------------------------------------------
# NPC 类型注册表 (从 JSON 加载)
# ---------------------------------------------------------------------------

## 单个 NPC 类型定义
## { name, tex_path, dialogues[], daily_cooldown, sprite_scale }
var _npc_types: Dictionary = {}  # id → type config dict

## 资源名称/图标映射
var _resource_names: Dictionary = {}  # "health" → "健康"
var _resource_icons: Dictionary = {}  # "health" → "❤️"

## 动作配置 (gift/look/pet/feed 的 banner 和特殊规则)
var _action_config: Dictionary = {}

# ---------------------------------------------------------------------------
# NPC 实例数据
# ---------------------------------------------------------------------------

class NPCData:
	var id: String
	var npc_name: String
	var row: int
	var col: int
	var tex_path: String
	var alpha: float = 0.0
	var scale: float = 0.0
	var breathe_phase: float = 0.0
	var sprite_scale: float = 1.0

var npcs: Dictionary = {}  # id → NPCData

## 每日冷却: id → true 表示当天已使用功能性交互
var _daily_used: Dictionary = {}

# Board 引用
var _board = null  # Board

var _loaded: bool = false

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _init() -> void:
	_load_data()

func _load_data() -> void:
	if _loaded:
		return
	var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("[NPCManager] %s not found" % DATA_PATH)
		return
	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	if err != OK:
		push_warning("[NPCManager] JSON parse error: %s" % json.get_error_message())
		return
	var data: Dictionary = json.data

	# 资源名称/图标
	_resource_names = data.get("resource_names", {})
	_resource_icons = data.get("resource_icons", {})

	# 动作配置
	_action_config = data.get("action_config", {})

	# NPC 类型注册
	var npc_defs: Dictionary = data.get("npcs", {})
	for npc_id in npc_defs:
		var def: Dictionary = npc_defs[npc_id]
		_npc_types[npc_id] = {
			"name": def.get("name", npc_id),
			"tex_path": def.get("tex_path", ""),
			"dialogues": def.get("dialogues", []),
			"daily_cooldown": def.get("daily_cooldown", false),
			"sprite_scale": def.get("sprite_scale", 1.0),
		}

	_loaded = true
	print("[NPCManager] Loaded %d NPC types, %d action configs" % [
		_npc_types.size(), _action_config.size()])
	for npc_id in _npc_types:
		print("[NPCManager]   %s → tex_path=%s" % [npc_id, _npc_types[npc_id].get("tex_path", "")])

# ---------------------------------------------------------------------------
# Board 引用
# ---------------------------------------------------------------------------

func set_board(board) -> void:
	_board = board

# ---------------------------------------------------------------------------
# NPC 类型查询
# ---------------------------------------------------------------------------

## 获取 NPC 类型配置
func get_npc_type(npc_id: String) -> Dictionary:
	return _npc_types.get(npc_id, {})

## 获取 NPC 的随机对话组
## 返回一组 lines 数组, 每行 { speaker, text, choices? }
func get_random_dialogue(npc_id: String) -> Array:
	var type_config: Dictionary = _npc_types.get(npc_id, {})
	var dialogues: Array = type_config.get("dialogues", [])
	if dialogues.is_empty():
		return []
	var idx: int = randi() % dialogues.size()
	return dialogues[idx].get("lines", [])

# ---------------------------------------------------------------------------
# 每日冷却
# ---------------------------------------------------------------------------

## 标记 NPC 当天已使用功能性交互
func mark_used_today(npc_id: String) -> void:
	_daily_used[npc_id] = true

## 查询 NPC 当天是否已使用功能性交互
func is_used_today(npc_id: String) -> bool:
	return _daily_used.get(npc_id, false)

## 重置每日冷却 (新一天开始时调用)
func reset_daily() -> void:
	_daily_used.clear()

# ---------------------------------------------------------------------------
# NPC 实例管理
# ---------------------------------------------------------------------------

## 放置 NPC (使用注册表中的类型配置)
func spawn_npc(id: String, row: int, col: int) -> void:
	if npcs.has(id):
		remove_npc(id)

	var type_config: Dictionary = _npc_types.get(id, {})

	var npc: NPCData = NPCData.new()
	npc.id = id
	npc.npc_name = type_config.get("name", id)
	npc.row = row
	npc.col = col
	npc.tex_path = type_config.get("tex_path", "")
	npc.alpha = 0.0
	npc.scale = 0.0
	npc.sprite_scale = type_config.get("sprite_scale", 1.0)
	npc.breathe_phase = randf() * TAU
	npcs[id] = npc
	# 弹出动画由 main.gd tween 驱动 npc.scale/alpha
	print("[NPCManager] Spawned '%s' at (%d,%d)" % [npc.npc_name, row, col])

## 放置 NPC (使用自定义参数, 兼容旧接口)
func spawn_npc_custom(id: String, npc_name: String, row: int, col: int,
		tex_path: String) -> void:
	if npcs.has(id):
		remove_npc(id)

	var npc: NPCData = NPCData.new()
	npc.id = id
	npc.npc_name = npc_name
	npc.row = row
	npc.col = col
	npc.tex_path = tex_path
	npc.alpha = 0.0
	npc.scale = 0.0
	npc.breathe_phase = randf() * TAU
	npcs[id] = npc

## 移除指定 NPC
func remove_npc(id: String) -> void:
	npcs.erase(id)

## 清除全部 NPC (每日重置时调用)
func clear() -> void:
	npcs.clear()
	_daily_used.clear()

## 查询指定格子的 NPC
func get_npc_at(row: int, col: int) -> NPCData:
	for npc in npcs.values():
		if npc.row == row and npc.col == col:
			return npc
	return null

## 获取 Token 的同格偏移量 (负值=左移)
## 如果该格有 NPC 则返回 -SHARE_OFFSET，否则返回 0
func get_share_offset(row: int, col: int) -> float:
	if get_npc_at(row, col) != null:
		return -SHARE_OFFSET
	return 0.0

## 每帧更新: 呼吸浮动参数
func update(_dt: float, game_time: float) -> void:
	for npc in npcs.values():
		if npc.alpha <= 0.01:
			continue
		# 呼吸动画参数 (实际绘制由 main.gd 使用)
		npc.breathe_phase = game_time * 2.2 + npc.breathe_phase

# ---------------------------------------------------------------------------
# 选项动作执行
# ---------------------------------------------------------------------------

## 执行对话选项动作
## choice_data: { action, cost?, gain?, label }
## 返回 true 表示动作执行成功, false 表示失败
func execute_choice_action(npc_id: String, choice_data: Dictionary) -> bool:
	if choice_data.is_empty():
		return false

	var action: String = choice_data.get("action", "none")

	# "none" 直接返回
	if action == "none":
		return true

	var ac: Dictionary = _action_config.get(action, {})

	# "look" 类动作: 无资源变动, 不受每日限制
	if ac.get("no_cooldown", false):
		var banner: String = ac.get("banner", "")
		if banner != "":
			action_executed.emit(action, banner)
		return true

	# 有资源效果的交互: 检查每日冷却
	var type_config: Dictionary = _npc_types.get(npc_id, {})
	if type_config.get("daily_cooldown", false) and is_used_today(npc_id):
		trade_failed.emit("today_used")
		return false

	# --- 处理各种动作 ---

	if action == "trade":
		return _do_trade(npc_id, choice_data)

	elif action == "pet" or action == "feed":
		return _do_resource_action(npc_id, choice_data, action)

	elif action == "gift":
		return _do_gift(npc_id, action)

	# 未知动作, 仍然标记冷却
	if type_config.get("daily_cooldown", false):
		mark_used_today(npc_id)
	return true

# --- 内部: 资源交易 (trade) ---
func _do_trade(npc_id: String, choice_data: Dictionary) -> bool:
	var cost: Array = choice_data.get("cost", [])
	var gain: Array = choice_data.get("gain", [])

	# 检查资源是否足够
	if cost.size() >= 2:
		var cost_res: String = cost[0]
		var cost_amt: int = int(cost[1])
		if GameData.get_resource(cost_res) < cost_amt:
			trade_failed.emit("insufficient")
			return false
		GameData.modify_resource(cost_res, -cost_amt)

	# 获得资源
	if gain.size() >= 2:
		var gain_res: String = gain[0]
		var gain_amt: int = int(gain[1])
		GameData.modify_resource(gain_res, gain_amt)
		# 生成 banner
		var icon: String = _resource_icons.get(gain_res, "")
		var res_name: String = _resource_names.get(gain_res, gain_res)
		var banner: String = "%s %s +%d" % [icon, res_name, gain_amt]
		trade_executed.emit(banner)

	mark_used_today(npc_id)
	return true

# --- 内部: pet/feed 等带资源的动作 ---
func _do_resource_action(npc_id: String, choice_data: Dictionary, action: String) -> bool:
	# 检查 cost
	var cost: Array = choice_data.get("cost", [])
	if cost.size() >= 2:
		var cost_res: String = cost[0]
		var cost_amt: int = int(cost[1])
		if GameData.get_resource(cost_res) < cost_amt:
			trade_failed.emit("insufficient")
			return false
		GameData.modify_resource(cost_res, -cost_amt)

	# 获得资源
	var gain: Array = choice_data.get("gain", [])
	if gain.size() >= 2:
		GameData.modify_resource(gain[0], int(gain[1]))

	mark_used_today(npc_id)

	var ac: Dictionary = _action_config.get(action, {})
	var banner: String = ac.get("banner", "")
	if banner != "":
		action_executed.emit(action, banner)
	return true

# --- 内部: gift 动作 (固定奖励) ---
func _do_gift(npc_id: String, action: String) -> bool:
	var ac: Dictionary = _action_config.get(action, {})
	var res_key: String = ac.get("resource", "")
	var amount: int = int(ac.get("amount", 0))
	if res_key != "" and amount > 0:
		GameData.modify_resource(res_key, amount)

	mark_used_today(npc_id)

	var banner: String = ac.get("banner", "")
	if banner != "":
		action_executed.emit(action, banner)
	return true

# ---------------------------------------------------------------------------
# 重置
# ---------------------------------------------------------------------------

## 完全重置 (游戏重新开始)
func reset() -> void:
	npcs.clear()
	_daily_used.clear()
	_npc_types.clear()
	_loaded = false
	_load_data()
