## ConsumableItemBtn - 道具格子按钮（节点版）
## Button 包含 TextureRect（有贴图时）或 EmojiLabel（fallback）
## 数量通过 BadgeLabel 覆盖，名称通过 NameLabel 显示
class_name ConsumableItemBtn
extends VBoxContainer

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal item_used(key: String)

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const ICON_SIZE: float = 40.0

# ---------------------------------------------------------------------------
# @onready
# ---------------------------------------------------------------------------
@onready var _item_btn: Button        = $ItemBtn
@onready var _icon_texture: TextureRect = $ItemBtn/IconTexture
@onready var _emoji_label: Label      = $ItemBtn/EmojiLabel
@onready var _badge_label: Label      = $ItemBtn/BadgeLabel
@onready var _name_label: Label       = $NameLabel

# ---------------------------------------------------------------------------
# 数据
# ---------------------------------------------------------------------------
var _entry: Dictionary = {}
var _tooltip_text: String = ""

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	_apply_styles()
	_item_btn.pressed.connect(func() -> void: _on_pressed())
	_item_btn.mouse_entered.connect(func() -> void: _on_hover(true))
	_item_btn.mouse_exited.connect(func() -> void: _on_hover(false))

func _apply_styles() -> void:
	var t: Node = get_node("/root/GameTheme")

	# 图标按钮外框样式
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(t.notebook_border, 0.11)
	sb_normal.set_border_width_all(1)
	sb_normal.border_color = Color(t.notebook_border, 0.27)
	sb_normal.set_corner_radius_all(6)

	var sb_hover := StyleBoxFlat.new()
	sb_hover.bg_color = Color(0.29, 0.64, 0.89, 0.11)
	sb_hover.set_border_width_all(1)
	sb_hover.border_color = Color(t.notebook_border, 0.47)
	sb_hover.set_corner_radius_all(6)

	var sb_pressed := sb_hover.duplicate()
	sb_pressed.bg_color = Color(0.29, 0.64, 0.89, 0.20)

	_item_btn.add_theme_stylebox_override("normal",  sb_normal)
	_item_btn.add_theme_stylebox_override("hover",   sb_hover)
	_item_btn.add_theme_stylebox_override("pressed", sb_pressed)
	_item_btn.add_theme_stylebox_override("focus",   sb_normal)

	# Emoji 字号
	_emoji_label.add_theme_font_size_override("font_size", 20)

	# 角标样式
	var badge_sb := StyleBoxFlat.new()
	badge_sb.bg_color = Color(t.info, 0.82)
	badge_sb.set_corner_radius_all(6)
	_badge_label.add_theme_stylebox_override("normal", badge_sb)
	_badge_label.add_theme_font_size_override("font_size", 7)
	_badge_label.add_theme_color_override("font_color", Color.WHITE)

	# 名称小字
	_name_label.add_theme_font_size_override("font_size", 9)
	_name_label.add_theme_color_override("font_color", Color(t.text_secondary, 0.63))

# ---------------------------------------------------------------------------
# 注入数据
# ---------------------------------------------------------------------------
func set_entry(entry: Dictionary, tooltip: String = "") -> void:
	_entry        = entry
	_tooltip_text = tooltip

	var info: Dictionary = entry.get("info", {})
	var count: int = entry.get("count", 1)

	# 贴图图标
	var icon_key: String = info.get("icon_key", "")
	if icon_key != "":
		var tex: Texture2D = ItemIcons.get_texture(icon_key) if has_node("/root/ItemIcons") else null
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

	# 名称
	_name_label.text = info.get("label", "")

	# Tooltip
	if tooltip != "":
		_item_btn.tooltip_text = tooltip
	else:
		# 自动生成 tooltip
		var effects: Array = info.get("effects", [])
		var parts: Array[String] = []
		for eff: Array in effects:
			if eff.size() >= 2:
				if eff[0] == "exorcism":
					parts.append("驱除怪物")
				else:
					var res_names: Dictionary = {"san": "理智", "order": "秩序", "film": "胶卷"}
					var rn: String = res_names.get(eff[0], str(eff[0]))
					var sign: String = "+" if int(eff[1]) > 0 else ""
					parts.append(rn + sign + str(eff[1]))
		_item_btn.tooltip_text = " / ".join(parts)

# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------
func _on_pressed() -> void:
	var key: String = _entry.get("key", "")
	if key != "":
		item_used.emit(key)

func _on_hover(hovered: bool) -> void:
	# hover 时轻微放大
	var target_scale: Vector2 = Vector2(1.08, 1.08) if hovered else Vector2.ONE
	var tw: Tween = create_tween()
	tw.tween_property(_item_btn, "scale", target_scale, 0.1)
