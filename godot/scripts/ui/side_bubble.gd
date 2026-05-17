## SideBubble - 屏幕侧边气泡消息流
## 用途：教程提示、非主线旁白、环境对话等非剧情信息
## 每条消息是独立小卡片，右侧滑入，向下堆叠，按时间自动消失
## 支持白夜 / 苏柚两种说话人，各自头像和颜色
class_name SideBubble
extends Control

# ---------------------------------------------------------------------------
# 常量 — 单条消息尺寸
# ---------------------------------------------------------------------------
const ITEM_W: float        = 600.0   # 每条消息宽度
const ITEM_AVATAR_R: float = 36.0    # 头像半径
const ITEM_SPINE_W: float  = 28.0    # 左侧色条宽度（说话人颜色）
const ITEM_PAD_X: float    = 18.0    # 水平内边距
const ITEM_PAD_Y: float    = 16.0    # 垂直内边距
const ITEM_MAX_H: float    = 260.0   # 最大单条高度
const ITEM_MIN_H: float    = 104.0   # 最小单条高度

# ---------------------------------------------------------------------------
# 常量 — 布局
# ---------------------------------------------------------------------------
const MARGIN_X: float  = 24.0   # 距屏幕右边缘
const MARGIN_Y: float  = 24.0   # 距屏幕顶部
const ITEM_GAP: float  = 10.0   # 消息之间间距
const MAX_ITEMS: int   = 6      # 最多同时显示条数

# ---------------------------------------------------------------------------
# 常量 — 动画
# ---------------------------------------------------------------------------
const ENTER_DUR: float  = 0.32   # 入场时长
const EXIT_DUR: float   = 0.28   # 出场时长
const SLIDE_X: float    = 55.0   # 从右侧滑入距离
const STAGGER: float    = 0.65   # 序列中每条延迟间隔（秒）

# ---------------------------------------------------------------------------
# 常量 — 时长
# ---------------------------------------------------------------------------
const IDLE_TIME: float      = 8.0    # 对话型停留时长
const IDLE_TIME_LONG: float = 14.0   # 操作指引型停留时长

# ---------------------------------------------------------------------------
# 说话人配置
# ---------------------------------------------------------------------------
const SPEAKER_BAIYE: String = "白夜"
const SPEAKER_SUYOU: String = "苏柚"
const AVATAR_PATH: Dictionary = {
	SPEAKER_BAIYE: "res://assets/image/白夜_chibi_20260506003802.png",
	SPEAKER_SUYOU: "res://assets/image/zhujiao_avater.png",
}
const SPEAKER_COLOR: Dictionary = {
	SPEAKER_BAIYE: Color(0.38, 0.28, 0.62),
	SPEAKER_SUYOU: Color(0.22, 0.45, 0.68),
}

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _active_items: Array = []   # Array of item Dictionary

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

## 显示单条气泡消息
func show_tutorial(text: String, speaker: String = SPEAKER_BAIYE,
		duration: float = IDLE_TIME) -> void:
	_create_item(text, speaker, duration)

## 显示序列对话（每条自动延迟出现，各自计时消失）
## lines: [{speaker, text}, ...]
func show_sequence(lines: Array, duration_per_line: float = IDLE_TIME) -> void:
	for i in lines.size():
		var line: Dictionary = lines[i]
		get_tree().create_timer(i * STAGGER).timeout.connect(func() -> void:
			_create_item(
				line.get("text", ""),
				line.get("speaker", SPEAKER_BAIYE),
				duration_per_line
			)
		)

## 立即清除所有消息
func dismiss() -> void:
	for item in _active_items.duplicate():
		_start_item_exit(item)

# ---------------------------------------------------------------------------
# 每帧：打字机 + 自动消失
# ---------------------------------------------------------------------------
func _process(dt: float) -> void:
	for item in _active_items.duplicate():
		_update_item(item, dt)

func _update_item(item: Dictionary, dt: float) -> void:
	if item["phase"] == "exiting" or item["phase"] == "done":
		return

	# 自动消失计时
	if item["phase"] == "visible":
		item["idle_timer"] += dt
		if item["idle_timer"] >= item["duration"]:
			_start_item_exit(item)

# ---------------------------------------------------------------------------
# 创建一条消息
# ---------------------------------------------------------------------------
func _create_item(text: String, speaker: String, duration: float) -> void:
	if _active_items.size() >= MAX_ITEMS:
		return

	var sw: float = get_viewport_rect().size.x
	var item_h: float = _estimate_height(text)
	var base_x: float = sw - ITEM_W - MARGIN_X
	var base_y: float = _get_next_y()

	var panel: Control = Control.new()
	panel.size = Vector2(ITEM_W, item_h)
	panel.position = Vector2(base_x + SLIDE_X, base_y)
	panel.modulate.a = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var av_diam: float = ITEM_AVATAR_R * 2.0

	# 头像（右侧，垂直居中）
	var avatar_rect: TextureRect = TextureRect.new()
	avatar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var avatar_path: String = AVATAR_PATH.get(speaker, "")
	if avatar_path != "" and ResourceLoader.exists(avatar_path):
		avatar_rect.texture = load(avatar_path) as Texture2D
	avatar_rect.size = Vector2(av_diam, av_diam)
	avatar_rect.position = Vector2(
		ITEM_W - av_diam - ITEM_PAD_X,
		(item_h - av_diam) * 0.5
	)
	panel.add_child(avatar_rect)

	# 说话人名字
	var name_label: Label = Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = speaker
	name_label.add_theme_font_size_override("font_size", 20)
	var sp_color: Color = SPEAKER_COLOR.get(speaker, Color(0.3, 0.3, 0.3))
	name_label.add_theme_color_override("font_color", sp_color)
	name_label.position = Vector2(ITEM_SPINE_W + ITEM_PAD_X, ITEM_PAD_Y)
	name_label.size = Vector2(ITEM_W - ITEM_SPINE_W - ITEM_PAD_X * 2 - av_diam - 8.0, 28.0)
	panel.add_child(name_label)

	# 正文
	var text_label: RichTextLabel = RichTextLabel.new()
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.bbcode_enabled = false
	text_label.scroll_active = false
	text_label.fit_content = true
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("normal_font_size", 23)
	text_label.add_theme_color_override("default_color",
		Color(GameTheme.text_primary.r, GameTheme.text_primary.g,
			GameTheme.text_primary.b, 0.90))
	text_label.text = text
	var text_x: float = ITEM_SPINE_W + ITEM_PAD_X
	var text_y: float = ITEM_PAD_Y + 32.0
	var text_w: float = ITEM_W - ITEM_SPINE_W - ITEM_PAD_X * 2 - av_diam - 8.0
	var text_h: float = item_h - text_y - ITEM_PAD_Y
	text_label.position = Vector2(text_x, text_y)
	text_label.size = Vector2(text_w, maxf(text_h, 32.0))
	panel.add_child(text_label)

	var item: Dictionary = {
		"panel":      panel,
		"text_label": text_label,
		"speaker":    speaker,
		"duration":   duration,
		"idle_timer": 0.0,
		"phase":      "entering",
		"tween":      null,
		"base_x":     base_x,
		"base_y":     base_y,
		"height":     item_h,
	}

	panel.draw.connect(_draw_item.bind(item))

	add_child(panel)
	_active_items.append(item)

	_start_item_enter(item)

# ---------------------------------------------------------------------------
# 高度估算（字号 23）
# ---------------------------------------------------------------------------
func _estimate_height(text: String) -> float:
	var line_count: int = maxi(1, text.count("\n") + 1)
	# 可用文字宽度约 600 - 28 - 36 - 72 - 8 = 456px，字号23 每字约23px
	var chars_per_line: float = 20.0
	var est_lines: int = maxi(line_count, ceili(float(text.length()) / chars_per_line))
	var text_h: float = est_lines * (23.0 * 1.65)
	return clampf(ITEM_PAD_Y * 2 + 32.0 + text_h, ITEM_MIN_H, ITEM_MAX_H)

# ---------------------------------------------------------------------------
# 计算下一条消息的 Y 位置
# ---------------------------------------------------------------------------
func _get_next_y() -> float:
	var y: float = MARGIN_Y
	for item in _active_items:
		if not is_instance_valid(item["panel"]):
			continue
		if item["phase"] == "done":
			continue
		y = maxf(y, item["base_y"] + item["height"] + ITEM_GAP)
	return y

# ---------------------------------------------------------------------------
# 绘制：便签条风格
# ---------------------------------------------------------------------------
func _draw_item(item: Dictionary) -> void:
	var panel: Control = item["panel"]
	if not is_instance_valid(panel):
		return
	var t = GameTheme
	var w: float = panel.size.x
	var h: float = panel.size.y
	var sp_color: Color = SPEAKER_COLOR.get(item["speaker"], Color(0.5, 0.5, 0.5))

	# 阴影（直角偏移块）
	panel.draw_rect(Rect2(3, 5, w, h), Color(0.08, 0.06, 0.12, 0.20))

	# 主背景（稿纸色）
	panel.draw_rect(Rect2(0, 0, w, h),
		Color(t.notebook_paper.r, t.notebook_paper.g, t.notebook_paper.b, 0.97))

	# 横线（文字区）
	var line_color: Color = Color(t.notebook_line.r, t.notebook_line.g, t.notebook_line.b, 0.40)
	var lx0: float = ITEM_SPINE_W + ITEM_PAD_X
	var lx1: float = w - ITEM_PAD_X - ITEM_AVATAR_R * 2.0 - 6.0
	var ly: float = ITEM_PAD_Y + 32.0 + 32.0
	var step: float = 34.0
	while ly < h - ITEM_PAD_Y - 4.0:
		panel.draw_line(Vector2(lx0, ly), Vector2(lx1, ly), line_color, 0.8)
		ly += step

	# 左侧说话人色条
	panel.draw_rect(Rect2(0, 0, ITEM_SPINE_W, h),
		Color(sp_color.r, sp_color.g, sp_color.b, 0.75))

	# 外框
	panel.draw_rect(Rect2(0, 0, w, h),
		Color(t.notebook_border.r, t.notebook_border.g, t.notebook_border.b, 0.40), false, 1.0)

	# 头像圆底
	var av_cx: float = w - ITEM_AVATAR_R - ITEM_PAD_X
	var av_cy: float = h * 0.5
	panel.draw_circle(Vector2(av_cx, av_cy), ITEM_AVATAR_R + 2.0,
		Color(sp_color.r, sp_color.g, sp_color.b, 0.25))
	panel.draw_circle(Vector2(av_cx, av_cy), ITEM_AVATAR_R,
		Color(1.0, 1.0, 1.0, 0.92))

# ---------------------------------------------------------------------------
# 动画
# ---------------------------------------------------------------------------
func _start_item_enter(item: Dictionary) -> void:
	var panel: Control = item["panel"]
	var base_x: float = item["base_x"]
	var base_y: float = item["base_y"]

	var tw: Tween = create_tween()
	item["tween"] = tw
	tw.set_parallel(true)
	tw.tween_property(panel, "position", Vector2(base_x, base_y), ENTER_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(panel, "modulate:a", 1.0, ENTER_DUR * 0.8) \
		.set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func() -> void:
		item["phase"] = "visible"
	)

func _start_item_exit(item: Dictionary) -> void:
	if item["phase"] == "exiting" or item["phase"] == "done":
		return
	item["phase"] = "exiting"

	var panel: Control = item["panel"]
	if item["tween"]:
		item["tween"].kill()

	var tw: Tween = create_tween()
	item["tween"] = tw
	tw.set_parallel(true)
	tw.tween_property(panel, "position",
		panel.position + Vector2(20.0, 0.0), EXIT_DUR) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(panel, "modulate:a", 0.0, EXIT_DUR) \
		.set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void:
		item["phase"] = "done"
		_active_items.erase(item)
		if is_instance_valid(panel):
			panel.queue_free()
		_shift_items_up(item)
	)

## 某条气泡消失后，将其下方的气泡缓速上移
func _shift_items_up(removed_item: Dictionary) -> void:
	var freed_h: float = removed_item["height"] + ITEM_GAP
	var removed_y: float = removed_item["base_y"]
	const SHIFT_DUR: float = 0.30

	for other in _active_items:
		if other["base_y"] <= removed_y:
			continue
		if other["phase"] == "done":
			continue
		other["base_y"] -= freed_h
		var panel: Control = other["panel"]
		if not is_instance_valid(panel):
			continue
		var target_pos: Vector2 = Vector2(panel.position.x, other["base_y"])
		var shift_tw: Tween = create_tween()
		shift_tw.tween_property(panel, "position", target_pos, SHIFT_DUR) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
