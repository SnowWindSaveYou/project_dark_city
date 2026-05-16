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
const BUBBLE_OFFSET_Y: float = 65.0  # 精灵中心在腰部，需要补偿半身高
const FONT_SIZE: int = 13

# ---------------------------------------------------------------------------
# 缓存
# ---------------------------------------------------------------------------
var _font: Font = null

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_dt: float) -> void:
	if m == null:
		return
	var needs_redraw: bool = false
	if m._bubble_dialogue != null and m._bubble_dialogue.bubble_alpha > 0.01:
		needs_redraw = true
	if not needs_redraw and m.has_meta("_npc_bubbles"):
		var npc_bubbles: Dictionary = m.get_meta("_npc_bubbles")
		for bd in npc_bubbles.values():
			if (bd as BubbleDialogue).bubble_alpha > 0.01:
				needs_redraw = true
				break
	if not needs_redraw and m.has_meta("_baiye_bubble"):
		var bd: BubbleDialogue = m.get_meta("_baiye_bubble")
		if bd.bubble_alpha > 0.01:
			needs_redraw = true
	if needs_redraw:
		queue_redraw()

func _draw() -> void:
	if m == null:
		return
	if not m._camera_3d:
		return

	# --- 主角气泡 ---
	if m._bubble_dialogue != null:
		var bd: BubbleDialogue = m._bubble_dialogue
		if bd.bubble_alpha >= 0.01 and bd.text != "" \
				and m._token_sprite and m._token_sprite.visible:
			var screen_pos: Vector2 = m._camera_3d.unproject_position(
				m._token_sprite.global_position)
			_draw_bubble(bd, screen_pos, BUBBLE_OFFSET_Y)

	# --- 白夜气泡 ---
	if m.has_meta("_baiye_bubble") and m._baiye_sprite and m._baiye_sprite.visible:
		var bd: BubbleDialogue = m.get_meta("_baiye_bubble")
		if bd.bubble_alpha >= 0.01 and bd.text != "":
			var screen_pos: Vector2 = m._camera_3d.unproject_position(
				m._baiye_sprite.global_position)
			_draw_bubble(bd, screen_pos, BUBBLE_OFFSET_Y)

	# --- NPC 气泡 ---
	if m.has_meta("_npc_bubbles"):
		var npc_bubbles: Dictionary = m.get_meta("_npc_bubbles")
		for npc_id in npc_bubbles:
			var bd: BubbleDialogue = npc_bubbles[npc_id]
			if bd.bubble_alpha < 0.01 or bd.text == "":
				continue
			# 从 board_visual 找 NPC 3D 节点位置
			var npc_screen: Vector2 = _get_npc_screen_pos(npc_id)
			if npc_screen == Vector2.ZERO:
				continue
			_draw_bubble(bd, npc_screen, BUBBLE_OFFSET_Y)

## 将气泡绘制到指定屏幕坐标上方
func _draw_bubble(bd: BubbleDialogue, anchor_screen: Vector2, offset_y_base: float) -> void:
	var text: String = bd.text
	var line_h: float = FONT_SIZE * 1.3
	var lines: Array = _wrap_text(text, BUBBLE_MAX_W - BUBBLE_PAD_H * 2)
	var text_h: float = lines.size() * line_h

	var max_line_w: float = 0.0
	for line in lines:
		var lw: float = _font.get_string_size(
			line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		max_line_w = maxf(max_line_w, lw)
	var bw: float = minf(max_line_w + BUBBLE_PAD_H * 2, BUBBLE_MAX_W)
	var bh: float = text_h + BUBBLE_PAD_V * 2

	var bx: float = anchor_screen.x - bw * 0.5
	var by: float = anchor_screen.y - bh - BUBBLE_ARROW_H - offset_y_base

	by += bd.offset_y
	var scale_val: float = bd.bubble_scale
	var alpha: float = bd.bubble_alpha

	var cx: float = bx + bw * 0.5
	var cy: float = by + bh
	var draw_x: float = cx - bw * 0.5 * scale_val
	var draw_y: float = cy - bh * scale_val
	var draw_w: float = bw * scale_val
	var draw_h: float = bh * scale_val

	var shadow_rect: Rect2 = Rect2(draw_x + 2, draw_y + 2, draw_w, draw_h)
	draw_rect(shadow_rect, Color(0, 0, 0, 0.12 * alpha), true)

	var bubble_rect: Rect2 = Rect2(draw_x, draw_y, draw_w, draw_h)
	draw_rect(bubble_rect, Color(1, 1, 1, 0.95 * alpha), true)
	draw_rect(bubble_rect, Color(0.75, 0.75, 0.75, 0.5 * alpha), false, 1.0)

	var arrow_top: float = draw_y + draw_h
	var arrow_points: PackedVector2Array = PackedVector2Array([
		Vector2(cx - BUBBLE_ARROW_W * 0.5 * scale_val, arrow_top),
		Vector2(cx + BUBBLE_ARROW_W * 0.5 * scale_val, arrow_top),
		Vector2(cx, arrow_top + BUBBLE_ARROW_H * scale_val),
	])
	draw_colored_polygon(arrow_points, Color(1, 1, 1, 0.95 * alpha))

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

## 获取指定 NPC 的屏幕坐标，找不到返回 Vector2.ZERO
func _get_npc_screen_pos(npc_id: String) -> Vector2:
	if not m.board_visual:
		return Vector2.ZERO
	var npc_nodes: Dictionary = m.board_visual._npc_nodes
	for key in npc_nodes:
		var data: Dictionary = npc_nodes[key]
		if data.get("npc_id", "") == npc_id:
			var node = data.get("node")
			if is_instance_valid(node) and node.visible:
				return m._camera_3d.unproject_position(node.global_position)
	return Vector2.ZERO

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
