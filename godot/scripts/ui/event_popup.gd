## EventPopup - 事件弹窗系统
## 对应原版 EventPopup.lua
## 功能: 模态事件弹窗 + Toast 通知 + 裂隙确认弹窗 + 相片预览
class_name EventPopup
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal popup_closed(card: Card)
signal photo_popup_closed(card_type: String)
signal rift_confirmed()
signal rift_cancelled()
signal toast_dismissed(card_type: String)

# ---------------------------------------------------------------------------
# 常量: 弹窗尺寸
# ---------------------------------------------------------------------------
const POPUP_R: int = 14
const BTN_W: int = 100
const BTN_H: int = 32
const BTN_R: int = 8

# 裂隙弹窗
const RIFT_POPUP_W: int = 260
const RIFT_POPUP_H: int = 185
const RIFT_BTN_W: int = 100
const RIFT_BTN_H: int = 30
const RIFT_BTN_GAP: int = 12

# Toast
const TOAST_W: int = 220
const TOAST_R: int = 10
const TOAST_GAP: int = 8
const TOAST_MARGIN_R: int = 12
const TOAST_MARGIN_T: int = 52
const TOAST_MAX: int = 3
const TOAST_IDLE_TIME: float = 3.0
const TOAST_ENTER_TIME: float = 0.35
const TOAST_EXIT_TIME: float = 0.25

# 相片拍立得尺寸
const PHOTO_W: int = 200
const PHOTO_H: int = 260
const PHOTO_BORDER: int = 10
const PHOTO_BOTTOM: int = 40
const PHOTO_R: int = 3

# ---------------------------------------------------------------------------
# 阻塞判定
# ---------------------------------------------------------------------------
const BLOCKING_EVENTS: Dictionary = {
	"shop": true,
}

static func is_blocking_event(card_type: String, _has_choices: bool = false) -> bool:
	if card_type in BLOCKING_EVENTS:
		return true
	return false

# ===========================================================================
# 模态弹窗状态
# ===========================================================================
var _active: bool = false
var _card: Card = null
var _phase: String = "none"  # "enter" | "idle" | "exit"
var _is_photo_mode: bool = false
var _photo_card_type: String = ""
var _photo_location: String = ""
var _photo_rotation: float = 0.0  # 拍立得微倾角度
var _cached_desc: String = ""     # 缓存的事件描述文本 (避免每帧随机)

# 动画值
var _overlay_alpha: float = 0.0
var _panel_scale: float = 0.0
var _panel_alpha: float = 0.0
var _icon_t: float = 0.0
var _title_t: float = 0.0
var _desc_t: float = 0.0
var _effects_t: float = 0.0
var _button_t: float = 0.0
var _btn_hover_t: float = 0.0

# ===========================================================================
# 裂隙确认弹窗状态
# ===========================================================================
var _rift_active: bool = false
var _rift_phase: String = "none"
var _rift_cx: float = 0.0
var _rift_cy: float = 0.0
var _rift_overlay_alpha: float = 0.0
var _rift_popup_scale: float = 0.0
var _rift_popup_alpha: float = 0.0
var _rift_icon_t: float = 0.0
var _rift_title_t: float = 0.0
var _rift_desc_t: float = 0.0
var _rift_btn_enter_t: float = 0.0
var _rift_btn_stay_t: float = 0.0
var _rift_btn_enter_hover: float = 0.0
var _rift_btn_stay_hover: float = 0.0

# ===========================================================================
# Toast 系统状态
# ===========================================================================
var _toast_queue: Array = []  # Array of ToastInstance dictionaries
var _toast_next_id: int = 1

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

## 选择性命中检测：模态弹窗全屏拦截，toast 仅拦截其矩形区域
func _has_point(point: Vector2) -> bool:
	# 模态弹窗或裂隙弹窗：全屏拦截
	if _active or _rift_active:
		return true
	# Toast 模式：仅拦截 toast 矩形内的点击，其余透传
	if is_toast_active():
		for t in _toast_queue:
			if t["phase"] == "done" or t["phase"] == "exit":
				continue
			if t["draw_w"] > 0.0 and t["draw_h"] > 0.0:
				var rect: Rect2 = Rect2(t["draw_x"], t["draw_y"], t["draw_w"], t["draw_h"])
				if rect.has_point(point):
					return true
	return false

# ===========================================================================
# 模态弹窗 API
# ===========================================================================

## 打开事件弹窗 (常规模态)
func show_event(card: Card) -> void:
	_card = card
	_active = true
	_phase = "enter"
	_is_photo_mode = false
	_cached_desc = card.get_event_text()  # 缓存, 避免 _draw 中每帧随机
	visible = true

	_overlay_alpha = 0.0
	_panel_scale = 0.3
	_panel_alpha = 0.0
	_icon_t = 0.0
	_title_t = 0.0
	_desc_t = 0.0
	_effects_t = 0.0
	_button_t = 0.0
	_btn_hover_t = 0.0

	# 入场动画
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_overlay_alpha", 0.45, 0.35)
	tw.tween_property(self, "_panel_scale", 1.0, 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_panel_alpha", 1.0, 0.35)

	# 内容逐行错时入场
	var base: float = 0.12
	var stagger: float = 0.08
	tw.tween_property(self, "_icon_t", 1.0, 0.3).set_delay(base) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_title_t", 1.0, 0.3).set_delay(base + stagger) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_desc_t", 1.0, 0.3).set_delay(base + stagger * 2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "_effects_t", 1.0, 0.25).set_delay(base + stagger * 3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "_button_t", 1.0, 0.3).set_delay(base + stagger * 4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(func(): _phase = "idle")

## 拍照模式弹窗 (拍立得风格, 仅预览不结算)
func show_photo(card: Card) -> void:
	_card = card
	_active = true
	_phase = "enter"
	_is_photo_mode = true
	_photo_card_type = card.type
	_photo_location = card.location
	_photo_rotation = randf_range(-6.0, 6.0)
	_cached_desc = card.get_event_text()  # 缓存, 避免 _draw 中每帧随机
	visible = true

	_overlay_alpha = 0.0
	_panel_scale = 0.2
	_panel_alpha = 0.0
	_icon_t = 0.0
	_title_t = 0.0
	_desc_t = 0.0
	_button_t = 0.0
	_btn_hover_t = 0.0

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_overlay_alpha", 0.5, 0.3)
	tw.tween_property(self, "_panel_scale", 1.0, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_panel_alpha", 1.0, 0.3)

	var base: float = 0.08
	tw.tween_property(self, "_icon_t", 1.0, 0.25).set_delay(base) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_title_t", 1.0, 0.25).set_delay(base + 0.06) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_desc_t", 1.0, 0.25).set_delay(base + 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "_button_t", 1.0, 0.25).set_delay(base + 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(func(): _phase = "idle")

func dismiss() -> void:
	if not _active or _phase == "exit":
		return
	_phase = "exit"
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_overlay_alpha", 0.0, 0.22)
	tw.tween_property(self, "_panel_scale", 0.5, 0.22) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_panel_alpha", 0.0, 0.22)
	tw.tween_property(self, "_icon_t", 0.0, 0.15)
	tw.tween_property(self, "_title_t", 0.0, 0.15)
	tw.tween_property(self, "_desc_t", 0.0, 0.15)
	tw.tween_property(self, "_effects_t", 0.0, 0.15)
	tw.tween_property(self, "_button_t", 0.0, 0.15)
	tw.chain().tween_callback(_on_dismiss_complete)

func _on_dismiss_complete() -> void:
	_active = false
	_phase = "none"
	if _is_photo_mode:
		_is_photo_mode = false
		photo_popup_closed.emit(_photo_card_type)
		_photo_card_type = ""
		_photo_location = ""
	else:
		popup_closed.emit(_card)
	_card = null
	_update_visibility()

func is_active() -> bool:
	return _active

# ===========================================================================
# 裂隙确认弹窗 API
# ===========================================================================

## 显示裂隙确认弹窗
func show_rift_confirm(cx: float, cy: float) -> void:
	_rift_active = true
	_rift_phase = "enter"
	_rift_cx = cx
	_rift_cy = cy
	visible = true

	_rift_overlay_alpha = 0.0
	_rift_popup_scale = 0.3
	_rift_popup_alpha = 0.0
	_rift_icon_t = 0.0
	_rift_title_t = 0.0
	_rift_desc_t = 0.0
	_rift_btn_enter_t = 0.0
	_rift_btn_stay_t = 0.0
	_rift_btn_enter_hover = 0.0
	_rift_btn_stay_hover = 0.0

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_rift_overlay_alpha", 0.4, 0.35)
	tw.tween_property(self, "_rift_popup_scale", 1.0, 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_rift_popup_alpha", 1.0, 0.35)

	var base: float = 0.12
	tw.tween_property(self, "_rift_icon_t", 1.0, 0.3).set_delay(base) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_rift_title_t", 1.0, 0.3).set_delay(base + 0.08) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_rift_desc_t", 1.0, 0.3).set_delay(base + 0.16) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "_rift_btn_enter_t", 1.0, 0.3).set_delay(base + 0.24) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_rift_btn_stay_t", 1.0, 0.3).set_delay(base + 0.30) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(func(): _rift_phase = "idle")

func dismiss_rift(accepted: bool) -> void:
	if not _rift_active or _rift_phase == "exit":
		return
	_rift_phase = "exit"
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_rift_overlay_alpha", 0.0, 0.22)
	tw.tween_property(self, "_rift_popup_scale", 0.5, 0.22) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "_rift_popup_alpha", 0.0, 0.22)
	tw.tween_property(self, "_rift_icon_t", 0.0, 0.15)
	tw.tween_property(self, "_rift_title_t", 0.0, 0.15)
	tw.tween_property(self, "_rift_desc_t", 0.0, 0.15)
	tw.tween_property(self, "_rift_btn_enter_t", 0.0, 0.15)
	tw.tween_property(self, "_rift_btn_stay_t", 0.0, 0.15)
	tw.chain().tween_callback(func():
		_rift_active = false
		_rift_phase = "none"
		if accepted:
			rift_confirmed.emit()
		else:
			rift_cancelled.emit()
		_update_visibility()
	)

func is_rift_confirm_active() -> bool:
	return _rift_active

# ===========================================================================
# Toast API
# ===========================================================================

## 推送一条非阻塞事件 Toast
func show_toast(card_type: String, applied_effects: Dictionary = {},
		shield_used: bool = false, location: String = "",
		trap_subtype: String = "") -> void:
	visible = true

	var tid: int = _toast_next_id
	_toast_next_id += 1

	# 文案
	var tmpl: Dictionary = _pick_template(card_type, trap_subtype)

	# 暗面世界标题
	var display_title: String = tmpl["title"]
	if location != "":
		var dark_info: Dictionary = Card.DARKSIDE_INFO.get(location, {}).get(card_type, {})
		if dark_info.has("label"):
			display_title = dark_info["label"]

	# 陷阱子类型图标
	var display_icon: String = GameTheme.card_type_info(card_type).get("icon", "❓")
	if card_type == "trap" and trap_subtype != "":
		var sub_info: Dictionary = Card.TRAP_SUBTYPE_INFO.get(trap_subtype, {})
		if sub_info.has("icon"):
			display_icon = sub_info["icon"]

	var toast: Dictionary = {
		"id": tid,
		"card_type": card_type,
		"trap_subtype": trap_subtype,
		"title": display_title,
		"desc": tmpl["desc"],
		"icon": display_icon,
		"effects": applied_effects,
		"shield_used": shield_used,
		"phase": "enter",  # enter → idle → exit → done
		"timer": 0.0,
		# 动画属性
		"slide_x": TOAST_W + TOAST_MARGIN_R + 20.0,
		"alpha": 0.0,
		"scale_val": 0.8,
		"target_y": 0.0,
		"current_y": 0.0,
		# 碰撞区域 (draw 时更新)
		"draw_x": 0.0, "draw_y": 0.0,
		"draw_w": 0.0, "draw_h": 0.0,
	}

	_toast_queue.append(toast)

	# 溢出：强制退场最老的
	var visible_count: int = 0
	for t in _toast_queue:
		if t["phase"] != "exit" and t["phase"] != "done":
			visible_count += 1
	if visible_count > TOAST_MAX:
		for t in _toast_queue:
			if t["phase"] != "exit" and t["phase"] != "done":
				_start_toast_exit(t)
				break

	# 入场 tween
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(v: float): toast["slide_x"] = v, toast["slide_x"], 0.0, TOAST_ENTER_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_method(func(v: float): toast["alpha"] = v, 0.0, 1.0, TOAST_ENTER_TIME)
	tw.tween_method(func(v: float): toast["scale_val"] = v, 0.8, 1.0, TOAST_ENTER_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(func():
		if toast["phase"] == "enter":
			toast["phase"] = "idle"
			toast["timer"] = 0.0
	)

func _start_toast_exit(toast: Dictionary) -> void:
	toast["phase"] = "exit"
	toast["timer"] = 0.0
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(v: float): toast["slide_x"] = v, toast["slide_x"], TOAST_W + 30.0, TOAST_EXIT_TIME) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float): toast["alpha"] = v, toast["alpha"], 0.0, TOAST_EXIT_TIME)
	tw.tween_method(func(v: float): toast["scale_val"] = v, toast["scale_val"], 0.85, TOAST_EXIT_TIME)
	tw.chain().tween_callback(func(): toast["phase"] = "done")

func is_toast_active() -> bool:
	return _toast_queue.size() > 0

func clear_toasts() -> void:
	_toast_queue.clear()

# ===========================================================================
# 全局查询
# ===========================================================================

func is_any_active() -> bool:
	return _active or _rift_active or is_toast_active()

# ===========================================================================
# 输入处理
# ===========================================================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = mb.position
			# 优先级: 裂隙确认 > 模态弹窗 > Toast
			if _rift_active:
				_handle_rift_click(pos)
				accept_event()
				return
			if _active:
				_handle_popup_click(pos)
				accept_event()
				return
			if _handle_toast_click(pos):
				accept_event()
				return

func _handle_popup_click(pos: Vector2) -> void:
	if _phase == "enter":
		return  # 入场中不处理
	if _is_photo_mode:
		dismiss()
		return
	# 点击任意处关闭
	dismiss()

func _handle_rift_click(pos: Vector2) -> void:
	if _rift_phase == "enter":
		return
	var hit: String = _rift_btn_hit_test(pos)
	if hit == "enter":
		dismiss_rift(true)
	elif hit == "stay":
		dismiss_rift(false)
	else:
		# 面板外点击 = 留下
		var px: float = _rift_cx - RIFT_POPUP_W / 2.0
		var py: float = _rift_cy - RIFT_POPUP_H / 2.0
		if not Rect2(px, py, RIFT_POPUP_W, RIFT_POPUP_H).has_point(pos):
			dismiss_rift(false)

func _handle_toast_click(pos: Vector2) -> bool:
	# 从最新往最老遍历
	for i in range(_toast_queue.size() - 1, -1, -1):
		var t: Dictionary = _toast_queue[i]
		if t["phase"] == "done" or t["phase"] == "exit":
			continue
		var rect: Rect2 = Rect2(t["draw_x"], t["draw_y"], t["draw_w"], t["draw_h"])
		if rect.has_point(pos):
			_start_toast_exit(t)
			return true
	return false

func _rift_btn_hit_test(pos: Vector2) -> String:
	var btn_y: float = _rift_cy + RIFT_POPUP_H / 2.0 - RIFT_BTN_H - 14.0
	var total_w: float = RIFT_BTN_W * 2.0 + RIFT_BTN_GAP
	var start_x: float = _rift_cx - total_w / 2.0
	# 进入按钮
	if Rect2(start_x, btn_y, RIFT_BTN_W, RIFT_BTN_H).has_point(pos):
		return "enter"
	# 留下按钮
	var stay_x: float = start_x + RIFT_BTN_W + RIFT_BTN_GAP
	if Rect2(stay_x, btn_y, RIFT_BTN_W, RIFT_BTN_H).has_point(pos):
		return "stay"
	return ""

# ===========================================================================
# 每帧更新
# ===========================================================================
func _process(delta: float) -> void:
	_update_toasts(delta)
	_update_visibility()
	if visible:
		queue_redraw()

func _update_visibility() -> void:
	visible = _active or _rift_active or is_toast_active()

func _update_toasts(delta: float) -> void:
	# 更新计时器 + 自动退场
	for t in _toast_queue:
		t["timer"] += delta
		if t["phase"] == "idle" and t["timer"] >= TOAST_IDLE_TIME:
			_start_toast_exit(t)

	# 移除已完成的
	var i: float = _toast_queue.size() - 1
	while i >= 0:
		if _toast_queue[i]["phase"] == "done":
			var removed_type: String = _toast_queue[i]["card_type"]
			_toast_queue.remove_at(i)
			toast_dismissed.emit(removed_type)
		i -= 1

	# 计算目标 Y (从上往下排列)
	var slot: int = 0
	for t in _toast_queue:
		if t["phase"] != "done":
			t["target_y"] = TOAST_MARGIN_T + slot * (_toast_item_h(t) + TOAST_GAP)
			slot += 1

	# 平滑 Y
	for t in _toast_queue:
		if t["phase"] == "enter" and t["timer"] < 0.05:
			t["current_y"] = t["target_y"]
		else:
			t["current_y"] = lerpf(t["current_y"], t["target_y"], minf(1.0, delta * 12.0))

# ===========================================================================
# 工具方法
# ===========================================================================

func _pick_template(card_type: String, trap_subtype: String = "") -> Dictionary:
	# 陷阱子类型使用专属文案池
	if card_type == "trap" and trap_subtype != "":
		var sub_texts: Array = Card.TRAP_SUBTYPE_TEXTS.get(trap_subtype, [])
		if sub_texts.size() > 0:
			var text: String = sub_texts[randi() % sub_texts.size()]
			var sub_info: Dictionary = Card.TRAP_SUBTYPE_INFO.get(trap_subtype, {})
			return { "title": sub_info.get("label", "陷阱"), "desc": text }

	var texts: Array = Card.EVENT_TEXTS.get(card_type, ["发生了一些事情..."])
	var type_info: Dictionary = GameTheme.card_type_info(card_type)
	return { "title": type_info.get("label", "未知"), "desc": texts[randi() % texts.size()] }

func _toast_item_h(toast: Dictionary) -> float:
	var h: float = 42.0  # 色条 + 图标/标题行
	h += 28.0      # 描述行
	if toast["shield_used"] or toast["effects"].size() > 0:
		h += 24.0  # 徽章行
	h += 12.0      # 进度条 + 底部间距
	return h

# ===========================================================================
# 渲染: 主入口
# ===========================================================================
func _draw() -> void:
	# Toast 先绘制 (最底层)
	_draw_toasts()

	# 模态弹窗
	if _active and _card != null:
		if _is_photo_mode:
			_draw_photo()
		else:
			_draw_event()

	# 裂隙确认弹窗 (最顶层)
	if _rift_active:
		_draw_rift_confirm()

# ===========================================================================
# 渲染: 模态事件弹窗
# ===========================================================================
func _draw_event() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var t = GameTheme
	var font: Font = ThemeDB.fallback_font

	# 遮罩
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, _overlay_alpha))

	# 面板尺寸
	var popup_w: float = vp.x * 0.7
	var popup_h: float = vp.y * 0.55
	var cx: float = vp.x / 2.0
	var cy: float = vp.y / 2.0
	var scaled_w: float = popup_w * _panel_scale
	var scaled_h: float = popup_h * _panel_scale
	var panel_x: float = cx - scaled_w / 2.0
	var panel_y: float = cy - scaled_h / 2.0

	# 面板背景
	var panel_color: Color = Color(t.card_face.r, t.card_face.g, t.card_face.b, _panel_alpha * 0.95)
	draw_rect(Rect2(panel_x, panel_y, scaled_w, scaled_h), panel_color)

	# 面板边框
	var border_color: Color = Color(t.card_border.r, t.card_border.g, t.card_border.b, _panel_alpha * 0.6)
	draw_rect(Rect2(panel_x, panel_y, scaled_w, scaled_h), border_color, false, 2.0)

	if _panel_alpha < 0.01:
		return

	# 类型色条
	var type_color: Color = t.card_type_color(_card.type)
	type_color.a = _panel_alpha * 0.8
	draw_rect(Rect2(panel_x + 8, panel_y + 8, scaled_w - 16, 6), type_color)

	# 内容
	var darkside: Dictionary = _card.get_darkside_info()
	var content_alpha: float = _panel_alpha

	# 图标
	if _icon_t > 0.01:
		var icon_color: Color = Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, content_alpha * _icon_t)
		draw_string(font, Vector2(cx - 20, cy - 50 + (1.0 - _icon_t) * 15),
			darkside.get("icon", "❓"),
			HORIZONTAL_ALIGNMENT_CENTER, -1, 42, icon_color)

	# 标题
	if _title_t > 0.01:
		var title_color: Color = Color(type_color.r, type_color.g, type_color.b, content_alpha * _title_t)
		var label_text: String = darkside.get("label", "未知事件")
		draw_string(font, Vector2(cx, cy - 8 + (1.0 - _title_t) * 10),
			label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18, title_color)

	# 描述
	if _desc_t > 0.01:
		var desc_color: Color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, content_alpha * _desc_t)
		draw_string(font, Vector2(cx, cy + 22 + (1.0 - _desc_t) * 10),
			_cached_desc, HORIZONTAL_ALIGNMENT_CENTER, scaled_w * 0.8, 12, desc_color)

	# 效果徽章
	if _effects_t > 0.01:
		var effects: Dictionary = _card.get_effects()
		var ey: float = cy + 55.0
		for key in effects:
			var delta_val: int = effects[key]
			var prefix: String = "+" if delta_val > 0 else ""
			var icon_str: String = GameData.RESOURCE_ICONS.get(key, "")
			var effect_text: String = icon_str + " " + prefix + str(delta_val)
			var effect_color: Color = t.safe if delta_val > 0 else t.danger
			effect_color.a = content_alpha * _effects_t
			draw_string(font, Vector2(cx, ey), effect_text,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 14, effect_color)
			ey += 22.0

	# 关闭提示
	if _button_t > 0.01:
		var btn_color: Color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, _button_t * 0.6)
		draw_string(font, Vector2(cx, panel_y + scaled_h - 24), "点击关闭",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, btn_color)

# ===========================================================================
# 渲染: 相片预览 (拍立得风格)
# ===========================================================================
func _draw_photo() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var t = GameTheme
	var font: Font = ThemeDB.fallback_font
	var cx: float = vp.x / 2.0
	var cy: float = vp.y / 2.0

	# 遮罩 (比普通弹窗更暗)
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, _overlay_alpha))

	if _panel_alpha < 0.01:
		return

	var type_color: Color = t.card_type_color(_card.type)
	var darkside: Dictionary = _card.get_darkside_info()

	# 使用 draw_set_transform 实现缩放+旋转
	var xform: Transform2D = Transform2D.IDENTITY
	xform = xform.translated(-Vector2(cx, cy))
	xform = xform.rotated(deg_to_rad(_photo_rotation))
	xform = xform.scaled(Vector2(_panel_scale, _panel_scale))
	xform = xform.translated(Vector2(cx, cy))
	draw_set_transform_matrix(xform)

	var hw: float = PHOTO_W / 2.0
	var hh: float = PHOTO_H / 2.0
	var photo_x: float = cx - hw
	var photo_y: float = cy - hh

	# 相片白底 (略带暖白)
	var paper_color: Color = Color(0.988, 0.980, 0.961, _panel_alpha * 0.98)
	draw_rect(Rect2(photo_x, photo_y, PHOTO_W, PHOTO_H), paper_color)

	# 相片边框
	var edge_color: Color = Color(0.824, 0.784, 0.725, _panel_alpha * 0.47)
	draw_rect(Rect2(photo_x, photo_y, PHOTO_W, PHOTO_H), edge_color, false, 0.8)

	# 内部照片区
	var img_x: float = photo_x + PHOTO_BORDER
	var img_y: float = photo_y + PHOTO_BORDER
	var img_w: float = PHOTO_W - PHOTO_BORDER * 2.0
	var img_h: int = PHOTO_H - PHOTO_BORDER - PHOTO_BOTTOM

	# 照片底色 (暗蓝灰)
	draw_rect(Rect2(img_x, img_y, img_w, img_h), Color(0.098, 0.118, 0.157, _panel_alpha * 0.94))

	# 照片内氛围色 (事件类型颜色)
	var atmos_color: Color = Color(type_color.r, type_color.g, type_color.b, _panel_alpha * 0.15)
	draw_rect(Rect2(img_x, img_y, img_w, img_h), atmos_color)

	# 事件图标
	if _icon_t > 0.01:
		var icon_color: Color = Color(1, 1, 1, _panel_alpha * _icon_t * 0.9)
		draw_string(font, Vector2(img_x + img_w / 2.0 - 20, img_y + img_h / 2.0 - 12),
			darkside.get("icon", "❓"),
			HORIZONTAL_ALIGNMENT_CENTER, -1, 42, icon_color)

	# 事件标题
	if _title_t > 0.01:
		var title_color: Color = Color(type_color.r, type_color.g, type_color.b, _panel_alpha * _title_t * 0.9)
		draw_string(font, Vector2(img_x + img_w / 2.0, img_y + img_h / 2.0 + 24 + (1.0 - _title_t) * 10),
			darkside.get("label", ""), HORIZONTAL_ALIGNMENT_CENTER, -1, 16, title_color)

	# 描述
	if _desc_t > 0.01:
		var desc_color: Color = Color(0.784, 0.784, 0.824, _panel_alpha * _desc_t * 0.7)
		draw_string(font, Vector2(img_x + 10, img_y + img_h / 2.0 + 48 + (1.0 - _desc_t) * 8),
			_cached_desc, HORIZONTAL_ALIGNMENT_LEFT, img_w - 20, 10, desc_color)

	# 照片区内边框
	draw_rect(Rect2(img_x, img_y, img_w, img_h), Color(0, 0, 0, _panel_alpha * 0.16), false, 0.6)

	# 底部白边区域 (拍立得签名区)
	if _button_t > 0.01:
		var bottom_y: float = img_y + img_h + 6.0
		# 地点名
		var loc_info: Dictionary = Card.LOCATION_INFO.get(_photo_location, {})
		var loc_label: String = loc_info.get("icon", "") + " " + loc_info.get("label", "")
		var loc_color: Color = Color(0.314, 0.294, 0.255, _panel_alpha * _button_t * 0.78)
		draw_string(font, Vector2(photo_x + PHOTO_BORDER + 2, bottom_y + 14),
			loc_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, loc_color)

		# 侦察标记
		var scout_color: Color = Color(0.588, 0.549, 0.490, _panel_alpha * _button_t * 0.63)
		draw_string(font, Vector2(photo_x + PHOTO_W - PHOTO_BORDER - 2, bottom_y + 14),
			"📷 侦察", HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, scout_color)

	# 顶部胶带装饰
	var tape_w: float = 36.0
	var tape_h: float = 10.0
	var tape_x: float = cx - tape_w / 2.0
	var tape_y: float = photo_y - tape_h / 2.0
	var tape_color: Color = Color(0.863, 0.824, 0.706, _panel_alpha * 0.63)
	draw_rect(Rect2(tape_x, tape_y, tape_w, tape_h), tape_color)
	draw_line(Vector2(tape_x, tape_y + tape_h * 0.5),
		Vector2(tape_x + tape_w, tape_y + tape_h * 0.5),
		Color(0.784, 0.745, 0.647, _panel_alpha * 0.24), 0.5)

	# 关闭提示
	if _button_t > 0.01:
		var hint_color: Color = Color(0.706, 0.667, 0.608, _panel_alpha * _button_t * 0.7)
		draw_string(font, Vector2(cx, photo_y + PHOTO_H + 14),
			"点击任意处关闭", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, hint_color)

	# 重置 transform
	draw_set_transform_matrix(Transform2D.IDENTITY)

# ===========================================================================
# 渲染: 裂隙确认弹窗
# ===========================================================================
func _draw_rift_confirm() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var t = GameTheme
	var font: Font = ThemeDB.fallback_font

	# 遮罩
	if _rift_overlay_alpha > 0.01:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, _rift_overlay_alpha))

	if _rift_popup_alpha < 0.01:
		return

	# 使用 transform 实现缩放
	var xform: Transform2D = Transform2D.IDENTITY
	xform = xform.translated(-Vector2(_rift_cx, _rift_cy))
	xform = xform.scaled(Vector2(_rift_popup_scale, _rift_popup_scale))
	xform = xform.translated(Vector2(_rift_cx, _rift_cy))
	draw_set_transform_matrix(xform)

	var hw: float = RIFT_POPUP_W / 2.0
	var hh: float = RIFT_POPUP_H / 2.0
	var px: float = _rift_cx - hw
	var py: float = _rift_cy - hh

	# 面板背景
	var panel_color: Color = Color(t.panel_bg.r, t.panel_bg.g, t.panel_bg.b, _rift_popup_alpha * 0.96)
	draw_rect(Rect2(px, py, RIFT_POPUP_W, RIFT_POPUP_H), panel_color)

	# 面板边框 (暗面风格)
	var border_color: Color = Color(t.dark_accent.r, t.dark_accent.g, t.dark_accent.b, _rift_popup_alpha * 0.4)
	draw_rect(Rect2(px, py, RIFT_POPUP_W, RIFT_POPUP_H), border_color, false, 1.2)

	# 顶部色条
	var accent_color: Color = Color(t.dark_accent.r, t.dark_accent.g, t.dark_accent.b, _rift_popup_alpha)
	draw_rect(Rect2(px, py, RIFT_POPUP_W, 4), accent_color)

	# 图标
	if _rift_icon_t > 0.01:
		var icon_color: Color = Color(t.dark_accent.r, t.dark_accent.g, t.dark_accent.b, _rift_popup_alpha * _rift_icon_t)
		draw_string(font, Vector2(_rift_cx - 18, py + 40 + (1.0 - _rift_icon_t) * 15),
			"🌀", HORIZONTAL_ALIGNMENT_CENTER, -1, 36, icon_color)

	# 标题
	if _rift_title_t > 0.01:
		var title_color: Color = Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, _rift_popup_alpha * _rift_title_t)
		draw_string(font, Vector2(_rift_cx, py + 70 + (1.0 - _rift_title_t) * 10),
			"发现空间裂隙", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, title_color)

	# 描述
	if _rift_desc_t > 0.01:
		var desc_color: Color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, _rift_popup_alpha * _rift_desc_t * 0.7)
		draw_string(font, Vector2(_rift_cx, py + 92 + (1.0 - _rift_desc_t) * 8),
			"此处出现通往暗面世界的裂隙", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, desc_color)
		draw_string(font, Vector2(_rift_cx, py + 108 + (1.0 - _rift_desc_t) * 8),
			"是否要进入？", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, desc_color)

	# 双按钮
	var btn_y: float = _rift_cy + hh - RIFT_BTN_H - 14.0
	var total_w: float = RIFT_BTN_W * 2.0 + RIFT_BTN_GAP
	var start_x: float = _rift_cx - total_w / 2.0

	# "进入暗面" 按钮
	if _rift_btn_enter_t > 0.01:
		var bx: float = start_x
		var enter_alpha: float = _rift_popup_alpha * _rift_btn_enter_t
		var da: Color = t.dark_accent
		var hover: float = _rift_btn_enter_hover
		var btn_bg: Color = Color(
			da.r + (1.0 - da.r) * hover * 0.15,
			da.g + (1.0 - da.g) * hover * 0.15,
			da.b + (1.0 - da.b) * hover * 0.15,
			enter_alpha * 0.86)
		draw_rect(Rect2(bx, btn_y + (1.0 - _rift_btn_enter_t) * 15, RIFT_BTN_W, RIFT_BTN_H), btn_bg)
		var btn_text_color: Color = Color(1, 1, 1, enter_alpha * 0.94)
		draw_string(font, Vector2(bx + RIFT_BTN_W / 2.0, btn_y + RIFT_BTN_H / 2.0 + 5 + (1.0 - _rift_btn_enter_t) * 15),
			"进入暗面", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, btn_text_color)

	# "留在原地" 按钮
	if _rift_btn_stay_t > 0.01:
		var bx: float = start_x + RIFT_BTN_W + RIFT_BTN_GAP
		var stay_alpha: float = _rift_popup_alpha * _rift_btn_stay_t
		var stay_bg: Color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, stay_alpha * 0.24)
		draw_rect(Rect2(bx, btn_y + (1.0 - _rift_btn_stay_t) * 15, RIFT_BTN_W, RIFT_BTN_H), stay_bg)
		var stay_border: Color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, stay_alpha * 0.47)
		draw_rect(Rect2(bx, btn_y + (1.0 - _rift_btn_stay_t) * 15, RIFT_BTN_W, RIFT_BTN_H), stay_border, false, 1.0)
		var stay_text_color: Color = Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, stay_alpha * 0.78)
		draw_string(font, Vector2(bx + RIFT_BTN_W / 2.0, btn_y + RIFT_BTN_H / 2.0 + 5 + (1.0 - _rift_btn_stay_t) * 15),
			"留在原地", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, stay_text_color)

	# 重置 transform
	draw_set_transform_matrix(Transform2D.IDENTITY)

# ===========================================================================
# 渲染: Toast 通知
# ===========================================================================
func _draw_toasts() -> void:
	if _toast_queue.is_empty():
		return

	var vp: Vector2 = get_viewport_rect().size
	var t = GameTheme
	var font: Font = ThemeDB.fallback_font

	for toast in _toast_queue:
		if toast["phase"] == "done":
			continue
		var alpha: float = toast["alpha"]
		if alpha < 0.01:
			continue

		var item_h: float = _toast_item_h(toast)
		var x: float = vp.x - TOAST_W - TOAST_MARGIN_R + toast["slide_x"]
		var y: float = toast["current_y"]

		# 更新碰撞区域
		toast["draw_x"] = x
		toast["draw_y"] = y
		toast["draw_w"] = float(TOAST_W)
		toast["draw_h"] = item_h

		# 背景
		var bg_color: Color = Color(t.panel_bg.r, t.panel_bg.g, t.panel_bg.b, alpha * 0.94)
		draw_rect(Rect2(x, y, TOAST_W, item_h), bg_color)

		# 边框
		var border_color: Color = Color(t.panel_border.r, t.panel_border.g, t.panel_border.b, alpha * 0.31)
		draw_rect(Rect2(x, y, TOAST_W, item_h), border_color, false, 1.0)

		# 顶部类型色条
		var type_color: Color = t.card_type_color(toast["card_type"])
		var bar_color: Color = Color(type_color.r, type_color.g, type_color.b, alpha * 0.78)
		draw_rect(Rect2(x + 3, y + 3, TOAST_W - 6, 4), bar_color)

		# 内容区域
		var content_x: float = x + 12.0
		var content_y: float = y + 14.0

		# 图标 + 标题
		var display_icon: String = toast["icon"]
		var icon_color: Color = Color(t.text_primary.r, t.text_primary.g, t.text_primary.b, alpha)
		draw_string(font, Vector2(content_x, content_y + 12), display_icon,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, icon_color)

		var title_color: Color = Color(type_color.r, type_color.g, type_color.b, alpha * 0.94)
		draw_string(font, Vector2(content_x + 28, content_y + 12),
			toast["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, title_color)

		content_y += 24.0

		# 描述
		var desc_text: String = toast["desc"]
		if desc_text.length() > 40:
			desc_text = desc_text.substr(0, 37) + "..."
		var desc_color: Color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, alpha * 0.78)
		draw_string(font, Vector2(content_x, content_y + 12),
			desc_text, HORIZONTAL_ALIGNMENT_LEFT, TOAST_W - 24, 11, desc_color)
		content_y += 28.0

		# 资源徽章 或 护盾提示
		if toast["shield_used"]:
			var shield_color: Color = Color(t.safe.r, t.safe.g, t.safe.b, alpha * 0.86)
			draw_string(font, Vector2(content_x, content_y + 12),
				"🧿 护身符抵挡了伤害!", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, shield_color)
			content_y += 20.0
		elif toast["effects"].size() > 0:
			var badge_x: float = content_x
			var effects: Dictionary = toast["effects"]
			for key in effects:
				var delta_val: int = effects[key]
				var res_icon: String = GameData.RESOURCE_ICONS.get(key, "?")
				var prefix: String = "+" if delta_val > 0 else ""
				var label: String = res_icon + prefix + str(delta_val)
				var bw: float = label.length() * 7.0 + 14.0
				var bh: float = 18.0

				var bg_c: Color = t.safe if delta_val > 0 else t.danger
				var badge_bg: Color = Color(bg_c.r, bg_c.g, bg_c.b, alpha * 0.14)
				draw_rect(Rect2(badge_x, content_y, bw, bh), badge_bg)
				var badge_border: Color = Color(bg_c.r, bg_c.g, bg_c.b, alpha * 0.31)
				draw_rect(Rect2(badge_x, content_y, bw, bh), badge_border, false, 0.8)

				var badge_text_color: Color = Color(bg_c.r, bg_c.g, bg_c.b, alpha * 0.86)
				draw_string(font, Vector2(badge_x + bw / 2.0, content_y + bh / 2.0 + 4),
					label, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, badge_text_color)
				badge_x += bw + 6.0
			content_y += 24.0

		# 进度条 (自动消失倒计时)
		if toast["phase"] == "idle":
			var progress: float = 1.0 - minf(toast["timer"] / TOAST_IDLE_TIME, 1.0)
			var bar_y: float = y + item_h - 6.0
			var bar_w: float = float(TOAST_W - 20)

			# 背景
			var bar_bg: Color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, alpha * 0.12)
			draw_rect(Rect2(x + 10, bar_y, bar_w, 2), bar_bg)

			# 前景
			var bar_fg: Color = Color(type_color.r, type_color.g, type_color.b, alpha * 0.47)
			draw_rect(Rect2(x + 10, bar_y, bar_w * progress, 2), bar_fg)
