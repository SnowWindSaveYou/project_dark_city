## Main - 暗面都市 · 主入口
## 对应原版 main.lua
## 状态机、2D 场景组织、交互处理、弹窗回调
extends Node2D

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const MAX_DAYS := 3
const DRAG_THRESHOLD := 8.0  # 像素，超过此距离判定为拖拽

## 卡牌像素尺寸
const CARD_PX_W := 90.0
const CARD_PX_H := 126.0
const CARD_PX_GAP := 8.0

# ---------------------------------------------------------------------------
# 游戏状态
# ---------------------------------------------------------------------------
enum GamePhase { TITLE, PLAYING, GAMEOVER }
enum DemoState {
	IDLE, DEALING, READY, FLIPPING, POPUP, MOVING,
	PHOTOGRAPHING, EXORCISING
}

var game_phase := GamePhase.TITLE
var demo_state := DemoState.IDLE
var day_count := 1
var game_time := 0.0

## 统计
var stats := {
	"cards_revealed": 0,
	"monsters_slain": 0,
	"photos_used": 0,
}

# ---------------------------------------------------------------------------
# 核心数据
# ---------------------------------------------------------------------------
var board: Board = null
var token: Token = null
var card_manager: CardManager = null

# ---------------------------------------------------------------------------
# UI / 视觉节点引用 (在 _ready 中初始化)
# ---------------------------------------------------------------------------
var _vfx: VFXManager = null
var _resource_bar: Control = null
var _event_popup: Control = null
var _shop_popup: Control = null
var _hand_panel: Control = null
var _camera_button: Control = null
var _title_screen: Control = null
var _game_over: Control = null
var _date_transition: Control = null

## 棋盘视觉层 (卡牌精灵容器)
var _board_layer: Node2D = null
## Token 精灵
var _token_sprite: Sprite2D = null

# ---------------------------------------------------------------------------
# 交互状态
# ---------------------------------------------------------------------------
var _drag_state := {
	"active": false,
	"is_dragging": false,
	"start_pos": Vector2.ZERO,
	"last_pos": Vector2.ZERO,
}

## 背景氛围
var _bg_transition := 0.0
var _bg_transition_target := 0.0

## 相机平移 (2D 模式下用 camera offset)
var _camera_offset := Vector2.ZERO
const PAN_LIMIT := Vector2(200, 200)

# ---------------------------------------------------------------------------
# 背景色定义
# ---------------------------------------------------------------------------
const BG_BRIGHT := Color(0.53, 0.76, 0.92)
const BG_DARK   := Color(0.15, 0.12, 0.18)

# ---------------------------------------------------------------------------
# 发牌动画
# ---------------------------------------------------------------------------
## 牌堆起始位置 (屏幕外右上角)
var _deck_spawn_pos := Vector2.ZERO

# =========================================================================
# 初始化
# =========================================================================

func _ready() -> void:
	board = Board.new()
	token = Token.new()
	card_manager = CardManager.new()
	token.load_textures()

	_setup_scene_tree()
	_generate_board()

	game_phase = GamePhase.TITLE
	demo_state = DemoState.IDLE
	_title_screen.show_title()

func _setup_scene_tree() -> void:
	# 棋盘层
	_board_layer = Node2D.new()
	_board_layer.name = "BoardLayer"
	add_child(_board_layer)

	# Token 精灵
	_token_sprite = Sprite2D.new()
	_token_sprite.name = "TokenSprite"
	_token_sprite.visible = false
	add_child(_token_sprite)

	# UI CanvasLayer
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UILayer"
	ui_layer.layer = 10
	add_child(ui_layer)

	# VFX
	_vfx = VFXManager.new()
	_vfx.name = "VFX"
	_vfx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(_vfx)

	# Resource Bar
	_resource_bar = load("res://scripts/ui/resource_bar.gd").new()
	_resource_bar.name = "ResourceBar"
	_resource_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_resource_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(_resource_bar)

	# Hand Panel
	_hand_panel = load("res://scripts/ui/hand_panel.gd").new()
	_hand_panel.name = "HandPanel"
	_hand_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_hand_panel)

	# Camera Button
	_camera_button = load("res://scripts/ui/camera_button.gd").new()
	_camera_button.name = "CameraButton"
	_camera_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_camera_button)

	# Event Popup
	_event_popup = load("res://scripts/ui/event_popup.gd").new()
	_event_popup.name = "EventPopup"
	_event_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_event_popup)

	# Shop Popup
	_shop_popup = load("res://scripts/ui/shop_popup.gd").new()
	_shop_popup.name = "ShopPopup"
	_shop_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_shop_popup)

	# Game Over
	_game_over = load("res://scripts/visual/game_over.gd").new()
	_game_over.name = "GameOver"
	_game_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over.visible = false
	ui_layer.add_child(_game_over)

	# Date Transition
	_date_transition = load("res://scripts/visual/date_transition.gd").new()
	_date_transition.name = "DateTransition"
	_date_transition.set_anchors_preset(Control.PRESET_FULL_RECT)
	_date_transition.visible = false
	ui_layer.add_child(_date_transition)

	# Title Screen (最顶层)
	_title_screen = load("res://scripts/visual/title_screen.gd").new()
	_title_screen.name = "TitleScreen"
	_title_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_title_screen)

	# 连接信号
	_title_screen.start_requested.connect(_on_title_start)
	_game_over.restart_requested.connect(_on_game_restart)
	_date_transition.transition_completed.connect(_on_date_transition_complete)
	_event_popup.popup_closed.connect(_on_popup_dismissed)
	_event_popup.photo_popup_closed.connect(_on_photo_popup_dismissed)
	_shop_popup.shop_closed.connect(_on_shop_closed)
	_hand_panel.end_day_requested.connect(_on_end_day)
	_camera_button.photograph_requested.connect(_on_photograph_request)
	_camera_button.exorcise_requested.connect(_on_exorcise_request)

# =========================================================================
# 棋盘生成
# =========================================================================

func _generate_board() -> void:
	var req_locs := card_manager.pre_select_locations()
	board.required_locations = req_locs
	board.generate_cards()
	_rebuild_board_visuals()

func _rebuild_board_visuals() -> void:
	for child in _board_layer.get_children():
		child.queue_free()

	var screen_size := get_viewport_rect().size
	var board_center := screen_size * 0.5
	_deck_spawn_pos = Vector2(screen_size.x + 60, -60)  # 屏幕外右上

	var total_w: float = Board.COLS * (CARD_PX_W + CARD_PX_GAP) - CARD_PX_GAP
	var total_h: float = Board.ROWS * (CARD_PX_H + CARD_PX_GAP) - CARD_PX_GAP
	var start_x: float = board_center.x - total_w * 0.5
	var start_y: float = board_center.y - total_h * 0.5 - 30

	for r in range(Board.ROWS):
		for c in range(Board.COLS):
			var card: Card = board.get_card(r + 1, c + 1)
			if card == null:
				continue

			var card_node := ColorRect.new()
			card_node.name = "Card_%d_%d" % [r + 1, c + 1]
			card_node.size = Vector2(CARD_PX_W, CARD_PX_H)

			# 最终目标位置
			var target_pos := Vector2(
				start_x + c * (CARD_PX_W + CARD_PX_GAP),
				start_y + r * (CARD_PX_H + CARD_PX_GAP)
			)
			card_node.position = target_pos  # 先放目标位置，发牌时会覆盖
			card_node.color = Theme.card_back
			card_node.set_meta("row", r + 1)
			card_node.set_meta("col", c + 1)
			card_node.set_meta("target_pos", target_pos)
			_board_layer.add_child(card_node)

# =========================================================================
# 螺旋发牌动画
# =========================================================================

func _start_deal() -> void:
	demo_state = DemoState.DEALING
	_vfx.action_banner("第 %d 天" % day_count, Color.WHITE, 1.2)

	# 获取螺旋顺序
	var order := board.get_spiral_order()
	var total_cards := order.size()

	# 渐进加速延迟: 前几张 0.09s → 后几张 0.03s
	var acc_delay := 0.3  # 初始延迟让横幅先展示
	var last_arrival := acc_delay

	for i in range(total_cards):
		var pos: Vector2i = order[i]
		var card_name := "Card_%d_%d" % [pos.x, pos.y]
		var card_node: ColorRect = _board_layer.get_node_or_null(card_name)
		if card_node == null:
			continue

		var target_pos: Vector2 = card_node.get_meta("target_pos")

		# 起始: 牌堆位置, 透明, 缩小
		card_node.position = _deck_spawn_pos
		card_node.modulate.a = 0.0
		card_node.scale = Vector2(0.4, 0.4)

		# 飞行时长
		var fly_dur := 0.35

		# 淡入 (0.15s)
		var tw := create_tween()
		tw.tween_property(card_node, "modulate:a", 1.0, 0.15).set_delay(acc_delay)

		# 飞行到目标位置
		var tw2 := create_tween()
		tw2.tween_property(card_node, "position", target_pos, fly_dur) \
			.set_delay(acc_delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

		# 缩放恢复
		var tw3 := create_tween()
		tw3.tween_property(card_node, "scale", Vector2.ONE, fly_dur) \
			.set_delay(acc_delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

		# 弹跳效果 (到达后)
		var bounce_delay := acc_delay + fly_dur * 0.6
		var tw4 := create_tween()
		tw4.tween_property(card_node, "scale", Vector2(1.08, 0.92), 0.1) \
			.set_delay(bounce_delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw4.tween_property(card_node, "scale", Vector2.ONE, 0.1) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

		last_arrival = acc_delay + fly_dur

		# 间隔随进度递减: lerp(0.09, 0.03, progress)
		var progress: float = float(i) / float(total_cards)
		var interval: float = 0.09 - 0.06 * progress
		acc_delay += interval

	# 发牌结束后进入 READY
	var finish_delay := last_arrival + 0.4
	var tw_finish := create_tween()
	tw_finish.tween_callback(_on_deal_complete).set_delay(finish_delay)

func _on_deal_complete() -> void:
	demo_state = DemoState.READY

	# Token 出现在 "家"
	var home_row := board.home_row
	var home_col := board.home_col
	token.target_row = home_row
	token.target_col = home_col
	token.visible = true
	token.alpha = 1.0
	_update_token_visual()

	# 家的卡牌默认翻开
	var home_card := board.get_card(home_row, home_col)
	if home_card:
		board.flip_card(home_row, home_col)
		_update_card_visual(home_row, home_col)

	# 生成日程
	card_manager.generate_daily(day_count)

# =========================================================================
# 日期流程
# =========================================================================

func advance_day() -> void:
	if game_phase != GamePhase.PLAYING:
		return
	if demo_state != DemoState.READY:
		return

	# 结算当天
	card_manager.settle_day()

	# 恢复资源
	GameData.modify_resource("san", 1)
	GameData.modify_resource("order", 1)
	var current_film := GameData.get_resource("film")
	if current_film < 3:
		GameData.modify_resource("film", 3 - current_film)
	GameData.modify_resource("money", 10)

	demo_state = DemoState.DEALING
	token.visible = false

	day_count += 1

	if day_count > MAX_DAYS:
		_trigger_victory()
		return

	_date_transition.play(day_count)

# =========================================================================
# 胜负判定
# =========================================================================

func _check_defeat() -> void:
	if game_phase != GamePhase.PLAYING:
		return
	if GameData.check_defeat():
		game_phase = GamePhase.GAMEOVER
		demo_state = DemoState.IDLE
		token.set_emotion("dead")
		_vfx.screen_shake(8.0, 0.4, 20.0)
		_vfx.screen_flash(Color(0.7, 0.12, 0.12, 0.78), 0.5)
		_game_over.show_result(false, {
			"days_survived": day_count,
			"cards_revealed": stats["cards_revealed"],
			"monsters_slain": stats["monsters_slain"],
			"photos_used": stats["photos_used"],
		})

func _trigger_victory() -> void:
	game_phase = GamePhase.GAMEOVER
	demo_state = DemoState.IDLE
	token.set_emotion("happy")
	_vfx.screen_flash(Color(1.0, 0.84, 0.39, 0.7), 0.5)
	_game_over.show_result(true, {
		"days_survived": MAX_DAYS,
		"cards_revealed": stats["cards_revealed"],
		"monsters_slain": stats["monsters_slain"],
		"photos_used": stats["photos_used"],
	})

# =========================================================================
# 拍照逻辑 (Photograph)
# =========================================================================

## 执行拍照: 消耗胶卷 → 闪光 → 翻牌 → 弹窗 → 标记侦察 → 翻回
func _do_photograph(card: Card, row: int, col: int) -> void:
	GameData.modify_resource("film", -1)
	stats["photos_used"] += 1

	demo_state = DemoState.PHOTOGRAPHING
	_camera_button.exit_camera_mode()
	token.set_emotion("determined")

	# 快门闪光
	_vfx.screen_flash(Color.WHITE, 0.5)
	token.hop(0.05)

	# 延迟后翻牌
	await get_tree().create_timer(0.25).timeout

	if not card.is_flipped and not card.is_flipping:
		# 翻开
		demo_state = DemoState.FLIPPING
		card.is_flipping = true
		board.flip_card(row, col)
		_update_card_visual(row, col)

		# 翻牌动画 (缩放模拟)
		var card_node := _get_card_node(row, col)
		if card_node:
			var tw := create_tween()
			tw.tween_property(card_node, "scale:x", 0.0, 0.12) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_callback(func(): _update_card_visual(row, col))
			tw.tween_property(card_node, "scale:x", 1.0, 0.12) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			await tw.finished

		card.is_flipping = false

		# 粒子爆发
		var center := _get_card_center(row, col)
		var tc := Theme.card_type_color(card.type)
		_vfx.spawn_burst(center, 8, tc)
		_vfx.screen_shake(2.0, 0.1)

		# 弹窗
		demo_state = DemoState.POPUP
		await get_tree().create_timer(0.4).timeout
		_event_popup.show_photo(card)
	else:
		token.set_emotion("default")
		demo_state = DemoState.READY

## 拍照弹窗关闭回调
func _on_photo_popup_dismissed(_card_type: String) -> void:
	stats["cards_revealed"] += 1

	# 当前正在查看的卡牌: 标记侦察 + 翻回
	var row := token.target_row
	var col := token.target_col
	# 查找最近拍照的卡牌 (可能是非当前位置, 但相机模式下通常就是点击的那张)
	# 简化: 遍历所有刚翻开且未侦察的
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card := board.get_card(r, c)
			if card and card.is_flipped and not card.scouted:
				# 这是刚拍照翻开的卡
				card.scouted = true
				board.flip_back(r, c)
				_update_card_visual(r, c)
				# 翻回动画
				var card_node := _get_card_node(r, c)
				if card_node:
					var tw := create_tween()
					tw.tween_property(card_node, "scale:x", 0.0, 0.1)
					tw.tween_callback(func(): _update_card_visual(r, c))
					tw.tween_property(card_node, "scale:x", 1.0, 0.1)

	token.set_emotion("happy")
	demo_state = DemoState.READY

# =========================================================================
# 驱魔逻辑 (Exorcise)
# =========================================================================

## 执行驱魔: 消耗胶卷或道具 → 闪光震动 → 卡牌变形为 "photo" → 完成
func _do_exorcise(card: Card, row: int, col: int, free_exorcise: bool = false) -> void:
	# 消耗资源
	if free_exorcise:
		_vfx.action_banner("🪔 驱魔香驱除!", Theme.safe, 0.8)
	elif GameData.remove_item("exorcism"):
		_vfx.action_banner("🪔 驱魔香免费驱除!", Theme.safe, 0.8)
	else:
		GameData.modify_resource("film", -1)

	stats["photos_used"] += 1
	stats["monsters_slain"] += 1

	demo_state = DemoState.EXORCISING
	_camera_button.exit_camera_mode()
	token.set_emotion("angry")

	# 闪光 + 震动
	var pc := Theme.card_type_color("plot")
	_vfx.screen_flash(pc, 0.5)
	_vfx.screen_shake(4.0, 0.2)
	token.hop(0.06)

	# 延迟后变形
	await get_tree().create_timer(0.3).timeout

	# 卡牌类型变为 photo
	card.type = "photo"
	_update_card_visual(row, col)

	# 变形动画 (缩放 + 弹出)
	var card_node := _get_card_node(row, col)
	if card_node:
		var tw := create_tween()
		tw.tween_property(card_node, "scale", Vector2(0.6, 0.6), 0.15) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func(): _update_card_visual(row, col))
		tw.tween_property(card_node, "scale", Vector2(1.15, 1.15), 0.2) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(card_node, "scale", Vector2.ONE, 0.1)
		await tw.finished

	# 粒子爆发 + 横幅
	var center := _get_card_center(row, col)
	_vfx.spawn_burst(center, 16, pc)
	_vfx.action_banner("驱除成功!", pc, 1.0)

	token.set_emotion("happy")
	demo_state = DemoState.READY

## F4 快捷键 - 使用道具栏驱魔香
func _handle_inventory_exorcism() -> void:
	if demo_state != DemoState.READY:
		return

	if not GameData.remove_item("exorcism"):
		_vfx.action_banner("没有驱魔香!", Color(0.86, 0.31, 0.31), 0.7)
		return

	var row := token.target_row
	var col := token.target_col
	var card := board.get_card(row, col)

	if card == null:
		GameData.add_item("exorcism")  # 退还
		_vfx.action_banner("无效位置", Color(0.7, 0.7, 0.7), 0.6)
		return

	if card.is_flipped and card.type == "monster":
		_do_exorcise(card, row, col, true)
	else:
		GameData.add_item("exorcism")  # 退还
		if not card.is_flipped:
			_vfx.action_banner("需要先翻开卡牌!", Color(0.86, 0.63, 0.31), 0.7)
		else:
			_vfx.action_banner("当前格子没有怪物", Color(0.7, 0.7, 0.7), 0.6)

# =========================================================================
# 相机模式点击
# =========================================================================

func _handle_camera_mode_click(card: Card, row: int, col: int) -> void:
	var film := GameData.get_resource("film")

	# 已翻开的怪物 → 驱魔
	if card.is_flipped and card.type == "monster" and not card.is_flipping:
		if film <= 0:
			_vfx.action_banner("胶卷不足!", Color(0.86, 0.31, 0.31), 0.8)
			return
		_do_exorcise(card, row, col)
		return

	# 已侦察的卡牌 → 再次查看
	if card.scouted and card.is_flipped and not card.is_flipping:
		demo_state = DemoState.POPUP
		_event_popup.show_photo(card)
		return

	# 胶卷不足
	if film <= 0:
		_vfx.action_banner("胶卷不足!", Color(0.86, 0.31, 0.31), 0.8)
		return

	# 未翻开的卡牌 → 拍照
	if not card.is_flipped and not card.is_flipping:
		_do_photograph(card, row, col)
	else:
		_vfx.action_banner("无法拍摄", Color(0.7, 0.7, 0.7), 0.6)

# =========================================================================
# 信号回调
# =========================================================================

func _on_title_start() -> void:
	game_phase = GamePhase.PLAYING
	_start_deal()

func _on_game_restart() -> void:
	day_count = 1
	game_phase = GamePhase.PLAYING
	stats = { "cards_revealed": 0, "monsters_slain": 0, "photos_used": 0 }
	_bg_transition = 0.0
	_bg_transition_target = 0.0
	_camera_offset = Vector2.ZERO

	GameData.reset()
	card_manager = CardManager.new()
	board = Board.new()
	_generate_board()
	token = Token.new()
	token.load_textures()
	_start_deal()

func _on_date_transition_complete() -> void:
	board = Board.new()
	_generate_board()
	_start_deal()

func _on_popup_dismissed(card: Card) -> void:
	if card:
		# 应用效果
		var effects := card.get_effects()
		for key in effects:
			GameData.modify_resource(key, effects[key])

	stats["cards_revealed"] += 1

	# 根据类型切换表情
	if card:
		var positive := ["clue", "safe", "home", "landmark"]
		if card.type in positive:
			token.set_emotion("happy")
		else:
			token.set_emotion("default")

	demo_state = DemoState.READY
	_check_defeat()

func _on_shop_closed() -> void:
	demo_state = DemoState.READY

func _on_end_day() -> void:
	advance_day()

func _on_photograph_request() -> void:
	# 从 CameraButton 信号触发 — 对当前 Token 所在格拍照
	if demo_state != DemoState.READY:
		return
	var row := token.target_row
	var col := token.target_col
	var card := board.get_card(row, col)
	if card and not card.is_flipped and not card.is_flipping:
		_do_photograph(card, row, col)

func _on_exorcise_request() -> void:
	_handle_inventory_exorcism()

# =========================================================================
# 普通模式卡牌交互
# =========================================================================

func _handle_card_click(row: int, col: int) -> void:
	if game_phase != GamePhase.PLAYING:
		return
	if demo_state != DemoState.READY:
		return

	var card := board.get_card(row, col)
	if card == null:
		return

	# 相机模式下走不同分支
	if _camera_button.is_camera_mode():
		_handle_camera_mode_click(card, row, col)
		return

	var is_current := (token.target_row == row and token.target_col == col)

	if is_current:
		# 翻当前格子的牌
		if not card.is_flipped:
			demo_state = DemoState.FLIPPING
			board.flip_card(row, col)
			_update_card_visual(row, col)
			_on_card_flipped(card, row, col)
		return

	# 检查相邻
	if not board.is_adjacent(token.target_row, token.target_col, row, col):
		_vfx.action_banner("只能移动到相邻格子", Color(0.7, 0.7, 0.7), 0.6)
		return

	# 移动 Token
	demo_state = DemoState.MOVING
	token.target_row = row
	token.target_col = col
	token.set_emotion("running")

	var tween := create_tween()
	var target_pos := _get_card_center(row, col)
	tween.tween_property(_token_sprite, "position", target_pos, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func():
		var arrived_card := board.get_card(row, col)
		if arrived_card and not arrived_card.is_flipped:
			demo_state = DemoState.FLIPPING
			board.flip_card(row, col)
			_update_card_visual(row, col)
			_on_card_flipped(arrived_card, row, col)
		else:
			token.set_emotion("default")
			demo_state = DemoState.READY
	)

func _on_card_flipped(card: Card, row: int, col: int) -> void:
	var card_type: String = card.type

	# 地标光环净化
	if board.is_in_landmark_aura(row, col):
		if card_type == "monster" or card_type == "trap":
			card_type = "safe"
			card.type = "safe"
			_update_card_visual(row, col)

	# 检查日程完成
	if card.location != "":
		card_manager.complete_schedule_at(card.location)

	# 表情映射
	var emotion_map := {
		"monster": "scared", "trap": "nervous", "shop": "confused",
		"clue": "surprised", "home": "relieved", "landmark": "relieved",
		"safe": "relieved",
	}
	token.set_emotion(emotion_map.get(card_type, "default"))

	# 安全区域直接通过
	if card_type == "home" or card_type == "landmark":
		_vfx.action_banner("安全", Theme.safe, 0.8)
		demo_state = DemoState.READY
		return

	_vfx.screen_shake(3.0, 0.15)

	# 弹窗延迟
	demo_state = DemoState.POPUP
	await get_tree().create_timer(0.4).timeout

	if card_type == "shop":
		_shop_popup.open_shop()
	else:
		_event_popup.show_event(card)

# =========================================================================
# 视觉更新辅助
# =========================================================================

func _get_card_node(row: int, col: int) -> ColorRect:
	var card_name := "Card_%d_%d" % [row, col]
	return _board_layer.get_node_or_null(card_name) as ColorRect

func _update_card_visual(row: int, col: int) -> void:
	var card_node := _get_card_node(row, col)
	if not card_node:
		return

	var card := board.get_card(row, col)
	if card == null:
		return

	if card.is_flipped:
		var type_info: Dictionary = Theme.card_type_info(card.type)
		card_node.color = type_info.get("color", Theme.card_face)
		# 侦察标记 (右上角小点)
		if card.scouted:
			card_node.color = card_node.color.lightened(0.15)
	else:
		card_node.color = Theme.card_back

func _update_token_visual() -> void:
	if not token.visible:
		_token_sprite.visible = false
		return

	_token_sprite.visible = true
	var tex := token.get_current_texture()
	if tex:
		_token_sprite.texture = tex

	var base_pos := _get_card_center(token.target_row, token.target_col)

	# 呼吸动画
	var breathe := token.get_breathe_offset(game_time)
	base_pos.y += breathe["y"]

	# 弹跳偏移
	base_pos.y += token.bounce_y

	_token_sprite.position = base_pos
	_token_sprite.modulate.a = token.alpha

	# squash 变形
	_token_sprite.scale = Vector2(token.squash_x, token.squash_y)

func _get_card_center(row: int, col: int) -> Vector2:
	var card_node := _get_card_node(row, col)
	if card_node:
		return card_node.position + card_node.size * 0.5
	return get_viewport_rect().size * 0.5

# =========================================================================
# 输入处理
# =========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if _date_transition.visible and _date_transition.is_active():
		return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_drag_state["active"] = true
			_drag_state["is_dragging"] = false
			_drag_state["start_pos"] = event.position
			_drag_state["last_pos"] = event.position
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _drag_state["active"] and not _drag_state["is_dragging"]:
				_process_click(event.position)
			_drag_state["active"] = false
			_drag_state["is_dragging"] = false

	elif event is InputEventMouseMotion:
		if _drag_state["active"]:
			var delta: Vector2 = event.position - _drag_state["start_pos"]
			if not _drag_state["is_dragging"]:
				if delta.length() > DRAG_THRESHOLD:
					_drag_state["is_dragging"] = true
			if _drag_state["is_dragging"]:
				var move_delta: Vector2 = event.position - _drag_state["last_pos"]
				_drag_state["last_pos"] = event.position
				_camera_offset -= move_delta
				_camera_offset = _camera_offset.clamp(-PAN_LIMIT, PAN_LIMIT)

	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_F4:
				_handle_inventory_exorcism()

func _process_click(pos: Vector2) -> void:
	for child in _board_layer.get_children():
		if child is ColorRect:
			var rect := Rect2(child.position, child.size)
			if rect.has_point(pos):
				var row: int = child.get_meta("row", 0)
				var col: int = child.get_meta("col", 0)
				if row > 0 and col > 0:
					_handle_card_click(row, col)
					return

# =========================================================================
# 主循环
# =========================================================================

func _process(dt: float) -> void:
	game_time += dt

	# 背景氛围过渡
	var total_for_full := 8.0
	_bg_transition_target = minf(float(stats["cards_revealed"]) / total_for_full, 1.0)
	var bg_speed := 2.0
	if _bg_transition < _bg_transition_target:
		_bg_transition = minf(_bg_transition + bg_speed * dt, _bg_transition_target)
	elif _bg_transition > _bg_transition_target:
		_bg_transition = maxf(_bg_transition - bg_speed * dt, _bg_transition_target)

	# Token 更新
	token.update(dt)
	_update_token_visual()

	queue_redraw()

func _draw() -> void:
	var bg_color := BG_BRIGHT.lerp(BG_DARK, _bg_transition)
	var screen_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen_size), bg_color)
