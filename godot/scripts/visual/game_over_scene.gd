## GameOver — 物语风格结算画面
## 视觉语言对齐主菜单：零圆角、极细边框、_draw() 线条生长、数字滚动
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal return_to_menu_requested

# ---------------------------------------------------------------------------
# 常量（与 main_menu_scene.gd 保持一致）
# ---------------------------------------------------------------------------
const MAIN_MENU_PATH: String = "res://scenes/screens/main_menu.tscn"

## 深色遮罩底色（暗面世界氛围）
const C_OVERLAY_VIC:  Color = Color(0.04, 0.03, 0.10, 0.90)
const C_OVERLAY_DEF:  Color = Color(0.08, 0.02, 0.04, 0.93)

## 深色背景上的文字（反转为浅色系）
const C_TITLE:    Color = Color(0.93, 0.91, 0.97, 1.00)   # 近白，微紫
const C_SUBTITLE: Color = Color(0.72, 0.68, 0.80, 0.82)   # 浅紫灰
const C_COORD:    Color = Color(0.52, 0.50, 0.62, 0.60)   # 暗淡小字

## 细线（深色背景上稍亮）
const C_LINE: Color = Color(0.55, 0.52, 0.68, 0.28)

## 按钮（深色背景上：主按钮=浅色填充深字，次级=半透明边框浅字）
const C_BTN_PRIMARY_BG:    Color = Color(0.88, 0.86, 0.96, 0.96)  # 近白紫
const C_BTN_PRIMARY_HOVER: Color = Color(1.00, 1.00, 1.00, 1.00)  # 纯白
const C_BTN_PRIMARY_TEXT:  Color = Color(0.08, 0.06, 0.16, 1.00)  # 深色文字
const C_BTN_SEC_BG:        Color = Color(0.0,  0.0,  0.0,  0.0)
const C_BTN_SEC_BORDER:    Color = Color(0.60, 0.56, 0.75, 0.45)
const C_BTN_SEC_HOVER_BG:  Color = Color(0.55, 0.50, 0.72, 0.12)

# 统计项定义
const STAT_DEFS: Array = [
	{ "key": "days_survived",  "icon": "📅", "label": "存活天数" },
	{ "key": "cards_revealed", "icon": "🃏", "label": "翻开卡牌" },
	{ "key": "monsters_slain", "icon": "👻", "label": "驱除怪物" },
	{ "key": "photos_used",    "icon": "📷", "label": "消耗胶卷" },
]

# ---------------------------------------------------------------------------
# 节点引用
# ---------------------------------------------------------------------------
@onready var _overlay:        ColorRect    = $Overlay
@onready var _draw_layer:     Control      = $DrawLayer
@onready var _ending_id_lbl:  Label        = $ContentBlock/EndingIdRow/EndingIdLabel
@onready var _day_lbl:        Label        = $ContentBlock/EndingIdRow/DayLabel
@onready var _title_label:    Label        = $ContentBlock/TitleLabel
@onready var _subtitle_label: Label        = $ContentBlock/SubtitleLabel
@onready var _stats_row:      HBoxContainer = $ContentBlock/StatsRow
@onready var _progress_row:   HBoxContainer = $ContentBlock/ProgressRow
@onready var _progress_bar:   ProgressBar  = $ContentBlock/ProgressRow/ProgressBar
@onready var _progress_lbl:   Label        = $ContentBlock/ProgressRow/ProgressLabel
@onready var _btn_menu:       Button       = $ContentBlock/ButtonRow/BtnMenu
@onready var _btn_gallery:    Button       = $ContentBlock/ButtonRow/BtnGallery

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
enum Phase { NONE, ENTER, IDLE, EXIT }
var _phase: Phase = Phase.NONE
var _game_time: float = 0.0
var _is_victory: bool = false

## 当前结局配色（供 _draw_layer 使用）
var _accent_color: Color = Color(0.6, 0.8, 1.0)

## 细线生长进度 0→1（两条分隔线）
var _line_progress: float = 0.0
var _line_progress_target: float = 0.0

## 统计数字滚动（同主菜单坐标滚动原理）
## { key: { current: float, target: int, label: Label } }
var _stat_rolls: Dictionary = {}

## 入场各元素可见度（逐步淡入）
var _overlay_alpha:   float = 0.0
var _header_alpha:    float = 0.0
var _title_alpha:     float = 0.0
var _subtitle_alpha:  float = 0.0
var _stats_alpha:     float = 0.0
var _progress_alpha:  float = 0.0
var _btns_alpha:      float = 0.0

## 扫描线（与主菜单一致）
var _scan_y:     float = 0.0
var _scan_alpha: float = 0.0

## 标题逐字可见度（每个字一个 Label）
var _title_chars: Array[Label] = []
var _title_char_alpha: Array[float] = []
## 标题逐字容器（HBoxContainer，需单独清理）
var _title_hbox: HBoxContainer = null

## 统计数据
var _stats: Dictionary = {
	"days_survived": 1, "cards_revealed": 0,
	"monsters_slain": 0, "photos_used": 0,
}

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	visible = false
	set_process(false)
	set_process_input(false)

	_draw_layer.draw.connect(_on_draw_layer_draw)

	# 按钮信号
	_btn_menu.pressed.connect(_on_menu_pressed)
	_btn_menu.mouse_entered.connect(func(): _btn_hover(_btn_menu, true,  true))
	_btn_menu.mouse_exited.connect(func():  _btn_hover(_btn_menu, false, true))
	_btn_gallery.pressed.connect(_on_gallery_pressed)
	_btn_gallery.mouse_entered.connect(func(): _btn_hover(_btn_gallery, true,  false))
	_btn_gallery.mouse_exited.connect(func():  _btn_hover(_btn_gallery, false, false))

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func show_result(is_victory: bool, stats: Dictionary = {}, ending: Dictionary = {}) -> void:
	if _phase != Phase.NONE:
		return
	_phase = Phase.ENTER
	_is_victory = is_victory
	if stats.size() > 0:
		_stats = stats

	visible = true
	set_process(true)
	set_process_input(true)
	_game_time = 0.0

	# 存档
	var ending_id: String = ending.get("id", "")
	SaveManager.record_run(ending_id, stats)

	# 结局展示数据
	var display: Dictionary = {}
	if not ending.is_empty():
		display = EndingSystem.get_ending_display(ending)
		_is_victory = display.get("is_victory", is_victory)

	# 配色
	if not display.is_empty():
		_accent_color = display.get("primary_color", Color(0.6, 0.8, 1.0))
		_overlay.color = display.get("bg_color", Color(0.04, 0.03, 0.10))
	else:
		_accent_color = GameTheme.safe if _is_victory else GameTheme.danger
		_overlay.color = C_OVERLAY_VIC if _is_victory else C_OVERLAY_DEF
	_overlay.color.a = 0.0

	# 结局 ID 行
	var eid_display: String = ending_id.to_upper() if ending_id != "" else "DEFAULT"
	_ending_id_lbl.text = "ENDING · %s" % eid_display
	_ending_id_lbl.add_theme_color_override("font_color", Color(_accent_color, 0.55))
	_day_lbl.text = "DAY %d" % _stats.get("days_survived", 1)
	_day_lbl.add_theme_color_override("font_color", C_COORD)

	# 主标题（逐字拆分）
	var title_text: String
	if not display.is_empty():
		title_text = display.get("title", "未知结局")
	else:
		title_text = "任务完成" if _is_victory else "意识崩溃"
	_title_label.text = title_text  # 保留原 Label 用于布局占位，alpha 始终为 0
	_title_label.modulate.a = 0.0
	_build_title_chars(title_text)

	# 副标题
	if not display.is_empty():
		_subtitle_label.text = display.get("subtitle", "")
	elif _is_victory:
		_subtitle_label.text = "你在暗面都市中幸存了下来。"
	else:
		_subtitle_label.text = "黑暗吞噬了你最后的理智..."
	_subtitle_label.add_theme_color_override("font_color", C_SUBTITLE)

	# 统计滚动初始化
	_build_stat_rolls()

	# 结局进度
	var total_endings: int = StoryManager._endings.size()
	var unlocked_count: int = SaveManager.unlocked_endings.size()
	_progress_bar.min_value = 0
	_progress_bar.max_value = total_endings
	_progress_bar.value = unlocked_count
	_progress_lbl.text = "已解锁结局  %d / %d" % [unlocked_count, total_endings]
	_progress_lbl.add_theme_color_override("font_color", C_COORD)

	# 按钮样式（零圆角）
	_apply_btn_style_primary(_btn_menu)
	_apply_btn_style_secondary(_btn_gallery)

	# 重置所有透明度
	_reset_alphas()
	_line_progress = 0.0
	_line_progress_target = 0.0
	_scan_y = 0.0
	_scan_alpha = 0.0

	# 启动入场序列
	_start_enter_sequence()

func dismiss() -> void:
	if _phase == Phase.EXIT or _phase == Phase.NONE:
		return
	_phase = Phase.EXIT
	_line_progress_target = 0.0

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "color:a", 0.0, 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	if _title_hbox != null:
		tw.tween_property(_title_hbox, "modulate:a", 0.0, 0.25).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(_on_dismiss_done)

func _on_dismiss_done() -> void:
	if _title_hbox != null:
		_title_hbox.queue_free()
		_title_hbox = null
	_title_chars.clear()
	_title_char_alpha.clear()
	_phase = Phase.NONE
	_scan_alpha = 0.0
	visible = false
	set_process(false)
	set_process_input(false)

func is_active() -> bool:
	return _phase != Phase.NONE

# ---------------------------------------------------------------------------
# 入场序列
# ---------------------------------------------------------------------------

func _start_enter_sequence() -> void:
	# 0.0s: 遮罩淡入
	var t_overlay: Tween = create_tween()
	t_overlay.tween_method(func(v: float): _overlay_alpha = v; _overlay.color.a = v,
		0.0, 0.85, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 0.25s: 细线从左生长到右
	var t_line: Tween = create_tween()
	t_line.tween_interval(0.25)
	t_line.tween_method(func(v: float): _line_progress = v; _draw_layer.queue_redraw(),
		0.0, 1.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# 0.4s: 标题 ID 行淡入
	var t_hdr: Tween = create_tween()
	t_hdr.tween_interval(0.4)
	t_hdr.tween_method(func(v: float): _header_alpha = v; _set_row_alpha($ContentBlock/EndingIdRow, v),
		0.0, 1.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 0.55s: 标题逐字瞬切
	var t_title: Tween = create_tween()
	t_title.tween_interval(0.55)
	t_title.tween_callback(_begin_title_reveal)

	# 0.85s: 副标题
	var t_sub: Tween = create_tween()
	t_sub.tween_interval(0.85)
	t_sub.tween_method(func(v: float): _subtitle_alpha = v; _subtitle_label.modulate.a = v,
		0.0, 1.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 1.0s: 统计数字滚动开始
	var t_stats: Tween = create_tween()
	t_stats.tween_interval(1.0)
	t_stats.tween_method(func(v: float): _stats_alpha = v; _stats_row.modulate.a = v,
		0.0, 1.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 1.2s: 进度条
	var t_prog: Tween = create_tween()
	t_prog.tween_interval(1.2)
	t_prog.tween_method(func(v: float): _progress_alpha = v; _progress_row.modulate.a = v,
		0.0, 1.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 1.45s: 按钮淡入 + 扫描线激活
	var t_btns: Tween = create_tween()
	t_btns.tween_interval(1.45)
	t_btns.tween_method(func(v: float): _btns_alpha = v; $ContentBlock/ButtonRow.modulate.a = v,
		0.0, 1.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t_btns.tween_callback(func():
		_phase = Phase.IDLE
		_scan_alpha = 0.0)

# ---------------------------------------------------------------------------
# 标题逐字瞬切（与主菜单 _start_char_reveal 同逻辑）
# ---------------------------------------------------------------------------

func _build_title_chars(text: String) -> void:
	# 清理旧的
	if _title_hbox != null:
		_title_hbox.queue_free()
		_title_hbox = null
	_title_chars.clear()
	_title_char_alpha.clear()

	# 在 TitleLabel 同位置叠加逐字 Label
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 2)
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_label.add_sibling(hbox)
	_title_hbox = hbox

	for ch in text:
		var lbl: Label = Label.new()
		lbl.text = ch
		lbl.add_theme_font_size_override("font_size", 72)
		lbl.add_theme_color_override("font_color", _accent_color)
		lbl.modulate.a = 0.0
		hbox.add_child(lbl)
		_title_chars.append(lbl)
		_title_char_alpha.append(0.0)

func _begin_title_reveal() -> void:
	# 逐字延迟 0.06s 瞬切（与主菜单 _start_char_reveal 一致）
	for i in range(_title_chars.size()):
		var lbl: Label = _title_chars[i]
		var t: Tween = create_tween()
		t.tween_interval(i * 0.06)
		t.tween_callback(func(): lbl.modulate.a = 1.0)

# ---------------------------------------------------------------------------
# 统计数字滚动
# ---------------------------------------------------------------------------

func _build_stat_rolls() -> void:
	_stat_rolls.clear()
	# 清理旧的统计子节点
	for ch in _stats_row.get_children():
		ch.queue_free()

	for i in range(STAT_DEFS.size()):
		var def: Dictionary = STAT_DEFS[i]
		var target: int = _stats.get(def["key"], 0)

		# 每项：VBoxContainer（图标+数值+标签）
		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 4)
		_stats_row.add_child(vbox)

		var num_lbl: Label = Label.new()
		num_lbl.text = "0"
		num_lbl.add_theme_font_size_override("font_size", 52)
		num_lbl.add_theme_color_override("font_color", _accent_color)
		num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(num_lbl)

		var name_lbl: Label = Label.new()
		name_lbl.text = "%s %s" % [def["icon"], def["label"]]
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", C_COORD)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(name_lbl)

		_stat_rolls[def["key"]] = {
			"current": 0.0,
			"target": target,
			"label": num_lbl,
		}

		# 竖向分隔线（最后一项不加）
		if i < STAT_DEFS.size() - 1:
			var sep: Control = Control.new()
			sep.custom_minimum_size = Vector2(1, 40)
			sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sep.draw.connect(func():
				sep.draw_line(Vector2(0, 0), Vector2(0, 40), C_LINE, 1.0))
			_stats_row.add_child(sep)

# ---------------------------------------------------------------------------
# _process: 数字滚动 + 扫描线
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	_game_time += dt
	var needs_redraw: bool = false

	# 统计数字滚动
	if _stats_alpha > 0.05:
		for key in _stat_rolls:
			var roll: Dictionary = _stat_rolls[key]
			if roll["current"] < float(roll["target"]):
				var speed: float = maxf(float(roll["target"]) * 3.5, 8.0)
				roll["current"] = minf(roll["current"] + speed * dt, float(roll["target"]))
				roll["label"].text = str(int(roll["current"]))
				needs_redraw = true

	# 扫描线（IDLE 阶段常驻）
	if _phase == Phase.IDLE:
		_scan_alpha = minf(_scan_alpha + dt * 0.6, 0.45)
		_scan_y = fmod(_scan_y + dt * 0.18, 1.0)
		needs_redraw = true

	if needs_redraw:
		_draw_layer.queue_redraw()

# ---------------------------------------------------------------------------
# 绘制：分隔线生长 + 扫描线
# ---------------------------------------------------------------------------

func _on_draw_layer_draw() -> void:
	if _phase == Phase.NONE:
		return

	var w: float = _draw_layer.size.x
	var h: float = _draw_layer.size.y

	# --- 上分隔线（标题下方约 45%）---
	var line1_y: float = h * 0.455
	var line1_w: float = w * 0.72 * _line_progress
	var line1_x: float = (w - w * 0.72) * 0.5
	_draw_layer.draw_line(
		Vector2(line1_x, line1_y),
		Vector2(line1_x + line1_w, line1_y),
		C_LINE, 1.0)

	# --- 下分隔线（统计下方约 72%）---
	var line2_y: float = h * 0.725
	var line2_progress: float = maxf(0.0, (_line_progress - 0.3) / 0.7)
	var line2_w: float = w * 0.72 * line2_progress
	var line2_x: float = (w - w * 0.72) * 0.5
	_draw_layer.draw_line(
		Vector2(line2_x, line2_y),
		Vector2(line2_x + line2_w, line2_y),
		C_LINE, 1.0)

	# --- 扫描线（遮罩上方滚动）---
	if _scan_alpha > 0.01:
		var scan_y_px: float = _scan_y * h
		var scan_col: Color = Color(_accent_color.r, _accent_color.g, _accent_color.b, _scan_alpha * 0.35)
		_draw_layer.draw_line(Vector2(0, scan_y_px), Vector2(w, scan_y_px), scan_col, 1.5)
		# 扫描线光晕（上下各1px淡化）
		var glow_col: Color = Color(_accent_color.r, _accent_color.g, _accent_color.b, _scan_alpha * 0.12)
		_draw_layer.draw_line(Vector2(0, scan_y_px - 2), Vector2(w, scan_y_px - 2), glow_col, 1.0)
		_draw_layer.draw_line(Vector2(0, scan_y_px + 2), Vector2(w, scan_y_px + 2), glow_col, 1.0)

# ---------------------------------------------------------------------------
# 按钮样式（零圆角，与主菜单一致）
# ---------------------------------------------------------------------------

func _apply_btn_style_primary(btn: Button) -> void:
	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = C_BTN_PRIMARY_BG
	n.set_corner_radius_all(0)
	n.set_border_width_all(0)
	n.content_margin_left = 36.0; n.content_margin_right = 36.0
	n.content_margin_top  = 18.0; n.content_margin_bottom = 18.0
	btn.add_theme_stylebox_override("normal", n)
	var hv: StyleBoxFlat = n.duplicate()
	hv.bg_color = C_BTN_PRIMARY_HOVER
	btn.add_theme_stylebox_override("hover", hv)
	var pr: StyleBoxFlat = n.duplicate()
	pr.bg_color = Color(C_BTN_PRIMARY_BG, 0.75)
	btn.add_theme_stylebox_override("pressed", pr)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", C_BTN_PRIMARY_TEXT)
	btn.add_theme_color_override("font_hover_color", C_BTN_PRIMARY_TEXT)
	btn.add_theme_color_override("font_pressed_color", C_BTN_PRIMARY_TEXT)

func _apply_btn_style_secondary(btn: Button) -> void:
	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = C_BTN_SEC_BG
	n.border_color = C_BTN_SEC_BORDER
	n.set_border_width_all(1)
	n.set_corner_radius_all(0)
	n.content_margin_left = 36.0; n.content_margin_right = 36.0
	n.content_margin_top  = 18.0; n.content_margin_bottom = 18.0
	btn.add_theme_stylebox_override("normal", n)
	var hv: StyleBoxFlat = n.duplicate()
	hv.bg_color = C_BTN_SEC_HOVER_BG
	hv.border_color = Color(_accent_color, 0.70)
	btn.add_theme_stylebox_override("hover", hv)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", C_SUBTITLE)
	btn.add_theme_color_override("font_hover_color", Color(_accent_color, 0.95))

func _btn_hover(btn: Button, enter: bool, is_primary: bool) -> void:
	if is_primary:
		var tw: Tween = btn.create_tween()
		var target: Color = C_BTN_PRIMARY_HOVER if enter else C_BTN_PRIMARY_BG
		var sb: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
		if sb:
			tw.tween_method(func(c: Color): sb.bg_color = c; btn.add_theme_stylebox_override("normal", sb),
				sb.bg_color, target, 0.1)

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _phase == Phase.NONE:
		return
	if event is InputEventKey and event.pressed:
		if _phase == Phase.IDLE:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				_goto_menu()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# 按钮回调
# ---------------------------------------------------------------------------

func _on_menu_pressed() -> void:
	if _phase == Phase.IDLE:
		_goto_menu()

func _on_gallery_pressed() -> void:
	if _phase == Phase.IDLE:
		# 先执行退场动画，再跳转主菜单（主菜单内含画廊入口）
		_goto_menu()

func _goto_menu() -> void:
	if _phase != Phase.IDLE:
		return
	_phase = Phase.EXIT
	return_to_menu_requested.emit()

	var tw: Tween = create_tween()
	tw.tween_property(_overlay, "color:a", 0.0, 0.4)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_method(
		func(v: float): _line_progress = v; _draw_layer.queue_redraw(),
		_line_progress, 0.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		get_tree().change_scene_to_file(MAIN_MENU_PATH))

# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _reset_alphas() -> void:
	_overlay_alpha  = 0.0
	_header_alpha   = 0.0
	_title_alpha    = 0.0
	_subtitle_alpha = 0.0
	_stats_alpha    = 0.0
	_progress_alpha = 0.0
	_btns_alpha     = 0.0
	_overlay.color.a = 0.0
	_set_row_alpha($ContentBlock/EndingIdRow, 0.0)
	_subtitle_label.modulate.a = 0.0
	_stats_row.modulate.a = 0.0
	_progress_row.modulate.a = 0.0
	$ContentBlock/ButtonRow.modulate.a = 0.0

func _set_row_alpha(node: Control, alpha: float) -> void:
	node.modulate.a = alpha
