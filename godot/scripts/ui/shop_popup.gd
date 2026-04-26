## ShopPopup - 商店弹窗
## 对应原版 ShopPopup.lua
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal shop_closed

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _active := false
var _phase := "none"
var _goods: Array = []  # 当前展示的商品 key 列表
var _variant: Dictionary = {}  # 当前商店变体
var _sold: Array = []  # 已售出标记

# 动画
var _overlay_alpha := 0.0
var _panel_alpha := 0.0
var _card_alphas: Array = []  # 每张商品卡的透明度

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

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_overlay_alpha", 0.45, 0.3)
	tw.tween_property(self, "_panel_alpha", 1.0, 0.35)
	# 商品卡交错入场
	for i in range(_card_alphas.size()):
		tw.tween_property(self, "_card_alphas:" + str(i), 1.0, 0.3).set_delay(0.1 + i * 0.08)
	tw.chain().tween_callback(func(): _phase = "idle")

func close_shop() -> void:
	if not _active or _phase == "exit":
		return
	_phase = "exit"
	var tw := create_tween()
	tw.tween_property(self, "_overlay_alpha", 0.0, 0.25)
	tw.tween_property(self, "_panel_alpha", 0.0, 0.2)
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
	for _i in range(_goods.size()):
		_sold.append(false)
		_card_alphas.append(0.0)

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if not _active or _phase != "idle":
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return

		var vp := get_viewport_rect().size
		var local_pos := mb.position

		# 检查关闭按钮
		var close_rect := _get_close_button_rect(vp)
		if close_rect.has_point(local_pos):
			close_shop()
			accept_event()
			return

		# 检查刷新按钮
		var refresh_rect := _get_refresh_button_rect(vp)
		if refresh_rect.has_point(local_pos):
			if GameData.get_resource("money") >= ShopData.REFRESH_COST:
				GameData.modify_resource("money", -ShopData.REFRESH_COST)
				_refresh_goods()
				# 重新播放入场动画
				for i in range(_card_alphas.size()):
					_card_alphas[i] = 0.0
				var tw := create_tween()
				for i in range(_card_alphas.size()):
					tw.tween_property(self, "_card_alphas:" + str(i), 1.0, 0.25).set_delay(i * 0.06)
			accept_event()
			return

		# 检查商品卡点击
		for i in range(_goods.size()):
			if _sold[i]:
				continue
			var card_rect := _get_card_rect(vp, i)
			if card_rect.has_point(local_pos):
				_try_purchase(i)
				accept_event()
				return

		accept_event()

func _try_purchase(index: int) -> void:
	var item_key: String = _goods[index]
	var info: Dictionary = ShopData.get_item_info(item_key)
	var price: int = info.get("price", 999)

	if GameData.get_resource("money") < price:
		# TODO: 抖动动画
		return

	# 扣钱
	GameData.modify_resource("money", -price)

	# 应用效果
	var effect: Dictionary = info.get("effect", {})
	GameData.apply_effects(effect)

	# 添加到道具栏 (如果是持久/消耗品)
	if info.get("type", "") in ["consumable", "persistent"]:
		GameData.add_item(item_key)

	# 标记已售
	_sold[index] = true

# ---------------------------------------------------------------------------
# 布局辅助
# ---------------------------------------------------------------------------

func _get_panel_rect(vp: Vector2) -> Rect2:
	var pw := vp.x * 0.75
	var ph := vp.y * 0.65
	return Rect2((vp.x - pw) / 2, (vp.y - ph) / 2, pw, ph)

func _get_card_rect(vp: Vector2, index: int) -> Rect2:
	var panel := _get_panel_rect(vp)
	var card_w := panel.size.x * 0.25
	var card_h := panel.size.y * 0.55
	var spacing := (panel.size.x - card_w * 3) / 4
	var x := panel.position.x + spacing + index * (card_w + spacing)
	var y := panel.position.y + panel.size.y * 0.25
	return Rect2(x, y, card_w, card_h)

func _get_close_button_rect(vp: Vector2) -> Rect2:
	var panel := _get_panel_rect(vp)
	return Rect2(panel.position.x + panel.size.x - 40, panel.position.y + 5, 35, 30)

func _get_refresh_button_rect(vp: Vector2) -> Rect2:
	var panel := _get_panel_rect(vp)
	var bw := 100.0
	var bh := 30.0
	return Rect2(panel.position.x + (panel.size.x - bw) / 2, panel.position.y + panel.size.y - 45, bw, bh)

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if _active:
		queue_redraw()

func _draw() -> void:
	if not _active:
		return

	var vp := get_viewport_rect().size
	var t = Theme
	var font := ThemeDB.fallback_font

	# 遮罩
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, _overlay_alpha))

	# 面板
	var panel := _get_panel_rect(vp)
	var panel_color := Color(t.notebook_paper.r, t.notebook_paper.g, t.notebook_paper.b, _panel_alpha * 0.95)
	draw_rect(panel, panel_color)
	draw_rect(panel, Color(t.card_border.r, t.card_border.g, t.card_border.b, _panel_alpha * 0.5), false, 2.0)

	if _panel_alpha < 0.1:
		return

	# 店名
	var title_color := Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, _panel_alpha)
	draw_string(font, Vector2(panel.position.x + panel.size.x / 2, panel.position.y + 30),
		_variant.get("name", "商店"), HORIZONTAL_ALIGNMENT_CENTER, -1, 20, title_color)

	# 欢迎语
	var greet_color := Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, _panel_alpha * 0.7)
	draw_string(font, Vector2(panel.position.x + panel.size.x / 2, panel.position.y + 55),
		_variant.get("greeting", ""), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, greet_color)

	# 商品卡
	for i in range(_goods.size()):
		var alpha: float = _card_alphas[i] if i < _card_alphas.size() else 0.0
		if alpha < 0.01:
			continue
		_draw_item_card(vp, i, alpha)

	# 关闭按钮
	var close_rect := _get_close_button_rect(vp)
	draw_string(font, Vector2(close_rect.position.x + 12, close_rect.position.y + 20), "✕",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 18, title_color)

	# 刷新按钮
	var refresh_rect := _get_refresh_button_rect(vp)
	var refresh_color := t.accent if GameData.get_resource("money") >= ShopData.REFRESH_COST else t.deferred
	refresh_color.a = _panel_alpha
	draw_rect(refresh_rect, refresh_color)
	draw_string(font, Vector2(refresh_rect.position.x + 50, refresh_rect.position.y + 20),
		"🔄 刷新 ($" + str(ShopData.REFRESH_COST) + ")",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1, 1, 1, _panel_alpha))

	# 钱币显示
	var money_text := "💰 " + str(GameData.get_resource("money"))
	draw_string(font, Vector2(panel.position.x + 20, panel.position.y + 30),
		money_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, title_color)

func _draw_item_card(vp: Vector2, index: int, alpha: float) -> void:
	var t = Theme
	var font := ThemeDB.fallback_font

	var item_key: String = _goods[index]
	var info: Dictionary = ShopData.get_item_info(item_key)
	var card_rect := _get_card_rect(vp, index)

	if _sold[index]:
		# 已售出 - 半透明
		alpha *= 0.3

	# 卡背景
	var bg := Color(t.card_face.r, t.card_face.g, t.card_face.b, alpha * 0.95)
	draw_rect(card_rect, bg)
	draw_rect(card_rect, Color(t.card_border.r, t.card_border.g, t.card_border.b, alpha * 0.5), false, 1.5)

	var cx := card_rect.position.x + card_rect.size.x / 2
	var cy := card_rect.position.y

	# 图标
	var icon_color := Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, alpha)
	draw_string(font, Vector2(cx, cy + card_rect.size.y * 0.3), info.get("icon", "?"),
		HORIZONTAL_ALIGNMENT_CENTER, -1, 36, icon_color)

	# 名称
	draw_string(font, Vector2(cx, cy + card_rect.size.y * 0.55), info.get("name", ""),
		HORIZONTAL_ALIGNMENT_CENTER, -1, 14, icon_color)

	# 价格
	var price_color := Color(t.warning.r, t.warning.g, t.warning.b, alpha)
	draw_string(font, Vector2(cx, cy + card_rect.size.y * 0.72), "$" + str(info.get("price", 0)),
		HORIZONTAL_ALIGNMENT_CENTER, -1, 16, price_color)

	# 描述
	var desc_color := Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, alpha * 0.7)
	draw_string(font, Vector2(cx, cy + card_rect.size.y * 0.88), info.get("desc", ""),
		HORIZONTAL_ALIGNMENT_CENTER, card_rect.size.x - 10, 10, desc_color)

	# 已售出标记
	if _sold[index]:
		draw_string(font, Vector2(cx, cy + card_rect.size.y * 0.5), "已售出",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(t.danger.r, t.danger.g, t.danger.b, 0.8))
