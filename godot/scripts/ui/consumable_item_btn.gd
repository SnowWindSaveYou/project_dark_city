## ConsumableItemBtn - 道具行（HBoxContainer 版）
## 左侧大图标按钮 + 右侧名称/描述/使用按钮
## 3× 缩放（适配 Godot 1920×1080 canvas）
class_name ConsumableItemBtn
extends HBoxContainer

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal item_used(key: String)

# ---------------------------------------------------------------------------
# 常量（×3 缩放）
# ---------------------------------------------------------------------------
const ICON_SIZE: float = 90.0

# ---------------------------------------------------------------------------
# @onready
# ---------------------------------------------------------------------------
@onready var _item_btn: Button          = $ItemBtn
@onready var _icon_texture: TextureRect = $ItemBtn/IconTexture
@onready var _emoji_label: Label        = $ItemBtn/EmojiLabel
@onready var _badge_label: Label        = $ItemBtn/BadgeLabel
@onready var _name_label: Label         = $InfoVBox/NameLabel
@onready var _desc_label: Label         = $InfoVBox/DescLabel
@onready var _use_btn: Button           = $InfoVBox/UseBtn

# ---------------------------------------------------------------------------
# 数据
# ---------------------------------------------------------------------------
var _entry: Dictionary = {}

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	_apply_styles()
	_item_btn.pressed.connect(func() -> void: _on_pressed())
	_use_btn.pressed.connect(func() -> void: _on_pressed())

func _apply_styles() -> void:
	var t: Node = get_node("/root/GameTheme")

	# 图标按钮外框样式
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(t.notebook_border, 0.08)
	sb_normal.set_border_width_all(2)
	sb_normal.border_color = Color(t.notebook_border, 0.25)
	sb_normal.set_corner_radius_all(12)

	var sb_hover := StyleBoxFlat.new()
	sb_hover.bg_color = Color(0.29, 0.64, 0.89, 0.13)
	sb_hover.set_border_width_all(2)
	sb_hover.border_color = Color(t.notebook_border, 0.45)
	sb_hover.set_corner_radius_all(12)

	var sb_pressed := sb_hover.duplicate()
	sb_pressed.bg_color = Color(0.29, 0.64, 0.89, 0.22)

	_item_btn.flat = false
	_item_btn.add_theme_stylebox_override("normal",  sb_normal)
	_item_btn.add_theme_stylebox_override("hover",   sb_hover)
	_item_btn.add_theme_stylebox_override("pressed", sb_pressed)
	_item_btn.add_theme_stylebox_override("focus",   sb_normal)
	_item_btn.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)

	# Emoji 字号（60px = 20×3）
	_emoji_label.add_theme_font_size_override("font_size", 60)

	# 角标样式（右上角数量）
	var badge_sb := StyleBoxFlat.new()
	badge_sb.bg_color = Color(t.info, 0.82)
	badge_sb.set_corner_radius_all(8)
	badge_sb.set_content_margin_all(2)
	_badge_label.add_theme_stylebox_override("normal", badge_sb)
	_badge_label.add_theme_font_size_override("font_size", 21)   # 7×3
	_badge_label.add_theme_color_override("font_color", Color.WHITE)
	_badge_label.offset_left   = ICON_SIZE - 26.0
	_badge_label.offset_top    = -4.0
	_badge_label.offset_right  = ICON_SIZE
	_badge_label.offset_bottom = 18.0

	# 名称字号（27px = 9×3）
	_name_label.add_theme_font_size_override("font_size", 27)
	_name_label.add_theme_color_override("font_color", Color(t.text_primary, 0.88))

	# 描述字号（21px = 7×3），次要色
	_desc_label.add_theme_font_size_override("font_size", 21)
	_desc_label.add_theme_color_override("font_color", Color(t.text_secondary, 0.60))

	# 使用按钮样式（小型）
	var use_sb_normal := StyleBoxFlat.new()
	use_sb_normal.bg_color = Color(0.29, 0.64, 0.89, 0.18)
	use_sb_normal.set_border_width_all(1)
	use_sb_normal.border_color = Color(0.29, 0.64, 0.89, 0.45)
	use_sb_normal.set_corner_radius_all(8)
	use_sb_normal.set_content_margin_all(4)

	var use_sb_hover := use_sb_normal.duplicate()
	use_sb_hover.bg_color = Color(0.29, 0.64, 0.89, 0.30)

	_use_btn.flat = false
	_use_btn.add_theme_stylebox_override("normal",  use_sb_normal)
	_use_btn.add_theme_stylebox_override("hover",   use_sb_hover)
	_use_btn.add_theme_stylebox_override("pressed", use_sb_hover)
	_use_btn.add_theme_stylebox_override("focus",   use_sb_normal)
	_use_btn.add_theme_font_size_override("font_size", 24)   # 8×3
	_use_btn.add_theme_color_override("font_color", Color(0.22, 0.45, 0.70, 0.90))

# ---------------------------------------------------------------------------
# 注入数据
# ---------------------------------------------------------------------------
func set_entry(entry: Dictionary) -> void:
	_entry = entry

	var info: Dictionary = entry.get("info", {})
	var count: int = entry.get("count", 1)

	# 图标：优先用 image_path 图片，失败则 fallback 到 emoji
	var image_path: String = info.get("image_path", "")
	if image_path != "" and ResourceLoader.exists(image_path):
		var tex: Texture2D = load(image_path)
		if tex:
			_icon_texture.texture = tex
			_icon_texture.visible = true
			_emoji_label.visible  = false
		else:
			_icon_texture.visible = false
			_emoji_label.visible  = true
			_emoji_label.text = info.get("icon", "🧪")
	else:
		_icon_texture.visible = false
		_emoji_label.visible  = true
		_emoji_label.text = info.get("icon", "🧪")

	# 数量角标
	if count > 1:
		_badge_label.text    = str(count)
		_badge_label.visible = true
	else:
		_badge_label.visible = false

	# 名称（data 字段为 "name"）
	_name_label.text = info.get("name", "未知道具")

	# 描述（data 字段为 "desc"）
	_desc_label.text = info.get("desc", "")

	# 数量不足时禁用使用按钮
	_use_btn.disabled = (count <= 0)

# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------
func _on_pressed() -> void:
	var key: String = _entry.get("key", "")
	if key != "" and _entry.get("count", 0) > 0:
		item_used.emit(key)
