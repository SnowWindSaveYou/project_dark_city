## EventPopup - 事件弹窗
## 对应原版 EventPopup.lua
## 翻开卡牌后展示事件信息的弹窗
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal popup_closed(card: Card)
signal photo_popup_closed(card_type: String)

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _active := false
var _card: Card = null
var _phase := "none"  # "enter" | "idle" | "exit"
var _is_photo_mode := false  # 拍照模式 (翻看后翻回)
var _photo_card_type := ""   # 拍照模式下的卡牌类型

# 动画值
var _overlay_alpha := 0.0
var _panel_scale := 0.0
var _panel_alpha := 0.0
var _content_alpha := 0.0
var _button_alpha := 0.0

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## 拍照模式弹窗 (偷看卡牌后翻回)
func show_photo(card: Card) -> void:
	_is_photo_mode = true
	_photo_card_type = card.type
	show_event(card)

func show_event(card: Card) -> void:
	_card = card
	_active = true
	_phase = "enter"
	visible = true

	# 重置动画
	_overlay_alpha = 0.0
	_panel_scale = 0.6
	_panel_alpha = 0.0
	_content_alpha = 0.0
	_button_alpha = 0.0

	# 入场动画用 Tween
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_overlay_alpha", 0.5, 0.3)
	tw.tween_property(self, "_panel_scale", 1.0, 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_panel_alpha", 1.0, 0.3)
	tw.tween_property(self, "_content_alpha", 1.0, 0.4).set_delay(0.15)
	tw.tween_property(self, "_button_alpha", 1.0, 0.3).set_delay(0.35)
	tw.chain().tween_callback(func(): _phase = "idle")

func dismiss() -> void:
	if not _active or _phase == "exit":
		return
	_phase = "exit"
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_overlay_alpha", 0.0, 0.25)
	tw.tween_property(self, "_panel_scale", 0.9, 0.2)
	tw.tween_property(self, "_panel_alpha", 0.0, 0.2)
	tw.chain().tween_callback(_on_dismiss_complete)

func _on_dismiss_complete() -> void:
	_active = false
	visible = false
	_phase = "none"
	if _is_photo_mode:
		_is_photo_mode = false
		photo_popup_closed.emit(_photo_card_type)
		_photo_card_type = ""
	else:
		popup_closed.emit(_card)
	_card = null

func is_active() -> bool:
	return _active

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _phase == "idle":
				dismiss()
			accept_event()

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _active:
		queue_redraw()

func _draw() -> void:
	if not _active or _card == null:
		return

	var vp := get_viewport_rect().size
	var t = Theme  # Autoload
	var font := ThemeDB.fallback_font

	# 遮罩
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, _overlay_alpha))

	# 面板
	var panel_w := vp.x * 0.7
	var panel_h := vp.y * 0.55
	var panel_x := (vp.x - panel_w * _panel_scale) / 2.0
	var panel_y := (vp.y - panel_h * _panel_scale) / 2.0

	# 面板背景
	var panel_color := Color(t.card_face.r, t.card_face.g, t.card_face.b, _panel_alpha * 0.95)
	draw_rect(Rect2(panel_x, panel_y, panel_w * _panel_scale, panel_h * _panel_scale), panel_color)

	# 面板边框
	var border_color := Color(t.card_border.r, t.card_border.g, t.card_border.b, _panel_alpha * 0.6)
	draw_rect(Rect2(panel_x, panel_y, panel_w * _panel_scale, panel_h * _panel_scale), border_color, false, 2.0)

	if _content_alpha < 0.01:
		return

	# 内容区域
	var cx := vp.x / 2.0
	var cy := vp.y / 2.0
	var content_color := Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, _content_alpha)

	# 类型色条
	var type_color := t.card_type_color(_card.type)
	type_color.a = _content_alpha * 0.8
	draw_rect(Rect2(panel_x + 8, panel_y + 8, panel_w * _panel_scale - 16, 16), type_color)

	# 事件图标
	var darkside := _card.get_darkside_info()
	draw_string(font, Vector2(cx - 20, cy - 40), darkside.get("icon", "❓"),
		HORIZONTAL_ALIGNMENT_CENTER, -1, 48, content_color)

	# 事件名称
	var label_text: String = darkside.get("label", "未知事件")
	draw_string(font, Vector2(cx, cy), label_text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 20, content_color)

	# 事件描述
	var desc_color := Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, _content_alpha)
	var desc := _card.get_event_text()
	draw_string(font, Vector2(cx, cy + 30), desc,
		HORIZONTAL_ALIGNMENT_CENTER, panel_w * 0.8, 13, desc_color)

	# 效果
	var effects := _card.get_effects()
	var ey := cy + 60
	for key in effects:
		var delta_val: int = effects[key]
		var prefix := "+" if delta_val > 0 else ""
		var icon: String = GameData.RESOURCE_ICONS.get(key, "")
		var effect_text := icon + " " + prefix + str(delta_val)
		var effect_color := t.safe if delta_val > 0 else t.danger
		effect_color.a = _content_alpha
		draw_string(font, Vector2(cx, ey), effect_text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 14, effect_color)
		ey += 22

	# 关闭按钮/提示
	if _button_alpha > 0.01:
		var btn_color := Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, _button_alpha * 0.6)
		draw_string(font, Vector2(cx, panel_y + panel_h * _panel_scale - 24), "点击关闭",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, btn_color)
