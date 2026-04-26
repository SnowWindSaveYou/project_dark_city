## HandPanel - 手账本面板 (底部 UI)
## 对应原版 HandPanel.lua
## 显示日程、传闻、道具工具条和"结束这一天"按钮
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal end_day_pressed
signal schedule_toggled(index: int)

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _expanded := false
var _tab := "schedules"  # "schedules" | "rumors"
var _panel_y := 0.0  # 当前面板 Y 位置 (动画用)
var _target_y := 0.0

# 引用
var _card_manager: CardManager = null

const COLLAPSED_HEIGHT := 40.0
const TAB_HEIGHT := 36.0
const SCHEDULE_ITEM_HEIGHT := 28.0
const RUMOR_HEIGHT := 60.0
const TOOLBAR_HEIGHT := 40.0
const BUTTON_HEIGHT := 36.0
const PADDING := 12.0

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)

## 设置 CardManager 引用
func setup(cm: CardManager) -> void:
	_card_manager = cm

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func toggle_expand() -> void:
	_expanded = not _expanded

func expand() -> void:
	_expanded = true

func collapse() -> void:
	_expanded = false

## 展示模式: 自动展开 → 停留 → 收起
func showcase(delay: float = 2.0) -> void:
	expand()
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(collapse)

# ---------------------------------------------------------------------------
# 布局计算
# ---------------------------------------------------------------------------

func _calc_expanded_height() -> float:
	if _card_manager == null:
		return 200.0
	var h := TAB_HEIGHT + PADDING

	if _tab == "schedules":
		h += _card_manager.schedules.size() * SCHEDULE_ITEM_HEIGHT + PADDING
	else:
		h += max(_card_manager.rumors.size(), 1) * RUMOR_HEIGHT + PADDING

	# 道具工具条
	if not GameData.inventory.is_empty():
		h += TOOLBAR_HEIGHT

	# "结束这一天" 按钮
	h += BUTTON_HEIGHT + PADDING * 2
	return h

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	var expanded_h := _calc_expanded_height()

	_target_y = vp.y - COLLAPSED_HEIGHT if not _expanded else vp.y - expanded_h
	_panel_y = lerpf(_panel_y, _target_y, minf(1.0, delta * 10.0))

	queue_redraw()

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return

		var vp := get_viewport_rect().size
		var local_pos := mb.position
		var panel_top := _panel_y

		# Tab 区域点击 → 切换展开/折叠
		if local_pos.y >= panel_top and local_pos.y < panel_top + TAB_HEIGHT:
			if _expanded:
				# 检查是切换 tab 还是折叠
				if local_pos.x < vp.x / 2:
					_tab = "schedules"
				else:
					_tab = "rumors"
			else:
				toggle_expand()
			accept_event()
			return

		if not _expanded:
			return

		# "结束这一天" 按钮
		var btn_y := panel_top + _calc_expanded_height() - BUTTON_HEIGHT - PADDING
		if local_pos.y >= btn_y and local_pos.y < btn_y + BUTTON_HEIGHT:
			var btn_x := (vp.x - 140) / 2
			if local_pos.x >= btn_x and local_pos.x < btn_x + 140:
				end_day_pressed.emit()
				accept_event()
				return

		# 日程项点击 (延期切换)
		if _tab == "schedules" and _card_manager:
			var item_y := panel_top + TAB_HEIGHT + PADDING
			for i in range(_card_manager.schedules.size()):
				if local_pos.y >= item_y and local_pos.y < item_y + SCHEDULE_ITEM_HEIGHT:
					_card_manager.toggle_defer(i)
					schedule_toggled.emit(i)
					accept_event()
					return
				item_y += SCHEDULE_ITEM_HEIGHT

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _draw() -> void:
	var vp := get_viewport_rect().size
	var t = Theme
	var font := ThemeDB.fallback_font
	var panel_top := _panel_y

	# 笔记本背景
	var bg := Color(t.notebook_paper.r, t.notebook_paper.g, t.notebook_paper.b, 0.95)
	var panel_h := vp.y - panel_top + 10
	draw_rect(Rect2(0, panel_top, vp.x, panel_h), bg)

	# 书脊 (左侧)
	var spine_color := Color(t.notebook_spine.r, t.notebook_spine.g, t.notebook_spine.b, 0.6)
	draw_rect(Rect2(0, panel_top, 8, panel_h), spine_color)

	# 蓝色横线
	var line_color := Color(t.notebook_line.r, t.notebook_line.g, t.notebook_line.b, 0.25)
	var ly := panel_top + TAB_HEIGHT
	while ly < vp.y:
		draw_line(Vector2(15, ly), Vector2(vp.x - 10, ly), line_color, 0.5)
		ly += 20

	# Tab 栏
	var tab_bg := Color(t.notebook_tab.r, t.notebook_tab.g, t.notebook_tab.b, 0.8)
	draw_rect(Rect2(0, panel_top, vp.x, TAB_HEIGHT), tab_bg)

	# Tab 标签
	var schedule_count := _card_manager.schedules.size() if _card_manager else 0
	var rumor_count := _card_manager.rumors.size() if _card_manager else 0

	var sched_label := "📋 日程 (" + str(schedule_count) + ")"
	var rumor_label := "📌 传闻 (" + str(rumor_count) + ")"

	var sched_color := t.text_primary if _tab == "schedules" else t.text_secondary
	var rumor_color := t.text_primary if _tab == "rumors" else t.text_secondary

	draw_string(font, Vector2(vp.x * 0.25, panel_top + 24), sched_label,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 13, sched_color)
	draw_string(font, Vector2(vp.x * 0.75, panel_top + 24), rumor_label,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 13, rumor_color)

	# 活动 tab 下划线
	var ul_x: float = 0.0 if _tab == "schedules" else vp.x / 2.0
	draw_rect(Rect2(ul_x + vp.x * 0.1, panel_top + TAB_HEIGHT - 3, vp.x * 0.3, 3), t.accent)

	if not _expanded:
		return

	# 内容区
	var content_y := panel_top + TAB_HEIGHT + PADDING

	if _tab == "schedules" and _card_manager:
		# 日程列表
		for i in range(_card_manager.schedules.size()):
			var s: Dictionary = _card_manager.schedules[i]
			var sy := content_y + i * SCHEDULE_ITEM_HEIGHT

			# 复选框
			var check_icon := "☑" if s["status"] == "completed" else "☐"
			if s["status"] == "deferred":
				check_icon = "⏳"

			var status_color := t.completed if s["status"] == "completed" \
				else t.deferred if s["status"] == "deferred" \
				else t.text_primary

			draw_string(font, Vector2(24, sy + 18), check_icon,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, status_color)

			# 任务文本
			var verb: String = s.get("verb", "")
			draw_string(font, Vector2(44, sy + 18), verb,
				HORIZONTAL_ALIGNMENT_LEFT, vp.x - 60, 12, status_color)

			# 奖励
			var reward: Dictionary = s.get("reward", {})
			var reward_strs: Array = []
			for key in reward:
				reward_strs.append(GameData.RESOURCE_ICONS.get(key, "") + "+" + str(reward[key]))
			if reward_strs.size() > 0:
				var reward_text := " ".join(reward_strs)
				draw_string(font, Vector2(vp.x - 80, sy + 18), reward_text,
					HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, 0.7))

		content_y += _card_manager.schedules.size() * SCHEDULE_ITEM_HEIGHT + PADDING

	elif _tab == "rumors" and _card_manager:
		# 传闻便签
		for i in range(_card_manager.rumors.size()):
			var r: Dictionary = _card_manager.rumors[i]
			var ry := content_y + i * RUMOR_HEIGHT
			var rot := (randf() - 0.5) * 0.05  # 轻微倾斜 (视觉效果)

			# 便签背景
			var note_color := Color(1.0, 0.95, 0.8, 0.85)
			draw_rect(Rect2(30, ry, vp.x - 60, RUMOR_HEIGHT - 8), note_color)

			# 便签文本
			var rumor_text: String = r.get("text", "")
			draw_string(font, Vector2(40, ry + 28), rumor_text,
				HORIZONTAL_ALIGNMENT_LEFT, vp.x - 80, 12, t.text_primary)

		content_y += maxf(_card_manager.rumors.size(), 1) * RUMOR_HEIGHT + PADDING

	# 道具工具条
	if not GameData.inventory.is_empty():
		var tool_x := 24.0
		for item_key in ShopData.CONSUMABLE_ORDER:
			var count := GameData.get_item_count(item_key)
			if count <= 0:
				continue
			var info := ShopData.get_item_info(item_key)
			# 图标 + 数量
			draw_string(font, Vector2(tool_x, content_y + 24), info.get("icon", "?"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, t.text_primary)
			draw_string(font, Vector2(tool_x + 22, content_y + 28), "×" + str(count),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, t.text_secondary)
			tool_x += 48
		content_y += TOOLBAR_HEIGHT

	# "结束这一天" 按钮
	var btn_w := 140.0
	var btn_x := (vp.x - btn_w) / 2.0
	var btn_y := content_y + PADDING
	draw_rect(Rect2(btn_x, btn_y, btn_w, BUTTON_HEIGHT), t.accent)
	draw_string(font, Vector2(vp.x / 2, btn_y + 24), "结束这一天",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)
