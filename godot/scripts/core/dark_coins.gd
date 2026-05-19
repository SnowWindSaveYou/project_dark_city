## DarkCoins - 暗面货币 (暗币) 3D Billboard 系统
## 对应 Lua DarkCoins.lua
## 在暗面世界中，对每个 dark_dot=true 的格子放置可拾取的水晶暗币
## 玩家走到格子时自动拾取，触发 +1 暗币资源和收集动画
class_name DarkCoins
extends RefCounted

# ---------------------------------------------------------------------------
# 常量 (与 Lua DarkCoins.lua 对齐)
# ---------------------------------------------------------------------------
const CRYSTAL_TEX: String = "res://assets/image/dark_coin_crystal_v3_20260519122446.png"

## Billboard 世界尺寸 (半尺寸, 与 Lua COIN_SIZE=0.16 一致; Godot ×2)
const COIN_SIZE: float = 0.16 * 2.0
## 基准 Y 高度
const COIN_BASE_Y: float = 0.30
## 浮动动画
const FLOAT_AMP: float = 0.04
const FLOAT_SPEED: float = 2.2
## 向相机方向偏移 (与 board_visual item_nodes 保持一致)
const CAMERA_OFFSET_Z: float = -0.18

# ---------------------------------------------------------------------------
# 单枚暗币数据
# ---------------------------------------------------------------------------
class DarkCoin:
	var row: int
	var col: int
	var collected: bool = false
	var phase: float  # 浮动相位 (随机)

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var coins: Array = []  # Array of DarkCoin

# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

## 清除所有暗币数据
func clear() -> void:
	coins.clear()

## 从当前棋盘读取 dark_dot 格子，生成暗币数组
## board: Board — 当前暗面棋盘
func spawn_from_board(board: Board) -> void:
	clear()
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card = board.get_card(r, c)
			if card and card.get("dark_dot", false):
				var coin: DarkCoin = DarkCoin.new()
				coin.row = r
				coin.col = c
				coin.phase = randf() * TAU
				coins.append(coin)

## 检测玩家到达格子时是否有暗币可拾取
## 返回 index (>=0) 表示拾取成功，-1 表示没有
func try_collect(row: int, col: int) -> int:
	for i in range(coins.size()):
		var coin: DarkCoin = coins[i]
		if not coin.collected and coin.row == row and coin.col == col:
			coin.collected = true
			return i
	return -1

## 获取当前未拾取数量
func get_active_count() -> int:
	var n: int = 0
	for coin in coins:
		if not coin.collected:
			n += 1
	return n
