## TutorialBubble - 屏幕教程气泡
## 便签条风格，固定显示在屏幕右上角，完全独立于对话系统和角色气泡
## 支持白夜 / 主角两种说话人，各自配头像
## 动效：从右上角滑下 + 轻微弹簧回弹，打字机效果，手指轻点消除
class_name TutorialBubble
extends Control

# ---------------------------------------------------------------------------
# 常量 — 布局
# ---------------------------------------------------------------------------
const BUBBLE_W: float      = 520.0   # 气泡宽度
const BUBBLE_MAX_H: float  = 320.0   # 最大高度（文字过多时不超出）
const AVATAR_SIZE: float   = 84.0    # 头像尺寸
const PAD_X: float         = 22.0    # 水平内边距
const PAD_Y: float         = 18.0    # 垂直内边距
const LINE_GAP: float      = 6.0     # 笔记本横线间距（额外）
const CORNER_R: float      = 12.0    # 圆角半径
const MARGIN_SCREEN: float = 24.0    # 距屏幕边缘
const NOTCH_W: float       = 14.0    # 左侧红色竖线（稿纸装饰）宽度
const SPINE_W: float       = 32.0    # 左侧装订线宽度（含 NOTCH）
const PIN_R: float         = 7.0     # 订书针/图钉半径

# ---------------------------------------------------------------------------
# 常量 — 动画
# ---------------------------------------------------------------------------
const ENTER_DUR: float      = 0.45   # 入场时长
const EXIT_DUR: float       = 0.30   # 出场时长
const IDLE_TIME: float      = 9.0    # 对话型教程停留时长（秒）
const IDLE_TIME_LONG: float = 15.0   # 操作指引型教程停留时长（秒）
const TYPE_SPEED: int       = 22     # 打字机：每秒字符数
const SLIDE_DIST: float     = 60.0   # 入场从上滑下的距离

# ---------------------------------------------------------------------------
# 说话人配置
# ---------------------------------------------------------------------------
const SPEAKER_BAIYE: String  = "白夜"
const SPEAKER_SUYOU: String  = "苏柚"
const AVATAR_PATH: Dictionary = {
	SPEAKER_BAIYE: "res://assets/image/白夜_chibi_20260506003802.png",
	SPEAKER_SUYOU: "res://assets/image/zhujiao_avater.png",
}
const SPEAKER_COLOR: Dictionary = {
	SPEAKER_BAIYE: Color(0.38, 0.28, 0.62),   # 紫灰，白夜冷调
	SPEAKER_SUYOU: Color(0.22, 0.45, 0.68),   # 蓝调，主角
}

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _phase: String  = "hidden"   # hidden | entering | visible | exiting
var _text_full: String  = ""     # 完整文字
var _speaker: String    = ""     # 说话人名字
var _timer: float       = 0.0
var _idle_duration: float = IDLE_TIME
var _typewriter_pos: int  = 0
var _typewriter_accum: float = 0.0
var _avatar_tex: Texture2D = null

# 序列对话
var _sequence: Array = []        # [{speaker, text}, ...]
var _seq_index: int  = 0

# ---------------------------------------------------------------------------
# 内部节点 (程序化构建)
# ---------------------------------------------------------------------------
var _panel: Control       = null   # 主体容器（_draw 在此绘制）
var _avatar_rect: TextureRect = null
var _name_label: Label    = null
var _text_label: RichTextLabel = null
var _close_hint: Label    = null   # "轻触关闭"小字
var _tween: Tween         = null

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	# 全屏覆盖，不影响下层输入（点击由 _panel.gui_input 处理）
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_ui()

func _build_ui() -> void:
	# ── 主面板容器（用于 _draw 绘制笔记本背景）──
	_panel = Control.new()
	_panel.name = "BubblePanel"
	_panel.custom_minimum_size = Vector2(BUBBLE_W, 80.0)
	_panel.size = Vector2(BUBBLE_W, 80.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.draw.connect(_draw_panel)
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)

	# ── 头像 ──
	_avatar_rect = TextureRect.new()
	_avatar_rect.name = "Avatar"
	_avatar_rect.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	_avatar_rect.size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_avatar_rect)

	# ── 说话人名字 ──
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override("font_size", 17)
	_panel.add_child(_name_label)

	# ── 正文（打字机用 RichTextLabel）──
	_text_label = RichTextLabel.new()
	_text_label.name = "TextLabel"
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_label.bbcode_enabled = false
	_text_label.scroll_active = false
	_text_label.fit_content = true
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("normal_font_size", 18)
	_panel.add_child(_text_label)

	# ── "轻触关闭" 提示 ──
	_close_hint = Label.new()
	_close_hint.name = "CloseHint"
	_close_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_hint.text = "轻触关闭"
	_close_hint.add_theme_font_size_override("font_size", 13)
	_close_hint.modulate = Color(0.6, 0.6, 0.6, 0.65)
	_panel.add_child(_close_hint)

# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

## 显示单条教程气泡
func show_tutorial(text: String, speaker: String = SPEAKER_BAIYE,
		duration: float = IDLE_TIME) -> void:
	_sequence = []
	_seq_index = 0
	_idle_duration = duration
	_start_bubble(text, speaker)

## 显示多人序列对话
## lines: [{speaker: "白夜", text: "..."}, ...]
## duration_last: 最后一条停留时长
func show_sequence(lines: Array, duration_last: float = IDLE_TIME) -> void:
	if lines.is_empty():
		return
	_sequence = lines
	_seq_index = 0
	_idle_duration = duration_last
	var first: Dictionary = lines[0]
	_start_bubble(first.get("text", ""), first.get("speaker", SPEAKER_BAIYE))

## 立即隐藏（外部强制）
func dismiss() -> void:
	if _phase == "hidden" or _phase == "exiting":
		return
	_start_exit_anim()

# ---------------------------------------------------------------------------
# 内部：启动气泡（单条 or 序列共用）
# ---------------------------------------------------------------------------
func _start_bubble(text: String, speaker: String) -> void:
	if _phase == "entering" or _phase == "visible":
		_force_hide_immediate()

	_text_full = text
	_speaker = speaker
	_typewriter_pos = 0
	_typewriter_accum = 0.0
	_timer = 0.0

	_apply_speaker(speaker)
	_text_label.text = ""

	visible = true
	_phase = "entering"
	_layout_panel()
	_update_seq_hint()
	_start_enter_anim()

## 切换当前说话人（头像 / 名字 / 颜色）
func _apply_speaker(speaker: String) -> void:
	var avatar_path: String = AVATAR_PATH.get(speaker, "")
	if avatar_path != "" and ResourceLoader.exists(avatar_path):
		_avatar_tex = load(avatar_path) as Texture2D
	else:
		_avatar_tex = null
	_avatar_rect.texture = _avatar_tex

	var name_color: Color = SPEAKER_COLOR.get(speaker, Color(0.25, 0.25, 0.25))
	_name_label.text = speaker
	_name_label.add_theme_color_override("font_color", name_color)
	_text_label.add_theme_color_override("default_color",
		Color(GameTheme.text_primary.r, GameTheme.text_primary.g, GameTheme.text_primary.b, 0.92))

## 更新底部提示文字："轻触继续 ▶" 或 "轻触关闭"
func _update_seq_hint() -> void:
	var has_more: bool = _sequence.size() > 0 and _seq_index < _sequence.size() - 1
	_close_hint.text = "轻触继续 ▶" if has_more else "轻触关闭"

## 推进到序列下一条
func _advance_sequence() -> void:
	_seq_index += 1
	var line: Dictionary = _sequence[_seq_index]
	_speaker = line.get("speaker", SPEAKER_BAIYE)
	_text_full = line.get("text", "")
	_typewriter_pos = 0
	_typewriter_accum = 0.0
	_timer = 0.0
	_text_label.text = ""
	_apply_speaker(_speaker)
	_update_seq_hint()
	_panel.queue_redraw()  # 刷新说话人颜色装饰

# ---------------------------------------------------------------------------
# 布局计算（每次显示前调用）
# ---------------------------------------------------------------------------
func _layout_panel() -> void:
	var sw: float = get_viewport_rect().size.x
	var sh: float = get_viewport_rect().size.y

	# 估算面板高度（粗略：按换行和字数估）
	var line_count: int = maxi(1, _text_full.count("\n") + 1)
	var avg_chars_per_line: float = 18.0
	var estimated_lines: int = maxi(line_count,
		ceili(float(_text_full.length()) / avg_chars_per_line))
	var text_h: float = estimated_lines * (16.0 * 1.55)
	var panel_h: float = clampf(
		PAD_Y * 2 + 28.0 + text_h + 20.0,   # pad + name + text + close_hint
		100.0, BUBBLE_MAX_H
	)

	_panel.custom_minimum_size = Vector2(BUBBLE_W, panel_h)
	_panel.size = Vector2(BUBBLE_W, panel_h)

	# 定位：屏幕右上角
	var px: float = sw - BUBBLE_W - MARGIN_SCREEN
	var py: float = MARGIN_SCREEN
	_panel.position = Vector2(px, py)

	# 子节点布局
	var inner_x: float = SPINE_W + PAD_X
	var inner_w: float = BUBBLE_W - SPINE_W - PAD_X * 2 - AVATAR_SIZE - 10.0

	# 头像：右侧居中
	_avatar_rect.position = Vector2(
		BUBBLE_W - AVATAR_SIZE - PAD_X,
		(panel_h - AVATAR_SIZE) * 0.5
	)

	# 名字标签
	_name_label.position = Vector2(inner_x, PAD_Y + 2.0)
	_name_label.size = Vector2(inner_w, 22.0)

	# 正文区域
	var text_y: float = PAD_Y + 26.0
	var text_area_h: float = panel_h - text_y - PAD_Y - 18.0
	_text_label.position = Vector2(inner_x, text_y)
	_text_label.size = Vector2(inner_w, maxf(text_area_h, 20.0))

	# "轻触关闭"
	_close_hint.position = Vector2(inner_x, panel_h - 17.0)

	_panel.queue_redraw()

# ---------------------------------------------------------------------------
# 绘制笔记本风格背景
# ---------------------------------------------------------------------------
func _draw_panel() -> void:
	if _panel == null:
		return
	var t = GameTheme
	var w: float = _panel.size.x
	var h: float = _panel.size.y

	# ── 1. 底层阴影 ──
	var shadow_rect: Rect2 = Rect2(3, 4, w, h)
	draw_rect_on(_panel, shadow_rect,
		Color(0.1, 0.08, 0.15, 0.28), CORNER_R + 2.0)

	# ── 2. 主背景（稿纸米白）──
	draw_rect_on(_panel, Rect2(0, 0, w, h),
		Color(t.notebook_paper.r, t.notebook_paper.g, t.notebook_paper.b, 0.97),
		CORNER_R)

	# ── 3. 稿纸横线（蓝色淡线）──
	var line_color: Color = Color(t.notebook_line.r, t.notebook_line.g, t.notebook_line.b, 0.55)
	var line_x0: float = SPINE_W + PAD_X
	var line_x1: float = w - PAD_X - AVATAR_SIZE - 8.0
	var first_line_y: float = PAD_Y + 26.0 + 4.0  # 名字行下方开始
	var line_step: float = 22.0
	var line_y: float = first_line_y
	while line_y < h - PAD_Y - 10.0:
		_panel.draw_line(Vector2(line_x0, line_y), Vector2(line_x1, line_y),
			line_color, 0.8)
		line_y += line_step

	# ── 4. 装订线区域（暖棕色竖条）──
	var spine_color: Color = Color(t.notebook_spine.r, t.notebook_spine.g, t.notebook_spine.b, 0.82)
	_panel.draw_rect(Rect2(0, 0, SPINE_W, h), spine_color)
	# 装订线右侧深竖线
	_panel.draw_line(Vector2(SPINE_W, 0), Vector2(SPINE_W, h),
		Color(t.notebook_spine.r * 0.7, t.notebook_spine.g * 0.7, t.notebook_spine.b * 0.7, 0.7), 1.5)

	# ── 5. 红色边距竖线（稿纸左侧红线）──
	var red_line_x: float = SPINE_W + 10.0
	_panel.draw_line(Vector2(red_line_x, PAD_Y), Vector2(red_line_x, h - PAD_Y),
		Color(0.82, 0.22, 0.22, 0.50), 1.2)

	# ── 6. 装订孔（3 个圆圈）──
	var hole_color: Color = Color(t.notebook_paper.r * 0.85, t.notebook_paper.g * 0.85, t.notebook_paper.b * 0.85, 1.0)
	var hole_shadow: Color = Color(0.1, 0.08, 0.15, 0.25)
	var hole_ys: Array[float] = [h * 0.2, h * 0.5, h * 0.8]
	for hy in hole_ys:
		_panel.draw_circle(Vector2(SPINE_W * 0.5, hy), 5.0, hole_shadow)
		_panel.draw_circle(Vector2(SPINE_W * 0.5, hy), 4.0, hole_color)

	# ── 7. 外框线（细笔迹感）──
	draw_rect_border_on(_panel, Rect2(0, 0, w, h),
		Color(t.notebook_border.r, t.notebook_border.g, t.notebook_border.b, 0.55),
		CORNER_R, 1.2)

	# ── 8. 左下角折角（撕纸效果）──
	var fold_size: float = 14.0
	var fold_pts: PackedVector2Array = [
		Vector2(0, h - fold_size),
		Vector2(fold_size, h),
		Vector2(0, h),
	]
	_panel.draw_colored_polygon(fold_pts, Color(t.notebook_spine.r, t.notebook_spine.g, t.notebook_spine.b, 0.55))

	# ── 9. 说话人色条（右上角小角标）──
	var speaker_c: Color = SPEAKER_COLOR.get(_speaker, Color(0.5, 0.5, 0.5))
	var badge_w: float = 52.0
	var badge_h: float = 20.0
	var badge_x: float = w - badge_w - PAD_X - AVATAR_SIZE - 4.0
	_panel.draw_rect(Rect2(badge_x, 0, badge_w, badge_h),
		Color(speaker_c.r, speaker_c.g, speaker_c.b, 0.18))
	_panel.draw_line(Vector2(badge_x, badge_h), Vector2(badge_x + badge_w, badge_h),
		Color(speaker_c.r, speaker_c.g, speaker_c.b, 0.40), 1.0)

	# ── 10. 头像圆形底图（圆形裁切感）──
	var av_cx: float = _avatar_rect.position.x + AVATAR_SIZE * 0.5
	var av_cy: float = _avatar_rect.position.y + AVATAR_SIZE * 0.5
	# 圆形边框
	_panel.draw_circle(Vector2(av_cx, av_cy), AVATAR_SIZE * 0.5 + 2.0,
		Color(speaker_c.r, speaker_c.g, speaker_c.b, 0.30))
	# 白色圆底
	_panel.draw_circle(Vector2(av_cx, av_cy), AVATAR_SIZE * 0.5,
		Color(1.0, 1.0, 1.0, 0.95))


# 辅助：在 Control 上绘制圆角填充矩形
func draw_rect_on(ctrl: Control, rect: Rect2, color: Color, radius: float) -> void:
	var pts: PackedVector2Array = _rounded_rect_pts(rect, radius)
	ctrl.draw_colored_polygon(pts, color)

# 辅助：在 Control 上绘制圆角边框
func draw_rect_border_on(ctrl: Control, rect: Rect2, color: Color,
		radius: float, width: float) -> void:
	var pts: PackedVector2Array = _rounded_rect_pts(rect, radius)
	# draw_polyline 需要闭合
	var closed: PackedVector2Array = pts
	closed.append(pts[0])
	ctrl.draw_polyline(closed, color, width)

# 辅助：生成圆角矩形顶点
func _rounded_rect_pts(rect: Rect2, r: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = 8  # 每角顶点数
	var corners: Array[Vector2] = [
		Vector2(rect.position.x + r,        rect.position.y + r),        # 左上
		Vector2(rect.position.x + rect.size.x - r, rect.position.y + r),  # 右上
		Vector2(rect.position.x + rect.size.x - r, rect.position.y + rect.size.y - r),  # 右下
		Vector2(rect.position.x + r,        rect.position.y + rect.size.y - r),  # 左下
	]
	var start_angles: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
	for i in range(4):
		for s in range(steps + 1):
			var angle: float = start_angles[i] + PI * 0.5 * float(s) / float(steps)
			pts.append(corners[i] + Vector2(cos(angle), sin(angle)) * r)
	return pts

# ---------------------------------------------------------------------------
# 动画
# ---------------------------------------------------------------------------
func _start_enter_anim() -> void:
	if _tween:
		_tween.kill()
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	# 入场起始位置：从上方 SLIDE_DIST 滑下
	var base_pos: Vector2 = _panel.position
	_panel.position = base_pos + Vector2(0, -SLIDE_DIST)

	_tween = create_tween()
	_tween.set_parallel(true)
	# 滑入
	_tween.tween_property(_panel, "position", base_pos, ENTER_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# 淡入
	_tween.tween_property(_panel, "modulate:a", 1.0, ENTER_DUR * 0.8) \
		.set_ease(Tween.EASE_OUT)
	# 弹性缩放
	_tween.tween_property(_panel, "scale", Vector2.ONE, ENTER_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.chain().tween_callback(func() -> void:
		_phase = "visible"
		_timer = 0.0
	)

func _start_exit_anim() -> void:
	if _phase == "exiting":
		return
	_phase = "exiting"
	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_parallel(true)
	# 向右上角收缩
	_tween.tween_property(_panel, "position",
		_panel.position + Vector2(20.0, -30.0), EXIT_DUR) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_panel, "modulate:a", 0.0, EXIT_DUR) \
		.set_ease(Tween.EASE_IN)
	_tween.tween_property(_panel, "scale", Vector2(0.88, 0.88), EXIT_DUR) \
		.set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(func() -> void:
		_phase = "hidden"
		visible = false
	)

func _force_hide_immediate() -> void:
	if _tween:
		_tween.kill()
	_phase = "hidden"
	visible = false
	_panel.modulate.a = 0.0

# ---------------------------------------------------------------------------
# 打字机 & 每帧逻辑
# ---------------------------------------------------------------------------
func _process(dt: float) -> void:
	if _phase == "hidden" or _phase == "exiting":
		return

	# 打字机效果（进入 visible 后才开始）
	if _phase == "visible" or _phase == "entering":
		if _typewriter_pos < _text_full.length():
			_typewriter_accum += dt * TYPE_SPEED
			var new_pos: int = mini(int(_typewriter_accum), _text_full.length())
			if new_pos != _typewriter_pos:
				_typewriter_pos = new_pos
				_text_label.text = _text_full.substr(0, _typewriter_pos)

	# 自动消失计时（文字打完且是最后一条时才开始）
	var is_last_line: bool = _sequence.is_empty() or _seq_index >= _sequence.size() - 1
	if _phase == "visible" and _typewriter_pos >= _text_full.length() and is_last_line:
		if _idle_duration > 0.0:
			_timer += dt
			if _timer >= _idle_duration:
				_start_exit_anim()

# ---------------------------------------------------------------------------
# 输入：点击关闭
# ---------------------------------------------------------------------------
func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _phase == "visible" or _phase == "entering":
				if _typewriter_pos < _text_full.length():
					# 打字机未完：跳到完整文字
					_typewriter_pos = _text_full.length()
					_typewriter_accum = float(_text_full.length())
					_text_label.text = _text_full
				elif not _sequence.is_empty() and _seq_index < _sequence.size() - 1:
					# 序列还有下一条：推进
					_advance_sequence()
				else:
					# 最后一条（或单条）：关闭
					_start_exit_anim()
