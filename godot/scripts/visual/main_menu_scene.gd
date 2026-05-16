## MainMenuScene — 物语风格主菜单
##
## 动态效果：
##   - 角色上下浮动 + 微旋转
##   - 标题四字逐字瞬切入场
##   - 坐标 DAY 数字快速滚动到 0
##   - 按钮 hover 左划线
##   - 竖切线/横线「生长」入场
##   - 标题偶发字符抖动（故障美学）

extends Control

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"

const BAIYE_PATHS: Array = [
	"res://assets/image/主角_蜷缩漂浮_v4_20260516012946.png",
	"res://assets/image/白夜_chibi_20260506003802.png",  # fallback
]

# 物语配色（白底）
const C_TITLE:    Color = Color(0.04, 0.03, 0.08, 1.0)
const C_SUBTITLE: Color = Color(0.28, 0.25, 0.38, 0.85)
const C_COORD:    Color = Color(0.50, 0.46, 0.60, 0.60)
const C_VERSION:  Color = Color(0.55, 0.52, 0.62, 0.45)
const C_LINE:     Color = Color(0.18, 0.16, 0.28, 0.35)

const C_BTN_START_BG:     Color = Color(0.08, 0.06, 0.14, 1.0)
const C_BTN_START_HOVER:  Color = Color(0.18, 0.12, 0.32, 1.0)
const C_BTN_SEC_BG:       Color = Color(0.0,  0.0,  0.0,  0.0)
const C_BTN_SEC_BORDER:   Color = Color(0.22, 0.20, 0.32, 0.45)
const C_BTN_SEC_HOVER_BG: Color = Color(0.12, 0.10, 0.20, 0.08)

# ---------------------------------------------------------------------------
# 节点引用
# ---------------------------------------------------------------------------
@onready var _draw_layer: Control       = $DrawLayer
@onready var _baiye_sprite: TextureRect = $BaiYeSprite
@onready var _title_block: Control      = $TitleBlock
@onready var _title_en: Label           = $TitleBlock/TitleEn
@onready var _coord_label: Label        = $TitleBlock/CoordLabel
@onready var _btn_block: Control        = $TitleBlock/ButtonBlock
@onready var _btn_start: Button         = $TitleBlock/ButtonBlock/BtnStart
@onready var _btn_gallery: Button       = $TitleBlock/ButtonBlock/BtnGallery
@onready var _btn_settings: Button      = $TitleBlock/ButtonBlock/BtnSettings
@onready var _btn_quit: Button          = $TitleBlock/ButtonBlock/BtnQuit
@onready var _ver_label: Label          = $VersionLabel

# ---------------------------------------------------------------------------
# overlay
# ---------------------------------------------------------------------------
var _settings_overlay: Control = null
var _gallery_overlay: Control  = null

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _game_time: float    = 0.0
var _enter_done: bool    = false

# 标题四个字的 Label 列表（逐字动画用）
var _title_chars: Array[Label] = []

# 竖切线生长进度 0→1
var _line_progress: float = 0.0

# 按钮 hover 划线进度 { button: float 0→1 }
var _btn_line_progress: Dictionary = {}

# 坐标 DAY 滚动
var _coord_day: float   = 14.0   # 从14滚到0
var _coord_rolling: bool = true

# 角色浮动
var _float_time: float = 0.0
var _baiye_base_y: float = 0.0
var _baiye_base_rot: float = 0.0

# 标题偶发抖动
var _glitch_timer: float   = 0.0
var _glitch_interval: float = 10.0
var _glitch_char_idx: int   = -1
var _glitch_frames: int     = 0

# 标题颜色呼吸（周期 8s，缓慢在深色→偏紫之间来回）
var _breath_time: float = 0.0

# 按钮浮动（每个按钮独立相位，与背景文字浮动同风格）
# { btn: { phase, amp, period, base_top } }
var _btn_float: Dictionary = {}

# 扫描线（周期 6s，从标题区顶端扫到底部，持续动效）
var _scan_y: float = 0.0          # 当前扫描线 Y（归一化 0→1 相对 TitleBlock 高度）
var _scan_alpha: float = 0.0      # 扫描线透明度（入场后淡入）

# 坐标噪声扰动（入场稳定后偶发，每隔 5~9s 抖动一次经纬度数字）
var _coord_noise_timer: float  = 0.0
var _coord_noise_interval: float = 6.0
var _coord_noise_frames: int   = 0

# 右侧城市层
var _city_layer: Control = null
var _buildings: Array[Dictionary] = []

# ---------------------------------------------------------------------------
# _ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	_set_white_bg()
	_setup_city_layer()   # 右侧暗色渐变 + 楼宇剪影（在白色背景之上，立绘之下）

	# 逐字标题（替换 tscn 里的 TitleLarge Label）
	_build_title_chars()

	_title_en.add_theme_color_override("font_color", C_SUBTITLE)
	_coord_label.add_theme_color_override("font_color", C_COORD)
	_ver_label.add_theme_color_override("font_color", C_VERSION)

	# 浮动文字按钮样式
	_style_btn_floating(_btn_start,
		Color(0.06, 0.05, 0.10, 0.92), Color(0.04, 0.03, 0.08, 1.0))
	_style_btn_floating(_btn_gallery,
		Color(0.22, 0.20, 0.32, 0.75), Color(0.06, 0.05, 0.10, 0.95))
	_style_btn_floating(_btn_settings,
		Color(0.22, 0.20, 0.32, 0.75), Color(0.06, 0.05, 0.10, 0.95))
	_style_btn_floating(_btn_quit,
		Color(0.42, 0.18, 0.18, 0.70), Color(0.70, 0.14, 0.14, 0.95))

	_btn_start.pressed.connect(_on_start_pressed)
	_btn_gallery.pressed.connect(_on_gallery_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)
	_btn_quit.pressed.connect(_on_quit_pressed)

	# 按钮 hover 划线
	for btn in [_btn_start, _btn_gallery, _btn_settings, _btn_quit]:
		_btn_line_progress[btn] = 0.0
		btn.mouse_entered.connect(_on_btn_hover.bind(btn))
		btn.mouse_exited.connect(_on_btn_exit.bind(btn))

	_draw_layer.draw.connect(_draw_decorations)

	_load_baiye_sprite()

	_gallery_overlay = _build_gallery_overlay()
	add_child(_gallery_overlay)

	_settings_overlay = load("res://scenes/screens/settings.tscn").instantiate()
	_settings_overlay.close_requested.connect(func() -> void: pass)
	_settings_overlay.quit_requested.connect(_on_quit_pressed)
	add_child(_settings_overlay)

	# 入场初始状态
	for lbl in _title_chars:
		lbl.modulate.a = 0.0
	_title_en.modulate.a    = 0.0
	_coord_label.modulate.a = 0.0
	_btn_block.modulate.a   = 0.0
	_baiye_sprite.modulate.a = 0.0

	# 物语背景层
	var bg_layer: CanvasLayer = CanvasLayer.new()
	bg_layer.name  = "MonogatariBGLayer"
	bg_layer.layer = 2
	add_child(bg_layer)
	var monogatari_bg: Node = load("res://scripts/visual/monogatari_bg.gd").new()
	monogatari_bg.name = "MonogatariBG"
	bg_layer.add_child(monogatari_bg)
	monogatari_bg.set_day(1)
	monogatari_bg.set_dark_transition(0.0)

	# 随机抖动间隔
	_glitch_interval = randf_range(8.0, 14.0)

	call_deferred("_play_enter_anim")
	AudioManager.play_bgm("main")


# ---------------------------------------------------------------------------
# 逐字标题构建
# ---------------------------------------------------------------------------

func _build_title_chars() -> void:
	# 移除 tscn 里的 TitleLarge（若存在）
	var old: Node = _title_block.get_node_or_null("TitleLarge")
	if old:
		old.queue_free()

	# HBoxContainer 承载四个字，锚点定位到 14% 高度处
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.name = "TitleHBox"
	hbox.layout_mode = 1
	hbox.set_anchor(SIDE_LEFT,   0.0)
	hbox.set_anchor(SIDE_TOP,    0.14)
	hbox.set_anchor(SIDE_RIGHT,  0.9)
	hbox.set_anchor(SIDE_BOTTOM, 0.14)
	hbox.set_offset(SIDE_LEFT,   72.0)
	hbox.set_offset(SIDE_TOP,    -64.0)
	hbox.set_offset(SIDE_RIGHT,  0.0)
	hbox.set_offset(SIDE_BOTTOM, 64.0)
	hbox.add_theme_constant_override("separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_block.add_child(hbox)

	var chars: String = "暗面都市"
	for i in range(chars.length()):
		var lbl: Label = Label.new()
		lbl.name = "TitleChar%d" % i
		lbl.text = chars[i]
		lbl.add_theme_font_size_override("font_size", 112)
		lbl.add_theme_color_override("font_color", C_TITLE)
		lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		lbl.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
		hbox.add_child(lbl)
		_title_chars.append(lbl)


# ---------------------------------------------------------------------------
# 白色背景
# ---------------------------------------------------------------------------

func _set_white_bg() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.97, 0.97, 0.97, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -100
	add_child(bg)
	move_child(bg, 0)


# ---------------------------------------------------------------------------
# 城市层：右侧暗色渐变 + 楼宇剪影
# ---------------------------------------------------------------------------

func _setup_city_layer() -> void:
	# ── 暗色渐变 TextureRect（全屏，从中间到右侧渐深）
	var grad_rect: TextureRect = TextureRect.new()
	grad_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grad_rect.z_index = -80   # 白底之上，其他一切之下

	var grad: Gradient = Gradient.new()
	grad.colors  = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),          # 透明（渐变起点）
		Color(0.10, 0.10, 0.12, 0.68),       # 深冷灰（几乎无色相偏移）
	])
	grad.offsets = PackedFloat32Array([0.0, 1.0])

	var grad_tex: GradientTexture2D = GradientTexture2D.new()
	grad_tex.gradient  = grad
	grad_tex.fill      = GradientTexture2D.FILL_LINEAR
	grad_tex.fill_from = Vector2(0.58, 0.22)  # 右移：暗色从右侧 60% 处开始渗入
	grad_tex.fill_to   = Vector2(1.02, 0.90)  # 终点推到屏幕右边缘外，暗区更集中

	grad_rect.texture      = grad_tex
	grad_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(grad_rect)
	move_child(grad_rect, 1)   # 紧跟白色背景之后

	# ── 楼宇剪影绘制层（z_index 低于 BaiYeSprite，让角色浮在城市之上）
	_city_layer = Control.new()
	_city_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_city_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_city_layer.z_index = -1   # 刚好在默认层之下
	add_child(_city_layer)
	_city_layer.draw.connect(_draw_city)

	_init_buildings()
	_city_layer.queue_redraw()


func _init_buildings() -> void:
	_buildings.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20250516

	# 层0：远景小楼 — 从白区开始（x: 30%~105%），矮小稀疏
	var x: float = 0.30
	while x < 1.05:
		var bw: float = rng.randf_range(0.016, 0.038)
		var bh: float = rng.randf_range(0.04, 0.09)
		_buildings.append({ "x": x, "w": bw, "h": bh, "layer": 0 })
		x += bw + rng.randf_range(0.006, 0.018)

	# 层1：中景楼 — 从过渡区开始（x: 43%~105%），中等高度
	x = 0.43
	while x < 1.05:
		var bw: float = rng.randf_range(0.022, 0.052)
		var bh: float = rng.randf_range(0.09, 0.17)
		_buildings.append({ "x": x, "w": bw, "h": bh, "layer": 1 })
		x += bw + rng.randf_range(0.002, 0.009)

	# 层2：近景大楼 — 主要在暗色区（x: 53%~108%），高耸密集
	x = 0.53
	while x < 1.08:
		var bw: float = rng.randf_range(0.028, 0.068)
		var bh: float = rng.randf_range(0.13, 0.26)
		_buildings.append({ "x": x, "w": bw, "h": bh, "layer": 2 })
		x += bw + rng.randf_range(0.001, 0.005)


func _draw_city() -> void:
	if _city_layer == null:
		return
	var w: float = _city_layer.size.x
	var h: float = _city_layer.size.y

	# 三层从远到近依次绘制（远景先画，近景覆盖其上）
	for layer in range(3):
		for bld in _buildings:
			if bld["layer"] != layer:
				continue

			var bx: float    = bld["x"] * w
			var bw_px: float = bld["w"] * w
			var bh_px: float = bld["h"] * h
			var by: float    = h - bh_px

			# 楼中心X → 计算处于白区(0)还是暗区(1)，与渐变起点对齐（0.58起渐深）
			var cx: float   = bld["x"] + bld["w"] * 0.5
			var zone_t: float = clamp((cx - 0.55) / 0.30, 0.0, 1.0)

			# 各层在暗区的不透明度（远→近递增，整体降低避免太黑）
			var dark_alpha: Array[float] = [0.42, 0.62, 0.78]
			# 白区楼宇：浅暖灰，暗区楼宇：深冷灰（无紫色偏移）
			var fill_bright: Color = Color(0.70, 0.70, 0.72, dark_alpha[layer] * 0.22)
			var fill_dark:   Color = Color(0.20, 0.20, 0.22, dark_alpha[layer])
			var fill_col: Color    = fill_bright.lerp(fill_dark, zone_t)
			_city_layer.draw_rect(Rect2(bx, by, bw_px, bh_px), fill_col)

			# 顶部轮廓线（白区浅灰，暗区中灰边）
			var edge_bright: Color = Color(0.55, 0.55, 0.57, 0.10)
			var edge_dark:   Color = Color(0.40, 0.40, 0.44, 0.35)
			var edge_col: Color    = edge_bright.lerp(edge_dark, zone_t)
			_city_layer.draw_line(Vector2(bx, by), Vector2(bx + bw_px, by), edge_col, 1.0)


# ---------------------------------------------------------------------------
# 立绘加载
# ---------------------------------------------------------------------------

func _load_baiye_sprite() -> void:
	for path: String in BAIYE_PATHS:
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path) as Texture2D
			if tex:
				_baiye_sprite.texture = tex
				return
	_baiye_sprite.visible = false


# ---------------------------------------------------------------------------
# 按钮样式
# ---------------------------------------------------------------------------

## 统一的浮动文字按钮样式
## font_col      — 静止文字颜色
## hover_col     — hover 文字颜色
## is_quit       — 退出按钮特殊颜色
func _style_btn_floating(btn: Button,
		font_col: Color, hover_col: Color) -> void:
	# 完全透明盒子，无边框，只显示文字
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	empty.content_margin_left  = 8.0
	empty.content_margin_right = 8.0
	empty.content_margin_top   = 4.0
	empty.content_margin_bottom = 4.0
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, empty)
	btn.add_theme_color_override("font_color",         font_col)
	btn.add_theme_color_override("font_hover_color",   hover_col)
	btn.add_theme_color_override("font_pressed_color", hover_col.darkened(0.15))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = false


## 初始化所有按钮的浮动参数（在 _ready 尾部调用）
func _init_btn_floats() -> void:
	# { btn → { phase, amp, period, base_top, base_bot } }
	# base_top/base_bot 从当前 offset 读取（入场动画结束后调用，已还原到目标位置）
	var cfg: Array = [
		[_btn_start,   0.00, 7.0, 4.2],
		[_btn_gallery, 1.80, 5.5, 5.1],
		[_btn_settings,3.20, 6.0, 3.9],
		[_btn_quit,    0.90, 4.5, 4.7],
	]
	for c in cfg:
		var btn: Button = c[0]
		_btn_float[btn] = {
			"phase":    c[1],
			"amp":      c[2],
			"period":   c[3],
			"base_top": btn.offset_top,
			"base_bot": btn.offset_bottom,
		}


# _style_btn_primary / _style_btn_secondary / _style_btn_quit 已废弃，
# 保留空壳避免引用报错（实际样式由 _style_btn_floating 接管）
func _style_btn_primary(_btn: Button) -> void:   pass
func _style_btn_secondary(_btn: Button) -> void: pass
func _style_btn_quit(_btn: Button) -> void:      pass


# ---------------------------------------------------------------------------
# 按钮 hover 划线
# ---------------------------------------------------------------------------

func _on_btn_hover(btn: Button) -> void:
	_btn_line_progress[btn] = 0.0
	var tw: Tween = create_tween()
	tw.tween_method(func(v: float) -> void:
		_btn_line_progress[btn] = v
		_draw_layer.queue_redraw()
	, 0.0, 1.0, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _on_btn_exit(btn: Button) -> void:
	var tw: Tween = create_tween()
	tw.tween_method(func(v: float) -> void:
		_btn_line_progress[btn] = v
		_draw_layer.queue_redraw()
	, (_btn_line_progress[btn] if btn in _btn_line_progress else 1.0), 0.0, 0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


# ---------------------------------------------------------------------------
# 绘制：竖切线 + 横线 + 装饰 + 按钮划线
# ---------------------------------------------------------------------------

func _draw_decorations() -> void:
	var w: float = _draw_layer.size.x
	var h: float = _draw_layer.size.y

	# 竖切线（生长：从中心向两端）
	if _line_progress > 0.0:
		var lx: float    = w * 0.59
		var half_h: float = h * 0.40   # 从40%到60%，全长20%屏高
		var center_y: float = h * 0.50
		var grown: float = half_h * _line_progress
		_draw_layer.draw_line(
			Vector2(lx, center_y - grown),
			Vector2(lx, center_y + grown),
			C_LINE, 1.0)

		# 标题下横线（从左向右生长）
		var line_x_start: float = 72.0
		var line_x_end: float   = w * 0.54
		var title_y: float      = h * 0.36
		_draw_layer.draw_line(
			Vector2(line_x_start, title_y),
			Vector2(line_x_start + (line_x_end - line_x_start) * _line_progress, title_y),
			Color(C_LINE.r, C_LINE.g, C_LINE.b, C_LINE.a * 0.6), 1.0)

	# 左上装饰小字
	var font: Font = ThemeDB.fallback_font
	if font and _line_progress > 0.5:
		var alpha: float = ((_line_progress - 0.5) / 0.5) * 0.5
		_draw_layer.draw_string(font, Vector2(72.0, h * 0.14),
			"暗面都市 / DARK SIDE CITY", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 11, Color(C_COORD.r, C_COORD.g, C_COORD.b, alpha))

	# ── 按钮重影文字 + 常驻下划线 + hover 划线
	var font_draw: Font = ThemeDB.fallback_font
	var btn_list: Array[Button] = [_btn_start, _btn_gallery, _btn_settings, _btn_quit]
	for btn: Button in btn_list:
		var btn_global: Vector2 = btn.global_position
		var btn_local: Vector2  = _draw_layer.get_global_transform().affine_inverse() * btn_global
		# 文字绘制基线：按钮中心偏上
		var fs: int  = btn.get_theme_font_size("font_size")
		var text_y: float = btn_local.y + btn.size.y * 0.5 + fs * 0.35
		# 常驻下划线（静止时也存在，宽度为文字近似宽度，alpha 较低）
		var txt: String  = btn.text
		var txt_w: float = font_draw.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var ul_y: float  = text_y + 3.0
		var ul_alpha: float = 0.18
		_draw_layer.draw_line(
			Vector2(btn_local.x + 8.0, ul_y),
			Vector2(btn_local.x + 8.0 + txt_w, ul_y),
			Color(C_TITLE.r, C_TITLE.g, C_TITLE.b, ul_alpha), 1.0)
		# 重影文字（偏移 +2,+2，alpha 0.18，颜色与正文相近）
		if font_draw:
			var ghost_col: Color = Color(C_TITLE.r, C_TITLE.g, C_TITLE.b, 0.18)
			_draw_layer.draw_string(font_draw,
				Vector2(btn_local.x + 8.0 + 2.0, text_y + 2.0),
				txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ghost_col)
		# hover 划线（覆盖在下划线之上，亮度更高）
		var prog: float = _btn_line_progress[btn] if btn in _btn_line_progress else 0.0
		if prog > 0.0:
			var btn_w: float = txt_w * prog
			_draw_layer.draw_line(
				Vector2(btn_local.x + 8.0, ul_y),
				Vector2(btn_local.x + 8.0 + btn_w, ul_y),
				Color(C_TITLE.r, C_TITLE.g, C_TITLE.b, 0.65), 1.5)


# ---------------------------------------------------------------------------
# 入场动画
# ---------------------------------------------------------------------------

func _play_enter_anim() -> void:
	# 记录立绘基础位置（浮动动画用）
	_baiye_base_y   = _baiye_sprite.position.y
	_baiye_base_rot = _baiye_sprite.rotation_degrees

	# 立绘淡入
	var t0: Tween = create_tween()
	t0.set_parallel(true)
	t0.tween_property(_baiye_sprite, "modulate:a", 1.0, 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 切线生长（0.15s 延迟后 0.5s 生长）
	var t_line: Tween = create_tween()
	t_line.tween_interval(0.15)
	t_line.tween_method(func(v: float) -> void:
		_line_progress = v
		_draw_layer.queue_redraw()
	, 0.0, 1.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 标题四字逐字瞬现（每字间隔 70ms，从 0.05s 起）
	for i in range(_title_chars.size()):
		var lbl: Label = _title_chars[i]
		var delay: float = 0.05 + i * 0.07
		var tw: Tween = create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: lbl.modulate.a = 1.0)

	# 英文副标题（0.35s）
	var t2: Tween = create_tween()
	t2.tween_interval(0.35)
	t2.tween_callback(func() -> void: _title_en.modulate.a = 1.0)

	# 坐标行（0.45s 显现，同时开始数字滚动）
	var t3: Tween = create_tween()
	t3.tween_interval(0.45)
	t3.tween_callback(func() -> void:
		_coord_label.modulate.a = 1.0
		_coord_rolling = true
	)

	# 按钮逐个错落淡入（0.55s 起，每个按钮间隔 80ms，从下方 12px 上浮）
	var btns: Array[Button] = [_btn_start, _btn_gallery, _btn_settings, _btn_quit]
	for bi: int in range(btns.size()):
		var btn: Button     = btns[bi]
		var delay: float    = 0.55 + bi * 0.08
		var tw_b: Tween     = create_tween()
		tw_b.tween_interval(delay)
		tw_b.tween_callback(func() -> void:
			# 从当前位置下方 12px 处上浮进入
			btn.offset_top    += 12.0
			btn.offset_bottom += 12.0
			btn.modulate.a     = 0.0
			var tw_in: Tween = create_tween()
			tw_in.set_parallel(true)
			tw_in.tween_property(btn, "modulate:a", 1.0, 0.22) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw_in.tween_property(btn, "offset_top",
				btn.offset_top - 12.0, 0.22) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
			tw_in.tween_property(btn, "offset_bottom",
				btn.offset_bottom - 12.0, 0.22) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
		)
	# 所有按钮入场完成后标记入场结束，并初始化浮动参数
	var t4: Tween = create_tween()
	t4.tween_interval(0.55 + btns.size() * 0.08 + 0.25)
	t4.tween_callback(func() -> void:
		_btn_block.modulate.a = 1.0
		_init_btn_floats()
		_enter_done = true
	)

	# 超时保底
	get_tree().create_timer(2.5).timeout.connect(func() -> void:
		if not _enter_done:
			for lbl in _title_chars: lbl.modulate.a = 1.0
			_title_en.modulate.a     = 1.0
			_coord_label.modulate.a  = 1.0
			for btn: Button in btns: btn.modulate.a = 1.0
			_btn_block.modulate.a    = 1.0
			_baiye_sprite.modulate.a = 1.0
			_line_progress = 1.0
			_init_btn_floats()
			_enter_done = true
	)


# ---------------------------------------------------------------------------
# _process：浮动 + 坐标滚动 + 标题抖动 + 重绘
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	_game_time   += dt
	_float_time  += dt
	_breath_time += dt

	# ── 角色浮动（正弦，±18px，周期 3.5s；旋转 ±1.5°同步）
	if _baiye_sprite.visible and _baiye_sprite.texture:
		var t: float = _float_time
		_baiye_sprite.position.y       = _baiye_base_y + sin(t * TAU / 3.5) * 18.0
		_baiye_sprite.rotation_degrees = _baiye_base_rot + sin(t * TAU / 3.5 + 0.5) * 1.5

	# ── 坐标 DAY 滚动（14→0，约 0.7s）
	if _coord_rolling:
		_coord_day = move_toward(_coord_day, 0.0, dt * 22.0)
		_coord_label.text = "31.2304°N  121.4737°E  /  DAY %d" % int(_coord_day)
		if _coord_day <= 0.0:
			_coord_rolling = false
			_coord_label.text = "31.2304°N  121.4737°E  /  DAY 0"

	# ── 标题颜色呼吸（周期 8s，深近黑 ↔ 深紫，幅度温和）
	if _title_chars.size() > 0 and _enter_done:
		var phase: float = sin(_breath_time * TAU / 8.0) * 0.5 + 0.5  # 0→1
		# C_TITLE(0.04,0.03,0.08) ↔ 深紫(0.18,0.12,0.30)
		var breath_color: Color = Color(
			lerp(C_TITLE.r, 0.18, phase * 0.6),
			lerp(C_TITLE.g, 0.12, phase * 0.6),
			lerp(C_TITLE.b, 0.30, phase * 0.6),
			1.0
		)
		for lbl: Label in _title_chars:
			lbl.add_theme_color_override("font_color", breath_color)

	# ── 标题偶发抖动（使用 offset 而非 position，避免锚点节点飞移）
	_glitch_timer += dt
	if _glitch_timer >= _glitch_interval and _title_chars.size() > 0 and _enter_done:
		_glitch_timer    = 0.0
		_glitch_interval = randf_range(8.0, 14.0)
		_glitch_char_idx = randi() % _title_chars.size()
		_glitch_frames   = 3

	if _glitch_frames > 0:
		_glitch_frames -= 1
		var hbox: Control = _title_block.get_node_or_null("TitleHBox") as Control
		if hbox:
			if _glitch_frames > 0:
				# layout_mode=1 的锚点节点必须用 offset 而非 position 做位移
				hbox.offset_left = 72.0 + randf_range(-5.0, 5.0)
				hbox.offset_top  = -64.0 + randf_range(-3.0, 3.0)
			else:
				# 复位到初始 offset
				hbox.offset_left = 72.0
				hbox.offset_top  = -64.0
				_glitch_char_idx = -1

	# ── 按钮浮动（入场完成且 _btn_float 已初始化后，每帧更新 offset）
	if _enter_done and not _btn_float.is_empty():
		for btn: Button in _btn_float:
			var fp: Dictionary = _btn_float[btn]
			var drift: float = sin(_game_time / fp["period"] * TAU + fp["phase"]) * fp["amp"]
			btn.offset_top    = fp["base_top"] + drift
			btn.offset_bottom = fp["base_bot"] + drift

	# ── 坐标噪声（每 ~6s 抖动经纬度数字 4 帧）
	if _enter_done and not _coord_rolling:
		_coord_noise_timer += dt
		if _coord_noise_timer >= _coord_noise_interval:
			_coord_noise_timer = 0.0
			_coord_noise_interval = randf_range(5.0, 9.0)
			_coord_noise_frames = 4
		if _coord_noise_frames > 0:
			_coord_noise_frames -= 1
			var lat:  String = "%.4f" % (31.2304 + randf_range(-0.003, 0.003))
			var lon:  String = "%.4f" % (121.4737 + randf_range(-0.003, 0.003))
			if _coord_noise_frames == 0:
				_coord_label.text = "31.2304°N  121.4737°E  /  DAY 0"
			else:
				_coord_label.text = "%s°N  %s°E  /  DAY 0" % [lat, lon]

	_draw_layer.queue_redraw()
	if _city_layer:
		_city_layer.queue_redraw()


# ---------------------------------------------------------------------------
# 图鉴 overlay（白底物语风）
# ---------------------------------------------------------------------------

func _build_gallery_overlay() -> Control:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false

	var overlay: ColorRect = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.03, 0.02, 0.06, 0.62)
	root.add_child(overlay)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 560)

	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color = Color(0.97, 0.97, 0.97, 0.98)
	ps.border_color = Color(0.20, 0.18, 0.30, 0.55)
	ps.set_border_width_all(1)
	ps.corner_radius_top_left    = 0; ps.corner_radius_top_right    = 0
	ps.corner_radius_bottom_left = 0; ps.corner_radius_bottom_right = 0
	ps.content_margin_left = 40.0; ps.content_margin_right  = 40.0
	ps.content_margin_top  = 36.0; ps.content_margin_bottom = 36.0
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	var hdr: HBoxContainer = HBoxContainer.new()
	vbox.add_child(hdr)
	var title_lbl: Label = Label.new()
	title_lbl.text = "结局图鉴"
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", C_TITLE)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title_lbl)
	var runs_lbl: Label = Label.new()
	runs_lbl.text = "共游玩 %d 次" % SaveManager.total_runs
	runs_lbl.add_theme_font_size_override("font_size", 14)
	runs_lbl.add_theme_color_override("font_color", C_COORD)
	runs_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hdr.add_child(runs_lbl)

	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("color", Color(0.18, 0.16, 0.28, 0.25))
	vbox.add_child(sep)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	var gallery: Array = EndingSystem.get_endings_gallery(SaveManager.unlocked_endings)
	for entry: Dictionary in gallery:
		if not entry.get("id", "").begins_with("frag_"):
			grid.add_child(_build_ending_card(entry))

	var frag_unlocked: int = 0; var frag_total: int = 0
	for entry: Dictionary in gallery:
		if entry.get("id", "").begins_with("frag_"):
			frag_total += 1
			if entry.get("unlocked", false): frag_unlocked += 1

	if frag_total > 0:
		var frag_row: HBoxContainer = HBoxContainer.new()
		frag_row.add_theme_constant_override("separation", 12)
		vbox.add_child(frag_row)
		var frag_lbl: Label = Label.new()
		frag_lbl.text = "照片碎片  %d / %d" % [frag_unlocked, frag_total]
		frag_lbl.add_theme_font_size_override("font_size", 15)
		frag_lbl.add_theme_color_override("font_color", C_COORD)
		frag_row.add_child(frag_lbl)
		var prog: ProgressBar = ProgressBar.new()
		prog.min_value = 0.0; prog.max_value = float(frag_total); prog.value = float(frag_unlocked)
		prog.custom_minimum_size = Vector2(180, 18)
		prog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prog.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
		frag_row.add_child(prog)

	var close_btn: Button = Button.new()
	close_btn.text = "关  闭"
	close_btn.custom_minimum_size = Vector2(120, 42)
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.add_theme_color_override("font_color", C_TITLE)
	var cb_n: StyleBoxFlat = StyleBoxFlat.new()
	cb_n.bg_color = Color(0,0,0,0); cb_n.border_color = Color(0.18, 0.16, 0.28, 0.45)
	cb_n.set_border_width_all(1)
	cb_n.corner_radius_top_left=0; cb_n.corner_radius_top_right=0
	cb_n.corner_radius_bottom_left=0; cb_n.corner_radius_bottom_right=0
	close_btn.add_theme_stylebox_override("normal", cb_n)
	var cb_h: StyleBoxFlat = cb_n.duplicate(); cb_h.bg_color = Color(0.10,0.08,0.16,0.08)
	close_btn.add_theme_stylebox_override("hover", cb_h)
	close_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var btn_wrap: HBoxContainer = HBoxContainer.new()
	var bw_sp: Control = Control.new(); bw_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_wrap.add_child(bw_sp); btn_wrap.add_child(close_btn)
	vbox.add_child(btn_wrap)
	close_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("button_click"); _hide_gallery())

	return root


func _build_ending_card(entry: Dictionary) -> PanelContainer:
	var unlocked: bool = entry.get("unlocked", false)
	var is_vic: bool   = entry.get("is_victory", true)
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size    = Vector2(320, 80)
	card.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	var s: StyleBoxFlat = StyleBoxFlat.new()
	if unlocked:
		s.bg_color     = Color(0.94, 0.93, 0.97) if is_vic else Color(0.97, 0.93, 0.93)
		s.border_color = Color(0.38, 0.30, 0.55, 0.45) if is_vic else Color(0.65, 0.20, 0.20, 0.45)
	else:
		s.bg_color = Color(0.92, 0.92, 0.93); s.border_color = Color(0.55, 0.53, 0.58, 0.30)
	s.set_border_width_all(1)
	s.corner_radius_top_left=0; s.corner_radius_top_right=0
	s.corner_radius_bottom_left=0; s.corner_radius_bottom_right=0
	s.content_margin_left=16.0; s.content_margin_right=16.0
	s.content_margin_top=10.0; s.content_margin_bottom=10.0
	card.add_theme_stylebox_override("panel", s)
	var inner: VBoxContainer = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4); card.add_child(inner)
	var title_row: HBoxContainer = HBoxContainer.new(); inner.add_child(title_row)
	var icon_lbl: Label = Label.new()
	icon_lbl.text = "— " if unlocked else "? "
	icon_lbl.add_theme_font_size_override("font_size", 14)
	icon_lbl.add_theme_color_override("font_color",
		Color(0.38,0.30,0.55) if (unlocked and is_vic) else
		Color(0.65,0.20,0.20) if (unlocked and not is_vic) else Color(0.55,0.53,0.58))
	title_row.add_child(icon_lbl)
	var title_lbl: Label = Label.new()
	title_lbl.text = entry.get("title", "???")
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", C_TITLE if unlocked else Color(0.55,0.53,0.58))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_lbl)
	if unlocked:
		var tag: Label = Label.new()
		tag.text = "胜利" if is_vic else "失败"
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color",
			Color(0.25,0.55,0.25) if is_vic else Color(0.65,0.20,0.20))
		title_row.add_child(tag)
	var sub_lbl: Label = Label.new()
	sub_lbl.text = entry.get("subtitle","") if unlocked else "尚未解锁"
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", C_COORD if unlocked else Color(0.60,0.58,0.62))
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	inner.add_child(sub_lbl)
	return card


# ---------------------------------------------------------------------------
# 图鉴刷新
# ---------------------------------------------------------------------------

func _on_gallery_pressed() -> void:
	AudioManager.play_sfx("button_click")
	_refresh_gallery_content()
	_gallery_overlay.visible = true
	_gallery_overlay.modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(_gallery_overlay, "modulate:a", 1.0, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _hide_gallery() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(_gallery_overlay, "modulate:a", 0.0, 0.12) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void: _gallery_overlay.visible = false)


func _refresh_gallery_content() -> void:
	var center: CenterContainer = _gallery_overlay.get_child(1) as CenterContainer
	if not center: return
	var panel: PanelContainer = center.get_child(0) as PanelContainer
	if not panel: return
	var vbox: VBoxContainer = panel.get_child(0) as VBoxContainer
	if not vbox: return
	var hdr: HBoxContainer = vbox.get_child(0) as HBoxContainer
	if hdr and hdr.get_child_count() >= 2:
		var rl: Label = hdr.get_child(1) as Label
		if rl: rl.text = "共游玩 %d 次" % SaveManager.total_runs
	var scroll: ScrollContainer = vbox.get_child(2) as ScrollContainer
	if not scroll: return
	var grid: GridContainer = scroll.get_child(0) as GridContainer
	if not grid: return
	for child in grid.get_children(): child.queue_free()
	var gallery: Array = EndingSystem.get_endings_gallery(SaveManager.unlocked_endings)
	for entry: Dictionary in gallery:
		if not entry.get("id","").begins_with("frag_"):
			grid.add_child(_build_ending_card(entry))
	if vbox.get_child_count() >= 5:
		var frag_row: HBoxContainer = vbox.get_child(3) as HBoxContainer
		if frag_row:
			var fu: int = 0; var ft: int = 0
			for entry: Dictionary in gallery:
				if entry.get("id","").begins_with("frag_"):
					ft += 1
					if entry.get("unlocked", false): fu += 1
			var fl: Label = frag_row.get_child(0) as Label
			if fl: fl.text = "照片碎片  %d / %d" % [fu, ft]
			var pb: ProgressBar = frag_row.get_child(1) as ProgressBar
			if pb: pb.value = float(fu)


# ---------------------------------------------------------------------------
# 按钮事件
# ---------------------------------------------------------------------------

func _on_start_pressed() -> void:
	AudioManager.play_sfx("button_click")
	_btn_start.disabled=true; _btn_gallery.disabled=true
	_btn_settings.disabled=true; _btn_quit.disabled=true
	# 直接切换，不做淡出——main.gd 的日期切换动效会接管入场过渡
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _on_settings_pressed() -> void:
	AudioManager.play_sfx("button_click")
	_settings_overlay.show_settings()


func _on_quit_pressed() -> void:
	AudioManager.play_sfx("button_click")
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.22) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void: get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	if _settings_overlay and _settings_overlay.visible: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _gallery_overlay and _gallery_overlay.visible:
			AudioManager.play_sfx("popup_close"); _hide_gallery()
		else:
			_on_quit_pressed()
		get_viewport().set_input_as_handled()
