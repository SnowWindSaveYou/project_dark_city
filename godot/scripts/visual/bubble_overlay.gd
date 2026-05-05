## BubbleOverlay - 气泡对话渲染层
## 读取 BubbleDialogue 的动画属性, 在 Token 头顶绘制白色气泡框
## 气泡位置: 将 Token 3D 坐标投影到屏幕, 然后在上方绘制
extends Control

# ---------------------------------------------------------------------------
# 引用
# ---------------------------------------------------------------------------
var m: Node = null  # main.gd 引用 (由 main 注入)

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const BUBBLE_MAX_W: float = 180.0
const BUBBLE_PAD_H: float = 10.0
const BUBBLE_PAD_V: float = 8.0
const BUBBLE_RADIUS: float = 8.0
const BUBBLE_ARROW_W: float = 10.0
const BUBBLE_ARROW_H: float = 8.0
const BUBBLE_OFFSET_Y: float = 12.0
const FONT_SIZE: int = 13

# ---------------------------------------------------------------------------
# 缓存
# ---------------------------------------------------------------------------
var _font: Font = null

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_dt: float) -> void:
	if m == null or m._bubble_dialogue == null:
		return
	var bd: BubbleDialogue = m._bubble_dialogue
	if bd.bubble_alpha > 0.01:
		queue_redraw()

func _draw() -> void:
	if m == null or m._bubble_dialogue == null:
		return
	var bd: BubbleDialogue = m._bubble_dialogue
	if bd.bubble_alpha < 0.01 or bd.text == "":
		return
	if not m._token_sprite or not m._token_sprite.visible:
		return
	if not m._camera_3d or not m._camera_3d.current:
		return

	# Token 屏幕坐标
	var token_screen: Vector2 = m._camera_3d.unproject_position(
		m._token_sprite.global_position)

	# 气泡文本尺寸
	var text: String = bd.text
	var lines: Array = _wrap_text(text, BUBBLE_MAX_W - BUBBLE_PAD_H * 2)
	var line_h: float = FONT_SIZE * 1.3
	var text_h: float = lines.size() * line_h

	# 气泡尺寸
	var max_line_w: float = 0.0
	for line in lines:
		var lw: float = _font.get_string_size(
			line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		max_line_w = maxf(max_line_w, lw)
	var bw: float = minf(max_line_w + BUBBLE_PAD_H * 2, BUBBLE_MAX_W)
	var bh: float = text_h + BUBBLE_PAD_V * 2

	# 气泡位置 (Token 上方)
	var bx: float = token_screen.x - bw * 0.5
	var by: float = token_screen.y - bh - BUBBLE_ARROW_H - BUBBLE_OFFSET_Y

	# 应用动画偏移和缩放
	by += bd.offset_y
	var scale_val: float = bd.bubble_scale
	var alpha: float = bd.bubble_alpha

	# 缩放变换 (以气泡底部中心为锚点)
	var cx: float = bx + bw * 0.5
	var cy: float = by + bh
	var draw_x: float = cx - bw * 0.5 * scale_val
	var draw_y: float = cy - bh * scale_val
	var draw_w: float = bw * scale_val
	var draw_h: float = bh * scale_val

	# --- 阴影 ---
	var shadow_rect: Rect2 = Rect2(draw_x + 2, draw_y + 2, draw_w, draw_h)
	draw_rect(shadow_rect, Color(0, 0, 0, 0.12 * alpha), true)

	# --- 气泡背景 ---
	var bubble_rect: Rect2 = Rect2(draw_x, draw_y, draw_w, draw_h)
	draw_rect(bubble_rect, Color(1, 1, 1, 0.95 * alpha), true)

	# --- 边框 ---
	draw_rect(bubble_rect, Color(0.75, 0.75, 0.75, 0.5 * alpha), false, 1.0)

	# --- 三角箭头 ---
	var arrow_cx: float = cx
	var arrow_top: float = draw_y + draw_h
	var arrow_points: PackedVector2Array = PackedVector2Array([
		Vector2(arrow_cx - BUBBLE_ARROW_W * 0.5 * scale_val, arrow_top),
		Vector2(arrow_cx + BUBBLE_ARROW_W * 0.5 * scale_val, arrow_top),
		Vector2(arrow_cx, arrow_top + BUBBLE_ARROW_H * scale_val),
	])
	draw_colored_polygon(arrow_points, Color(1, 1, 1, 0.95 * alpha))

	# --- 文本 ---
	if scale_val > 0.5:
		var text_color: Color = Color(0.15, 0.15, 0.15, alpha)
		var tx: float = draw_x + BUBBLE_PAD_H * scale_val
		var ty: float = draw_y + BUBBLE_PAD_V * scale_val + FONT_SIZE * scale_val * 0.85
		var scaled_font_size: int = maxi(int(FONT_SIZE * scale_val), 8)
		var scaled_line_h: float = line_h * scale_val
		for i in range(lines.size()):
			draw_string(_font,
				Vector2(tx, ty + i * scaled_line_h),
				lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
				scaled_font_size, text_color)

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
		var w: float = _font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		if w > max_width and current_line != "":
			result.append(current_line)
			current_line = ch
		else:
			current_line = test
	if current_line != "":
		result.append(current_line)
	return result
