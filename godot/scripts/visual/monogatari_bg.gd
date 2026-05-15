## MonogatariBG — 物语系列风格背景层
## 灵感：《化物语》西尾维新 × SHAFT 动画风格
## 功能：
##   - 漂浮的线框几何体（立方体、十字、圆环）在背景深处随机移动
##   - 巨大的带阴影关键词文字（当天剧情相关词汇）
##   - 随明/暗面状态在黑白配色间切换
##   - 每天切换时通过 set_day() 更新文字内容
extends Node2D

# ---------------------------------------------------------------------------
# 剧情文字内容表 — 按天数设计，来源于对话关键词
# ---------------------------------------------------------------------------
## 每天显示 3~5 个关键词，混搭日文片假名增加异质感
const DAY_WORDS: Dictionary = {
	1: ["衣柜", "ク", "泡面", "31.230°N", "眼泪"],
	2: ["雷", "夢", "暗面", "碎片", "121.473°E"],
	3: ["冷冻", "追随", "平板", "不会丢", "跟随"],
	4: ["训练", "影", "別逃", "跑", "雾"],
	5: ["控制", "ロック", "锁", "不安全", "保护"],
	6: ["镜子", "另一个", "陌生", "我是谁", "鏡"],
	7: ["唐棱", "揭示", "前世", "タング", "记忆"],
	8: ["裂隙", "暗面都市", "入口", "深渊", "亀裂"],
	9: ["一千年", "等待", "マタ", "孤独", "守护"],
	10: ["信任", "距离", "心跳", "温热", "もっと"],
	11: ["契约", "代价", "ケイヤク", "灵魂", "绑定"],
	12: ["消散", "凋落", "さよなら", "叶", "最后"],
	13: ["归来", "帰還", "月光", "相认", "另一面"],
	14: ["结局", "选择", "エンド", "此刻", "永远"],
}

## 默认（加载前/超出天数时）显示的词汇
const DEFAULT_WORDS: Array[String] = ["暗面", "都市", "夢", "蟹", "蜗牛"]

# ---------------------------------------------------------------------------
# 几何体定义
# ---------------------------------------------------------------------------
enum ShapeType { CUBE_WIRE, CROSS, CIRCLE_RING, TRIANGLE }
const SHAPE_TYPE_COUNT: int = 4  # ShapeType 的枚举数量（enum 无 .size()）

const SHAPE_COUNT: int = 14  # 同屏漂浮几何体数量
const WORD_COUNT: int = 5    # 同屏文字数量

# ---------------------------------------------------------------------------
# 配色方案 — 明面 / 暗面
# ---------------------------------------------------------------------------
## 明面：白底黑字，几何体深灰线条
const COLOR_BRIGHT_BG:    Color = Color(0.96, 0.95, 0.92, 0.0)   # 完全透明（由 3D 背景决定）
const COLOR_BRIGHT_SHAPE: Color = Color(0.15, 0.13, 0.12, 0.18)  # 深墨色线条，半透明
const COLOR_BRIGHT_TEXT:  Color = Color(0.08, 0.06, 0.06, 0.22)  # 深色文字，低饱和
const COLOR_BRIGHT_SHADOW:Color = Color(0.85, 0.82, 0.78, 0.10)  # 浅暖阴影

## 暗面：黑底白字，几何体冷紫/白线条
const COLOR_DARK_SHAPE:  Color = Color(0.72, 0.68, 0.88, 0.20)   # 冷紫线条
const COLOR_DARK_TEXT:   Color = Color(0.88, 0.85, 0.95, 0.28)   # 白紫文字
const COLOR_DARK_SHADOW: Color = Color(0.25, 0.18, 0.38, 0.18)   # 深紫阴影

# ---------------------------------------------------------------------------
# 运行时数据
# ---------------------------------------------------------------------------
var _shapes: Array[Dictionary] = []     # 几何体运行时数据
var _words:  Array[Dictionary] = []     # 文字运行时数据

var _current_day: int = 1
var _dark_t: float = 0.0               # 0.0=明面 1.0=暗面，由外部插值赋值

var _time: float = 0.0
var _font: Font = null

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	z_index = -10          # 渲染在所有 UI 后面，棋盘前面

	# 加载字体（引擎内置 fallback）
	_font = ThemeDB.fallback_font

	_init_shapes()
	_init_words()


func _get_vp_size() -> Vector2:
	if is_inside_tree() and get_viewport():
		return get_viewport().get_visible_rect().size
	return Vector2(1280, 720)


## 初始化漂浮几何体
func _init_shapes() -> void:
	_shapes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var vp_size: Vector2 = _get_vp_size()

	for i in range(SHAPE_COUNT):
		var shape_type: int = rng.randi_range(0, SHAPE_TYPE_COUNT - 1)
		var size: float = rng.randf_range(30.0, 130.0)
		var pos: Vector2 = Vector2(
			rng.randf_range(-size, vp_size.x + size),
			rng.randf_range(-size, vp_size.y + size)
		)
		var speed: Vector2 = Vector2(
			rng.randf_range(-8.0, 8.0),
			rng.randf_range(-12.0, -3.0)   # 总体向上漂浮
		)
		var rot_speed: float = rng.randf_range(-0.15, 0.15)
		var phase: float = rng.randf_range(0.0, TAU)
		var bob_amp: float = rng.randf_range(3.0, 12.0)
		var bob_freq: float = rng.randf_range(0.3, 0.8)

		_shapes.append({
			"type": shape_type,
			"size": size,
			"pos": pos,
			"speed": speed,
			"rot": rng.randf_range(0.0, TAU),
			"rot_speed": rot_speed,
			"phase": phase,
			"bob_amp": bob_amp,
			"bob_freq": bob_freq,
			"alpha_phase": rng.randf_range(0.0, TAU),
			"alpha_freq": rng.randf_range(0.2, 0.6),
		})


## 初始化漂浮文字
func _init_words() -> void:
	_words.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 137

	var vp_size: Vector2 = _get_vp_size()
	var word_list: Array = _get_day_words()

	for i in range(WORD_COUNT):
		var word: String = word_list[i % word_list.size()]
		var font_size: int = rng.randi_range(48, 140)
		var pos: Vector2 = Vector2(
			rng.randf_range(0.0, vp_size.x),
			rng.randf_range(0.0, vp_size.y)
		)
		var speed: Vector2 = Vector2(
			rng.randf_range(-5.0, 5.0),
			rng.randf_range(-10.0, -2.0)
		)
		var phase: float = rng.randf_range(0.0, TAU)

		_words.append({
			"text": word,
			"font_size": font_size,
			"pos": pos,
			"speed": speed,
			"phase": phase,
			"bob_amp": rng.randf_range(4.0, 16.0),
			"bob_freq": rng.randf_range(0.25, 0.55),
			"rot": rng.randf_range(-0.15, 0.15),
			"alpha_phase": rng.randf_range(0.0, TAU),
		})


func _get_day_words() -> Array:
	if DAY_WORDS.has(_current_day):
		return DAY_WORDS[_current_day]
	return DEFAULT_WORDS


# ---------------------------------------------------------------------------
# 公开接口
# ---------------------------------------------------------------------------

## 外部调用：切换天数（更新文字内容）
func set_day(day: int) -> void:
	_current_day = day
	# 重新初始化文字（保留几何体）
	_init_words()
	queue_redraw()


## 外部调用：设置明/暗面插值 (0.0~1.0)
func set_dark_transition(t: float) -> void:
	_dark_t = t
	queue_redraw()


# ---------------------------------------------------------------------------
# 更新 & 重绘
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var vp_size: Vector2 = _get_vp_size()

	# 更新几何体位置
	for sh in _shapes:
		sh["rot"] += sh["rot_speed"] * delta
		var bob: float = sin(_time * sh["bob_freq"] * TAU + sh["phase"]) * sh["bob_amp"]
		sh["pos"] += sh["speed"] * delta
		sh["pos"].y += bob * delta

		# 超出屏幕则回卷到对面
		if sh["pos"].y < -sh["size"] - 20.0:
			sh["pos"].y = vp_size.y + sh["size"] + 20.0
			sh["pos"].x = randf_range(-sh["size"], vp_size.x + sh["size"])
		if sh["pos"].x < -sh["size"] - 100.0:
			sh["pos"].x = vp_size.x + sh["size"]
		elif sh["pos"].x > vp_size.x + sh["size"] + 100.0:
			sh["pos"].x = -sh["size"]

	# 更新文字位置
	for wd in _words:
		var bob: float = sin(_time * wd["bob_freq"] * TAU + wd["phase"]) * wd["bob_amp"]
		wd["pos"] += wd["speed"] * delta
		wd["pos"].y += bob * delta

		if wd["pos"].y < -200.0:
			wd["pos"].y = vp_size.y + 100.0
			wd["pos"].x = randf_range(0.0, vp_size.x)
		if wd["pos"].x < -200.0:
			wd["pos"].x = vp_size.x + 100.0
		elif wd["pos"].x > vp_size.x + 200.0:
			wd["pos"].x = -100.0

	queue_redraw()


func _draw() -> void:
	_draw_shapes()
	_draw_words()


# ---------------------------------------------------------------------------
# 绘制几何体
# ---------------------------------------------------------------------------

func _get_shape_color() -> Color:
	return COLOR_BRIGHT_SHAPE.lerp(COLOR_DARK_SHAPE, _dark_t)


func _draw_shapes() -> void:
	var c: Color = _get_shape_color()
	for sh in _shapes:
		# 基于相位调制 alpha（呼吸感）
		var a_mod: float = 0.7 + 0.3 * sin(_time * sh["alpha_freq"] * TAU + sh["alpha_phase"])
		var col: Color = Color(c.r, c.g, c.b, c.a * a_mod)

		draw_set_transform(sh["pos"], sh["rot"], Vector2.ONE)

		match sh["type"]:
			ShapeType.CUBE_WIRE:
				_draw_cube_wire(sh["size"], col)
			ShapeType.CROSS:
				_draw_cross(sh["size"], col)
			ShapeType.CIRCLE_RING:
				_draw_circle_ring(sh["size"], col)
			ShapeType.TRIANGLE:
				_draw_triangle_wire(sh["size"], col)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 线框立方体（正投影，错位两矩形模拟 3D）
func _draw_cube_wire(size: float, col: Color) -> void:
	var h: float = size * 0.5
	var off: float = size * 0.22     # 背面偏移
	var w: float = 1.5               # 线宽

	# 前面
	_draw_rect_wire(Vector2(-h, -h), Vector2(h, h), col, w)
	# 背面（右上偏移）
	_draw_rect_wire(Vector2(-h + off, -h - off), Vector2(h + off, h - off), col, w)
	# 连线（四角连接前后面）
	draw_line(Vector2(-h, -h), Vector2(-h + off, -h - off), col, w)
	draw_line(Vector2(h, -h),  Vector2(h + off,  -h - off), col, w)
	draw_line(Vector2(h,  h),  Vector2(h + off,   h - off), col, w)
	draw_line(Vector2(-h, h),  Vector2(-h + off,  h - off), col, w)


func _draw_rect_wire(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(Vector2(a.x, a.y), Vector2(b.x, a.y), col, w)
	draw_line(Vector2(b.x, a.y), Vector2(b.x, b.y), col, w)
	draw_line(Vector2(b.x, b.y), Vector2(a.x, b.y), col, w)
	draw_line(Vector2(a.x, b.y), Vector2(a.x, a.y), col, w)


## 十字架（长+短交叉）
func _draw_cross(size: float, col: Color) -> void:
	var long_h: float = size * 0.9
	var short_h: float = size * 0.35
	var short_y: float = -size * 0.25   # 短横在上方 1/4 处
	var w: float = maxf(1.5, size * 0.06)
	# 竖线
	draw_line(Vector2(0, -long_h), Vector2(0, long_h), col, w)
	# 横线
	draw_line(Vector2(-short_h, short_y), Vector2(short_h, short_y), col, w)


## 圆环（两个同心圆）
func _draw_circle_ring(size: float, col: Color) -> void:
	var w: float = maxf(1.0, size * 0.05)
	draw_arc(Vector2.ZERO, size, 0.0, TAU, 48, col, w)
	draw_arc(Vector2.ZERO, size * 0.62, 0.0, TAU, 36, col, w * 0.7)


## 线框等边三角形
func _draw_triangle_wire(size: float, col: Color) -> void:
	var h: float = size * 0.866
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(0, -size * 0.667),
		Vector2(size * 0.5, h * 0.333),
		Vector2(-size * 0.5, h * 0.333),
	])
	var w: float = maxf(1.5, size * 0.05)
	draw_line(pts[0], pts[1], col, w)
	draw_line(pts[1], pts[2], col, w)
	draw_line(pts[2], pts[0], col, w)


# ---------------------------------------------------------------------------
# 绘制文字
# ---------------------------------------------------------------------------

func _draw_words() -> void:
	if _font == null:
		return

	var text_col:   Color = COLOR_BRIGHT_TEXT.lerp(COLOR_DARK_TEXT, _dark_t)
	var shadow_col: Color = COLOR_BRIGHT_SHADOW.lerp(COLOR_DARK_SHADOW, _dark_t)

	for wd in _words:
		var fs: int = wd["font_size"]
		var pos: Vector2 = wd["pos"]
		var a_mod: float = 0.6 + 0.4 * sin(_time * 0.4 + wd["alpha_phase"])

		var t_col: Color = Color(text_col.r, text_col.g, text_col.b, text_col.a * a_mod)
		var s_col: Color = Color(shadow_col.r, shadow_col.g, shadow_col.b, shadow_col.a * a_mod)

		# 阴影层（偏移 4px 绘制两次增强厚度）
		var shadow_offset: Vector2 = Vector2(4, 5)
		draw_string(_font, pos + shadow_offset * 1.5, wd["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, s_col)
		draw_string(_font, pos + shadow_offset, wd["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, s_col)
		# 主文字
		draw_string(_font, pos, wd["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, t_col)
