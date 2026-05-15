class_name DebugPanel
extends PanelContainer
## DebugPanel — 开发调试面板
##
## 显示游戏状态信息，提供快捷调试按钮。
## 按 F1 切换显示/隐藏。
##
## 用法:
##   var panel = DebugPanel.create(ui_layer)
##   panel.refresh(game_state_dict)  # 每帧或按需调用

# ─── 信号 ──────────────────────────────────────────────
signal debug_action(action_id: String)

# ─── 常量 ──────────────────────────────────────────────
const PANEL_WIDTH: int = 340
const LINE_HEIGHT: int = 24
const TITLE_COLOR: Color = Color(0.39, 0.78, 1.0)
const KEY_COLOR: Color = Color(0.7, 0.7, 0.7)
const VALUE_COLOR: Color = Color(1.0, 1.0, 0.78)
const BTN_COLOR: Color = Color(0.2, 0.3, 0.4)
const BG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.75)

# ─── 内部节点 ─────────────────────────────────────────
var _vbox: VBoxContainer = null
var _data_container: VBoxContainer = null
var _btn_container: GridContainer = null
var _title_label: Label = null

# ─── 工厂方法 ─────────────────────────────────────────

## 创建并挂载到指定父节点（通常是 CanvasLayer）
static func create(parent: Node) -> DebugPanel:
	var panel: DebugPanel = DebugPanel.new()
	parent.add_child(panel)
	panel.visible = false
	return panel


func _ready() -> void:
	_build_ui()
	_build_debug_buttons()


func _build_ui() -> void:
	# 面板自身样式
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = TITLE_COLOR * Color(1, 1, 1, 0.4)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	# 定位: 右上角
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -PANEL_WIDTH - 10
	offset_right = -10
	offset_top = 10

	custom_minimum_size.x = PANEL_WIDTH

	# 主 VBox
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	add_child(_vbox)

	# 标题
	_title_label = Label.new()
	_title_label.text = "调试面板"
	_title_label.add_theme_color_override("font_color", TITLE_COLOR)
	_title_label.add_theme_font_size_override("font_size", 18)
	_vbox.add_child(_title_label)

	# 分隔线
	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("separator", TITLE_COLOR * Color(1, 1, 1, 0.3))
	_vbox.add_child(sep)

	# 数据容器
	_data_container = VBoxContainer.new()
	_data_container.add_theme_constant_override("separation", 2)
	_vbox.add_child(_data_container)

	# 分隔线 2
	var sep2: HSeparator = HSeparator.new()
	sep2.add_theme_color_override("separator", TITLE_COLOR * Color(1, 1, 1, 0.2))
	_vbox.add_child(sep2)

	# 按钮网格
	_btn_container = GridContainer.new()
	_btn_container.columns = 3
	_btn_container.add_theme_constant_override("h_separation", 4)
	_btn_container.add_theme_constant_override("v_separation", 4)
	_vbox.add_child(_btn_container)


func _build_debug_buttons() -> void:
	var buttons: Array[Dictionary] = [
		{ "label": "进入暗面", "id": "enter_dark" },
		{ "label": "灵感+10", "id": "ins_10" },
		{ "label": "灵感+50", "id": "ins_50" },
		{ "label": "信任+1", "id": "trust_up" },
		{ "label": "信任-1", "id": "trust_down" },
		{ "label": "力量+1", "id": "power_up" },
		{ "label": "力量MAX", "id": "power_max" },
		{ "label": "清除沉睡", "id": "clear_sleep" },
		{ "label": "+1碎片", "id": "add_frag" },
		{ "label": "碎片=4", "id": "frag_4" },
		{ "label": "碎片=9", "id": "frag_9" },
		{ "label": "重置旗标", "id": "reset_flags" },
		{ "label": "下一天", "id": "next_day" },
	]

	for def in buttons:
		var btn: Button = Button.new()
		btn.text = def["label"]
		btn.custom_minimum_size = Vector2(100, 28)

		var btn_style: StyleBoxFlat = StyleBoxFlat.new()
		btn_style.bg_color = BTN_COLOR
		btn_style.corner_radius_top_left = 4
		btn_style.corner_radius_top_right = 4
		btn_style.corner_radius_bottom_left = 4
		btn_style.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", btn_style)

		var btn_hover: StyleBoxFlat = StyleBoxFlat.new()
		btn_hover.bg_color = BTN_COLOR.lightened(0.15)
		btn_hover.corner_radius_top_left = 4
		btn_hover.corner_radius_top_right = 4
		btn_hover.corner_radius_bottom_left = 4
		btn_hover.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("hover", btn_hover)

		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", Color.WHITE)

		var action_id: String = def["id"]
		btn.pressed.connect(func(): debug_action.emit(action_id))
		_btn_container.add_child(btn)


# ─── 公共接口 ─────────────────────────────────────────

## 切换显隐
func toggle() -> void:
	visible = not visible


## 刷新显示数据
## data 格式: { "Day": 3, "Phase": "exploration", "San": 8, ... }
func refresh(data: Dictionary) -> void:
	if not visible:
		return

	# 清空旧内容
	for child in _data_container.get_children():
		child.queue_free()

	# 按 key 排序
	var keys: Array = data.keys()
	keys.sort()

	for key in keys:
		var row: HBoxContainer = HBoxContainer.new()

		var key_label: Label = Label.new()
		key_label.text = str(key) + ":"
		key_label.add_theme_color_override("font_color", KEY_COLOR)
		key_label.add_theme_font_size_override("font_size", 14)
		key_label.custom_minimum_size.x = 140
		row.add_child(key_label)

		var val_label: Label = Label.new()
		val_label.text = str(data[key])
		val_label.add_theme_color_override("font_color", VALUE_COLOR)
		val_label.add_theme_font_size_override("font_size", 14)
		row.add_child(val_label)

		_data_container.add_child(row)


## 设置单条数据 (便捷方法，配合 refresh 使用)
func set_data(key: String, value: Variant) -> void:
	# 对于需要实时更新单条数据的场景
	# 推荐用法: 收集所有数据到 dict 后调用 refresh()
	pass


# ─── 输入处理 ─────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			toggle()
			get_viewport().set_input_as_handled()
