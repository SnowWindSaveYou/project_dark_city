## TitleScreen (Scene 版) — 标题画面
## 混合架构: 浮动卡牌保留 _draw()，标题/副标题/提示使用 Label 节点
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal start_requested

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const FLOAT_CARD_COUNT: int = 12
const CARD_ICONS: Array = ["🏠", "👻", "⚡", "💎", "📖", "🔍", "🛒", "📸", "⛪"]

# ---------------------------------------------------------------------------
# 节点引用
# ---------------------------------------------------------------------------
@onready var _overlay: ColorRect = $Overlay
@onready var _floating_cards: Control = $FloatingCards
@onready var _glow_circle: Control = $GlowCircle
@onready var _title_label: Label = $TitleLabel
@onready var _subtitle_label: Label = $SubtitleLabel
@onready var _prompt_label: Label = $PromptLabel

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
enum Phase { NONE, ENTER, IDLE, EXIT }
var _phase: Phase = Phase.NONE

## 浮动卡牌数据
var _cards_data: Array[Dictionary] = []

## 计时
var _game_time: float = 0.0

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	visible = false
	set_process(false)
	set_process_input(false)

	# 浮动卡牌使用 _draw()
	_floating_cards.draw.connect(_draw_floating_cards)

	# 光晕使用 _draw()
	_glow_circle.draw.connect(_draw_glow)

	# 初始隐藏所有子元素
	_overlay.modulate.a = 0.0
	_title_label.modulate.a = 0.0
	_title_label.scale = Vector2(0.6, 0.6)
	_subtitle_label.modulate.a = 0.0
	_prompt_label.modulate.a = 0.0
	_glow_circle.modulate.a = 0.0

	# 标题色
	_title_label.add_theme_color_override("font_color", GameTheme.accent)
	# 副标题色
	_subtitle_label.add_theme_color_override("font_color",
		Color(GameTheme.text_secondary, 0.7))
	# 提示文字色
	_prompt_label.add_theme_color_override("font_color", GameTheme.text_secondary)

	# 标题缩放锚点居中
	_title_label.pivot_offset = _title_label.size / 2.0
	_title_label.resized.connect(func():
		_title_label.pivot_offset = _title_label.size / 2.0)

# ---------------------------------------------------------------------------
# 浮动卡牌初始化
# ---------------------------------------------------------------------------

func _init_floating_cards() -> void:
	_cards_data.clear()
	for i in range(FLOAT_CARD_COUNT):
		_cards_data.append({
			"x": randf_range(-0.2, 1.2),
			"y": randf_range(-0.2, 1.2),
			"icon": CARD_ICONS[randi() % CARD_ICONS.size()],
			"rot": randf_range(0, 360),
			"speed": randf_range(0.3, 0.7),
			"phase_offset": randf_range(0, TAU),
			"font_size": randf_range(18, 28),
			"base_alpha": randf_range(20, 50) / 255.0,
		})

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func show_title() -> void:
	_phase = Phase.ENTER
	visible = true
	set_process(true)
	set_process_input(true)
	_game_time = 0.0

	# 重置状态
	_overlay.modulate.a = 1.0
	_title_label.modulate.a = 0.0
	_title_label.scale = Vector2(0.6, 0.6)
	_subtitle_label.modulate.a = 0.0
	_prompt_label.modulate.a = 0.0
	_glow_circle.modulate.a = 0.0

	_init_floating_cards()

	# === 入场动画序列 ===

	# 1. 遮罩褪到半透明
	var overlay_tw: Tween = create_tween()
	overlay_tw.tween_property(_overlay, "modulate:a", 0.55, 1.0)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 2. 标题入场（延迟 0.4s）
	var title_tw: Tween = create_tween()
	title_tw.tween_interval(0.4)
	title_tw.set_parallel(true)
	title_tw.tween_property(_title_label, "modulate:a", 1.0, 0.7)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	title_tw.tween_property(_title_label, "scale", Vector2.ONE, 0.7)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	title_tw.tween_property(_glow_circle, "modulate:a", 1.0, 0.7)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 3. 副标题（延迟 0.9s）
	var sub_tw: Tween = create_tween()
	sub_tw.tween_interval(0.9)
	sub_tw.tween_property(_subtitle_label, "modulate:a", 1.0, 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	sub_tw.tween_callback(func(): _phase = Phase.IDLE)

	# 4. 提示文字（延迟 1.3s）
	var prompt_tw: Tween = create_tween()
	prompt_tw.tween_interval(1.3)
	prompt_tw.tween_property(_prompt_label, "modulate:a", 1.0, 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

func dismiss() -> void:
	if _phase == Phase.EXIT or _phase == Phase.NONE:
		return
	_phase = Phase.EXIT

	# 同时淡出标题/副标题/提示
	var fade_tw: Tween = create_tween()
	fade_tw.set_parallel(true)
	fade_tw.tween_property(_title_label, "modulate:a", 0.0, 0.3)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fade_tw.tween_property(_title_label, "scale", Vector2(1.1, 1.1), 0.3)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fade_tw.tween_property(_subtitle_label, "modulate:a", 0.0, 0.3)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fade_tw.tween_property(_prompt_label, "modulate:a", 0.0, 0.3)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fade_tw.tween_property(_glow_circle, "modulate:a", 0.0, 0.3)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# 遮罩延迟淡出
	var overlay_tw: Tween = create_tween()
	overlay_tw.tween_interval(0.15)
	overlay_tw.tween_property(_overlay, "modulate:a", 0.0, 0.5)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	overlay_tw.tween_callback(func():
		_phase = Phase.NONE
		visible = false
		set_process(false)
		set_process_input(false)
		start_requested.emit()
	)

func is_active() -> bool:
	return _phase != Phase.NONE

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _phase != Phase.IDLE:
		return
	if event is InputEventMouseButton and event.pressed:
		dismiss()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			dismiss()
			get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	_game_time += dt

	# 提示文字呼吸动画
	if _phase == Phase.IDLE and _prompt_label.modulate.a > 0.01:
		var breathe: float = 0.5 + 0.5 * sin(_game_time * 2.5)
		_prompt_label.modulate.a = breathe

	# 重绘浮动卡牌和光晕
	_floating_cards.queue_redraw()
	_glow_circle.queue_redraw()

# ---------------------------------------------------------------------------
# 绘制: 浮动卡牌 (委托给 FloatingCards 子节点)
# ---------------------------------------------------------------------------

func _draw_floating_cards() -> void:
	if _phase == Phase.NONE:
		return

	var w: float = _floating_cards.size.x
	var h: float = _floating_cards.size.y
	var default_font: Font = ThemeDB.fallback_font

	for fc in _cards_data:
		var fx: float = fc["x"] * w
		var fy: float = fc["y"] * h
		var spd: float = fc["speed"]
		var ph: float = fc["phase_offset"]

		fx += sin(_game_time * spd + ph) * 15.0
		fy += cos(_game_time * spd * 0.7 + ph + 1.5) * 10.0

		var card_alpha: float = fc["base_alpha"] * _overlay.modulate.a

		# 卡牌背景矩形
		var card_rect: Rect2 = Rect2(fx - 20, fy - 28, 40, 56)
		_floating_cards.draw_rect(card_rect,
			Color(GameTheme.card_back.r, GameTheme.card_back.g,
				GameTheme.card_back.b, card_alpha * 0.25),
			true)

		# 卡牌图标
		if default_font:
			_floating_cards.draw_string(default_font,
				Vector2(fx - 20, fy + 6),
				fc["icon"], HORIZONTAL_ALIGNMENT_CENTER,
				40, int(fc["font_size"]),
				Color(1, 1, 1, card_alpha * 0.2))

# ---------------------------------------------------------------------------
# 绘制: 光晕 (委托给 GlowCircle 子节点)
# ---------------------------------------------------------------------------

func _draw_glow() -> void:
	if _phase == Phase.NONE:
		return
	if _title_label.modulate.a < 0.3:
		return

	var pulse: float = 0.8 + 0.2 * sin(_game_time * 1.5)
	var glow_r: float = 100.0 * pulse
	var center: Vector2 = _glow_circle.size / 2.0

	_glow_circle.draw_circle(center, glow_r,
		Color(GameTheme.accent.r, GameTheme.accent.g,
			GameTheme.accent.b, 0.1 * pulse))
