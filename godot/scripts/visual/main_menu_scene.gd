## MainMenuScene — 独立主菜单场景
##
## 作为游戏入口场景 (project.godot main_scene)。
## 包含: 开始游戏、设置、退出三个操作。
## 设置面板以 overlay 形式叠加显示。
## 游戏开始时通过 change_scene_to_file 切换到 main.tscn。
extends Control

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const FLOAT_CARD_COUNT: int = 14
const CARD_ICONS: Array = ["🏠", "👻", "⚡", "💎", "📖", "🔍", "🛒", "📸", "⛪", "🌙", "🔮", "🎴"]

# ---------------------------------------------------------------------------
# 子节点
# ---------------------------------------------------------------------------
var _floating_cards: Control = null
var _glow_bg: Control = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _btn_start: Button = null
var _btn_gallery: Button = null
var _btn_settings: Button = null
var _btn_quit: Button = null
var _settings_overlay: Control = null
var _gallery_overlay: Control = null

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _game_time: float = 0.0
var _cards_data: Array[Dictionary] = []
var _enter_done: bool = false

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 给根节点挂载带默认字体的主题，所有子控件自动继承，解决无字体文件时文字不渲染的问题
	var root_theme := Theme.new()
	var fb: Font = ThemeDB.fallback_font
	if fb:
		root_theme.default_font = fb
		root_theme.default_font_size = 16
	theme = root_theme
	_build_ui()
	_init_floating_cards()
	# 延迟一帧再播放动画，确保节点树完全就绪
	call_deferred("_play_enter_anim")
	AudioManager.play_bgm("main")


## 辅助：直接用 anchor+offset 定位一个控件
## cx/cy 为锚点中心 (0..1)，w/h 为像素尺寸
func _place(node: Control, cx: float, cy: float, w: float, h: float) -> void:
	node.anchor_left   = cx;  node.anchor_right  = cx
	node.anchor_top    = cy;  node.anchor_bottom = cy
	node.offset_left   = -w * 0.5
	node.offset_right  =  w * 0.5
	node.offset_top    = -h * 0.5
	node.offset_bottom =  h * 0.5


func _build_ui() -> void:
	# ── 深色渐变背景 ──
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.06, 0.12)
	add_child(bg)

	# ── 浮动卡牌层 ──
	_floating_cards = Control.new()
	_floating_cards.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_floating_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floating_cards.draw.connect(_draw_floating_cards)
	add_child(_floating_cards)

	# ── 光晕层 ──
	_glow_bg = Control.new()
	_glow_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_bg.draw.connect(_draw_glow)
	add_child(_glow_bg)

	# ─── 直接 anchor+offset 定位，不依赖容器 layout ───
	# 屏幕水平中心 = 0.5，垂直位置用百分比锚点
	# 典型 9:16 手机屏布局（720×1280）：
	#   标题   ≈ 28% 高度
	#   副标题 ≈ 38% 高度
	#   按钮区 ≈ 55~75% 高度（4个按钮 + 间距）

	# 标题
	_title_label = Label.new()
	_title_label.text = "暗面都市"
	_title_label.add_theme_font_size_override("font_size", 72)
	_title_label.add_theme_color_override("font_color", GameTheme.accent)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place(_title_label, 0.5, 0.28, 400.0, 100.0)
	_title_label.modulate.a = 0.0
	_title_label.scale = Vector2(0.7, 0.7)
	_title_label.pivot_offset = Vector2(200.0, 50.0)
	add_child(_title_label)

	# 副标题
	_subtitle_label = Label.new()
	_subtitle_label.text = "Dark Side City"
	_subtitle_label.add_theme_font_size_override("font_size", 22)
	_subtitle_label.add_theme_color_override("font_color",
		Color(GameTheme.text_secondary.r, GameTheme.text_secondary.g,
			GameTheme.text_secondary.b, 0.8))
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place(_subtitle_label, 0.5, 0.38, 360.0, 40.0)
	_subtitle_label.modulate.a = 0.0
	add_child(_subtitle_label)

	# 按钮容器（VBoxContainer 只负责堆叠，本身被精确定位）
	# 4 个按钮高度: 56 + 48*3 = 200，间距 18*3 = 54 → 总高约 254
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 18)
	_place(btn_vbox, 0.5, 0.63, 300.0, 260.0)
	btn_vbox.modulate.a = 0.0  # 动画开始前隐藏
	add_child(btn_vbox)

	_btn_start = _make_menu_button("▶  开始游戏", GameTheme.accent, true)
	_btn_start.pressed.connect(_on_start_pressed)
	btn_vbox.add_child(_btn_start)

	_btn_gallery = _make_menu_button("📖  结局图鉴", Color(0.35, 0.28, 0.55), false)
	_btn_gallery.pressed.connect(_on_gallery_pressed)
	btn_vbox.add_child(_btn_gallery)

	_btn_settings = _make_menu_button("⚙  设 置", GameTheme.card_back, false)
	_btn_settings.pressed.connect(_on_settings_pressed)
	btn_vbox.add_child(_btn_settings)

	_btn_quit = _make_menu_button("✕  退出游戏", Color(0.55, 0.22, 0.22), false)
	_btn_quit.pressed.connect(_on_quit_pressed)
	btn_vbox.add_child(_btn_quit)

	# 版本标签 (右下角)
	var ver := Label.new()
	ver.text = "v0.1-dev"
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color",
		Color(GameTheme.text_secondary.r, GameTheme.text_secondary.g,
			GameTheme.text_secondary.b, 0.4))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -100.0
	ver.offset_top  = -36.0
	add_child(ver)

	# ── 图鉴 overlay ──
	_gallery_overlay = _build_gallery_overlay()
	add_child(_gallery_overlay)

	# ── 设置 overlay (最后添加，覆盖最上层) ──
	_settings_overlay = load("res://scenes/screens/settings.tscn").instantiate()
	_settings_overlay.close_requested.connect(func() -> void: pass)
	_settings_overlay.quit_requested.connect(_on_quit_pressed)
	add_child(_settings_overlay)


func _make_menu_button(text: String, color: Color, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, primary and 56 or 48)
	# 显式注入内置字体，确保无字体文件时文字仍可渲染
	var fallback: Font = ThemeDB.fallback_font
	if fallback:
		btn.add_theme_font_override("font", fallback)
	btn.add_theme_font_size_override("font_size", primary and 20 or 17)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))

	var alpha: float = primary and 0.92 or 0.75

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(color.r, color.g, color.b, alpha)
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(color.r, color.g, color.b, 1.0)
	hover.corner_radius_top_left = 10
	hover.corner_radius_top_right = 10
	hover.corner_radius_bottom_left = 10
	hover.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("hover", hover)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = GameTheme.darken(color, 0.75)
	pressed_style.corner_radius_top_left = 10
	pressed_style.corner_radius_top_right = 10
	pressed_style.corner_radius_bottom_left = 10
	pressed_style.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("pressed", pressed_style)

	return btn


## 程序化构建结局图鉴 overlay
func _build_gallery_overlay() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false

	# 背景遮罩
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.72)
	root.add_child(overlay)

	# 面板
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 560)
	panel.set_anchors_preset(Control.PRESET_CENTER)

	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.08, 0.16, 0.97)
	ps.border_color = Color(0.45, 0.35, 0.75, 0.6)
	ps.set_border_width_all(2)
	ps.corner_radius_top_left = 16
	ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16
	ps.corner_radius_bottom_right = 16
	ps.content_margin_left = 36.0
	ps.content_margin_right = 36.0
	ps.content_margin_top = 32.0
	ps.content_margin_bottom = 32.0
	panel.add_theme_stylebox_override("panel", ps)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	# 标题行
	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)

	var title_lbl := Label.new()
	title_lbl.text = "📖  结局图鉴"
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", Color(0.72, 0.6, 1.0))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title_lbl)

	# 统计小标签
	var runs_lbl := Label.new()
	runs_lbl.text = "共游玩 %d 次" % SaveManager.total_runs
	runs_lbl.add_theme_font_size_override("font_size", 14)
	runs_lbl.add_theme_color_override("font_color", GameTheme.text_secondary)
	runs_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hdr.add_child(runs_lbl)

	# 分隔
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.45, 0.35, 0.75, 0.35))
	vbox.add_child(sep)

	# 结局卡片滚动区
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	# 主线结局（不含 frag_xx）
	var gallery: Array = EndingSystem.get_endings_gallery(SaveManager.unlocked_endings)
	for entry: Dictionary in gallery:
		var eid: String = entry.get("id", "")
		if eid.begins_with("frag_"):
			continue  # 碎片单独区域
		grid.add_child(_build_ending_card(entry))

	# 碎片区
	var frag_unlocked: int = 0
	var frag_total: int = 0
	for entry: Dictionary in gallery:
		if entry.get("id", "").begins_with("frag_"):
			frag_total += 1
			if entry.get("unlocked", false):
				frag_unlocked += 1

	if frag_total > 0:
		var frag_label := Label.new()
		frag_label.text = "📷  照片碎片  %d / %d" % [frag_unlocked, frag_total]
		frag_label.add_theme_font_size_override("font_size", 15)
		frag_label.add_theme_color_override("font_color", GameTheme.text_secondary)
		# colspan 模拟：单独加在 grid 外用 vbox 包一层
		# 直接加入 grid 会占一格，用分隔 label 放在 vbox 里
		# 先关闭 grid，插入 vbox 元素（把 frag_label 加到 vbox）
		vbox.remove_child(scroll)
		vbox.add_child(scroll)  # 重新插到 frag_label 前后都不对，换方案：
		# 用 subvbox 把 scroll 和 frag 区域包在一起
		# 简单方案：直接在 grid 最后加 colspan 的空占位 + label
		# 最简单：frag_label + frag 进度 bar 直接加到 grid 外的 vbox
		# 我们已知 vbox 子节点顺序: title_row, sep, scroll
		# frag 区域加在 scroll 后
		var frag_row := HBoxContainer.new()
		frag_row.add_theme_constant_override("separation", 12)
		vbox.add_child(frag_row)
		frag_row.add_child(frag_label)
		# 进度条
		var prog := ProgressBar.new()
		prog.min_value = 0.0
		prog.max_value = float(frag_total)
		prog.value = float(frag_unlocked)
		prog.custom_minimum_size = Vector2(180, 18)
		prog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prog.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frag_row.add_child(prog)

	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关 闭"
	close_btn.custom_minimum_size = Vector2(120, 42)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	var cb_style := StyleBoxFlat.new()
	cb_style.bg_color = Color(0.25, 0.2, 0.4, 0.85)
	cb_style.corner_radius_top_left = 8
	cb_style.corner_radius_top_right = 8
	cb_style.corner_radius_bottom_left = 8
	cb_style.corner_radius_bottom_right = 8
	close_btn.add_theme_stylebox_override("normal", cb_style)
	var cb_hover := cb_style.duplicate() as StyleBoxFlat
	cb_hover.bg_color = Color(0.35, 0.28, 0.55, 1.0)
	close_btn.add_theme_stylebox_override("hover", cb_hover)
	close_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var btn_wrap := HBoxContainer.new()
	var bw_spacer := Control.new()
	bw_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_wrap.add_child(bw_spacer)
	btn_wrap.add_child(close_btn)
	vbox.add_child(btn_wrap)

	close_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("button_click")
		_hide_gallery()
	)

	return root


## 构建单个结局展示卡片
func _build_ending_card(entry: Dictionary) -> PanelContainer:
	var unlocked: bool = entry.get("unlocked", false)
	var is_vic: bool = entry.get("is_victory", true)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(320, 88)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var card_style := StyleBoxFlat.new()
	if unlocked:
		card_style.bg_color = Color(0.18, 0.14, 0.28, 0.9) if is_vic \
			else Color(0.25, 0.08, 0.08, 0.9)
		card_style.border_color = Color(0.55, 0.42, 0.85, 0.5) if is_vic \
			else Color(0.75, 0.2, 0.2, 0.5)
	else:
		card_style.bg_color = Color(0.12, 0.11, 0.18, 0.6)
		card_style.border_color = Color(0.3, 0.3, 0.35, 0.3)
	card_style.set_border_width_all(1)
	card_style.corner_radius_top_left = 8
	card_style.corner_radius_top_right = 8
	card_style.corner_radius_bottom_left = 8
	card_style.corner_radius_bottom_right = 8
	card_style.content_margin_left = 16.0
	card_style.content_margin_right = 16.0
	card_style.content_margin_top = 12.0
	card_style.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", card_style)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	card.add_child(inner)

	# 结局标题行
	var title_row := HBoxContainer.new()
	inner.add_child(title_row)

	var icon_lbl := Label.new()
	icon_lbl.text = "✦ " if unlocked else "？ "
	icon_lbl.add_theme_font_size_override("font_size", 16)
	icon_lbl.add_theme_color_override("font_color",
		Color(0.72, 0.6, 1.0) if (unlocked and is_vic) else
		Color(1.0, 0.4, 0.4) if (unlocked and not is_vic) else
		Color(0.4, 0.4, 0.45))
	title_row.add_child(icon_lbl)

	var title_lbl := Label.new()
	title_lbl.text = entry.get("title", "???")
	title_lbl.add_theme_font_size_override("font_size", 17)
	title_lbl.add_theme_color_override("font_color",
		Color(0.92, 0.88, 1.0) if unlocked else Color(0.4, 0.4, 0.45))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_lbl)

	# 胜败标签
	if unlocked:
		var tag := Label.new()
		tag.text = "✓ 胜利" if is_vic else "✗ 失败"
		tag.add_theme_font_size_override("font_size", 12)
		tag.add_theme_color_override("font_color",
			Color(0.5, 0.9, 0.5) if is_vic else Color(1.0, 0.5, 0.5))
		title_row.add_child(tag)

	# 副标题
	var sub_lbl := Label.new()
	sub_lbl.text = entry.get("subtitle", "") if unlocked else "尚未解锁"
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color",
		GameTheme.text_secondary if unlocked else Color(0.35, 0.35, 0.4))
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	inner.add_child(sub_lbl)

	return card


func _init_floating_cards() -> void:
	_cards_data.clear()
	for _i in range(FLOAT_CARD_COUNT):
		_cards_data.append({
			"x": randf_range(-0.1, 1.1),
			"y": randf_range(-0.1, 1.1),
			"icon": CARD_ICONS[randi() % CARD_ICONS.size()],
			"speed": randf_range(0.25, 0.6),
			"phase_offset": randf_range(0.0, TAU),
			"font_size": randf_range(18.0, 30.0),
			"base_alpha": randf_range(15.0, 45.0) / 255.0,
		})

# ---------------------------------------------------------------------------
# 入场动画
# ---------------------------------------------------------------------------

func _play_enter_anim() -> void:
	if _title_label == null or _subtitle_label == null or _btn_start == null:
		_show_all_immediately()
		return

	# btn_vbox 是 _btn_start 的父节点
	var btn_vbox: VBoxContainer = _btn_start.get_parent() as VBoxContainer
	if btn_vbox == null:
		_show_all_immediately()
		return

	# 标题淡入 + 放大（并行，0.3s 后开始）
	var t1 := create_tween().set_parallel(true)
	t1.tween_interval(0.3)
	t1.tween_property(_title_label, "modulate:a", 1.0, 0.7)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(0.3)
	t1.tween_property(_title_label, "scale", Vector2.ONE, 0.7)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(0.3)

	# 副标题淡入（0.7s 后）
	var t2 := create_tween()
	t2.tween_interval(0.7)
	t2.tween_property(_subtitle_label, "modulate:a", 1.0, 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 按钮组淡入（1.0s 后）
	var t3 := create_tween()
	t3.tween_interval(1.0)
	t3.tween_property(btn_vbox, "modulate:a", 1.0, 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t3.tween_callback(func() -> void:
		btn_vbox.modulate.a = 1.0
		_enter_done = true
	)

	# 超时保底：1.8s 后强制显示
	get_tree().create_timer(1.8).timeout.connect(func() -> void:
		if not _enter_done:
			_show_all_immediately()
	)


## 跳过动画，立即显示全部 UI（动画失败时的保底）
func _show_all_immediately() -> void:
	if _title_label:
		_title_label.modulate.a = 1.0
		_title_label.scale = Vector2.ONE
	if _subtitle_label:
		_subtitle_label.modulate.a = 1.0
	if _btn_start:
		var btn_vbox: VBoxContainer = _btn_start.get_parent() as VBoxContainer
		if btn_vbox:
			btn_vbox.modulate.a = 1.0
	_enter_done = true

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	_game_time += dt
	_floating_cards.queue_redraw()
	_glow_bg.queue_redraw()

# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw_floating_cards() -> void:
	var w: float = _floating_cards.size.x
	var h: float = _floating_cards.size.y
	var default_font: Font = ThemeDB.fallback_font

	for fc: Dictionary in _cards_data:
		var fx: float = fc["x"] * w + sin(_game_time * fc["speed"] + fc["phase_offset"]) * 50.0
		var fy: float = fc["y"] * h + cos(_game_time * fc["speed"] * 0.7 + fc["phase_offset"] + 1.5) * 35.0
		var a: float = fc["base_alpha"]

		_floating_cards.draw_rect(Rect2(fx - 56, fy - 80, 112, 160),
			Color(GameTheme.card_back.r, GameTheme.card_back.g,
				GameTheme.card_back.b, a * 0.2), true)
		_floating_cards.draw_rect(Rect2(fx - 56, fy - 80, 112, 160),
			Color(GameTheme.card_back.r, GameTheme.card_back.g,
				GameTheme.card_back.b, a * 0.6), false, 1.0)

		if default_font:
			_floating_cards.draw_string(default_font,
				Vector2(fx - 56, fy + 16),
				fc["icon"], HORIZONTAL_ALIGNMENT_CENTER,
				112, int(fc["font_size"] * 3),
				Color(1.0, 1.0, 1.0, a * 0.25))


func _draw_glow() -> void:
	var pulse: float = 0.85 + 0.15 * sin(_game_time * 1.2)
	var center2: Vector2 = _glow_bg.size * 0.5
	# 外层大光晕
	_glow_bg.draw_circle(center2, 420.0 * pulse,
		Color(GameTheme.dark_accent.r, GameTheme.dark_accent.g,
			GameTheme.dark_accent.b, 0.06 * pulse))
	# 内层光晕
	_glow_bg.draw_circle(center2, 200.0 * pulse,
		Color(GameTheme.accent.r, GameTheme.accent.g,
			GameTheme.accent.b, 0.08 * pulse))

# ---------------------------------------------------------------------------
# 事件处理
# ---------------------------------------------------------------------------

func _on_gallery_pressed() -> void:
	AudioManager.play_sfx("button_click")
	# 每次打开重建内容，确保显示最新解锁状态
	_refresh_gallery_content()
	_gallery_overlay.visible = true
	_gallery_overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_gallery_overlay, "modulate:a", 1.0, 0.2)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _hide_gallery() -> void:
	var tw := create_tween()
	tw.tween_property(_gallery_overlay, "modulate:a", 0.0, 0.15)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void: _gallery_overlay.visible = false)


## 刷新图鉴内容（每次打开时调用，确保反映最新解锁状态）
func _refresh_gallery_content() -> void:
	# 找到 panel > vbox > scroll > grid，清空 grid 并重填
	var panel: PanelContainer = _gallery_overlay.get_child(1) as PanelContainer
	if not panel:
		return
	var vbox: VBoxContainer = panel.get_child(0) as VBoxContainer
	if not vbox:
		return

	# 更新游玩次数标签 (hdr 第二个子节点)
	var hdr: HBoxContainer = vbox.get_child(0) as HBoxContainer
	if hdr and hdr.get_child_count() >= 2:
		var runs_lbl: Label = hdr.get_child(1) as Label
		if runs_lbl:
			runs_lbl.text = "共游玩 %d 次" % SaveManager.total_runs

	# 找到 scroll (index 2) > grid
	var scroll: ScrollContainer = vbox.get_child(2) as ScrollContainer
	if not scroll:
		return
	var grid: GridContainer = scroll.get_child(0) as GridContainer
	if not grid:
		return

	# 重填主线结局卡片
	for child in grid.get_children():
		child.queue_free()

	var gallery: Array = EndingSystem.get_endings_gallery(SaveManager.unlocked_endings)
	for entry: Dictionary in gallery:
		if not entry.get("id", "").begins_with("frag_"):
			grid.add_child(_build_ending_card(entry))

	# 更新碎片进度（frag_row 是 vbox 第4个子节点，若存在）
	if vbox.get_child_count() >= 5:
		var frag_row: HBoxContainer = vbox.get_child(3) as HBoxContainer
		if frag_row:
			var frag_unlocked: int = 0
			var frag_total: int = 0
			for entry: Dictionary in gallery:
				if entry.get("id", "").begins_with("frag_"):
					frag_total += 1
					if entry.get("unlocked", false):
						frag_unlocked += 1
			var frag_lbl: Label = frag_row.get_child(0) as Label
			if frag_lbl:
				frag_lbl.text = "📷  照片碎片  %d / %d" % [frag_unlocked, frag_total]
			var prog: ProgressBar = frag_row.get_child(1) as ProgressBar
			if prog:
				prog.value = float(frag_unlocked)


func _on_start_pressed() -> void:
	AudioManager.play_sfx("button_click")
	# 按钮禁用防止重复点击
	_btn_start.disabled = true
	_btn_gallery.disabled = true
	_btn_settings.disabled = true
	_btn_quit.disabled = true
	# 淡出后切换场景
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file(MAIN_SCENE_PATH)
	)


func _on_settings_pressed() -> void:
	AudioManager.play_sfx("button_click")
	_settings_overlay.show_settings()


func _on_quit_pressed() -> void:
	AudioManager.play_sfx("button_click")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void: get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	if _settings_overlay and _settings_overlay.visible:
		return  # 设置面板自行处理 ESC
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _gallery_overlay and _gallery_overlay.visible:
			AudioManager.play_sfx("popup_close")
			_hide_gallery()
		else:
			_on_quit_pressed()
		get_viewport().set_input_as_handled()
