## DialogueOverlay - 对话系统渲染层
## 读取 DialogueSystem 的动画属性, 用 _draw() 绘制:
##   - 半透明遮罩
##   - 笔记本风格对话框 (带横线)
##   - 名牌
##   - 打字机文本
##   - 立绘
##   - 闪烁三角 (等待点击)
extends Control

# ---------------------------------------------------------------------------
# 引用
# ---------------------------------------------------------------------------
var m: Node = null  # main.gd 引用 (由 main 注入)

# ---------------------------------------------------------------------------
# 常量 (与 DialogueSystem 保持一致)
# ---------------------------------------------------------------------------
const BOX_H_RATIO: float = 0.28
const BOX_MARGIN_X: float = 60.0
const BOX_MARGIN_BOTTOM: float = 48.0
const BOX_PAD_X: float = 84.0
const BOX_PAD_TOP: float = 108.0
const BOX_PAD_BOTTOM: float = 48.0
const BOX_RADIUS: float = 36.0
const BOX_LINE_SPACING: float = 66.0

const NAME_TAG_H: float = 78.0
const NAME_TAG_PAD_X: float = 42.0
const NAME_TAG_RADIUS: float = 18.0
const NAME_TAG_OFFSET_Y: float = -42.0

const PORTRAIT_H_RATIO: float = 0.75
const PORTRAIT_MARGIN_LEFT: float = 0.05

const FONT_SIZE_TEXT: int = 48
const FONT_SIZE_NAME: int = 42
const LINE_H_MULT: float = 1.5
const ADVANCE_BLINK_SPEED: float = 2.5

# ---------------------------------------------------------------------------
# 跳过按钮常量
# ---------------------------------------------------------------------------
const SKIP_BTN_W: float = 144.0   ## 跳过按钮宽度
const SKIP_BTN_H: float = 54.0    ## 跳过按钮高度
const SKIP_BTN_MARGIN_R: float = 30.0  ## 距对话框右边距
const SKIP_BTN_MARGIN_B: float = 24.0  ## 距对话框底边距

# ---------------------------------------------------------------------------
# 缓存 + 选项交互状态
# ---------------------------------------------------------------------------
var _font: Font = null
var _choice_rects: Array = []   ## 每个选项按钮的 Rect2 (用于命中检测)
var _hovered_choice: int = -1   ## 当前 hover 的选项索引 (-1 = 无)
var _skip_rect: Rect2 = Rect2()    ## 跳过按钮点击区域
var _skip_hovered: bool = false    ## 鼠标是否悬停在跳过按钮上

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_dt: float) -> void:
	if m == null or m._dialogue_system == null:
		return
	var ds: DialogueSystem = m._dialogue_system
	# 有选项 或 跳过按钮可见时，拦截鼠标；否则透传
	var has_choices: bool = ds.state == "waiting" and not ds.get_current_choices().is_empty()
	var skip_visible: bool = _is_skip_visible(ds)
	mouse_filter = Control.MOUSE_FILTER_STOP if (has_choices or skip_visible) else Control.MOUSE_FILTER_IGNORE

	var mp: Vector2 = get_local_mouse_position()

	# 更新选项 hover 状态
	if has_choices:
		var new_hover: int = -1
		for i in range(_choice_rects.size()):
			if _choice_rects[i].has_point(mp):
				new_hover = i
				break
		if new_hover != _hovered_choice:
			_hovered_choice = new_hover
			queue_redraw()

	# 更新跳过按钮 hover 状态
	if skip_visible and not _skip_rect.size.is_zero_approx():
		var new_skip_hover: bool = _skip_rect.has_point(mp)
		if new_skip_hover != _skip_hovered:
			_skip_hovered = new_skip_hover
			queue_redraw()
	elif _skip_hovered:
		_skip_hovered = false
		queue_redraw()

	# 需要渲染时才 queue_redraw
	if ds.is_active() or ds.overlay_alpha > 0.01:
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if m == null or m._dialogue_system == null:
		return
	var ds: DialogueSystem = m._dialogue_system
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var mp: Vector2 = get_local_mouse_position()

	# 优先检测跳过按钮 (非 choosing 状态)
	if _is_skip_visible(ds) and not _skip_rect.size.is_zero_approx():
		if _skip_rect.has_point(mp):
			ds.skip()
			_skip_hovered = false
			get_viewport().set_input_as_handled()
			return
		# 点击在跳过按钮之外 → 当作普通点击推进对话
		# (此时 mouse_filter=STOP 导致 _unhandled_input 收不到，需在此手动转发)
		ds.handle_click()
		get_viewport().set_input_as_handled()
		return

	# 选项按钮 (choosing 状态)
	if ds.state == "waiting" and not ds.get_current_choices().is_empty():
		for i in range(_choice_rects.size()):
			if _choice_rects[i].has_point(mp):
				ds.select_choice(i)
				_hovered_choice = -1
				_choice_rects = []
				get_viewport().set_input_as_handled()
				return

func _draw() -> void:
	if m == null or m._dialogue_system == null:
		return
	var ds: DialogueSystem = m._dialogue_system
	if ds.overlay_alpha < 0.01 and ds.box_alpha < 0.01:
		return

	var vp: Vector2 = get_viewport_rect().size

	# --- 半透明遮罩 ---
	var overlay_color: Color = Color(0, 0, 0, ds.overlay_alpha * DialogueSystem.OVERLAY_ALPHA_MAX)
	draw_rect(Rect2(Vector2.ZERO, vp), overlay_color)

	if ds.box_alpha < 0.01:
		return

	# --- 对话框位置 ---
	var box_h: float = vp.y * BOX_H_RATIO
	var box_x: float = BOX_MARGIN_X
	var box_w: float = vp.x - BOX_MARGIN_X * 2.0
	var box_y: float = vp.y - box_h - BOX_MARGIN_BOTTOM + ds.box_offset_y
	var box_rect: Rect2 = Rect2(box_x, box_y, box_w, box_h)

	var t = GameTheme

	# --- 立绘 (在对话框背景之前绘制, 使对话框覆盖立绘下半部分) ---
	var portrait: Texture2D = ds.get_portrait_texture()
	if portrait and ds.portrait_alpha > 0.01:
		var ph: float = vp.y * PORTRAIT_H_RATIO * ds.portrait_scale
		var pw: float = ph * (portrait.get_width() as float / portrait.get_height() as float)
		var px: float = vp.x * PORTRAIT_MARGIN_LEFT
		var py: float = vp.y - ph + ds.portrait_offset_y
		var p_color: Color = Color(1, 1, 1, ds.portrait_alpha)
		draw_texture_rect(portrait, Rect2(px, py, pw, ph), false, p_color)

	# --- 对话框背景 (笔记本纸) ---
	var paper_color: Color = Color(t.dialogue_paper, ds.box_alpha)
	draw_rect(box_rect, paper_color, true)

	# 笔记本横线
	var line_color: Color = Color(t.dialogue_line, ds.box_alpha * 0.4)
	var line_y: float = box_y + BOX_PAD_TOP
	while line_y < box_y + box_h - BOX_PAD_BOTTOM:
		draw_line(
			Vector2(box_x + 36, line_y),
			Vector2(box_x + box_w - 36, line_y),
			line_color, 3.0)
		line_y += BOX_LINE_SPACING

	# 边框
	var border_color: Color = Color(t.dialogue_border, ds.box_alpha)
	draw_rect(box_rect, border_color, false, 4.5)

	# --- 名牌 ---
	var speaker: String = ds.get_speaker()
	if speaker != "":
		var name_w: float = _font.get_string_size(speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_NAME).x + NAME_TAG_PAD_X * 2
		var tag_rect: Rect2 = Rect2(
			box_x + 60, box_y + NAME_TAG_OFFSET_Y,
			name_w, NAME_TAG_H)
		draw_rect(tag_rect, Color(t.dialogue_nametag, ds.box_alpha), true)
		draw_rect(tag_rect, Color(t.dialogue_nametag_border, ds.box_alpha), false, 3.0)
		draw_string(_font, Vector2(tag_rect.position.x + NAME_TAG_PAD_X,
			tag_rect.position.y + NAME_TAG_H * 0.72),
			speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_NAME,
			Color(1, 1, 1, ds.box_alpha))

	# --- 文本 ---
	var display_text: String = ds.get_display_text()
	if display_text != "":
		var text_x: float = box_x + BOX_PAD_X
		var text_y: float = box_y + BOX_PAD_TOP + FONT_SIZE_TEXT * 0.3
		var max_w: float = box_w - BOX_PAD_X * 2.0
		var text_color: Color = Color(t.dialogue_text, ds.box_alpha)

		# 简易自动换行
		var lines: Array = _wrap_text(display_text, max_w)
		for i in range(lines.size()):
			var ly: float = text_y + i * (FONT_SIZE_TEXT * LINE_H_MULT)
			if ly > box_y + box_h - BOX_PAD_BOTTOM:
				break
			draw_string(_font, Vector2(text_x, ly + FONT_SIZE_TEXT),
				lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_TEXT,
				text_color)

	# --- 跳过按钮 (非 choosing 状态显示，右下角) ---
	if _is_skip_visible(ds):
		var sb_x: float = box_x + box_w - SKIP_BTN_W - SKIP_BTN_MARGIN_R
		var sb_y: float = box_y + box_h - SKIP_BTN_H - SKIP_BTN_MARGIN_B
		_skip_rect = Rect2(sb_x, sb_y, SKIP_BTN_W, SKIP_BTN_H)

		# 投影阴影
		draw_rect(Rect2(sb_x + 3, sb_y + 3, SKIP_BTN_W, SKIP_BTN_H),
			Color(0, 0, 0, ds.box_alpha * 0.22), true)

		# 按钮背景 (笔记本纸色调，hover 时稍亮)
		var bg_alpha: float = 0.82 if _skip_hovered else 0.55
		var bg_col: Color = Color(t.dialogue_paper, ds.box_alpha * bg_alpha)
		# hover 时叠加一层浅色高亮
		if _skip_hovered:
			bg_col = bg_col.lerp(Color(1, 1, 1, ds.box_alpha * 0.9), 0.18)
		draw_rect(Rect2(sb_x, sb_y, SKIP_BTN_W, SKIP_BTN_H), bg_col, true)

		# 按钮边框 (使用对话框边框色)
		var bdr_alpha: float = 0.65 if _skip_hovered else 0.38
		draw_rect(Rect2(sb_x, sb_y, SKIP_BTN_W, SKIP_BTN_H),
			Color(t.dialogue_border, ds.box_alpha * bdr_alpha), false, 3.0)

		# 按钮文字 "跳过 »"
		var skip_label: String = "跳过 »"
		var txt_size: Vector2 = _font.get_string_size(skip_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_NAME - 4)
		var txt_x: float = sb_x + (SKIP_BTN_W - txt_size.x) * 0.5
		var txt_y: float = sb_y + (SKIP_BTN_H + txt_size.y * 0.5) * 0.5
		var txt_alpha: float = 0.92 if _skip_hovered else 0.55
		draw_string(_font, Vector2(txt_x, txt_y), skip_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_NAME - 4,
			Color(t.dialogue_text, ds.box_alpha * txt_alpha))
	else:
		_skip_rect = Rect2()

	# --- 选项按钮 / 闪烁三角 ---
	if ds.state == "waiting":
		var choices: Array = ds.get_current_choices()
		if not choices.is_empty():
			# 渲染选项按钮 (堆叠在对话框上方)
			_choice_rects.clear()
			_choice_rects.resize(choices.size())
			const BTN_H: float = 72.0
			const BTN_PAD_X: float = 18.0
			const BTN_GAP: float = 12.0
			const BTN_FONT_SIZE: int = 38
			var btn_w: float = box_w
			var btn_x: float = box_x
			var btn_base_y: float = box_y - BTN_GAP  # 从对话框上沿向上堆叠

			for i in range(choices.size() - 1, -1, -1):
				var choice: Dictionary = choices[i]
				var label: String = choice.get("label", "???")
				var by: float = btn_base_y - BTN_H - (choices.size() - 1 - i) * (BTN_H + BTN_GAP)
				var btn_rect: Rect2 = Rect2(btn_x, by, btn_w, BTN_H)
				_choice_rects[i] = btn_rect

				var is_hover: bool = (_hovered_choice == i)
				var bg_color: Color
				if is_hover:
					bg_color = Color(t.choice_hover.r, t.choice_hover.g, t.choice_hover.b, ds.box_alpha)
				else:
					bg_color = Color(t.choice_bg.r, t.choice_bg.g, t.choice_bg.b, ds.box_alpha * 0.9)
				draw_rect(btn_rect, bg_color, true)
				var border_c: Color = Color(t.choice_border.r, t.choice_border.g, t.choice_border.b, ds.box_alpha * 0.8)
				draw_rect(btn_rect, border_c, false, 3.0)

				# 居中文字
				var text_size: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, BTN_FONT_SIZE)
				var tx: float = btn_x + BTN_PAD_X
				var ty: float = by + (BTN_H + text_size.y * 0.5) * 0.5
				draw_string(_font, Vector2(tx, ty), label,
					HORIZONTAL_ALIGNMENT_LEFT, btn_w - BTN_PAD_X * 2, BTN_FONT_SIZE,
					Color(1.0, 1.0, 1.0, ds.box_alpha))
		else:
			# 无选项时显示闪烁三角
			var blink: float = (sin(m.game_time * ADVANCE_BLINK_SPEED * TAU) + 1.0) * 0.5
			var tri_x: float = box_x + box_w - 90
			var tri_y: float = box_y + box_h - 60
			var tri_color: Color = Color(t.dialogue_indicator, ds.box_alpha * blink)
			var tri_size: float = 18.0
			var points: PackedVector2Array = PackedVector2Array([
				Vector2(tri_x, tri_y),
				Vector2(tri_x + tri_size * 2, tri_y),
				Vector2(tri_x + tri_size, tri_y + tri_size),
			])
			draw_colored_polygon(points, tri_color)

# ---------------------------------------------------------------------------
# 辅助方法
# ---------------------------------------------------------------------------

## 判断跳过按钮是否应该显示
## 条件: 对话活跃 + 非 choosing 状态 (有选项时不显示)
func _is_skip_visible(ds: DialogueSystem) -> bool:
	if not ds.is_active():
		return false
	if ds.box_alpha < 0.01:
		return false
	# choosing 状态 (waiting + 有选项) 时隐藏
	if ds.state == "waiting" and not ds.get_current_choices().is_empty():
		return false
	# entering/exiting 过渡中也不显示
	if ds.state == "entering" or ds.state == "exiting":
		return false
	return true

# ---------------------------------------------------------------------------
# 自动换行
# ---------------------------------------------------------------------------

func _wrap_text(text: String, max_width: float) -> Array:
	var result: Array = []
	var current_line: String = ""
	for ch in text:
		if ch == "\n":
			result.append(current_line)
			current_line = ""
			continue
		var test: String = current_line + ch
		var w: float = _font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_TEXT).x
		if w > max_width and current_line != "":
			result.append(current_line)
			current_line = ch
		else:
			current_line = test
	if current_line != "":
		result.append(current_line)
	return result
