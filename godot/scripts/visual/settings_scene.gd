## SettingsScene — 设置面板 (全程序化构建)
##
## 可作为独立场景加载，也可作为 overlay 叠加在任何界面上。
## 包含: BGM 音量、SFX 音量滑块，以及关闭/退出按钮。
## 持久化: 通过 AudioManager.save_settings() → user://audio_settings.cfg
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
## 面板关闭时发出
signal close_requested
## 用户点击"退出游戏"时发出
signal quit_requested

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const PANEL_W: float = 520.0
const PANEL_H: float = 420.0

# ---------------------------------------------------------------------------
# 节点引用 (程序化创建)
# ---------------------------------------------------------------------------
var _overlay: ColorRect = null
var _panel: PanelContainer = null
var _bgm_slider: HSlider = null
var _sfx_slider: HSlider = null
var _bgm_value_label: Label = null
var _sfx_value_label: Label = null

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	# 占满全屏，用于捕获背景点击
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_ui()
	visible = false


func _build_ui() -> void:
	# ── 半透明背景遮罩 ──
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	add_child(_overlay)

	# ── 面板容器 ──
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)

	# 面板居中
	var anchor: Control = Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(anchor)

	_panel.set_anchors_preset(Control.PRESET_CENTER)
	anchor.add_child(_panel)

	# 面板样式 (圆角深色卡片)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.10, 0.18, 0.97)
	panel_style.border_color = Color(GameTheme.accent.r, GameTheme.accent.g,
		GameTheme.accent.b, 0.5)
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.content_margin_left = 40.0
	panel_style.content_margin_right = 40.0
	panel_style.content_margin_top = 36.0
	panel_style.content_margin_bottom = 36.0
	_panel.add_theme_stylebox_override("panel", panel_style)

	# ── 面板内容 VBox ──
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	_panel.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "⚙ 设置"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GameTheme.accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# 分隔线
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(GameTheme.accent.r,
		GameTheme.accent.g, GameTheme.accent.b, 0.3))
	vbox.add_child(sep)

	# BGM 音量
	vbox.add_child(_build_volume_row(
		"🎵  背景音乐",
		AudioManager.get_bgm_volume(),
		func(val: float) -> void:
			AudioManager.set_bgm_volume(val)
			_bgm_value_label.text = "%d%%" % roundi(val * 100),
		true
	))

	# SFX 音量
	vbox.add_child(_build_volume_row(
		"🔊  音效",
		AudioManager.get_sfx_volume(),
		func(val: float) -> void:
			AudioManager.set_sfx_volume(val)
			_sfx_value_label.text = "%d%%" % roundi(val * 100),
		false
	))

	# 弹性占位
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# 按钮行
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	# 弹性占位 (按钮右对齐)
	var btn_spacer := Control.new()
	btn_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(btn_spacer)

	# 退出游戏按钮
	var quit_btn := _make_button("退出游戏", GameTheme.accent)
	quit_btn.pressed.connect(_on_quit_pressed)
	btn_row.add_child(quit_btn)

	# 关闭按钮
	var close_btn := _make_button("关 闭", GameTheme.card_back)
	close_btn.pressed.connect(_on_close_pressed)
	btn_row.add_child(close_btn)


func _build_volume_row(label_text: String, init_val: float,
		on_change: Callable, is_bgm: bool) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# 标签行
	var label_row := HBoxContainer.new()
	row.add_child(label_row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", GameTheme.text_secondary)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_row.add_child(lbl)

	var val_lbl := Label.new()
	val_lbl.text = "%d%%" % roundi(init_val * 100)
	val_lbl.add_theme_font_size_override("font_size", 18)
	val_lbl.add_theme_color_override("font_color", GameTheme.accent)
	val_lbl.custom_minimum_size = Vector2(52, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_row.add_child(val_lbl)

	if is_bgm:
		_bgm_value_label = val_lbl
	else:
		_sfx_value_label = val_lbl

	# 滑块
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = init_val
	slider.custom_minimum_size = Vector2(PANEL_W - 80, 28)

	# 滑块样式
	var slider_style := StyleBoxFlat.new()
	slider_style.bg_color = Color(0.25, 0.22, 0.35)
	slider_style.corner_radius_top_left = 4
	slider_style.corner_radius_top_right = 4
	slider_style.corner_radius_bottom_left = 4
	slider_style.corner_radius_bottom_right = 4
	slider.add_theme_stylebox_override("slider", slider_style)

	var grabber_style := StyleBoxFlat.new()
	grabber_style.bg_color = GameTheme.accent
	grabber_style.corner_radius_top_left = 8
	grabber_style.corner_radius_top_right = 8
	grabber_style.corner_radius_bottom_left = 8
	grabber_style.corner_radius_bottom_right = 8
	slider.add_theme_stylebox_override("grabber_area", grabber_style)

	slider.value_changed.connect(on_change)
	row.add_child(slider)

	if is_bgm:
		_bgm_slider = slider
	else:
		_sfx_slider = slider

	return row


func _make_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(120, 44)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color.WHITE)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(color.r, color.g, color.b, 0.85)
	normal_style.corner_radius_top_left = 8
	normal_style.corner_radius_top_right = 8
	normal_style.corner_radius_bottom_left = 8
	normal_style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(color.r, color.g, color.b, 1.0)
	hover_style.corner_radius_top_left = 8
	hover_style.corner_radius_top_right = 8
	hover_style.corner_radius_bottom_left = 8
	hover_style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("hover", hover_style)

	return btn

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## 显示设置面板 (带淡入动画)
func show_settings() -> void:
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.2)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# 同步最新音量到滑块 (可能被其他地方修改)
	if _bgm_slider:
		_bgm_slider.value = AudioManager.get_bgm_volume()
	if _sfx_slider:
		_sfx_slider.value = AudioManager.get_sfx_volume()


## 隐藏设置面板 (带淡出动画)
func hide_settings() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): visible = false)

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# 事件处理
# ---------------------------------------------------------------------------

func _on_close_pressed() -> void:
	AudioManager.play_sfx("button_click")
	hide_settings()
	close_requested.emit()


func _on_quit_pressed() -> void:
	AudioManager.play_sfx("button_click")
	quit_requested.emit()
