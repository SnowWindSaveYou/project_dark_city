## EventPopupScene - 笔记本+拍立得风格事件弹窗 (Scene 化)
## 布局对齐 Lua 版: 笔记本底板 + 左侧倾斜拍立得卡 + 右侧文字区
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

# 笔记本尺寸（对应 Lua 版 NB_W/NB_H 的缩放值，1px Lua ≈ 4px Godot @1080p）
const NB_W: int = 900
const NB_H: int = 540

# 拍立得卡内图区尺寸
const POL_IMG_W: int = 190
const POL_IMG_H: int = 267

## 阻塞判定
static func is_blocking_event(card_type: String, _has_choices: bool = false) -> bool:
	return EventPool.is_blocking_type(card_type)

# ---------------------------------------------------------------------------
# 节点引用（对应新 tscn 结构）
# ---------------------------------------------------------------------------
@onready var _overlay: ColorRect = $Overlay
@onready var _notebook: PanelContainer = $PanelAnchor/Notebook
@onready var _notebook_decor: Control = $PanelAnchor/Notebook/NotebookDecor
@onready var _polaroid_area: Control = $PanelAnchor/Notebook/OuterVBox/HBox/PolaroidArea
@onready var _polaroid_card: PanelContainer = $PanelAnchor/Notebook/OuterVBox/HBox/PolaroidArea/PolaroidCard
@onready var _event_texture: TextureRect = $PanelAnchor/Notebook/OuterVBox/HBox/PolaroidArea/PolaroidCard/PolaroidVBox/EventTexture
@onready var _card_bottom: HBoxContainer = $PanelAnchor/Notebook/OuterVBox/HBox/PolaroidArea/PolaroidCard/PolaroidVBox/CardBottom
@onready var _type_label: Label = $PanelAnchor/Notebook/OuterVBox/HBox/PolaroidArea/PolaroidCard/PolaroidVBox/CardBottom/TypeLabel
@onready var _location_label: Label = $PanelAnchor/Notebook/OuterVBox/HBox/PolaroidArea/PolaroidCard/PolaroidVBox/CardBottom/LocationLabel
@onready var _right_vbox: VBoxContainer = $PanelAnchor/Notebook/OuterVBox/HBox/RightVBox
@onready var _title_label: Label = $PanelAnchor/Notebook/OuterVBox/HBox/RightVBox/TitleLabel
@onready var _effects_row: HBoxContainer = $PanelAnchor/Notebook/OuterVBox/HBox/RightVBox/EffectsRow
@onready var _desc_scroll: ScrollContainer = $PanelAnchor/Notebook/OuterVBox/HBox/RightVBox/DescScroll
@onready var _desc_label: Label = $PanelAnchor/Notebook/OuterVBox/HBox/RightVBox/DescScroll/ContentVBox/DescLabel
@onready var _baiiye_label: Label = $PanelAnchor/Notebook/OuterVBox/HBox/RightVBox/DescScroll/ContentVBox/BaiyeLabel
@onready var _confirm_button: PanelContainer = $PanelAnchor/Notebook/OuterVBox/ConfirmButton
@onready var _confirm_label: Label = $PanelAnchor/Notebook/OuterVBox/ConfirmButton/ConfirmLabel
@onready var _toast_container: VBoxContainer = $ToastContainer

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _active: bool = false
var _card: Card = null
var _phase: String = "none"  # "enter" | "idle" | "exit"
var _photo_rotation_deg: float = 0.0

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

	_overlay.visible = false
	$PanelAnchor.visible = false

	_toast_item_packed = load(TOAST_ITEM_SCENE)

	# 笔记本稿纸装饰（红色边距竖线 + 蓝色横线）
	_notebook_decor.draw.connect(_draw_notebook_decor)
	_notebook.resized.connect(func(): _notebook_decor.queue_redraw())

	# 笔记本/拍立得样式已写入 tscn sub_resource，运行时保持 custom_minimum_size 即可
	_notebook.custom_minimum_size = Vector2(NB_W, NB_H)

	# 笔记本/拍立得/标题/描述/字号/间距等静态样式已移至 event_popup.tscn 的 sub_resource，
	# 编辑器与运行时均可见，这里无需重复赋值。

	# 确认按钮样式（绿色胶囊）
	_style_confirm_button(false)
	_confirm_label.add_theme_font_size_override("font_size", 40)
	_confirm_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))

	# 确认按钮点击：PanelContainer mouse_filter=STOP 会消耗事件，
	# 父节点 _gui_input 收不到，需直接连接子节点 gui_input 信号。
	_confirm_button.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT \
					and _active and _phase != "enter":
				_style_confirm_button(true)
				dismiss()
	)

	# 拍立得尺寸由 tscn 的 Inspector 直接设置，_update_polaroid_layout 仅在 resize 时刷新样式边距
	# _update_polaroid_layout()  # ← 如需代码驱动尺寸再打开

# ---------------------------------------------------------------------------
# 关联组件引用
# ---------------------------------------------------------------------------
var _rift_popup: Control = null
var _photo_popup: Control = null

func bind_sub_popups(rift: Control, photo: Control) -> void:
	_rift_popup = rift
	_photo_popup = photo

# ---------------------------------------------------------------------------
# 委托方法
# ---------------------------------------------------------------------------

func show_rift_confirm(cx: float = 0.0, cy: float = 0.0) -> void:
	if _rift_popup:
		_rift_popup.show_rift_confirm(cx, cy)

func show_custom_confirm(icon: String, title: String, desc: String,
		btn_yes: String, btn_no: String, accent: Color) -> RiftPopup:
	if _rift_popup:
		_rift_popup.show_custom_confirm(icon, title, desc, btn_yes, btn_no, accent)
		return _rift_popup as RiftPopup
	return null

func show_photo(card: Card) -> void:
	if _photo_popup:
		_photo_popup.show_photo(card)

func show_photo_with_chibi(card: Card, monster_tex_path: String) -> void:
	if _photo_popup:
		_photo_popup.show_photo(card, monster_tex_path)

# ===========================================================================
# 模态弹窗 API
# ===========================================================================

## 非阻断事件弹窗（新路径）：笔记本+拍立得布局
func show_event_data(
		card_type: String,
		effects: Dictionary,
		shield_used: bool,
		location: String = "",
		trap_subtype: String = "") -> void:
	_active = true
	_phase = "enter"
	visible = true
	_overlay.visible = true
	$PanelAnchor.visible = true
	AudioManager.play_sfx("popup_open")

	_photo_rotation_deg = randf_range(-5.0, 5.0)

	var tmpl: Dictionary = CardConfig.pick_event_template(card_type, location, trap_subtype)
	var type_color: Color = GameTheme.card_type_color(card_type)
	var type_info: Dictionary = GameTheme.card_type_info(card_type)
	var dark_display: Dictionary = Locations.get_dark_display(location)
	var dark_info: Dictionary = dark_display.get(card_type, {})

	# --- 拍立得内容 ---
	_load_event_image(location, card_type)

	# 拍立得底部：事件类型 + 地点
	var type_icon: String = type_info.get("icon", "✨")
	var type_name: String = dark_info.get("label", type_info.get("label", card_type))
	_type_label.text = type_icon + " " + type_name
	_type_label.add_theme_color_override("font_color",
		Color(type_color.r, type_color.g, type_color.b, 0.82))

	var loc_info: Dictionary = CardConfig.location_info.get(location, {})
	var loc_text: String = loc_info.get("icon", "") + " " + loc_info.get("label", "")
	_location_label.text = loc_text.strip_edges()
	_location_label.add_theme_color_override("font_color", Color(0.314, 0.294, 0.255, 0.72))
	_location_label.visible = not loc_text.strip_edges().is_empty()
	($PanelAnchor/Notebook/OuterVBox/HBox/PolaroidArea/PolaroidCard/PolaroidVBox/CardBottom/CardBottomSep as Label).visible = _location_label.visible

	# 设置拍立得旋转，并通知 NotebookDecor 更新阴影位置
	_polaroid_card.rotation = deg_to_rad(_photo_rotation_deg)
	_notebook_decor.queue_redraw()

	# --- 右侧文字区 ---
	_title_label.text = tmpl.get("title", dark_info.get("label", "未知事件"))
	_title_label.add_theme_color_override("font_color",
		Color(type_color.r, type_color.g, type_color.b, 0.90))

	_populate_effects(effects, shield_used)

	_desc_label.text = tmpl.get("desc", "")
	_desc_scroll.call_deferred("set", "scroll_vertical", 0)

	# 白夜台词
	var baiiye_text: String = tmpl.get("baiiye", "")
	if baiiye_text != "":
		_baiiye_label.text = "— " + baiiye_text
		_baiiye_label.visible = true
		_baiiye_label.modulate.a = 0.0
	else:
		_baiiye_label.visible = false

	_confirm_label.text = "知道了"
	_style_confirm_button(false)

	# 按事件类型播放对应音效（对齐 Lua 版 CardInteraction 的 sfxMap 分发逻辑）
	var evt_sfx_map: Dictionary = {
		"safe":    "evt_safe",
		"trap":    "evt_trap",
		"reward":  "evt_reward",
		"clue":    "evt_clue",
		"plot":    "evt_plot",
		"monster": "evt_monster",
	}
	var evt_sfx: String = evt_sfx_map.get(card_type, "")
	if evt_sfx != "":
		AudioManager.play_sfx(evt_sfx)

	_run_enter_animation(baiiye_text != "")

## 碎片收集弹窗：展示前世记忆全文
func show_fragment(frag_info: Dictionary) -> void:
	_active = true
	_phase = "enter"
	visible = true
	_overlay.visible = true
	$PanelAnchor.visible = true
	AudioManager.play_sfx("popup_open")

	_photo_rotation_deg = randf_range(-4.0, 4.0)
	var accent: Color = Color(0.855, 0.714, 0.278)  # 金黄色

	# 拍立得：无插画，隐藏图片区
	_event_texture.texture = null
	_event_texture.visible = false

	# 拍立得底部：碎片类型标签
	_type_label.text = "🌙 前世碎片"
	_type_label.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.82))
	_location_label.visible = false
	($PanelAnchor/Notebook/OuterVBox/HBox/PolaroidArea/PolaroidCard/PolaroidVBox/CardBottom/CardBottomSep as Label).visible = false

	_polaroid_card.rotation = deg_to_rad(_photo_rotation_deg)
	_notebook_decor.queue_redraw()

	# 右侧文字区
	_title_label.text = frag_info.get("name", "前世碎片")
	_title_label.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.90))
	_populate_effects({}, false)
	_desc_label.text = frag_info.get("full_text", frag_info.get("desc", ""))
	_desc_scroll.call_deferred("set", "scroll_vertical", 0)
	_baiiye_label.visible = false
	_confirm_label.text = "收下记忆"
	_style_confirm_button(false)

	_run_enter_animation(false)

## 旧签名（供 shop 等阻断型事件使用）
func show_event(card: Card) -> void:
	_card = card
	_active = true
	_phase = "enter"
	visible = true
	_overlay.visible = true
	$PanelAnchor.visible = true
	AudioManager.play_sfx("popup_open")

	_photo_rotation_deg = randf_range(-4.0, 4.0)

	var type_color: Color = GameTheme.card_type_color(card.type)
	var type_info: Dictionary = GameTheme.card_type_info(card.type)
	var darkside: Dictionary = card.get_darkside_info()

	# 拍立得：shop 无插画，显示 emoji 占位
	_event_texture.texture = null
	_event_texture.visible = false
	# 底部类型+地点
	_type_label.text = type_info.get("icon", "❓") + " " + darkside.get("label", card.type)
	_type_label.add_theme_color_override("font_color",
		Color(type_color.r, type_color.g, type_color.b, 0.82))
	var loc_info: Dictionary = CardConfig.location_info.get(card.location, {})
	var loc_text: String = loc_info.get("icon", "") + " " + loc_info.get("label", "")
	_location_label.text = loc_text.strip_edges()
	_location_label.visible = not loc_text.strip_edges().is_empty()
	($PanelAnchor/Notebook/OuterVBox/HBox/PolaroidArea/PolaroidCard/PolaroidVBox/CardBottom/CardBottomSep as Label).visible = _location_label.visible

	_polaroid_card.rotation = deg_to_rad(_photo_rotation_deg)
	_notebook_decor.queue_redraw()

	# 右侧
	_title_label.text = darkside.get("label", "未知事件")
	_title_label.add_theme_color_override("font_color",
		Color(type_color.r, type_color.g, type_color.b, 0.90))
	_populate_effects(card.get_effects(), false)
	_desc_label.text = card.get_event_text()
	_desc_scroll.call_deferred("set", "scroll_vertical", 0)
	_baiiye_label.visible = false
	_confirm_label.text = "点击关闭"
	_style_confirm_button(false)

	_run_enter_animation(false)

# ---------------------------------------------------------------------------
# 内部：加载事件插画
# ---------------------------------------------------------------------------
func _load_event_image(location: String, event_type: String) -> void:
	var tex: Texture2D = CardImageMap.get_event_texture(location, event_type)
	if tex != null:
		_event_texture.texture = tex
		_event_texture.visible = true
	else:
		_event_texture.texture = null
		_event_texture.visible = false

# ---------------------------------------------------------------------------
# 内部：确认按钮样式
# ---------------------------------------------------------------------------
func _style_confirm_button(hovered: bool) -> void:
	var btn_style: StyleBoxFlat = StyleBoxFlat.new()
	var base_g: float = 0.706 if not hovered else 0.78
	btn_style.bg_color = Color(0.278, base_g, 0.510, 0.92)
	btn_style.set_corner_radius_all(24)
	btn_style.content_margin_left = 24
	btn_style.content_margin_right = 24
	btn_style.content_margin_top = 14
	btn_style.content_margin_bottom = 14
	_confirm_button.add_theme_stylebox_override("panel", btn_style)

# ---------------------------------------------------------------------------
# 内部：入场动画
# ---------------------------------------------------------------------------
func _run_enter_animation(has_baiiye: bool) -> void:
	_overlay.color.a = 0.0
	_notebook.scale = Vector2(0.3, 0.3)
	_notebook.pivot_offset = _notebook.size / 2.0
	_notebook.modulate.a = 0.0
	_polaroid_card.modulate.a = 0.0
	_title_label.modulate.a = 0.0
	_effects_row.modulate.a = 0.0
	_desc_label.modulate.a = 0.0
	_confirm_button.modulate.a = 0.0

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "color:a", 0.45, 0.35)
	tw.tween_property(_notebook, "scale", Vector2.ONE, 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_notebook, "modulate:a", 1.0, 0.35)

	var base: float = 0.10
	tw.tween_property(_polaroid_card, "modulate:a", 1.0, 0.28).set_delay(base) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_title_label, "modulate:a", 1.0, 0.26).set_delay(base + 0.06) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_effects_row, "modulate:a", 1.0, 0.24).set_delay(base + 0.13) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_desc_label, "modulate:a", 1.0, 0.24).set_delay(base + 0.20) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if has_baiiye:
		tw.tween_property(_baiiye_label, "modulate:a", 0.72, 0.28).set_delay(base + 0.30) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_confirm_button, "modulate:a", 1.0, 0.26).set_delay(base + 0.28) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(func(): _phase = "idle")

## 关闭弹窗
func dismiss() -> void:
	if not _active or _phase == "exit":
		return
	_phase = "exit"
	AudioManager.play_sfx("popup_close")
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "color:a", 0.0, 0.22)
	tw.tween_property(_notebook, "scale", Vector2(0.5, 0.5), 0.22) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_notebook, "modulate:a", 0.0, 0.22)
	tw.tween_property(_polaroid_card, "modulate:a", 0.0, 0.15)
	tw.tween_property(_title_label, "modulate:a", 0.0, 0.15)
	tw.tween_property(_effects_row, "modulate:a", 0.0, 0.15)
	tw.tween_property(_desc_label, "modulate:a", 0.0, 0.15)
	tw.tween_property(_confirm_button, "modulate:a", 0.0, 0.15)
	if _baiiye_label.visible:
		tw.tween_property(_baiiye_label, "modulate:a", 0.0, 0.12)
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
# 选择面板 API（暗面遭遇 / 通道方向）
# ===========================================================================

## 当前选择面板节点（null 表示未显示）
var _choice_panel: Control = null

## 显示选择面板，labels 为按钮文字数组，callback 接收选择的索引（0-based）
## 调用方：dark_world_flow.gd → _trigger_encounter_dialogue / _show_passage_choice
func show_choice(labels: Array, callback: Callable) -> void:
	_dismiss_choice_panel()

	# 确保弹窗容器可见（可能在事件弹窗关闭后调用）
	visible = true
	_overlay.visible = true
	_overlay.color.a = 0.55

	# 根节点：全屏居中容器，鼠标穿透（让 Overlay 拦截背景点击）
	var anchor: CenterContainer = CenterContainer.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	_choice_panel = anchor

	# 卡片面板（奶白色纸质感，带阴影）
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color = Color(0.980, 0.965, 0.933, 0.97)
	ps.border_color = Color(0.769, 0.722, 0.643, 0.55)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(18)
	ps.content_margin_left = 28
	ps.content_margin_right = 28
	ps.content_margin_top = 28
	ps.content_margin_bottom = 28
	ps.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
	ps.shadow_size = 18
	ps.shadow_offset = Vector2(4.0, 7.0)
	panel.add_theme_stylebox_override("panel", ps)
	anchor.add_child(panel)

	# 内部垂直布局
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	# 为每个选项创建按钮行
	for i: int in labels.size():
		var idx: int = i  # 闭包捕获
		var btn_panel: PanelContainer = PanelContainer.new()
		btn_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_panel.custom_minimum_size = Vector2(0, 56)

		# 交替配色：主色 蓝灰 / 暗绿，与暗面风格匹配
		var btn_color: Color
		if i % 2 == 0:
			btn_color = Color(0.286, 0.416, 0.518, 1.0)  # 深蓝灰
		else:
			btn_color = Color(0.235, 0.431, 0.376, 1.0)  # 暗绿

		var bs: StyleBoxFlat = StyleBoxFlat.new()
		bs.bg_color = Color(btn_color.r, btn_color.g, btn_color.b, 0.82)
		bs.border_color = Color(btn_color.r, btn_color.g, btn_color.b, 0.60)
		bs.set_border_width_all(2)
		bs.set_corner_radius_all(12)
		bs.content_margin_left = 20
		bs.content_margin_right = 20
		bs.content_margin_top = 10
		bs.content_margin_bottom = 10
		btn_panel.add_theme_stylebox_override("panel", bs)

		var lbl: Label = Label.new()
		lbl.text = labels[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 38)
		lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_panel.add_child(lbl)

		# 点击响应（通过 gui_input 捕获）
		btn_panel.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb: InputEventMouseButton = ev as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					_dismiss_choice_panel()
					callback.call(idx)
		)

		vbox.add_child(btn_panel)

	# 入场动画（淡入）
	panel.modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.22)

## 关闭选择面板；如果主弹窗也不活跃则隐藏 overlay
func _dismiss_choice_panel() -> void:
	if _choice_panel:
		_choice_panel.queue_free()
		_choice_panel = null
	# 仅当主弹窗和 toast 均不活跃时才隐藏 overlay
	if not _active and not _has_active_toasts():
		_overlay.visible = false
		visible = false

# ===========================================================================
# 效果徽章（Lua 版风格：绿/红胶囊，icon + 数值）
# ===========================================================================

func _populate_effects(effects: Dictionary, shield_used: bool) -> void:
	for child in _effects_row.get_children():
		child.queue_free()

	if shield_used:
		_add_effect_badge("🛡️ 护盾", Color(0.278, 0.706, 0.510), 0)
		return

	if effects.is_empty():
		return

	var t = GameTheme
	for key in effects:
		var delta_val: int = effects[key]
		var res_icon: String = GameData.RESOURCE_ICONS.get(key, "?")
		var prefix: String = "+" if delta_val > 0 else ""
		var bg_c: Color = t.safe if delta_val > 0 else t.danger
		_add_effect_badge(res_icon + " " + prefix + str(delta_val), bg_c, delta_val)

func _add_effect_badge(text: String, color: Color, _delta: int) -> void:
	var badge: PanelContainer = PanelContainer.new()
	var badge_style: StyleBoxFlat = StyleBoxFlat.new()
	badge_style.bg_color = Color(color.r, color.g, color.b, 0.14)
	badge_style.border_color = Color(color.r, color.g, color.b, 0.35)
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(20)
	badge_style.content_margin_left = 22
	badge_style.content_margin_right = 22
	badge_style.content_margin_top = 8
	badge_style.content_margin_bottom = 8
	badge.add_theme_stylebox_override("panel", badge_style)

	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", color)
	badge.add_child(lbl)
	_effects_row.add_child(badge)

# ===========================================================================
# Toast API
# ===========================================================================

func show_toast(data: ToastData) -> void:
	var card_type: String = data.card_type
	var trap_subtype: String = data.trap_subtype
	var location: String = data.location

	var tmpl: Dictionary = _pick_template(card_type, trap_subtype, location)

	var display_title: String = data.title
	if display_title == "":
		display_title = tmpl["title"]
		if location != "":
			var dark_display: Dictionary = Locations.get_dark_display(location)
			var dark_info: Dictionary = dark_display.get(card_type, {})
			if dark_info.has("label"):
				display_title = dark_info["label"]

	var display_icon: String = data.icon
	if display_icon == "":
		display_icon = GameTheme.card_type_info(card_type).get("icon", "❓")
		if card_type == "trap" and trap_subtype != "":
			var sub_info: Dictionary = EventPool.get_trap_subtype(trap_subtype)
			if sub_info.has("icon"):
				display_icon = sub_info["icon"]

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

func _show_toast_internal(data: Dictionary) -> void:
	visible = true
	var toast_node: ToastItem = _toast_item_packed.instantiate() as ToastItem
	_toast_container.add_child(toast_node)
	toast_node.setup(data)
	toast_node.dismissed.connect(_on_toast_dismissed)
	_enforce_toast_limit()

func _enforce_toast_limit() -> void:
	var visible_count: int = 0
	var children: Array[Node] = _toast_container.get_children()
	for child in children:
		if child is ToastItem:
			visible_count += 1
	if visible_count > TOAST_MAX:
		for child in children:
			if child is ToastItem:
				(child as ToastItem).start_exit()
				break

func _on_toast_dismissed(card_type: String) -> void:
	toast_dismissed.emit(card_type)
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
		return
	# hover 效果：按钮点击时短暂高亮
	_style_confirm_button(true)
	dismiss()

# ===========================================================================
# 工具方法
# ===========================================================================

func _pick_template(card_type: String, trap_subtype: String = "", location: String = "") -> Dictionary:
	return CardConfig.pick_event_template(card_type, location, trap_subtype)

# ---------------------------------------------------------------------------
# 笔记本稿纸装饰绘制（红色边距竖线 + 蓝色横线，对齐 Lua 版 drawPhoto）
# ---------------------------------------------------------------------------
func _draw_notebook_decor() -> void:
	# 先绘制拍立得阴影（需在卡片 PanelContainer 之下渲染，利用 NotebookDecor 在场景树中更早）
	_draw_polaroid_shadow_decor()

	var t: Node = get_node("/root/GameTheme")
	var sz: Vector2 = _notebook_decor.size
	if sz.x < 10.0 or sz.y < 10.0:
		return

	# 红色边距竖线位置：PolaroidArea 右边缘（约 240px）+ 小量偏移
	# 与拍立得区域右边齐，充当分隔线
	var pol_w: float = _polaroid_area.size.x if _polaroid_area else 240.0
	var red_x: float = pol_w + 6.0

	# 红色竖线
	_notebook_decor.draw_line(
		Vector2(red_x, 10.0),
		Vector2(red_x, sz.y - 10.0),
		Color(0.784, 0.333, 0.333, 0.38),
		2.0
	)

	# 蓝色横线（稿纸风格，仅在文字区右侧绘制）
	var line_x0: float = red_x + 10.0
	var line_x1: float = sz.x - 20.0
	var line_spacing: float = 54.0
	var ly: float = line_spacing * 1.1
	while ly < sz.y - 14.0:
		_notebook_decor.draw_line(
			Vector2(line_x0, ly),
			Vector2(line_x1, ly),
			Color(t.notebook_line, 0.20),
			1.5
		)
		ly += line_spacing

# ---------------------------------------------------------------------------
# 拍立得阴影绘制（在 NotebookDecor 的 draw 回调中执行，渲染在卡片之下）
# 与 ResourceBarScene._draw_soft_box_shadow() 方式相同：
#   StyleBoxFlat（主体透明）+ draw_style_box() 利用引擎内置阴影渲染
# Lua 原始: feather=16, offset(+2,+4), color(30,20,10,80)
# ---------------------------------------------------------------------------
func _draw_polaroid_shadow_decor() -> void:
	if _polaroid_card == null or not _polaroid_card.is_inside_tree():
		return
	# ⚠️ 必须用 .size 而非 get_global_rect().size：
	#   get_global_rect() 返回旋转后的 AABB，尺寸随旋转角度变化 → 阴影每次不一致
	var pol_size: Vector2 = _polaroid_card.size        # 原始未旋转尺寸（固定值）
	var pol_w: float = pol_size.x
	if pol_w < 10.0:
		return

	# 分辨率缩放（Lua POL_W=122 → Godot 实际宽度）
	var s: float = pol_w / 122.0

	# StyleBoxFlat 主体透明，只取引擎内置阴影（与 ResourceBar 完全相同的做法）
	var sb := StyleBoxFlat.new()
	sb.bg_color                   = Color(0, 0, 0, 0)
	sb.corner_radius_top_left     = 6
	sb.corner_radius_top_right    = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left  = 6
	sb.shadow_size   = int(8.0 * s)                   # ≈ 17
	sb.shadow_offset = Vector2(2.0 * s, 4.0 * s)      # ≈ (4, 9)
	sb.shadow_color  = Color(0.118, 0.078, 0.039, 0.28)

	# global_position 是未旋转矩形的左上角（不受 AABB 影响），配合 .size 还原真实中心
	var card_global_center: Vector2 = _polaroid_card.global_position + pol_size * 0.5
	var local_center: Vector2 = card_global_center - _notebook_decor.global_position
	# 以卡片中心为旋转原点，Rect 坐标相对于该原点（-half_size → +half_size）
	_notebook_decor.draw_set_transform(local_center, _polaroid_card.rotation)
	_notebook_decor.draw_style_box(sb, Rect2(-pol_size * 0.5, pol_size))
	_notebook_decor.draw_set_transform(Vector2.ZERO, 0.0)

# ---------------------------------------------------------------------------
# 拍立得动态尺寸计算（对齐 Lua 版比例）
# Lua 原始比例：POL_W/POL_H = 122/187 = 0.652，底白边 = POL_BOTTOM/POL_H = 32/187 = 17.1%
# ---------------------------------------------------------------------------
func _update_polaroid_layout() -> void:
	if not is_inside_tree() or _polaroid_card == null:
		return

	var vp: Vector2 = get_viewport_rect().size
	var nb_h: float = minf(vp.y * 0.52, 600.0)

	# HBox 可用高度 = 笔记本高 - 内容边距(top16+bottom20) - 确认按钮(52) - 分隔(12)
	var hbox_h: float = maxf(nb_h - 100.0, 180.0)

	# 拍立得高度：HBox 高的 88%（Lua 版约 93.5%，HBox 比 NB_H 略矮故留余量）
	var pol_h: float = hbox_h * 0.88
	# 拍立得宽度：保持 Lua 版比例 122/187 ≈ 0.652
	var pol_w: float = pol_h * (122.0 / 187.0)

	# 更新 PolaroidCard 大小（通过锚点偏移，锚在父容器中心）
	_polaroid_card.offset_left   = -pol_w * 0.5
	_polaroid_card.offset_right  =  pol_w * 0.5
	_polaroid_card.offset_top    = -pol_h * 0.5
	_polaroid_card.offset_bottom =  pol_h * 0.5
	_polaroid_card.pivot_offset  = Vector2(pol_w * 0.5, pol_h * 0.5)

	# 拍立得区域宽度：卡片宽 + 旋转余量（5° 时最大水平溢出 ≈ pol_h * sin5° ≈ pol_h * 0.044）
	# 余量覆盖旋转溢出，确保不与右侧文字区重叠
	var rot_margin: float = pol_h * 0.05 + 8.0
	_polaroid_area.custom_minimum_size = Vector2(pol_w + rot_margin, 0.0)

	# 拍立得边框内边距（Lua 版 POL_SIDE/POL_W = 9/122 ≈ 7.4%）
	var margin_side: float = maxf(pol_w * 0.074, 8.0)
	# 底部白边高度（Lua 版 POL_BOTTOM/POL_H = 32/187 ≈ 17.1%）
	var bottom_h: float = maxf(pol_h * 0.171, 32.0)

	# 更新拍立得卡样式（奶白色相纸，比例缩放边距）
	var pol_style := StyleBoxFlat.new()
	pol_style.bg_color          = Color(0.992, 0.988, 0.965, 1.0)
	pol_style.border_color      = Color(0.824, 0.784, 0.725, 0.55)
	pol_style.set_border_width_all(2)
	pol_style.set_corner_radius_all(6)
	pol_style.content_margin_left   = margin_side
	pol_style.content_margin_right  = margin_side
	pol_style.content_margin_top    = margin_side
	pol_style.content_margin_bottom = 0.0
	pol_style.shadow_color  = Color(0.0, 0.0, 0.0, 0.32)
	pol_style.shadow_size   = 14
	pol_style.shadow_offset = Vector2(3.0, 5.0)
	_polaroid_card.add_theme_stylebox_override("panel", pol_style)

	# 底部标签区高度 + 字号（按比例缩放）
	_card_bottom.custom_minimum_size = Vector2(0.0, bottom_h)
	var lbl_size: int = maxi(int(pol_h * 0.072), 22)
	_type_label.add_theme_font_size_override("font_size", lbl_size)
	_location_label.add_theme_font_size_override("font_size", lbl_size)

	if _notebook_decor:
		_notebook_decor.queue_redraw()

func _on_resized() -> void:
	if _notebook:
		var vp: Vector2 = get_viewport_rect().size
		_notebook.custom_minimum_size = Vector2(
			minf(vp.x * 0.72, 1080),
			minf(vp.y * 0.52, 600)
		)
		# 拍立得尺寸由 tscn Inspector 固定，resize 时只刷新装饰线位置
		# _update_polaroid_layout()  # ← 如需代码驱动尺寸再打开
		if _notebook_decor:
			_notebook_decor.queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_on_resized()
