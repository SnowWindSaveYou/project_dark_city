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
@onready var _btn_vbox: VBoxContainer   = $TitleBlock/ButtonBlock
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

# ---------------------------------------------------------------------------
# _ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	_set_white_bg()

	# 逐字标题（替换 tscn 里的 TitleLarge Label）
	_build_title_chars()

	_title_en.add_theme_color_override("font_color", C_SUBTITLE)
	_coord_label.add_theme_color_override("font_color", C_COORD)
	_ver_label.add_theme_color_override("font_color", C_VERSION)

	_style_btn_primary(_btn_start)
	_style_btn_secondary(_btn_gallery)
	_style_btn_secondary(_btn_settings)
	_style_btn_quit(_btn_quit)

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
	_btn_vbox.modulate.a    = 0.0
	_btn_vbox.position.x   -= 20.0
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

func _style_btn_primary(btn: Button) -> void:
	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = C_BTN_START_BG
	n.corner_radius_top_left = 0; n.corner_radius_top_right = 0
	n.corner_radius_bottom_left = 0; n.corner_radius_bottom_right = 0
	n.content_margin_left = 28.0
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_color_override("font_color",         Color(0.97, 0.97, 0.97))
	btn.add_theme_color_override("font_hover_color",   Color(1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	var h: StyleBoxFlat = n.duplicate(); h.bg_color = C_BTN_START_HOVER
	btn.add_theme_stylebox_override("hover", h)
	var p: StyleBoxFlat = n.duplicate(); p.bg_color = Color(0.28, 0.18, 0.48, 1.0)
	btn.add_theme_stylebox_override("pressed", p)


func _style_btn_secondary(btn: Button) -> void:
	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = C_BTN_SEC_BG
	n.border_color = C_BTN_SEC_BORDER
	n.set_border_width_all(1)
	n.corner_radius_top_left = 0; n.corner_radius_top_right = 0
	n.corner_radius_bottom_left = 0; n.corner_radius_bottom_right = 0
	n.content_margin_left = 28.0
	btn.add_theme_stylebox_override("normal", n)
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = C_BTN_SEC_HOVER_BG
	h.border_color = Color(0.35, 0.30, 0.50, 0.75)
	btn.add_theme_stylebox_override("hover", h)
	var p: StyleBoxFlat = n.duplicate(); p.bg_color = Color(0.18, 0.14, 0.28, 0.12)
	btn.add_theme_stylebox_override("pressed", p)


func _style_btn_quit(btn: Button) -> void:
	_style_btn_secondary(btn)
	var n: StyleBoxFlat = btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	n.border_color = Color(0.45, 0.14, 0.14, 0.35)
	btn.add_theme_stylebox_override("normal", n)


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
	, _btn_line_progress.get(btn, 1.0), 0.0, 0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


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

	# 按钮 hover 划线
	for btn: Button in [_btn_start, _btn_gallery, _btn_settings, _btn_quit]:
		var prog: float = _btn_line_progress.get(btn, 0.0)
		if prog <= 0.0:
			continue
		var btn_global: Vector2 = btn.global_position
		var btn_local: Vector2  = _draw_layer.get_global_transform().affine_inverse() * btn_global
		var btn_w: float = btn.size.x * prog
		var btn_y: float = btn_local.y + btn.size.y - 2.0
		_draw_layer.draw_line(
			Vector2(btn_local.x, btn_y),
			Vector2(btn_local.x + btn_w, btn_y),
			Color(C_TITLE.r, C_TITLE.g, C_TITLE.b, 0.55), 1.5)


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

	# 按钮组（0.55s 瞬现 + 横向滑入）
	var t4: Tween = create_tween()
	t4.tween_interval(0.55)
	t4.set_parallel(false)
	t4.tween_callback(func() -> void: _btn_vbox.modulate.a = 1.0)
	t4.set_parallel(true)
	t4.tween_property(_btn_vbox, "position:x",
		_btn_vbox.position.x + 20.0, 0.20) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	t4.tween_callback(func() -> void: _enter_done = true)

	# 超时保底
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if not _enter_done:
			for lbl in _title_chars: lbl.modulate.a = 1.0
			_title_en.modulate.a    = 1.0
			_coord_label.modulate.a = 1.0
			_btn_vbox.modulate.a    = 1.0
			_baiye_sprite.modulate.a = 1.0
			_line_progress = 1.0
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

	_draw_layer.queue_redraw()


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

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 560)
	panel.set_anchors_preset(Control.PRESET_CENTER)

	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color = Color(0.97, 0.97, 0.97, 0.98)
	ps.border_color = Color(0.20, 0.18, 0.30, 0.55)
	ps.set_border_width_all(1)
	ps.corner_radius_top_left    = 0; ps.corner_radius_top_right    = 0
	ps.corner_radius_bottom_left = 0; ps.corner_radius_bottom_right = 0
	ps.content_margin_left = 40.0; ps.content_margin_right  = 40.0
	ps.content_margin_top  = 36.0; ps.content_margin_bottom = 36.0
	panel.add_theme_stylebox_override("panel", ps)
	root.add_child(panel)

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
	var panel: PanelContainer = _gallery_overlay.get_child(1) as PanelContainer
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
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await get_tree().create_timer(0.32).timeout
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
