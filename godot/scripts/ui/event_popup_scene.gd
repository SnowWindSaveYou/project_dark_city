## EventPopupScene - 模态事件弹窗 (Scene 化)
## 替代原 EventPopup 中的模态弹窗 + Toast 功能
## 裂隙确认已拆分为 RiftPopup，相片预览已拆分为 PhotoPopup
class_name EventPopupScene
extends Control

# ---------------------------------------------------------------------------
# Toast 数据结构 (保持原有 API 兼容)
# ---------------------------------------------------------------------------
class ToastData:
	var card_type: String = "safe"
	var title: String = ""
	var desc: String = ""
	var icon: String = ""
	var effects: Dictionary = {}
	var shield_used: bool = false
	var trap_subtype: String = ""
	var location: String = ""

	func _init(p_card_type: String = "safe") -> void:
		card_type = p_card_type

	func set_title(p_title: String) -> ToastData:
		title = p_title
		return self

	func set_desc(p_desc: String) -> ToastData:
		desc = p_desc
		return self

	func set_icon(p_icon: String) -> ToastData:
		icon = p_icon
		return self

	func set_effects(p_effects: Dictionary) -> ToastData:
		effects = p_effects
		return self

	func set_shield_used(p_used: bool) -> ToastData:
		shield_used = p_used
		return self

	func set_trap_subtype(p_subtype: String) -> ToastData:
		trap_subtype = p_subtype
		return self

	func set_location(p_location: String) -> ToastData:
		location = p_location
		return self

	func to_dict() -> Dictionary:
		return {
			"card_type": card_type,
			"title": title,
			"desc": desc,
			"icon": icon,
			"effects": effects,
			"shield_used": shield_used,
			"trap_subtype": trap_subtype,
			"location": location,
		}

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal popup_closed(card: Card)
signal toast_dismissed(card_type: String)

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const TOAST_MAX: int = 3
const TOAST_ITEM_SCENE: String = "res://scenes/ui/components/toast_item.tscn"

## 阻塞判定 (保持兼容)
const BLOCKING_EVENTS: Dictionary = {
	"shop": true,
}

static func is_blocking_event(card_type: String, _has_choices: bool = false) -> bool:
	if card_type in BLOCKING_EVENTS:
		return true
	return false

# ---------------------------------------------------------------------------
# 节点引用
# ---------------------------------------------------------------------------
@onready var _overlay: ColorRect = $Overlay
@onready var _panel: PanelContainer = $PanelAnchor/Panel
@onready var _vbox: VBoxContainer = $PanelAnchor/Panel/VBox
@onready var _color_bar: ColorRect = $PanelAnchor/Panel/VBox/ColorBar
@onready var _icon_label: Label = $PanelAnchor/Panel/VBox/IconLabel
@onready var _title_label: Label = $PanelAnchor/Panel/VBox/TitleLabel
@onready var _desc_label: Label = $PanelAnchor/Panel/VBox/DescLabel
@onready var _effects_row: HBoxContainer = $PanelAnchor/Panel/VBox/EffectsRow
@onready var _hint_label: Label = $PanelAnchor/Panel/VBox/HintLabel
@onready var _toast_container: VBoxContainer = $ToastContainer

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _active: bool = false
var _card: Card = null
var _phase: String = "none"  # "enter" | "idle" | "exit"
var _cached_desc: String = ""

# ---------------------------------------------------------------------------
# 预加载
# ---------------------------------------------------------------------------
var _toast_item_packed: PackedScene = null

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 模态弹窗初始隐藏（仅 show_event 时显示）
	_overlay.visible = false
	$PanelAnchor.visible = false

	# 预加载 Toast 场景
	_toast_item_packed = load(TOAST_ITEM_SCENE)

	var t = GameTheme

	# 面板样式
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(t.card_face.r, t.card_face.g, t.card_face.b, 0.95)
	panel_style.border_color = Color(t.card_border.r, t.card_border.g, t.card_border.b, 0.6)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(14)
	panel_style.set_content_margin_all(0)
	_panel.add_theme_stylebox_override("panel", panel_style)

	# 面板尺寸 — 依赖 viewport
	_panel.custom_minimum_size = Vector2(280, 220)

	# 字号和颜色
	_icon_label.add_theme_font_size_override("font_size", 42)
	_icon_label.add_theme_color_override("font_color", t.text_primary)

	_title_label.add_theme_font_size_override("font_size", 18)

	_desc_label.add_theme_font_size_override("font_size", 12)
	_desc_label.add_theme_color_override("font_color", t.text_secondary)

	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color",
		Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, 0.6))

# ---------------------------------------------------------------------------
# 关联组件引用 (由 main.gd 在实例化后注入)
# ---------------------------------------------------------------------------
var _rift_popup: Control = null   # RiftPopup 实例
var _photo_popup: Control = null  # PhotoPopup 实例

## 设置关联组件 (在 main._setup_scene_tree() 中调用)
func bind_sub_popups(rift: Control, photo: Control) -> void:
	_rift_popup = rift
	_photo_popup = photo

# ---------------------------------------------------------------------------
# 委托方法 (保持控制器代码兼容)
# ---------------------------------------------------------------------------

## 委托给 RiftPopup
func show_rift_confirm(cx: float = 0.0, cy: float = 0.0) -> void:
	if _rift_popup:
		_rift_popup.show_rift_confirm(cx, cy)

## 委托给 PhotoPopup
func show_photo(card: Card) -> void:
	if _photo_popup:
		_photo_popup.show_photo(card)

## 自适应面板大小
func _on_resized() -> void:
	if _panel:
		var vp: Vector2 = get_viewport_rect().size
		_panel.custom_minimum_size = Vector2(vp.x * 0.7, vp.y * 0.45)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_on_resized()

# ===========================================================================
# 模态弹窗 API
# ===========================================================================

## 打开事件弹窗 (常规模态)
func show_event(card: Card) -> void:
	_card = card
	_active = true
	_phase = "enter"
	_cached_desc = card.get_event_text()
	visible = true
	_overlay.visible = true
	$PanelAnchor.visible = true

	# 填充内容
	var darkside: Dictionary = card.get_darkside_info()
	var type_color: Color = GameTheme.card_type_color(card.type)

	_color_bar.color = Color(type_color.r, type_color.g, type_color.b, 0.8)
	_icon_label.text = darkside.get("icon", "❓")
	_title_label.text = darkside.get("label", "未知事件")
	_title_label.add_theme_color_override("font_color", type_color)
	_desc_label.text = _cached_desc
	_hint_label.text = "点击关闭"

	# 填充效果徽章
	_populate_effects(card.get_effects())

	# 自适应面板大小
	_on_resized()

	# 初始动画状态
	_overlay.color.a = 0.0
	_panel.scale = Vector2(0.3, 0.3)
	_panel.pivot_offset = _panel.size / 2.0
	_panel.modulate.a = 0.0
	_icon_label.modulate.a = 0.0
	_title_label.modulate.a = 0.0
	_desc_label.modulate.a = 0.0
	_effects_row.modulate.a = 0.0
	_hint_label.modulate.a = 0.0

	# 入场动画
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "color:a", 0.45, 0.35)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.35)

	# 内容逐行错时入场
	var base: float = 0.12
	var stagger: float = 0.08
	tw.tween_property(_icon_label, "modulate:a", 1.0, 0.3).set_delay(base) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_title_label, "modulate:a", 1.0, 0.3).set_delay(base + stagger) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_desc_label, "modulate:a", 1.0, 0.3).set_delay(base + stagger * 2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_effects_row, "modulate:a", 1.0, 0.25).set_delay(base + stagger * 3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_hint_label, "modulate:a", 0.6, 0.3).set_delay(base + stagger * 4) \
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
	tw.tween_property(_panel, "scale", Vector2(0.5, 0.5), 0.22) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.22)
	tw.tween_property(_icon_label, "modulate:a", 0.0, 0.15)
	tw.tween_property(_title_label, "modulate:a", 0.0, 0.15)
	tw.tween_property(_desc_label, "modulate:a", 0.0, 0.15)
	tw.tween_property(_effects_row, "modulate:a", 0.0, 0.15)
	tw.tween_property(_hint_label, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(_on_dismiss_complete)

func _on_dismiss_complete() -> void:
	_active = false
	_phase = "none"
	_overlay.visible = false
	$PanelAnchor.visible = false
	visible = _has_active_toasts()
	popup_closed.emit(_card)
	_card = null

func is_active() -> bool:
	return _active

# ===========================================================================
# 效果徽章
# ===========================================================================

func _populate_effects(effects: Dictionary) -> void:
	# 清空旧内容
	for child in _effects_row.get_children():
		child.queue_free()

	if effects.is_empty():
		return

	var t = GameTheme
	for key in effects:
		var delta_val: int = effects[key]
		var res_icon: String = GameData.RESOURCE_ICONS.get(key, "?")
		var prefix: String = "+" if delta_val > 0 else ""
		var badge_text: String = res_icon + " " + prefix + str(delta_val)

		var badge := PanelContainer.new()
		var badge_style := StyleBoxFlat.new()
		var bg_c: Color = t.safe if delta_val > 0 else t.danger
		badge_style.bg_color = Color(bg_c.r, bg_c.g, bg_c.b, 0.14)
		badge_style.border_color = Color(bg_c.r, bg_c.g, bg_c.b, 0.31)
		badge_style.set_border_width_all(1)
		badge_style.set_corner_radius_all(4)
		badge_style.content_margin_left = 6
		badge_style.content_margin_right = 6
		badge_style.content_margin_top = 2
		badge_style.content_margin_bottom = 2
		badge.add_theme_stylebox_override("panel", badge_style)

		var lbl := Label.new()
		lbl.text = badge_text
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", bg_c)
		badge.add_child(lbl)
		_effects_row.add_child(badge)

# ===========================================================================
# Toast API
# ===========================================================================

## 推送一条 Toast 通知
func show_toast(data: ToastData) -> void:
	var card_type: String = data.card_type
	var trap_subtype: String = data.trap_subtype
	var location: String = data.location

	# 文案处理
	var tmpl: Dictionary = _pick_template(card_type, trap_subtype)

	# 标题
	var display_title: String = data.title
	if display_title == "":
		display_title = tmpl["title"]
		if location != "":
			var dark_info: Dictionary = CardConfig.darkside_info.get(location, {}).get(card_type, {})
			if dark_info.has("label"):
				display_title = dark_info["label"]

	# 图标
	var display_icon: String = data.icon
	if display_icon == "":
		display_icon = GameTheme.card_type_info(card_type).get("icon", "❓")
		if card_type == "trap" and trap_subtype != "":
			var sub_info: Dictionary = CardConfig.trap_subtype_info.get(trap_subtype, {})
			if sub_info.has("icon"):
				display_icon = sub_info["icon"]

	# 描述
	var display_desc: String = data.desc
	if display_desc == "":
		display_desc = tmpl["desc"]

	var toast_dict: Dictionary = {
		"card_type": card_type,
		"title": display_title,
		"desc": display_desc,
		"icon": display_icon,
		"effects": data.effects,
		"shield_used": data.shield_used,
		"trap_subtype": trap_subtype,
	}
	_show_toast_internal(toast_dict)

## 内部方法：实例化 ToastItem 场景
func _show_toast_internal(data: Dictionary) -> void:
	visible = true

	# 实例化 ToastItem
	var toast_node: ToastItem = _toast_item_packed.instantiate() as ToastItem
	_toast_container.add_child(toast_node)
	toast_node.setup(data)

	# 连接 dismissed 信号
	toast_node.dismissed.connect(_on_toast_dismissed)

	# 限制最大数量
	_enforce_toast_limit()

func _enforce_toast_limit() -> void:
	var visible_count: int = 0
	var children: Array[Node] = _toast_container.get_children()
	for child in children:
		if child is ToastItem:
			visible_count += 1

	if visible_count > TOAST_MAX:
		# 移除最旧的
		for child in children:
			if child is ToastItem:
				var ti: ToastItem = child as ToastItem
				ti.start_exit()
				break

func _on_toast_dismissed(card_type: String) -> void:
	toast_dismissed.emit(card_type)
	# 检查是否还需要保持可见
	if not _active and not _has_active_toasts():
		visible = false

func _has_active_toasts() -> bool:
	for child in _toast_container.get_children():
		if child is ToastItem:
			return true
	return false

func is_toast_active() -> bool:
	return _has_active_toasts()

func clear_toasts() -> void:
	for child in _toast_container.get_children():
		if child is ToastItem:
			child.queue_free()

# ===========================================================================
# 全局查询
# ===========================================================================

func is_any_active() -> bool:
	return _active or _has_active_toasts()

# ===========================================================================
# 输入处理
# ===========================================================================

## 选择性命中检测
func _has_point(point: Vector2) -> bool:
	# 模态弹窗：全屏拦截
	if _active:
		return true
	# Toast：仅拦截 toast 容器区域
	if _has_active_toasts():
		return _toast_container.get_global_rect().has_point(point)
	return false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _active:
				_handle_popup_click()
				accept_event()
				return

func _handle_popup_click() -> void:
	if _phase == "enter":
		return  # 入场中不处理
	dismiss()

# ===========================================================================
# 工具方法
# ===========================================================================

func _pick_template(card_type: String, trap_subtype: String = "") -> Dictionary:
	# 陷阱子类型使用专属文案池
	if card_type == "trap" and trap_subtype != "":
		var sub_texts: Array = CardConfig.trap_subtype_texts.get(trap_subtype, [])
		if sub_texts.size() > 0:
			var text: String = sub_texts[randi() % sub_texts.size()]
			var sub_info: Dictionary = CardConfig.trap_subtype_info.get(trap_subtype, {})
			return { "title": sub_info.get("label", "陷阱"), "desc": text }

	var texts: Array = CardConfig.event_texts.get(card_type, ["发生了一些事情..."])
	var type_info: Dictionary = GameTheme.card_type_info(card_type)
	return { "title": type_info.get("label", "未知"), "desc": texts[randi() % texts.size()] }
