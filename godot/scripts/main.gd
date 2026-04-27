## Main - 暗面都市 · 主入口 (模块化版)
## 场景树组织、信号桥接、输入路由、_process/_draw 主循环
## 游戏逻辑委托给 controllers/ 子模块:
##   board_visual.gd   — 卡牌节点管理、视觉更新、动画
##   game_flow.gd      — 发牌、日期推进、结算、胜负
##   card_interaction.gd — 翻牌/移动、相机模式、弹窗回调
##   dark_world_flow.gd — 暗面进出、换层、幽灵碰撞
extends Node2D

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const DRAG_THRESHOLD := 8.0
const PAN_LIMIT := Vector2(200, 200)
const BG_BRIGHT := Color(0.53, 0.76, 0.92)
const BG_DARK   := Color(0.15, 0.12, 0.18)
const TOKEN_CLICK_RADIUS := 32.0

# ---------------------------------------------------------------------------
# 核心数据 (控制器通过 m.xxx 访问)
# ---------------------------------------------------------------------------
var board: Board = null
var token: Token = null
var card_manager: CardManager = null
var board_items: BoardItems = null
var dark_world: DarkWorld = null

# ---------------------------------------------------------------------------
# 控制器
# ---------------------------------------------------------------------------
var board_visual = null       # Node2D — controllers/board_visual.gd
var game_flow = null          # RefCounted — controllers/game_flow.gd
var card_interaction = null   # RefCounted — controllers/card_interaction.gd
var dark_world_flow = null    # RefCounted — controllers/dark_world_flow.gd

# ---------------------------------------------------------------------------
# 对话系统
# ---------------------------------------------------------------------------
var _dialogue_system: DialogueSystem = null
var _bubble_dialogue: BubbleDialogue = null
var _dlg_enter_tweened := false
var _dlg_exit_tweened := false
var _bubble_show_tweened := false
var _bubble_hide_tweened := false

# ---------------------------------------------------------------------------
# UI 节点引用
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

# ---------------------------------------------------------------------------
# 场景节点
# ---------------------------------------------------------------------------
var _board_layer: Node2D = null
var _token_sprite: Sprite2D = null

# ---------------------------------------------------------------------------
# 运行时状态
# ---------------------------------------------------------------------------
var day_count := 1
var game_time := 0.0
var _bg_transition := 0.0
var _bg_transition_target := 0.0
var _camera_offset := Vector2.ZERO
var _drag_state := {
	"active": false,
	"is_dragging": false,
	"start_pos": Vector2.ZERO,
	"last_pos": Vector2.ZERO,
}

# =========================================================================
# 初始化
# =========================================================================

func _ready() -> void:
	# 核心数据
	board = Board.new()
	token = Token.new()
	card_manager = CardManager.new()
	board_items = BoardItems.new()
	dark_world = DarkWorld.new()
	token.load_textures()

	# 对话系统
	_dialogue_system = DialogueSystem.new()
	_bubble_dialogue = BubbleDialogue.new()

	# 场景树 → 控制器 → 信号
	_setup_scene_tree()
	_setup_controllers()
	_connect_signals()

	# 初始棋盘
	game_flow.generate_board()

	# 标题画面
	GameData.set_game_phase("title")
	GameData.set_demo_state("idle")
	_title_screen.show_title()

# ---------------------------------------------------------------------------
# 场景树构建
# ---------------------------------------------------------------------------

func _setup_scene_tree() -> void:
	# --- 2D 层 ---
	_board_layer = Node2D.new()
	_board_layer.name = "BoardLayer"
	add_child(_board_layer)

	_token_sprite = Sprite2D.new()
	_token_sprite.name = "TokenSprite"
	_token_sprite.z_index = 1
	_token_sprite.visible = false
	add_child(_token_sprite)

	# BoardVisual 叠层 (安全光晕、道具、裂隙标记)
	board_visual = load("res://scripts/controllers/board_visual.gd").new()
	board_visual.name = "BoardVisual"
	board_visual.z_index = 2
	add_child(board_visual)

	# --- UI CanvasLayer ---
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UILayer"
	ui_layer.layer = 10
	add_child(ui_layer)

	_vfx = VFXManager.new()
	_vfx.name = "VFX"
	_vfx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(_vfx)

	_resource_bar = load("res://scripts/ui/resource_bar.gd").new()
	_resource_bar.name = "ResourceBar"
	_resource_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_resource_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(_resource_bar)

	_hand_panel = load("res://scripts/ui/hand_panel.gd").new()
	_hand_panel.name = "HandPanel"
	_hand_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_hand_panel)

	_camera_button = load("res://scripts/ui/camera_button.gd").new()
	_camera_button.name = "CameraButton"
	_camera_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_camera_button)

	_event_popup = load("res://scripts/ui/event_popup.gd").new()
	_event_popup.name = "EventPopup"
	_event_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_event_popup)

	_shop_popup = load("res://scripts/ui/shop_popup.gd").new()
	_shop_popup.name = "ShopPopup"
	_shop_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_shop_popup)

	_game_over = load("res://scripts/visual/game_over.gd").new()
	_game_over.name = "GameOver"
	_game_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over.visible = false
	ui_layer.add_child(_game_over)

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

# ---------------------------------------------------------------------------
# 控制器初始化
# ---------------------------------------------------------------------------

func _setup_controllers() -> void:
	board_visual.setup(self)

	game_flow = load("res://scripts/controllers/game_flow.gd").new()
	game_flow.setup(self)

	card_interaction = load("res://scripts/controllers/card_interaction.gd").new()
	card_interaction.setup(self)

	dark_world_flow = load("res://scripts/controllers/dark_world_flow.gd").new()
	dark_world_flow.setup(self)

# ---------------------------------------------------------------------------
# 信号连接
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	# 标题 & 游戏结束
	_title_screen.start_requested.connect(_on_title_start)
	_game_over.restart_requested.connect(func(): game_flow.restart_game())

	# 日期过渡
	_date_transition.transition_completed.connect(
		func(): game_flow.on_date_transition_complete())

	# 事件弹窗
	_event_popup.popup_closed.connect(
		func(card: Card): card_interaction.on_popup_dismissed(card))
	_event_popup.photo_popup_closed.connect(
		func(card_type: String): card_interaction.on_photo_popup_dismissed(card_type))
	_event_popup.rift_confirmed.connect(
		func(): card_interaction.on_rift_confirmed())
	_event_popup.rift_cancelled.connect(
		func(): card_interaction.on_rift_cancelled())
	_event_popup.toast_dismissed.connect(func(_ct: String): pass)

	# 商店 (需区分普通/暗面)
	_shop_popup.shop_closed.connect(_on_shop_closed)

	# 手牌面板
	_hand_panel.end_day_pressed.connect(func(): game_flow.advance_day())
	_hand_panel.schedule_toggled.connect(
		func(idx: int): card_manager.toggle_defer(idx))
	_hand_panel.use_exorcism_pressed.connect(
		func(): card_interaction.handle_inventory_exorcism())

	# 相机按钮
	_camera_button.photograph_requested.connect(_on_photograph_request)
	_camera_button.exorcise_requested.connect(
		func(): card_interaction.handle_inventory_exorcism())

	# 资源栏 — 暗面退出
	_resource_bar.dark_exit_pressed.connect(
		func(): dark_world_flow.on_dark_exit_requested())

# =========================================================================
# 信号回调
# =========================================================================

func _on_title_start() -> void:
	GameData.set_game_phase("playing")
	game_flow.start_deal()

func _on_shop_closed() -> void:
	if GameData.demo_state == "dark_world":
		dark_world_flow.on_dark_shop_closed()
	else:
		card_interaction.on_shop_closed()

func _on_photograph_request() -> void:
	if GameData.demo_state != "ready":
		return
	var row := token.target_row
	var col := token.target_col
	var card: Card = board.get_card(row, col)
	if card and not card.is_flipped and not card.is_flipping:
		card_interaction.do_photograph(card, row, col)

# =========================================================================
# 输入处理
# =========================================================================

func _unhandled_input(event: InputEvent) -> void:
	# 日期过渡中阻断所有输入
	if _date_transition.visible and _date_transition.is_active():
		return

	# 对话系统优先消费
	if _dialogue_system and _dialogue_system.is_active():
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_dialogue_system.handle_click()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				_dialogue_system.handle_key()
				get_viewport().set_input_as_handled()
				return

	# 鼠标按钮
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	# 鼠标移动 (拖拽平移)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	# 键盘
	elif event is InputEventKey and event.pressed:
		_handle_key(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
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

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _drag_state["active"]:
		return
	var delta: Vector2 = event.position - _drag_state["start_pos"]
	if not _drag_state["is_dragging"]:
		if delta.length() > DRAG_THRESHOLD:
			_drag_state["is_dragging"] = true
	if _drag_state["is_dragging"]:
		var move_delta: Vector2 = event.position - _drag_state["last_pos"]
		_drag_state["last_pos"] = event.position
		_camera_offset -= move_delta
		_camera_offset = _camera_offset.clamp(-PAN_LIMIT, PAN_LIMIT)

func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_F4:
			card_interaction.handle_inventory_exorcism()

# ---------------------------------------------------------------------------
# 点击路由
# ---------------------------------------------------------------------------

func _process_click(pos: Vector2) -> void:
	if GameData.game_phase != "playing":
		return

	# 气泡对话 — 点击 Token
	if _bubble_dialogue and _token_sprite.visible:
		if pos.distance_to(_token_sprite.position) < TOKEN_CLICK_RADIUS:
			_bubble_dialogue.click_trigger()
			return

	# 棋盘点击检测
	var grid_pos := board_visual.hit_test(pos)
	if grid_pos == Vector2i.ZERO:
		return

	# 暗面世界
	if GameData.demo_state == "dark_world":
		dark_world_flow.handle_dark_card_click(grid_pos.x, grid_pos.y)
		return

	# 普通模式
	card_interaction.handle_card_click(grid_pos.x, grid_pos.y)

# =========================================================================
# 主循环
# =========================================================================

func _process(dt: float) -> void:
	game_time += dt

	# 背景氛围过渡
	_bg_transition_target = minf(float(GameData.cards_revealed) / 8.0, 1.0)
	_bg_transition = move_toward(_bg_transition, _bg_transition_target, 2.0 * dt)

	# Token
	token.update(dt)
	board_visual.update_token_visual()

	# 对话系统 tween 管理
	_update_dialogue_tweens(dt)

	# 气泡对话
	_update_bubble_tweens(dt)

	board_visual.queue_redraw()
	queue_redraw()

func _draw() -> void:
	var bg_color := BG_BRIGHT.lerp(BG_DARK, _bg_transition)
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), bg_color)

# ---------------------------------------------------------------------------
# 对话系统 tween 管理
# ---------------------------------------------------------------------------

func _update_dialogue_tweens(dt: float) -> void:
	if _dialogue_system == null:
		return
	_dialogue_system.update(dt)

	match _dialogue_system.state:
		"entering":
			if not _dlg_enter_tweened:
				_dlg_enter_tweened = true
				_dlg_exit_tweened = false
				_tween_dialogue_enter()
		"exiting":
			if not _dlg_exit_tweened:
				_dlg_exit_tweened = true
				_tween_dialogue_exit()
		"idle":
			_dlg_enter_tweened = false
			_dlg_exit_tweened = false

func _tween_dialogue_enter() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialogue_system, "overlay_alpha", 1.0, 0.3)
	tw.tween_property(_dialogue_system, "box_offset_y", 0.0, 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_dialogue_system, "box_alpha", 1.0, 0.3)
	tw.tween_property(_dialogue_system, "portrait_alpha", 1.0, 0.4).set_delay(0.1)
	tw.tween_property(_dialogue_system, "portrait_offset_y", 0.0, 0.4) \
		.set_delay(0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_dialogue_system, "portrait_scale", 1.0, 0.3).set_delay(0.1)
	# 完成回调
	var tw_cb := create_tween()
	tw_cb.tween_callback(_dialogue_system.on_enter_complete).set_delay(0.55)

func _tween_dialogue_exit() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialogue_system, "overlay_alpha", 0.0, 0.25)
	tw.tween_property(_dialogue_system, "box_offset_y", 60.0, 0.3) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_dialogue_system, "box_alpha", 0.0, 0.25)
	tw.tween_property(_dialogue_system, "portrait_alpha", 0.0, 0.25)
	tw.tween_property(_dialogue_system, "portrait_offset_y", 20.0, 0.25)
	# 完成回调
	var tw_cb := create_tween()
	tw_cb.tween_callback(_dialogue_system.on_exit_complete).set_delay(0.35)

# ---------------------------------------------------------------------------
# 气泡对话 tween 管理
# ---------------------------------------------------------------------------

func _update_bubble_tweens(dt: float) -> void:
	if _bubble_dialogue == null:
		return

	var is_idle := GameData.demo_state == "ready"
	var can_trigger := GameData.game_phase == "playing" \
		and not _dialogue_system.is_active()
	_bubble_dialogue.update(dt, is_idle, can_trigger)

	# 更新上下文: 当前位置的卡牌信息
	if is_idle and board:
		var card: Card = board.get_card(token.target_row, token.target_col)
		if card and card.is_flipped:
			_bubble_dialogue.set_context(card.location, card.type)

	match _bubble_dialogue.state:
		"showing":
			if not _bubble_show_tweened:
				_bubble_show_tweened = true
				_bubble_hide_tweened = false
				var tw := create_tween().set_parallel(true)
				tw.tween_property(_bubble_dialogue, "bubble_alpha", 1.0, 0.2)
				tw.tween_property(_bubble_dialogue, "bubble_scale", 1.0, 0.25) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
				tw.tween_property(_bubble_dialogue, "offset_y", 0.0, 0.2)
				var tw_cb := create_tween()
				tw_cb.tween_callback(_bubble_dialogue.on_show_complete).set_delay(0.3)
		"hiding":
			if not _bubble_hide_tweened:
				_bubble_hide_tweened = true
				var tw := create_tween().set_parallel(true)
				tw.tween_property(_bubble_dialogue, "bubble_alpha", 0.0, 0.15)
				tw.tween_property(_bubble_dialogue, "bubble_scale", 0.5, 0.15)
				var tw_cb := create_tween()
				tw_cb.tween_callback(_bubble_dialogue.on_hide_complete).set_delay(0.2)
		"hidden":
			_bubble_show_tweened = false
			_bubble_hide_tweened = false
