## ScheduleItemRow - 单条日程行（节点版）
## 使用 HBoxContainer + Label 节点，只有勾选框用轻量 _draw()
class_name ScheduleItemRow
extends HBoxContainer

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal row_clicked(index: int)

# ---------------------------------------------------------------------------
# 常量（对应 HandPanel.lua）
# ---------------------------------------------------------------------------
const CHECK_SIZE: float = 33.0
const ITEM_H: float     = 78.0

# ---------------------------------------------------------------------------
# @onready
# ---------------------------------------------------------------------------
@onready var _check_area: Control = $CheckArea
@onready var _icon_label: Label   = $IconLabel
@onready var _text_label: Label   = $TextLabel
@onready var _reward_label: Label = $RewardLabel

# ---------------------------------------------------------------------------
# 数据
# ---------------------------------------------------------------------------
var _index: int           = 0
var _data: Dictionary     = {}
var _is_hovered: bool     = false

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	_apply_styles()
	_check_area.draw.connect(_draw_checkbox)
	mouse_entered.connect(func() -> void: _is_hovered = true; queue_redraw(); _check_area.queue_redraw())
	mouse_exited.connect(func() -> void: _is_hovered = false; queue_redraw(); _check_area.queue_redraw())
	gui_input.connect(_on_gui_input)
	custom_minimum_size = Vector2(0, ITEM_H)

func _apply_styles() -> void:
	var t: Node = get_node("/root/GameTheme")

	_icon_label.add_theme_font_size_override("font_size", 39)
	_text_label.add_theme_font_size_override("font_size", 33)
	_reward_label.add_theme_font_size_override("font_size", 27)
	_reward_label.add_theme_color_override("font_color", Color(t.text_secondary, 0.47))

	# 悬停高亮背景通过 draw() 实现
	set("theme_override_styles/panel", null)

# ---------------------------------------------------------------------------
# 注入数据
# ---------------------------------------------------------------------------
func set_data(idx: int, data: Dictionary) -> void:
	_index = idx
	_data  = data

	var status: String = data.get("status", "pending")
	var t: Node = get_node("/root/GameTheme")

	# 图标
	_icon_label.text = data.get("icon", "📍")

	# 名称（日程数据字段为 "verb"，兼容旧 "label"）
	_text_label.text = data.get("verb", data.get("label", ""))
	match status:
		"completed":
			_text_label.add_theme_color_override("font_color", Color(t.text_secondary, 0.51))
			# 删除线通过在文字外套一条线段（_draw 实现）
		"deferred":
			_text_label.add_theme_color_override("font_color", Color(t.deferred, 0.63))
		_:
			_text_label.add_theme_color_override("font_color", Color(t.text_primary, 0.86))

	# 奖励角标（reward 是 Dictionary，如 {"san": 1}）
	if status != "deferred":
		var reward = data.get("reward", {})
		if reward is Dictionary and not reward.is_empty():
			var first_key: String = reward.keys()[0]
			var first_val = reward[first_key]
			var res_icon: String = _reward_icon(first_key)
			_reward_label.text = "%s+%s" % [res_icon, str(first_val)]
			_reward_label.visible = true
		elif reward is Array and reward.size() >= 2:
			# 兼容旧格式 Array
			var res_icon: String = _reward_icon(reward[0])
			_reward_label.text = "%s+%s" % [res_icon, str(reward[1])]
			_reward_label.visible = true
		else:
			_reward_label.visible = false
	else:
		_reward_label.visible = false

	_check_area.queue_redraw()
	queue_redraw()

func _reward_icon(res_key: String) -> String:
	match res_key:
		"money":  return "💰"
		"san":    return "🧠"
		"order":  return "⚖️"
		_:        return "?"

# ---------------------------------------------------------------------------
# _draw()：勾选框（CheckArea 内部）+ 悬停高亮 + 删除线
# ---------------------------------------------------------------------------
func _draw_checkbox() -> void:
	var t: Node = get_node("/root/GameTheme")
	var status: String = _data.get("status", "pending")

	# 勾选框在 CheckArea 中垂直居中
	var area_h: float = _check_area.size.y
	var ck_x: float   = 6.0
	var ck_y: float   = (area_h - CHECK_SIZE) / 2.0
	var rect: Rect2   = Rect2(ck_x, ck_y, CHECK_SIZE, CHECK_SIZE)

	match status:
		"completed":
			# 填充绿色方框
			_check_area.draw_rect(rect, Color(t.completed, 0.71), true)
			_check_area.draw_rect(rect, Color(t.completed, 0.86), false, 2.0)
			# 白色勾
			var cy: float = ck_y + CHECK_SIZE / 2.0
			_check_area.draw_line(
				Vector2(ck_x + 7.5, cy),
				Vector2(ck_x + CHECK_SIZE * 0.42, cy + 9.0),
				Color.WHITE, 3.0
			)
			_check_area.draw_line(
				Vector2(ck_x + CHECK_SIZE * 0.42, cy + 9.0),
				Vector2(ck_x + CHECK_SIZE - 6.0, cy - 10.5),
				Color.WHITE, 3.0
			)
		"deferred":
			# 空边框 + 箭头符号
			_check_area.draw_rect(rect, Color(t.deferred, 0.47), false, 2.0)
			_check_area.draw_string(
				ThemeDB.fallback_font,
				Vector2(ck_x + 3.0, ck_y + CHECK_SIZE - 6.0),
				"↗", HORIZONTAL_ALIGNMENT_LEFT, -1, 27,
				Color(t.deferred, 0.63)
			)
		_:
			# 空边框（待完成）
			_check_area.draw_rect(rect, Color(t.notebook_border, 0.55), false, 2.0)

func _draw() -> void:
	if not _is_hovered: return
	var status: String = _data.get("status", "pending")
	if status != "pending" and status != "deferred": return

	# 悬停高亮背景（浅蓝圆角矩形）
	draw_rect(
		Rect2(0.0, 2.0, size.x, size.y - 4.0),
		Color(0.29, 0.64, 0.89, 0.07), true, -1.0
	)

# ---------------------------------------------------------------------------
# 输入处理
# ---------------------------------------------------------------------------
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var status: String = _data.get("status", "pending")
			if status == "pending" or status == "deferred":
				row_clicked.emit(_index)
