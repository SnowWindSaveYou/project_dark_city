## HandPanel - 手账本面板 (底部 UI)
## 混合架构：场景节点处理结构/交互，_draw() 处理装饰性绘制
## 对应原版 HandPanel.lua，使用 Godot scene 形式实现
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal end_day_pressed
signal schedule_toggled(index: int)
signal use_exorcism_pressed
signal open_clue_log

# ---------------------------------------------------------------------------
# 场景节点引用
# ---------------------------------------------------------------------------
@onready var notebook: Control = $Notebook
@onready var tab_bar: HBoxContainer = $Notebook/TabBar
@onready var tab1_btn: Button = $Notebook/TabBar/Tab1Btn
@onready var tab2_btn: Button = $Notebook/TabBar/Tab2Btn
@onready var clue_btn: Button = $Notebook/TabBar/ClueBtn
@onready var schedule_page: ScrollContainer = $Notebook/SchedulePage
@onready var schedule_vbox: VBoxContainer = $Notebook/SchedulePage/ScheduleVBox
@onready var items_page: Control = $Notebook/ItemsPage
@onready var toolbar_hbox: HBoxContainer = $Notebook/ItemsPage/ToolbarHBox

# ---------------------------------------------------------------------------
# 常量 — 笔记本布局
# ---------------------------------------------------------------------------
const SPINE_W: int = 30
const TAB_H: int = 84
const BASE_BODY_H: int = 420
const LINE_SPACING: float = 54.0
const MARGIN_BOTTOM: int = 24
const MARGIN_X: int = 60
const MAX_W: int = 1020
const PAGE_PAD: int = 36
const CORNER_R: float = 12.0
const OVERFLOW: int = 72

const ITEM_H: int = 84
const CHECK_SIZE: int = 36

const NOTE_W: int = 234
const NOTE_H: int = 132

const TOOLBAR_H: int = 96
const TOOLBAR_ICON: int = 72
const TOOLBAR_GAP: int = 18

const BTN_H: int = 78
const BTN_MARGIN: int = 18

const COLLAPSED_H: float = 108.0

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _expanded: bool = false
var _showcasing: bool = false
var _panel_y: float = 0.0
var _alpha: float = 0.0
var _visible_state: bool = false
var _card_manager: CardManager = null
var _consumable_controller = null
var _hover_end_day: bool = false
var _hover_clue_btn: bool = false
var _rumor_page: int = 1
var _was_can_advance: bool = false
var _active_tab: int = 1  # 1=日程, 2=道具

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_y = _get_viewport_h() + 60

	# 连接 Tab 按钮
	tab1_btn.pressed.connect(_on_tab1_pressed)
	tab2_btn.pressed.connect(_on_tab2_pressed)
	clue_btn.pressed.connect(_on_clue_btn_pressed)

	# 初始隐藏
	notebook.visible = false

	# Tab 样式初始化
	_update_tab_style()

func setup(cm: CardManager, cc) -> void:
	_card_manager = cm
	_consumable_controller = cc

# ---------------------------------------------------------------------------
# Tab 切换
# ---------------------------------------------------------------------------
func _on_tab1_pressed() -> void:
	_active_tab = 1
	_update_tab_style()
	schedule_page.visible = true
	items_page.visible = false
	queue_redraw()

func _on_tab2_pressed() -> void:
	_active_tab = 2
	_update_tab_style()
	schedule_page.visible = false
	items_page.visible = true
	_refresh_toolbar()
	queue_redraw()

func _on_clue_btn_pressed() -> void:
	open_clue_log.emit()

func _update_tab_style() -> void:
	# Tab1
	var c1: Color = GameTheme.text_primary if _active_tab == 1 else Color(GameTheme.text_secondary, 0.55)
	tab1_btn.add_theme_color_override("font_color", c1)
	# Tab2
	var c2: Color = GameTheme.text_primary if _active_tab == 2 else Color(GameTheme.text_secondary, 0.55)
	tab2_btn.add_theme_color_override("font_color", c2)

func _update_clue_btn_label() -> void:
	var clue_count: int = StoryManager.get_clue_count() if StoryManager else 0
	clue_btn.text = "🔍 %d" % clue_count
	var clue_color: Color = Color(0.45, 0.65, 0.45, 0.86) if clue_count > 0 \
		else Color(GameTheme.text_secondary, 0.5)
	clue_btn.add_theme_color_override("font_color", clue_color)

# ---------------------------------------------------------------------------
# 日程列表刷新
# ---------------------------------------------------------------------------
func _refresh_schedule_list() -> void:
	# 清除旧行
	for child in schedule_vbox.get_children():
		child.queue_free()

	if not _card_manager:
		return

	var pr: Rect2 = _get_panel_rect()
	var reward_right_x: float = pr.size.x - PAGE_PAD - NOTE_W - 24 - SPINE_W

	for i in range(_card_manager.schedules.size()):
		var s: Dictionary = _card_manager.schedules[i]
		var row: ScheduleItemRow = ScheduleItemRow.new()
		schedule_vbox.add_child(row)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.set_data(i, s, reward_right_x)
		row.row_clicked.connect(_on_schedule_row_clicked)

## 刷新单行（状态变化后调用）
func refresh_schedule_row(idx: int) -> void:
	if not _card_manager or idx < 0 or idx >= _card_manager.schedules.size():
		return
	var rows: Array = schedule_vbox.get_children()
	if idx < rows.size():
		var row: ScheduleItemRow = rows[idx] as ScheduleItemRow
		if row:
			var pr: Rect2 = _get_panel_rect()
			var reward_right_x: float = pr.size.x - PAGE_PAD - NOTE_W - 24 - SPINE_W
			row.set_data(idx, _card_manager.schedules[idx], reward_right_x)

func _on_schedule_row_clicked(idx: int) -> void:
	schedule_toggled.emit(idx)

# ---------------------------------------------------------------------------
# 道具工具栏刷新
# ---------------------------------------------------------------------------
func _refresh_toolbar() -> void:
	for child in toolbar_hbox.get_children():
		child.queue_free()

	if not _consumable_controller:
		return

	var entries: Array = _consumable_controller.get_consumable_entries()
	for entry in entries:
		var btn: ConsumableItemBtn = ConsumableItemBtn.new()
		toolbar_hbox.add_child(btn)

		# 间距
		if toolbar_hbox.get_child_count() > 1:
			btn.custom_minimum_size.x = TOOLBAR_ICON
		else:
			btn.custom_minimum_size.x = TOOLBAR_ICON

		var tooltip: String = _consumable_controller.get_consumable_tooltip(entry["key"])
		btn.set_entry(entry, tooltip)
		btn.item_used.connect(_on_consumable_item_used)

func _on_consumable_item_used(key: String) -> void:
	if key == "exorcism":
		use_exorcism_pressed.emit()
	else:
		if _consumable_controller.use_consumable(key):
			_refresh_toolbar()
			queue_redraw()

# ---------------------------------------------------------------------------
# Notebook 节点定位（跟随 _panel_y 动画）
# ---------------------------------------------------------------------------
func _update_notebook_position() -> void:
	if not is_instance_valid(notebook):
		return
	var pr: Rect2 = _get_panel_rect()
	notebook.position = Vector2(pr.position.x, _panel_y)
	notebook.size = Vector2(pr.size.x, _get_full_h())
	notebook.visible = _visible_state and _alpha > 0.01
	notebook.modulate.a = _alpha

	# Tab 按钮位置由 TabBar 节点自动布局，只需调整内容页 offset
	var content_offset_y: float = TAB_H
	var content_h: float = _get_full_h() - TAB_H - BTN_H - BTN_MARGIN * 2
	if _consumable_controller and not _consumable_controller.get_consumable_entries().is_empty():
		content_h -= TOOLBAR_H

	schedule_page.position = Vector2(SPINE_W, content_offset_y)
	schedule_page.size = Vector2(pr.size.x - SPINE_W, content_h)

	items_page.position = Vector2(SPINE_W, content_offset_y)
	items_page.size = Vector2(pr.size.x - SPINE_W, content_h)

	# Toolbar 居中
	toolbar_hbox.position = Vector2(
		(items_page.size.x - toolbar_hbox.size.x) / 2.0,
		(content_h - TOOLBAR_ICON) / 2.0
	)

# ---------------------------------------------------------------------------
# 布局辅助
# ---------------------------------------------------------------------------
func _get_viewport_h() -> float:
	return get_viewport_rect().size.y

func _get_viewport_w() -> float:
	return get_viewport_rect().size.x

func _get_body_h() -> float:
	var count: int = _card_manager.schedules.size() if _card_manager else 3
	var base: int = BASE_BODY_H
	if count > 3:
		base = BASE_BODY_H + (count - 3) * ITEM_H
	var toolbar: float = _get_toolbar_h()
	var btn_space: float = (BTN_H + BTN_MARGIN * 2) if toolbar > 0 else 0
	return base + toolbar + btn_space

func _get_toolbar_h() -> float:
	if not _consumable_controller:
		return 0.0
	if _consumable_controller.get_consumable_entries().is_empty():
		return 0.0
	return TOOLBAR_H

func _get_full_h() -> float:
	return TAB_H + _get_body_h()

func _get_target_y() -> float:
	var vh: float = _get_viewport_h()
	if _expanded:
		return vh - _get_full_h() + OVERFLOW
	else:
		return vh - TAB_H - MARGIN_BOTTOM

func _get_panel_rect() -> Rect2:
	var vw: float = _get_viewport_w()
	var pw: float = minf(vw - MARGIN_X * 2, MAX_W)
	var px: float = (vw - pw) / 2.0
	return Rect2(px, _panel_y, pw, _get_full_h())

# ---------------------------------------------------------------------------
# 步数/日程 判断
# ---------------------------------------------------------------------------
func _can_advance() -> bool:
	if not _card_manager:
		return false
	var steps_exhausted: bool = GameData.steps_total > 0 and GameData.steps_remaining <= 0
	if steps_exhausted:
		return true
	for s: Dictionary in _card_manager.schedules:
		if s.get("status", "") == "pending":
			return false
	return _card_manager.schedules.size() > 0

# ---------------------------------------------------------------------------
# 显示 / 隐藏 API
# ---------------------------------------------------------------------------
func show_panel(showcase: bool = false) -> void:
	if _visible_state:
		return
	_visible_state = true
	_alpha = 0.0
	_panel_y = _get_viewport_h() + 60
	_refresh_schedule_list()
	_update_clue_btn_label()
	_update_tab_style()
	notebook.visible = true

	if showcase:
		_expanded = true
		_showcasing = true
		var tw: Tween = create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(self, "_panel_y", _get_target_y(), 0.5)
		tw.parallel().tween_property(self, "_alpha", 1.0, 0.5)
		tw.tween_interval(2.0)
		tw.tween_callback(_finish_showcase)
	else:
		_expanded = false
		_showcasing = false
		var tw: Tween = create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(self, "_panel_y", _get_target_y(), 0.45)
		tw.parallel().tween_property(self, "_alpha", 1.0, 0.45)

func _finish_showcase() -> void:
	if not _showcasing:
		return
	_showcasing = false
	_expanded = false
	var tw: Tween = create_tween()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "_panel_y", _get_target_y(), 0.4)

func hide_panel() -> void:
	if not _visible_state:
		return
	_showcasing = false
	var tw: Tween = create_tween()
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "_panel_y", _panel_y + _get_full_h() + 90, 0.3)
	tw.parallel().tween_property(self, "_alpha", 0.0, 0.3)
	tw.tween_callback(func():
		_visible_state = false
		_expanded = false
		notebook.visible = false
	)

func toggle_expand() -> void:
	if _showcasing:
		_finish_showcase()
		return
	_expanded = not _expanded
	var tw: Tween = create_tween()
	if _expanded:
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	else:
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "_panel_y", _get_target_y(), 0.35)

func expand() -> void:
	if not _expanded:
		toggle_expand()

func collapse() -> void:
	if _expanded:
		toggle_expand()

func is_active() -> bool:
	return _visible_state

func is_expanded() -> bool:
	return _visible_state and _expanded

# ---------------------------------------------------------------------------
# 输入 — Tab 栏点击（场景节点处理点击，这里处理 Tab 栏空白区域和页脚点击）
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if not _visible_state or _alpha < 0.1:
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	var lx: float = mb.position.x
	var ly: float = mb.position.y
	var pr: Rect2 = _get_panel_rect()
	var px: float = pr.position.x
	var py: float = _panel_y
	var pw: float = pr.size.x

	# 不在面板内
	if lx < px or lx > px + pw or ly < py or ly > py + _get_full_h():
		return

	# Tab 栏空白区域 → toggle
	if ly < py + TAB_H:
		if _showcasing:
			_finish_showcase()
			accept_event()
			return
		toggle_expand()
		accept_event()
		return

	if not _expanded or _showcasing:
		accept_event()
		return

	# "结束今天" 页脚点击
	var footer_y: float = _get_footer_y(py, pw)
	if lx >= px + SPINE_W + PAGE_PAD and lx <= px + pw - PAGE_PAD \
			and ly >= footer_y and ly <= footer_y + BTN_H:
		if _can_advance():
			end_day_pressed.emit()
		accept_event()
		return

	# 传闻便签翻页
	if _card_manager and _card_manager.rumors.size() > 1:
		var note_x: float = px + pw - NOTE_W - PAGE_PAD + 2
		var note_y: float = py + TAB_H + (_get_sched_area_h() - NOTE_H) / 2.0
		if lx >= note_x - 12 and lx <= note_x + NOTE_W + 12 \
				and ly >= note_y - 12 and ly <= note_y + NOTE_H + 42:
			_rumor_page += 1
			if _rumor_page > _card_manager.rumors.size():
				_rumor_page = 1
			accept_event()
			queue_redraw()
			return

	accept_event()

func _input(event: InputEvent) -> void:
	if not _visible_state or _alpha < 0.1:
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_update_hover(mm.position.x, mm.position.y)

# ---------------------------------------------------------------------------
# Hover
# ---------------------------------------------------------------------------
func _update_hover(lx: float, ly: float) -> void:
	_hover_end_day = false
	_hover_clue_btn = false

	if not _expanded or _showcasing:
		return

	var pr: Rect2 = _get_panel_rect()
	var px: float = pr.position.x
	var py: float = _panel_y
	var pw: float = pr.size.x

	var footer_y: float = _get_footer_y(py, pw)
	if lx >= px + SPINE_W + PAGE_PAD and lx <= px + pw - PAGE_PAD \
			and ly >= footer_y and ly <= footer_y + BTN_H:
		_hover_end_day = true

# ---------------------------------------------------------------------------
# 布局辅助（页脚位置计算）
# ---------------------------------------------------------------------------
func _get_sched_area_h() -> int:
	var count: int = _card_manager.schedules.size() if _card_manager else 3
	var base: int = BASE_BODY_H
	if count > 3:
		base = BASE_BODY_H + (count - 3) * ITEM_H
	return base

func _get_footer_y(py: float, _pw: float) -> float:
	var body_bottom: float = py + _get_full_h() - OVERFLOW
	return body_bottom - BTN_H - BTN_MARGIN

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if _visible_state:
		_update_notebook_position()
		queue_redraw()
		# 每帧刷新行状态（schedule_data 是字典引用，内容可能被外部改变）
		_sync_schedule_rows()

		# 自动展开检测
		var now_can: bool = _can_advance()
		if now_can and not _was_can_advance:
			if not _expanded:
				expand()
			_update_tab_style()
			_update_clue_btn_label()
		_was_can_advance = now_can

## 同步所有行的绘制（数据已是引用，只需触发 queue_redraw）
func _sync_schedule_rows() -> void:
	if not is_instance_valid(schedule_vbox):
		return
	var rows: Array = schedule_vbox.get_children()
	for row in rows:
		if row is ScheduleItemRow:
			row.queue_redraw()

# ---------------------------------------------------------------------------
# 渲染 — 纯装饰元素（书脊、横线、Tab底色、传闻便签、页脚、阴影）
# ---------------------------------------------------------------------------
func _draw() -> void:
	if not _visible_state or _alpha < 0.05:
		return

	var t = GameTheme
	var font: Font = ThemeDB.fallback_font
	var pr: Rect2 = _get_panel_rect()
	var px: float = pr.position.x
	var py: float = _panel_y
	var pw: float = pr.size.x
	var ph: float = _get_full_h()

	modulate.a = _alpha

	# === 纸张阴影 ===
	draw_rect(Rect2(px + 6, py + 9, pw, ph), Color(0.23, 0.16, 0.08, 0.15))

	# === 纸张主体 ===
	draw_rect(Rect2(px, py, pw, ph), Color(t.notebook_paper, 0.98))

	# === 纸张边框 ===
	draw_rect(Rect2(px, py, pw, ph), Color(t.notebook_border, 0.55), false, 3.0)

	# === 左侧书脊 ===
	draw_rect(Rect2(px, py, SPINE_W, ph), t.notebook_spine)
	draw_line(Vector2(px + SPINE_W - 4.5, py + 6),
		Vector2(px + SPINE_W - 4.5, py + ph - 6),
		Color(t.notebook_spine_h, 0.47), 3.0)
	var stitch_y: float = py + 42.0
	while stitch_y < py + ph - 30:
		draw_line(Vector2(px + 9, stitch_y), Vector2(px + 9, stitch_y + 18),
			Color(t.notebook_spine_h, 0.27), 3.6)
		stitch_y += 48.0

	# === 横线 ===
	_draw_lines(px, py, pw, ph, t)

	# === Tab 底色 ===
	draw_rect(Rect2(px + SPINE_W, py, pw - SPINE_W, TAB_H), Color(t.notebook_tab, 0.7))
	draw_line(Vector2(px + SPINE_W + 18, py + TAB_H - 1.5),
		Vector2(px + pw - 18, py + TAB_H - 1.5),
		Color(t.notebook_border, 0.39), 2.4)

	if not _expanded and not _showcasing:
		modulate.a = 1.0
		return

	# === 传闻便签 ===
	_draw_rumor_note(px, py, pw, font, t)

	# === 页脚（结束今天）===
	_draw_footer(px, py, pw, font, t)

	modulate.a = 1.0

# ---------------------------------------------------------------------------
# 横线
# ---------------------------------------------------------------------------
func _draw_lines(px: float, py: float, pw: float, ph: float, t) -> void:
	var start_x: float = px + SPINE_W + 18
	var end_x: float = px + pw - 18
	var y: float = py + TAB_H + LINE_SPACING * 0.5
	while y < py + ph - 12:
		draw_line(Vector2(start_x, y), Vector2(end_x, y),
			Color(t.notebook_line, 0.27), 1.5)
		y += LINE_SPACING

	var margin_x: float = px + SPINE_W + PAGE_PAD + CHECK_SIZE + 24
	draw_line(Vector2(margin_x, py + TAB_H + 6),
		Vector2(margin_x, py + ph - 12),
		Color(0.82, 0.47, 0.47, 0.18), 2.4)

# ---------------------------------------------------------------------------
# 传闻便签
# ---------------------------------------------------------------------------
func _draw_rumor_note(px: float, py: float, pw: float, font: Font, t) -> void:
	if not _card_manager or _card_manager.rumors.size() == 0:
		return

	var rumors: Array = _card_manager.rumors
	var total: int = rumors.size()

	if _rumor_page > total:
		_rumor_page = 1
	if _rumor_page < 1:
		_rumor_page = total

	var sched_h: int = _get_sched_area_h()
	var note_x: float = px + pw - NOTE_W - PAGE_PAD + 2
	var note_base_y: float = py + TAB_H + (sched_h - NOTE_H) / 2.0

	# --- 底层堆叠 ---
	if total > 1:
		var max_layer: int = mini(total - 1, 2)
		for layer in range(max_layer, 0, -1):
			var peek_idx: int = ((_rumor_page - 1 + layer) % total)
			var peek_rumor: Dictionary = rumors[peek_idx]
			var stack_off: float = layer * 12.0
			var rot_d: float = (1.5 + layer * 1.8) * (-1.0 if (peek_idx % 2 == 0) else 1.0)
			var layer_alpha: float = (0.4 - (layer - 1) * 0.12) * _alpha
			var cx2: float = note_x + NOTE_W / 2.0 + stack_off
			var cy2: float = note_base_y + NOTE_H / 2.0 + stack_off
			var xf2: Transform2D = Transform2D()
			xf2 = xf2.translated(-Vector2(cx2, cy2))
			xf2 = xf2.rotated(deg_to_rad(rot_d))
			xf2 = xf2.translated(Vector2(cx2, cy2))
			draw_set_transform_matrix(xf2)
			var bg_col: Color
			if peek_rumor.get("is_safe", false):
				bg_col = Color(0.855, 0.925, 0.855, 0.82 * layer_alpha / maxf(_alpha, 0.01))
			else:
				bg_col = Color(0.941, 0.878, 0.824, 0.82 * layer_alpha / maxf(_alpha, 0.01))
			draw_rect(Rect2(note_x, note_base_y, NOTE_W, NOTE_H), bg_col)
			draw_rect(Rect2(note_x, note_base_y, NOTE_W, NOTE_H),
				Color(0.706, 0.647, 0.549, 0.2 * layer_alpha / maxf(_alpha, 0.01)), false, 1.8)
			draw_set_transform_matrix(Transform2D.IDENTITY)

	# --- 顶层 ---
	var rumor: Dictionary = rumors[_rumor_page - 1]
	var rot_deg: float = 2.0
	var cx: float = note_x + NOTE_W / 2.0
	var cy: float = note_base_y + NOTE_H / 2.0
	var xf: Transform2D = Transform2D()
	xf = xf.translated(-Vector2(cx, cy))
	xf = xf.rotated(deg_to_rad(rot_deg))
	xf = xf.translated(Vector2(cx, cy))
	draw_set_transform_matrix(xf)

	draw_rect(Rect2(note_x + 6, note_base_y + 6, NOTE_W, NOTE_H),
		Color(0.31, 0.235, 0.157, 0.1))
	var note_color: Color = Color(0.894, 0.949, 0.894, 0.94) if rumor.get("is_safe", false) \
		else Color(0.973, 0.91, 0.855, 0.94)
	draw_rect(Rect2(note_x, note_base_y, NOTE_W, NOTE_H), note_color)
	draw_rect(Rect2(note_x, note_base_y, NOTE_W, NOTE_H),
		Color(0.706, 0.647, 0.549, 0.27), false, 2.4)
	draw_rect(Rect2(cx - 48, note_base_y - 9, 96, 21), Color(0.824, 0.804, 0.745, 0.31))

	var icon_str: String = rumor.get("icon", "📋")
	draw_string(font, Vector2(cx - 18, note_base_y + 48), icon_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 45, t.text_primary)

	var safe_text: String
	var safe_color: Color
	if rumor.get("is_safe", false):
		safe_text = "✓ 安全"
		safe_color = t.safe
	else:
		safe_text = "⚠ 危险"
		safe_color = t.danger
	var safe_w: float = font.get_string_size(safe_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(font, Vector2(cx - safe_w / 2.0, note_base_y + 90), safe_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, safe_color)

	var rumor_text: String = rumor.get("text", "")
	var text_w: float = font.get_string_size(rumor_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
	draw_string(font, Vector2(cx - text_w / 2.0, note_base_y + 126), rumor_text,
		HORIZONTAL_ALIGNMENT_LEFT, NOTE_W - 12, 21, Color(t.text_secondary, 0.71))

	if total > 1:
		var page_text: String = "▶ %d/%d" % [_rumor_page, total]
		var pw2: float = font.get_string_size(page_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
		draw_string(font, Vector2(cx - pw2 / 2.0, note_base_y + NOTE_H + 30), page_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(t.text_secondary, 0.59))

	draw_set_transform_matrix(Transform2D.IDENTITY)

# ---------------------------------------------------------------------------
# 页脚："结束今天" 琥珀线 / 灰色提示
# ---------------------------------------------------------------------------
func _draw_footer(px: float, py: float, pw: float, font: Font, _t) -> void:
	if not _card_manager:
		return

	var pending_count: int = 0
	for s: Dictionary in _card_manager.schedules:
		if s.get("status", "") == "pending":
			pending_count += 1

	var steps_exhausted: bool = GameData.steps_total > 0 and GameData.steps_remaining <= 0
	var can_adv: bool = pending_count == 0 or steps_exhausted

	var footer_y: float = _get_footer_y(py, pw)
	var footer_x: float = px + SPINE_W + PAGE_PAD
	var footer_w: float = pw - SPINE_W - PAGE_PAD * 2
	var t_now: float = Time.get_ticks_msec() / 1000.0

	if can_adv:
		var pulse: float = 0.72 + 0.28 * sin(t_now * 2.6)
		var line_alpha: float = 0.78 if _hover_end_day else (0.35 * pulse + 0.16)
		draw_line(Vector2(footer_x + 8, footer_y),
			Vector2(footer_x + footer_w - 8, footer_y),
			Color(0.824, 0.627, 0.235, line_alpha), 1.5)

		var arrow_nudge: float = 3.0 if _hover_end_day else (1.5 * sin(t_now * 2.0))
		var text_alpha: float = 1.0 if _hover_end_day else (0.67 * pulse + 0.22)
		var text: String = "结束今天 →"
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		draw_string(font,
			Vector2(footer_x + footer_w / 2.0 - tw / 2.0 + arrow_nudge, footer_y + 36),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
			Color(0.824, 0.627, 0.235, text_alpha))
	else:
		var hint: String = "还有 %d 项待完成" % pending_count
		var hw: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(font,
			Vector2(footer_x + footer_w / 2.0 - hw / 2.0, footer_y + 36),
			hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
			Color(0.627, 0.580, 0.510, 0.24))

# ---------------------------------------------------------------------------
# 重置
# ---------------------------------------------------------------------------
func reset() -> void:
	_visible_state = false
	_expanded = false
	_showcasing = false
	_alpha = 0.0
	_hover_end_day = false
	_hover_clue_btn = false
	_rumor_page = 1
	_was_can_advance = false
	_active_tab = 1
	if is_instance_valid(notebook):
		notebook.visible = false
	# 清除动态子节点
	if is_instance_valid(schedule_vbox):
		for child in schedule_vbox.get_children():
			child.queue_free()
	if is_instance_valid(toolbar_hbox):
		for child in toolbar_hbox.get_children():
			child.queue_free()
