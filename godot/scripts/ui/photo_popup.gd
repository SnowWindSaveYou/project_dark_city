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
const PHOTO_W: int = 520
const PHOTO_H: int = 720
const PHOTO_BORDER: int = 22

# ---------------------------------------------------------------------------
# 节点引用
# ---------------------------------------------------------------------------
@onready var _overlay: ColorRect = $Overlay
@onready var _photo_anchor: CenterContainer = $PhotoAnchor
@onready var _photo_frame: PanelContainer = $PhotoAnchor/PhotoFrame
@onready var _image_area: Control = $PhotoAnchor/PhotoFrame/VBox/ImageArea
@onready var _bg_fill: ColorRect = $PhotoAnchor/PhotoFrame/VBox/ImageArea/BgFill
@onready var _event_texture: TextureRect = $PhotoAnchor/PhotoFrame/VBox/ImageArea/EventTexture
@onready var _icon_label: Label = $PhotoAnchor/PhotoFrame/VBox/ImageArea/IconLabel
@onready var _scout_badge: Label = $PhotoAnchor/PhotoFrame/VBox/ImageArea/ScoutBadge
@onready var _chibi_overlay: TextureRect = $PhotoAnchor/PhotoFrame/VBox/ImageArea/ChibiOverlay
@onready var _white_bottom: VBoxContainer = $PhotoAnchor/PhotoFrame/VBox/WhiteBottomMargin/WhiteBottom
@onready var _title_label: Label = $PhotoAnchor/PhotoFrame/VBox/WhiteBottomMargin/WhiteBottom/TitleLocRow/TitleLabel
@onready var _sep_label: Label = $PhotoAnchor/PhotoFrame/VBox/WhiteBottomMargin/WhiteBottom/TitleLocRow/SepLabel
@onready var _location_label: Label = $PhotoAnchor/PhotoFrame/VBox/WhiteBottomMargin/WhiteBottom/TitleLocRow/LocationLabel
@onready var _baiiye_sep: HSeparator = $PhotoAnchor/PhotoFrame/VBox/WhiteBottomMargin/WhiteBottom/BaiyeSep
@onready var _baiiye_row: HBoxContainer = $PhotoAnchor/PhotoFrame/VBox/WhiteBottomMargin/WhiteBottom/BaiyeRow
@onready var _baiiye_label: Label = $PhotoAnchor/PhotoFrame/VBox/WhiteBottomMargin/WhiteBottom/BaiyeRow/BaiyeLabel
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

	# 相片白框 — 拍立得风格，四边均匀留白
	# 上/左/右留白相等，底部留白更大（拍立得特征）
	var frame_style: StyleBoxFlat = StyleBoxFlat.new()
	frame_style.bg_color = Color(0.990, 0.982, 0.965, 0.99)
	frame_style.border_color = Color(0.82, 0.78, 0.72, 0.35)
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(5)
	frame_style.content_margin_left = PHOTO_BORDER
	frame_style.content_margin_right = PHOTO_BORDER
	frame_style.content_margin_top = PHOTO_BORDER
	frame_style.content_margin_bottom = PHOTO_BORDER
	_photo_frame.add_theme_stylebox_override("panel", frame_style)
	_photo_frame.custom_minimum_size = Vector2(PHOTO_W, PHOTO_H)

	# 照片内区域背景 — 深色底，图片贴满（Control 无 content margin，直接显示）
	_bg_fill.color = Color(0.10, 0.12, 0.16, 0.96)

	# 侦察角标 — 图片右下角，半透明小字
	_scout_badge.add_theme_font_size_override("font_size", 22)
	_scout_badge.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 0.70))

	# 无插画时大 emoji 居中
	_icon_label.add_theme_font_size_override("font_size", 110)

	# 白边：标题 — 与地点同行，类型主色（颜色在 show_photo 里按类型设）
	_title_label.add_theme_font_size_override("font_size", 30)

	# 白边：分隔点 — 居中显示，灰色
	_sep_label.add_theme_font_size_override("font_size", 26)
	_sep_label.add_theme_color_override("font_color", Color(0.60, 0.57, 0.52, 0.50))

	# 白边：地点 — 小字，灰棕色
	_location_label.add_theme_font_size_override("font_size", 24)
	_location_label.add_theme_color_override("font_color", Color(0.46, 0.43, 0.38, 0.75))

	# 分割线颜色
	var sep_style: StyleBoxFlat = StyleBoxFlat.new()
	sep_style.bg_color = Color(0.75, 0.70, 0.62, 0.30)
	_baiiye_sep.add_theme_stylebox_override("separator", sep_style)

	# 白夜台词 — 斜体感偏色小字
	_baiiye_label.add_theme_font_size_override("font_size", 24)
	_baiiye_label.add_theme_color_override("font_color", Color(0.46, 0.44, 0.62, 0.82))

	# 白边内间距
	_white_bottom.add_theme_constant_override("separation", 6)

	# 提示文字
	_hint_label.add_theme_font_size_override("font_size", 26)
	_hint_label.add_theme_color_override("font_color", Color(0.70, 0.66, 0.60, 0.60))

# ===========================================================================
# API
# ===========================================================================

## 显示相片预览弹窗
## chibi_tex_path: 怪物 chibi 贴图路径，非空时叠加在图片右下区域
func show_photo(card: Card, chibi_tex_path: String = "") -> void:
	_active = true
	_phase = "enter"
	_card_type = card.type
	_photo_rotation = randf_range(-5.0, 5.0)
	visible = true

	var darkside: Dictionary = card.get_darkside_info()
	var type_color: Color = GameTheme.card_type_color(card.type)
	var tmpl: Dictionary = CardConfig.pick_event_template(card.type, card.location, card.trap_subtype)

	# 标题（白边区，类型主色暗化）
	_title_label.text = tmpl.get("title", darkside.get("label", "未知事件"))
	var tc: Color = type_color
	_title_label.add_theme_color_override("font_color",
		Color(tc.r * 0.55, tc.g * 0.55, tc.b * 0.55, 0.95))

	# 地点
	var loc_info: Dictionary = CardConfig.location_info.get(card.location, {})
	_location_label.text = loc_info.get("icon", "") + "  " + loc_info.get("label", "")

	# 事件插画
	var tex: Texture2D = CardImageMap.get_event_texture(card.location, card.type)
	if tex != null:
		_event_texture.texture = tex
		_event_texture.visible = true
		_icon_label.visible = false
	else:
		_event_texture.visible = false
		_icon_label.visible = true
		_icon_label.text = darkside.get("icon", "❓")
		_icon_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))

	# 照片区氛围色叠加（轻微类型染色）
	var base: Color = Color(0.10, 0.12, 0.16, 0.96)
	var atmos: Color = Color(tc.r, tc.g, tc.b, 0.10)
	_bg_fill.color = base.blend(atmos)

	# 怪物/陷阱 chibi 叠加层
	var has_chibi: bool = chibi_tex_path != ""
	if has_chibi:
		var chibi_tex: Texture2D = load(chibi_tex_path) as Texture2D
		if chibi_tex != null:
			_chibi_overlay.texture = chibi_tex
			_chibi_overlay.visible = true
			_chibi_overlay.modulate.a = 0.0
		else:
			has_chibi = false
			_chibi_overlay.visible = false
	else:
		_chibi_overlay.visible = false

	# 白夜台词（白边底部，分割线之后）
	var baiiye_text: String = tmpl.get("baiiye", "")
	if baiiye_text != "":
		_baiiye_label.text = baiiye_text
		_baiiye_sep.visible = true
		_baiiye_row.visible = true
		_baiiye_sep.modulate.a = 0.0
		_baiiye_row.modulate.a = 0.0
	else:
		_baiiye_sep.visible = false
		_baiiye_row.visible = false

	# 初始动画状态
	_overlay.color.a = 0.0
	_photo_frame.scale = Vector2(0.15, 0.15)
	_photo_frame.pivot_offset = _photo_frame.size / 2.0
	_photo_frame.modulate.a = 0.0
	_photo_frame.rotation = 0.0
	# 标题行（标题+分隔+地点同行，一起淡入）
	_title_label.modulate.a = 0.0
	_sep_label.modulate.a = 0.0
	_location_label.modulate.a = 0.0
	_scout_badge.modulate.a = 0.0
	_hint_label.modulate.a = 0.0
	_tape_decor.modulate.a = 0.0
	if not _event_texture.visible:
		_icon_label.modulate.a = 0.0

	# 入场动画
	var tw: Tween = create_tween()
	tw.set_parallel(true)

	tw.tween_property(_overlay, "color:a", 0.52, 0.28)
	tw.tween_property(_photo_frame, "scale", Vector2.ONE, 0.32) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_photo_frame, "modulate:a", 1.0, 0.28)
	tw.tween_property(_photo_frame, "rotation", deg_to_rad(_photo_rotation), 0.32) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_tape_decor, "modulate:a", 1.0, 0.28).set_delay(0.08)

	if not _event_texture.visible:
		tw.tween_property(_icon_label, "modulate:a", 1.0, 0.24).set_delay(0.10) \
			.set_ease(Tween.EASE_OUT)

	tw.tween_property(_scout_badge, "modulate:a", 1.0, 0.22).set_delay(0.14)

	# chibi 叠加层：比背景图稍晚淡入，并从下方弹起
	if has_chibi:
		_chibi_overlay.position.y = 30.0
		tw.tween_property(_chibi_overlay, "modulate:a", 1.0, 0.30).set_delay(0.22) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(_chibi_overlay, "position:y", 0.0, 0.30).set_delay(0.22) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# 白边文字：标题行同步淡入（标题+分隔点+地点）
	tw.tween_property(_title_label, "modulate:a", 1.0, 0.26).set_delay(0.20) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_sep_label, "modulate:a", 1.0, 0.26).set_delay(0.20) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_location_label, "modulate:a", 1.0, 0.26).set_delay(0.20) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# 白夜台词最后淡入（彩蛋感）
	if baiiye_text != "":
		tw.tween_property(_baiiye_sep, "modulate:a", 1.0, 0.20).set_delay(0.34)
		tw.tween_property(_baiiye_row, "modulate:a", 1.0, 0.26).set_delay(0.38) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	tw.tween_property(_hint_label, "modulate:a", 0.60, 0.22).set_delay(0.32)
	tw.chain().tween_callback(func(): _phase = "idle")

## 关闭弹窗
func dismiss() -> void:
	if not _active or _phase == "exit":
		return
	_phase = "exit"
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "color:a", 0.0, 0.20)
	tw.tween_property(_photo_frame, "scale", Vector2(0.45, 0.45), 0.20) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_photo_frame, "modulate:a", 0.0, 0.20)
	tw.tween_property(_title_label, "modulate:a", 0.0, 0.14)
	tw.tween_property(_sep_label, "modulate:a", 0.0, 0.14)
	tw.tween_property(_location_label, "modulate:a", 0.0, 0.14)
	tw.tween_property(_scout_badge, "modulate:a", 0.0, 0.12)
	tw.tween_property(_hint_label, "modulate:a", 0.0, 0.14)
	tw.tween_property(_tape_decor, "modulate:a", 0.0, 0.14)
	if _icon_label.visible:
		tw.tween_property(_icon_label, "modulate:a", 0.0, 0.14)
	if _chibi_overlay.visible:
		tw.tween_property(_chibi_overlay, "modulate:a", 0.0, 0.12)
	if _baiiye_row.visible:
		tw.tween_property(_baiiye_sep, "modulate:a", 0.0, 0.10)
		tw.tween_property(_baiiye_row, "modulate:a", 0.0, 0.12)
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
			dismiss()
			accept_event()
