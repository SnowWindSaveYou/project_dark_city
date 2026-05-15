## HandPanel - 左侧笔记本面板（Godot 节点版）
## 使用 @onready 引用 .tscn 中的节点，动画只控制 NotebookRoot.position.x + rotation
## _draw() 仅在 RuledLines 和 FooterArea 两个子节点中使用（无法用标准节点替代的部分）
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal end_day_pressed
signal schedule_toggled(index: int)
signal use_exorcism_pressed
signal open_clue_log

# ---------------------------------------------------------------------------
# 布局常量（Lua 原版 × 3，适配 Godot 1920×1080 canvas）
# Lua 版在 ~640px 逻辑宽度下运行，ResourceBar stripW 最大 360px
# Godot 版 ResourceBar stripW 最大 1080px → 缩放因子 3.0
# ---------------------------------------------------------------------------
const PANEL_W: float       = 600.0
const MARGIN_TOP: float    = 168.0   # ResourceBar 高度 156px，再留 12px
const MARGIN_BOT: float    = 60.0
const SPINE_W: float       = 42.0
const CORNER_R: float      = 15.0
const PAGE_PAD: float      = 30.0
const LINE_SPACING: float  = 54.0

const EXPANDED_X: float    = 18.0
const PEEK_W: float        = 18.0
const HIDDEN_EXTRA: float  = 150.0
const TILT_COLLAPSED: float = 0.12   # ~6.9°

const TAB_W: float         = 108.0
const TAB_H: float         = 144.0
const TAB_GAP: float       = 24.0
const TAB_RADIUS: float    = 9.0
const TAB_OVERLAP: float   = 30.0

const NOTE_W: float        = 252.0
const NOTE_H: float        = 138.0
const ITEM_H: float        = 78.0
const CHECK_SIZE: float    = 33.0
const ICON_SIZE: float     = 120.0
const ICON_GAP: float      = 24.0
const ICONS_PER_ROW: int   = 3

const TAB_COLORS: Array[Color] = [
	Color(0.961, 0.894, 0.580),   # 暖黄
	Color(0.706, 0.824, 0.941),   # 淡蓝
	Color(0.706, 0.894, 0.725),   # 淡绿
]
const TAB_NAMES: Array[String] = ["日程", "道具", "线索"]

# ---------------------------------------------------------------------------
# @onready 节点引用
# ---------------------------------------------------------------------------
@onready var _notebook_root: Control       = $NotebookRoot
@onready var _notebook_bg: Panel           = $NotebookRoot/NotebookBg
@onready var _spine_rect: ColorRect        = $NotebookRoot/SpineRect
@onready var _ruled_lines: Control         = $NotebookRoot/RuledLines
@onready var _page_header: HBoxContainer   = $NotebookRoot/PageHeader
@onready var _tab_title: Label             = $NotebookRoot/PageHeader/TabTitle
@onready var _collapse_btn: Button         = $NotebookRoot/PageHeader/CollapseBtn

@onready var _schedule_page: Control          = $NotebookRoot/SchedulePage
@onready var _schedule_scroll: ScrollContainer = $NotebookRoot/SchedulePage/ScheduleScroll
@onready var _schedule_vbox: VBoxContainer     = $NotebookRoot/SchedulePage/ScheduleScroll/ScheduleVBox
@onready var _footer_area: Control             = $NotebookRoot/SchedulePage/FooterArea
@onready var _rumor_note: Control              = $NotebookRoot/SchedulePage/RumorNote
@onready var _note_bg: Panel                   = $NotebookRoot/SchedulePage/RumorNote/NoteBg
@onready var _tape_rect: ColorRect             = $NotebookRoot/SchedulePage/RumorNote/TapeRect
@onready var _note_icon: Label                 = $NotebookRoot/SchedulePage/RumorNote/NoteVBox/NoteIcon
@onready var _note_safe: Label                 = $NotebookRoot/SchedulePage/RumorNote/NoteVBox/NoteSafe
@onready var _note_text: Label                 = $NotebookRoot/SchedulePage/RumorNote/NoteVBox/NoteText
@onready var _note_page_label: Label           = $NotebookRoot/SchedulePage/RumorNote/NotePageLabel

@onready var _items_page: ScrollContainer = $NotebookRoot/ItemsPage
@onready var _items_vbox: VBoxContainer   = $NotebookRoot/ItemsPage/ItemsVBox
@onready var _clue_page: VBoxContainer   = $NotebookRoot/CluePage

@onready var _tabs_container: Control = $NotebookRoot/TabsContainer
@onready var _tab_btns: Array[Button] = []   # 在 _ready 中填充

# ---------------------------------------------------------------------------
# 动画状态
# ---------------------------------------------------------------------------
var _visible_state: bool  = false
var _expanded: bool       = false
var _panel_x: float       = 0.0
var _panel_angle: float   = TILT_COLLAPSED
var _alpha: float         = 0.0
var _active_tab: int      = 1
var _was_can_advance: bool = false
var _rumor_page: int      = 1

var _tween: Tween = null

# 回调
var _on_use_exorcism: Callable
var _on_advance_day: Callable

# 外部引用
var _card_manager = null
var _consumable_controller = null

# ---------------------------------------------------------------------------
# _ready：初始化样式 + 布局
# ---------------------------------------------------------------------------
func _ready() -> void:
	_tab_btns = [
		$NotebookRoot/TabsContainer/Tab1Btn,
		$NotebookRoot/TabsContainer/Tab2Btn,
		$NotebookRoot/TabsContainer/Tab3Btn,
	]

	_apply_styles()
	_update_notebook_size()
	_position_tabs()

	# 连接便签按钮信号
	for i in range(3):
		var idx: int = i + 1
		_tab_btns[i].pressed.connect(func() -> void: _on_tab_pressed(idx))

	# 连接收起按钮
	_collapse_btn.pressed.connect(func() -> void: collapse())

	# 连接 FooterArea 鼠标点击
	_footer_area.gui_input.connect(_on_footer_input)

	# RuledLines：注入 _draw 函数
	_ruled_lines.draw.connect(_draw_ruled_lines)

	# FooterArea：注入 _draw 函数
	_footer_area.draw.connect(_draw_footer)
	_footer_area.mouse_filter = Control.MOUSE_FILTER_STOP

	# 初始隐藏，定位到屏幕外
	_panel_x = _hidden_x()
	_notebook_root.position.x = _panel_x
	_notebook_root.modulate.a = 0.0
	_notebook_root.rotation = TILT_COLLAPSED

	visible = false

# ---------------------------------------------------------------------------
# 样式应用
# ---------------------------------------------------------------------------
func _apply_styles() -> void:
	var t: Node = get_node("/root/GameTheme")

	# 纸张背景 StyleBoxFlat
	var paper_sb := StyleBoxFlat.new()
	paper_sb.bg_color = t.notebook_paper
	paper_sb.border_color = t.notebook_border
	paper_sb.set_border_width_all(1)
	paper_sb.set_corner_radius_all(int(CORNER_R))
	paper_sb.shadow_color = Color(0.23, 0.16, 0.08, 0.20)
	paper_sb.shadow_size = 12
	paper_sb.shadow_offset = Vector2(6, 9)
	_notebook_bg.add_theme_stylebox_override("panel", paper_sb)

	# 书脊颜色
	_spine_rect.color = t.notebook_spine

	# 胶带颜色
	_tape_rect.color = Color(0.82, 0.80, 0.75, 0.30)

	# 传闻便签背景（默认安全色，refresh_rumor 时更新）
	var note_sb := StyleBoxFlat.new()
	note_sb.bg_color = Color(0.89, 0.96, 0.89, 0.96)
	note_sb.set_border_width_all(1)
	note_sb.border_color = Color(0.71, 0.65, 0.55, 0.24)
	_note_bg.add_theme_stylebox_override("panel", note_sb)

	# 页眉标题字号
	_tab_title.add_theme_font_size_override("font_size", 33)
	_tab_title.add_theme_color_override("font_color", Color(t.text_secondary, 0.55))
	_tab_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 收起按钮样式
	_collapse_btn.add_theme_font_size_override("font_size", 42)
	_collapse_btn.add_theme_color_override("font_color", t.text_secondary)

	# NoteVBox 各 Label 字号
	_note_icon.add_theme_font_size_override("font_size", 42)
	_note_safe.add_theme_font_size_override("font_size", 27)
	_note_text.add_theme_font_size_override("font_size", 24)
	_note_page_label.add_theme_font_size_override("font_size", 21)
	_note_page_label.add_theme_color_override("font_color", Color(t.text_secondary, 0.55))

	# ClueIcon / ClueText 样式
	var clue_icon: Label = $NotebookRoot/CluePage/ClueIcon
	var clue_text: Label = $NotebookRoot/CluePage/ClueText
	clue_icon.add_theme_font_size_override("font_size", 84)
	clue_text.add_theme_font_size_override("font_size", 33)
	clue_text.add_theme_color_override("font_color", Color(t.text_secondary, 0.35))

	# 便签按钮样式
	_style_tab_buttons()

# ---------------------------------------------------------------------------
# 便签贴按钮样式
# ---------------------------------------------------------------------------
func _style_tab_buttons() -> void:
	for i in range(3):
		var btn: Button = _tab_btns[i]
		var col: Color = TAB_COLORS[i]

		# 普通态
		var sb_normal := StyleBoxFlat.new()
		sb_normal.bg_color = Color(col.r, col.g, col.b, 0.75)
		sb_normal.set_corner_radius_all(0)
		sb_normal.corner_radius_top_right = int(TAB_RADIUS)
		sb_normal.corner_radius_bottom_right = int(TAB_RADIUS)
		sb_normal.border_color = Color(col.r * 0.68, col.g * 0.68, col.b * 0.68, 0.43)
		sb_normal.set_border_width_all(1)
		sb_normal.border_width_left = 0

		# 激活态（更亮更不透明）
		var sb_pressed := StyleBoxFlat.new()
		sb_pressed.bg_color = Color(col.r, col.g, col.b, 0.98)
		sb_pressed.set_corner_radius_all(0)
		sb_pressed.corner_radius_top_right = int(TAB_RADIUS)
		sb_pressed.corner_radius_bottom_right = int(TAB_RADIUS)
		sb_pressed.border_color = Color(col.r * 0.68, col.g * 0.68, col.b * 0.68, 0.75)
		sb_pressed.set_border_width_all(1)
		sb_pressed.border_width_left = 0

		# Hover 态
		var sb_hover := StyleBoxFlat.new()
		sb_hover.bg_color = Color(col.r * 0.95, col.g * 0.95, col.b * 0.95, 0.86)
		sb_hover.set_corner_radius_all(0)
		sb_hover.corner_radius_top_right = int(TAB_RADIUS)
		sb_hover.corner_radius_bottom_right = int(TAB_RADIUS)
		sb_hover.border_color = Color(col.r * 0.68, col.g * 0.68, col.b * 0.68, 0.55)
		sb_hover.set_border_width_all(1)
		sb_hover.border_width_left = 0

		btn.flat = false   # flat=true 会屏蔽所有 StyleBox 覆盖，必须关闭
		btn.add_theme_stylebox_override("normal", sb_normal)
		btn.add_theme_stylebox_override("pressed", sb_pressed)
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.add_theme_stylebox_override("focus", sb_normal)
		btn.add_theme_font_size_override("font_size", 30)
		btn.add_theme_color_override("font_color", Color(0.22, 0.18, 0.14, 0.92))

# ---------------------------------------------------------------------------
# 布局：计算笔记本高度并调整所有子节点
# ---------------------------------------------------------------------------
func _update_notebook_size() -> void:
	var screen_h: float = get_viewport_rect().size.y
	var panel_h: float  = _get_panel_h(screen_h)

	# 调整 NotebookRoot 尺寸
	_notebook_root.custom_minimum_size = Vector2(PANEL_W, panel_h)
	_notebook_root.size = Vector2(PANEL_W, panel_h)

	# 调整 SpineRect 高度
	_spine_rect.size = Vector2(SPINE_W, panel_h)

	# 调整 PageHeader 高度
	var page_top: float = 78.0   # 页头高 26×3
	_page_header.offset_left   = SPINE_W
	_page_header.offset_right  = PANEL_W
	_page_header.offset_bottom = page_top
	_collapse_btn.custom_minimum_size = Vector2(60, 60)

	# RuledLines 全覆盖（由 anchor 决定）
	_ruled_lines.queue_redraw()

	# 调整 SchedulePage / ItemsPage / CluePage 高度
	var page_h: float    = panel_h - page_top
	var content_w: float = PANEL_W - SPINE_W

	_schedule_page.offset_left   = SPINE_W
	_schedule_page.offset_top    = page_top
	_schedule_page.offset_right  = PANEL_W
	_schedule_page.offset_bottom = panel_h

	_items_page.offset_left   = SPINE_W + PAGE_PAD
	_items_page.offset_top    = page_top
	_items_page.offset_right  = PANEL_W - PAGE_PAD
	_items_page.offset_bottom = panel_h

	_clue_page.offset_left   = SPINE_W + PAGE_PAD
	_clue_page.offset_top    = page_top
	_clue_page.offset_right  = PANEL_W - PAGE_PAD
	_clue_page.offset_bottom = panel_h

	# 计算传闻便签和 footer 位置（偏移量同样 ×3）
	var note_y: float   = page_h - NOTE_H - 42.0
	var footer_y: float = note_y - 102.0

	_rumor_note.offset_left   = (content_w - NOTE_W) / 2.0
	_rumor_note.offset_top    = note_y
	_rumor_note.offset_right  = _rumor_note.offset_left + NOTE_W
	_rumor_note.offset_bottom = _rumor_note.offset_top + NOTE_H

	_footer_area.offset_left   = PAGE_PAD
	_footer_area.offset_top    = footer_y
	_footer_area.offset_right  = content_w - PAGE_PAD
	_footer_area.offset_bottom = footer_y + 78.0

	# ScheduleScroll：占据从 0 到 footer_y 的空间
	_schedule_scroll.offset_right  = content_w - PAGE_PAD
	_schedule_scroll.offset_bottom = footer_y - 12.0

	# 初始化时隐藏，定位到屏幕外
	_notebook_root.position = Vector2(_panel_x, MARGIN_TOP)

# ---------------------------------------------------------------------------
# 布局：便签贴位置（在 NotebookRoot 右侧伸出）
# ---------------------------------------------------------------------------
func _position_tabs() -> void:
	var screen_h: float = get_viewport_rect().size.y
	var panel_h: float  = _get_panel_h(screen_h)
	var total_h: float  = 3 * TAB_H + 2 * TAB_GAP
	var start_y: float  = (panel_h - total_h) / 2.0

	_tabs_container.offset_left   = PANEL_W - TAB_OVERLAP
	_tabs_container.offset_top    = 0.0
	_tabs_container.offset_right  = PANEL_W - TAB_OVERLAP + TAB_W
	_tabs_container.offset_bottom = panel_h

	for i in range(3):
		var btn: Button = _tab_btns[i]
		var tab_y: float = start_y + i * (TAB_H + TAB_GAP)
		btn.offset_left   = 0.0
		btn.offset_top    = tab_y
		btn.offset_right  = TAB_W
		btn.offset_bottom = tab_y + TAB_H
		btn.custom_minimum_size = Vector2(TAB_W, TAB_H)

	# 激活 tab 样式更新
	_update_tab_visual()

# ---------------------------------------------------------------------------
# 高度辅助
# ---------------------------------------------------------------------------
func _get_panel_h(screen_h: float) -> float:
	var max_h: float = floor(PANEL_W / 0.62)  # ≈ 968
	var raw_h: float = screen_h - MARGIN_TOP - MARGIN_BOT
	return max(960.0, min(raw_h, max_h))

func _hidden_x() -> float:
	return -(PANEL_W + (TAB_W - TAB_OVERLAP) + HIDDEN_EXTRA)

func _collapsed_x() -> float:
	return -(PANEL_W - PEEK_W)

func _expanded_x() -> float:
	return EXPANDED_X

# ---------------------------------------------------------------------------
# RuledLines._draw()：横线 + 红色左边距线（只绘制线条，轻量）
# ---------------------------------------------------------------------------
func _draw_ruled_lines() -> void:
	var t: Node = get_node("/root/GameTheme")
	var rect: Rect2 = _ruled_lines.get_rect()
	var lx0: float = SPINE_W + 18.0
	var lx1: float = rect.size.x - 18.0
	var ly: float  = LINE_SPACING * 1.2

	# 横线
	while ly < rect.size.y - 12.0:
		_ruled_lines.draw_line(
			Vector2(lx0, ly), Vector2(lx1, ly),
			Color(t.notebook_line, 0.24), 1.5
		)
		ly += LINE_SPACING

	# 红色左边距竖线
	var margin_x: float = SPINE_W + PAGE_PAD + CHECK_SIZE + 24.0
	_ruled_lines.draw_line(
		Vector2(margin_x, 12.0), Vector2(margin_x, rect.size.y - 12.0),
		Color(0.82, 0.47, 0.47, 0.16), 2.0
	)

# ---------------------------------------------------------------------------
# FooterArea._draw()：结束今天 / 还有N项 文字和分隔线
# ---------------------------------------------------------------------------
var _footer_pulse_time: float = 0.0   # 每帧由 _process 累加

func _draw_footer() -> void:
	if not _visible_state or not _expanded: return

	var schedules: Array = _card_manager.schedules if _has_game_data() else []
	var has_pending: bool = false
	var pending_count: int = 0
	for s: Dictionary in schedules:
		if s.get("status", "") == "pending":
			has_pending = true
			pending_count += 1

	# steps_remaining 是剩余步数（Lua getSteps 返回已用步数，语义相反）
	# 步数耗尽 = 剩余为 0 且 total > 0
	var steps_remaining: int = GameData.steps_remaining if _has_game_data() else 0
	var steps_total: int     = GameData.steps_total     if _has_game_data() else 0
	var steps_done: bool  = steps_total > 0 and steps_remaining <= 0
	var can_advance: bool = (not has_pending) or steps_done

	var rect: Rect2 = _footer_area.get_rect()
	var cx: float   = rect.size.x / 2.0
	var t: Node     = get_node("/root/GameTheme")

	if can_advance:
		var pulse: float  = 0.72 + 0.28 * sin(_footer_pulse_time * 2.6)
		var line_alpha: float = 0.35 + 0.35 * pulse
		# 分隔线
		_footer_area.draw_line(
			Vector2(24.0, 0.0), Vector2(rect.size.x - 24.0, 0.0),
			Color(0.82, 0.63, 0.24, line_alpha), 2.0
		)
		# "结束今天 →" 文字
		var text_alpha: float = 0.45 + 0.45 * pulse
		var nudge: float = 4.5 * sin(_footer_pulse_time * 2.0)
		_footer_area.draw_string(
			ThemeDB.fallback_font,
			Vector2(cx - 84.0 + nudge, 36.0),
			"结束今天 →",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1, 30,
			Color(t.warning, text_alpha)
		)
	else:
		# 灰色小字
		_footer_area.draw_string(
			ThemeDB.fallback_font,
			Vector2(cx, 30.0),
			"还有 %d 项待完成" % pending_count,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1, 27,
			Color(0.63, 0.58, 0.51, 0.24)
		)

# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

## 设置 CardManager 和 ConsumableController 引用
func setup(cm, cc) -> void:
	_card_manager = cm
	_consumable_controller = cc

func set_use_exorcism_callback(fn: Callable) -> void:
	_on_use_exorcism = fn

func set_advance_day_callback(fn: Callable) -> void:
	_on_advance_day = fn

## 显示面板（折叠状态滑入）
func show_panel() -> void:
	if _visible_state: return
	_visible_state = true
	_expanded = false
	visible = true
	_notebook_root.modulate.a = 0.0
	_panel_x = _hidden_x()
	_notebook_root.position.x = _panel_x
	_animate_to(_collapsed_x(), TILT_COLLAPSED, 0.45, Tween.EASE_OUT, Tween.TRANS_BACK)
	refresh()

## 隐藏面板
func hide_panel() -> void:
	if not _visible_state: return
	_animate_to(_hidden_x(), TILT_COLLAPSED, 0.3, Tween.EASE_IN, Tween.TRANS_QUAD, func() -> void:
		_visible_state = false
		_expanded = false
		visible = false
	)

## 展开（动画到展开位）
func expand() -> void:
	if _expanded: return
	_expanded = true
	_collapse_btn.visible = true
	_animate_to(_expanded_x(), 0.0, 0.35, Tween.EASE_OUT, Tween.TRANS_BACK)
	_update_tab_visual()

## 折叠（动画到折叠位）
func collapse() -> void:
	if not _expanded: return
	_expanded = false
	_collapse_btn.visible = false
	_animate_to(_collapsed_x(), TILT_COLLAPSED, 0.35, Tween.EASE_IN_OUT, Tween.TRANS_QUAD)
	_update_tab_visual()

## 切换展开/折叠
func toggle_expand() -> void:
	if _expanded:
		collapse()
	else:
		expand()

func is_active() -> bool:
	return _visible_state

func is_expanded() -> bool:
	return _visible_state and _expanded

## 重置
func reset() -> void:
	if _tween:
		_tween.kill()
	_visible_state = false
	_expanded = false
	_panel_x = _hidden_x()
	_notebook_root.position.x = _panel_x
	_notebook_root.modulate.a = 0.0
	_notebook_root.rotation = TILT_COLLAPSED
	visible = false
	_was_can_advance = false
	_rumor_page = 1

# ---------------------------------------------------------------------------
# 动画
# ---------------------------------------------------------------------------
func _animate_to(
	target_x: float,
	target_angle: float,
	duration: float,
	ease_type: Tween.EaseType,
	trans_type: Tween.TransitionType,
	on_complete: Callable = Callable()
) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_notebook_root, "position:x", target_x, duration)\
		.set_ease(ease_type).set_trans(trans_type)
	_tween.tween_property(_notebook_root, "rotation", target_angle, duration)\
		.set_ease(ease_type).set_trans(trans_type)
	_tween.tween_property(_notebook_root, "modulate:a", 1.0, duration * 0.4)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_LINEAR)
	if on_complete.is_valid():
		_tween.chain().tween_callback(on_complete)

# ---------------------------------------------------------------------------
# 每帧更新
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _visible_state: return

	_footer_pulse_time += delta
	_footer_area.queue_redraw()

	# 检测"可进入下一天"状态变化 → 自动展开到日程 tab
	if _has_game_data():
		var schedules: Array = _card_manager.schedules
		var has_pending: bool = false
		for s: Dictionary in schedules:
			if s.get("status", "") == "pending":
				has_pending = true
				break
		var su: int = GameData.steps_remaining
		var sm: int = GameData.steps_total
		var steps_done: bool  = sm > 0 and su <= 0   # remaining <= 0 表示耗尽
		var can_advance: bool = (not has_pending) or steps_done

		if can_advance and not _was_can_advance:
			_active_tab = 1
			_switch_tab_pages()
			if not _expanded:
				expand()
			refresh()
		_was_can_advance = can_advance

# ---------------------------------------------------------------------------
# Tab 切换逻辑
# ---------------------------------------------------------------------------
func _on_tab_pressed(idx: int) -> void:
	if _active_tab == idx and _expanded:
		collapse()
		return
	_active_tab = idx
	_tab_title.text = TAB_NAMES[idx - 1]
	_switch_tab_pages()
	_update_tab_visual()
	if not _expanded:
		expand()
	refresh()

func _switch_tab_pages() -> void:
	_schedule_page.visible = (_active_tab == 1)
	_items_page.visible    = (_active_tab == 2)
	_clue_page.visible     = (_active_tab == 3)

func _update_tab_visual() -> void:
	_tab_title.text = TAB_NAMES[_active_tab - 1]
	# 激活便签向右偏移 2px，未激活恢复
	for i in range(3):
		var btn: Button = _tab_btns[i]
		var nudge: float = 2.0 if (i + 1 == _active_tab and _expanded) else 0.0
		var cur_l: float = btn.offset_left
		# 只改变 offset_right（相当于向右延伸）
		# 用 modulate.a 区分激活/非激活视觉
		btn.modulate.a = 1.0 if (i + 1 == _active_tab) else 0.75

# ---------------------------------------------------------------------------
# 刷新内容
# ---------------------------------------------------------------------------
func refresh() -> void:
	_refresh_schedules()
	_refresh_rumors()
	_refresh_items()

func _refresh_schedules() -> void:
	# 清除旧行
	for child in _schedule_vbox.get_children():
		child.queue_free()

	if not _has_game_data(): return
	var schedules: Array = _card_manager.schedules

	for i in range(schedules.size()):
		var sched: Dictionary = schedules[i]
		var row: Node = preload("res://scenes/ui/components/schedule_item_row.tscn").instantiate()
		_schedule_vbox.add_child(row)
		row.set_data(i, sched)
		row.row_clicked.connect(func(idx: int) -> void: _on_schedule_row_clicked(idx))

func _refresh_rumors() -> void:
	if not _has_game_data(): return
	var rumors: Array = _card_manager.rumors

	if rumors.is_empty():
		_rumor_note.visible = false
		return

	_rumor_note.visible = true
	if _rumor_page > rumors.size():
		_rumor_page = 1

	var rumor: Dictionary = rumors[_rumor_page - 1]
	_note_icon.text = rumor.get("icon", "❓")

	var is_safe: bool = rumor.get("is_safe", true)
	if is_safe:
		_note_safe.text = "✓ 安全"
		_note_safe.add_theme_color_override("font_color", get_node("/root/GameTheme").safe)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.89, 0.96, 0.89, 0.96)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.71, 0.65, 0.55, 0.24)
		_note_bg.add_theme_stylebox_override("panel", sb)
	else:
		_note_safe.text = "⚠ 危险"
		_note_safe.add_theme_color_override("font_color", get_node("/root/GameTheme").danger)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.98, 0.91, 0.85, 0.96)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.71, 0.65, 0.55, 0.24)
		_note_bg.add_theme_stylebox_override("panel", sb)

	_note_text.text = rumor.get("text", "")

	if rumors.size() > 1:
		_note_page_label.text = "▶ %d/%d" % [_rumor_page, rumors.size()]
		_note_page_label.visible = true
	else:
		_note_page_label.visible = false

func _refresh_items() -> void:
	for child in _items_vbox.get_children():
		child.queue_free()

	if not _has_game_data(): return
	var consumables: Array = _consumable_controller.get_consumable_entries() if _consumable_controller != null else []

	for entry: Dictionary in consumables:
		var btn: Node = preload("res://scenes/ui/components/consumable_item_btn.tscn").instantiate()
		_items_vbox.add_child(btn)
		btn.set_entry(entry)
		btn.item_used.connect(func(key: String) -> void: _on_item_used(key))

# ---------------------------------------------------------------------------
# 事件处理
# ---------------------------------------------------------------------------
func _on_schedule_row_clicked(idx: int) -> void:
	schedule_toggled.emit(idx)

func _on_item_used(key: String) -> void:
	# exorcism 还额外发出信号供外部处理怪物驱除效果
	if key == "exorcism":
		use_exorcism_pressed.emit()
	# 所有道具通过 ConsumableController 统一处理
	if _consumable_controller != null:
		_consumable_controller.use_consumable(key)
		refresh()   # 更新道具数量显示

func _on_footer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not _has_game_data(): return
			var schedules: Array = _card_manager.schedules
			var has_pending: bool = false
			for s: Dictionary in schedules:
				if s.get("status", "") == "pending":
					has_pending = true
					break
			var su: int = GameData.steps_remaining
			var sm: int = GameData.steps_total
			var steps_done: bool = sm > 0 and su <= 0   # remaining <= 0 表示耗尽
			if (not has_pending or steps_done):
				end_day_pressed.emit()
				if _on_advance_day.is_valid():
					_on_advance_day.call()

# ---------------------------------------------------------------------------
# 传闻翻页（外部可调用）
# ---------------------------------------------------------------------------
func next_rumor() -> void:
	if not _has_game_data(): return
	var rumors: Array = _card_manager.rumors
	if rumors.size() > 1:
		_rumor_page = (_rumor_page % rumors.size()) + 1
		_refresh_rumors()

# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------
func _has_game_data() -> bool:
	return has_node("/root/GameData") and _card_manager != null

func _on_resize() -> void:
	_update_notebook_size()
	_position_tabs()
