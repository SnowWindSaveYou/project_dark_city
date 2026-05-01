## PhotoPopup - 拍立得风格相片预览弹窗 (Scene 化)
## 从 EventPopup 拆分出的独立场景
## 仅预览，不结算；点击任意处关闭
class_name PhotoPopup
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal photo_popup_closed(card_type: String)

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const PHOTO_W: int = 200
const PHOTO_H: int = 260
const PHOTO_BORDER: int = 10
const PHOTO_BOTTOM: int = 40

# ---------------------------------------------------------------------------
# 节点引用
# ---------------------------------------------------------------------------
@onready var _overlay: ColorRect = $Overlay
@onready var _photo_anchor: CenterContainer = $PhotoAnchor
@onready var _photo_frame: PanelContainer = $PhotoAnchor/PhotoFrame
@onready var _image_area: PanelContainer = $PhotoAnchor/PhotoFrame/VBox/ImageArea
@onready var _icon_label: Label = $PhotoAnchor/PhotoFrame/VBox/ImageArea/ImageContent/IconLabel
@onready var _title_label: Label = $PhotoAnchor/PhotoFrame/VBox/ImageArea/ImageContent/TitleLabel
@onready var _desc_label: Label = $PhotoAnchor/PhotoFrame/VBox/ImageArea/ImageContent/DescLabel
@onready var _location_label: Label = $PhotoAnchor/PhotoFrame/VBox/BottomStrip/LocationLabel
@onready var _scout_label: Label = $PhotoAnchor/PhotoFrame/VBox/BottomStrip/ScoutLabel
@onready var _tape_decor: ColorRect = $PhotoAnchor/TapeDecor
@onready var _hint_label: Label = $HintLabel

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _active: bool = false
var _phase: String = "none"  # "enter" | "idle" | "exit"
var _card_type: String = ""
var _photo_rotation: float = 0.0

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	var t = GameTheme

	# 相片白框样式 (略带暖白)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.988, 0.980, 0.961, 0.98)
	frame_style.border_color = Color(0.824, 0.784, 0.725, 0.47)
	frame_style.set_border_width_all(1)
	frame_style.set_corner_radius_all(3)
	frame_style.content_margin_left = PHOTO_BORDER
	frame_style.content_margin_right = PHOTO_BORDER
	frame_style.content_margin_top = PHOTO_BORDER
	frame_style.content_margin_bottom = 6
	_photo_frame.add_theme_stylebox_override("panel", frame_style)
	_photo_frame.custom_minimum_size = Vector2(PHOTO_W, PHOTO_H)

	# 照片内区域样式 (暗蓝灰底色)
	var image_style := StyleBoxFlat.new()
	image_style.bg_color = Color(0.098, 0.118, 0.157, 0.94)
	image_style.border_color = Color(0, 0, 0, 0.16)
	image_style.set_border_width_all(1)
	image_style.set_corner_radius_all(0)
	image_style.set_content_margin_all(10)
	_image_area.add_theme_stylebox_override("panel", image_style)

	# 字号设置
	_icon_label.add_theme_font_size_override("font_size", 42)
	_title_label.add_theme_font_size_override("font_size", 16)
	_desc_label.add_theme_font_size_override("font_size", 10)
	_desc_label.add_theme_color_override("font_color", Color(0.784, 0.784, 0.824, 0.7))
	_location_label.add_theme_font_size_override("font_size", 12)
	_location_label.add_theme_color_override("font_color", Color(0.314, 0.294, 0.255, 0.78))
	_scout_label.add_theme_font_size_override("font_size", 10)
	_scout_label.add_theme_color_override("font_color", Color(0.588, 0.549, 0.490, 0.63))
	_hint_label.add_theme_font_size_override("font_size", 10)
	_hint_label.add_theme_color_override("font_color", Color(0.706, 0.667, 0.608, 0.7))

# ===========================================================================
# API
# ===========================================================================

## 显示相片预览弹窗
func show_photo(card: Card) -> void:
	_active = true
	_phase = "enter"
	_card_type = card.type
	_photo_rotation = randf_range(-6.0, 6.0)
	visible = true

	# 填充内容
	var darkside: Dictionary = card.get_darkside_info()
	var type_color: Color = GameTheme.card_type_color(card.type)
	var cached_desc: String = card.get_event_text()

	_icon_label.text = darkside.get("icon", "❓")
	_icon_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_title_label.text = darkside.get("label", "")
	_title_label.add_theme_color_override("font_color",
		Color(type_color.r, type_color.g, type_color.b, 0.9))
	_desc_label.text = cached_desc

	# 事件类型氛围色叠加到照片区域
	var image_style: StyleBoxFlat = _image_area.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	var base_color := Color(0.098, 0.118, 0.157, 0.94)
	var atmos := Color(type_color.r, type_color.g, type_color.b, 0.15)
	image_style.bg_color = base_color.blend(atmos)
	_image_area.add_theme_stylebox_override("panel", image_style)

	# 底部信息
	var loc_info: Dictionary = CardConfig.location_info.get(card.location, {})
	_location_label.text = loc_info.get("icon", "") + " " + loc_info.get("label", "")
	_scout_label.text = "📷 侦察"

	# 初始动画状态
	_overlay.color.a = 0.0
	_photo_frame.scale = Vector2(0.2, 0.2)
	_photo_frame.pivot_offset = _photo_frame.size / 2.0
	_photo_frame.modulate.a = 0.0
	_photo_frame.rotation = 0.0
	_icon_label.modulate.a = 0.0
	_title_label.modulate.a = 0.0
	_desc_label.modulate.a = 0.0
	_hint_label.modulate.a = 0.0

	# 胶带装饰初始
	_tape_decor.modulate.a = 0.0

	# 入场动画
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "color:a", 0.5, 0.3)
	tw.tween_property(_photo_frame, "scale", Vector2.ONE, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_photo_frame, "modulate:a", 1.0, 0.3)
	tw.tween_property(_photo_frame, "rotation", deg_to_rad(_photo_rotation), 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_tape_decor, "modulate:a", 1.0, 0.3).set_delay(0.1)

	var base: float = 0.08
	tw.tween_property(_icon_label, "modulate:a", 1.0, 0.25).set_delay(base) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_title_label, "modulate:a", 1.0, 0.25).set_delay(base + 0.06) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_desc_label, "modulate:a", 1.0, 0.25).set_delay(base + 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_hint_label, "modulate:a", 0.7, 0.25).set_delay(base + 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(func(): _phase = "idle")

## 关闭弹窗
func dismiss() -> void:
	if not _active or _phase == "exit":
		return
	_phase = "exit"
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "color:a", 0.0, 0.22)
	tw.tween_property(_photo_frame, "scale", Vector2(0.5, 0.5), 0.22) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_photo_frame, "modulate:a", 0.0, 0.22)
	tw.tween_property(_icon_label, "modulate:a", 0.0, 0.15)
	tw.tween_property(_title_label, "modulate:a", 0.0, 0.15)
	tw.tween_property(_desc_label, "modulate:a", 0.0, 0.15)
	tw.tween_property(_hint_label, "modulate:a", 0.0, 0.15)
	tw.tween_property(_tape_decor, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(func():
		_active = false
		_phase = "none"
		visible = false
		photo_popup_closed.emit(_card_type)
		_card_type = ""
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
			# 点击任意处关闭
			dismiss()
			accept_event()
