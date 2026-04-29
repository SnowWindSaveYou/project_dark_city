## Main - 暗面都市 · 主入口 (模块化版)
## 场景树组织、信号桥接、输入路由、_process 主循环
##
## 架构说明:
##   - core/    核心数据模型 (Board, Card, Token, DarkWorld)
##   - controllers/ 业务控制器 (game_flow, card_interaction, board_visual, dark_world_flow)
##   - ui/      UI组件 (DialogueSystem, EventPopup, ShopPopup 等)
##   - lib/     工具库 (Enums, GameConfig, WeatherSystem, VFXManager)
##
## 初始化顺序:
##   1. 核心数据 (Board, Token, CardManager, DarkWorld)
##   2. UI系统 (DialogueSystem, VFXManager)
##   3. 控制器 (game_flow, card_interaction, board_visual, dark_world_flow)
##   4. 信号连接
extends Node3D

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const DRAG_THRESHOLD: float = 8.0
const PAN_LIMIT: Vector2 = Vector2(2.5, 2.5)  # 世界坐标米
const BG_BRIGHT: Color = Color(0.53, 0.76, 0.92)
const BG_DARK: Color = Color(0.15, 0.12, 0.18)
const TOKEN_CLICK_RADIUS: float = 32.0

# 氛围参数 (明亮 → 暗黑, 由 _bg_transition 0→1 插值)
const ATMO_BRIGHT: Dictionary = {
	"light_energy": 2.8,
	"ambient_color": Color(0.4, 0.45, 0.5),
	"ambient_energy": 0.6,
	"fog_enabled": false,
	"fog_density": 0.0,
	"fog_color": Color(0.5, 0.6, 0.7),
	"table_color": Color(0.25, 0.22, 0.20),
}
const ATMO_DARK: Dictionary = {
	"light_energy": 0.6,
	"ambient_color": Color(0.15, 0.1, 0.25),
	"ambient_energy": 0.25,
	"fog_enabled": true,
	"fog_density": 0.04,
	"fog_color": Color(0.08, 0.06, 0.12),
	"table_color": Color(0.12, 0.10, 0.14),
}

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
var board_visual: Node3D = null       # Node3D — controllers/board_visual.gd
var game_flow: RefCounted = null          # RefCounted — controllers/game_flow.gd
var card_interaction: RefCounted = null   # RefCounted — controllers/card_interaction.gd
var dark_world_flow: RefCounted = null    # RefCounted — controllers/dark_world_flow.gd
var consumable_controller: RefCounted = null  # RefCounted — controllers/consumable_controller.gd

# ---------------------------------------------------------------------------
# 对话系统
# ---------------------------------------------------------------------------
var _dialogue_system: DialogueSystem = null
var _bubble_dialogue: BubbleDialogue = null
var _dlg_enter_tweened: bool = false
var _dlg_exit_tweened: bool = false
var _bubble_show_tweened: bool = false
var _bubble_hide_tweened: bool = false

# ---------------------------------------------------------------------------
# UI 节点引用
# ---------------------------------------------------------------------------
var _vfx: VFXManager = null
var _ui_layer: CanvasLayer = null
var _resource_bar: Control = null
var _event_popup: Control = null
var _shop_popup: Control = null
var _hand_panel: Control = null
var _clue_log: Control = null
var _camera_button: Control = null
var _title_screen: Control = null
var _game_over: Control = null
var _date_transition: Control = null
var _dialogue_overlay: Control = null
var _bubble_overlay: Control = null

# ---------------------------------------------------------------------------
# 场景节点
# ---------------------------------------------------------------------------
var _board_layer: Node3D = null
var _token_sprite: Sprite3D = null
var _token_shadow: MeshInstance3D = null

# ---------------------------------------------------------------------------
# 3D 场景组件
# ---------------------------------------------------------------------------
var _camera_3d: Camera3D = null
var _dir_light: DirectionalLight3D = null
var _world_env: WorldEnvironment = null
var _env: Environment = null
var _table_mesh: MeshInstance3D = null
var _table_mat: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# 兼容方法 (Node3D 没有 CanvasItem.get_viewport_rect)
# ---------------------------------------------------------------------------

## 返回主视口矩形 (替代 CanvasItem.get_viewport_rect)
func get_viewport_rect() -> Rect2:
	return get_viewport().get_visible_rect()

# ---------------------------------------------------------------------------
# 运行时状态
# ---------------------------------------------------------------------------
var day_count: int = 1
var game_time: float = 0.0
var _bg_transition: float = 0.0
var _bg_transition_target: float = 0.0
var _cam_pivot: Node3D = null
var _camera_offset: Vector2 = Vector2.ZERO
var _last_shake_offset_3d: Vector3 = Vector3.ZERO
var _drag_state: Dictionary = {
	"active": false,
	"is_dragging": false,
	"start_pos": Vector2.ZERO,
	"last_pos": Vector2.ZERO,
}
var _hovered_card: Card = null       # 当前鼠标悬停的卡牌 (hover 高亮)
var _mouse_screen_pos: Vector2 = Vector2.ZERO  # 最新鼠标屏幕坐标

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
	# === 3D 场景基础组件 (Camera3D, Light, Environment) ===
	_setup_3d_scene()

	# === 3D 棋盘层 (直接挂在根 Node3D 下) ===
	_board_layer = Node3D.new()
	_board_layer.name = "BoardLayer"
	add_child(_board_layer)

	# BoardVisual (Node3D, 管理 3D 卡牌)
	board_visual = load("res://scripts/controllers/board_visual.gd").new()
	board_visual.name = "BoardVisual"
	add_child(board_visual)

	# === 3D 桌面 ===
	_setup_table()

	# === Token (Sprite3D billboard, 始终面向相机) ===
	_token_sprite = Sprite3D.new()
	_token_sprite.name = "TokenSprite"
	_token_sprite.visible = false
	_token_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y  # Lua: FC_ROTATE_Y (只绕Y轴旋转, 精灵保持竖直)
	_token_sprite.pixel_size = 0.00065  # 每像素 0.00065m → 515px≈0.335m宽, 768px≈0.50m高 (匹配 Lua SPRITE_3D_W/H)
	_token_sprite.transparent = true
	_token_sprite.no_depth_test = false
	_token_sprite.render_priority = 1
	add_child(_token_sprite)

	# === Token Blob Shadow (扁平圆柱体, 脚下阴影) ===
	_token_shadow = MeshInstance3D.new()
	_token_shadow.name = "TokenShadow"
	_token_shadow.visible = false
	var shadow_cyl: CylinderMesh = CylinderMesh.new()
	shadow_cyl.top_radius = 0.5
	shadow_cyl.bottom_radius = 0.5
	shadow_cyl.height = 1.0  # 单位圆柱, 通过 scale 控制形状
	_token_shadow.mesh = shadow_cyl
	var shadow_mat: StandardMaterial3D = StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0, 0, 0, 0.3)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_token_shadow.material_override = shadow_mat
	# 初始缩放: X=0.369, Y=0.001(扁平), Z=0.168 (匹配 Lua SPRITE_3D_W)
	_token_shadow.scale = Vector3(0.369, 0.001, 0.168)
	add_child(_token_shadow)

	# === UI CanvasLayer (layer=10, 位于最顶层) ===
	var ui_layer: CanvasLayer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	ui_layer.layer = 10
	add_child(ui_layer)
	_ui_layer = ui_layer

	# VFX 放在独立的高层 CanvasLayer, 确保屏闪/横幅覆盖所有 UI
	var vfx_layer: CanvasLayer = CanvasLayer.new()
	vfx_layer.name = "VFXLayer"
	vfx_layer.layer = 100
	add_child(vfx_layer)

	_vfx = VFXManager.new()
	_vfx.name = "VFX"
	_vfx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vfx_layer.add_child(_vfx)

	_resource_bar = load("res://scripts/ui/resource_bar.gd").new()
	_resource_bar.name = "ResourceBar"
	_resource_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_resource_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(_resource_bar)

	_hand_panel = load("res://scripts/ui/hand_panel.gd").new()
	_hand_panel.name = "HandPanel"
	_hand_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_hand_panel)

	_clue_log = load("res://scripts/ui/clue_log.gd").new()
	_clue_log.name = "ClueLog"
	_clue_log.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_clue_log)

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

	# 气泡对话渲染层 (Token 头顶)
	_bubble_overlay = load("res://scripts/visual/bubble_overlay.gd").new()
	_bubble_overlay.name = "BubbleOverlay"
	_bubble_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bubble_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_overlay.m = self
	ui_layer.add_child(_bubble_overlay)

	# 对话系统渲染层 (遮罩 + 对话框 + 立绘)
	_dialogue_overlay = load("res://scripts/visual/dialogue_overlay.gd").new()
	_dialogue_overlay.name = "DialogueOverlay"
	_dialogue_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialogue_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_overlay.m = self
	ui_layer.add_child(_dialogue_overlay)

	# Title Screen (最顶层)
	_title_screen = load("res://scripts/visual/title_screen.gd").new()
	_title_screen.name = "TitleScreen"
	_title_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_title_screen)

# ---------------------------------------------------------------------------
# 3D 场景初始化 (Phase 0)
# ---------------------------------------------------------------------------

func _setup_3d_scene() -> void:
	# Camera3D: 45° 俯视, FOV 50
	_cam_pivot = Node3D.new()
	_cam_pivot.name = "CameraPivot"
	_cam_pivot.position = Vector3.ZERO
	add_child(_cam_pivot)

	_camera_3d = Camera3D.new()
	_camera_3d.name = "MainCamera"
	_camera_3d.fov = 45.0
	# 45° 俯视: 位于 Y=4.5, Z=-4.5 (与原版 UrhoX 一致)
	_camera_3d.position = Vector3(0, 4.5, -4.5)
	_camera_3d.rotation_degrees = Vector3(-45, 180, 0)
	_camera_3d.current = true
	_cam_pivot.add_child(_camera_3d)

	# DirectionalLight3D: 模拟日光
	_dir_light = DirectionalLight3D.new()
	_dir_light.name = "SunLight"
	_dir_light.rotation_degrees = Vector3(-50, -30, 0)
	_dir_light.light_energy = ATMO_BRIGHT["light_energy"]
	_dir_light.shadow_enabled = true
	add_child(_dir_light)

	# WorldEnvironment
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = BG_BRIGHT
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = ATMO_BRIGHT["ambient_color"]
	_env.ambient_light_energy = ATMO_BRIGHT["ambient_energy"]
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.fog_enabled = false  # 由 _apply_atmosphere() 动态控制

	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnv"
	_world_env.environment = _env
	add_child(_world_env)

# ---------------------------------------------------------------------------
# 3D 桌面初始化
# ---------------------------------------------------------------------------

func _setup_table() -> void:
	# 桌面: 棋盘下方的平面, 提供视觉地面
	var total_w: float = Board.COLS * (Card.CARD_W + Board.GAP) + 1.0
	var total_h: float = Board.ROWS * (Card.CARD_H + Board.GAP) + 1.0
	var table_size: Vector3 = Vector3(total_w, 0.05, total_h)

	_table_mesh = MeshInstance3D.new()
	_table_mesh.name = "TableSurface"
	var box: BoxMesh = BoxMesh.new()
	box.size = table_size
	_table_mesh.mesh = box

	_table_mat = StandardMaterial3D.new()
	_table_mat.albedo_color = ATMO_BRIGHT["table_color"]
	_table_mat.roughness = 0.85
	_table_mat.metallic = 0.0
	_table_mesh.material_override = _table_mat

	# 桌面位于卡牌下方
	_table_mesh.position = Vector3(0, -0.03, 0)
	add_child(_table_mesh)

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

	consumable_controller = load("res://scripts/controllers/consumable_controller.gd").new()
	consumable_controller.setup(self)

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
	_hand_panel.open_clue_log.connect(func(): _clue_log.open())

	# 相机按钮
	_camera_button.photograph_requested.connect(_on_photograph_request)
	_camera_button.exorcise_requested.connect(
		func(): card_interaction.handle_inventory_exorcism())
	_camera_button.camera_mode_entered.connect(_on_camera_mode_entered)
	_camera_button.camera_mode_exited.connect(_on_camera_mode_exited)

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

func _on_camera_mode_entered() -> void:
	board_visual.mg_show_on_scouted_cards()
	board_visual.mg_show_trails_on_board()

func _on_camera_mode_exited() -> void:
	board_visual.mg_clear_card_ghosts()
	board_visual.mg_clear_trail_ghosts()

func _on_photograph_request() -> void:
	if GameData.demo_state != "ready":
		return
	var row: int = token.target_row
	var col: int = token.target_col
	var card: Card = board.get_card(row, col)
	if card and not card.is_flipped and not card.is_flipping:
		card_interaction.do_photograph(card, row, col)

# =========================================================================
# 输入处理
# =========================================================================

func _unhandled_input(event: InputEvent) -> void:
	# 日期过渡中阻断所有输入
	if _date_transition and _date_transition.visible and _date_transition.is_active():
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
	# 始终记录鼠标位置 (用于 hover 检测)
	_mouse_screen_pos = event.position
	if not _drag_state["active"]:
		return
	var delta: Vector2 = event.position - _drag_state["start_pos"]
	if not _drag_state["is_dragging"]:
		if delta.length() > DRAG_THRESHOLD:
			_drag_state["is_dragging"] = true
	if _drag_state["is_dragging"]:
		var move_delta: Vector2 = event.position - _drag_state["last_pos"]
		_drag_state["last_pos"] = event.position
		# 屏幕像素 → 世界坐标偏移 (基于相机投影比例)
		var vp_size: Vector2 = get_viewport_rect().size
		if vp_size.y > 0 and _camera_3d:
			var cam_dist: float = _camera_3d.position.length()
			var half_h: float = cam_dist * tan(deg_to_rad(_camera_3d.fov * 0.5))
			var px_to_world: float = (half_h * 2.0) / vp_size.y
			# 相机旋转 180° yaw: 屏幕右→世界+X, 屏幕下→世界+Z
			_camera_offset.x += move_delta.x * px_to_world
			_camera_offset.y += move_delta.y * px_to_world
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

	# 气泡对话 — 点击 Token (投影 3D 位置到屏幕后判断距离)
	if _bubble_dialogue and _token_sprite.visible and _camera_3d:
		var token_screen: Vector2 = _camera_3d.unproject_position(
			_token_sprite.global_position)
		if pos.distance_to(token_screen) < TOKEN_CLICK_RADIUS:
			_bubble_dialogue.click_trigger()
			return

	# 棋盘点击检测
	var grid_pos: Vector2i = board_visual.hit_test(pos)
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
	# 当天翻牌数驱动氛围 (匹配 Lua: dailyRevealed = cardsRevealed - dayStartRevealed)
	var daily_revealed: int = GameData.cards_revealed - GameData.day_start_revealed
	_bg_transition_target = minf(float(daily_revealed) / 8.0, 1.0)
	_bg_transition = move_toward(_bg_transition, _bg_transition_target, 2.0 * dt)

	# 3D 相机平移 (平滑跟随 _camera_offset)
	if _cam_pivot:
		var target_pivot: Vector3 = Vector3(_camera_offset.x, 0, _camera_offset.y)
		# 先去掉上一帧的 shake 残留，再 lerp 到干净的 target（匹配 Lua 绝对设置行为）
		var clean_pos: Vector3 = _cam_pivot.position - _last_shake_offset_3d
		clean_pos = clean_pos.lerp(target_pivot, minf(10.0 * dt, 1.0))
		# 在干净的 base 上叠加本帧的 shake
		var shake_3d := Vector3.ZERO
		if _vfx:
			var shake: Vector2 = _vfx.shake_offset
			if shake != Vector2.ZERO:
				shake_3d = Vector3(shake.x * 0.005, shake.y * 0.005, 0)
		_cam_pivot.position = clean_pos + shake_3d
		_last_shake_offset_3d = shake_3d

	# 2D UI 层震动同步 (匹配 Lua: nvgTranslate(vg, sx, sy))
	if _ui_layer and _vfx:
		var shake_2d: Vector2 = _vfx.shake_offset
		_ui_layer.offset = shake_2d

	# Token
	token.update(dt)
	board_visual.update_token_visual()

	# 地图道具浮动动画
	board_visual.update_item_visuals(game_time)

	# 暗面幽灵浮动 & NPC 呼吸动画
	if dark_world.active:
		board_visual.update_ghost_visuals(game_time)
		board_visual.update_npc_visuals(game_time)

	# MonsterGhost chibi 浮动/摇摆动画
	board_visual.update_monster_ghost_visuals(game_time)

	# 对话系统 tween 管理
	_update_dialogue_tweens(dt)

	# 气泡对话
	_update_bubble_tweens(dt)

	# 卡牌悬停检测 + hover_t 更新
	_update_card_hover(dt)

	# 3D 氛围过渡 (背景色 + 灯光 + 环境光 + 雾)
	_apply_atmosphere(_bg_transition)

# ---------------------------------------------------------------------------
# 卡牌悬停高亮
# ---------------------------------------------------------------------------

## 每帧检测鼠标悬停卡牌, 平滑更新所有卡牌的 hover_t
func _update_card_hover(dt: float) -> void:
	# 确定当前悬停目标
	if GameData.game_phase != "playing" or GameData.demo_state != "ready" \
			or _drag_state["is_dragging"]:
		_hovered_card = null
	else:
		var grid_pos: Vector2i = board_visual.hit_test(_mouse_screen_pos)
		if grid_pos != Vector2i.ZERO:
			var card: Card = board.get_card(grid_pos.x, grid_pos.y)
			# 相机模式下: 只悬停未翻开或怪物卡
			if _camera_button.is_camera_mode() and card:
				if card.is_flipped and card.type != "monster":
					card = null
			_hovered_card = card
		else:
			_hovered_card = null

	# 更新所有卡牌的 hover_t (lerp dt*12)
	if board == null:
		return
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = board.get_card(r, c)
			if card == null:
				continue
			var target: float = 1.0 if card == _hovered_card else 0.0
			card.hover_t += (target - card.hover_t) * minf(1.0, dt * 12.0)
			if absf(card.hover_t - target) < 0.005:
				card.hover_t = target

	# 应用悬停缩放
	board_visual.apply_hover_scales()

# ---------------------------------------------------------------------------
# 3D 氛围过渡
# ---------------------------------------------------------------------------

## 根据过渡因子 t (0=明亮, 1=暗黑) 更新所有 3D 环境参数
func _apply_atmosphere(t: float) -> void:
	if not _env:
		return
	# 背景色
	_env.background_color = BG_BRIGHT.lerp(BG_DARK, t)
	# 主光源
	if _dir_light:
		_dir_light.light_energy = lerpf(
			ATMO_BRIGHT["light_energy"], ATMO_DARK["light_energy"], t)
	# 环境光
	_env.ambient_light_color = ATMO_BRIGHT["ambient_color"].lerp(
		ATMO_DARK["ambient_color"], t)
	_env.ambient_light_energy = lerpf(
		ATMO_BRIGHT["ambient_energy"], ATMO_DARK["ambient_energy"], t)
	# 雾效 (超过阈值才启用, 避免低值时多余开销)
	var fog_t: float = clampf((t - 0.3) / 0.7, 0.0, 1.0)  # 30% 后才开始出雾
	_env.fog_enabled = fog_t > 0.01
	if _env.fog_enabled:
		_env.fog_density = lerpf(0.0, ATMO_DARK["fog_density"], fog_t)
		_env.fog_light_color = ATMO_BRIGHT["fog_color"].lerp(
			ATMO_DARK["fog_color"], fog_t)
	# 桌面颜色
	if _table_mat:
		_table_mat.albedo_color = ATMO_BRIGHT["table_color"].lerp(
			ATMO_DARK["table_color"], t)

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
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_dialogue_system, "overlay_alpha", 1.0, 0.3)
	tw.tween_property(_dialogue_system, "box_offset_y", 0.0, 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_dialogue_system, "box_alpha", 1.0, 0.3)
	tw.tween_property(_dialogue_system, "portrait_alpha", 1.0, 0.4).set_delay(0.1)
	tw.tween_property(_dialogue_system, "portrait_offset_y", 0.0, 0.4) \
		.set_delay(0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_dialogue_system, "portrait_scale", 1.0, 0.3).set_delay(0.1)
	# 完成回调
	var tw_cb: Tween = create_tween()
	tw_cb.tween_callback(_dialogue_system.on_enter_complete).set_delay(0.55)

func _tween_dialogue_exit() -> void:
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_dialogue_system, "overlay_alpha", 0.0, 0.25)
	tw.tween_property(_dialogue_system, "box_offset_y", 60.0, 0.3) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_dialogue_system, "box_alpha", 0.0, 0.25)
	tw.tween_property(_dialogue_system, "portrait_alpha", 0.0, 0.25)
	tw.tween_property(_dialogue_system, "portrait_offset_y", 20.0, 0.25)
	# 完成回调
	var tw_cb: Tween = create_tween()
	tw_cb.tween_callback(_dialogue_system.on_exit_complete).set_delay(0.35)

# ---------------------------------------------------------------------------
# 气泡对话 tween 管理
# ---------------------------------------------------------------------------

func _update_bubble_tweens(dt: float) -> void:
	if _bubble_dialogue == null:
		return

	var is_idle: bool = GameData.demo_state == "ready"
	var can_trigger: bool = GameData.game_phase == "playing" \
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
				var tw: Tween = create_tween().set_parallel(true)
				tw.tween_property(_bubble_dialogue, "bubble_alpha", 1.0, 0.2)
				tw.tween_property(_bubble_dialogue, "bubble_scale", 1.0, 0.25) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
				tw.tween_property(_bubble_dialogue, "offset_y", 0.0, 0.2)
				var tw_cb: Tween = create_tween()
				tw_cb.tween_callback(_bubble_dialogue.on_show_complete).set_delay(0.3)
		"hiding":
			if not _bubble_hide_tweened:
				_bubble_hide_tweened = true
				var tw: Tween = create_tween().set_parallel(true)
				tw.tween_property(_bubble_dialogue, "bubble_alpha", 0.0, 0.15)
				tw.tween_property(_bubble_dialogue, "bubble_scale", 0.5, 0.15)
				var tw_cb: Tween = create_tween()
				tw_cb.tween_callback(_bubble_dialogue.on_hide_complete).set_delay(0.2)
		"hidden":
			_bubble_show_tweened = false
			_bubble_hide_tweened = false
