## ResourceBar - 顶部资源栏 HUD
## 对应原版 ResourceBar.lua
## 显示 san, order, money + 天数/天气
## 暗面模式: 层级名、能量条、🌀返回按钮
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal dark_exit_pressed  # 暗面世界返回按钮被点击

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

# 退出按钮几何缓存 (用于 hit test)
var _dark_exit_rect: Rect2 = Rect2()

# ---------------------------------------------------------------------------
# 常量 — 纸条布局 (与 Lua 版一致)
# ---------------------------------------------------------------------------
const MARGIN_X: int = 12
const MARGIN_TOP: int = 8
const STRIP_H: int = 36
const CORNER_R: float = 3.0
const PAD_X: int = 10
const LINE_SPACING: float = 9.0
const TAPE_W: float = 32.0
const TAPE_H: float = 10.0
const SEP_PAD: float = 6.0

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
	mouse_filter = Control.MOUSE_FILTER_PASS  # 需要接收暗面退出按钮点击
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size.y = 52  # 比纯纸条多一点空间给撕裂边

func _on_resource_changed(key: String, old_value: int, new_value: int) -> void:
	if key in _flash_timers:
		_flash_timers[key] = FLASH_DURATION
		var delta_val: int = new_value - old_value
		_flash_dirs[key] = 1 if delta_val > 0 else -1
		if delta_val != 0:
			var prefix: String = "+" if delta_val > 0 else ""
			_delta_texts.append({
				"key": key,
				"text": prefix + str(delta_val),
				"timer": 0.0,
				"color": GameTheme.safe if delta_val > 0 else GameTheme.danger,
			})

# ---------------------------------------------------------------------------
# 输入: 暗面退出按钮
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if not _dark_mode:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _dark_exit_rect.has_point(mb.position):
				dark_exit_pressed.emit()
				accept_event()

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	var needs_redraw: bool = false

	# 平滑数值过渡
	for key in _display_values:
		var target: float = float(GameData.get_resource(key))
		var old_val: float = _display_values[key]
		_display_values[key] = lerpf(old_val, target, minf(1.0, delta * 8.0))
		if absf(_display_values[key] - old_val) > 0.01:
			needs_redraw = true

	# 闪光衰减
	for key in _flash_timers:
		if _flash_timers[key] > 0:
			_flash_timers[key] -= delta
			needs_redraw = true

	# 飘字衰减
	var i: float = _delta_texts.size() - 1
	while i >= 0:
		_delta_texts[i]["timer"] += delta
		if _delta_texts[i]["timer"] > DELTA_DURATION:
			_delta_texts.remove_at(i)
		i -= 1
		needs_redraw = true

	# 暗面能量闪光
	if _dark_energy_flash > 0:
		_dark_energy_flash -= delta
		needs_redraw = true

	if needs_redraw:
		queue_redraw()

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _draw() -> void:
	var w: float = size.x
	var font: Font = ThemeDB.fallback_font
	var t = GameTheme  # Autoload

	# === 纸条几何 ===
	var strip_w: float = minf(w - MARGIN_X * 2, 360.0)
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
	var right_x: float = strip_x + strip_w - PAD_X - 6.0
	if _dark_mode:
		_draw_dark_right(strip_x, strip_y, strip_w, strip_cy, right_x, font, t)
	else:
		_draw_normal_right(strip_y, strip_cy, right_x, font, t)

	# === 飘字 ===
	_draw_delta_texts(strip_cy, font)


# ---------------------------------------------------------------------------
# 现实模式纸条背景
# ---------------------------------------------------------------------------
func _draw_normal_strip(sx: float, sy: float, sw: float, _scy: float,
		_font: Font, t) -> void:
	# 纸张阴影
	var shadow_rect: Rect2 = Rect2(sx - 4, sy + 1, sw + 8, STRIP_H + 6)
	draw_rect(shadow_rect, Color(0.23, 0.16, 0.08, 0.12))

	# 纸条主体
	draw_rect(Rect2(sx, sy, sw, STRIP_H), Color(t.notebook_paper, 0.95))

	# 横线纹理 (淡蓝色)
	var line_y: float = sy + LINE_SPACING * 0.6
	while line_y < sy + STRIP_H:
		draw_line(Vector2(sx + 4, line_y), Vector2(sx + sw - 4, line_y),
			Color(t.notebook_line, 0.2), 0.5)
		line_y += LINE_SPACING

	# 底部撕裂边缘
	_draw_torn_edge(sx, sy + STRIP_H, sw, t.notebook_paper)

	# 三边边框 (底部留给撕裂)
	var border_color: Color = Color(t.notebook_border, 0.4)
	draw_line(Vector2(sx, sy + STRIP_H), Vector2(sx, sy), border_color, 0.8)
	draw_line(Vector2(sx, sy), Vector2(sx + sw, sy), border_color, 0.8)
	draw_line(Vector2(sx + sw, sy), Vector2(sx + sw, sy + STRIP_H), border_color, 0.8)

	# 胶带装饰
	_draw_tape(Vector2(sx + 16, sy + 1), TAPE_W, TAPE_H, -0.12)
	_draw_tape(Vector2(sx + sw - 16, sy + 1), TAPE_W, TAPE_H, 0.10)


# ---------------------------------------------------------------------------
# 暗面模式石板背景
# ---------------------------------------------------------------------------
func _draw_dark_strip(sx: float, sy: float, sw: float, _scy: float,
		_font: Font, _t) -> void:
	# 深邃阴影
	var shadow_rect: Rect2 = Rect2(sx - 6, sy - 2, sw + 12, STRIP_H + 10)
	draw_rect(shadow_rect, Color(0.03, 0.015, 0.08, 0.35))

	# 面板主体 (深紫渐变)
	# Godot _draw 没有渐变 rect，用两段模拟
	var top_color: Color = Color(0.118, 0.094, 0.196, 0.88)  # (30,24,50)/255
	var bot_color: Color = Color(0.071, 0.055, 0.137, 0.94)  # (18,14,35)/255
	draw_rect(Rect2(sx, sy, sw, STRIP_H / 2), top_color)
	draw_rect(Rect2(sx, sy + STRIP_H / 2, sw, STRIP_H / 2), bot_color)

	# 横纹灵纹 (暗紫, 对应笔记本横线)
	var line_y: float = sy + LINE_SPACING * 0.6
	var vein_color: Color = Color(0.545, 0.361, 0.965, 0.06)  # #8B5CF6 alpha 16/255
	while line_y < sy + STRIP_H:
		draw_line(Vector2(sx + 4, line_y), Vector2(sx + sw - 4, line_y),
			vein_color, 0.4)
		line_y += LINE_SPACING

	# 底部腐蚀边缘
	_draw_dark_edge(sx, sy + STRIP_H, sw)

	# 上缘灵光
	var glow_color: Color = Color(0.545, 0.361, 0.965, 0.18)
	draw_rect(Rect2(sx, sy, sw, 4), glow_color)
	draw_rect(Rect2(sx, sy + 4, sw, 4), Color(0.545, 0.361, 0.965, 0.06))

	# 三边边框 (暗紫)
	var border_color: Color = Color(0.545, 0.361, 0.965, 0.22)
	draw_line(Vector2(sx, sy + STRIP_H), Vector2(sx, sy), border_color, 0.8)
	draw_line(Vector2(sx, sy), Vector2(sx + sw, sy), border_color, 0.8)
	draw_line(Vector2(sx + sw, sy), Vector2(sx + sw, sy + STRIP_H), border_color, 0.8)

	# 封印装饰 (对应胶带)
	_draw_dark_seal(Vector2(sx + 16, sy + 1), TAPE_W, TAPE_H, -0.12)
	_draw_dark_seal(Vector2(sx + sw - 16, sy + 1), TAPE_W, TAPE_H, 0.10)


# ---------------------------------------------------------------------------
# 资源内容 (两模式共享)
# ---------------------------------------------------------------------------
func _draw_resources(sx: float, sy: float, _sw: float,
		scy: float, font: Font, t) -> void:
	var cx: float = sx + PAD_X + 6.0
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
			icon_color = Color(0.784, 0.706, 1.0, 0.86)  # 200,180,255 / 220
		else:
			icon_color = Color(t.text_primary, 0.78)
		draw_string(font, Vector2(cx, scy + 2), icon_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, icon_color)
		var icon_w: float = font.get_string_size(icon_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var icon_end: float = cx + icon_w

		# --- 标签 (手写小字) ---
		var label_color: Color
		if _dark_mode:
			label_color = Color(0.706, 0.627, 0.863, 0.63)
		else:
			label_color = Color(t.text_secondary, 0.63)
		draw_string(font, Vector2(icon_end + 1, scy - 5), label_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, label_color)
		var label_w: float = font.get_string_size(label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x

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

		draw_string(font, Vector2(icon_end + 1, scy + 9), val_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, val_color)
		var num_w: float = font.get_string_size(val_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x

		# --- 分隔竖线 ---
		var next_x: float = icon_end + 1 + maxf(num_w, label_w) + 10.0
		if i < count - 1:
			var sep_color: Color
			if _dark_mode:
				sep_color = Color(0.545, 0.361, 0.965, 0.2)
			else:
				sep_color = Color(t.notebook_border, 0.4)
			draw_line(Vector2(next_x, sy + SEP_PAD),
				Vector2(next_x, sy + STRIP_H - SEP_PAD), sep_color, 0.8)
			cx = next_x + 8.0
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
	var weather_name: String = Weather.get_name(weather_type)

	# 天气图标
	draw_string(font, Vector2(right_x - 14, scy + 2), weather_icon,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(t.text_primary, 0.86))

	# 天气名 (小字)
	draw_string(font, Vector2(right_x - 36, scy + 9), weather_name,
		HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color(t.text_secondary, 0.63))

	# Day X (主文字)
	var day_text: String = "Day " + str(day)
	var day_text_w: float = font.get_string_size(day_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var day_right: float = right_x - 36.0
	draw_string(font, Vector2(day_right - day_text_w, scy - 2), day_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(t.text_primary, 0.86))

	# "第X天" (副文字)
	var sub_text: String = "第" + str(day) + "天"
	var sub_w: float = font.get_string_size(sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(font, Vector2(day_right - sub_w, scy + 9), sub_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(t.text_secondary, 0.55))

	# 分隔竖线
	var sep_x: float = day_right - maxf(day_text_w, sub_w) - 8.0
	draw_line(Vector2(sep_x, sy + SEP_PAD),
		Vector2(sep_x, sy + STRIP_H - SEP_PAD),
		Color(t.notebook_border, 0.4), 0.8)


# ---------------------------------------------------------------------------
# 右半: 暗面模式 — 层级 + 能量 + 🌀返回
# ---------------------------------------------------------------------------
func _draw_dark_right(sx: float, sy: float, _sw: float, scy: float,
		right_x: float, font: Font, _t) -> void:
	var icon_r: float = 10.0
	var icon_cx: float = right_x - icon_r
	var icon_cy: float = scy

	# --- 返回按钮外圈光晕 ---
	var glow_alpha: float = 0.2
	draw_circle(Vector2(icon_cx, icon_cy), icon_r * 1.3,
		Color(0.545, 0.361, 0.965, glow_alpha))

	# 圆形背景
	draw_circle(Vector2(icon_cx, icon_cy), icon_r,
		Color(0.137, 0.11, 0.235, 0.86))

	# 圆形边框 (用多段弧近似)
	_draw_circle_outline(Vector2(icon_cx, icon_cy), icon_r,
		Color(0.545, 0.361, 0.965, 0.31), 0.8)

	# 🌀 图标居中
	draw_string(font, Vector2(icon_cx - 6, icon_cy + 5), "🌀",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.784, 0.706, 1.0, 0.9))

	# "返回" 小字
	draw_string(font, Vector2(icon_cx - icon_r - 26, scy + 9), "返回",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.706, 0.627, 0.863, 0.63))

	# 缓存退出按钮点击区域
	_dark_exit_rect = Rect2(icon_cx - icon_r - 30, sy, icon_r * 2 + 30 + PAD_X, STRIP_H)

	# --- 层级信息组 ---
	var info_right_x: float = icon_cx - icon_r * 2 - 8.0

	# 层级名称 (主文字)
	var layer_name: bool = _dark_layer_name if _dark_layer_name != "" else "暗面"
	var layer_w: float = font.get_string_size(layer_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2(info_right_x - layer_w, scy - 2), layer_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.133, 0.827, 0.933, 0.86))  # #22D3EE

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
	var energy_text_w: float = font.get_string_size(energy_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(font, Vector2(info_right_x - energy_text_w, scy + 9), energy_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, e_color)

	# 迷你能量条 (能量文字左侧)
	var mini_bar_w: float = 30.0
	var mini_bar_h: float = 4.0
	var m_bar_x: float = info_right_x - energy_text_w - mini_bar_w - 3.0
	var m_bar_y: float = scy + 5 - mini_bar_h / 2.0

	# 背景槽
	draw_rect(Rect2(m_bar_x, m_bar_y, mini_bar_w, mini_bar_h),
		Color(0.078, 0.059, 0.157, 0.71))

	# 填充
	var fill_w: float = mini_bar_w * energy_ratio
	if fill_w > 0:
		draw_rect(Rect2(m_bar_x, m_bar_y, fill_w, mini_bar_h), e_color)

	# --- 分隔线 (层级组和资源区之间) ---
	var sep_x: float = info_right_x - maxf(layer_w, energy_text_w + mini_bar_w + 3) - 8.0
	draw_line(Vector2(sep_x, sy + SEP_PAD),
		Vector2(sep_x, sy + STRIP_H - SEP_PAD),
		Color(0.545, 0.361, 0.965, 0.2), 0.8)


# ---------------------------------------------------------------------------
# 飘字
# ---------------------------------------------------------------------------
func _draw_delta_texts(scy: float, font: Font) -> void:
	for dt in _delta_texts:
		var progress: float = dt["timer"] / DELTA_DURATION
		var alpha: float = 1.0 - progress
		var offset_y: float = -20.0 * progress
		var color: Color = dt["color"]
		color.a = alpha

		var dx: float = 60.0
		match dt["key"]:
			"order": dx = 130.0
			"money": dx = 200.0

		draw_string(font, Vector2(dx, scy - 8 + offset_y), dt["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


# ---------------------------------------------------------------------------
# 辅助: 撕裂边缘 (现实模式底部)
# ---------------------------------------------------------------------------
func _draw_torn_edge(x: float, y: float, w: float, base_color: Color) -> void:
	var tear_color: Color = Color(base_color, 0.6)
	var step: float = 5.0
	var cx: float = x
	var i: int = 0
	while cx < x + w:
		var next_x: float = minf(cx + step, x + w)
		var dy: float = 1.5 if (i % 2 == 0) else -0.5
		var jitter: float = sin(cx * 1.7) * 0.8
		var rect_h: float = 2.0 + absf(dy + jitter)
		draw_rect(Rect2(cx, y, step * 0.7, rect_h), tear_color)
		cx = next_x
		i += 1


# ---------------------------------------------------------------------------
# 辅助: 腐蚀边缘 (暗面模式底部)
# ---------------------------------------------------------------------------
func _draw_dark_edge(x: float, y: float, w: float) -> void:
	var edge_color: Color = Color(0.071, 0.055, 0.137, 0.94)
	var step: float = 4.0
	var cx: float = x
	var i: int = 0
	while cx < x + w:
		var _next_x: float = minf(cx + step, x + w)
		var dy: float = 2.0 if (i % 2 == 0) else -0.3
		var jitter: float = sin(cx * 2.1 + 0.7) * 1.2
		var rect_h: float = 2.0 + absf(dy + jitter)
		draw_rect(Rect2(cx, y, step * 0.7, rect_h), edge_color)
		cx = _next_x
		i += 1


# ---------------------------------------------------------------------------
# 辅助: 胶带装饰 (现实模式)
# ---------------------------------------------------------------------------
func _draw_tape(center: Vector2, tw: float, th: float, angle: float) -> void:
	# 半透明胶带主体
	var tape_color: Color = Color(0.961, 0.922, 0.784, 0.24)
	var tape_border: Color = Color(0.863, 0.824, 0.706, 0.16)

	# 用 draw_set_transform 旋转
	var xf: Transform2D = Transform2D()
	xf = xf.translated(-center)
	xf = xf.rotated(angle)
	xf = xf.translated(center)
	draw_set_transform_matrix(xf)

	draw_rect(Rect2(center.x - tw / 2, center.y - th / 2, tw, th), tape_color)
	draw_rect(Rect2(center.x - tw / 2, center.y - th / 2, tw, th), tape_border, false, 0.5)

	# 恢复变换
	draw_set_transform_matrix(Transform2D.IDENTITY)


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
	draw_set_transform_matrix(xf)

	# 封印主体
	draw_rect(Rect2(center.x - tw / 2, center.y - th / 2, tw, th), seal_body)

	# 中线灵纹
	draw_line(Vector2(center.x - tw / 2 + 4, center.y),
		Vector2(center.x + tw / 2 - 4, center.y), seal_line, 0.4)

	# 两端节点
	draw_circle(Vector2(center.x - tw / 2 + 5, center.y), 1.0,
		Color(0.133, 0.827, 0.933, 0.18))
	draw_circle(Vector2(center.x + tw / 2 - 5, center.y), 1.0,
		Color(0.133, 0.827, 0.933, 0.18))

	# 边框轮廓
	draw_rect(Rect2(center.x - tw / 2, center.y - th / 2, tw, th),
		seal_border, false, 0.5)

	draw_set_transform_matrix(Transform2D.IDENTITY)


# ---------------------------------------------------------------------------
# 辅助: 画圆形轮廓 (用线段近似)
# ---------------------------------------------------------------------------
func _draw_circle_outline(center: Vector2, radius: float,
		color: Color, width: float = 1.0) -> void:
	var segments: int = 24
	var prev: float = center + Vector2(radius, 0)
	for i in range(1, segments + 1):
		var angle: float = TAU * float(i) / float(segments)
		var next: float = center + Vector2(cos(angle) * radius, sin(angle) * radius)
		draw_line(prev, next, color, width)
		prev = next
