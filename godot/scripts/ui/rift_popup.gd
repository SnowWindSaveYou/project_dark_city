## RiftPopup - 裂隙确认弹窗 (Scene 化)
## 从 EventPopup 拆分出的独立场景，使用 Control 节点替代 _draw()
class_name RiftPopup
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal rift_confirmed()
signal rift_cancelled()

# ---------------------------------------------------------------------------
# 节点引用
# ---------------------------------------------------------------------------
@onready var _overlay: ColorRect = $Overlay
@onready var _panel: PanelContainer = $PanelAnchor/Panel
@onready var _color_bar: ColorRect = $PanelAnchor/Panel/ColorBar
@onready var _icon_label: Label = $PanelAnchor/Panel/Content/IconLabel
@onready var _title_label: Label = $PanelAnchor/Panel/Content/TitleLabel
@onready var _desc_label: Label = $PanelAnchor/Panel/Content/DescLabel
@onready var _enter_button: Button = $PanelAnchor/Panel/Content/ButtonRow/EnterButton
@onready var _stay_button: Button = $PanelAnchor/Panel/Content/ButtonRow/StayButton

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _active: bool = false
var _phase: String = "none"  # "enter" | "idle" | "exit"

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 应用主题色
	var t = GameTheme
	_color_bar.color = t.dark_accent
	_icon_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", t.text_primary)
	_desc_label.add_theme_font_size_override("font_size", 12)
	_desc_label.add_theme_color_override("font_color", t.text_secondary)

	# 面板样式
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(t.panel_bg.r, t.panel_bg.g, t.panel_bg.b, 0.96)
	panel_style.border_color = Color(t.dark_accent.r, t.dark_accent.g, t.dark_accent.b, 0.4)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(0)
	_panel.add_theme_stylebox_override("panel", panel_style)

	# "进入暗面" 按钮样式
	var enter_style := StyleBoxFlat.new()
	enter_style.bg_color = Color(t.dark_accent.r, t.dark_accent.g, t.dark_accent.b, 0.86)
	enter_style.set_corner_radius_all(4)
	enter_style.set_content_margin_all(4)
	_enter_button.add_theme_stylebox_override("normal", enter_style)
	var enter_hover := enter_style.duplicate()
	enter_hover.bg_color = GameTheme.lighten(t.dark_accent, 0.15)
	_enter_button.add_theme_stylebox_override("hover", enter_hover)
	var enter_pressed := enter_style.duplicate()
	enter_pressed.bg_color = GameTheme.darken(t.dark_accent, 0.85)
	_enter_button.add_theme_stylebox_override("pressed", enter_pressed)
	_enter_button.add_theme_color_override("font_color", Color.WHITE)
	_enter_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_enter_button.add_theme_font_size_override("font_size", 13)

	# "留在原地" 按钮样式
	var stay_style := StyleBoxFlat.new()
	stay_style.bg_color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, 0.24)
	stay_style.border_color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, 0.47)
	stay_style.set_border_width_all(1)
	stay_style.set_corner_radius_all(4)
	stay_style.set_content_margin_all(4)
	_stay_button.add_theme_stylebox_override("normal", stay_style)
	var stay_hover := stay_style.duplicate()
	stay_hover.bg_color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, 0.35)
	_stay_button.add_theme_stylebox_override("hover", stay_hover)
	_stay_button.add_theme_color_override("font_color", t.text_primary)
	_stay_button.add_theme_color_override("font_hover_color", t.text_primary)
	_stay_button.add_theme_font_size_override("font_size", 13)

	# 信号连接
	_enter_button.pressed.connect(_on_enter_pressed)
	_stay_button.pressed.connect(_on_stay_pressed)

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## 显示裂隙确认弹窗
func show_rift_confirm(_cx: float = 0.0, _cy: float = 0.0) -> void:
	_active = true
	_phase = "enter"
	visible = true

	# 初始状态
	_overlay.color.a = 0.0
	_panel.scale = Vector2(0.3, 0.3)
	_panel.pivot_offset = _panel.size / 2.0
	_panel.modulate.a = 0.0
	_icon_label.modulate.a = 0.0
	_title_label.modulate.a = 0.0
	_desc_label.modulate.a = 0.0
	_enter_button.modulate.a = 0.0
	_stay_button.modulate.a = 0.0

	# 入场动画
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "color:a", 0.4, 0.35)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.35)

	var base: float = 0.12
	tw.tween_property(_icon_label, "modulate:a", 1.0, 0.3).set_delay(base) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_title_label, "modulate:a", 1.0, 0.3).set_delay(base + 0.08) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_desc_label, "modulate:a", 1.0, 0.3).set_delay(base + 0.16) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_enter_button, "modulate:a", 1.0, 0.3).set_delay(base + 0.24) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_stay_button, "modulate:a", 1.0, 0.3).set_delay(base + 0.30) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(func(): _phase = "idle")

## 关闭弹窗
func dismiss(accepted: bool) -> void:
	if not _active or _phase == "exit":
		return
	_phase = "exit"
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "color:a", 0.0, 0.22)
	tw.tween_property(_panel, "scale", Vector2(0.5, 0.5), 0.22) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.22)
	tw.tween_property(_icon_label, "modulate:a", 0.0, 0.15)
	tw.tween_property(_title_label, "modulate:a", 0.0, 0.15)
	tw.tween_property(_desc_label, "modulate:a", 0.0, 0.15)
	tw.tween_property(_enter_button, "modulate:a", 0.0, 0.15)
	tw.tween_property(_stay_button, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(func():
		_active = false
		_phase = "none"
		visible = false
		if accepted:
			rift_confirmed.emit()
		else:
			rift_cancelled.emit()
	)

func is_active() -> bool:
	return _active

# ---------------------------------------------------------------------------
# 输入处理
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _phase == "enter":
				accept_event()
				return
			# 点击面板外 = 留在原地
			var panel_rect: Rect2 = _panel.get_global_rect()
			if not panel_rect.has_point(mb.global_position):
				dismiss(false)
				accept_event()

# ---------------------------------------------------------------------------
# 按钮回调
# ---------------------------------------------------------------------------

func _on_enter_pressed() -> void:
	if _phase != "idle":
		return
	dismiss(true)

func _on_stay_pressed() -> void:
	if _phase != "idle":
		return
	dismiss(false)
