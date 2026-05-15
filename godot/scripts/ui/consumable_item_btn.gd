## ConsumableItemBtn - 单个消耗品道具按钮
## 用作 HandPanel 中 ToolbarHBox 的子节点
## 独立 _draw() 绘制：圆形底色 + 纹理图标/emoji + 数量角标 + hover tooltip
class_name ConsumableItemBtn
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal item_used(key: String)

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const BTN_SIZE: int = 72
const BADGE_R: float = 15.0

# ---------------------------------------------------------------------------
# 数据
# ---------------------------------------------------------------------------
var item_key: String = ""
var item_info: Dictionary = {}   ## ConsumableController.get_consumable_entries() 中的 entry
var item_count: int = 0
var tooltip_text: String = ""

var _is_hovered: bool = false

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	size = Vector2(BTN_SIZE, BTN_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

## 设置道具数据（由 HandPanel 调用）
func set_entry(entry: Dictionary, tooltip: String) -> void:
	item_key = entry.get("key", "")
	item_info = entry.get("info", {})
	item_count = entry.get("count", 0)
	tooltip_text = tooltip
	queue_redraw()

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			item_used.emit(item_key)
			accept_event()

func _on_mouse_entered() -> void:
	_is_hovered = true
	queue_redraw()

func _on_mouse_exited() -> void:
	_is_hovered = false
	queue_redraw()

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _draw() -> void:
	if item_key == "":
		return

	var t = GameTheme
	var font: Font = ThemeDB.fallback_font
	var icon_cx: float = BTN_SIZE / 2.0
	var icon_cy: float = BTN_SIZE / 2.0

	# hover 底色
	if _is_hovered:
		draw_rect(Rect2(-6, -6, BTN_SIZE + 12, BTN_SIZE + 12), Color(t.info, 0.12))

	# 图标背景圆
	var bg_alpha: float = 0.2 if _is_hovered else 0.12
	draw_circle(Vector2(icon_cx, icon_cy), BTN_SIZE / 2.0, Color(t.notebook_border, bg_alpha))

	# 纹理图标（优先）或 emoji fallback
	var tex: Texture2D = ItemIcons.get_texture(item_key)
	if tex:
		var tex_size: float = BTN_SIZE - 4
		draw_texture_rect(tex, Rect2(icon_cx - tex_size / 2, icon_cy - tex_size / 2,
			tex_size, tex_size), false)
	else:
		var icon_str: String = item_info.get("icon", "?")
		draw_string(font, Vector2(icon_cx - 21, icon_cy + 15), icon_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 42, t.text_primary)

	# 数量角标（> 1 时显示）
	if item_count > 1:
		var badge_pos: Vector2 = Vector2(BTN_SIZE - 3, 6)
		draw_circle(badge_pos, BADGE_R, Color(t.info, 0.78))
		draw_string(font, Vector2(badge_pos.x - 9, badge_pos.y + 9), str(item_count),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color.WHITE)

	# hover tooltip 气泡（绘制在按钮上方）
	if _is_hovered and tooltip_text != "":
		var tip: String = tooltip_text
		var tip_size: float = 27.0
		var tip_w: float = font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, tip_size).x
		var pad_x: float = 18.0
		var pad_y: float = 9.0
		var bx: float = icon_cx - tip_w / 2 - pad_x
		var by: float = -tip_size - pad_y * 2 - 6
		var bw: float = tip_w + pad_x * 2
		var bh: float = tip_size + pad_y * 2

		# 阴影
		draw_rect(Rect2(bx + 3, by + 3, bw, bh), Color(t.notebook_border, 0.16))
		# 填充
		draw_rect(Rect2(bx, by, bw, bh), Color(t.notebook_paper, 0.96))
		# 边框
		draw_rect(Rect2(bx, by, bw, bh), Color(t.notebook_border, 0.47), false, 1.5)
		# 文字
		draw_string(font, Vector2(bx + pad_x, by + bh - pad_y), tip,
			HORIZONTAL_ALIGNMENT_LEFT, -1, tip_size, t.text_primary)
