## AdvanceDayButton - 右下角"进入下一天"悬浮按钮
##
## 视觉风格：与相机按钮、HUD 一致的明亮卡牌游戏美学
##   背景：白色半透明卡片面板 (panel_bg)
##   主色：暖金 warning #FFC350 作为 CTA 高亮
##   文字：深海蓝 text_primary #232D3C
##   hover：accent 橘红 #FF7F66
##   带轻柔阴影，圆角设计
##
## 状态机：
##   hidden   → 条件满足时 → appearing（从右侧弹入）
##   appearing → idle（轻微呼吸 + 偶发上下浮动）
##   idle      → 点击/条件不再满足 → disappearing → hidden

extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal advance_day_requested

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const BTN_W: float    = 228.0
const BTN_H: float    = 64.0
const MARGIN_R: float = 32.0   # 右边距
const MARGIN_B: float = 120.0  # 底边距（在相机按钮上方，留出空间）
const CORNER_R: float = 14.0   # 圆角半径

# 颜色（使用 GameTheme 静态颜色，与全局主题一致）
# 注意：GameTheme 是 Autoload，这里直接引用其静态属性
# bg: 白色半透明卡片 (panel_bg)
const C_BG:        Color = Color(1.0,  1.0,  1.0,  0.93)
const C_BG_HOVER:  Color = Color(1.0,  0.97, 0.93, 0.97)   # 暖白 (hint of amber)
const C_BORDER:    Color = Color(0.94, 0.79, 0.33, 0.75)   # warning #FFC350 边框
const C_BORDER_HOVER: Color = Color(1.0, 0.49, 0.40, 0.90) # accent #FF7F66 hover 边框
const C_TEXT:      Color = Color(0.14, 0.18, 0.24, 1.0)    # text_primary #232D3C
const C_ARROW:     Color = Color(0.94, 0.79, 0.33, 1.0)    # warning #FFC350 箭头
const C_ARROW_HOVER: Color = Color(1.0, 0.49, 0.40, 1.0)   # accent #FF7F66 hover
const C_BADGE:     Color = Color(0.94, 0.79, 0.33, 0.15)   # 顶部 badge 淡金底
const C_BADGE_TEXT: Color = Color(0.80, 0.60, 0.10, 0.80)  # badge 文字
const C_PULSE:     Color = Color(0.94, 0.79, 0.33, 0.0)    # 呼吸光晕（alpha 动态）

# ---------------------------------------------------------------------------
# 状态枚举
# ---------------------------------------------------------------------------
enum State { HIDDEN, APPEARING, IDLE, DISAPPEARING }

# ---------------------------------------------------------------------------
# 状态变量
# ---------------------------------------------------------------------------
var _state: State = State.HIDDEN

# 布局：按钮左上角位置（动画驱动）
var _btn_x: float = 0.0
var _btn_y: float = 0.0

# 动画时间轴
var _time: float = 0.0
var _anim_t: float = 0.0   # 入场/出场进度 0→1

# idle 动效
var _pulse_time: float = 0.0
var _float_offset: float = 0.0   # 轻微上下浮动 offset

# hover / press
var _hover_t: float = 0.0   # 0→1
var _press_t: float = 0.0   # 0→1 press 亮闪
var _arrow_dx: float = 0.0  # hover 时箭头右移

# 缓存
var _can_advance: bool = false
var _card_manager = null

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## 由 main.gd 注入 CardManager
func setup(card_manager) -> void:
	_card_manager = card_manager


# ---------------------------------------------------------------------------
# 每帧
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_time += delta
	_pulse_time += delta

	# ── hover 平滑
	var inside: bool = _is_inside_btn(get_local_mouse_position()) and _state == State.IDLE
	_hover_t = lerpf(_hover_t, 1.0 if inside else 0.0, delta * 14.0)
	_arrow_dx = lerpf(_arrow_dx, _hover_t * 7.0, delta * 16.0)

	# ── press 衰减
	_press_t = lerpf(_press_t, 0.0, delta * 20.0)

	# ── 轻浮动（idle 时才计算）
	if _state == State.IDLE:
		_float_offset = sin(_time * 1.5) * 2.8

	# ── 入场/出场动画
	match _state:
		State.APPEARING:
			_anim_t = minf(_anim_t + delta * 3.2, 1.0)
			# easeOutBack 弹性弹入
			var ease_x: float = _ease_out_back(1.0 - _anim_t) * (BTN_W + MARGIN_R + 48.0)
			_btn_x = _calc_btn_x_target() + ease_x
			if _anim_t >= 1.0:
				_state = State.IDLE
				_btn_x = _calc_btn_x_target()

		State.DISAPPEARING:
			_anim_t = minf(_anim_t + delta * 5.0, 1.0)
			# easeInQuad：向右快速滑出
			var ease_t: float = _anim_t * _anim_t
			_btn_x = _calc_btn_x_target() + ease_t * (BTN_W + MARGIN_R + 48.0)
			if _anim_t >= 1.0:
				_state = State.HIDDEN
				visible = false

	queue_redraw()

	# ── 轮询 can_advance 状态（节流：~5 fps）
	if fmod(_pulse_time, 0.2) < delta:
		_refresh_can_advance()


# ---------------------------------------------------------------------------
# 状态刷新
# ---------------------------------------------------------------------------
func _refresh_can_advance() -> void:
	var can: bool = false
	if GameData.game_phase != "playing":
		can = false
	elif _card_manager != null:
		var schedules: Array = _card_manager.schedules
		var has_pending: bool = false
		for s: Dictionary in schedules:
			if s.get("status", "") == "pending":
				has_pending = true
				break
		var su: int = GameData.steps_remaining
		var sm: int = GameData.steps_total
		var steps_done: bool = sm > 0 and su <= 0
		can = (not has_pending) or steps_done

	if can == _can_advance:
		return
	_can_advance = can

	if can and _state == State.HIDDEN:
		_show()
	elif not can and (_state == State.IDLE or _state == State.APPEARING):
		_hide_btn()


func show_button() -> void:
	_can_advance = true
	if _state == State.HIDDEN or _state == State.DISAPPEARING:
		_show()


func hide_button() -> void:
	_can_advance = false
	if _state == State.IDLE or _state == State.APPEARING:
		_hide_btn()


func _show() -> void:
	_state = State.APPEARING
	_anim_t = 0.0
	var vp: Vector2 = get_viewport_rect().size
	_btn_y = vp.y - MARGIN_B - BTN_H
	_btn_x = vp.x + BTN_W   # 从屏幕右侧外开始
	visible = true
	_pulse_time = 0.0
	_float_offset = 0.0


func _hide_btn() -> void:
	_state = State.DISAPPEARING
	_anim_t = 0.0


# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _draw() -> void:
	if _state == State.HIDDEN:
		return

	var vp: Vector2 = get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font

	# 动态 alpha（入场淡入 / 出场淡出）
	var base_alpha: float = 1.0
	match _state:
		State.APPEARING:    base_alpha = _ease_out_quad(_anim_t)
		State.DISAPPEARING: base_alpha = 1.0 - _anim_t * _anim_t

	var bx: float = _btn_x
	var by: float = _btn_y + _float_offset   # 叠加浮动
	var bw: float = BTN_W
	var bh: float = BTN_H

	# ─────────────────────────────────────────
	# 1. 呼吸光晕（idle 时仅在 warning 色调上）
	# ─────────────────────────────────────────
	if _state == State.IDLE:
		var pulse: float = 0.5 + 0.5 * sin(_pulse_time * 1.8)   # 0~1
		var glow_alpha: float = pulse * 0.14 * base_alpha
		var glow_expand: float = 3.0 + pulse * 10.0
		# 用多层半透明圆角矩形叠加模拟柔和光晕
		for i in range(4):
			var t: float = float(i + 1) / 4.0
			var layer_a: float = glow_alpha * (1.0 - t * 0.8)
			var exp_i: float = glow_expand * t
			_draw_rounded_rect(
				Rect2(bx - exp_i, by - exp_i, bw + exp_i * 2.0, bh + exp_i * 2.0),
				CORNER_R + exp_i,
				Color(C_PULSE.r, C_PULSE.g, C_PULSE.b, layer_a)
			)

	# ─────────────────────────────────────────
	# 2. 软阴影
	# ─────────────────────────────────────────
	_draw_card_shadow(bx, by, bw, bh, base_alpha)

	# ─────────────────────────────────────────
	# 3. 背景（白色圆角卡片）
	# ─────────────────────────────────────────
	var bg: Color = C_BG.lerp(C_BG_HOVER, _hover_t)
	bg.a *= base_alpha
	_draw_rounded_rect(Rect2(bx, by, bw, bh), CORNER_R, bg)

	# ─────────────────────────────────────────
	# 4. 边框（下 + 右 + 上，左侧用色块替代）
	# ─────────────────────────────────────────
	var border_c: Color = C_BORDER.lerp(C_BORDER_HOVER, _hover_t)
	border_c.a *= base_alpha
	# 上边框
	draw_line(Vector2(bx + CORNER_R, by), Vector2(bx + bw - CORNER_R, by), border_c, 1.5)
	# 右边框
	draw_line(Vector2(bx + bw, by + CORNER_R), Vector2(bx + bw, by + bh - CORNER_R), border_c, 1.5)
	# 下边框
	draw_line(Vector2(bx + CORNER_R, by + bh), Vector2(bx + bw - CORNER_R, by + bh), border_c, 1.5)

	# ─────────────────────────────────────────
	# 5. 左侧色条（3px warning 暖金竖条）
	# ─────────────────────────────────────────
	var bar_c: Color = C_BORDER.lerp(C_BORDER_HOVER, _hover_t)
	bar_c.a = (0.80 + 0.20 * _hover_t) * base_alpha
	draw_line(Vector2(bx, by + CORNER_R), Vector2(bx, by + bh - CORNER_R), bar_c, 3.5)

	# ─────────────────────────────────────────
	# 6. 主文字 "进入下一天"
	# ─────────────────────────────────────────
	var text_c: Color = Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, base_alpha)
	var text_x: float = bx + 20.0
	var text_y: float = by + 40.0
	draw_string(font, Vector2(text_x, text_y),
		"进入下一天",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, text_c)

	# ─────────────────────────────────────────
	# 7. 右侧箭头 "→"（hover 时往右移 + 变橘）
	# ─────────────────────────────────────────
	var arrow_c: Color = C_ARROW.lerp(C_ARROW_HOVER, _hover_t)
	arrow_c.a = (0.80 + 0.20 * _hover_t) * base_alpha
	var arrow_x: float = bx + bw - 38.0 + _arrow_dx
	draw_string(font, Vector2(arrow_x, text_y),
		"→", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, arrow_c)

	# ─────────────────────────────────────────
	# 8. 右上角小 badge "DAY +1"
	# ─────────────────────────────────────────
	if _state == State.IDLE:
		var badge_alpha: float = (0.60 + 0.30 * _hover_t) * base_alpha
		var badge_text: String = "DAY +" + str(GameData.get("current_day", 0) + 1)
		var badge_x: float = bx + bw - 10.0
		var badge_y: float = by - 2.0
		# badge 背景小圆角矩形
		var bw2: float = 72.0
		var bh2: float = 20.0
		var badge_bg: Color = Color(C_BADGE.r, C_BADGE.g, C_BADGE.b, badge_alpha * 0.9)
		_draw_rounded_rect(Rect2(badge_x - bw2, badge_y - bh2 * 0.5, bw2, bh2), 5.0, badge_bg)
		# badge 文字
		var badge_text_c: Color = Color(C_BADGE_TEXT.r, C_BADGE_TEXT.g, C_BADGE_TEXT.b, badge_alpha)
		draw_string(font, Vector2(badge_x - bw2 + 4.0, badge_y + 5.5),
			badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, badge_text_c)

	# ─────────────────────────────────────────
	# 9. 按下闪光（白色叠层）
	# ─────────────────────────────────────────
	if _press_t > 0.01:
		var flash_a: float = _press_t * 0.28 * base_alpha
		_draw_rounded_rect(Rect2(bx, by, bw, bh), CORNER_R, Color(1.0, 1.0, 1.0, flash_a))


# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------
func _has_point(point: Vector2) -> bool:
	if _state != State.IDLE:
		return false
	return _is_inside_btn(point)


func _gui_input(event: InputEvent) -> void:
	if _state != State.IDLE:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if not _is_inside_btn(mb.position):
			return
		if mb.pressed:
			_press_t = 1.0
			accept_event()
		else:
			accept_event()
			_trigger_advance()


func _trigger_advance() -> void:
	_hide_btn()
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		advance_day_requested.emit()
	)


# ---------------------------------------------------------------------------
# 辅助：命中检测
# ---------------------------------------------------------------------------
func _is_inside_btn(pos: Vector2) -> bool:
	var vp: Vector2 = get_viewport_rect().size
	_btn_y = vp.y - MARGIN_B - BTN_H
	var rect: Rect2 = Rect2(_btn_x, _btn_y, BTN_W, BTN_H)
	return rect.has_point(pos)


func _calc_btn_x_target() -> float:
	var vp: Vector2 = get_viewport_rect().size
	return vp.x - MARGIN_R - BTN_W


# ---------------------------------------------------------------------------
# 辅助：绘制 - 圆角矩形
# ---------------------------------------------------------------------------
func _draw_rounded_rect(rect: Rect2, radius: float, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left     = int(radius)
	sb.corner_radius_top_right    = int(radius)
	sb.corner_radius_bottom_left  = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	sb.set_content_margin_all(0)
	draw_style_box(sb, rect)


## 卡片式软阴影（偏移向下，与游戏其他卡牌视觉一致）
func _draw_card_shadow(bx: float, by: float, bw: float, bh: float, base_alpha: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.corner_radius_top_left     = int(CORNER_R)
	sb.corner_radius_top_right    = int(CORNER_R)
	sb.corner_radius_bottom_left  = int(CORNER_R)
	sb.corner_radius_bottom_right = int(CORNER_R)
	sb.shadow_color  = Color(0.12, 0.20, 0.30, 0.22 * base_alpha)
	sb.shadow_size   = 12
	sb.shadow_offset = Vector2(0.0, 4.0)
	draw_style_box(sb, Rect2(bx, by, bw, bh))


# ---------------------------------------------------------------------------
# 缓动函数
# ---------------------------------------------------------------------------
func _ease_out_back(t: float) -> float:
	var c1: float = 1.70158
	var c3: float = c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)


func _ease_out_quad(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)
