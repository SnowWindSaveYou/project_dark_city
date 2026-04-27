## MonsterGhost - 怪物 Chibi 弹出浮动系统
## 对应原版 MonsterGhost.lua
## 踩到怪物牌时小怪物们环绕玩家弹出浮动
## 拍摄鉴定怪物时在卡牌上方显示怪物 Chibi
## Godot 2D: 使用 _draw() 绘制纹理
class_name MonsterGhost
extends RefCounted

# ---------------------------------------------------------------------------
# 怪物 Chibi 贴图映射 (地点 → 主怪物贴图)
# ---------------------------------------------------------------------------
const MONSTER_CHIBI := {
	"company":  "res://assets/image/怪物_无脸商人_20260426071011.png",
	"school":   "res://assets/image/怪物_长发女鬼v2_20260426072646.png",
	"park":     "res://assets/image/怪物_双尾猫妖v3_20260426071805.png",
	"alley":    "res://assets/image/怪物_幽灵娘v3_20260426072315.png",
	"station":  "res://assets/image/怪物_小幽灵_20260426072511.png",
	"hospital": "res://assets/image/怪物_幽灵娘v3_20260426072315.png",
	"library":  "res://assets/image/怪物_长发女鬼v2_20260426072646.png",
	"bank":     "res://assets/image/edited_怪物_面具使v3_20260426073034.png",
}
const DEFAULT_MONSTER := "res://assets/image/怪物_小幽灵_20260426072511.png"

# 小幽灵表情变体 (随机伴生)
const GHOST_VARIANTS := [
	"res://assets/image/小幽灵_愤怒v2_20260426073743.png",
	"res://assets/image/小幽灵_开心v2_20260426073756.png",
	"res://assets/image/小幽灵_狡猾v2_20260426073758.png",
	"res://assets/image/小幽灵_委屈v2_20260426073907.png",
	"res://assets/image/小幽灵_瞌睡v2_20260426073910.png",
	"res://assets/image/怪物_小幽灵_20260426072511.png",
]

# ---------------------------------------------------------------------------
# 环绕布局定义 (相对玩家的偏移)
# ---------------------------------------------------------------------------
const SURROUND_LAYOUT: Array = [
	# 主怪物: 正上方偏大
	{ "dx":   0.0, "dy": -50.0, "size": 36.0, "is_main": true },
	# 小幽灵们: 散布四周
	{ "dx": -40.0, "dy":  15.0, "size": 20.0, "is_main": false },
	{ "dx":  38.0, "dy":  -8.0, "size": 22.0, "is_main": false },
	{ "dx": -20.0, "dy": -55.0, "size": 16.0, "is_main": false },
	{ "dx":  28.0, "dy":  25.0, "size": 18.0, "is_main": false },
]

# ---------------------------------------------------------------------------
# 幽灵数据
# ---------------------------------------------------------------------------

class GhostSprite:
	var tex_path: String
	var anchor_x: float    # 锚定位置 (像素)
	var anchor_y: float
	var phase: float       # 浮动相位
	var base_y: float      # 基础 Y 偏移
	var size: float        # 目标尺寸 (像素)
	var scale: float = 0.0 # 当前缩放 (弹出动画)
	var alpha: float = 0.0 # 当前透明度
	var lifetime: float = -1.0  # -1 = 不自动消失
	var is_main: bool = false

var surround_ghosts: Array = []  # 环绕玩家的幽灵
var card_ghosts: Array = []      # 卡牌上的怪物 chibi
var trail_ghosts: Array = []     # 踪迹箭头

# 纹理缓存
var _tex_cache: Dictionary = {}

# ---------------------------------------------------------------------------
# 纹理加载
# ---------------------------------------------------------------------------

func _load_texture(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			_tex_cache[path] = tex
			return tex
	return null

# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

func clear_surround() -> void:
	surround_ghosts.clear()

func clear_card_ghosts() -> void:
	card_ghosts.clear()

func clear_trail_ghosts() -> void:
	trail_ghosts.clear()

func clear() -> void:
	clear_surround()
	clear_card_ghosts()
	clear_trail_ghosts()

## 踩到怪物牌时: 在玩家周围弹出怪物 chibi
func spawn_around_player(screen_x: float, screen_y: float, location: String) -> void:
	clear_surround()
	var main_tex_path: String = MONSTER_CHIBI.get(location, DEFAULT_MONSTER)

	for i in range(SURROUND_LAYOUT.size()):
		var slot: Dictionary = SURROUND_LAYOUT[i]
		var ghost := GhostSprite.new()

		if slot.get("is_main", false):
			ghost.tex_path = main_tex_path
			ghost.is_main = true
		else:
			ghost.tex_path = GHOST_VARIANTS[randi_range(0, GHOST_VARIANTS.size() - 1)]

		ghost.anchor_x = screen_x + slot["dx"]
		ghost.anchor_y = screen_y + slot["dy"]
		ghost.base_y = slot["dy"]
		ghost.size = slot["size"]
		ghost.phase = float(i) * 1.3 + randf() * 0.5
		ghost.scale = 0.0
		ghost.alpha = 0.0
		ghost.lifetime = -1.0  # 由外部调用 clear_surround() 清除
		surround_ghosts.append(ghost)

	# 弹出动画由 main.gd tween 驱动 ghost.scale/alpha

## 在卡牌上方显示怪物 chibi (拍摄鉴定后)
func show_on_card(card_screen_x: float, card_screen_y: float, location: String) -> void:
	var tex_path: String = MONSTER_CHIBI.get(location, DEFAULT_MONSTER)
	var ghost := GhostSprite.new()
	ghost.tex_path = tex_path
	ghost.anchor_x = card_screen_x
	ghost.anchor_y = card_screen_y - 40.0  # 卡牌上方
	ghost.base_y = -40.0
	ghost.size = 32.0
	ghost.phase = randf() * TAU
	ghost.lifetime = -1.0
	card_ghosts.append(ghost)
	# 弹出动画由 main.gd 驱动

## 相机模式: 显示所有已侦测的怪物卡牌 chibi
func show_on_scouted_cards(board: Board, card_screen_positions: Dictionary) -> void:
	clear_card_ghosts()
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = board.get_card(r, c)
			if card and card.scouted and card.type == "monster":
				var key := "%d,%d" % [r, c]
				if card_screen_positions.has(key):
					var pos: Vector2 = card_screen_positions[key]
					var ghost := GhostSprite.new()
					ghost.tex_path = MONSTER_CHIBI.get(card.location, DEFAULT_MONSTER)
					ghost.anchor_x = pos.x
					ghost.anchor_y = pos.y - 35.0
					ghost.base_y = -35.0
					ghost.size = 28.0
					ghost.phase = randf() * TAU
					ghost.scale = 0.0
					ghost.alpha = 0.0
					ghost.lifetime = -1.0
					card_ghosts.append(ghost)

## 计算并记录踪迹方向到卡牌数据上
func calculate_trail(card: Card, board: Board) -> bool:
	var mr := -1
	var mc := -1
	var best_dist := 999.0

	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			if r == card.row and c == card.col:
				continue
			var cd: Card = board.get_card(r, c)
			if cd and cd.type == "monster" and not cd.face_up:
				if not board.is_in_landmark_aura(r, c):
					var dr := float(r - card.row)
					var dc := float(c - card.col)
					var dist := sqrt(dr * dr + dc * dc)
					if dist < best_dist:
						mr = r
						mc = c
						best_dist = dist

	if mr < 0:
		card.trail_dir_x = 0.0
		card.trail_dir_y = 0.0
		return false

	card.trail_dir_x = float(mc - card.col)
	card.trail_dir_y = float(mr - card.row)
	return true

## 显示踪迹箭头 (小幽灵指向最近怪物)
func show_trail_on_card(card_screen_x: float, card_screen_y: float, dir_x: float, dir_y: float) -> void:
	var tex_path: String = GHOST_VARIANTS[randi_range(0, GHOST_VARIANTS.size() - 1)]
	var len := sqrt(dir_x * dir_x + dir_y * dir_y)
	var offset_x := 0.0
	var offset_y := 0.0
	if len > 0.001:
		offset_x = (dir_x / len) * 30.0  # 偏移到卡牌边缘
		offset_y = (dir_y / len) * 30.0

	var ghost := GhostSprite.new()
	ghost.tex_path = tex_path
	ghost.anchor_x = card_screen_x + offset_x
	ghost.anchor_y = card_screen_y + offset_y
	ghost.base_y = 0.0
	ghost.size = 16.0
	ghost.phase = randf() * TAU
	ghost.scale = 0.0
	ghost.alpha = 0.0
	ghost.lifetime = -1.0
	trail_ghosts.append(ghost)

## 显示所有已记录的踪迹箭头
func show_trails_on_board(board: Board, card_screen_positions: Dictionary) -> void:
	clear_trail_ghosts()
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = board.get_card(r, c)
			if card and card.trail_dir_x != 0.0 and card.trail_dir_y != 0.0:
				var key := "%d,%d" % [r, c]
				if card_screen_positions.has(key):
					var pos: Vector2 = card_screen_positions[key]
					show_trail_on_card(pos.x, pos.y, card.trail_dir_x, card.trail_dir_y)

# ---------------------------------------------------------------------------
# 每帧更新
# ---------------------------------------------------------------------------

func update(dt: float, game_time: float) -> void:
	# 环绕幽灵: 浮动 + 生命周期
	var i := 0
	while i < surround_ghosts.size():
		var g: GhostSprite = surround_ghosts[i]
		if g.lifetime > 0:
			g.lifetime -= dt
			if g.lifetime <= 0.8 and g.alpha > 0:
				if g.lifetime <= 0:
					surround_ghosts.remove_at(i)
					continue
				else:
					g.alpha = maxf(0.0, g.lifetime / 0.8)
		i += 1

	# 卡牌 chibi / 踪迹 不做 lifetime 管理 (由外部 clear)

## 获取地点对应的怪物贴图路径
static func get_monster_texture(location: String) -> String:
	return MONSTER_CHIBI.get(location, DEFAULT_MONSTER)
