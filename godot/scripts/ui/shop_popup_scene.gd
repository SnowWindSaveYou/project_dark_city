## ShopPopupScene - 商店弹窗 (Scene 化 + 混合架构)
## 面板框架/按钮使用 Control 节点；商品卡使用 _draw() 保留复杂动画
class_name ShopPopupScene
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal shop_closed

# ---------------------------------------------------------------------------
# 常量: 卡牌绘制
# ---------------------------------------------------------------------------
const CARD_W: float = 234.0
const CARD_H: float = 330.0
const CARD_GAP: float = 42.0
const CARD_COUNT: int = 3

# ---------------------------------------------------------------------------
# 节点引用
# ---------------------------------------------------------------------------
@onready var _overlay: ColorRect = $Overlay
@onready var _panel: PanelContainer = $PanelAnchor/Panel
@onready var _color_bar: ColorRect = $PanelAnchor/Panel/VBox/ColorBar
@onready var _money_label: Label = $PanelAnchor/Panel/VBox/HeaderRow/MoneyLabel
@onready var _shop_icon: Label = $PanelAnchor/Panel/VBox/HeaderRow/ShopIcon
@onready var _title_label: Label = $PanelAnchor/Panel/VBox/TitleLabel
@onready var _desc_label: Label = $PanelAnchor/Panel/VBox/DescLabel
@onready var _cards_area: Control = $PanelAnchor/Panel/VBox/CardsArea
@onready var _refresh_button: Button = $PanelAnchor/Panel/VBox/ButtonRow/RefreshButton
@onready var _leave_button: Button = $PanelAnchor/Panel/VBox/ButtonRow/LeaveButton

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _active: bool = false
var _phase: String = "none"
var _goods: Array = []
var _variant: Dictionary = {}
var _sold: Array = []
var _is_dark: bool = false  # 暗面商店模式

# 卡牌动画 (保留 _draw 用)
var _card_alphas: Array = []
var _card_rots: Array = []
var _card_shake_x: Array = []
var _purchase_flash: Array = []
var _hover_card: int = -1
var _hover_card_t: Array = []
var _refresh_phase: String = "idle"

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	var t = GameTheme

	# 面板样式
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(t.panel_bg.r, t.panel_bg.g, t.panel_bg.b, 0.96)
	panel_style.border_color = Color(t.panel_border.r, t.panel_border.g, t.panel_border.b, 0.47)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(42)
	panel_style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", panel_style)

	# 色条
	_color_bar.color = Color(t.info.r, t.info.g, t.info.b, 0.78)

	# 字号和颜色
	_money_label.add_theme_font_size_override("font_size", 42)
	_money_label.add_theme_color_override("font_color", t.text_primary)
	_shop_icon.add_theme_font_size_override("font_size", 78)
	_title_label.add_theme_font_size_override("font_size", 45)
	_desc_label.add_theme_font_size_override("font_size", 33)
	_desc_label.add_theme_color_override("font_color",
		Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, 0.7))

	# 刷新按钮样式
	var refresh_style := StyleBoxFlat.new()
	refresh_style.bg_color = Color(t.info.r, t.info.g, t.info.b, 0.72)
	refresh_style.set_corner_radius_all(21)
	refresh_style.set_content_margin_all(12)
	_refresh_button.add_theme_stylebox_override("normal", refresh_style)
	var refresh_hover := refresh_style.duplicate()
	refresh_hover.bg_color = GameTheme.lighten(t.info, 0.25)
	_refresh_button.add_theme_stylebox_override("hover", refresh_hover)
	var refresh_pressed := refresh_style.duplicate()
	refresh_pressed.bg_color = GameTheme.darken(t.info, 0.85)
	_refresh_button.add_theme_stylebox_override("pressed", refresh_pressed)
	_refresh_button.add_theme_color_override("font_color", Color.WHITE)
	_refresh_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_refresh_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	_refresh_button.add_theme_font_size_override("font_size", 36)
	# 消除 focus 边框
	var empty_focus := StyleBoxEmpty.new()
	_refresh_button.add_theme_stylebox_override("focus", empty_focus)
	_refresh_button.focus_mode = Control.FOCUS_NONE

	# 离开按钮样式
	var leave_style := StyleBoxFlat.new()
	leave_style.bg_color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, 0.55)
	leave_style.set_corner_radius_all(21)
	leave_style.set_content_margin_all(12)
	_leave_button.add_theme_stylebox_override("normal", leave_style)
	var leave_hover := leave_style.duplicate()
	leave_hover.bg_color = GameTheme.lighten(t.text_secondary, 0.3)
	_leave_button.add_theme_stylebox_override("hover", leave_hover)
	var leave_pressed := leave_style.duplicate()
	leave_pressed.bg_color = GameTheme.darken(t.text_secondary, 0.85)
	_leave_button.add_theme_stylebox_override("pressed", leave_pressed)
	_leave_button.add_theme_color_override("font_color", Color.WHITE)
	_leave_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_leave_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	_leave_button.add_theme_font_size_override("font_size", 39)
	_leave_button.add_theme_stylebox_override("focus", empty_focus)
	_leave_button.focus_mode = Control.FOCUS_NONE

	# Hover 放大动效
	_refresh_button.mouse_entered.connect(func(): _btn_hover_tween(_refresh_button, true))
	_refresh_button.mouse_exited.connect(func(): _btn_hover_tween(_refresh_button, false))
	_leave_button.mouse_entered.connect(func(): _btn_hover_tween(_leave_button, true))
	_leave_button.mouse_exited.connect(func(): _btn_hover_tween(_leave_button, false))

	# 信号连接
	_refresh_button.pressed.connect(_on_refresh_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)

	# CardsArea 的 _draw 回调
	_cards_area.draw.connect(_draw_cards)

# ===========================================================================
# API
# ===========================================================================

func open_shop(is_dark: bool = false) -> void:
	_active = true
	_phase = "enter"
	_is_dark = is_dark
	visible = true
	_variant = ShopData.random_dark_variant() if is_dark else ShopData.random_variant()
	_refresh_goods()
	_refresh_phase = "idle"

	# 暗面商店色调
	if is_dark:
		_color_bar.color = Color(0.5, 0.2, 0.7, 0.78)
	else:
		_color_bar.color = Color(GameTheme.info.r, GameTheme.info.g, GameTheme.info.b, 0.78)

	# 填充内容
	_title_label.text = _variant.get("name", "商店")
	_desc_label.text = _variant.get("greeting", "")
	_update_money_display()
	_update_refresh_button_text()

	# 初始动画状态
	_overlay.color.a = 0.0
	_panel.scale = Vector2(0.3, 0.3)
	_panel.pivot_offset = _panel.size / 2.0
	_panel.modulate.a = 0.0

	# 入场动画
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "color:a", 0.45, 0.35)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.35)

	# 卡牌入场动画
	for i in range(_card_alphas.size()):
		var delay_i: float = 0.12 + 0.07 * (i + 2)
		_tween_array(tw, _card_alphas, i, 1.0, 0.35, delay_i, Tween.TRANS_BACK, Tween.EASE_OUT)
		_tween_array(tw, _card_rots, i, 0.0, 0.35, delay_i, Tween.TRANS_BACK, Tween.EASE_OUT)

	tw.chain().tween_callback(func(): _phase = "idle")

func close_shop() -> void:
	if not _active or _phase == "exit":
		return
	_phase = "exit"

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	# 卡牌飞散
	for i in range(_card_alphas.size()):
		var spin: Array = [deg_to_rad(-15.0), 0.0, deg_to_rad(15.0)]
		_tween_array(tw, _card_alphas, i, 0.0, 0.2, i * 0.03, Tween.TRANS_BACK, Tween.EASE_IN)
		_tween_array(tw, _card_rots, i, spin[i] if i < 3 else 0.0, 0.2, i * 0.03, Tween.TRANS_BACK, Tween.EASE_IN)
	tw.tween_property(_overlay, "color:a", 0.0, 0.25).set_delay(0.08)
	tw.tween_property(_panel, "scale", Vector2(0.5, 0.5), 0.25).set_delay(0.08) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.25).set_delay(0.08)
	tw.chain().tween_callback(func():
		_active = false
		visible = false
		_phase = "none"
		shop_closed.emit()
	)

func is_active() -> bool:
	return _active

# ---------------------------------------------------------------------------
# 内部方法
# ---------------------------------------------------------------------------

func _refresh_goods() -> void:
	_goods = ShopData.generate_dark_shop_goods() if _is_dark else ShopData.generate_shop_goods()
	_sold = []
	_card_alphas = []
	_card_rots = []
	_card_shake_x = []
	_purchase_flash = []
	_hover_card_t = []
	for _i in range(_goods.size()):
		_sold.append(false)
		_card_alphas.append(0.0)
		var rand_rot: float = (randf() - 0.5) * 2.0 * deg_to_rad(8.0)
		_card_rots.append(rand_rot)
		_card_shake_x.append(0.0)
		_purchase_flash.append(0.0)
		_hover_card_t.append(0.0)

func _update_money_display() -> void:
	_money_label.text = "💰 " + str(GameData.get_resource("money"))

func _update_refresh_button_text() -> void:
	_refresh_button.text = "🔄 刷新 💰" + str(CardConfig.shop_refresh_cost)
	var can_afford: bool = GameData.get_resource("money") >= CardConfig.shop_refresh_cost
	_refresh_button.disabled = not can_afford or _refresh_phase != "idle"

func _tween_array(tw: Tween, arr: Array, idx: int, target: float,
		dur: float, delay: float = 0.0,
		trans: Tween.TransitionType = Tween.TRANS_LINEAR,
		ease_type: Tween.EaseType = Tween.EASE_IN_OUT) -> void:
	var tweener = tw.tween_method(
		func(v: float): arr[idx] = v,
		arr[idx], target, dur
	)
	if delay > 0.0:
		tweener.set_delay(delay)
	tweener.set_trans(trans).set_ease(ease_type)

# ---------------------------------------------------------------------------
# 按钮动效
# ---------------------------------------------------------------------------

func _btn_hover_tween(btn: Button, enter: bool) -> void:
	var target_scale: Vector2 = Vector2(1.05, 1.05) if enter else Vector2.ONE
	btn.pivot_offset = btn.size / 2.0
	var tw: Tween = btn.create_tween()
	tw.tween_property(btn, "scale", target_scale, 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

# ---------------------------------------------------------------------------
# 按钮回调
# ---------------------------------------------------------------------------

func _on_refresh_pressed() -> void:
	if _phase != "idle" or _refresh_phase != "idle":
		return
	if GameData.get_resource("money") < CardConfig.shop_refresh_cost:
		return

	GameData.modify_resource("money", -CardConfig.shop_refresh_cost)
	_update_money_display()
	_refresh_phase = "exit"

	# 旧卡牌旋转飞出
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	for i in range(CARD_COUNT):
		var spin_dir: float = 1.0 if randf() > 0.5 else -1.0
		var target_rot: float = spin_dir * deg_to_rad(10.0 + randf() * 10.0)
		_tween_array(tw, _card_alphas, i, 0.0, 0.22, i * 0.05, Tween.TRANS_BACK, Tween.EASE_IN)
		_tween_array(tw, _card_rots, i, target_rot, 0.22, i * 0.05, Tween.TRANS_BACK, Tween.EASE_IN)

	tw.chain().tween_callback(func():
		_refresh_goods()
		_refresh_phase = "enter"
		var tw2: Tween = create_tween()
		tw2.set_parallel(true)
		for j in range(_card_alphas.size()):
			_tween_array(tw2, _card_alphas, j, 1.0, 0.32, 0.06 + j * 0.08, Tween.TRANS_BACK, Tween.EASE_OUT)
			_tween_array(tw2, _card_rots, j, 0.0, 0.32, 0.06 + j * 0.08, Tween.TRANS_BACK, Tween.EASE_OUT)
		tw2.chain().tween_callback(func():
			_refresh_phase = "idle"
			_update_refresh_button_text()
		)
	)

func _on_leave_pressed() -> void:
	close_shop()

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
			# 面板外点击 = 关闭
			var panel_rect: Rect2 = _panel.get_global_rect()
			if not panel_rect.has_point(mb.global_position):
				close_shop()
				accept_event()
				return
			# 卡牌点击检测
			if _phase == "idle" and _refresh_phase == "idle":
				var local_pos: Vector2 = _cards_area.get_local_mouse_position()
				var hit_idx: int = _card_hit_test(local_pos)
				if hit_idx >= 0:
					if _sold[hit_idx]:
						_shake_card(hit_idx)
					else:
						_try_purchase(hit_idx)
					accept_event()
					return

	if event is InputEventMouseMotion:
		if _phase == "idle" and _refresh_phase == "idle":
			var local_pos: Vector2 = _cards_area.get_local_mouse_position()
			_hover_card = _card_hit_test(local_pos)

func _card_hit_test(local_pos: Vector2) -> int:
	var area_w: float = _cards_area.size.x
	var total_w: float = CARD_COUNT * CARD_W + (CARD_COUNT - 1) * CARD_GAP
	var start_x: float = (area_w - total_w) / 2.0
	for i in range(_goods.size()):
		var cx: float = start_x + i * (CARD_W + CARD_GAP)
		var cy: float = (_cards_area.size.y - CARD_H) / 2.0
		if Rect2(cx, cy, CARD_W, CARD_H).has_point(local_pos):
			return i
	return -1

func _try_purchase(index: int) -> void:
	var item_key: String = _goods[index]
	var info: Dictionary = ShopData.get_item_info(item_key)
	var price: int = info.get("price", 999)

	if GameData.get_resource("money") < price:
		_shake_card(index)
		return

	GameData.modify_resource("money", -price)
	var effect: Dictionary = info.get("effect", {})
	# 特殊效果: sanMax / healthMax 上限提升
	for ek in effect.keys():
		if ek == "sanMax":
			GameData.modify_resource_max("san", effect[ek])
		elif ek == "healthMax":
			GameData.modify_resource_max("health", effect[ek])
	GameData.apply_effects(effect)
	if info.get("type", "") in ["consumable", "persistent"]:
		GameData.add_item(item_key)

	_sold[index] = true
	_purchase_flash[index] = 1.0
	var tw: Tween = create_tween()
	tw.tween_method(func(v: float): _purchase_flash[index] = v, 1.0, 0.0, 0.4)

	_update_money_display()
	_update_refresh_button_text()

func _shake_card(index: int) -> void:
	var tw: Tween = create_tween()
	tw.tween_method(func(p: float):
		_card_shake_x[index] = sin(p * PI * 4.0) * 15.0 * (1.0 - p)
	, 0.0, 1.0, 0.4)
	tw.tween_callback(func(): _card_shake_x[index] = 0.0)

# ===========================================================================
# 渲染: 仅商品卡区域使用 _draw()
# ===========================================================================

func _process(_delta: float) -> void:
	if not _active:
		return
	# Hover 插值
	var speed: float = minf(1.0, _delta * 12.0)
	for i in range(_hover_card_t.size()):
		var target: float = 1.0 if _hover_card == i else 0.0
		_hover_card_t[i] += (target - _hover_card_t[i]) * speed
	_cards_area.queue_redraw()

func _draw_cards() -> void:
	if not _active:
		return

	var t = GameTheme
	var font: Font = ThemeDB.fallback_font
	var game_time: float = Time.get_ticks_msec() / 1000.0
	var area_w: float = _cards_area.size.x
	var area_h: float = _cards_area.size.y
	var total_w: float = CARD_COUNT * CARD_W + (CARD_COUNT - 1) * CARD_GAP
	var start_x: float = (area_w - total_w) / 2.0

	for i in range(_goods.size()):
		var alpha_i: float = _card_alphas[i] if i < _card_alphas.size() else 0.0
		if alpha_i < 0.01:
			continue

		var item_key: String = _goods[i]
		var info: Dictionary = ShopData.get_item_info(item_key)
		var sold: bool = _sold[i]
		var money: int = GameData.get_resource("money")
		var price: int = info.get("price", 999)
		var can_afford: bool = money >= price

		var hover_t: float = _hover_card_t[i] if i < _hover_card_t.size() else 0.0
		var rot: float = _card_rots[i] if i < _card_rots.size() else 0.0
		var shake_x: float = _card_shake_x[i] if i < _card_shake_x.size() else 0.0
		var flash: float = _purchase_flash[i] if i < _purchase_flash.size() else 0.0

		# 呼吸浮动 + hover 上浮
		var float_y: float = sin(game_time * 2.0 + i * 1.3) * 4.5
		var hover_lift: float = hover_t * 12.0
		var card_x: float = start_x + i * (CARD_W + CARD_GAP)
		var card_y: float = (area_h - CARD_H) / 2.0 + float_y - hover_lift
		var card_cx: float = card_x + CARD_W / 2.0 + shake_x
		var card_cy: float = card_y + CARD_H / 2.0
		var s: float = alpha_i * (1.0 + hover_t * 0.04)

		# 变换
		var xf: Transform2D = Transform2D()
		xf = xf.rotated(rot)
		xf = xf.scaled(Vector2(s, s))
		xf = xf.translated(Vector2(card_cx, card_cy))
		_cards_area.draw_set_transform_matrix(xf)

		var base_alpha: float = minf(alpha_i * 1.5, 1.0)
		var draw_alpha: float = base_alpha * (0.3 if sold else 1.0)

		var hw: float = CARD_W / 2.0
		var hh: float = CARD_H / 2.0
		var local_rect: Rect2 = Rect2(-hw, -hh, CARD_W, CARD_H)

		# 阴影
		_cards_area.draw_rect(Rect2(-hw + 3, -hh + 9, CARD_W + 6, CARD_H + 6),
			Color(0, 0, 0, 0.12 * draw_alpha))

		# 背景
		var bg_a: float = 0.82 if (sold or not can_afford) else 0.96
		_cards_area.draw_rect(local_rect,
			Color(t.card_face.r, t.card_face.g, t.card_face.b, bg_a * draw_alpha))

		# 边框
		if sold:
			_cards_area.draw_rect(local_rect,
				Color(t.safe.r, t.safe.g, t.safe.b, 0.78 * base_alpha), false, 6.0)
		elif can_afford:
			var ba: float = 0.4 + hover_t * 0.4
			_cards_area.draw_rect(local_rect,
				Color(t.info.r, t.info.g, t.info.b, ba * base_alpha), false, 3.6 + hover_t * 2.4)
		else:
			_cards_area.draw_rect(local_rect,
				Color(0.47, 0.47, 0.47, 0.27 * base_alpha), false, 3.0)

		# 购买闪光
		if flash > 0.01:
			_cards_area.draw_rect(local_rect,
				Color(t.safe.r, t.safe.g, t.safe.b, flash * 0.4 * base_alpha))

		if sold:
			# 已售出: 图标 + 大勾
			_cards_area.draw_string(font, Vector2(-hw, -24),
				info.get("icon", "?"), HORIZONTAL_ALIGNMENT_CENTER, CARD_W, 66,
				Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, draw_alpha))
			_cards_area.draw_string(font, Vector2(-hw, 42),
				"✓", HORIZONTAL_ALIGNMENT_CENTER, CARD_W, 102,
				Color(t.safe.r, t.safe.g, t.safe.b, 0.82 * base_alpha))
			_cards_area.draw_string(font, Vector2(-hw, hh - 24),
				"已购", HORIZONTAL_ALIGNMENT_CENTER, CARD_W, 33,
				Color(t.safe.r, t.safe.g, t.safe.b, 0.7 * base_alpha))
		else:
			var content_alpha: float = draw_alpha if can_afford else draw_alpha * 0.55

			# 图标
			var tex: Texture2D = ItemIcons.get_texture(item_key)
			if tex:
				var icon_size: float = 108.0
				var tex_rect: Rect2 = Rect2(-icon_size / 2.0, -hh + 12, icon_size, icon_size)
				_cards_area.draw_texture_rect(tex, tex_rect, false, Color(1, 1, 1, content_alpha))
			else:
				_cards_area.draw_string(font, Vector2(-hw, -hh + 90),
					info.get("icon", "?"), HORIZONTAL_ALIGNMENT_CENTER, CARD_W, 66,
					Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, content_alpha))

			# 名称
			_cards_area.draw_string(font, Vector2(-hw, -hh + 144),
				info.get("name", ""), HORIZONTAL_ALIGNMENT_CENTER, CARD_W, 33,
				Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, content_alpha))

			# 效果描述
			var desc_text: String = info.get("desc", "")
			if desc_text != "":
				_cards_area.draw_string(font, Vector2(-(CARD_W - 24) / 2.0, -hh + 198),
					desc_text, HORIZONTAL_ALIGNMENT_CENTER, CARD_W - 24, 30,
					Color(t.info.r, t.info.g, t.info.b, content_alpha * 0.78))

			# 价格
			var price_color: Color = t.highlight if can_afford else t.danger
			var price_alpha: float = content_alpha if can_afford else draw_alpha * 0.67
			_cards_area.draw_string(font, Vector2(-hw, hh - 24),
				"💰 " + str(price), HORIZONTAL_ALIGNMENT_CENTER, CARD_W, 36,
				Color(price_color.r, price_color.g, price_color.b, price_alpha))

			# Hover 提示
			if hover_t > 0.3 and can_afford:
				_cards_area.draw_string(font, Vector2(-hw, hh - 66),
					"点击购买", HORIZONTAL_ALIGNMENT_CENTER, CARD_W, 27,
					Color(t.info.r, t.info.g, t.info.b, hover_t * 0.63 * base_alpha))

	# 重置变换
	_cards_area.draw_set_transform_matrix(Transform2D.IDENTITY)
