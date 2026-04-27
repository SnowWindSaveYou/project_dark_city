## NPCManager - NPC 管理模块
## 对应原版 NPCManager.lua
## 管理棋盘上的 NPC 精灵，同格偏移，点击交互
## Godot 2D: 数据层，绘制由 main.gd _draw() 统一处理
class_name NPCManager
extends RefCounted

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

## 同格偏移 (Token 左移, NPC 右移)
const SHARE_OFFSET := 18.0  # 像素

# ---------------------------------------------------------------------------
# NPC 数据
# ---------------------------------------------------------------------------

class NPCData:
	var id: String
	var npc_name: String
	var row: int
	var col: int
	var tex_path: String
	var dialogue_script: Array  # Array of { "speaker": String, "text": String }
	var alpha: float = 0.0
	var scale: float = 0.0
	var breathe_phase: float = 0.0

var npcs: Dictionary = {}  # id → NPCData

# Board 引用
var _board: Board = null

# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

func set_board(board: Board) -> void:
	_board = board

## 放置 NPC
func spawn_npc(id: String, npc_name: String, row: int, col: int,
		tex_path: String, dialogue_script: Array) -> void:
	if npcs.has(id):
		remove_npc(id)

	var npc := NPCData.new()
	npc.id = id
	npc.npc_name = npc_name
	npc.row = row
	npc.col = col
	npc.tex_path = tex_path
	npc.dialogue_script = dialogue_script
	npc.alpha = 0.0
	npc.scale = 0.0
	npc.breathe_phase = randf() * TAU
	npcs[id] = npc
	# 弹出动画由 main.gd tween 驱动 npc.scale/alpha

## 移除指定 NPC
func remove_npc(id: String) -> void:
	npcs.erase(id)

## 清除全部 NPC
func clear() -> void:
	npcs.clear()

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
