## BoardItems - 棋盘道具系统
## 对应原版 BoardItems.lua
## 每回合在地图上放置 1~3 个可拾取道具，玩家走到格子上后拾取
## Godot 2D: 使用 Sprite2D 显示道具图标，浮动动画
class_name BoardItems
extends RefCounted

# ---------------------------------------------------------------------------
# 道具池定义 (key, 权重, 拾取效果描述)
# ---------------------------------------------------------------------------
const ITEM_POOL: Array = [
	{ "key": "coffee",    "weight": 25, "label": "咖啡",     "icon": "☕" },
	{ "key": "film",      "weight": 20, "label": "胶卷",     "icon": "🎞️" },
	{ "key": "shield",    "weight": 15, "label": "护身符",   "icon": "🧿" },
	{ "key": "exorcism",  "weight": 15, "label": "驱魔香",   "icon": "🪔" },
	{ "key": "mapReveal", "weight": 25, "label": "地图碎片", "icon": "🗺️" },
]

# 道具图标绘制参数 (2D overlay 保留兼容)
const ICON_SIZE: float = 20.0
const FLOAT_AMP: float = 2.0
const FLOAT_SPEED: float = 2.2
const GLOW_RADIUS: float = 14.0

# 3D Billboard 参数 (匹配 Lua BoardItems)
const ITEM_SIZE_3D: float = 0.22
const ITEM_BASE_Y_3D: float = 0.35
const FLOAT_AMP_3D: float = 0.025
const FLOAT_SPEED_3D: float = 2.2

# 道具贴图路径映射
const ICON_TEXTURES: Dictionary = {
	"coffee":    "res://assets/image/道具_咖啡v2_20260426153856.png",
	"film":      "res://assets/image/道具_胶卷v2_20260426153757.png",
	"shield":    "res://assets/image/道具_护身符v2_20260426153859.png",
	"exorcism":  "res://assets/image/道具_驱魔香v2_20260426153756.png",
	"mapReveal": "res://assets/image/道具_地图碎片v2_20260426153808.png",
}

# ---------------------------------------------------------------------------
# 道具实例
# ---------------------------------------------------------------------------

## 单个道具数据
class BoardItem:
	var key: String         # 道具 key
	var label: String       # 显示名
	var icon: String        # emoji 图标
	var row: int            # 所在行
	var col: int            # 所在列
	var collected: bool = false
	var phase: float        # 浮动相位
	var scale: float = 0.0  # 当前缩放 (弹出动画)
	var alpha: float = 0.0  # 当前透明度
	var glow_alpha: float = 0.0

var items: Array = []  # Array of BoardItem

# ---------------------------------------------------------------------------
# 工具: 按权重随机选取道具
# ---------------------------------------------------------------------------

static func _random_item_entry() -> Dictionary:
	var total_w: int = 0
	for entry in ITEM_POOL:
		total_w += int(entry["weight"])
	var roll: int = randi_range(1, total_w)
	var acc: int = 0
	for entry in ITEM_POOL:
		acc += int(entry["weight"])
		if roll <= acc:
			return entry
	return ITEM_POOL[0]

static func get_pool_entry(key: String) -> Dictionary:
	for entry in ITEM_POOL:
		if entry["key"] == key:
			return entry
	return {}

# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

## 清除所有地图道具
func clear() -> void:
	items.clear()

## 每回合放置道具
func spawn_daily(board: Board, exclude_row: int, exclude_col: int) -> void:
	clear()

	# 收集可放置的格子 (排除家、地标、商店)
	var candidates: Array = []
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			if r == exclude_row and c == exclude_col:
				continue
			var card: Card = board.get_card(r, c)
			if card and card.type != "home" and card.type != "landmark" and card.type != "shop":
				candidates.append({ "r": r, "c": c })

	# 打乱候选格子
	candidates.shuffle()

	# 放置 1~3 个道具
	var count: int = mini(randi_range(1, 3), candidates.size())

	for i in range(count):
		var pos: Dictionary = candidates[i]
		var entry: Dictionary = _random_item_entry()

		var item: BoardItem = BoardItem.new()
		item.key = entry["key"]
		item.label = entry["label"]
		item.icon = entry["icon"]
		item.row = pos["r"]
		item.col = pos["c"]
		item.phase = randf() * TAU
		item.scale = 0.0
		item.alpha = 0.0
		item.glow_alpha = 0.0
		items.append(item)

	# 弹出动画: 由 main.gd 的 tween 驱动
	# 这里只设置初始值，main.gd 负责 tween item.scale/alpha/glow_alpha

## 检测玩家到达格子时是否有道具可拾取
func try_collect(row: int, col: int) -> Dictionary:
	for i in range(items.size()):
		var item: BoardItem = items[i]
		if not item.collected and item.row == row and item.col == col:
			item.collected = true
			# 返回道具信息 (由 main.gd 驱动收集动画和效果)
			return {
				"key": item.key,
				"label": item.label,
				"icon": item.icon,
				"index": i,
			}
	return {}

## 获取当前活跃道具数量
func get_active_count() -> int:
	var count: int = 0
	for item in items:
		if not item.collected:
			count += 1
	return count
