## ScheduleItemRow - 单条日程行
## 用作 HandPanel 中 ScheduleVBox 的子节点
## 独立 _draw() 绘制 checkbox + 图标 + 动词 + 奖励
class_name ScheduleItemRow
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal row_clicked(index: int)

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const ITEM_H: int = 84
const CHECK_SIZE: int = 36
const SPINE_W: int = 30
const PAGE_PAD: int = 36

# ---------------------------------------------------------------------------
# 数据
# ---------------------------------------------------------------------------
var schedule_index: int = 0       ## 对应 _card_manager.schedules[schedule_index]
var schedule_data: Dictionary = {}
var reward_right_x: float = 0.0   ## 由父节点注入，奖励文字右侧边界 x (本地坐标)

var _is_hovered: bool = false

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	custom_minimum_size = Vector2(0, ITEM_H)
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

## 设置行数据（由 HandPanel 调用）
func set_data(idx: int, data: Dictionary, rr_x: float) -> void:
	schedule_index = idx
	schedule_data = data
	reward_right_x = rr_x
	queue_redraw()

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			row_clicked.emit(schedule_index)
			accept_event()

func _on_mouse_entered() -> void:
	var status: String = schedule_data.get("status", "")
	if status in ["pending", "deferred"]:
		_is_hovered = true
		queue_redraw()

func _on_mouse_exited() -> void:
	_is_hovered = false
	queue_redraw()

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _draw() -> void:
	if schedule_data.is_empty():
		return

	var t = GameTheme
	var font: Font = ThemeDB.fallback_font
	var status: String = schedule_data.get("status", "pending")
	var w: float = size.x
	var center_y: float = ITEM_H / 2.0

	# hover 高亮背景
	if _is_hovered:
		draw_rect(Rect2(-6, 6, w + 12, ITEM_H - 12), Color(t.info, 0.07))

	# --- 勾选框 ---
	var check_x: float = CHECK_SIZE + 12.0   # 留出左边距
	var check_y: float = center_y - CHECK_SIZE / 2.0

	if status == "completed":
		draw_rect(Rect2(check_x, check_y, CHECK_SIZE, CHECK_SIZE), Color(t.completed, 0.71))
		draw_rect(Rect2(check_x, check_y, CHECK_SIZE, CHECK_SIZE),
			Color(t.completed, 0.86), false, 3.0)
		draw_string(font, Vector2(check_x + 3, center_y + 15), "✓",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
	elif status == "deferred":
		draw_rect(Rect2(check_x, check_y, CHECK_SIZE, CHECK_SIZE),
			Color(t.deferred, 0.47), false, 3.0)
		draw_string(font, Vector2(check_x + 3, center_y + 12), "↗",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(t.deferred, 0.63))
	else:
		draw_rect(Rect2(check_x, check_y, CHECK_SIZE, CHECK_SIZE),
			Color(t.notebook_border, 0.55), false, 3.0)

	# --- 图标 + 动词 ---
	var text_start_x: float = check_x + CHECK_SIZE + 30
	var icon_str: String = schedule_data.get("icon", "📋")
	draw_string(font, Vector2(text_start_x, center_y + 15), icon_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 42, t.text_primary)
	var icon_w: float = font.get_string_size(icon_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x

	var verb: String = schedule_data.get("verb", "")
	var verb_color: Color
	if status == "completed":
		verb_color = Color(t.text_secondary, 0.55)
	elif status == "deferred":
		verb = verb + " (明天)"
		verb_color = Color(t.deferred, 0.63)
	else:
		verb_color = Color(t.text_primary, 0.86)

	var available_verb_w: float = (reward_right_x if reward_right_x > 0 else w) \
		- text_start_x - icon_w - 12 - 200
	draw_string(font, Vector2(text_start_x + icon_w + 12, center_y + 15), verb,
		HORIZONTAL_ALIGNMENT_LEFT, available_verb_w, 36, verb_color)

	# 删除线（已完成）
	if status == "completed":
		var verb_w: float = font.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
		var line_x1: float = text_start_x + icon_w + 9
		draw_line(Vector2(line_x1, center_y),
			Vector2(line_x1 + verb_w + 6, center_y),
			Color(t.text_secondary, 0.39), 2.4)

	# --- 奖励 ---
	if status != "deferred":
		var reward: Array = schedule_data.get("reward", [])
		if reward.size() >= 2:
			var res_icon: String = GameData.RESOURCE_ICONS.get(reward[0], "?")
			var reward_text: String = res_icon + "+" + str(reward[1])
			var rw: float = font.get_string_size(reward_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x
			var rx: float = (reward_right_x if reward_right_x > 0 else w - 12) - rw
			draw_string(font, Vector2(rx, center_y + 12), reward_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color(t.text_secondary, 0.55))

	# hover 提示
	if _is_hovered:
		var tip: String = "点击取消" if status == "deferred" else "点击推迟"
		var tip_color: Color = Color(t.deferred, 0.63) if status == "deferred" \
			else Color(t.schedule, 0.63)
		var rx2: float = (reward_right_x if reward_right_x > 0 else w - 12) - 200
		draw_string(font, Vector2(rx2, center_y + 12), tip,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 27, tip_color)
