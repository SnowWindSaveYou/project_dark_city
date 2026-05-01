## GameOver (Scene 版) — 游戏结算画面
## 全 Scene 化: 标题/副标题/统计/按钮均为节点，光晕保留 _draw()
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal restart_requested

# ---------------------------------------------------------------------------
# 节点引用
# ---------------------------------------------------------------------------
@onready var _overlay: ColorRect = $Overlay
@onready var _glow_circle: Control = $GlowCircle
@onready var _title_label: Label = $TitleLabel
@onready var _subtitle_label: Label = $SubtitleLabel
@onready var _stats_grid: GridContainer = $StatsGrid
@onready var _days_value: Label = $StatsGrid/DaysValue
@onready var _cards_value: Label = $StatsGrid/CardsValue
@onready var _monsters_value: Label = $StatsGrid/MonstersValue
@onready var _film_value: Label = $StatsGrid/FilmValue
@onready var _restart_button: Button = $RestartButton

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
enum Phase { NONE, ENTER, IDLE, EXIT }
var _phase: Phase = Phase.NONE
var _is_victory: bool = false
var _game_time: float = 0.0

## 统计数据
var _stats: Dictionary = {
	"days_survived": 1,
	"cards_revealed": 0,
	"monsters_slain": 0,
	"photos_used": 0,
}

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	visible = false
	set_process(false)
	set_process_input(false)

	# 光晕委托绘制
	_glow_circle.draw.connect(_draw_glow)

	# 初始隐藏所有元素
	_overlay.color.a = 0.0
	_title_label.modulate.a = 0.0
	_title_label.scale = Vector2(0.01, 0.01)
	_subtitle_label.modulate.a = 0.0
	_stats_grid.modulate.a = 0.0
	_restart_button.modulate.a = 0.0
	_restart_button.scale = Vector2(0.01, 0.01)
	_glow_circle.modulate.a = 0.0

	# 标题缩放锚点
	_title_label.pivot_offset = _title_label.size / 2.0
	_title_label.resized.connect(func():
		_title_label.pivot_offset = _title_label.size / 2.0)

	# 按钮缩放锚点
	_restart_button.pivot_offset = _restart_button.size / 2.0
	_restart_button.resized.connect(func():
		_restart_button.pivot_offset = _restart_button.size / 2.0)

	# 按钮样式初始化
	_setup_button_style()

	# 按钮信号
	_restart_button.pressed.connect(_on_restart_pressed)
	_restart_button.mouse_entered.connect(func(): _btn_hover_tween(true))
	_restart_button.mouse_exited.connect(func(): _btn_hover_tween(false))

# ---------------------------------------------------------------------------
# 按钮样式
# ---------------------------------------------------------------------------

func _setup_button_style() -> void:
	# 默认使用胜利色（show_result 中会根据实际结果切换）
	var btn_color: Color = GameTheme.safe

	var normal := StyleBoxFlat.new()
	normal.bg_color = btn_color
	normal.set_corner_radius_all(12)
	normal.set_content_margin_all(24)
	_restart_button.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = GameTheme.lighten(btn_color, 0.15)
	_restart_button.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = GameTheme.darken(btn_color, 0.85)
	_restart_button.add_theme_stylebox_override("pressed", pressed)

	var focus := StyleBoxEmpty.new()
	_restart_button.add_theme_stylebox_override("focus", focus)

	_restart_button.add_theme_color_override("font_color", Color.WHITE)
	_restart_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_restart_button.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.8))

func _update_button_color(btn_color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = btn_color
	normal.set_corner_radius_all(12)
	normal.set_content_margin_all(24)
	_restart_button.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = GameTheme.lighten(btn_color, 0.15)
	_restart_button.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = GameTheme.darken(btn_color, 0.85)
	_restart_button.add_theme_stylebox_override("pressed", pressed)

# ---------------------------------------------------------------------------
# 按钮 hover 动画
# ---------------------------------------------------------------------------

func _btn_hover_tween(enter: bool) -> void:
	var target_scale: Vector2 = Vector2(1.05, 1.05) if enter else Vector2.ONE
	_restart_button.pivot_offset = _restart_button.size / 2.0
	var tw: Tween = _restart_button.create_tween()
	tw.tween_property(_restart_button, "scale", target_scale, 0.12)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func show_result(is_victory: bool, stats: Dictionary = {}) -> void:
	_phase = Phase.ENTER
	_is_victory = is_victory
	if stats.size() > 0:
		_stats = stats
	visible = true
	set_process(true)
	set_process_input(true)
	_game_time = 0.0

	# 根据胜利/失败设置颜色
	var title_color: Color = GameTheme.safe if _is_victory else GameTheme.danger
	var btn_color: Color = GameTheme.safe if _is_victory else GameTheme.accent

	# 遮罩底色
	if _is_victory:
		_overlay.color = Color(15/255.0, 25/255.0, 45/255.0, 0.0)
	else:
		_overlay.color = Color(40/255.0, 10/255.0, 10/255.0, 0.0)

	# 标题内容和颜色
	_title_label.text = "任务完成" if _is_victory else "意识崩溃"
	_title_label.add_theme_color_override("font_color", title_color)

	# 副标题
	if _is_victory:
		_subtitle_label.text = "你在暗面都市中幸存了下来。"
	else:
		_subtitle_label.text = "黑暗吞噬了你最后的理智..."
	_subtitle_label.add_theme_color_override("font_color",
		Color(GameTheme.text_secondary, 0.8))

	# 统计数据
	_days_value.text = str(_stats.get("days_survived", 1))
	_cards_value.text = str(_stats.get("cards_revealed", 0))
	_monsters_value.text = str(_stats.get("monsters_slain", 0))
	_film_value.text = str(_stats.get("photos_used", 0))

	# 统计 Label 颜色
	for child in _stats_grid.get_children():
		var label: Label = child as Label
		if label:
			if label.name.ends_with("Value"):
				label.add_theme_color_override("font_color", GameTheme.text_primary)
			else:
				label.add_theme_color_override("font_color", GameTheme.text_secondary)

	# 按钮颜色
	_update_button_color(btn_color)

	# 重置动画状态
	_overlay.color.a = 0.0
	_title_label.modulate.a = 0.0
	_title_label.scale = Vector2(0.01, 0.01)
	_subtitle_label.modulate.a = 0.0
	_stats_grid.modulate.a = 0.0
	_restart_button.modulate.a = 0.0
	_restart_button.scale = Vector2(0.01, 0.01)
	_glow_circle.modulate.a = 0.0

	# === 入场动画序列 ===

	# 1. 遮罩淡入
	var t1: Tween = create_tween()
	t1.tween_property(_overlay, "color:a", 0.7, 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 2. 标题弹入（延迟 0.3s）
	var t2: Tween = create_tween()
	t2.tween_interval(0.3)
	t2.set_parallel(true)
	t2.tween_property(_title_label, "scale", Vector2.ONE, 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t2.tween_property(_title_label, "modulate:a", 1.0, 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t2.tween_property(_glow_circle, "modulate:a", 1.0, 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t2.set_parallel(false)
	t2.tween_callback(func(): _phase = Phase.IDLE)

	# 3. 副标题（延迟 0.6s）
	var t3: Tween = create_tween()
	t3.tween_interval(0.6)
	t3.tween_property(_subtitle_label, "modulate:a", 1.0, 0.4)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 4. 统计数据（延迟 0.8s）
	var t4: Tween = create_tween()
	t4.tween_interval(0.8)
	t4.tween_property(_stats_grid, "modulate:a", 1.0, 0.4)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 5. 按钮弹入（延迟 1.1s）
	var t5: Tween = create_tween()
	t5.tween_interval(1.1)
	t5.set_parallel(true)
	t5.tween_property(_restart_button, "modulate:a", 1.0, 0.35)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t5.tween_property(_restart_button, "scale", Vector2.ONE, 0.35)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func dismiss() -> void:
	if _phase == Phase.EXIT or _phase == Phase.NONE:
		return
	_phase = Phase.EXIT

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "color:a", 0.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_title_label, "modulate:a", 0.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_subtitle_label, "modulate:a", 0.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_stats_grid, "modulate:a", 0.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_restart_button, "modulate:a", 0.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_glow_circle, "modulate:a", 0.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.set_parallel(false)
	tw.tween_callback(func():
		_phase = Phase.NONE
		visible = false
		set_process(false)
		set_process_input(false)
		restart_requested.emit()
	)

func is_active() -> bool:
	return _phase != Phase.NONE

# ---------------------------------------------------------------------------
# 输入 — 全屏点击也支持关闭
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _phase == Phase.NONE:
		return

	# 吃掉所有输入防止穿透到下层
	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if _phase == Phase.IDLE:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				dismiss()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# 按钮回调
# ---------------------------------------------------------------------------

func _on_restart_pressed() -> void:
	if _phase == Phase.IDLE:
		dismiss()

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	_game_time += dt
	_glow_circle.queue_redraw()

# ---------------------------------------------------------------------------
# 绘制: 光晕
# ---------------------------------------------------------------------------

func _draw_glow() -> void:
	if _phase == Phase.NONE:
		return
	if _title_label.modulate.a < 0.3:
		return

	var title_color: Color = GameTheme.safe if _is_victory else GameTheme.danger
	var pulse: float = 0.8 + 0.2 * sin(_game_time * 2.0)
	var glow_r: float = 240.0 + 30.0 * sin(_game_time * 2.0)
	var center: Vector2 = _glow_circle.size / 2.0

	_glow_circle.draw_circle(center, glow_r,
		Color(title_color.r, title_color.g, title_color.b, 0.15 * pulse))
