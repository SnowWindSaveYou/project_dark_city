## ClueLog - 线索日志弹窗
## 显示已收集的线索，按分类归组，笔记本翻页风格
## 从 StoryManager 读取数据，纯 _draw() 渲染
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal closed

# ---------------------------------------------------------------------------
# 常量 — 布局
# ---------------------------------------------------------------------------
const PANEL_W: int = 300
const PANEL_H: int = 360
const CORNER_R: float = 6.0
const PAD: int = 14
const TITLE_H: int = 32
const TAB_BAR_H: int = 26
const ITEM_H: int = 48
const ICON_SIZE: int = 20
const CLOSE_SIZE: int = 20

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _open: bool = false
var _alpha: float = 0.0
var _scale: float = 0.8
var _active_category: int = 0   # 当前分类索引
var _categories: Array = []     # [String] 分类列表
var _clue_data: Array = []      # 当前分类下的线索列表
var _scroll_offset: int = 0     # 滚动偏移 (条目数)
var _hover_close: bool = false
var _hover_tab: int = -1        # hover 的分类 tab (-1=无)
var _hover_item: int = -1       # hover 的线索条目 (-1=无)

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

func _has_point(point: Vector2) -> bool:
	if not _open or _alpha < 0.1:
		return false
	# 遮罩层全屏拦截
	return true

# ---------------------------------------------------------------------------
# 打开 / 关闭
# ---------------------------------------------------------------------------

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_alpha = 0.0
	_scale = 0.8
	_scroll_offset = 0
	_refresh_data()
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(self, "_alpha", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_scale", 1.0, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func close() -> void:
	if not _open:
		return
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(self, "_alpha", 0.0, 0.15)
	tw.tween_property(self, "_scale", 0.85, 0.15)
	tw.chain().tween_callback(func():
		_open = false
		visible = false
		closed.emit()
	)

func is_open() -> bool:
	return _open

# ---------------------------------------------------------------------------
# 数据刷新
# ---------------------------------------------------------------------------

func _refresh_data() -> void:
	_categories = StoryManager.get_clue_categories()
	if _categories.is_empty():
		_categories = ["暂无"]
	_active_category = clampi(_active_category, 0, _categories.size() - 1)
	_refresh_category_items()

func _refresh_category_items() -> void:
	if _active_category < 0 or _active_category >= _categories.size():
		_clue_data = []
		return
	var cat: String = _categories[_active_category]
	if cat == "暂无":
		_clue_data = []
	else:
		_clue_data = StoryManager.get_clues_by_category(cat)
	_scroll_offset = 0

# ---------------------------------------------------------------------------
# 布局辅助
# ---------------------------------------------------------------------------

func _get_panel_rect() -> Rect2:
	var vw: float = get_viewport_rect().size.x
	var vh: float = get_viewport_rect().size.y
	var pw: float = minf(PANEL_W, vw - 40)
	var ph: float = minf(PANEL_H, vh - 80)
	var px: float = (vw - pw) / 2.0
	var py: float = (vh - ph) / 2.0
	return Rect2(px, py, pw, ph)

func _get_close_rect(pr: Rect2) -> Rect2:
	return Rect2(pr.position.x + pr.size.x - CLOSE_SIZE - 6,
		pr.position.y + 6, CLOSE_SIZE, CLOSE_SIZE)

func _get_tab_rect(pr: Rect2, idx: int, total: int) -> Rect2:
	var content_w: float = pr.size.x - PAD * 2
	var tab_w: float = minf(content_w / total, 72)
	var tx: float = pr.position.x + PAD + idx * tab_w
	var ty: float = pr.position.y + TITLE_H
	return Rect2(tx, ty, tab_w, TAB_BAR_H)

func _get_item_rect(pr: Rect2, idx: int) -> Rect2:
	var content_y: float = pr.position.y + TITLE_H + TAB_BAR_H + 4
	var iy: float = content_y + idx * ITEM_H
	return Rect2(pr.position.x + PAD, iy,
		pr.size.x - PAD * 2, ITEM_H)

func _max_visible_items(pr: Rect2) -> int:
	var available: float = pr.size.y - TITLE_H - TAB_BAR_H - 8
	return maxi(1, int(available / ITEM_H))

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not _open or _alpha < 0.1:
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed:
		return

	if mb.button_index == MOUSE_BUTTON_LEFT:
		var pr: Rect2 = _get_panel_rect()
		var pos: Vector2 = mb.position

		# 关闭按钮
		if _get_close_rect(pr).has_point(pos):
			close()
			accept_event()
			return

		# 点击面板外 → 关闭
		if not pr.has_point(pos):
			close()
			accept_event()
			return

		# 分类 Tab
		for i in range(_categories.size()):
			if _get_tab_rect(pr, i, _categories.size()).has_point(pos):
				if i != _active_category:
					_active_category = i
					_refresh_category_items()
				accept_event()
				return

		accept_event()

	# 滚轮翻页
	elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll_offset = maxi(0, _scroll_offset - 1)
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var pr: Rect2 = _get_panel_rect()
		var max_scroll: int = maxi(0, _clue_data.size() - _max_visible_items(pr))
		_scroll_offset = mini(_scroll_offset + 1, max_scroll)
		accept_event()

func _input(event: InputEvent) -> void:
	if not _open or _alpha < 0.1:
		return
	if event is InputEventMouseMotion:
		_update_hover(event.position)

func _update_hover(pos: Vector2) -> void:
	_hover_close = false
	_hover_tab = -1
	_hover_item = -1
	var pr: Rect2 = _get_panel_rect()

	if _get_close_rect(pr).has_point(pos):
		_hover_close = true
		return

	for i in range(_categories.size()):
		if _get_tab_rect(pr, i, _categories.size()).has_point(pos):
			_hover_tab = i
			return

	var max_vis: int = _max_visible_items(pr)
	for i in range(max_vis):
		var data_idx: int = i + _scroll_offset
		if data_idx >= _clue_data.size():
			break
		if _get_item_rect(pr, i).has_point(pos):
			_hover_item = data_idx
			return

# ---------------------------------------------------------------------------
# 更新 & 渲染
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _open and _alpha > 0.01:
		queue_redraw()

func _draw() -> void:
	if not _open or _alpha < 0.05:
		return

	var font: Font = ThemeDB.fallback_font
	var pr: Rect2 = _get_panel_rect()
	var px: float = pr.position.x
	var py: float = pr.position.y
	var pw: float = pr.size.x
	var ph: float = pr.size.y

	modulate.a = _alpha

	# 全屏遮罩
	var vw: float = get_viewport_rect().size.x
	var vh: float = get_viewport_rect().size.y
	draw_rect(Rect2(0, 0, vw, vh), Color(0.0, 0.0, 0.0, 0.4 * _alpha))

	# 缩放变换
	var cx: float = px + pw / 2.0
	var cy: float = py + ph / 2.0
	var xf: Transform2D = Transform2D()
	xf = xf.translated(-Vector2(cx, cy))
	xf = xf.scaled(Vector2(_scale, _scale))
	xf = xf.translated(Vector2(cx, cy))
	draw_set_transform_matrix(xf)

	# --- 纸张阴影 ---
	draw_rect(Rect2(px + 3, py + 4, pw, ph),
		Color(0.15, 0.10, 0.05, 0.25))

	# --- 纸张主体 ---
	var paper_color: Color = Color(0.96, 0.94, 0.89, 0.98)
	draw_rect(Rect2(px, py, pw, ph), paper_color)

	# --- 纸张边框 ---
	draw_rect(Rect2(px, py, pw, ph),
		Color(0.65, 0.55, 0.42, 0.55), false, 1.0)

	# === 标题栏 ===
	_draw_title(px, py, pw, font)

	# === 关闭按钮 ===
	_draw_close_btn(pr, font)

	# === 分类 Tab ===
	_draw_tabs(pr, font)

	# === 线索列表 ===
	_draw_clue_list(pr, font)

	# === 空状态 ===
	if _clue_data.is_empty():
		_draw_empty_state(pr, font)

	draw_set_transform_matrix(Transform2D.IDENTITY)
	modulate.a = 1.0

# ---------------------------------------------------------------------------
# 子绘制
# ---------------------------------------------------------------------------

func _draw_title(px: float, py: float, pw: float, font: Font) -> void:
	# 标题底色
	draw_rect(Rect2(px, py, pw, TITLE_H),
		Color(0.55, 0.42, 0.30, 0.12))

	# 标题文字
	var title: String = "🔍 线索日志"
	var clue_count: int = StoryManager.get_clue_count()
	var total_count: int = StoryManager._clue_defs.size()
	var subtitle: String = " (%d/%d)" % [clue_count, total_count]
	var full_title: String = title + subtitle
	var tw: float = font.get_string_size(full_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2(px + (pw - tw) / 2.0, py + 22), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.25, 0.18, 0.12, 0.86))
	draw_string(font, Vector2(px + (pw - tw) / 2.0 + font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, py + 22),
		subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.38, 0.30, 0.63))

	# 底部分隔线
	draw_line(Vector2(px + PAD, py + TITLE_H - 1),
		Vector2(px + pw - PAD, py + TITLE_H - 1),
		Color(0.65, 0.55, 0.42, 0.27), 0.8)

func _draw_close_btn(pr: Rect2, font: Font) -> void:
	var cr: Rect2 = _get_close_rect(pr)
	var alpha: float = 0.86 if _hover_close else 0.47
	draw_string(font, Vector2(cr.position.x + 3, cr.position.y + 15), "✕",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 0.3, 0.2, alpha))

func _draw_tabs(pr: Rect2, font: Font) -> void:
	var total: int = _categories.size()
	if total == 0:
		return

	var tab_y: float = pr.position.y + TITLE_H

	for i in range(total):
		var tr: Rect2 = _get_tab_rect(pr, i, total)
		var cat: String = _categories[i]
		var is_active: bool = (i == _active_category)
		var is_hovered: bool = (i == _hover_tab)

		# Tab 底色
		if is_active:
			draw_rect(tr, Color(0.70, 0.55, 0.35, 0.18))
			# 底部高亮线
			draw_line(Vector2(tr.position.x + 4, tr.position.y + tr.size.y - 1),
				Vector2(tr.position.x + tr.size.x - 4, tr.position.y + tr.size.y - 1),
				Color(0.70, 0.50, 0.30, 0.63), 1.5)
		elif is_hovered:
			draw_rect(tr, Color(0.65, 0.55, 0.42, 0.08))

		# Tab 文字
		var label: String = cat
		var label_color: Color
		if is_active:
			label_color = Color(0.30, 0.20, 0.12, 0.86)
		else:
			label_color = Color(0.45, 0.38, 0.30, 0.55)
		var lw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font,
			Vector2(tr.position.x + (tr.size.x - lw) / 2.0,
				tr.position.y + tr.size.y / 2.0 + 4),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, label_color)

	# Tab 栏底线
	draw_line(
		Vector2(pr.position.x + PAD, tab_y + TAB_BAR_H),
		Vector2(pr.position.x + pr.size.x - PAD, tab_y + TAB_BAR_H),
		Color(0.65, 0.55, 0.42, 0.18), 0.5)

func _draw_clue_list(pr: Rect2, font: Font) -> void:
	if _clue_data.is_empty():
		return

	var max_vis: int = _max_visible_items(pr)

	for i in range(max_vis):
		var data_idx: int = i + _scroll_offset
		if data_idx >= _clue_data.size():
			break
		var entry: Dictionary = _clue_data[data_idx]
		var info: Dictionary = entry.get("info", {})
		var ir: Rect2 = _get_item_rect(pr, i)
		var ix: float = ir.position.x
		var iy: float = ir.position.y
		var iw: float = ir.size.x
		var ih: float = ir.size.y
		var is_hovered: bool = (data_idx == _hover_item)

		# Hover 底色
		if is_hovered:
			draw_rect(Rect2(ix - 2, iy + 1, iw + 4, ih - 2),
				Color(0.70, 0.55, 0.35, 0.08))

		# 图标
		var icon_str: String = info.get("icon", "📋")
		draw_string(font, Vector2(ix + 2, iy + 18), icon_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.30, 0.22, 0.14, 0.86))

		# 线索名称
		var clue_name: String = info.get("name", entry.get("id", "???"))
		draw_string(font, Vector2(ix + ICON_SIZE + 8, iy + 16), clue_name,
			HORIZONTAL_ALIGNMENT_LEFT, iw - ICON_SIZE - 12, 12,
			Color(0.25, 0.18, 0.12, 0.86))

		# 线索描述
		var desc: String = info.get("desc", "")
		if desc != "":
			draw_string(font, Vector2(ix + ICON_SIZE + 8, iy + 32), desc,
				HORIZONTAL_ALIGNMENT_LEFT, iw - ICON_SIZE - 12, 9,
				Color(0.45, 0.38, 0.30, 0.55))

		# 底部分隔线
		draw_line(Vector2(ix + ICON_SIZE + 6, iy + ih - 1),
			Vector2(ix + iw, iy + ih - 1),
			Color(0.65, 0.55, 0.42, 0.12), 0.5)

	# 滚动指示
	if _clue_data.size() > max_vis:
		var indicator: String = "▲▼ %d/%d" % [_scroll_offset + 1,
			_clue_data.size() - max_vis + 1]
		var ind_w: float = font.get_string_size(indicator, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(font,
			Vector2(pr.position.x + pr.size.x - PAD - ind_w,
				pr.position.y + pr.size.y - 8),
			indicator, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color(0.45, 0.38, 0.30, 0.39))

func _draw_empty_state(pr: Rect2, font: Font) -> void:
	var cx: float = pr.position.x + pr.size.x / 2.0
	var cy: float = pr.position.y + TITLE_H + TAB_BAR_H + (pr.size.y - TITLE_H - TAB_BAR_H) / 2.0

	draw_string(font, Vector2(cx - 14, cy - 8), "📭",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28,
		Color(0.55, 0.45, 0.35, 0.31))

	var empty_text: String = "暂未收集到线索"
	var tw: float = font.get_string_size(empty_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, Vector2(cx - tw / 2.0, cy + 20), empty_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.55, 0.45, 0.35, 0.39))

# ---------------------------------------------------------------------------
# 重置
# ---------------------------------------------------------------------------
func reset() -> void:
	_open = false
	visible = false
	_alpha = 0.0
	_active_category = 0
	_scroll_offset = 0
