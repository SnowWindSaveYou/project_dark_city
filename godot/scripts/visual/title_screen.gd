## TitleScreen - 标题/开始画面
## 对应原版 TitleScreen.lua
## 氛围感入场 + 浮动卡牌 + 点击/按键开始
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal start_requested

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const FLOAT_CARD_COUNT := 12
const CARD_ICONS := ["🏠", "👻", "⚡", "💎", "📖", "🔍", "🛒", "📸", "⛪"]

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
enum Phase { NONE, ENTER, IDLE, EXIT }
var _phase := Phase.NONE

## 动画值
var _overlay_alpha := 1.0
var _title_alpha := 0.0
var _title_scale := 0.6
var _subtitle_alpha := 0.0
var _prompt_alpha := 0.0

## 浮动卡牌数据
var _floating_cards: Array[Dictionary] = []

## 计时
var _game_time := 0.0

# ---------------------------------------------------------------------------
# 浮动卡牌初始化
# ---------------------------------------------------------------------------
func _init_floating_cards() -> void:
	_floating_cards.clear()
	for i in range(FLOAT_CARD_COUNT):
		_floating_cards.append({
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

	# 重置
	_overlay_alpha = 1.0
	_title_alpha = 0.0
	_title_scale = 0.6
	_subtitle_alpha = 0.0
	_prompt_alpha = 0.0

	_init_floating_cards()

	# 入场动画序列
	var tween := create_tween()
	tween.set_parallel(false)

	# 1. 遮罩褪色
	tween.tween_property(self, "_overlay_alpha", 0.55, 1.0)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 2. 标题入场 (与遮罩同步但延迟)
	var title_tween := create_tween()
	title_tween.tween_interval(0.4)
	title_tween.set_parallel(true)
	title_tween.tween_property(self, "_title_alpha", 1.0, 0.7)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	title_tween.tween_property(self, "_title_scale", 1.0, 0.7)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# 3. 副标题
	var sub_tween := create_tween()
	sub_tween.tween_interval(0.9)
	sub_tween.tween_property(self, "_subtitle_alpha", 1.0, 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	sub_tween.tween_callback(func(): _phase = Phase.IDLE)

	# 4. 提示文字
	var prompt_tween := create_tween()
	prompt_tween.tween_interval(1.3)
	prompt_tween.tween_property(self, "_prompt_alpha", 1.0, 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

func dismiss() -> void:
	if _phase == Phase.EXIT or _phase == Phase.NONE:
		return
	_phase = Phase.EXIT

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "_title_alpha", 0.0, 0.3)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "_title_scale", 1.1, 0.3)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "_subtitle_alpha", 0.0, 0.3)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "_prompt_alpha", 0.0, 0.3)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	var overlay_tween := create_tween()
	overlay_tween.tween_interval(0.15)
	overlay_tween.tween_property(self, "_overlay_alpha", 0.0, 0.5)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	overlay_tween.tween_callback(func():
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
# 更新与渲染
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	_game_time += dt
	queue_redraw()

func _draw() -> void:
	if _phase == Phase.NONE:
		return

	var w := size.x
	var h := size.y
	var cx := w * 0.5

	# === 遮罩 ===
	draw_rect(Rect2(-50, -50, w + 100, h + 100),
		Color(12/255.0, 18/255.0, 30/255.0, _overlay_alpha))

	# === 浮动卡牌 ===
	var default_font := ThemeDB.fallback_font
	for fc in _floating_cards:
		var fx: float = fc["x"] * w
		var fy: float = fc["y"] * h
		var spd: float = fc["speed"]
		var ph: float = fc["phase_offset"]

		fx += sin(_game_time * spd + ph) * 15.0
		fy += cos(_game_time * spd * 0.7 + ph + 1.5) * 10.0

		var card_alpha: float = fc["base_alpha"] * _overlay_alpha

		# 卡牌背景
		var card_rect := Rect2(fx - 20, fy - 28, 40, 56)
		draw_rect(card_rect,
			Color(Theme.card_back.r, Theme.card_back.g, Theme.card_back.b, card_alpha * 0.25),
			true)

		# 图标
		if default_font:
			draw_string(default_font, Vector2(fx, fy + 6),
				fc["icon"], HORIZONTAL_ALIGNMENT_CENTER,
				-1, int(fc["font_size"]),
				Color(1, 1, 1, card_alpha * 0.2))

	# === 标题 ===
	if _title_alpha > 0.01:
		var title_y := h * 0.35
		var font_size := 42

		if default_font:
			# 光晕底层
			if _title_alpha > 0.3:
				var pulse := 0.8 + 0.2 * sin(_game_time * 1.5)
				var glow_r := 100.0 * pulse
				draw_circle(Vector2(cx, title_y), glow_r,
					Color(Theme.accent.r, Theme.accent.g, Theme.accent.b,
						_title_alpha * 0.1 * pulse))

			# 阴影
			draw_string(default_font, Vector2(cx + 2, title_y + 2 + 14),
				"暗面都市", HORIZONTAL_ALIGNMENT_CENTER,
				-1, font_size,
				Color(0, 0, 0, _title_alpha * 0.5))

			# 主标题
			draw_string(default_font, Vector2(cx, title_y + 14),
				"暗面都市", HORIZONTAL_ALIGNMENT_CENTER,
				-1, font_size,
				Color(Theme.accent.r, Theme.accent.g, Theme.accent.b, _title_alpha))

	# === 副标题 ===
	if _subtitle_alpha > 0.01:
		if default_font:
			draw_string(default_font, Vector2(cx, h * 0.44 + 7),
				"用镜头记录真相  ·  用光明驱散恐惧",
				HORIZONTAL_ALIGNMENT_CENTER,
				-1, 14,
				Color(Theme.text_secondary.r, Theme.text_secondary.g,
					Theme.text_secondary.b, _subtitle_alpha * 0.7))

	# === 按任意键开始 (呼吸闪烁) ===
	if _prompt_alpha > 0.01:
		var breathe := 0.5 + 0.5 * sin(_game_time * 2.5)
		var pa := _prompt_alpha * breathe

		if default_font:
			draw_string(default_font, Vector2(cx, h * 0.62 + 6),
				"- 点击或按 Enter 开始 -",
				HORIZONTAL_ALIGNMENT_CENTER,
				-1, 13,
				Color(Theme.text_secondary.r, Theme.text_secondary.g,
					Theme.text_secondary.b, pa * 0.8))
