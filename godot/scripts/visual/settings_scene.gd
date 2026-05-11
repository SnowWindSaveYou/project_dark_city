## SettingsScene — 设置面板
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
# 节点引用 (来自 settings.tscn)
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
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_apply_styles()
	_connect_signals()

	# 同步初始音量
	_bgm_slider.value = AudioManager.get_bgm_volume()
	_sfx_slider.value = AudioManager.get_sfx_volume()
	_bgm_value_label.text = "%d%%" % roundi(AudioManager.get_bgm_volume() * 100)
	_sfx_value_label.text = "%d%%" % roundi(AudioManager.get_sfx_volume() * 100)

	visible = false


func _apply_styles() -> void:
	# 标题颜色
	_title_label.add_theme_color_override("font_color", GameTheme.accent)

	# 分隔线颜色
	_separator.add_theme_color_override("color",
		Color(GameTheme.accent.r, GameTheme.accent.g, GameTheme.accent.b, 0.3))

	# 标签颜色
	_bgm_label.add_theme_color_override("font_color", GameTheme.text_secondary)
	_sfx_label.add_theme_color_override("font_color", GameTheme.text_secondary)
	_bgm_value_label.add_theme_color_override("font_color", GameTheme.accent)
	_sfx_value_label.add_theme_color_override("font_color", GameTheme.accent)

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

	# 滑块样式 - BGM
	_apply_slider_style(_bgm_slider)
	_apply_slider_style(_sfx_slider)

	# 按钮样式
	_apply_button_style(_btn_quit, GameTheme.accent)
	_apply_button_style(_btn_close, GameTheme.card_back)


func _apply_slider_style(slider: HSlider) -> void:
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Color(0.25, 0.22, 0.35)
	track_style.corner_radius_top_left = 4
	track_style.corner_radius_top_right = 4
	track_style.corner_radius_bottom_left = 4
	track_style.corner_radius_bottom_right = 4
	slider.add_theme_stylebox_override("slider", track_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = GameTheme.accent
	fill_style.corner_radius_top_left = 8
	fill_style.corner_radius_top_right = 8
	fill_style.corner_radius_bottom_left = 8
	fill_style.corner_radius_bottom_right = 8
	slider.add_theme_stylebox_override("grabber_area", fill_style)


func _apply_button_style(btn: Button, color: Color) -> void:
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

## 显示设置面板 (带淡入动画)
func show_settings() -> void:
	visible = true
	modulate.a = 0.0
	# 同步最新音量到滑块 (可能被其他地方修改)
	_bgm_slider.value = AudioManager.get_bgm_volume()
	_sfx_slider.value = AudioManager.get_sfx_volume()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.2)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


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
