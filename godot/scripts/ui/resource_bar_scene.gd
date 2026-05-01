## ResourceBar — 顶部资源栏 HUD（场景化版本）
## 混合架构: 装饰性背景/资源数值保留 _draw()，退出按钮用 Button 节点
## 对应原版 ResourceBar.lua
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal dark_exit_pressed  # 暗面世界返回按钮被点击

# ---------------------------------------------------------------------------
# 节点引用
# ---------------------------------------------------------------------------
@onready var _strip_area: Control = $StripArea
@onready var _dark_exit_btn: Button = $DarkExitButton

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _display_values: Dictionary = { "san": 10.0, "order": 10.0, "money": 50.0 }
var _flash_timers: Dictionary = { "san": 0.0, "order": 0.0, "money": 0.0 }
var _flash_dirs: Dictionary = { "san": 0, "order": 0, "money": 0 }  # +1 增 / -1 减
var _delta_texts: Array = []  # { "key", "text", "timer", "color" }

const FLASH_DURATION: float = 0.6
const DELTA_DURATION: float = 1.2

# --- 暗面模式状态 ---
var _dark_mode: bool = false
var _dark_layer_name: String = ""
var _dark_energy: int = 0
var _dark_max_energy: int = 10
var _dark_layer_idx: int = 1
var _dark_layer_count: int = 3
var _dark_energy_flash: float = 0.0

# --- Tween 引用 ---
var _value_tweens: Dictionary = {}  # key -> Tween

# ---------------------------------------------------------------------------
# 常量 — 纸条布局 (与 Lua 版一致)
# ---------------------------------------------------------------------------
const MARGIN_X: int = 36
const MARGIN_TOP: int = 24
const STRIP_H: int = 108
const CORNER_R: float = 9.0
const PAD_X: int = 30
const LINE_SPACING: float = 27.0
const TAPE_W: float = 96.0
const TAPE_H: float = 30.0
const SEP_PAD: float = 18.0

# ---------------------------------------------------------------------------
# 资源定义
# ---------------------------------------------------------------------------
const RESOURCES_DEF: Array = [
	{ "key": "san",   "icon": "🧠", "label": "理智", "color_key": "info" },
	{ "key": "order", "icon": "⚖️",  "label": "秩序", "color_key": "safe" },
	{ "key": "money", "icon": "💰", "label": "钱币", "color_key": "warning" },
]

# ---------------------------------------------------------------------------
# 暗面模式 API
# ---------------------------------------------------------------------------

func set_dark_mode(enabled: bool, opts: Dictionary = {}) -> void:
	_dark_mode = enabled
	if enabled:
		_dark_layer_name = opts.get("layer_name", "")
		_dark_energy = opts.get("energy", 0)
		_dark_max_energy = opts.get("max_energy", 10)
		_dark_layer_idx = opts.get("layer_idx", 1)
		_dark_layer_count = opts.get("layer_count", 3)
	_dark_exit_btn.visible = enabled
	queue_redraw()

func update_dark_energy(energy: int, max_energy: int = -1) -> void:
	if _dark_mode:
		_dark_energy = energy
		if max_energy >= 0:
			_dark_max_energy = max_energy
		queue_redraw()

func flash_dark_energy() -> void:
	_dark_energy_flash = 0.5

func is_dark_mode() -> bool:
	return _dark_mode

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	GameData.resource_changed.connect(_on_resource_changed)
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size.y = 156

	# 退出按钮 — 用 Button 节点替代手动 hit-test
	_dark_exit_btn.visible = false
	_dark_exit_btn.pressed.connect(_on_dark_exit_pressed)
	_apply_dark_exit_style()

	# StripArea 连接 draw 信号，由我们来绘制装饰和内容
	_strip_area.draw.connect(_on_strip_draw)

func _apply_dark_exit_style() -> void:
	# 按钮样式: 暗紫色圆角背景
	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = Color(0.137, 0.11, 0.235, 0.86)
	normal_sb.border_color = Color(0.545, 0.361, 0.965, 0.31)
	normal_sb.set_border_width_all(1)
	normal_sb.set_corner_radius_all(30)
	normal_sb.set_content_margin_all(12)
	_dark_exit_btn.add_theme_stylebox_override("normal", normal_sb)

	var hover_sb := normal_sb.duplicate()
	hover_sb.bg_color = Color(0.18, 0.14, 0.3, 0.92)
	_dark_exit_btn.add_theme_stylebox_override("hover", hover_sb)

	var pressed_sb := normal_sb.duplicate()
	pressed_sb.bg_color = Color(0.22, 0.18, 0.36, 0.95)
	_dark_exit_btn.add_theme_stylebox_override("pressed", pressed_sb)

	_dark_exit_btn.add_theme_color_override("font_color", Color(0.784, 0.706, 1.0, 0.9))
	_dark_exit_btn.add_theme_color_override("font_hover_color", Color(0.85, 0.78, 1.0, 1.0))
	_dark_exit_btn.add_theme_font_size_override("font_size", 36)

func _on_dark_exit_pressed() -> void:
	dark_exit_pressed.emit()

func _on_resource_changed(key: String, old_value: int, new_value: int) -> void:
	if key in _flash_timers:
		_flash_timers[key] = FLASH_DURATION
		var delta_val: int = new_value - old_value
		_flash_dirs[key] = 1 if delta_val > 0 else -1

		# P5: Tween-driven easeOutCubic value transition
		if _value_tweens.has(key) and _value_tweens[key] != null and _value_tweens[key].is_valid():
			_value_tweens[key].kill()
		var val_tw: Tween = create_tween()
		val_tw.tween_method(func(v: float):
			_display_values[key] = v
			_strip_area.queue_redraw()
		, _display_values[key], float(new_value), 0.35) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_value_tweens[key] = val_tw

		if delta_val != 0:
			var prefix: String = "+" if delta_val > 0 else ""
			# P6: Tween-driven delta text float + fade
			var dt_entry: Dictionary = {
				"key": key,
				"text": prefix + str(delta_val),
				"progress": 0.0,
				"color": GameTheme.safe if delta_val > 0 else GameTheme.danger,
			}
			_delta_texts.append(dt_entry)
			var dt_tw: Tween = create_tween()
			dt_tw.tween_method(func(p: float):
				dt_entry["progress"] = p
				_strip_area.queue_redraw()
			, 0.0, 1.0, DELTA_DURATION) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			dt_tw.tween_callback(func():
				_delta_texts.erase(dt_entry)
				_strip_area.queue_redraw()
			)

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	var needs_redraw: bool = false

	# P5: 数值平滑已由 Tween 驱动，此处无需 lerp
	# P6: 飘字动画已由 Tween 驱动，此处无需手动计时

	# 闪光衰减
	for key in _flash_timers:
		if _flash_timers[key] > 0:
			_flash_timers[key] -= delta
			needs_redraw = true

	# 暗面能量闪光
	if _dark_energy_flash > 0:
		_dark_energy_flash -= delta
		needs_redraw = true

	if needs_redraw:
		_strip_area.queue_redraw()

# ---------------------------------------------------------------------------
# StripArea draw — 所有装饰与内容绘制委托至此
# ---------------------------------------------------------------------------
func _on_strip_draw() -> void:
	var w: float = _strip_area.size.x
	var font: Font = ThemeDB.fallback_font
	var t = GameTheme

	# === 纸条几何 ===
	var strip_w: float = minf(w - MARGIN_X * 2, 1080.0)
	var strip_x: float = (w - strip_w) / 2.0
	var strip_y: float = float(MARGIN_TOP)
	var strip_cy: float = strip_y + STRIP_H / 2.0

	if _dark_mode:
		_draw_dark_strip(strip_x, strip_y, strip_w, strip_cy, font, t)
	else:
		_draw_normal_strip(strip_x, strip_y, strip_w, strip_cy, font, t)

	# === 资源内容 (两种模式共享) ===
	_draw_resources(strip_x, strip_y, strip_w, strip_cy, font, t)

	# === 右半区域 ===
	var right_x: float = strip_x + strip_w - PAD_X - 18.0
	if _dark_mode:
		_draw_dark_right(strip_x, strip_y, strip_w, strip_cy, right_x, font, t)
	else:
		_draw_normal_right(strip_y, strip_cy, right_x, font, t)

	# === 飘字 ===
	_draw_delta_texts(strip_cy, font)

	# === 暗面退出按钮位置更新 ===
	if _dark_mode:
		_update_dark_exit_position(strip_x, strip_y, strip_w)


# ---------------------------------------------------------------------------
# 暗面退出按钮位置同步 — 基于 strip 几何计算
# ---------------------------------------------------------------------------
func _update_dark_exit_position(sx: float, sy: float, sw: float) -> void:
	var icon_r: float = 30.0
	var right_x: float = sx + sw - PAD_X - 18.0
	var btn_w: float = 180.0
	var btn_h: float = 84.0
	var btn_x: float = right_x - icon_r - btn_w / 2.0 - 30.0
	var btn_y: float = sy + (STRIP_H - btn_h) / 2.0
	_dark_exit_btn.position = Vector2(btn_x, btn_y)
	_dark_exit_btn.size = Vector2(btn_w, btn_h)


# ---------------------------------------------------------------------------
# 现实模式纸条背景
# ---------------------------------------------------------------------------
func _draw_normal_strip(sx: float, sy: float, sw: float, _scy: float,
		_font: Font, t) -> void:
	# 纸张阴影
	var shadow_rect: Rect2 = Rect2(sx - 12, sy + 3, sw + 24, STRIP_H + 18)
	_strip_area.draw_rect(shadow_rect, Color(0.23, 0.16, 0.08, 0.12))

	# 纸条主体
	_strip_area.draw_rect(Rect2(sx, sy, sw, STRIP_H), Color(t.notebook_paper, 0.95))

	# 横线纹理 (淡蓝色)
	var line_y: float = sy + LINE_SPACING * 0.6
	while line_y < sy + STRIP_H:
		_strip_area.draw_line(Vector2(sx + 12, line_y), Vector2(sx + sw - 12, line_y),
			Color(t.notebook_line, 0.2), 1.5)
		line_y += LINE_SPACING

	# 底部撕裂边缘
	_draw_torn_edge(sx, sy + STRIP_H, sw, t.notebook_paper)

	# 三边边框 (底部留给撕裂)
	var border_color: Color = Color(t.notebook_border, 0.4)
	_strip_area.draw_line(Vector2(sx, sy + STRIP_H), Vector2(sx, sy), border_color, 2.4)
	_strip_area.draw_line(Vector2(sx, sy), Vector2(sx + sw, sy), border_color, 2.4)
	_strip_area.draw_line(Vector2(sx + sw, sy), Vector2(sx + sw, sy + STRIP_H), border_color, 2.4)

	# 胶带装饰
	_draw_tape(Vector2(sx + 48, sy + 3), TAPE_W, TAPE_H, -0.12)
	_draw_tape(Vector2(sx + sw - 48, sy + 3), TAPE_W, TAPE_H, 0.10)


# ---------------------------------------------------------------------------
# 暗面模式石板背景
# ---------------------------------------------------------------------------
func _draw_dark_strip(sx: float, sy: float, sw: float, _scy: float,
		_font: Font, _t) -> void:
	# 深邃阴影
	var shadow_rect: Rect2 = Rect2(sx - 18, sy - 6, sw + 36, STRIP_H + 30)
	_strip_area.draw_rect(shadow_rect, Color(0.03, 0.015, 0.08, 0.35))

	# 面板主体 (深紫渐变 — 两段模拟)
	var top_color: Color = Color(0.118, 0.094, 0.196, 0.88)
	var bot_color: Color = Color(0.071, 0.055, 0.137, 0.94)
	_strip_area.draw_rect(Rect2(sx, sy, sw, STRIP_H / 2), top_color)
	_strip_area.draw_rect(Rect2(sx, sy + STRIP_H / 2, sw, STRIP_H / 2), bot_color)

	# 横纹灵纹 (暗紫)
	var line_y: float = sy + LINE_SPACING * 0.6
	var vein_color: Color = Color(0.545, 0.361, 0.965, 0.06)
	while line_y < sy + STRIP_H:
		_strip_area.draw_line(Vector2(sx + 12, line_y), Vector2(sx + sw - 12, line_y),
			vein_color, 1.2)
		line_y += LINE_SPACING

	# 底部腐蚀边缘
	_draw_dark_edge(sx, sy + STRIP_H, sw)

	# 上缘灵光
	var glow_color: Color = Color(0.545, 0.361, 0.965, 0.18)
	_strip_area.draw_rect(Rect2(sx, sy, sw, 12), glow_color)
	_strip_area.draw_rect(Rect2(sx, sy + 12, sw, 12), Color(0.545, 0.361, 0.965, 0.06))

	# 三边边框 (暗紫)
	var border_color: Color = Color(0.545, 0.361, 0.965, 0.22)
	_strip_area.draw_line(Vector2(sx, sy + STRIP_H), Vector2(sx, sy), border_color, 2.4)
	_strip_area.draw_line(Vector2(sx, sy), Vector2(sx + sw, sy), border_color, 2.4)
	_strip_area.draw_line(Vector2(sx + sw, sy), Vector2(sx + sw, sy + STRIP_H), border_color, 2.4)

	# 封印装饰 (对应胶带)
	_draw_dark_seal(Vector2(sx + 48, sy + 3), TAPE_W, TAPE_H, -0.12)
	_draw_dark_seal(Vector2(sx + sw - 48, sy + 3), TAPE_W, TAPE_H, 0.10)


# ---------------------------------------------------------------------------
# 资源内容 (两模式共享)
# ---------------------------------------------------------------------------
func _draw_resources(sx: float, sy: float, _sw: float,
		scy: float, font: Font, t) -> void:
	var cx: float = sx + PAD_X + 18.0
	var count: int = RESOURCES_DEF.size()

	for i in count:
		var res_def: Dictionary = RESOURCES_DEF[i]
		var key: String = res_def["key"]
		var icon_str: String = res_def["icon"]
		var label_str: String = res_def["label"]
		var color_key: String = res_def["color_key"]
		var rc: Color = t.get(color_key) if t.get(color_key) else t.text_primary
		var display_num: int = int(round(_display_values[key]))

		# --- 图标 ---
		var icon_color: Color
		if _dark_mode:
			icon_color = Color(0.784, 0.706, 1.0, 0.86)
		else:
			icon_color = Color(t.text_primary, 0.78)
		_strip_area.draw_string(font, Vector2(cx, scy + 6), icon_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 45, icon_color)
		var icon_w: float = font.get_string_size(icon_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 45).x
		var icon_end: float = cx + icon_w

		# --- 标签 (手写小字) ---
		var label_color: Color
		if _dark_mode:
			label_color = Color(0.706, 0.627, 0.863, 0.63)
		else:
			label_color = Color(t.text_secondary, 0.63)
		_strip_area.draw_string(font, Vector2(icon_end + 3, scy - 15), label_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 27, label_color)
		var label_w: float = font.get_string_size(label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x

		# --- 数值 ---
		var val_str: String = str(display_num)
		var val_color: Color = rc
		var flash_t: float = _flash_timers.get(key, 0.0)
		if flash_t > 0:
			var pulse: float = 0.5 + 0.5 * sin(flash_t * 20.0)
			var flash_dir: int = _flash_dirs.get(key, 0)
			if flash_dir > 0:
				val_color = rc.lerp(t.safe, pulse)
			else:
				val_color = rc.lerp(t.danger, pulse)
		elif _dark_mode:
			val_color = Color(rc, 0.78)

		_strip_area.draw_string(font, Vector2(icon_end + 3, scy + 27), val_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 45, val_color)
		var num_w: float = font.get_string_size(val_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 45).x

		# --- 分隔竖线 ---
		var next_x: float = icon_end + 3 + maxf(num_w, label_w) + 30.0
		if i < count - 1:
			var sep_color: Color
			if _dark_mode:
				sep_color = Color(0.545, 0.361, 0.965, 0.2)
			else:
				sep_color = Color(t.notebook_border, 0.4)
			_strip_area.draw_line(Vector2(next_x, sy + SEP_PAD),
				Vector2(next_x, sy + STRIP_H - SEP_PAD), sep_color, 0.8)
			cx = next_x + 24.0
		else:
			cx = next_x


# ---------------------------------------------------------------------------
# 右半: 现实模式 — 天数 + 天气
# ---------------------------------------------------------------------------
func _draw_normal_right(sy: float, scy: float, right_x: float,
		font: Font, t) -> void:
	var day: int = GameData.current_day
	if day <= 0:
		return

	var weather_type: int = Weather.get_weather(day)
	var weather_icon: String = Weather.get_icon(weather_type)
	var weather_name: String = Weather.get_weather_name(weather_type)

	# 天气图标
	_strip_area.draw_string(font, Vector2(right_x - 42, scy + 6), weather_icon,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 42, Color(t.text_primary, 0.86))

	# 天气名 (小字)
	_strip_area.draw_string(font, Vector2(right_x - 108, scy + 27), weather_name,
		HORIZONTAL_ALIGNMENT_RIGHT, -1, 27, Color(t.text_secondary, 0.63))

	# Day X (主文字)
	var day_text: String = "Day " + str(day)
	var day_text_w: float = font.get_string_size(day_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x
	var day_right: float = right_x - 108.0
	_strip_area.draw_string(font, Vector2(day_right - day_text_w, scy - 6), day_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 42, Color(t.text_primary, 0.86))

	# "第X天" (副文字)
	var sub_text: String = "第" + str(day) + "天"
	var sub_w: float = font.get_string_size(sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x
	_strip_area.draw_string(font, Vector2(day_right - sub_w, scy + 27), sub_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color(t.text_secondary, 0.55))

	# 分隔竖线
	var sep_x: float = day_right - maxf(day_text_w, sub_w) - 24.0
	_strip_area.draw_line(Vector2(sep_x, sy + SEP_PAD),
		Vector2(sep_x, sy + STRIP_H - SEP_PAD),
		Color(t.notebook_border, 0.4), 0.8)


# ---------------------------------------------------------------------------
# 右半: 暗面模式 — 层级 + 能量 (退出按钮已由 Button 节点处理)
# ---------------------------------------------------------------------------
func _draw_dark_right(sx: float, sy: float, _sw: float, scy: float,
		right_x: float, font: Font, _t) -> void:
	# 退出按钮区域不再手动绘制——由 DarkExitButton 节点负责

	# --- 层级信息组 (退出按钮左侧) ---
	var info_right_x: float = right_x - 180.0 - 24.0  # 留出按钮宽度

	# 层级名称 (主文字)
	var layer_name: String = _dark_layer_name if _dark_layer_name != "" else "暗面"
	var layer_w: float = font.get_string_size(layer_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x
	_strip_area.draw_string(font, Vector2(info_right_x - layer_w, scy - 6), layer_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 42, Color(0.133, 0.827, 0.933, 0.86))

	# 能量副行
	var energy_ratio: float = float(_dark_energy) / maxf(float(_dark_max_energy), 1.0)
	var energy_text: String = "⚡" + str(_dark_energy) + "/" + str(_dark_max_energy)

	# 能量颜色 (低于 30% 变红)
	var e_color: Color
	if energy_ratio <= 0.3:
		e_color = Color(0.957, 0.247, 0.369)  # #F43F5E
	else:
		e_color = Color(0.133, 0.827, 0.933)   # #22D3EE

	# 闪光
	var flash_alpha: float = 0.63
	if _dark_energy_flash > 0:
		flash_alpha = 0.5 + 0.5 * sin(_dark_energy_flash * 20.0)
	e_color.a = flash_alpha

	# 能量文字
	var energy_text_w: float = font.get_string_size(energy_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x
	_strip_area.draw_string(font, Vector2(info_right_x - energy_text_w, scy + 27), energy_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 27, e_color)

	# 迷你能量条 (能量文字左侧)
	var mini_bar_w: float = 90.0
	var mini_bar_h: float = 12.0
	var m_bar_x: float = info_right_x - energy_text_w - mini_bar_w - 9.0
	var m_bar_y: float = scy + 15 - mini_bar_h / 2.0

	# 背景槽
	_strip_area.draw_rect(Rect2(m_bar_x, m_bar_y, mini_bar_w, mini_bar_h),
		Color(0.078, 0.059, 0.157, 0.71))

	# 填充
	var fill_w: float = mini_bar_w * energy_ratio
	if fill_w > 0:
		_strip_area.draw_rect(Rect2(m_bar_x, m_bar_y, fill_w, mini_bar_h), e_color)

	# --- 分隔线 (层级组和资源区之间) ---
	var sep_x: float = info_right_x - maxf(layer_w, energy_text_w + mini_bar_w + 9) - 24.0
	_strip_area.draw_line(Vector2(sep_x, sy + SEP_PAD),
		Vector2(sep_x, sy + STRIP_H - SEP_PAD),
		Color(0.545, 0.361, 0.965, 0.2), 0.8)


# ---------------------------------------------------------------------------
# 飘字
# ---------------------------------------------------------------------------
func _draw_delta_texts(scy: float, font: Font) -> void:
	for dt in _delta_texts:
		var progress: float = dt["progress"]
		var alpha: float = 1.0 - progress
		var offset_y: float = -60.0 * progress
		var color: Color = dt["color"]
		color.a = alpha

		var dx: float = 180.0
		match dt["key"]:
			"order": dx = 390.0
			"money": dx = 600.0

		_strip_area.draw_string(font, Vector2(dx, scy - 24 + offset_y), dt["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 36, color)


# ---------------------------------------------------------------------------
# 辅助: 撕裂边缘 (现实模式底部)
# ---------------------------------------------------------------------------
func _draw_torn_edge(x: float, y: float, w: float, base_color: Color) -> void:
	var tear_color: Color = Color(base_color, 0.6)
	var step: float = 15.0
	var cx: float = x
	var i: int = 0
	while cx < x + w:
		var _next_x: float = minf(cx + step, x + w)
		var dy: float = 4.5 if (i % 2 == 0) else -1.5
		var jitter: float = sin(cx * 1.7) * 2.4
		var rect_h: float = 6.0 + absf(dy + jitter)
		_strip_area.draw_rect(Rect2(cx, y, step * 0.7, rect_h), tear_color)
		cx = _next_x
		i += 1


# ---------------------------------------------------------------------------
# 辅助: 腐蚀边缘 (暗面模式底部)
# ---------------------------------------------------------------------------
func _draw_dark_edge(x: float, y: float, w: float) -> void:
	var edge_color: Color = Color(0.071, 0.055, 0.137, 0.94)
	var step: float = 12.0
	var cx: float = x
	var i: int = 0
	while cx < x + w:
		var _next_x: float = minf(cx + step, x + w)
		var dy: float = 6.0 if (i % 2 == 0) else -0.9
		var jitter: float = sin(cx * 2.1 + 0.7) * 3.6
		var rect_h: float = 6.0 + absf(dy + jitter)
		_strip_area.draw_rect(Rect2(cx, y, step * 0.7, rect_h), edge_color)
		cx = _next_x
		i += 1


# ---------------------------------------------------------------------------
# 辅助: 胶带装饰 (现实模式)
# ---------------------------------------------------------------------------
func _draw_tape(center: Vector2, tw: float, th: float, angle: float) -> void:
	var tape_color: Color = Color(0.961, 0.922, 0.784, 0.24)
	var tape_border: Color = Color(0.863, 0.824, 0.706, 0.16)

	var xf: Transform2D = Transform2D()
	xf = xf.translated(-center)
	xf = xf.rotated(angle)
	xf = xf.translated(center)
	_strip_area.draw_set_transform_matrix(xf)

	_strip_area.draw_rect(Rect2(center.x - tw / 2, center.y - th / 2, tw, th), tape_color)
	_strip_area.draw_rect(Rect2(center.x - tw / 2, center.y - th / 2, tw, th), tape_border, false, 0.5)

	_strip_area.draw_set_transform_matrix(Transform2D.IDENTITY)


# ---------------------------------------------------------------------------
# 辅助: 暗面封印装饰 (暗面模式)
# ---------------------------------------------------------------------------
func _draw_dark_seal(center: Vector2, tw: float, th: float, angle: float) -> void:
	var seal_body: Color = Color(0.545, 0.361, 0.965, 0.10)
	var seal_line: Color = Color(0.133, 0.827, 0.933, 0.14)
	var seal_border: Color = Color(0.545, 0.361, 0.965, 0.14)

	var xf: Transform2D = Transform2D()
	xf = xf.translated(-center)
	xf = xf.rotated(angle)
	xf = xf.translated(center)
	_strip_area.draw_set_transform_matrix(xf)

	# 封印主体
	_strip_area.draw_rect(Rect2(center.x - tw / 2, center.y - th / 2, tw, th), seal_body)

	# 中线灵纹
	_strip_area.draw_line(Vector2(center.x - tw / 2 + 12, center.y),
		Vector2(center.x + tw / 2 - 12, center.y), seal_line, 1.2)

	# 两端节点
	_strip_area.draw_circle(Vector2(center.x - tw / 2 + 15, center.y), 3.0,
		Color(0.133, 0.827, 0.933, 0.18))
	_strip_area.draw_circle(Vector2(center.x + tw / 2 - 15, center.y), 3.0,
		Color(0.133, 0.827, 0.933, 0.18))

	# 边框轮廓
	_strip_area.draw_rect(Rect2(center.x - tw / 2, center.y - th / 2, tw, th),
		seal_border, false, 0.5)

	_strip_area.draw_set_transform_matrix(Transform2D.IDENTITY)
