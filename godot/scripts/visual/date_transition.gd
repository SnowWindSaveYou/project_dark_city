## DateTransition - P4 风格日期转场
## 对应原版 DateTransition.lua
## 蓝色光带 (+22°) × 日期线 (-42°) 交叉，5 阶段动画序列
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal transition_completed

# ---------------------------------------------------------------------------
# 双角度系统
# ---------------------------------------------------------------------------
const BAND_ANGLE_DEG: float = 22.0
const DATE_ANGLE_DEG: float = -42.0

var _band_angle_rad: float
var _band_cos: float
var _band_sin: float
var _band_perp_rad: float
var _band_perp_cos: float
var _band_perp_sin: float

var _date_angle_rad: float
var _date_cos: float
var _date_sin: float

const BAND_WIDTH_RATIO: float = 0.22
const DATE_COUNT: int = 8
const CURRENT_INDEX: int = 4  # 当前日在序列中的位置

# ---------------------------------------------------------------------------
# 动画时间轴
# ---------------------------------------------------------------------------
const T_WIPE_START: float = 0.0
const T_WIPE_END: float = 0.45
const T_SHRINK_END: float = 0.90
const T_POPUP_START: float = 0.75
const T_POPUP_STAGGER: float = 0.07
const T_POPUP_DUR: float = 0.35
const T_SCROLL_START: float = 1.60
const T_SCROLL_DUR: float = 0.50
const T_RIPPLE_START: float = 2.10
const T_RIPPLE_DUR: float = 0.65
const T_EXIT_START: float = 2.80
const T_EXIT_DUR: float = 0.50
const T_BG_FADE_DUR: float = 0.40
const TOTAL_DUR: float = T_EXIT_START + T_EXIT_DUR

# ---------------------------------------------------------------------------
# 日期系统常量
# ---------------------------------------------------------------------------
const BASE_YEAR: int = 2026
const BASE_MONTH: int = 4
const BASE_DAY: int = 24
const WEEKDAY_NAMES: Array = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
const MONTH_NAMES: Array = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"
]
const DAYS_IN_MONTH: Array = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _active: bool = false
var _timer: float = 0.0
var _day_count: int = 1

## 背景图 (可选)
var _bg_texture: Texture2D = null

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	_band_angle_rad = deg_to_rad(BAND_ANGLE_DEG)
	_band_cos = cos(_band_angle_rad)
	_band_sin = sin(_band_angle_rad)
	_band_perp_rad = _band_angle_rad + PI * 0.5
	_band_perp_cos = cos(_band_perp_rad)
	_band_perp_sin = sin(_band_perp_rad)
	_date_angle_rad = deg_to_rad(DATE_ANGLE_DEG)
	_date_cos = cos(_date_angle_rad)
	_date_sin = sin(_date_angle_rad)

	visible = false
	set_process(false)

	# 尝试加载背景图
	var bg_path: String = "res://assets/images/date_transition_bg.png"
	if ResourceLoader.exists(bg_path):
		_bg_texture = load(bg_path)

# ---------------------------------------------------------------------------
# 日期计算
# ---------------------------------------------------------------------------

static func _is_leap_year(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0)

static func _days_in_month(y: int, m: int) -> int:
	if m == 2 and _is_leap_year(y):
		return 29
	return DAYS_IN_MONTH[m - 1]

static func _calc_date(day_count: int) -> Array:
	var y: int = BASE_YEAR
	var m: int = BASE_MONTH
	var d: float = BASE_DAY + (day_count - 1)
	while d < 1:
		m -= 1
		if m < 1:
			m = 12
			y -= 1
		d += _days_in_month(y, m)
	while d > _days_in_month(y, m):
		d -= _days_in_month(y, m)
		m += 1
		if m > 12:
			m = 1
			y += 1
	return [y, m, d]

static func _calc_weekday(y: int, m: int, d: int) -> int:
	var t_arr: Array = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	var yy: int = y
	if m < 3:
		yy -= 1
	return (yy + yy / 4 - yy / 100 + yy / 400 + t_arr[m - 1] + d) % 7

# ---------------------------------------------------------------------------
# Easing
# ---------------------------------------------------------------------------

static func _ease_out_cubic(t: float) -> float:
	var t1: float = t - 1.0
	return t1 * t1 * t1 + 1.0

static func _ease_in_cubic(t: float) -> float:
	return t * t * t

static func _ease_out_back(t: float) -> float:
	var c: float = 1.70158
	var t1: float = t - 1.0
	return t1 * t1 * ((c + 1) * t1 + c) + 1.0

static func _ease_out_elastic(t: float) -> float:
	if t <= 0:
		return 0.0
	if t >= 1:
		return 1.0
	var p: float = 0.35
	return pow(2, -10 * t) * sin((t - p / 4) * TAU / p) + 1.0

static func _clamp01(t: float) -> float:
	return clampf(t, 0.0, 1.0)

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func play(day_count: int) -> void:
	_active = true
	_timer = 0.0
	_day_count = day_count
	visible = true
	set_process(true)

func is_active() -> bool:
	return _active

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	if not _active:
		return
	_timer += dt
	if _timer >= TOTAL_DUR:
		_active = false
		visible = false
		set_process(false)
		transition_completed.emit()
		return
	queue_redraw()

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not _active:
		return

	var t: float = _timer
	var w: float = size.x
	var h: float = size.y
	var diag_len: float = sqrt(w * w + h * h)
	var band_target_w: float = h * BAND_WIDTH_RATIO
	var center_x: float = w * 0.5
	var center_y: float = h * 0.5
	var default_font: Font = ThemeDB.fallback_font

	# === Phase 5: 退出进度 ===
	var exit_p: float = 0.0
	if t > T_EXIT_START:
		exit_p = _clamp01((t - T_EXIT_START) / T_EXIT_DUR)
		exit_p = _ease_in_cubic(exit_p)
	var band_exit_offset: float = exit_p * diag_len * 0.6
	var ui_exit_offset: float = exit_p * diag_len * 0.6
	var exit_alpha: float = 1.0 - exit_p

	# === Phase 1: 蓝色遮罩擦入 ===
	var wipe_p: float = _clamp01((t - T_WIPE_START) / (T_WIPE_END - T_WIPE_START))
	wipe_p = _ease_out_cubic(wipe_p)

	# === Phase 2: 缩窄为光带 ===
	var shrink_p: float = 0.0
	if t > T_WIPE_END:
		shrink_p = _clamp01((t - T_WIPE_END) / (T_SHRINK_END - T_WIPE_END))
		shrink_p = _ease_out_cubic(shrink_p)

	var full_cover_h: float = diag_len * 1.5
	var current_band_h: float = full_cover_h + (band_target_w - full_cover_h) * shrink_p
	var start_offset: float = diag_len * 0.9
	var perp_offset: float = start_offset * (1.0 - wipe_p)

	# === 背景图 (cover 模式) ===
	var bg_fade_in: float = _clamp01(shrink_p)
	var bg_fade_out: float = 1.0
	if t > T_EXIT_START:
		bg_fade_out = 1.0 - _clamp01((t - T_EXIT_START) / T_BG_FADE_DUR)
	var bg_alpha: float = bg_fade_in * bg_fade_out
	if bg_alpha > 0.001:
		_draw_bg_cover(w, h, bg_alpha)

	# === 蓝色光带 ===
	var band_alpha: float = _clamp01(wipe_p) * exit_alpha
	if band_alpha > 0.01:
		var bx: float = center_x - _band_perp_cos * perp_offset
		var by: float = center_y - _band_perp_sin * perp_offset
		if band_exit_offset > 0.1:
			bx += _band_cos * band_exit_offset
			by += _band_sin * band_exit_offset

		# 绘制旋转的光带 (用多边形近似)
		_draw_rotated_band(bx, by, diag_len, current_band_h, band_alpha)

	# === 日期元素 ===
	if t >= T_POPUP_START and wipe_p >= 0.99 and default_font:
		var date_spacing: float = w * 0.28

		# Phase 4: 滚动
		var scroll_p: float = 0.0
		if t > T_SCROLL_START:
			var raw_scroll: float = _clamp01((t - T_SCROLL_START) / T_SCROLL_DUR)
			scroll_p = _ease_out_elastic(raw_scroll)
		var scroll_off_x: float = -scroll_p * _date_cos * date_spacing
		var scroll_off_y: float = -scroll_p * _date_sin * date_spacing
		var highlight_p: float = _clamp01(scroll_p)

		# Phase 5: UI 滑出
		var ui_slide_x: float = 0.0
		var ui_slide_y: float = 0.0
		if ui_exit_offset > 0.1:
			ui_slide_x = -_date_cos * ui_exit_offset
			ui_slide_y = -_date_sin * ui_exit_offset

		var display_day: int = _day_count - 1
		var prev_dc: int = _day_count - 1
		var attention_center: float = prev_dc + highlight_p

		# 收集日期 slot 数据
		var date_slots: Array[Dictionary] = []
		for i in range(DATE_COUNT):
			var day_offset: int = i - (CURRENT_INDEX - 1)
			var dc: float = display_day + day_offset

			var base_pos_x: float = center_x + _date_cos * day_offset * date_spacing
			var base_pos_y: float = center_y + _date_sin * day_offset * date_spacing

			var pop_start: float = T_POPUP_START + i * T_POPUP_STAGGER
			var raw_t: float = _clamp01((t - pop_start) / T_POPUP_DUR)
			var pop_t: float = _ease_out_back(raw_t) if raw_t > 0 else 0.0

			var final_x: float = base_pos_x + scroll_off_x + ui_slide_x
			var final_y: float = base_pos_y + scroll_off_y + ui_slide_y

			var highlight_w: float = 0.0
			if dc == prev_dc:
				highlight_w = 1.0 - highlight_p
			elif dc == _day_count:
				highlight_w = highlight_p

			date_slots.append({
				"pos_x": final_x, "pos_y": final_y,
				"dc": dc, "idx": i, "pop_t": pop_t,
				"raw_alpha": raw_t, "highlight_w": highlight_w,
			})

		# 白色对角线
		var line_end_idx: int = 0
		for slot in date_slots:
			if slot["raw_alpha"] > 0.01:
				line_end_idx += 1
		if line_end_idx >= 1:
			var first_slot: Dictionary = date_slots[0]
			var last_visible: Dictionary = date_slots[mini(line_end_idx - 1, date_slots.size() - 1)]
			var extend: float = diag_len * 0.5
			var lx1: float = first_slot["pos_x"] - _date_cos * extend
			var ly1: float = first_slot["pos_y"] - _date_sin * extend
			var lx2: float = last_visible["pos_x"] + _date_cos * extend
			var ly2: float = last_visible["pos_y"] + _date_sin * extend
			var line_alpha: float = _clamp01(first_slot["raw_alpha"]) * exit_alpha * 0.6
			if line_alpha > 0.01:
				draw_line(Vector2(lx1, ly1), Vector2(lx2, ly2),
					Color(1, 1, 1, line_alpha), 1.5)

		# 绘制日期
		for slot in date_slots:
			if slot["pop_t"] <= 0.001:
				continue

			var dc: int = slot["dc"]
			var hw: float = slot["highlight_w"]
			var date_arr: Array = _calc_date(dc)
			var year: int = date_arr[0]
			var month: int = date_arr[1]
			var day: int = date_arr[2]
			var weekday: int = _calc_weekday(year, month, day)
			var day_str: String = str(day)
			var wd_str: String = WEEKDAY_NAMES[weekday]
			var weather: int = Weather.get_weather(dc)

			var pop_alpha: float = _clamp01(slot["raw_alpha"] * 2.5) * exit_alpha
			if pop_alpha <= 0.01:
				continue

			var bounce_y: float = 0.0
			if t < T_SCROLL_START:
				bounce_y = (1.0 - _clamp01(slot["raw_alpha"] * 3.0)) * 15.0

			var px: float = slot["pos_x"]
			var py: float = slot["pos_y"] + bounce_y

			# 距离注意力中心越远越小
			var day_off: float = absf(dc - attention_center)
			var small_scale: float = maxf(0.25, 0.50 - day_off * 0.04)
			var render_scale: float = small_scale + (1.0 - small_scale) * hw
			var alpha_scale: float = 0.4 + render_scale * 0.6
			var text_alpha: float = alpha_scale * pop_alpha

			var font_size: int = int(h * 0.15 * slot["pop_t"] * render_scale)
			if font_size < 4:
				continue

			# 日期数字
			draw_string(default_font, Vector2(px, py + font_size * 0.35),
				day_str, HORIZONTAL_ALIGNMENT_RIGHT,
				-1, font_size,
				Color(1, 1, 1, text_alpha))

			# 星期
			var wd_size: int = int(font_size * 0.28)
			var wd_x: float = px + font_size * 0.15
			var wd_y: float = py - font_size * 0.22
			draw_string(default_font, Vector2(wd_x, wd_y + wd_size * 0.8),
				wd_str, HORIZONTAL_ALIGNMENT_LEFT,
				-1, wd_size,
				Color(1, 1, 1, text_alpha * 0.85))

			# 星期下划线 (周日/周六/高亮项)
			var ul_color: Color = Color.WHITE
			if weekday == 0:  # SUN
				ul_color = Color(0.9, 0.23, 0.23)
			elif weekday == 6:  # SAT
				ul_color = Color(0.31, 0.78, 0.86)
			if weekday == 0 or weekday == 6 or hw > 0.3:
				draw_rect(
					Rect2(wd_x, wd_y + wd_size + 3, wd_size * 2.2, 2),
					Color(ul_color.r, ul_color.g, ul_color.b, text_alpha * 0.7))

		# 波纹 (滚动后)
		if t > T_RIPPLE_START:
			var ripple_p: float = _clamp01((t - T_RIPPLE_START) / T_RIPPLE_DUR)
			var ripple_cx: float = center_x + ui_slide_x
			var ripple_cy: float = center_y + ui_slide_y

			for ri in range(3):
				var delay_r: float = ri * 0.12
				var local_p: float = _clamp01((ripple_p - delay_r) / (1.0 - delay_r * 0.75))
				if local_p > 0:
					var max_r: float = h * (0.06 + ri * 0.04)
					var radius: float = local_p * max_r
					var a: float = (1.0 - local_p * local_p) * exit_alpha * 0.7
					if a > 0.01:
						draw_arc(Vector2(ripple_cx, ripple_cy), radius,
							0, TAU, 64,
							Color(0.63, 0.78, 1.0, a), 2.0 - local_p)

		# "第 X 天" 文字
		var month_pop_start: float = T_POPUP_START + DATE_COUNT * T_POPUP_STAGGER
		var month_raw_t: float = _clamp01((t - month_pop_start) / 0.4)
		var month_pop_t: float = _ease_out_back(month_raw_t) if month_raw_t > 0 else 0.0
		var month_alpha: float = _clamp01(month_raw_t * 2) * exit_alpha
		if month_alpha > 0.01 and default_font:
			var band_tan: float = tan(_band_angle_rad)
			var hud_x: float = w * 0.10
			var hud_y: float = center_y + band_tan * (hud_x - center_x)
			if band_exit_offset > 0.1:
				hud_x += _band_cos * band_exit_offset
				hud_y += _band_sin * band_exit_offset
			var bounce_hud: float = (1.0 - _clamp01(month_raw_t * 3)) * 20.0
			var day_label_fs: int = int(h * 0.09 * month_pop_t)
			if day_label_fs > 2:
				draw_string(default_font,
					Vector2(hud_x, hud_y + bounce_hud + day_label_fs * 0.35),
					"第 " + str(_day_count) + " 天",
					HORIZONTAL_ALIGNMENT_LEFT,
					-1, day_label_fs,
					Color(1, 1, 1, month_alpha))

		# 右下角年份月份
		if month_alpha > 0.01 and default_font:
			var date_arr: Array = _calc_date(_day_count)
			var year: int = date_arr[0]
			var month: int = date_arr[1]
			var mx: float = w * 0.95 + ui_slide_x
			var my: float = h * 0.92 + ui_slide_y
			var bounce_y2: float = (1.0 - _clamp01(month_raw_t * 3)) * 12.0
			var yr_fs: int = int(h * 0.035 * month_pop_t)
			if yr_fs > 2:
				draw_string(default_font,
					Vector2(mx, my + bounce_y2),
					str(year), HORIZONTAL_ALIGNMENT_RIGHT,
					-1, yr_fs,
					Color(0.7, 0.82, 0.94, month_alpha * 0.7))
				draw_string(default_font,
					Vector2(mx, my + bounce_y2 + yr_fs + 3),
					MONTH_NAMES[month - 1], HORIZONTAL_ALIGNMENT_RIGHT,
					-1, int(h * 0.03 * month_pop_t),
					Color(0.7, 0.82, 0.94, month_alpha * 0.6))

# ---------------------------------------------------------------------------
# 辅助绘制
# ---------------------------------------------------------------------------

func _draw_bg_cover(w: float, h: float, alpha: float) -> void:
	if _bg_texture:
		var tex_size: Vector2 = _bg_texture.get_size()
		var screen_aspect: float = w / h
		var tex_aspect: float = tex_size.x / tex_size.y
		var draw_w: float
		var draw_h: float
		var draw_x: float
		var draw_y: float
		if tex_aspect > screen_aspect:
			draw_h = h
			draw_w = h * tex_aspect
		else:
			draw_w = w
			draw_h = w / tex_aspect
		draw_x = (w - draw_w) * 0.5
		draw_y = (h - draw_h) * 0.5
		draw_texture_rect(_bg_texture, Rect2(draw_x, draw_y, draw_w, draw_h),
			false, Color(1, 1, 1, alpha))
		# 暗色叠加
		draw_rect(Rect2(-50, -50, w + 100, h + 100),
			Color(10/255.0, 10/255.0, 25/255.0, alpha * 0.45))
	else:
		# 无背景图时用深色填充
		draw_rect(Rect2(-50, -50, w + 100, h + 100),
			Color(13/255.0, 13/255.0, 26/255.0, alpha))

func _draw_rotated_band(cx: float, cy: float, length: float, band_h: float, alpha: float) -> void:
	# 绘制旋转的蓝色光带 (使用多边形)
	var half_len: float = length
	var half_h: float = band_h * 0.5

	# 光带四个角点 (沿 band 方向旋转)
	var dx: float = _band_cos * half_len
	var dy: float = _band_sin * half_len
	var nx: float = -_band_sin * half_h  # 法线方向
	var ny: float = _band_cos * half_h

	var points: PackedVector2Array = PackedVector2Array([
		Vector2(cx - dx + nx, cy - dy + ny),
		Vector2(cx + dx + nx, cy + dy + ny),
		Vector2(cx + dx - nx, cy + dy - ny),
		Vector2(cx - dx - nx, cy - dy - ny),
	])

	# 渐变色 (深蓝 → 亮蓝)
	var colors: PackedColorArray = PackedColorArray([
		Color(20/255.0, 50/255.0, 130/255.0, alpha),
		Color(35/255.0, 80/255.0, 170/255.0, alpha * 0.9),
		Color(35/255.0, 80/255.0, 170/255.0, alpha * 0.9),
		Color(20/255.0, 50/255.0, 130/255.0, alpha),
	])

	draw_polygon(points, colors)
