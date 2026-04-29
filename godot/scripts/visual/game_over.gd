## GameOver - 游戏结算画面
## 对应原版 GameOver.lua
## 失败/胜利结算，统计展示 + 重新开始
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal restart_requested

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
enum Phase { NONE, ENTER, IDLE, EXIT }
var _phase: Phase = Phase.NONE
var _is_victory: bool = false

## 统计数据
var _stats: Dictionary = {
	"days_survived": 1,
	"cards_revealed": 0,
	"monsters_slain": 0,
	"photos_used": 0,
}

## 动画值
var _overlay_alpha: float = 0.0
var _title_scale: float = 0.0
var _title_alpha: float = 0.0
var _subtitle_alpha: float = 0.0
var _stats_alpha: float = 0.0
var _button_t: float = 0.0
var _btn_hover: bool = false

## 粒子定时
var _particle_timer: float = 0.0
var _game_time: float = 0.0

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

	# 重置
	_overlay_alpha = 0.0
	_title_scale = 0.0
	_title_alpha = 0.0
	_subtitle_alpha = 0.0
	_stats_alpha = 0.0
	_button_t = 0.0
	_particle_timer = 0.0

	# 入场动画序列
	# 1. 遮罩淡入
	var t1: Tween = create_tween()
	t1.tween_property(self, "_overlay_alpha", 0.7, 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 2. 标题弹入
	var t2: Tween = create_tween()
	t2.tween_interval(0.3)
	t2.set_parallel(true)
	t2.tween_property(self, "_title_scale", 1.0, 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t2.tween_property(self, "_title_alpha", 1.0, 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t2.set_parallel(false)
	t2.tween_callback(func(): _phase = Phase.IDLE)

	# 3. 副标题
	var t3: Tween = create_tween()
	t3.tween_interval(0.6)
	t3.tween_property(self, "_subtitle_alpha", 1.0, 0.4)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 4. 统计数据
	var t4: Tween = create_tween()
	t4.tween_interval(0.8)
	t4.tween_property(self, "_stats_alpha", 1.0, 0.4)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 5. 按钮
	var t5: Tween = create_tween()
	t5.tween_interval(1.1)
	t5.tween_property(self, "_button_t", 1.0, 0.35)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func dismiss() -> void:
	if _phase == Phase.EXIT or _phase == Phase.NONE:
		return
	_phase = Phase.EXIT

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "_overlay_alpha", 0.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "_title_alpha", 0.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "_subtitle_alpha", 0.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "_stats_alpha", 0.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "_button_t", 0.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(false)
	tween.tween_callback(func():
		_phase = Phase.NONE
		visible = false
		set_process(false)
		set_process_input(false)
		restart_requested.emit()
	)

func is_active() -> bool:
	return _phase != Phase.NONE

# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _get_button_rect() -> Rect2:
	var bw: float = 120.0
	var bh: float = 38.0
	return Rect2(size.x / 2 - bw / 2, size.y * 0.72, bw, bh)

func _input(event: InputEvent) -> void:
	if _phase == Phase.NONE:
		return

	if event is InputEventMouseButton and event.pressed:
		if _button_t > 0.5:
			var btn_rect: Rect2 = _get_button_rect()
			if btn_rect.has_point(event.position):
				dismiss()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed:
		if _phase == Phase.IDLE:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				dismiss()
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if _button_t > 0.5:
			var btn_rect: Rect2 = _get_button_rect()
			_btn_hover = btn_rect.has_point(event.position)

# ---------------------------------------------------------------------------
# 更新与渲染
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	_game_time += dt
	queue_redraw()

func _draw() -> void:
	if _phase == Phase.NONE:
		return

	var w: float = size.x
	var h: float = size.y
	var cx: float = w * 0.5
	var default_font: Font = ThemeDB.fallback_font

	# === 遮罩 ===
	if _overlay_alpha > 0.01:
		var overlay_color: Color
		if _is_victory:
			overlay_color = Color(15/255.0, 25/255.0, 45/255.0, _overlay_alpha)
		else:
			overlay_color = Color(40/255.0, 10/255.0, 10/255.0, _overlay_alpha)
		draw_rect(Rect2(-50, -50, w + 100, h + 100), overlay_color)

	# === 标题 ===
	if _title_alpha > 0.01 and default_font:
		var title_text: String = "任务完成" if _is_victory else "意识崩溃"
		var title_color: Color = GameTheme.safe if _is_victory else GameTheme.danger
		var title_y: float = h * 0.28
		var fs: int = 36

		# 光晕
		if _title_alpha > 0.3:
			var glow_r: float = 80.0 + 10.0 * sin(_game_time * 2.0)
			draw_circle(Vector2(cx, title_y), glow_r,
				Color(title_color.r, title_color.g, title_color.b, _title_alpha * 0.15))

		# 阴影
		draw_string(default_font, Vector2(2, title_y + 2 + 12),
			title_text, HORIZONTAL_ALIGNMENT_CENTER,
			w, fs, Color(0, 0, 0, _title_alpha * 0.5))

		# 标题文字 (缩放通过字号近似)
		var scaled_fs: int = int(fs * _title_scale)
		draw_string(default_font, Vector2(0, title_y + 12),
			title_text, HORIZONTAL_ALIGNMENT_CENTER,
			w, scaled_fs,
			Color(title_color.r, title_color.g, title_color.b, _title_alpha))

	# === 副标题 ===
	if _subtitle_alpha > 0.01 and default_font:
		var sub_text: String
		if _is_victory:
			sub_text = "你在暗面都市中幸存了下来。"
		else:
			sub_text = "黑暗吞噬了你最后的理智..."
		draw_string(default_font, Vector2(0, h * 0.36 + 7),
			sub_text, HORIZONTAL_ALIGNMENT_CENTER,
			w, 15,
			Color(GameTheme.text_secondary.r, GameTheme.text_secondary.g,
				GameTheme.text_secondary.b, _subtitle_alpha * 0.8))

	# === 统计 ===
	if _stats_alpha > 0.01 and default_font:
		var lines: Array = [
			{ "icon": "📅", "label": "存活天数", "value": str(_stats.get("days_survived", 1)) },
			{ "icon": "🃏", "label": "翻开卡牌", "value": str(_stats.get("cards_revealed", 0)) },
			{ "icon": "👻", "label": "驱除怪物", "value": str(_stats.get("monsters_slain", 0)) },
			{ "icon": "📷", "label": "消耗胶卷", "value": str(_stats.get("photos_used", 0)) },
		]

		var line_h: float = 24.0
		var start_y: float = h * 0.44

		for i in range(lines.size()):
			var line: Dictionary = lines[i]
			var ly: float = start_y + i * line_h

			# 图标 + 标签
			draw_string(default_font, Vector2(0, ly + 5),
				line["icon"] + " " + line["label"],
				HORIZONTAL_ALIGNMENT_RIGHT,
				cx - 10, 16,
				Color(GameTheme.text_secondary.r, GameTheme.text_secondary.g,
					GameTheme.text_secondary.b, _stats_alpha))

			# 数值
			draw_string(default_font, Vector2(cx + 10, ly + 5),
				line["value"],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1, 16,
				Color(GameTheme.text_primary.r, GameTheme.text_primary.g,
					GameTheme.text_primary.b, _stats_alpha))

	# === 重新开始按钮 ===
	if _button_t > 0.01:
		var btn_rect: Rect2 = _get_button_rect()
		var btn_color: Color = GameTheme.safe if _is_victory else GameTheme.accent

		# Hover 效果
		var hover_brighten: float = 0.15 if _btn_hover else 0.0
		var lift: float = 2.0 if _btn_hover else 0.0

		var final_color: Color = Color(
			minf(btn_color.r + hover_brighten, 1.0),
			minf(btn_color.g + hover_brighten, 1.0),
			minf(btn_color.b + hover_brighten, 1.0),
			_button_t * 0.94
		)

		# 按钮背景 (考虑缩放)
		var scaled_w: float = btn_rect.size.x * _button_t
		var scaled_h: float = btn_rect.size.y * _button_t
		var scaled_rect: Rect2 = Rect2(
			cx - scaled_w / 2,
			btn_rect.position.y + (btn_rect.size.y - scaled_h) / 2 - lift,
			scaled_w, scaled_h
		)
		draw_rect(scaled_rect, final_color, true)

		# 按钮文字
		if default_font and _button_t > 0.3:
			draw_string(default_font,
				Vector2(scaled_rect.position.x, scaled_rect.position.y + scaled_rect.size.y / 2 + 6),
				"重新开始", HORIZONTAL_ALIGNMENT_CENTER,
				scaled_rect.size.x, 15,
				Color(1, 1, 1, _button_t))
