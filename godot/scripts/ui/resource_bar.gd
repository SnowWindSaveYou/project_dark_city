## ResourceBar - 顶部资源栏 HUD
## 对应原版 ResourceBar.lua
## 显示 san, order, money + 天数/天气
extends Control

# ---------------------------------------------------------------------------
# 节点引用 (在场景中配置或代码创建)
# ---------------------------------------------------------------------------
var _display_values := { "san": 10.0, "order": 10.0, "money": 50.0 }
var _flash_timers := { "san": 0.0, "order": 0.0, "money": 0.0 }
var _delta_texts: Array = []  # { "key", "delta", "timer", "pos" }

const FLASH_DURATION := 0.5
const DELTA_DURATION := 1.2

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	GameData.resource_changed.connect(_on_resource_changed)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 设置锚点为顶部全宽
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size.y = 48

func _on_resource_changed(key: String, old_value: int, new_value: int) -> void:
	if key in _flash_timers:
		_flash_timers[key] = FLASH_DURATION
		# 飘字
		var delta_val := new_value - old_value
		if delta_val != 0:
			var prefix := "+" if delta_val > 0 else ""
			_delta_texts.append({
				"key": key,
				"text": prefix + str(delta_val),
				"timer": 0.0,
				"color": Theme.safe if delta_val > 0 else Theme.danger,
			})

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	# 平滑数值过渡
	for key in _display_values:
		var target: float = float(GameData.get_resource(key))
		_display_values[key] = lerpf(_display_values[key], target, minf(1.0, delta * 8.0))

	# 闪光衰减
	for key in _flash_timers:
		if _flash_timers[key] > 0:
			_flash_timers[key] -= delta

	# 飘字衰减
	var i := _delta_texts.size() - 1
	while i >= 0:
		_delta_texts[i]["timer"] += delta
		if _delta_texts[i]["timer"] > DELTA_DURATION:
			_delta_texts.remove_at(i)
		i -= 1

	queue_redraw()

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _draw() -> void:
	var w := size.x
	var h := size.y
	var t = Theme  # Autoload

	# 撕纸条背景
	var bg_color := Color(t.notebook_paper.r, t.notebook_paper.g, t.notebook_paper.b, 0.92)
	draw_rect(Rect2(0, 0, w, h), bg_color)

	# 蓝色横线装饰
	var line_y := h - 6.0
	draw_line(Vector2(10, line_y), Vector2(w - 10, line_y),
		Color(t.notebook_line.r, t.notebook_line.g, t.notebook_line.b, 0.4), 1.0)

	# 底部撕纸边缘 (简化为锯齿)
	var tear_color := Color(t.notebook_paper.r, t.notebook_paper.g, t.notebook_paper.b, 0.6)
	var step := 8.0
	var x := 0.0
	while x < w:
		var th := 2.0 + randf() * 3.0
		draw_rect(Rect2(x, h, step * 0.7, th), tear_color)
		x += step

	# 资源显示
	var font := ThemeDB.fallback_font
	var font_size := 15
	var resources_display := [
		{ "key": "san",   "icon": "🧠" },
		{ "key": "order", "icon": "⚖️" },
		{ "key": "money", "icon": "💰" },
	]

	var rx := 20.0
	for res in resources_display:
		var key: String = res["key"]
		var icon: String = res["icon"]
		var val := int(round(_display_values[key]))

		# 闪光效果
		var flash_t: float = _flash_timers.get(key, 0.0)
		var text_color := t.text_primary
		if flash_t > 0:
			var flash_ratio := flash_t / FLASH_DURATION
			text_color = text_color.lerp(Color.WHITE, flash_ratio * 0.5)

		# 图标
		draw_string(font, Vector2(rx, h / 2 + 6), icon,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
		rx += 28.0

		# 数值
		var val_str := str(val)
		draw_string(font, Vector2(rx, h / 2 + 6), val_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
		rx += font.get_string_size(val_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 24.0

	# 天数和天气 (右侧)
	var day := GameData.current_day
	if day > 0:
		var weather := Weather.get_weather(day)
		var weather_icon := Weather.get_icon(weather)
		var day_text := weather_icon + " 第 " + str(day) + " 天"
		var day_w := font.get_string_size(day_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(w - day_w - 20, h / 2 + 6), day_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, t.text_secondary)

	# 飘字
	for dt in _delta_texts:
		var progress: float = dt["timer"] / DELTA_DURATION
		var alpha := 1.0 - progress
		var offset_y := -20.0 * progress
		var color: Color = dt["color"]
		color.a = alpha

		# 简单地根据 key 确定 x 位置
		var dx := 60.0
		match dt["key"]:
			"order": dx = 130.0
			"money": dx = 200.0

		draw_string(font, Vector2(dx, h / 2 - 8 + offset_y), dt["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
