## SettingsScene — 设置面板（物语白底风格）
##
## 与图鉴 overlay 保持一致：白底、直角、细边框、近黑文字。
extends Control

signal close_requested
signal quit_requested

# ---------------------------------------------------------------------------
# 配色常量（与 main_menu_scene.gd 保持一致）
# ---------------------------------------------------------------------------
const C_TITLE:  Color = Color(0.04, 0.03, 0.08, 1.0)
const C_COORD:  Color = Color(0.50, 0.46, 0.60, 0.60)
const C_ACCENT: Color = Color(0.22, 0.18, 0.38, 1.0)   # 深紫，用于滑块填充

# ---------------------------------------------------------------------------
# 节点引用
# ---------------------------------------------------------------------------
@onready var _overlay: ColorRect       = $Overlay
@onready var _panel: PanelContainer    = $AnchorCenter/Panel
@onready var _title_label: Label       = $AnchorCenter/Panel/VBox/TitleLabel
@onready var _separator: HSeparator    = $AnchorCenter/Panel/VBox/Separator
@onready var _bgm_label: Label         = $AnchorCenter/Panel/VBox/BgmRow/BgmLabelRow/BgmLabel
@onready var _bgm_value_label: Label   = $AnchorCenter/Panel/VBox/BgmRow/BgmLabelRow/BgmValueLabel
@onready var _bgm_slider: HSlider      = $AnchorCenter/Panel/VBox/BgmRow/BgmSlider
@onready var _sfx_label: Label         = $AnchorCenter/Panel/VBox/SfxRow/SfxLabelRow/SfxLabel
@onready var _sfx_value_label: Label   = $AnchorCenter/Panel/VBox/SfxRow/SfxLabelRow/SfxValueLabel
@onready var _sfx_slider: HSlider      = $AnchorCenter/Panel/VBox/SfxRow/SfxSlider
@onready var _btn_quit: Button         = $AnchorCenter/Panel/VBox/BtnRow/BtnQuit
@onready var _btn_close: Button        = $AnchorCenter/Panel/VBox/BtnRow/BtnClose

# ---------------------------------------------------------------------------
# _ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_apply_styles()
	_connect_signals()

	_bgm_slider.value = AudioManager.get_bgm_volume()
	_sfx_slider.value = AudioManager.get_sfx_volume()
	_bgm_value_label.text = "%d%%" % roundi(AudioManager.get_bgm_volume() * 100)
	_sfx_value_label.text = "%d%%" % roundi(AudioManager.get_sfx_volume() * 100)

	visible = false


func _apply_styles() -> void:
	# 遮罩：极浅半透明（不要全黑，和白底协调）
	_overlay.color = Color(0.03, 0.02, 0.06, 0.55)

	# 标题
	_title_label.add_theme_color_override("font_color", C_TITLE)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# 分隔线
	_separator.add_theme_color_override("color", Color(0.18, 0.16, 0.28, 0.25))

	# 标签
	for lbl in [_bgm_label, _sfx_label]:
		lbl.add_theme_color_override("font_color", C_TITLE)
	for lbl in [_bgm_value_label, _sfx_value_label]:
		lbl.add_theme_color_override("font_color", C_ACCENT)

	# 面板：白底、直角、细边框
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color     = Color(0.97, 0.97, 0.97, 0.98)
	ps.border_color = Color(0.20, 0.18, 0.30, 0.55)
	ps.set_border_width_all(1)
	ps.corner_radius_top_left    = 0
	ps.corner_radius_top_right   = 0
	ps.corner_radius_bottom_left = 0
	ps.corner_radius_bottom_right = 0
	ps.content_margin_left   = 40.0
	ps.content_margin_right  = 40.0
	ps.content_margin_top    = 36.0
	ps.content_margin_bottom = 36.0
	_panel.add_theme_stylebox_override("panel", ps)

	# 滑块
	_apply_slider_style(_bgm_slider)
	_apply_slider_style(_sfx_slider)

	# 按钮
	_apply_btn_quit(_btn_quit)
	_apply_btn_close(_btn_close)


func _apply_slider_style(slider: HSlider) -> void:
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(0.82, 0.81, 0.86, 1.0)   # 浅灰轨道
	track.corner_radius_top_left    = 2
	track.corner_radius_top_right   = 2
	track.corner_radius_bottom_left = 2
	track.corner_radius_bottom_right = 2
	slider.add_theme_stylebox_override("slider", track)

	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = C_ACCENT
	fill.corner_radius_top_left    = 2
	fill.corner_radius_top_right   = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	slider.add_theme_stylebox_override("grabber_area", fill)


func _apply_btn_quit(btn: Button) -> void:
	btn.add_theme_color_override("font_color",         Color(0.45, 0.12, 0.12))
	btn.add_theme_color_override("font_hover_color",   Color(0.75, 0.10, 0.10))
	btn.add_theme_color_override("font_pressed_color", Color(0.75, 0.10, 0.10))
	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = Color(0,0,0,0); n.border_color = Color(0.45, 0.14, 0.14, 0.40)
	n.set_border_width_all(1)
	n.corner_radius_top_left=0; n.corner_radius_top_right=0
	n.corner_radius_bottom_left=0; n.corner_radius_bottom_right=0
	n.content_margin_left = 20.0
	btn.add_theme_stylebox_override("normal", n)
	var h: StyleBoxFlat = n.duplicate(); h.bg_color = Color(0.97,0.92,0.92,1.0)
	btn.add_theme_stylebox_override("hover", h)
	var p: StyleBoxFlat = n.duplicate(); p.bg_color = Color(0.92,0.88,0.88,1.0)
	btn.add_theme_stylebox_override("pressed", p)


func _apply_btn_close(btn: Button) -> void:
	btn.add_theme_color_override("font_color",         C_TITLE)
	btn.add_theme_color_override("font_hover_color",   Color(0.04, 0.03, 0.08))
	btn.add_theme_color_override("font_pressed_color", Color(0.04, 0.03, 0.08))
	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = Color(0,0,0,0); n.border_color = Color(0.18, 0.16, 0.28, 0.45)
	n.set_border_width_all(1)
	n.corner_radius_top_left=0; n.corner_radius_top_right=0
	n.corner_radius_bottom_left=0; n.corner_radius_bottom_right=0
	n.content_margin_left = 20.0
	btn.add_theme_stylebox_override("normal", n)
	var h: StyleBoxFlat = n.duplicate(); h.bg_color = Color(0.10,0.08,0.16,0.06)
	btn.add_theme_stylebox_override("hover", h)
	var p: StyleBoxFlat = n.duplicate(); p.bg_color = Color(0.10,0.08,0.16,0.12)
	btn.add_theme_stylebox_override("pressed", p)


# ---------------------------------------------------------------------------
# 信号连接
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	_btn_quit.pressed.connect(_on_quit_pressed)
	_btn_close.pressed.connect(_on_close_pressed)
	_bgm_slider.value_changed.connect(func(val: float) -> void:
		AudioManager.set_bgm_volume(val)
		_bgm_value_label.text = "%d%%" % roundi(val * 100)
	)
	_sfx_slider.value_changed.connect(func(val: float) -> void:
		AudioManager.set_sfx_volume(val)
		_sfx_value_label.text = "%d%%" % roundi(val * 100)
	)


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func show_settings() -> void:
	visible = true
	modulate.a = 0.0
	_bgm_slider.value = AudioManager.get_bgm_volume()
	_sfx_slider.value = AudioManager.get_sfx_volume()
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func hide_settings() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.12) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): visible = false)


# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close_pressed()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 事件
# ---------------------------------------------------------------------------

func _on_close_pressed() -> void:
	AudioManager.play_sfx("button_click")
	hide_settings()
	close_requested.emit()


func _on_quit_pressed() -> void:
	AudioManager.play_sfx("button_click")
	quit_requested.emit()
