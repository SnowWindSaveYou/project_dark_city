## MainMenuScene — 主菜单场景
##
## 混合架构：节点在 main_menu.tscn 中预定义（编辑器可见），
## 脚本只负责颜色/样式、动画和事件处理。
extends Control

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const FLOAT_CARD_COUNT: int = 14
const CARD_ICONS: Array = ["🏠", "👻", "⚡", "💎", "📖", "🔍", "🛒", "📸", "⛪", "🌙", "🔮", "🎴"]

# ---------------------------------------------------------------------------
# 节点引用（来自 .tscn）
# ---------------------------------------------------------------------------
@onready var _floating_cards: Control    = $FloatingCards
@onready var _glow_bg: Control           = $GlowBg
@onready var _title_label: Label         = $TitleLabel
@onready var _subtitle_label: Label      = $SubtitleLabel
@onready var _btn_vbox: VBoxContainer    = $ButtonVBox
@onready var _btn_start: Button          = $ButtonVBox/BtnStart
@onready var _btn_gallery: Button        = $ButtonVBox/BtnGallery
@onready var _btn_settings: Button       = $ButtonVBox/BtnSettings
@onready var _btn_quit: Button           = $ButtonVBox/BtnQuit
@onready var _ver_label: Label           = $VersionLabel

# ---------------------------------------------------------------------------
# 动态创建的 overlay（图鉴/设置）
# ---------------------------------------------------------------------------
var _settings_overlay: Control = null
var _gallery_overlay: Control  = null

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
	# ── 颜色/样式 ──
	_title_label.add_theme_color_override("font_color", GameTheme.accent)
	_subtitle_label.add_theme_color_override("font_color",
		Color(GameTheme.text_secondary.r, GameTheme.text_secondary.g,
			GameTheme.text_secondary.b, 0.8))
	_ver_label.add_theme_color_override("font_color",
		Color(GameTheme.text_secondary.r, GameTheme.text_secondary.g,
			GameTheme.text_secondary.b, 0.4))

	# ── 按钮样式 ──
	_style_button(_btn_start,    GameTheme.accent,             true)
	_style_button(_btn_gallery,  Color(0.35, 0.28, 0.55),     false)
	_style_button(_btn_settings, GameTheme.card_back,          false)
	_style_button(_btn_quit,     Color(0.55, 0.22, 0.22),     false)

	# ── 按钮信号 ──
	_btn_start.pressed.connect(_on_start_pressed)
	_btn_gallery.pressed.connect(_on_gallery_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)
	_btn_quit.pressed.connect(_on_quit_pressed)

	# ── 浮动卡牌和光晕绘制 ──
	_floating_cards.draw.connect(_draw_floating_cards)
	_glow_bg.draw.connect(_draw_glow)

	# ── 动态 overlay ──
	_gallery_overlay = _build_gallery_overlay()
	add_child(_gallery_overlay)

	_settings_overlay = load("res://scenes/screens/settings.tscn").instantiate()
	_settings_overlay.close_requested.connect(func() -> void: pass)
	_settings_overlay.quit_requested.connect(_on_quit_pressed)
	add_child(_settings_overlay)

	# ── 初始化浮动卡牌 ──
	_init_floating_cards()

	# ── 动画初始状态 ──
	_title_label.modulate.a  = 0.0
	_title_label.scale       = Vector2(0.7, 0.7)
	_title_label.pivot_offset = _title_label.size / 2.0
	_title_label.resized.connect(func() -> void:
		_title_label.pivot_offset = _title_label.size / 2.0)
	_subtitle_label.modulate.a = 0.0
	_btn_vbox.modulate.a       = 0.0

	# ── 入场动画（延一帧确保布局完成）──
	call_deferred("_play_enter_anim")

	AudioManager.play_bgm("main")


func _style_button(btn: Button, color: Color, primary: bool) -> void:
	var alpha: float = 0.92 if primary else 0.75

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(color.r, color.g, color.b, alpha)
	normal.corner_radius_top_left    = 10
	normal.corner_radius_top_right   = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(color.r, color.g, color.b, 1.0)
	hover.corner_radius_top_left    = 10
	hover.corner_radius_top_right   = 10
	hover.corner_radius_bottom_left = 10
	hover.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("hover", hover)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = GameTheme.darken(color, 0.75)
	pressed_style.corner_radius_top_left    = 10
	pressed_style.corner_radius_top_right   = 10
	pressed_style.corner_radius_bottom_left = 10
	pressed_style.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("pressed", pressed_style)


# ---------------------------------------------------------------------------
# 入场动画
# ---------------------------------------------------------------------------

func _play_enter_anim() -> void:
	# 标题淡入 + 放大（并行，0.3s 后）
	var t1: Tween = create_tween()
	t1.tween_interval(0.3)
	t1.set_parallel(true)
	t1.tween_property(_title_label, "modulate:a", 1.0, 0.7) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t1.tween_property(_title_label, "scale", Vector2.ONE, 0.7) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# 副标题（0.7s 后）
	var t2: Tween = create_tween()
	t2.tween_interval(0.7)
	t2.tween_property(_subtitle_label, "modulate:a", 1.0, 0.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 按钮组（1.0s 后）
	var t3: Tween = create_tween()
	t3.tween_interval(1.0)
	t3.tween_property(_btn_vbox, "modulate:a", 1.0, 0.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t3.tween_callback(func() -> void:
		_btn_vbox.modulate.a = 1.0
		_enter_done = true
	)

	# 超时保底
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if not _enter_done:
			_title_label.modulate.a  = 1.0
			_title_label.scale       = Vector2.ONE
			_subtitle_label.modulate.a = 1.0
			_btn_vbox.modulate.a     = 1.0
			_enter_done = true
	)


# ---------------------------------------------------------------------------
# 更新 & 绘制
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	_game_time += dt
	_floating_cards.queue_redraw()
	_glow_bg.queue_redraw()


func _draw_floating_cards() -> void:
	var w: float = _floating_cards.size.x
	var h: float = _floating_cards.size.y
	var default_font: Font = ThemeDB.fallback_font

	for fc: Dictionary in _cards_data:
		var fx: float = fc["x"] * w + sin(_game_time * fc["speed"] + fc["phase_offset"]) * 50.0
		var fy: float = fc["y"] * h + cos(_game_time * fc["speed"] * 0.7 + fc["phase_offset"] + 1.5) * 35.0
		var a: float  = fc["base_alpha"]

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
	_glow_bg.draw_circle(center2, 420.0 * pulse,
		Color(GameTheme.dark_accent.r, GameTheme.dark_accent.g,
			GameTheme.dark_accent.b, 0.06 * pulse))
	_glow_bg.draw_circle(center2, 200.0 * pulse,
		Color(GameTheme.accent.r, GameTheme.accent.g,
			GameTheme.accent.b, 0.08 * pulse))


# ---------------------------------------------------------------------------
# 浮动卡牌初始化
# ---------------------------------------------------------------------------

func _init_floating_cards() -> void:
	_cards_data.clear()
	for _i in range(FLOAT_CARD_COUNT):
		_cards_data.append({
			"x":            randf_range(-0.1, 1.1),
			"y":            randf_range(-0.1, 1.1),
			"icon":         CARD_ICONS[randi() % CARD_ICONS.size()],
			"speed":        randf_range(0.25, 0.6),
			"phase_offset": randf_range(0.0, TAU),
			"font_size":    randf_range(18.0, 30.0),
			"base_alpha":   randf_range(15.0, 45.0) / 255.0,
		})


# ---------------------------------------------------------------------------
# 图鉴 overlay（程序化，因为内容是动态的）
# ---------------------------------------------------------------------------

func _build_gallery_overlay() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false

	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.72)
	root.add_child(overlay)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 560)
	panel.set_anchors_preset(Control.PRESET_CENTER)

	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.08, 0.16, 0.97)
	ps.border_color = Color(0.45, 0.35, 0.75, 0.6)
	ps.set_border_width_all(2)
	ps.corner_radius_top_left    = 16
	ps.corner_radius_top_right   = 16
	ps.corner_radius_bottom_left = 16
	ps.corner_radius_bottom_right = 16
	ps.content_margin_left   = 36.0
	ps.content_margin_right  = 36.0
	ps.content_margin_top    = 32.0
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

	var runs_lbl := Label.new()
	runs_lbl.text = "共游玩 %d 次" % SaveManager.total_runs
	runs_lbl.add_theme_font_size_override("font_size", 14)
	runs_lbl.add_theme_color_override("font_color", GameTheme.text_secondary)
	runs_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hdr.add_child(runs_lbl)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.45, 0.35, 0.75, 0.35))
	vbox.add_child(sep)

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

	var gallery: Array = EndingSystem.get_endings_gallery(SaveManager.unlocked_endings)
	for entry: Dictionary in gallery:
		if not entry.get("id", "").begins_with("frag_"):
			grid.add_child(_build_ending_card(entry))

	# 碎片进度
	var frag_unlocked: int = 0
	var frag_total: int = 0
	for entry: Dictionary in gallery:
		if entry.get("id", "").begins_with("frag_"):
			frag_total += 1
			if entry.get("unlocked", false):
				frag_unlocked += 1

	if frag_total > 0:
		var frag_row := HBoxContainer.new()
		frag_row.add_theme_constant_override("separation", 12)
		vbox.add_child(frag_row)
		var frag_lbl := Label.new()
		frag_lbl.text = "📷  照片碎片  %d / %d" % [frag_unlocked, frag_total]
		frag_lbl.add_theme_font_size_override("font_size", 15)
		frag_lbl.add_theme_color_override("font_color", GameTheme.text_secondary)
		frag_row.add_child(frag_lbl)
		var prog := ProgressBar.new()
		prog.min_value  = 0.0
		prog.max_value  = float(frag_total)
		prog.value      = float(frag_unlocked)
		prog.custom_minimum_size = Vector2(180, 18)
		prog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prog.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
		frag_row.add_child(prog)

	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关 闭"
	close_btn.custom_minimum_size = Vector2(120, 42)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	var cb_style := StyleBoxFlat.new()
	cb_style.bg_color = Color(0.25, 0.2, 0.4, 0.85)
	cb_style.corner_radius_top_left    = 8
	cb_style.corner_radius_top_right   = 8
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


func _build_ending_card(entry: Dictionary) -> PanelContainer:
	var unlocked: bool = entry.get("unlocked", false)
	var is_vic: bool   = entry.get("is_victory", true)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(320, 88)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var card_style := StyleBoxFlat.new()
	if unlocked:
		card_style.bg_color     = Color(0.18, 0.14, 0.28, 0.9) if is_vic else Color(0.25, 0.08, 0.08, 0.9)
		card_style.border_color = Color(0.55, 0.42, 0.85, 0.5) if is_vic else Color(0.75, 0.2,  0.2,  0.5)
	else:
		card_style.bg_color     = Color(0.12, 0.11, 0.18, 0.6)
		card_style.border_color = Color(0.3,  0.3,  0.35, 0.3)
	card_style.set_border_width_all(1)
	card_style.corner_radius_top_left     = 8
	card_style.corner_radius_top_right    = 8
	card_style.corner_radius_bottom_left  = 8
	card_style.corner_radius_bottom_right = 8
	card_style.content_margin_left   = 16.0
	card_style.content_margin_right  = 16.0
	card_style.content_margin_top    = 12.0
	card_style.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", card_style)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	card.add_child(inner)

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

	if unlocked:
		var tag := Label.new()
		tag.text = "✓ 胜利" if is_vic else "✗ 失败"
		tag.add_theme_font_size_override("font_size", 12)
		tag.add_theme_color_override("font_color",
			Color(0.5, 0.9, 0.5) if is_vic else Color(1.0, 0.5, 0.5))
		title_row.add_child(tag)

	var sub_lbl := Label.new()
	sub_lbl.text = entry.get("subtitle", "") if unlocked else "尚未解锁"
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color",
		GameTheme.text_secondary if unlocked else Color(0.35, 0.35, 0.4))
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	inner.add_child(sub_lbl)

	return card


# ---------------------------------------------------------------------------
# 图鉴刷新
# ---------------------------------------------------------------------------

func _on_gallery_pressed() -> void:
	AudioManager.play_sfx("button_click")
	_refresh_gallery_content()
	_gallery_overlay.visible = true
	_gallery_overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_gallery_overlay, "modulate:a", 1.0, 0.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _hide_gallery() -> void:
	var tw := create_tween()
	tw.tween_property(_gallery_overlay, "modulate:a", 0.0, 0.15) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void: _gallery_overlay.visible = false)


func _refresh_gallery_content() -> void:
	var panel: PanelContainer = _gallery_overlay.get_child(1) as PanelContainer
	if not panel:
		return
	var vbox: VBoxContainer = panel.get_child(0) as VBoxContainer
	if not vbox:
		return

	var hdr: HBoxContainer = vbox.get_child(0) as HBoxContainer
	if hdr and hdr.get_child_count() >= 2:
		var runs_lbl: Label = hdr.get_child(1) as Label
		if runs_lbl:
			runs_lbl.text = "共游玩 %d 次" % SaveManager.total_runs

	var scroll: ScrollContainer = vbox.get_child(2) as ScrollContainer
	if not scroll:
		return
	var grid: GridContainer = scroll.get_child(0) as GridContainer
	if not grid:
		return

	for child in grid.get_children():
		child.queue_free()

	var gallery: Array = EndingSystem.get_endings_gallery(SaveManager.unlocked_endings)
	for entry: Dictionary in gallery:
		if not entry.get("id", "").begins_with("frag_"):
			grid.add_child(_build_ending_card(entry))

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


# ---------------------------------------------------------------------------
# 按钮事件
# ---------------------------------------------------------------------------

func _on_start_pressed() -> void:
	AudioManager.play_sfx("button_click")
	_btn_start.disabled    = true
	_btn_gallery.disabled  = true
	_btn_settings.disabled = true
	_btn_quit.disabled     = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4) \
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
	tw.tween_property(self, "modulate:a", 0.0, 0.25) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void: get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	if _settings_overlay and _settings_overlay.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _gallery_overlay and _gallery_overlay.visible:
			AudioManager.play_sfx("popup_close")
			_hide_gallery()
		else:
			_on_quit_pressed()
		get_viewport().set_input_as_handled()
