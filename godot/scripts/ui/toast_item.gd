## ToastItem - 单条 Toast 通知 (Scene 化子组件)
class_name ToastItem
extends PanelContainer

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal dismissed(card_type: String)

# ---------------------------------------------------------------------------
# 节点引用
# ---------------------------------------------------------------------------
@onready var _type_bar: ColorRect = $HBox/TypeBar
@onready var _icon_label: Label = $HBox/VBox/HeaderRow/IconLabel
@onready var _title_label: Label = $HBox/VBox/HeaderRow/TitleLabel
@onready var _desc_label: Label = $HBox/VBox/DescLabel
@onready var _effects_row: HBoxContainer = $HBox/VBox/EffectsRow
@onready var _progress_bar: ProgressBar = $HBox/VBox/ProgressBar

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const IDLE_TIME: float = 3.0
const ENTER_TIME: float = 0.35
const EXIT_TIME: float = 0.25
const TOAST_W: float = 660.0

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var card_type: String = "safe"
var _phase: String = "enter"  # "enter" | "idle" | "exit" | "done"
var _timer: float = 0.0

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 面板样式
	var t = GameTheme
	var style := StyleBoxFlat.new()
	style.bg_color = Color(t.panel_bg.r, t.panel_bg.g, t.panel_bg.b, 0.94)
	style.border_color = Color(t.panel_border.r, t.panel_border.g, t.panel_border.b, 0.31)
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", style)

	# 字号
	_icon_label.add_theme_font_size_override("font_size", 60)
	_title_label.add_theme_font_size_override("font_size", 42)
	_desc_label.add_theme_font_size_override("font_size", 33)
	_desc_label.add_theme_color_override("font_color", t.text_secondary)

	# 进度条样式
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, 0.12)
	pb_bg.set_corner_radius_all(3)
	_progress_bar.add_theme_stylebox_override("background", pb_bg)

## 配置 Toast 内容
func setup(data: Dictionary) -> void:
	card_type = data.get("card_type", "safe")
	var t = GameTheme
	var type_color: Color = t.card_type_color(card_type)

	# 类型色条
	_type_bar.color = Color(type_color.r, type_color.g, type_color.b, 0.78)

	# 标题行
	_icon_label.text = data.get("icon", "❓")
	_title_label.text = data.get("title", "")
	_title_label.add_theme_color_override("font_color",
		Color(type_color.r, type_color.g, type_color.b, 0.94))

	# 描述
	var desc: String = data.get("desc", "")
	if desc.length() > 40:
		desc = desc.substr(0, 37) + "..."
	_desc_label.text = desc

	# 效果徽章
	_populate_effects(data)

	# 进度条前景色
	var pb_fg := StyleBoxFlat.new()
	pb_fg.bg_color = Color(type_color.r, type_color.g, type_color.b, 0.47)
	pb_fg.set_corner_radius_all(3)
	_progress_bar.add_theme_stylebox_override("fill", pb_fg)

	# 入场动画
	_start_enter()

func _populate_effects(data: Dictionary) -> void:
	# 清空旧内容
	for child in _effects_row.get_children():
		child.queue_free()

	var t = GameTheme
	var shield_used: bool = data.get("shield_used", false)
	var effects: Dictionary = data.get("effects", {})

	if shield_used:
		var lbl := Label.new()
		lbl.text = "🧿 护身符抵挡了伤害!"
		lbl.add_theme_font_size_override("font_size", 33)
		lbl.add_theme_color_override("font_color", Color(t.safe.r, t.safe.g, t.safe.b, 0.86))
		_effects_row.add_child(lbl)
	elif effects.size() > 0:
		for key in effects:
			var delta_val: int = effects[key]
			var res_icon: String = GameData.RESOURCE_ICONS.get(key, "?")
			var prefix: String = "+" if delta_val > 0 else ""
			var badge_text: String = res_icon + prefix + str(delta_val)

			var badge := PanelContainer.new()
			var badge_style := StyleBoxFlat.new()
			var bg_c: Color = t.safe if delta_val > 0 else t.danger
			badge_style.bg_color = Color(bg_c.r, bg_c.g, bg_c.b, 0.14)
			badge_style.border_color = Color(bg_c.r, bg_c.g, bg_c.b, 0.31)
			badge_style.set_border_width_all(1)
			badge_style.set_corner_radius_all(9)
			badge_style.content_margin_left = 12
			badge_style.content_margin_right = 12
			badge_style.content_margin_top = 6
			badge_style.content_margin_bottom = 6
			badge.add_theme_stylebox_override("panel", badge_style)

			var lbl := Label.new()
			lbl.text = badge_text
			lbl.add_theme_font_size_override("font_size", 30)
			lbl.add_theme_color_override("font_color", Color(bg_c.r, bg_c.g, bg_c.b, 0.86))
			badge.add_child(lbl)
			_effects_row.add_child(badge)

# ---------------------------------------------------------------------------
# 动画
# ---------------------------------------------------------------------------

func _start_enter() -> void:
	_phase = "enter"
	_timer = 0.0
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)
	position.x = TOAST_W + 60.0

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:x", 0.0, ENTER_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "modulate:a", 1.0, ENTER_TIME)
	tw.tween_property(self, "scale", Vector2.ONE, ENTER_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(func():
		if _phase == "enter":
			_phase = "idle"
			_timer = 0.0
	)

func start_exit() -> void:
	if _phase == "exit" or _phase == "done":
		return
	_phase = "exit"
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:x", TOAST_W + 90.0, EXIT_TIME) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "modulate:a", 0.0, EXIT_TIME)
	tw.tween_property(self, "scale", Vector2(0.85, 0.85), EXIT_TIME)
	tw.chain().tween_callback(func():
		_phase = "done"
		dismissed.emit(card_type)
		queue_free()
	)

# ---------------------------------------------------------------------------
# 每帧更新
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_timer += delta
	if _phase == "idle":
		# 更新倒计时进度条
		var progress: float = 1.0 - minf(_timer / IDLE_TIME, 1.0)
		_progress_bar.value = progress * 100.0
		if _timer >= IDLE_TIME:
			start_exit()

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			start_exit()
			accept_event()
