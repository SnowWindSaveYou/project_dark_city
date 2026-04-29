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
const BOX_MARGIN_X: float = 20.0
const BOX_MARGIN_BOTTOM: float = 16.0
const BOX_PAD_X: float = 28.0
const BOX_PAD_TOP: float = 36.0
const BOX_PAD_BOTTOM: float = 16.0
const BOX_RADIUS: float = 12.0
const BOX_LINE_SPACING: float = 22.0

const NAME_TAG_H: float = 26.0
const NAME_TAG_PAD_X: float = 14.0
const NAME_TAG_RADIUS: float = 6.0
const NAME_TAG_OFFSET_Y: float = -14.0

const PORTRAIT_H_RATIO: float = 0.75
const PORTRAIT_MARGIN_LEFT: float = 0.05

const FONT_SIZE_TEXT: int = 16
const FONT_SIZE_NAME: int = 14
const LINE_H_MULT: float = 1.5
const ADVANCE_BLINK_SPEED: float = 2.5

# ---------------------------------------------------------------------------
# 缓存
# ---------------------------------------------------------------------------
var _font: Font = null

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_dt: float) -> void:
	if m == null or m._dialogue_system == null:
		return
	var ds: DialogueSystem = m._dialogue_system
	# 需要渲染时才 queue_redraw
	if ds.is_active() or ds.overlay_alpha > 0.01:
		queue_redraw()

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

	# --- 对话框背景 (笔记本纸) ---
	var paper_color: Color = Color(0.98, 0.96, 0.92, ds.box_alpha)
	draw_rect(box_rect, paper_color, true)

	# 笔记本横线
	var line_color: Color = Color(0.7, 0.82, 0.92, ds.box_alpha * 0.4)
	var line_y: float = box_y + BOX_PAD_TOP
	while line_y < box_y + box_h - BOX_PAD_BOTTOM:
		draw_line(
			Vector2(box_x + 12, line_y),
			Vector2(box_x + box_w - 12, line_y),
			line_color, 1.0)
		line_y += BOX_LINE_SPACING

	# 边框
	var border_color: Color = Color(0.65, 0.60, 0.55, ds.box_alpha)
	draw_rect(box_rect, border_color, false, 1.5)

	# --- 名牌 ---
	var speaker: String = ds.get_speaker()
	if speaker != "":
		var name_w: float = _font.get_string_size(speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_NAME).x + NAME_TAG_PAD_X * 2
		var tag_rect: Rect2 = Rect2(
			box_x + 20, box_y + NAME_TAG_OFFSET_Y,
			name_w, NAME_TAG_H)
		draw_rect(tag_rect, Color(0.35, 0.55, 0.75, ds.box_alpha), true)
		draw_rect(tag_rect, Color(0.25, 0.45, 0.65, ds.box_alpha), false, 1.0)
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
		var text_color: Color = Color(0.15, 0.15, 0.15, ds.box_alpha)

		# 简易自动换行
		var lines: Array = _wrap_text(display_text, max_w)
		for i in range(lines.size()):
			var ly: float = text_y + i * (FONT_SIZE_TEXT * LINE_H_MULT)
			if ly > box_y + box_h - BOX_PAD_BOTTOM:
				break
			draw_string(_font, Vector2(text_x, ly + FONT_SIZE_TEXT),
				lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_TEXT,
				text_color)

	# --- 闪烁三角 (等待点击) ---
	if ds.state == "waiting":
		var blink: float = (sin(m.game_time * ADVANCE_BLINK_SPEED * TAU) + 1.0) * 0.5
		var tri_x: float = box_x + box_w - 30
		var tri_y: float = box_y + box_h - 20
		var tri_color: Color = Color(0.4, 0.55, 0.7, ds.box_alpha * blink)
		var tri_size: float = 6.0
		var points: PackedVector2Array = PackedVector2Array([
			Vector2(tri_x, tri_y),
			Vector2(tri_x + tri_size * 2, tri_y),
			Vector2(tri_x + tri_size, tri_y + tri_size),
		])
		draw_colored_polygon(points, tri_color)

	# --- 立绘 ---
	var portrait: Texture2D = ds.get_portrait_texture()
	if portrait and ds.portrait_alpha > 0.01:
		var ph: float = vp.y * PORTRAIT_H_RATIO * ds.portrait_scale
		var pw: float = ph * (portrait.get_width() as float / portrait.get_height() as float)
		var px: float = vp.x * PORTRAIT_MARGIN_LEFT
		var py: float = vp.y - ph + ds.portrait_offset_y
		var p_color: Color = Color(1, 1, 1, ds.portrait_alpha)
		draw_texture_rect(portrait, Rect2(px, py, pw, ph), false, p_color)

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
