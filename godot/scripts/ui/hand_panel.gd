## HandPanel - 手账本面板 (底部 UI)
## 对应原版 HandPanel.lua
## 显示日程、传闻便签(翻页+堆叠)、道具工具条(纹理图标)、"结束这一天"按钮
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal end_day_pressed
signal schedule_toggled(index: int)
signal use_exorcism_pressed  # 驱魔香特殊回调

# ---------------------------------------------------------------------------
# 常量 — 笔记本布局 (与 Lua 版一致)
# ---------------------------------------------------------------------------
const SPINE_W: int = 10
const TAB_H: int = 28
const BASE_BODY_H: int = 140
const LINE_SPACING: float = 18.0
const MARGIN_BOTTOM: int = 8
const MARGIN_X: int = 20
const MAX_W: int = 340
const PAGE_PAD: int = 12
const CORNER_R: float = 4.0
const OVERFLOW: int = 24  # 底部溢出屏幕量

# 日程条目
const ITEM_H: int = 28
const CHECK_SIZE: int = 12

# 传闻便签
const NOTE_W: int = 78
const NOTE_H: int = 44

# 道具工具栏
const TOOLBAR_H: int = 32
const TOOLBAR_ICON: int = 24
const TOOLBAR_GAP: int = 6

# 结束今天按钮
const BTN_H: int = 26
const BTN_MARGIN: int = 6

# 折叠时露出高度
const COLLAPSED_H: float = 36.0

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _expanded: bool = false
var _showcasing: bool = false
var _panel_y: float = 0.0
var _alpha: float = 0.0
var _visible_state: bool = false
var _card_manager: CardManager = null
var _hover_index: int = 0  # 日程 hover (1-based)
var _hover_end_day: bool = false
var _hover_toolbar: String = "" # 工具栏 hover 的 item key
var _rumor_page: int = 1  # 传闻翻页 (1-based, 循环)

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_y = _get_viewport_h() + 20

func setup(cm: CardManager) -> void:
	_card_manager = cm

# ---------------------------------------------------------------------------
# 布局辅助
# ---------------------------------------------------------------------------

func _get_viewport_h() -> float:
	return get_viewport_rect().size.y

func _get_viewport_w() -> float:
	return get_viewport_rect().size.x

func _get_toolbar_h() -> float:
	if GameData.inventory.is_empty():
		return 0.0
	return TOOLBAR_H

func _get_body_h() -> float:
	var count: int = _card_manager.schedules.size() if _card_manager else 3
	var base: int = BASE_BODY_H
	if count > 3:
		base = BASE_BODY_H + (count - 3) * ITEM_H
	var toolbar: float = _get_toolbar_h()
	var btn_space: bool = (BTN_H + BTN_MARGIN * 2) if toolbar > 0 else 0
	return base + toolbar + btn_space

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

func _get_end_day_btn_rect(px: float, py: float, pw: float) -> Rect2:
	var btn_w: float = pw - SPINE_W - PAGE_PAD * 2
	var btn_x: float = px + SPINE_W + PAGE_PAD
	var btn_y: float = py + TAB_H + _get_body_h() - OVERFLOW - BTN_H - BTN_MARGIN
	return Rect2(btn_x, btn_y, btn_w, BTN_H)

func _get_toolbar_y(py: float) -> float:
	var btn_rect: Rect2 = _get_end_day_btn_rect(0, py, 200)
	return btn_rect.position.y - _get_toolbar_h()

func _get_toolbar_item_rect(px: float, py: float, pw: float,
		idx: int, total: int) -> Rect2:
	var toolbar_y: float = _get_toolbar_y(py)
	var content_w: float = pw - SPINE_W - PAGE_PAD * 2
	var total_item_w: int = total * TOOLBAR_ICON + (total - 1) * TOOLBAR_GAP
	var start_x: float = px + SPINE_W + PAGE_PAD + (content_w - total_item_w) / 2.0
	var ix: float = start_x + idx * (TOOLBAR_ICON + TOOLBAR_GAP)
	var iy: float = toolbar_y + (TOOLBAR_H - TOOLBAR_ICON) / 2.0
	return Rect2(ix, iy, TOOLBAR_ICON, TOOLBAR_ICON)

# ---------------------------------------------------------------------------
# 显示 / 隐藏 API
# ---------------------------------------------------------------------------

func show_panel(showcase: bool = false) -> void:
	if _visible_state:
		return
	_visible_state = true
	_alpha = 0.0
	_panel_y = _get_viewport_h() + 20

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
	tw.tween_property(self, "_panel_y", _panel_y + _get_full_h() + 30, 0.3)
	tw.parallel().tween_property(self, "_alpha", 0.0, 0.3)
	tw.tween_callback(func():
		_visible_state = false
		_expanded = false
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
# 输入
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
	var py: float = pr.position.y
	var pw: float = pr.size.x
	var vw: float = _get_viewport_w()

	# 不在面板内
	if lx < px or lx > px + pw or ly < py or ly > py + _get_full_h():
		return

	# Tab 栏
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

	# 道具工具栏
	var consumable_keys: Array = _get_consumable_entries()
	if consumable_keys.size() > 0:
		for idx in range(consumable_keys.size()):
			var ir: Rect2 = _get_toolbar_item_rect(px, py, pw, idx, consumable_keys.size())
			if ir.has_point(Vector2(lx, ly)):
				var entry: Dictionary = consumable_keys[idx]
				if entry["key"] == "exorcism":
					use_exorcism_pressed.emit()
				else:
					_use_consumable(entry["key"])
				accept_event()
				return

	# "结束今天"按钮
	var btn_rect: Rect2 = _get_end_day_btn_rect(px, py, pw)
	if btn_rect.has_point(Vector2(lx, ly)):
		end_day_pressed.emit()
		accept_event()
		return

	# 传闻便签点击 → 翻页
	if _card_manager and _card_manager.rumors.size() > 1:
		var sched_count: int = _card_manager.schedules.size()
		var sched_h: int = BASE_BODY_H
		if sched_count > 3:
			sched_h = BASE_BODY_H + (sched_count - 3) * ITEM_H
		var note_x: float = px + pw - NOTE_W - PAGE_PAD + 2
		var note_base_y: float = py + TAB_H + (sched_h - NOTE_H) / 2.0
		var hit_pad: float = 4.0
		if lx >= note_x - hit_pad and lx <= note_x + NOTE_W + hit_pad \
				and ly >= note_base_y - hit_pad and ly <= note_base_y + NOTE_H + hit_pad + 10:
			_rumor_page += 1
			if _rumor_page > _card_manager.rumors.size():
				_rumor_page = 1
			accept_event()
			queue_redraw()
			return

	# 日程条目点击
	if _card_manager:
		var content_x: float = px + SPINE_W + PAGE_PAD
		var content_y: float = py + TAB_H + 4
		for i in range(_card_manager.schedules.size()):
			var item_y: float = content_y + i * ITEM_H
			if ly >= item_y and ly <= item_y + ITEM_H and lx >= content_x and lx <= px + pw - PAGE_PAD:
				_card_manager.toggle_defer(i)
				schedule_toggled.emit(i)
				accept_event()
				return

	accept_event()  # 面板内消费事件

func _input(event: InputEvent) -> void:
	if not _visible_state or _alpha < 0.1:
		return
	# Hover 跟踪
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_update_hover(mm.position.x, mm.position.y)

# ---------------------------------------------------------------------------
# Hover
# ---------------------------------------------------------------------------
func _update_hover(lx: float, ly: float) -> void:
	_hover_index = 0
	_hover_end_day = false
	_hover_toolbar = ""

	if not _expanded or _showcasing:
		return

	var pr: Rect2 = _get_panel_rect()
	var px: float = pr.position.x
	var py: float = pr.position.y
	var pw: float = pr.size.x

	# 结束今天
	var btn_rect: Rect2 = _get_end_day_btn_rect(px, py, pw)
	if btn_rect.has_point(Vector2(lx, ly)):
		_hover_end_day = true

	# 工具栏
	var consumables: Array = _get_consumable_entries()
	for idx in range(consumables.size()):
		var ir: Rect2 = _get_toolbar_item_rect(px, py, pw, idx, consumables.size())
		if ir.has_point(Vector2(lx, ly)):
			_hover_toolbar = consumables[idx]["key"]
			break

	# 日程条目
	if _card_manager:
		var content_x: float = px + SPINE_W + PAGE_PAD
		var content_y: float = py + TAB_H + 4
		for i in range(_card_manager.schedules.size()):
			var item_y: float = content_y + i * ITEM_H
			if ly >= item_y and ly <= item_y + ITEM_H and lx >= content_x and lx <= px + pw - PAGE_PAD:
				var s: Dictionary = _card_manager.schedules[i]
				if s["status"] in ["pending", "deferred"]:
					_hover_index = i + 1  # 1-based
				break

# ---------------------------------------------------------------------------
# 消耗品辅助
# ---------------------------------------------------------------------------

func _get_consumable_entries() -> Array:
	var result: Array = []
	for key in ShopData.CONSUMABLE_ORDER:
		var count: int = GameData.get_item_count(key)
		if count > 0:
			result.append({
				"key": key,
				"count": count,
				"info": ShopData.get_item_info(key),
			})
	return result

func _use_consumable(key: String) -> void:
	var info: Dictionary = ShopData.get_item_info(key)
	if info.is_empty():
		return
	if not GameData.remove_item(key):
		return
	# 应用效果
	var effects: Dictionary = info.get("effect", {})
	GameData.apply_effects(effects)

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if _visible_state and _alpha > 0.01:
		queue_redraw()

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _draw() -> void:
	if not _visible_state or _alpha < 0.05:
		return

	var vw: float = _get_viewport_w()
	var vh: float = _get_viewport_h()
	var t = GameTheme
	var font: Font = ThemeDB.fallback_font

	var pr: Rect2 = _get_panel_rect()
	var px: float = pr.position.x
	var py: float = pr.position.y
	var pw: float = pr.size.x
	var ph: float = pr.size.y

	# 全局 modulate alpha
	modulate.a = _alpha

	# === 纸张阴影 ===
	draw_rect(Rect2(px + 2, py + 3, pw, ph), Color(0.23, 0.16, 0.08, 0.15))

	# === 纸张主体 ===
	draw_rect(Rect2(px, py, pw, ph), Color(t.notebook_paper, 0.98))

	# === 纸张边框 ===
	draw_rect(Rect2(px, py, pw, ph), Color(t.notebook_border, 0.55), false, 1.0)

	# === 左侧书脊 ===
	draw_rect(Rect2(px, py, SPINE_W, ph), t.notebook_spine)
	# 书脊高光线
	draw_line(Vector2(px + SPINE_W - 1.5, py + 2),
		Vector2(px + SPINE_W - 1.5, py + ph - 2),
		Color(t.notebook_spine_h, 0.47), 1.0)
	# 书脊缝线装饰
	var stitch_y: float = py + 14.0
	while stitch_y < py + ph - 10:
		draw_line(Vector2(px + 3, stitch_y),
			Vector2(px + 3, stitch_y + 6),
			Color(t.notebook_spine_h, 0.27), 1.2)
		stitch_y += 16.0

	# === 横线 ===
	_draw_lines(px, py, pw, ph, t)

	# === Tab 栏 ===
	_draw_tab_bar(px, py, pw, font, t)

	if not _expanded and not _showcasing:
		modulate.a = 1.0
		return

	# === 日程条目 ===
	_draw_schedule_items(px, py, pw, font, t)

	# === 传闻便签 ===
	_draw_rumor_note(px, py, pw, font, t)

	# === 道具工具栏 ===
	_draw_toolbar(px, py, pw, font, t)

	# === 结束今天按钮 ===
	_draw_end_day_btn(px, py, pw, font, t)

	modulate.a = 1.0

# ---------------------------------------------------------------------------
# 横线
# ---------------------------------------------------------------------------
func _draw_lines(px: float, py: float, pw: float, ph: float, t) -> void:
	var start_x: float = px + SPINE_W + 6
	var end_x: float = px + pw - 6
	var y: float = py + TAB_H + LINE_SPACING * 0.5
	while y < py + ph - 4:
		draw_line(Vector2(start_x, y), Vector2(end_x, y),
			Color(t.notebook_line, 0.27), 0.5)
		y += LINE_SPACING

	# 红色左边距竖线
	var margin_x: float = px + SPINE_W + PAGE_PAD + CHECK_SIZE + 8
	draw_line(Vector2(margin_x, py + TAB_H + 2),
		Vector2(margin_x, py + ph - 4),
		Color(0.82, 0.47, 0.47, 0.18), 0.8)

# ---------------------------------------------------------------------------
# Tab 栏
# ---------------------------------------------------------------------------
func _draw_tab_bar(px: float, py: float, pw: float, font: Font, t) -> void:
	# Tab 底色
	draw_rect(Rect2(px + SPINE_W, py, pw - SPINE_W, TAB_H),
		Color(t.notebook_tab, 0.7))

	# 底部分隔线
	draw_line(Vector2(px + SPINE_W + 6, py + TAB_H - 0.5),
		Vector2(px + pw - 6, py + TAB_H - 0.5),
		Color(t.notebook_border, 0.39), 0.8)

	var tab_cy: float = py + TAB_H / 2.0 + 4

	# 左: 日程
	var progress: Array = _card_manager.get_progress() if _card_manager else [0, 0]
	var sched_label: String = "📋 日程 %d/%d" % [progress[0], progress[1]]
	draw_string(font, Vector2(px + SPINE_W + 14, tab_cy), sched_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(t.text_primary, 0.78))

	# 右: 传闻
	var rumor_count: int = _card_manager.rumors.size() if _card_manager else 0
	var rumor_label: String
	if rumor_count > 1:
		var page: int = clampi(_rumor_page, 1, rumor_count)
		rumor_label = "传闻 %d/%d 📰" % [page, rumor_count]
	else:
		rumor_label = "传闻 %d 📰" % rumor_count
	var rumor_w: float = font.get_string_size(rumor_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(px + pw - rumor_w - 10, tab_cy), rumor_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(t.text_primary, 0.78))

	# 中间: 拉手 (三条短横线)
	var handle_x: float = px + pw / 2.0
	var handle_y: float = py + TAB_H / 2.0
	for i in range(-1, 2):
		draw_line(Vector2(handle_x - 8, handle_y + i * 3.5),
			Vector2(handle_x + 8, handle_y + i * 3.5),
			Color(t.notebook_border, 0.47), 1.2)

# ---------------------------------------------------------------------------
# 日程条目
# ---------------------------------------------------------------------------
func _draw_schedule_items(px: float, py: float, pw: float, font: Font, t) -> void:
	if not _card_manager:
		return
	var content_x: float = px + SPINE_W + PAGE_PAD
	var content_y: float = py + TAB_H + 4
	var reward_right_x: float = px + pw - PAGE_PAD - NOTE_W - 8

	for i in range(_card_manager.schedules.size()):
		var s: Dictionary = _card_manager.schedules[i]
		var item_y: float = content_y + i * ITEM_H
		var center_y: float = item_y + ITEM_H / 2.0
		var is_hovered: bool = (_hover_index == i + 1 and s["status"] in ["pending", "deferred"])

		# hover 高亮
		if is_hovered:
			draw_rect(Rect2(content_x - 2, item_y + 2,
				pw - SPINE_W - PAGE_PAD * 2 + 4, ITEM_H - 4),
				Color(0.294, 0.639, 0.89, 0.07))

		# 勾选框
		var check_x: float = content_x
		var check_y: float = center_y - CHECK_SIZE / 2.0
		var status: String = s["status"]

		if status == "completed":
			draw_rect(Rect2(check_x, check_y, CHECK_SIZE, CHECK_SIZE),
				Color(t.completed, 0.71))
			draw_rect(Rect2(check_x, check_y, CHECK_SIZE, CHECK_SIZE),
				Color(t.completed, 0.86), false, 1.0)
			# 勾号 ✓
			draw_string(font, Vector2(check_x + 1, center_y + 5), "✓",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
		elif status == "deferred":
			draw_rect(Rect2(check_x, check_y, CHECK_SIZE, CHECK_SIZE),
				Color(t.deferred, 0.47), false, 1.0)
			draw_string(font, Vector2(check_x + 1, center_y + 4), "↗",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(t.deferred, 0.63))
		else:
			draw_rect(Rect2(check_x, check_y, CHECK_SIZE, CHECK_SIZE),
				Color(t.notebook_border, 0.55), false, 1.0)

		# 地点图标
		var text_start_x: float = content_x + CHECK_SIZE + 10
		var icon_str: String = s.get("icon", "📋")
		draw_string(font, Vector2(text_start_x, center_y + 5), icon_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, t.text_primary)
		var icon_w: float = font.get_string_size(icon_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x

		# 日程描述
		var verb: String = s.get("verb", "")
		var verb_color: Color
		if status == "completed":
			verb_color = Color(t.text_secondary, 0.55)
		elif status == "deferred":
			verb = verb + " (明天)"
			verb_color = Color(t.deferred, 0.63)
		else:
			verb_color = Color(t.text_primary, 0.86)
		draw_string(font, Vector2(text_start_x + icon_w + 4, center_y + 5), verb,
			HORIZONTAL_ALIGNMENT_LEFT, pw - 120, 12, verb_color)

		# 删除线 (已完成)
		if status == "completed":
			var verb_w: float = font.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var line_x1: float = text_start_x + icon_w + 3
			draw_line(Vector2(line_x1, center_y),
				Vector2(line_x1 + verb_w + 2, center_y),
				Color(t.text_secondary, 0.39), 0.8)

		# 奖励标记
		if status != "deferred":
			var reward: Array = s.get("reward", [])
			if reward.size() >= 2:
				var res_icon: String = GameData.RESOURCE_ICONS.get(reward[0], "?")
				var reward_text: String = res_icon + "+" + str(reward[1])
				var rw: float = font.get_string_size(reward_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
				draw_string(font, Vector2(reward_right_x - rw, center_y + 4), reward_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(t.text_secondary, 0.55))

		# hover 提示
		if is_hovered:
			var tip: String = "点击取消" if status == "deferred" else "点击推迟"
			var tip_color: Color = Color(t.deferred, 0.63) if status == "deferred" \
				else Color(t.schedule, 0.63)
			draw_string(font, Vector2(reward_right_x - 60, center_y + 4), tip,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, tip_color)

# ---------------------------------------------------------------------------
# 传闻便签 (翻页 + 堆叠)
# ---------------------------------------------------------------------------
func _draw_rumor_note(px: float, py: float, pw: float, font: Font, t) -> void:
	if not _card_manager or _card_manager.rumors.size() == 0:
		return

	var rumors: Array = _card_manager.rumors
	var total: int = rumors.size()

	# 保证 _rumor_page 在有效范围
	if _rumor_page > total:
		_rumor_page = 1
	if _rumor_page < 1:
		_rumor_page = total

	# 日程区高度 (不含工具栏)
	var sched_count: int = _card_manager.schedules.size()
	var sched_h: int = BASE_BODY_H
	if sched_count > 3:
		sched_h = BASE_BODY_H + (sched_count - 3) * ITEM_H

	# 便签基准位置
	var note_x: float = px + pw - NOTE_W - PAGE_PAD + 2
	var note_base_y: float = py + TAB_H + (sched_h - NOTE_H) / 2.0

	# --- 底层堆叠便签 (暗示还有更多传闻) ---
	if total > 1:
		var max_layer: int = mini(total - 1, 2)
		for layer in range(max_layer, 0, -1):
			var peek_idx: int = ((_rumor_page - 1 + layer) % total)
			var peek_rumor: Dictionary = rumors[peek_idx]

			var stack_off: float = layer * 4.0
			var rot_deg: bool = (1.5 + layer * 1.8) * (-1.0 if (peek_idx % 2 == 0) else 1.0)
			var layer_alpha: float = (0.4 - (layer - 1) * 0.12) * _alpha

			var cx: float = note_x + NOTE_W / 2.0 + stack_off
			var cy: float = note_base_y + NOTE_H / 2.0 + stack_off

			# 用 transform 做旋转
			var xf: Transform2D = Transform2D()
			xf = xf.translated(-Vector2(cx, cy))
			xf = xf.rotated(deg_to_rad(rot_deg))
			xf = xf.translated(Vector2(cx, cy))
			draw_set_transform_matrix(xf)

			var bg_col: Color
			if peek_rumor.get("is_safe", false):
				bg_col = Color(0.855, 0.925, 0.855, 0.82 * layer_alpha / _alpha)
			else:
				bg_col = Color(0.941, 0.878, 0.824, 0.82 * layer_alpha / _alpha)
			draw_rect(Rect2(note_x, note_base_y, NOTE_W, NOTE_H), bg_col)
			draw_rect(Rect2(note_x, note_base_y, NOTE_W, NOTE_H),
				Color(0.706, 0.647, 0.549, 0.2 * layer_alpha / _alpha), false, 0.6)

			draw_set_transform_matrix(Transform2D.IDENTITY)

	# --- 顶层: 当前页传闻 ---
	var rumor: Dictionary = rumors[_rumor_page - 1]
	var rot_deg: float = 2.0
	var cx: float = note_x + NOTE_W / 2.0
	var cy: float = note_base_y + NOTE_H / 2.0

	var xf: Transform2D = Transform2D()
	xf = xf.translated(-Vector2(cx, cy))
	xf = xf.rotated(deg_to_rad(rot_deg))
	xf = xf.translated(Vector2(cx, cy))
	draw_set_transform_matrix(xf)

	# 阴影
	draw_rect(Rect2(note_x + 2, note_base_y + 2, NOTE_W, NOTE_H),
		Color(0.31, 0.235, 0.157, 0.1))

	# 底色
	var note_color: Color
	if rumor.get("is_safe", false):
		note_color = Color(0.894, 0.949, 0.894, 0.94)
	else:
		note_color = Color(0.973, 0.91, 0.855, 0.94)
	draw_rect(Rect2(note_x, note_base_y, NOTE_W, NOTE_H), note_color)

	# 边框
	draw_rect(Rect2(note_x, note_base_y, NOTE_W, NOTE_H),
		Color(0.706, 0.647, 0.549, 0.27), false, 0.8)

	# 胶带
	draw_rect(Rect2(cx - 16, note_base_y - 3, 32, 7),
		Color(0.824, 0.804, 0.745, 0.31))

	# 图标
	var icon_str: String = rumor.get("icon", "📋")
	draw_string(font, Vector2(cx - 6, note_base_y + 16), icon_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, t.text_primary)

	# 安全/危险
	var safe_text: String
	var safe_color: Color
	if rumor.get("is_safe", false):
		safe_text = "✓ 安全"
		safe_color = t.safe
	else:
		safe_text = "⚠ 危险"
		safe_color = t.danger
	var safe_w: float = font.get_string_size(safe_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, Vector2(cx - safe_w / 2.0, note_base_y + 30), safe_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, safe_color)

	# 传闻文字
	var rumor_text: String = rumor.get("text", "")
	var text_w: float = font.get_string_size(rumor_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	draw_string(font, Vector2(cx - text_w / 2.0, note_base_y + 42), rumor_text,
		HORIZONTAL_ALIGNMENT_LEFT, NOTE_W - 4, 7, Color(t.text_secondary, 0.71))

	# 多条时: 翻页指示器
	if total > 1:
		var page_text: String = "▶ %d/%d" % [_rumor_page, total]
		var pw2: float = font.get_string_size(page_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		draw_string(font, Vector2(cx - pw2 / 2.0, note_base_y + NOTE_H + 10), page_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(t.text_secondary, 0.59))

	draw_set_transform_matrix(Transform2D.IDENTITY)

# ---------------------------------------------------------------------------
# 道具工具栏 (纹理图标)
# ---------------------------------------------------------------------------
func _draw_toolbar(px: float, py: float, pw: float, font: Font, t) -> void:
	var consumables: Array = _get_consumable_entries()
	if consumables.is_empty():
		return

	var toolbar_y: float = _get_toolbar_y(py)

	# 虚线分隔
	var dash_x: float = px + SPINE_W + PAGE_PAD
	var dash_end: float = px + pw - PAGE_PAD
	var dash_y: float = toolbar_y + 2
	var dx: float = dash_x
	while dx < dash_end:
		draw_line(Vector2(dx, dash_y),
			Vector2(minf(dx + 3, dash_end), dash_y),
			Color(t.notebook_border, 0.24), 0.5)
		dx += 7

	# "🎒 道具" 小标签
	draw_string(font, Vector2(dash_x, dash_y + 10), "🎒 道具",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(t.text_secondary, 0.47))

	# 图标列表
	var total: int = consumables.size()
	for idx in range(total):
		var entry: Dictionary = consumables[idx]
		var ir: Rect2 = _get_toolbar_item_rect(px, py, pw, idx, total)
		var icon_cx: float = ir.position.x + ir.size.x / 2.0
		var icon_cy: float = ir.position.y + ir.size.y / 2.0
		var is_hovered: bool = (_hover_toolbar == entry["key"])

		# hover 底色
		if is_hovered:
			draw_rect(Rect2(ir.position.x - 2, ir.position.y - 2,
				ir.size.x + 4, ir.size.y + 4),
				Color(0.294, 0.639, 0.89, 0.12))

		# 图标背景圆
		var bg_alpha: float = 0.2 if is_hovered else 0.12
		draw_circle(Vector2(icon_cx, icon_cy), ir.size.x / 2.0,
			Color(t.notebook_border, bg_alpha))

		# 纹理图标 (优先) or emoji fallback
		var icon_key: String = entry["key"]
		var tex: Texture2D = ItemIcons.get_texture(icon_key)
		if tex:
			var tex_size: float = ir.size.x - 4
			var tex_rect: Rect2 = Rect2(icon_cx - tex_size / 2, icon_cy - tex_size / 2,
				tex_size, tex_size)
			draw_texture_rect(tex, tex_rect, false)
		else:
			var info: Dictionary = entry["info"]
			var icon_str: String = info.get("icon", "?")
			draw_string(font, Vector2(icon_cx - 7, icon_cy + 5), icon_str,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, t.text_primary)

		# 数量角标
		var count: int = entry["count"]
		if count > 1:
			var badge_pos: Vector2 = Vector2(ir.position.x + ir.size.x - 1, ir.position.y + 2)
			draw_circle(badge_pos, 5.0, Color(t.info, 0.78))
			draw_string(font, Vector2(badge_pos.x - 3, badge_pos.y + 3), str(count),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color.WHITE)

		# hover 提示气泡
		if is_hovered:
			var info: Dictionary = entry["info"]
			var label: String = info.get("name", "")
			var effect: Dictionary = info.get("effect", {})
			var parts: Array = []
			var res_names: Dictionary = { "san": "理智", "order": "秩序", "film": "胶卷" }
			if icon_key == "exorcism":
				parts.append("驱除当前怪物")
			elif icon_key == "shield":
				parts.append("抵挡一次伤害")
			elif icon_key == "mapReveal":
				parts.append("揭示周围")
			else:
				for ek in effect:
					var rn: String = res_names.get(ek, ek)
					var ev: int = effect[ek]
					var sign: String = "+" if ev > 0 else ""
					parts.append(rn + sign + str(ev))
			var tip: String = label + ": " + ", ".join(parts)
			var tip_w: float = font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			var tip_x: float = icon_cx
			var tip_y: float = ir.position.y - 4
			var pad_x: float = 6.0
			var pad_y: float = 3.0
			var bx: float = tip_x - tip_w / 2 - pad_x
			var by: float = tip_y - 9 - pad_y
			var bw: float = tip_w + pad_x * 2
			var bh: float = 10 + pad_y * 2
			# 阴影
			draw_rect(Rect2(bx + 1, by + 1, bw, bh), Color(t.notebook_border, 0.16))
			# 填充
			draw_rect(Rect2(bx, by, bw, bh), Color(t.notebook_paper, 0.96))
			# 边框
			draw_rect(Rect2(bx, by, bw, bh), Color(t.notebook_border, 0.47), false, 0.5)
			# 文字
			draw_string(font, Vector2(bx + pad_x, by + bh - pad_y), tip,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, t.text_primary)

# ---------------------------------------------------------------------------
# "结束今天" 按钮 (手写风)
# ---------------------------------------------------------------------------
func _draw_end_day_btn(px: float, py: float, pw: float, font: Font, t) -> void:
	var btn_rect: Rect2 = _get_end_day_btn_rect(px, py, pw)
	var bx: float = btn_rect.position.x
	var by: float = btn_rect.position.y
	var bw: float = btn_rect.size.x
	var bh: float = btn_rect.size.y
	var center_y: float = by + bh / 2.0

	# hover 底色
	if _hover_end_day:
		draw_rect(Rect2(bx, by, bw, bh), Color(0.706, 0.47, 0.314, 0.1))

	# 虚线分隔
	var dash_x: float = bx + 4
	var dash_end: float = bx + bw - 4
	var dash_y: float = by - 1
	var dx: float = dash_x
	while dx < dash_end:
		draw_line(Vector2(dx, dash_y),
			Vector2(minf(dx + 4, dash_end), dash_y),
			Color(t.notebook_border, 0.31), 0.6)
		dx += 8

	# 手写文字
	var alpha: float = 0.94 if _hover_end_day else 0.63
	var text: String = "☾ 结束今天，回家休息"
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(bx + (bw - tw) / 2, center_y + 4), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.549, 0.353, 0.196, alpha))

# ---------------------------------------------------------------------------
# 重置
# ---------------------------------------------------------------------------
func reset() -> void:
	_visible_state = false
	_expanded = false
	_showcasing = false
	_alpha = 0.0
	_hover_index = 0
	_hover_end_day = false
	_hover_toolbar = ""
	_rumor_page = 1
