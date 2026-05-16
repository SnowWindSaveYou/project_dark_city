## AdvanceDayButton - 右下角"进入下一天"悬浮按钮
##
## 状态机：
##   hidden   → 条件满足时 → appearing（弹入动效）
##   appearing → idle（idle 有呼吸光晕 + 轻微浮动）
##   idle      → 点击/条件不再满足 → disappearing → hidden
##
## 动效设计（物语故障美学）：
##   - 入场：从右边缘外侧滑入 + 透明度淡入 + 弹性过冲
##   - idle：琥珀色光晕呼吸脉冲 + 文字偶发扫描闪
##   - hover：前景白色抬起 + 右侧箭头向右轻移
##   - press：按钮往右下轻压缩 + 短促闪白
##   - 消失：向右滑出 + 淡出

extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal advance_day_requested

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const BTN_W: float       = 220.0
const BTN_H: float       = 62.0
const MARGIN_R: float    = 28.0   # 右边距
const MARGIN_B: float    = 44.0   # 底边距（位于相机按钮上方，相机现在在下方中心）

const C_BG:        Color = Color(0.11, 0.08, 0.04, 0.96)
const C_BG_HOVER:  Color = Color(0.22, 0.14, 0.04, 0.98)
const C_BORDER:    Color = Color(0.82, 0.62, 0.20, 0.70)
const C_GLOW:      Color = Color(0.90, 0.68, 0.20, 0.0)   # alpha 动态控制
const C_TEXT:      Color = Color(0.96, 0.88, 0.62, 1.0)
const C_TEXT_DIM:  Color = Color(0.96, 0.88, 0.62, 0.45)
const C_ARROW:     Color = Color(0.96, 0.88, 0.62, 0.85)
const C_SCAN:      Color = Color(1.0,  0.95, 0.75, 0.18)
const C_HINT:      Color = Color(0.75, 0.68, 0.50, 0.40)

# ---------------------------------------------------------------------------
# 状态枚举
# ---------------------------------------------------------------------------
enum State { HIDDEN, APPEARING, IDLE, DISAPPEARING }

# ---------------------------------------------------------------------------
# 状态变量
# ---------------------------------------------------------------------------
var _state: State = State.HIDDEN

# 布局：按钮左上角位置（动画驱动）
var _btn_x: float = 0.0    # 从屏宽外侧滑入
var _btn_y: float = 0.0

# 动画时间轴
var _time: float = 0.0
var _anim_t: float = 0.0   # 入场/出场进度 0→1

# idle 动效
var _pulse_time: float = 0.0
var _scan_x: float = 0.0          # 扫描线 X（从左到右）
var _scan_active: bool = false
var _scan_timer: float = 0.0
var _scan_interval: float = 5.5   # 每隔多久触发一次扫描

# hover / press
var _hover_t: float = 0.0         # 0→1
var _press_t: float = 0.0         # 0→1（按下瞬间短暂亮起）
var _arrow_offset: float = 0.0    # hover 时箭头右移量

# 缓存：当前是否"可进入下一天"
var _can_advance: bool = false

# 外部引用（由 main.gd 注入）
var _card_manager = null

# 入场偏移 X（从屏幕右边缘外侧开始）
var _offscreen_x: float = 0.0

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
	var target_hover: float = 1.0 if _is_inside_btn(get_local_mouse_position()) and _state == State.IDLE else 0.0
	_hover_t = lerpf(_hover_t, target_hover, delta * 12.0)
	_arrow_offset = lerpf(_arrow_offset, _hover_t * 8.0, delta * 14.0)

	# ── press 衰减
	_press_t = lerpf(_press_t, 0.0, delta * 18.0)

	# ── 扫描线
	if _state == State.IDLE:
		_scan_timer += delta
		if not _scan_active and _scan_timer >= _scan_interval:
			_scan_timer = 0.0
			_scan_interval = randf_range(4.5, 8.0)
			_scan_active = true
			_scan_x = 0.0
		if _scan_active:
			_scan_x += delta * 620.0
			if _scan_x > BTN_W + 20.0:
				_scan_active = false
				_scan_x = 0.0

	# ── 入场/出场动画
	match _state:
		State.APPEARING:
			_anim_t = minf(_anim_t + delta * 3.0, 1.0)
			# easeOutBack：过冲弹性
			_btn_x = _calc_btn_x_target() + _ease_out_back(1.0 - _anim_t) * (BTN_W + MARGIN_R + 40.0)
			if _anim_t >= 1.0:
				_state = State.IDLE
				_btn_x = _calc_btn_x_target()
		State.DISAPPEARING:
			_anim_t = minf(_anim_t + delta * 4.5, 1.0)
			# easeInQuad：快速滑出
			var ease_t: float = _anim_t * _anim_t
			_btn_x = _calc_btn_x_target() + ease_t * (BTN_W + MARGIN_R + 40.0)
			if _anim_t >= 1.0:
				_state = State.HIDDEN
				visible = false

	queue_redraw()

	# ── 轮询 can_advance 状态（每 0.2s 刷新一次避免性能问题）
	# 利用 _pulse_time 做简单节流
	if fmod(_pulse_time, 0.2) < delta:
		_refresh_can_advance()


# ---------------------------------------------------------------------------
# 状态刷新
# ---------------------------------------------------------------------------
func _refresh_can_advance() -> void:
	var can: bool = false
	# 非游戏进行中（标题/游戏结束/过渡）时强制隐藏
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


## 外部调用：强制显示（例如游戏流程手动触发）
func show_button() -> void:
	_can_advance = true
	if _state == State.HIDDEN or _state == State.DISAPPEARING:
		_show()


## 外部调用：强制隐藏
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
	_scan_timer = 0.0


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

	# 动态 alpha（入场/出场渐变）
	var base_alpha: float = 1.0
	match _state:
		State.APPEARING:    base_alpha = _ease_out_quad(_anim_t)
		State.DISAPPEARING: base_alpha = 1.0 - (_anim_t * _anim_t)

	var bx: float = _btn_x
	var by: float = _btn_y
	var bw: float = BTN_W
	var bh: float = BTN_H
	var rect: Rect2 = Rect2(bx, by, bw, bh)

	# ── 光晕（idle 时呼吸脉冲）
	if _state == State.IDLE:
		var pulse: float = 0.5 + 0.5 * sin(_pulse_time * 2.2)   # 0→1
		var glow_alpha: float = pulse * 0.22 * base_alpha
		var glow_expand: float = 4.0 + pulse * 12.0
		var glow_rect: Rect2 = rect.grow(glow_expand)
		_draw_rounded_glow(glow_rect, Color(C_GLOW.r, C_GLOW.g, C_GLOW.b, glow_alpha), int(glow_expand))

	# ── 背景
	var bg_lerp: float = _hover_t * 0.75 + _press_t * 0.25
	var bg_color: Color = C_BG.lerp(C_BG_HOVER, bg_lerp)
	bg_color.a *= base_alpha
	_draw_flat_rect(rect, bg_color)

	# ── 左侧亮条（3px，琥珀色）
	var bar_alpha: float = (0.70 + 0.30 * _hover_t) * base_alpha
	draw_line(Vector2(bx, by + 6.0), Vector2(bx, by + bh - 6.0),
		Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, bar_alpha), 3.0)

	# ── 边框（上/右/下各 1px，左侧亮条已有效果，左边框不画）
	var border_alpha: float = (0.40 + 0.35 * _hover_t) * base_alpha
	var bc: Color = Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, border_alpha)
	draw_line(Vector2(bx, by),        Vector2(bx + bw, by),        bc, 1.0)  # 上
	draw_line(Vector2(bx + bw, by),   Vector2(bx + bw, by + bh),   bc, 1.0)  # 右
	draw_line(Vector2(bx, by + bh),   Vector2(bx + bw, by + bh),   bc, 1.0)  # 下

	# ── 主文字 "进入下一天"
	var text_alpha: float = base_alpha
	var text_color: Color = Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, text_alpha)
	draw_string(font, Vector2(bx + 22.0, by + 39.0),
		"进入下一天", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, text_color)

	# ── 右侧箭头 "→"（hover 时右移）
	var arrow_x: float = bx + bw - 36.0 + _arrow_offset
	var arrow_alpha: float = (0.55 + 0.45 * _hover_t) * base_alpha
	draw_string(font, Vector2(arrow_x, by + 39.0),
		"→", HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
		Color(C_ARROW.r, C_ARROW.g, C_ARROW.b, arrow_alpha))

	# ── 按下闪白
	if _press_t > 0.01:
		var flash_alpha: float = _press_t * 0.30 * base_alpha
		_draw_flat_rect(rect, Color(1.0, 1.0, 1.0, flash_alpha))

	# ── 扫描线（水平扫过）
	if _scan_active and _state == State.IDLE:
		var sx: float = bx + _scan_x - 20.0
		# 渐变宽度：边缘淡入淡出
		for di: int in range(-4, 5):
			var scan_alpha_t: float = 1.0 - absf(float(di)) / 5.0
			var sa: float = C_SCAN.a * scan_alpha_t * base_alpha
			draw_line(Vector2(sx, by + float(di)), Vector2(sx + 40.0, by + float(di)),
				Color(C_SCAN.r, C_SCAN.g, C_SCAN.b, sa), 1.0)

	# ── 顶部小标签 "/ END DAY"（右上角，细小装饰字）
	if _state == State.IDLE:
		var tag_alpha: float = (0.25 + 0.15 * _hover_t) * base_alpha
		draw_string(font, Vector2(bx + bw - 90.0, by - 11.0),
			"/ END DAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(C_HINT.r, C_HINT.g, C_HINT.b, tag_alpha))


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
			# 松开时触发
			accept_event()
			_trigger_advance()


func _trigger_advance() -> void:
	# 消失动效后再触发信号（给玩家视觉反馈）
	_hide_btn()
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
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
# 辅助：绘制
# ---------------------------------------------------------------------------
func _draw_flat_rect(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color)


func _draw_rounded_glow(rect: Rect2, color: Color, size: int) -> void:
	# 用多层半透明矩形叠加模拟辉光
	var steps: int = mini(size, 6)
	for i in range(steps):
		var t: float = float(i + 1) / float(steps)
		var layer_color: Color = Color(color.r, color.g, color.b, color.a * (1.0 - t * 0.7))
		var expand: float = float(i + 1) * float(size) / float(steps) * 0.5
		draw_rect(rect.grow(-expand), layer_color)


# ---------------------------------------------------------------------------
# 缓动函数
# ---------------------------------------------------------------------------
func _ease_out_back(t: float) -> float:
	var c1: float = 1.70158
	var c3: float = c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)


func _ease_out_quad(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)
