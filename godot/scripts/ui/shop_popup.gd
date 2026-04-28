## ShopPopup - 商店弹窗
## 对应原版 ShopPopup.lua
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal shop_closed

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const POPUP_R: float = 14.0
const CARD_W: float = 78.0
const CARD_H: float = 110.0
const CARD_GAP: float = 14.0
const CARD_R: float = 10.0
const CARD_COUNT: int = 3
const BTN_H: float = 28.0
const BTN_R: float = 7.0
const REFRESH_BTN_W: float = 100.0
const LEAVE_BTN_W: float = 60.0
const BTN_GAP: float = 14.0

# 布局 Y (相对面板顶部)
const HEADER_Y: float = 12.0
const TITLE_Y: float = 40.0
const DESC_Y: float = 58.0
const DIVIDER_Y: float = 76.0
const CARDS_Y: float = 84.0

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _active: bool = false
var _phase: String = "none"  # "enter"|"idle"|"exit"|"none"
var _goods: Array = []
var _variant: Dictionary = {}
var _sold: Array = []

# 动画
var _overlay_alpha: float = 0.0
var _panel_alpha: float = 0.0
var _panel_scale: float = 1.0
var _header_t: float = 0.0
var _desc_t: float = 0.0
var _card_alphas: Array = []  # 每张商品卡的入场进度
var _card_rots: Array = []    # 每张卡牌旋转角(弧度)
var _card_shake_x: Array = [] # 抖动 X 偏移
var _purchase_flash: Array = []  # 购买闪光
var _refresh_t: float = 0.0
var _leave_t: float = 0.0

# Hover
var _hover_card: int = -1
var _hover_refresh: bool = false
var _hover_leave: bool = false
var _hover_card_t: Array = []
var _hover_refresh_t: float = 0.0
var _hover_leave_t: float = 0.0

# 刷新动画
var _refresh_phase: String = "idle"

# 缓存
var _popup_rect: Rect2 = Rect2()
var _btn_y: float = 0.0
var _popup_w: float = 0.0
var _popup_h: float = 0.0

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
func open_shop() -> void:
	_active = true
	_phase = "enter"
	visible = true
	_variant = ShopData.random_variant()
	_refresh_goods()

	_overlay_alpha = 0.0
	_panel_alpha = 0.0
	_panel_scale = 0.3
	_header_t = 0.0
	_desc_t = 0.0
	_refresh_t = 0.0
	_leave_t = 0.0
	_hover_card = -1
	_hover_refresh = false
	_hover_leave = false
	_hover_refresh_t = 0.0
	_hover_leave_t = 0.0
	_refresh_phase = "idle"

	# 面板入场
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_overlay_alpha", 0.45, 0.35)
	tw.tween_property(self, "_panel_alpha", 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_panel_scale", 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 标题 / 描述
	tw.tween_property(self, "_header_t", 1.0, 0.3).set_delay(0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_desc_t", 1.0, 0.25).set_delay(0.19).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 商品卡交错入场
	for i in range(_card_alphas.size()):
		var delay_i: float = 0.12 + 0.07 * (i + 2)
		tw.tween_property(self, "_card_alphas:" + str(i), 1.0, 0.35).set_delay(delay_i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "_card_rots:" + str(i), 0.0, 0.35).set_delay(delay_i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 按钮
	var btn_delay: float = 0.12 + 0.07 * (CARD_COUNT + 3)
	tw.tween_property(self, "_refresh_t", 1.0, 0.25).set_delay(btn_delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_leave_t", 1.0, 0.25).set_delay(btn_delay + 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func(): _phase = "idle")

func close_shop() -> void:
	if not _active or _phase == "exit":
		return
	_phase = "exit"
	# 卡牌飞散
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	for i in range(_card_alphas.size()):
		var spin: Array = [deg_to_rad(-15.0), 0.0, deg_to_rad(15.0)]
		tw.tween_property(self, "_card_alphas:" + str(i), 0.0, 0.2).set_delay(i * 0.03).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(self, "_card_rots:" + str(i), spin[i] if i < 3 else 0.0, 0.2).set_delay(i * 0.03).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "_overlay_alpha", 0.0, 0.25).set_delay(0.08)
	tw.tween_property(self, "_panel_alpha", 0.0, 0.25).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "_panel_scale", 0.5, 0.25).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "_header_t", 0.0, 0.15).set_delay(0.08)
	tw.tween_property(self, "_desc_t", 0.0, 0.15).set_delay(0.08)
	tw.tween_property(self, "_refresh_t", 0.0, 0.15).set_delay(0.08)
	tw.tween_property(self, "_leave_t", 0.0, 0.15).set_delay(0.08)
	tw.chain().tween_callback(_on_close_complete)

func _on_close_complete() -> void:
	_active = false
	visible = false
	_phase = "none"
	shop_closed.emit()

func is_active() -> bool:
	return _active

func _refresh_goods() -> void:
	_goods = ShopData.generate_shop_goods()
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

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if not _active or _phase != "idle":
		return

	if event is InputEventMouseMotion:
		_update_hover(event.position)
		accept_event()
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return

		var local_pos: Vector2 = mb.position
		var vp: Vector2 = get_viewport_rect().size
		_calc_layout(vp)

		# 检查关闭 - 面板外
		if not _popup_rect.has_point(local_pos):
			close_shop()
			accept_event()
			return

		# 检查商品卡点击
		if _refresh_phase == "idle":
			for i in range(_goods.size()):
				var card_rect: Rect2 = _get_card_rect(i)
				if card_rect.has_point(local_pos):
					if _sold[i]:
						_shake_card(i)
					else:
						_try_purchase(i)
					accept_event()
					return

		# 检查刷新按钮
		if _refresh_t > 0.5 and _refresh_phase == "idle":
			var refresh_rect: Rect2 = _get_refresh_button_rect()
			if refresh_rect.has_point(local_pos):
				_do_refresh()
				accept_event()
				return

		# 检查离开按钮
		if _leave_t > 0.5:
			var leave_rect: Rect2 = _get_leave_button_rect()
			if leave_rect.has_point(local_pos):
				close_shop()
				accept_event()
				return

		accept_event()

func _update_hover(pos: Vector2) -> void:
	var vp: Vector2 = get_viewport_rect().size
	_calc_layout(vp)

	_hover_card = -1
	_hover_refresh = false
	_hover_leave = false

	if _refresh_phase != "idle":
		return

	# 商品卡 hover
	for i in range(_goods.size()):
		if _sold[i]:
			continue
		var card_rect: Rect2 = _get_card_rect(i)
		if card_rect.has_point(pos):
			_hover_card = i
			break

	# 刷新按钮
	if _refresh_t > 0.5:
		var can_afford: bool = GameData.get_resource("money") >= ShopData.REFRESH_COST
		if can_afford:
			var refresh_rect: Rect2 = _get_refresh_button_rect()
			if refresh_rect.has_point(pos):
				_hover_refresh = true

	# 离开按钮
	if _leave_t > 0.5:
		var leave_rect: Rect2 = _get_leave_button_rect()
		if leave_rect.has_point(pos):
			_hover_leave = true

func _try_purchase(index: int) -> void:
	var item_key: String = _goods[index]
	var info: Dictionary = ShopData.get_item_info(item_key)
	var price: int = info.get("price", 999)

	if GameData.get_resource("money") < price:
		_shake_card(index)
		return

	# 扣钱
	GameData.modify_resource("money", -price)

	# 应用效果
	var effect: Dictionary = info.get("effect", {})
	GameData.apply_effects(effect)

	# 添加到道具栏
	if info.get("type", "") in ["consumable", "persistent"]:
		GameData.add_item(item_key)

	# 标记已售
	_sold[index] = true

	# 购买闪光
	_purchase_flash[index] = 1.0
	var tw: Tween = create_tween()
	tw.tween_property(self, "_purchase_flash:" + str(index), 0.0, 0.4)

func _shake_card(index: int) -> void:
	var tw: Tween = create_tween()
	tw.tween_method(func(p: float):
		_card_shake_x[index] = sin(p * PI * 4.0) * 5.0 * (1.0 - p)
	, 0.0, 1.0, 0.4)
	tw.tween_callback(func(): _card_shake_x[index] = 0.0)

func _do_refresh() -> void:
	if _refresh_phase != "idle":
		return
	if GameData.get_resource("money") < ShopData.REFRESH_COST:
		return

	GameData.modify_resource("money", -ShopData.REFRESH_COST)
	_refresh_phase = "exit"

	# 旧卡牌旋转飞出
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	for i in range(CARD_COUNT):
		var spin_dir: bool = 1.0 if randf() > 0.5 else -1.0
		var target_rot: float = spin_dir * deg_to_rad(10.0 + randf() * 10.0)
		tw.tween_property(self, "_card_alphas:" + str(i), 0.0, 0.22).set_delay(i * 0.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(self, "_card_rots:" + str(i), target_rot, 0.22).set_delay(i * 0.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	tw.chain().tween_callback(func():
		# 生成新商品
		_refresh_goods()
		_refresh_phase = "enter"
		# 新卡牌弹入
		var tw2: Tween = create_tween()
		tw2.set_parallel(true)
		for j in range(_card_alphas.size()):
			var rand_rot: bool = (1.0 if randf() > 0.5 else -1.0) * deg_to_rad(4.0 + randf() * 4.0)
			_card_rots[j] = rand_rot
			tw2.tween_property(self, "_card_alphas:" + str(j), 1.0, 0.32).set_delay(0.06 + j * 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw2.tween_property(self, "_card_rots:" + str(j), 0.0, 0.32).set_delay(0.06 + j * 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.chain().tween_callback(func(): _refresh_phase = "idle")
	)

# ---------------------------------------------------------------------------
# 布局
# ---------------------------------------------------------------------------
func _calc_layout(vp: Vector2) -> void:
	_popup_w = minf(310.0, vp.x * 0.8)
	_btn_y = CARDS_Y + CARD_H + 10.0
	_popup_h = _btn_y + BTN_H + 14.0
	var px: float = (vp.x - _popup_w) / 2.0
	var py: float = (vp.y - _popup_h) / 2.0
	_popup_rect = Rect2(px, py, _popup_w, _popup_h)

func _get_card_rect(index: int) -> Rect2:
	var total_w: float = CARD_COUNT * CARD_W + (CARD_COUNT - 1) * CARD_GAP
	var start_x: float = _popup_rect.position.x + (_popup_w - total_w) / 2.0
	var x: float = start_x + index * (CARD_W + CARD_GAP)
	var y: float = _popup_rect.position.y + CARDS_Y
	return Rect2(x, y, CARD_W, CARD_H)

func _get_refresh_button_rect() -> Rect2:
	var total_btn_w: float = REFRESH_BTN_W + BTN_GAP + LEAVE_BTN_W
	var x: float = _popup_rect.position.x + (_popup_w - total_btn_w) / 2.0
	var y: float = _popup_rect.position.y + _btn_y
	return Rect2(x, y, REFRESH_BTN_W, BTN_H)

func _get_leave_button_rect() -> Rect2:
	var total_btn_w: float = REFRESH_BTN_W + BTN_GAP + LEAVE_BTN_W
	var x: float = _popup_rect.position.x + (_popup_w - total_btn_w) / 2.0 + REFRESH_BTN_W + BTN_GAP
	var y: float = _popup_rect.position.y + _btn_y
	return Rect2(x, y, LEAVE_BTN_W, BTN_H)

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _active:
		return
	# Hover 插值
	var speed: float = minf(1.0, delta * 12.0)
	for i in range(_hover_card_t.size()):
		var target: bool = 1.0 if _hover_card == i else 0.0
		_hover_card_t[i] += (target - _hover_card_t[i]) * speed
	var r_target: float = 1.0 if _hover_refresh else 0.0
	_hover_refresh_t += (r_target - _hover_refresh_t) * speed
	var l_target: float = 1.0 if _hover_leave else 0.0
	_hover_leave_t += (l_target - _hover_leave_t) * speed

	queue_redraw()

func _draw() -> void:
	if not _active:
		return

	var vp: Vector2 = get_viewport_rect().size
	var t = GameTheme
	var font: Font = ThemeDB.fallback_font
	var game_time: float = Time.get_ticks_msec() / 1000.0

	_calc_layout(vp)

	# === 遮罩 ===
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, _overlay_alpha))

	if _panel_alpha < 0.01:
		return

	# === 面板 ===
	var cx: float = _popup_rect.get_center().x
	var cy: float = _popup_rect.get_center().y
	var hw: float = _popup_w / 2.0
	var hh: float = _popup_h / 2.0

	# 变换：缩放
	var xf: Transform2D = Transform2D()
	xf = xf.translated(-Vector2(cx, cy))
	xf = xf.scaled(Vector2(_panel_scale, _panel_scale))
	xf = xf.translated(Vector2(cx, cy))
	draw_set_transform_matrix(xf)
	modulate.a = _panel_alpha

	# 面板阴影
	var shadow_rect: Rect2 = Rect2(_popup_rect.position - Vector2(8, 4), _popup_rect.size + Vector2(16, 12))
	draw_rect(shadow_rect, Color(0, 0, 0, 0.15 * _panel_alpha))

	# 面板背景
	draw_rect(_popup_rect, Color(t.panel_bg.r, t.panel_bg.g, t.panel_bg.b, 0.96))
	draw_rect(_popup_rect, Color(t.panel_border.r, t.panel_border.g, t.panel_border.b, 0.47), false, 1.2)

	# 顶部色条
	var shop_color: Color = t.info
	var bar_rect: Rect2 = Rect2(_popup_rect.position.x + 4, _popup_rect.position.y + 4, _popup_w - 8, 5)
	draw_rect(bar_rect, Color(shop_color.r, shop_color.g, shop_color.b, 0.78))

	var panel_left: float = _popup_rect.position.x
	var panel_top: float = _popup_rect.position.y

	# === Header ===
	if _header_t > 0.01:
		var ha: float = _panel_alpha * _header_t
		# 购物车图标
		draw_string(font, Vector2(cx, panel_top + HEADER_Y + 18),
			"🛒", HORIZONTAL_ALIGNMENT_CENTER, -1, 26,
			Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, ha))
		# 店名
		draw_string(font, Vector2(cx, panel_top + TITLE_Y + 12),
			_variant.get("name", "商店"), HORIZONTAL_ALIGNMENT_CENTER, -1, 15,
			Color(shop_color.r, shop_color.g, shop_color.b, ha))

	# === 描述 ===
	if _desc_t > 0.01:
		var da: float = _panel_alpha * _desc_t
		var desc_offset: float = (1.0 - _desc_t) * 6.0
		draw_string(font, Vector2(cx, panel_top + DESC_Y + 10 + desc_offset),
			_variant.get("greeting", ""), HORIZONTAL_ALIGNMENT_CENTER, -1, 11,
			Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, da * 0.7))

	# === 分割线 ===
	draw_line(
		Vector2(panel_left + 16, panel_top + DIVIDER_Y),
		Vector2(panel_left + _popup_w - 16, panel_top + DIVIDER_Y),
		Color(t.panel_border.r, t.panel_border.g, t.panel_border.b, 0.24), 1.0)

	# === 三张商品卡 ===
	for i in range(_goods.size()):
		var alpha_i: float = _card_alphas[i] if i < _card_alphas.size() else 0.0
		if alpha_i < 0.01:
			continue
		_draw_item_card(i, alpha_i, game_time)

	# === 钱币显示 (左上角) ===
	var money_text: String = "💰 " + str(GameData.get_resource("money"))
	draw_string(font, Vector2(panel_left + 20, panel_top + 28),
		money_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, _panel_alpha))

	# === 按钮 ===
	_draw_buttons()

	# 重置变换
	draw_set_transform_matrix(Transform2D.IDENTITY)
	modulate.a = 1.0

# ---------------------------------------------------------------------------
# 绘制单张商品卡
# ---------------------------------------------------------------------------
func _draw_item_card(index: int, card_t: float, game_time: float) -> void:
	var t = GameTheme
	var font: Font = ThemeDB.fallback_font
	var item_key: String = _goods[index]
	var info: Dictionary = ShopData.get_item_info(item_key)
	var card_rect: Rect2 = _get_card_rect(index)

	var sold: bool = _sold[index]
	var money: int = GameData.get_resource("money")
	var price: int = info.get("price", 999)
	var can_afford: bool = money >= price

	var hover_t: float = _hover_card_t[index] if index < _hover_card_t.size() else 0.0
	var rot: float = _card_rots[index] if index < _card_rots.size() else 0.0
	var shake_x: float = _card_shake_x[index] if index < _card_shake_x.size() else 0.0
	var flash: float = _purchase_flash[index] if index < _purchase_flash.size() else 0.0

	# 呼吸浮动
	var float_y: float = sin(game_time * 2.0 + index * 1.3) * 1.5
	# Hover 上浮
	var hover_lift: float = hover_t * 4.0

	var card_cx: float = card_rect.get_center().x + shake_x
	var card_cy: float = card_rect.get_center().y + float_y - hover_lift
	var s: float = card_t * (1.0 + hover_t * 0.04)

	# 保存当前变换，在卡牌中心进行旋转和缩放
	var card_xf: Transform2D = Transform2D()
	card_xf = card_xf.translated(-Vector2(card_cx, card_cy))
	card_xf = card_xf.rotated(rot)
	card_xf = card_xf.scaled(Vector2(s, s))
	card_xf = card_xf.translated(Vector2(card_cx, card_cy))

	# 需要和面板缩放组合
	var panel_cx: float = _popup_rect.get_center().x
	var panel_cy: float = _popup_rect.get_center().y
	var panel_xf: Transform2D = Transform2D()
	panel_xf = panel_xf.translated(-Vector2(panel_cx, panel_cy))
	panel_xf = panel_xf.scaled(Vector2(_panel_scale, _panel_scale))
	panel_xf = panel_xf.translated(Vector2(panel_cx, panel_cy))

	draw_set_transform_matrix(panel_xf * card_xf)

	var base_alpha: float = _panel_alpha * minf(card_t * 1.5, 1.0)
	var draw_alpha: float = base_alpha * (0.3 if sold else 1.0)

	var hw: float = CARD_W / 2.0
	var hh: float = CARD_H / 2.0
	var local_rect: Rect2 = Rect2(-hw, -hh, CARD_W, CARD_H)

	# ── 卡牌阴影 ──
	var shadow_r: Rect2 = Rect2(-hw + 1, -hh + 3, CARD_W + 2, CARD_H + 2)
	draw_rect(shadow_r, Color(0, 0, 0, 0.12 * draw_alpha))

	# ── 卡牌背景 ──
	var bg_a: bool = 0.82 if (sold or not can_afford) else 0.96
	draw_rect(local_rect, Color(t.card_face.r, t.card_face.g, t.card_face.b, bg_a * draw_alpha))

	# ── 卡牌边框 ──
	if sold:
		draw_rect(local_rect, Color(t.safe.r, t.safe.g, t.safe.b, 0.78 * base_alpha), false, 2.0)
	elif can_afford:
		var ba: float = 0.4 + hover_t * 0.4
		var bw: float = 1.2 + hover_t * 0.8
		draw_rect(local_rect, Color(t.info.r, t.info.g, t.info.b, ba * base_alpha), false, bw)
	else:
		draw_rect(local_rect, Color(0.47, 0.47, 0.47, 0.27 * base_alpha), false, 1.0)

	# ── 购买闪光 ──
	if flash > 0.01:
		draw_rect(local_rect, Color(t.safe.r, t.safe.g, t.safe.b, flash * 0.4 * base_alpha))

	if sold:
		# === 已售出状态 ===
		# 暗淡的图标
		_draw_card_icon(info, item_key, Vector2(0, -hh + 22), draw_alpha)
		# 暗淡的名称
		draw_string(font, Vector2(0, -hh + 48),
			info.get("name", ""), HORIZONTAL_ALIGNMENT_CENTER, -1, 11,
			Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, draw_alpha))
		# ✓ 大勾
		draw_string(font, Vector2(0, 14),
			"✓", HORIZONTAL_ALIGNMENT_CENTER, -1, 34,
			Color(t.safe.r, t.safe.g, t.safe.b, 0.82 * base_alpha))
		# "已购" 小字
		draw_string(font, Vector2(0, hh - 8),
			"已购", HORIZONTAL_ALIGNMENT_CENTER, -1, 11,
			Color(t.safe.r, t.safe.g, t.safe.b, 0.7 * base_alpha))
	else:
		# === 可购 / 不可购 ===
		var content_alpha: float = draw_alpha if can_afford else draw_alpha * 0.55

		# 图标
		_draw_card_icon(info, item_key, Vector2(0, -hh + 22), content_alpha)

		# 名称
		draw_string(font, Vector2(0, -hh + 48),
			info.get("name", ""), HORIZONTAL_ALIGNMENT_CENTER, -1, 11,
			Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, content_alpha))

		# 效果描述
		var desc_text: String = info.get("desc", "")
		if desc_text != "":
			var desc_c: Color = Color(t.info.r, t.info.g, t.info.b, content_alpha * 0.78)
			draw_string(font, Vector2(0, -hh + 66),
				desc_text, HORIZONTAL_ALIGNMENT_CENTER, CARD_W - 8, 10, desc_c)

		# 价格 (底部)
		var price_color: Color = t.highlight if can_afford else t.danger
		var price_alpha: float = content_alpha if can_afford else draw_alpha * 0.67
		draw_string(font, Vector2(0, hh - 8),
			"💰 " + str(price), HORIZONTAL_ALIGNMENT_CENTER, -1, 12,
			Color(price_color.r, price_color.g, price_color.b, price_alpha))

		# Hover 提示
		if hover_t > 0.3 and can_afford:
			draw_string(font, Vector2(0, hh - 22),
				"点击购买", HORIZONTAL_ALIGNMENT_CENTER, -1, 9,
				Color(t.info.r, t.info.g, t.info.b, hover_t * 0.63 * base_alpha))

	# 恢复面板变换
	var restore_xf: Transform2D = Transform2D()
	restore_xf = restore_xf.translated(-Vector2(panel_cx, panel_cy))
	restore_xf = restore_xf.scaled(Vector2(_panel_scale, _panel_scale))
	restore_xf = restore_xf.translated(Vector2(panel_cx, panel_cy))
	draw_set_transform_matrix(restore_xf)

# ---------------------------------------------------------------------------
# 绘制卡牌图标 (纹理优先，emoji fallback)
# ---------------------------------------------------------------------------
func _draw_card_icon(info: Dictionary, item_key: String, center: Vector2, alpha: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var t = GameTheme

	# 尝试纹理图标
	var tex: Texture2D = ItemIcons.get_texture(item_key)
	if tex:
		var icon_size: float = 36.0
		var tex_rect: Rect2 = Rect2(center.x - icon_size / 2.0, center.y - icon_size / 2.0, icon_size, icon_size)
		draw_texture_rect(tex, tex_rect, false, Color(1, 1, 1, alpha))
	else:
		# Fallback: emoji
		draw_string(font, Vector2(center.x, center.y + 8),
			info.get("icon", "?"), HORIZONTAL_ALIGNMENT_CENTER, -1, 22,
			Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, alpha))

# ---------------------------------------------------------------------------
# 绘制底部按钮
# ---------------------------------------------------------------------------
func _draw_buttons() -> void:
	var t = GameTheme
	var font: Font = ThemeDB.fallback_font
	var money: int = GameData.get_resource("money")
	var can_refresh: bool = money >= ShopData.REFRESH_COST and _refresh_phase == "idle"

	# ── 刷新按钮 ──
	if _refresh_t > 0.01:
		var rect: Rect2 = _get_refresh_button_rect()
		var h_t: float = _hover_refresh_t

		# 背景色
		var bg_color: Color
		if can_refresh:
			bg_color = Color(
				t.info.r + (1.0 - t.info.r) * h_t * 0.25,
				t.info.g + (1.0 - t.info.g) * h_t * 0.25,
				t.info.b + (1.0 - t.info.b) * h_t * 0.25,
				0.72 * _refresh_t * _panel_alpha)
		else:
			bg_color = Color(0.4, 0.4, 0.4, 0.31 * _refresh_t * _panel_alpha)

		var s_btn: float = 1.0 + h_t * 0.05
		# 微缩放在按钮中心
		var btn_cx: float = rect.get_center().x
		var btn_cy: float = rect.get_center().y
		var scaled_rect: Rect2 = Rect2(
			btn_cx - rect.size.x * s_btn / 2.0,
			btn_cy - rect.size.y * s_btn / 2.0,
			rect.size.x * s_btn,
			rect.size.y * s_btn)
		draw_rect(scaled_rect, bg_color)

		var text_a: float = 0.92 if can_refresh else 0.4
		draw_string(font, Vector2(btn_cx, btn_cy + 5),
			"🔄 刷新 💰" + str(ShopData.REFRESH_COST),
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12,
			Color(1, 1, 1, text_a * _refresh_t * _panel_alpha))

	# ── 离开按钮 ──
	if _leave_t > 0.01:
		var rect: Rect2 = _get_leave_button_rect()
		var h_t: float = _hover_leave_t

		var bg_color: Color = Color(
			t.text_secondary.r + (1.0 - t.text_secondary.r) * h_t * 0.3,
			t.text_secondary.g + (1.0 - t.text_secondary.g) * h_t * 0.3,
			t.text_secondary.b + (1.0 - t.text_secondary.b) * h_t * 0.3,
			0.55 * _leave_t * _panel_alpha)

		var s_btn: float = 1.0 + h_t * 0.05
		var btn_cx: float = rect.get_center().x
		var btn_cy: float = rect.get_center().y
		var scaled_rect: Rect2 = Rect2(
			btn_cx - rect.size.x * s_btn / 2.0,
			btn_cy - rect.size.y * s_btn / 2.0,
			rect.size.x * s_btn,
			rect.size.y * s_btn)
		draw_rect(scaled_rect, bg_color)

		draw_string(font, Vector2(btn_cx, btn_cy + 5),
			"离开", HORIZONTAL_ALIGNMENT_CENTER, -1, 13,
			Color(1, 1, 1, 0.9 * _leave_t * _panel_alpha))
