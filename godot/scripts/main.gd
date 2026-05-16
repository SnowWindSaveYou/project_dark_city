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
# 物语系列背景色：明面纯白、暗面深紫黑
const BG_BRIGHT: Color = Color(0.97, 0.97, 0.97)   # 近纯白（SHAFT 风格空白背景）
const BG_DARK: Color   = Color(0.06, 0.05, 0.10)   # 极深紫黑
const TOKEN_CLICK_RADIUS: float = 32.0

# 氛围参数 (明亮 → 暗黑, 由 _bg_transition 0→1 插值)
const ATMO_BRIGHT: Dictionary = {
	# 灯光 — 白背景下大幅压低，避免叠加过曝
	"light_color":    Color(1.00, 0.97, 0.90),   # 暖白阳光
	"light_energy":   1.4,                        # 从 2.2 降到 1.4
	"ambient_color":  Color(0.72, 0.74, 0.80),   # 明亮冷白天光（配白背景）
	"ambient_energy": 0.50,
	# 背景/雾
	"fog_enabled": false,
	"fog_density": 0.0,
	"fog_color":   Color(0.5, 0.6, 0.7),
	"table_color": Color(0.25, 0.22, 0.20),
	# Bloom — 白背景几乎关闭 glow，避免发白
	"glow_intensity":  0.20,
	"glow_bloom":      0.00,
	# 色彩调整 — 物语系列偏平、去饱和的清冷感
	"adj_brightness":  0.90,
	"adj_contrast":    1.02,
	"adj_saturation":  0.92,
	# Tonemap — 降低 exposure 进一步压住高光
	"tonemap_exposure": 0.82,
	"tonemap_white":    1.0,
}
const ATMO_DARK: Dictionary = {
	# 灯光
	"light_color":    Color(0.62, 0.65, 0.90),   # 冷蓝紫幽光
	"light_energy":   0.55,
	"ambient_color":  Color(0.12, 0.08, 0.22),   # 深紫环境
	"ambient_energy": 0.30,
	# 背景/雾
	"fog_enabled": true,
	"fog_density": 0.04,
	"fog_color":   Color(0.08, 0.06, 0.12),
	"table_color": Color(0.10, 0.08, 0.14),
	# Bloom — 暗面元素发光渗出
	"glow_intensity":  1.10,
	"glow_bloom":      0.08,
	# 色彩调整 — 压抑去饱和
	"adj_brightness":  0.88,
	"adj_contrast":    1.18,
	"adj_saturation":  0.58,
	# Tonemap
	"tonemap_exposure": 0.82,
	"tonemap_white":    1.0,
}
# 雷暴天气叠加偏移 (在当前氛围基础上额外施加)
const ATMO_STORMY_OFFSET: Dictionary = {
	"adj_brightness":  -0.07,
	"adj_contrast":    +0.08,
	"adj_saturation":  -0.15,
	"light_energy":    -0.35,
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
# 白夜跟随精灵
# ---------------------------------------------------------------------------
var _baiye: Baiye = null
var _baiye_sprite: Sprite2D = null

# ---------------------------------------------------------------------------
# 对话系统
# ---------------------------------------------------------------------------
var _dialogue_system: DialogueSystem = null
var _bubble_dialogue: BubbleDialogue = null
var _dlg_enter_tweened: bool = false
var _dlg_exit_tweened: bool = false
var _bubble_show_tweened: bool = false
var _bubble_hide_tweened: bool = false
var _npc_bubbles: Dictionary = {}          # npc_id → BubbleDialogue
var _npc_bubble_show_tweened: Dictionary = {}  # npc_id → bool
var _npc_bubble_hide_tweened: Dictionary = {}  # npc_id → bool

# ---------------------------------------------------------------------------
# UI 节点引用
# ---------------------------------------------------------------------------
var _vfx: VFXManager = null
var _ui_layer: CanvasLayer = null
var _resource_bar: Control = null
var _event_popup: Control = null
var _shop_popup: Control = null
var _rift_popup: Control = null
var _photo_popup: Control = null
var _conversion_popup: Control = null
var _hand_panel: Control = null
var _clue_log: Control = null
var _camera_button: Control = null
var _advance_day_btn: Control = null
var _title_screen: Control = null
var _game_over: Control = null
var _date_transition: Control = null
var _dialogue_overlay: Control = null
var _bubble_overlay: Control = null
var _debug_panel: DebugPanel = null
var _settings_overlay: Control = null

# ---------------------------------------------------------------------------
# 天气粒子
# ---------------------------------------------------------------------------
var _weather_particles: WeatherParticles = null

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
var _monogatari_bg: Node2D = null   # 物语系列风格背景层

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
	set_meta("_npc_bubbles", _npc_bubbles)  # 供 bubble_overlay 读取

	# 场景树 → 控制器 → 信号
	_setup_scene_tree()
	_setup_controllers()
	_connect_signals()

	# 初始棋盘
	game_flow.generate_board()

	# 白夜跟随精灵 (在 _ui_layer 创建后初始化)
	_baiye = Baiye.new()
	_baiye_sprite = Sprite2D.new()
	_baiye_sprite.name = "BaiyeSprite"
	_baiye_sprite.visible = false
	_baiye_sprite.texture = _baiye.texture
	_baiye_sprite.modulate = Color(1, 1, 1, 0)
	_baiye_sprite.z_index = 5  # 位于 UI 下方, Token 上方
	_ui_layer.add_child(_baiye_sprite)

	# 从主菜单跳转而来，直接进入游戏，跳过游戏内标题画面
	_on_title_start()

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
	_token_sprite.pixel_size = 0.0013  # ×2 修正: Urho3D bb.size 是半尺寸, Godot pixel_size 是全尺寸
	_token_sprite.transparent = true
	_token_sprite.no_depth_test = false
	_token_sprite.render_priority = 0
	# OPAQUE_PREPASS: 不透明像素写深度缓冲, 保证 chibi 之间正确遮挡
	_token_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_token_sprite.alpha_scissor_threshold = 0.5
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
	# 初始缩放: ×2 修正后 TOKEN_WORLD_W≈0.67m，缩小至约60%避免阴影过大
	_token_shadow.scale = Vector3(0.44, 0.001, 0.20)
	add_child(_token_shadow)

	# === UI CanvasLayer (layer=10, 位于最顶层) ===
	var ui_layer: CanvasLayer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	ui_layer.layer = 10
	add_child(ui_layer)
	_ui_layer = ui_layer

	# 物语系列背景层 (layer=2: 最底层，在 3D 场景和天气粒子之下)
	var bg_layer: CanvasLayer = CanvasLayer.new()
	bg_layer.name = "MonogatariBGLayer"
	bg_layer.layer = 2
	add_child(bg_layer)

	_monogatari_bg = load("res://scripts/visual/monogatari_bg.gd").new()
	_monogatari_bg.name = "MonogatariBG"
	bg_layer.add_child(_monogatari_bg)

	# 天气粒子层 (layer=5: 位于 UI 层之下，渲染在界面背后)
	var weather_layer: CanvasLayer = CanvasLayer.new()
	weather_layer.name = "WeatherLayer"
	weather_layer.layer = 5
	add_child(weather_layer)

	_weather_particles = WeatherParticles.new()
	_weather_particles.name = "WeatherParticles"
	weather_layer.add_child(_weather_particles)

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

	var resource_bar_scene: PackedScene = load("res://scenes/ui/resource_bar.tscn")
	_resource_bar = resource_bar_scene.instantiate()
	ui_layer.add_child(_resource_bar)

	# HandPanel — Scene 化（保留 _draw() 笔记本渲染）
	_hand_panel = load("res://scenes/ui/hand_panel.tscn").instantiate()
	ui_layer.add_child(_hand_panel)

	# ClueLog — Scene 化
	_clue_log = load("res://scenes/ui/clue_log.tscn").instantiate()
	ui_layer.add_child(_clue_log)

	# CameraButton — Scene 化（位于画面下方中心）
	_camera_button = load("res://scenes/ui/camera_button.tscn").instantiate()
	ui_layer.add_child(_camera_button)

	# AdvanceDayButton — 右下角"进入下一天"悬浮按钮
	_advance_day_btn = load("res://scripts/ui/advance_day_button.gd").new()
	_advance_day_btn.name = "AdvanceDayButton"
	ui_layer.add_child(_advance_day_btn)

	# BubbleOverlay — 气泡层，z_index=-1 确保低于所有 UI 菜单和弹窗
	_bubble_overlay = load("res://scenes/screens/bubble_overlay.tscn").instantiate()
	_bubble_overlay.m = self
	_bubble_overlay.z_index = -1
	ui_layer.add_child(_bubble_overlay)

	var event_popup_scene: PackedScene = load("res://scenes/ui/event_popup.tscn")
	_event_popup = event_popup_scene.instantiate()
	ui_layer.add_child(_event_popup)

	var rift_popup_scene: PackedScene = load("res://scenes/ui/rift_popup.tscn")
	_rift_popup = rift_popup_scene.instantiate()
	ui_layer.add_child(_rift_popup)

	var photo_popup_scene: PackedScene = load("res://scenes/ui/photo_popup.tscn")
	_photo_popup = photo_popup_scene.instantiate()
	ui_layer.add_child(_photo_popup)

	# 注入子弹窗引用 (保持控制器代码兼容)
	_event_popup.bind_sub_popups(_rift_popup, _photo_popup)

	var conversion_popup_scene: PackedScene = load("res://scenes/ui/conversion_popup.tscn")
	_conversion_popup = conversion_popup_scene.instantiate()
	ui_layer.add_child(_conversion_popup)

	var shop_popup_scene: PackedScene = load("res://scenes/ui/shop_popup.tscn")
	_shop_popup = shop_popup_scene.instantiate()
	ui_layer.add_child(_shop_popup)

	# GameOver — Scene 化
	_game_over = load("res://scenes/screens/game_over.tscn").instantiate()
	ui_layer.add_child(_game_over)

	_date_transition = load("res://scripts/visual/date_transition.gd").new()
	_date_transition.name = "DateTransition"
	_date_transition.set_anchors_preset(Control.PRESET_FULL_RECT)
	_date_transition.visible = false
	ui_layer.add_child(_date_transition)

	# DialogueOverlay — Scene 化 (遮罩 + 对话框 + 立绘)
	_dialogue_overlay = load("res://scenes/screens/dialogue_overlay.tscn").instantiate()
	_dialogue_overlay.m = self
	ui_layer.add_child(_dialogue_overlay)

	# DebugPanel (开发调试面板, 按 1 切换; 打包 release 时不创建)
	if OS.is_debug_build():
		_debug_panel = DebugPanel.create(ui_layer)

	# Title Screen (最顶层) — Scene 化
	_title_screen = load("res://scenes/screens/title_screen.tscn").instantiate()
	ui_layer.add_child(_title_screen)

	# 设置 Overlay (覆盖在 title_screen 之上, 游戏内 ESC 呼出)
	_settings_overlay = load("res://scenes/screens/settings.tscn").instantiate()
	_settings_overlay.quit_requested.connect(func() -> void: get_tree().quit())
	ui_layer.add_child(_settings_overlay)

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
	_camera_3d.current = true
	_cam_pivot.add_child(_camera_3d)
	# 精确匹配 Lua: cameraNode:LookAt(Vector3(0, 0, -0.3))
	# 必须在 add_child 后调用 look_at, 否则 global_position 不可用
	_camera_3d.look_at(Vector3(0, 0, -0.3), Vector3.UP)

	# DirectionalLight3D: 模拟日光
	_dir_light = DirectionalLight3D.new()
	_dir_light.name = "SunLight"
	# Lua: SetDirection(0.5, -1.0, 0.6) → 光从右前上方照向左后下方
	# pitch ≈ -50°, yaw ≈ atan2(0.5,0.6) ≈ 40°, 阴影落在角色身后偏左
	_dir_light.rotation_degrees = Vector3(-50, 40, 0)
	_dir_light.light_color  = ATMO_BRIGHT["light_color"]
	_dir_light.light_energy = ATMO_BRIGHT["light_energy"]
	_dir_light.shadow_enabled = false  # chibi 已有 blob shadow，不需要实时投影
	add_child(_dir_light)

	# WorldEnvironment
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = BG_BRIGHT
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color  = ATMO_BRIGHT["ambient_color"]
	_env.ambient_light_energy = ATMO_BRIGHT["ambient_energy"]
	# Tonemap
	_env.tonemap_mode     = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = ATMO_BRIGHT["tonemap_exposure"]
	_env.tonemap_white    = ATMO_BRIGHT["tonemap_white"]
	# Glow (Bloom)
	_env.glow_enabled    = true
	_env.glow_normalized = false
	_env.glow_intensity  = ATMO_BRIGHT["glow_intensity"]
	_env.glow_bloom      = ATMO_BRIGHT["glow_bloom"]
	# Color Adjustment
	_env.adjustment_enabled    = true
	_env.adjustment_brightness = ATMO_BRIGHT["adj_brightness"]
	_env.adjustment_contrast   = ATMO_BRIGHT["adj_contrast"]
	_env.adjustment_saturation = ATMO_BRIGHT["adj_saturation"]
	# Fog (由 _apply_atmosphere() 动态控制)
	_env.fog_enabled = false

	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnv"
	_world_env.environment = _env
	add_child(_world_env)

# ---------------------------------------------------------------------------
# 3D 桌面初始化
# ---------------------------------------------------------------------------

func _setup_table() -> void:
	# 桌面已移除 — 物语系列风格场景不使用地面平面
	pass

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

	# 手牌面板需要 card_manager 和 consumable_controller 引用才能展示内容
	_hand_panel.setup(card_manager, consumable_controller)

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

	# 事件弹窗 (场景化拆分后信号分布在三个组件)
	_event_popup.popup_closed.connect(
		func(card: Card): card_interaction.on_popup_dismissed(card))
	_event_popup.toast_dismissed.connect(func(_ct: String): pass)

	# 裂隙确认 (独立组件)
	_rift_popup.rift_confirmed.connect(
		func(): card_interaction.on_rift_confirmed())
	_rift_popup.rift_cancelled.connect(
		func(): card_interaction.on_rift_cancelled())

	# 拍照预览 (独立组件)
	_photo_popup.photo_popup_closed.connect(
		func(card_type: String): card_interaction.on_photo_popup_dismissed(card_type))

	# 资源转化确认 (独立组件)
	_conversion_popup.conversion_confirmed.connect(
		func(): card_interaction.on_conversion_confirmed())
	_conversion_popup.conversion_cancelled.connect(
		func(): card_interaction.on_conversion_cancelled())

	# 商店 (需区分普通/暗面)
	_shop_popup.shop_closed.connect(_on_shop_closed)

	# 道具栏变更 → 刷新手牌面板道具页
	GameData.item_changed.connect(func(_key: String, _cnt: int) -> void:
		if _hand_panel and _hand_panel.is_active():
			_hand_panel.refresh())

	# 手牌面板
	_hand_panel.end_day_pressed.connect(func(): game_flow.advance_day())
	_hand_panel.schedule_toggled.connect(func(idx: int) -> void:
		card_manager.toggle_defer(idx)
		_hand_panel.refresh())
	_hand_panel.use_exorcism_pressed.connect(
		func(): card_interaction.handle_inventory_exorcism())
	_hand_panel.use_map_pressed.connect(
		func(): game_flow.reveal_random_card())
	_hand_panel.open_clue_log.connect(func(): _clue_log.open())

	# 进入下一天悬浮按钮
	_advance_day_btn.setup(card_manager)
	_advance_day_btn.advance_day_requested.connect(func(): game_flow.advance_day())

	# 相机按钮
	_camera_button.photograph_requested.connect(_on_photograph_request)
	_camera_button.exorcise_requested.connect(
		func(): card_interaction.handle_inventory_exorcism())
	_camera_button.camera_mode_entered.connect(_on_camera_mode_entered)
	_camera_button.camera_mode_exited.connect(_on_camera_mode_exited)

	# 资源栏 — 暗面退出
	_resource_bar.dark_exit_pressed.connect(
		func(): dark_world_flow.on_dark_exit_requested())

	# DebugPanel 调试动作
	if _debug_panel:
		_debug_panel.debug_action.connect(_on_debug_action)

	# NPC 交易信号 → 飞字反馈
	if game_flow.npc_manager:
		var npc_mgr: NPCManager = game_flow.npc_manager
		npc_mgr.trade_executed.connect(func(banner_text: String) -> void:
			if _vfx:
				_vfx.action_banner(banner_text, GameTheme.safe, 2.0)
			AudioManager.play_sfx("resource_gain")
		)
		npc_mgr.trade_failed.connect(func(reason: String) -> void:
			var msg: String = "资源不足！" if reason == "insufficient" else "今天已经交易过了~"
			if _vfx:
				_vfx.action_banner(msg, GameTheme.danger, 1.8)
		)
		npc_mgr.action_executed.connect(func(_action: String, banner_text: String) -> void:
			if _vfx:
				_vfx.action_banner(banner_text, GameTheme.highlight, 2.0)
		)

	# 故事/晨间/里程碑事件对话 (game_flow 触发, 由 DialogueSystem 呈现)
	game_flow.event_dialogue_requested.connect(_on_event_dialogue_requested)

# =========================================================================
# 信号回调
# =========================================================================

func _on_title_start() -> void:
	GameData.set_game_phase("playing")
	card_interaction.reset_daily_steps()
	# 播放日期切换动效（第1天），完成后再发牌；动效内含"第X天"文字，不显示横幅。
	# Day 1 入场不走晨间事件链，需临时断开常规的 transition_completed 连接，
	# 用一次性回调替代，结束后恢复常规连接。
	for c in _date_transition.transition_completed.get_connections():
		_date_transition.transition_completed.disconnect(c["callable"])
	var conn: Callable = func() -> void:
		# 恢复常规连接（供 Day 2+ 使用）
		_date_transition.transition_completed.connect(
			func(): game_flow.on_date_transition_complete())
		game_flow.start_deal(false)
	_date_transition.transition_completed.connect(conn, CONNECT_ONE_SHOT)
	_date_transition.play(day_count)

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

func _on_debug_action(action_id: String) -> void:
	match action_id:
		"enter_dark":
			if GameData.demo_state == "ready":
				dark_world_flow.enter_dark_world(token.target_row, token.target_col, true)
		"ins_10":
			GameData.modify_resource("inspiration", 10)
		"ins_50":
			GameData.modify_resource("inspiration", 50)
		"trust_up":
			GameData.modify_resource("trust", 1)
		"trust_down":
			GameData.modify_resource("trust", -1)
		"power_up":
			StoryManager.modify_baiye_power(1)
		"power_max":
			StoryManager.baiye_power = 5
		"clear_sleep":
			GameData.set_resource("sleep_days", 0)
		"add_frag":
			# 收集第一个尚未获得的碎片（与 Lua 版逻辑一致）
			var all_frags: Array = StoryManager.get_all_fragments()
			for frag_info in all_frags:
				if not frag_info.get("collected", false):
					StoryManager.collect_fragment(frag_info["id"])
					print("[Debug] add_frag: collected %s" % frag_info["id"])
					break
		"frag_4":
			for i in range(1, 5):
				StoryManager.collect_fragment("memory_%02d" % i)
		"frag_9":
			for i in range(1, 10):
				StoryManager.collect_fragment("memory_%02d" % i)
		"reset_flags":
			StoryManager.reset_flags()
		"next_day":
			if GameData.demo_state == "ready":
				game_flow.advance_day()
	print("[Debug] action: %s" % action_id)

## 故事/晨间/里程碑事件对话请求
## event: 含 dialogue(Array) 和 portrait(String) 的事件数据
## on_complete: 对话结束后回调, 参数为 chosen_choice_id (无选择时传 "")
func _on_event_dialogue_requested(event: Dictionary, on_complete: Callable) -> void:
	var dialogue: Array = event.get("dialogue", [])
	var portrait_path: String = event.get("portrait", "")
	print("[Main] _on_event_dialogue_requested: id=%s, lines=%d, dlg_state=%s, demo_state=%s" % [
		event.get("id", "?"), dialogue.size(), _dialogue_system.state, GameData.demo_state])
	if dialogue.is_empty() or _dialogue_system.state != "idle":
		# 无台词 或 对话系统忙碌 → 直接回调, 避免链断裂
		print("[Main] _on_event_dialogue_requested: SKIP (empty=%s, state=%s)" % [dialogue.is_empty(), _dialogue_system.state])
		on_complete.call("")
		return
	# 背景图：event 中若显式指定则优先，否则自动推断当前地点背景
	var bg_path: String = event.get("bg_image", _get_current_dialogue_bg())
	_dialogue_system.start(dialogue, portrait_path, bg_path, func() -> void:
		print("[Main] event dialogue on_complete fired")
		on_complete.call("")
	)

## 根据当前游戏状态推断对话背景图路径
## - 暗面世界：按层级返回对应暗面背景图
## - 现实世界：返回当前所站地点的卡面图（CardImageMap.LOCATION_IMAGES）
func _get_current_dialogue_bg() -> String:
	# 暗面世界
	if dark_world != null and dark_world.active:
		const DARK_BGS: Array = [
			"res://assets/image/bg_dark_world_open_20260515161039.png",
			"res://assets/image/bg_dark_world_deep_v2_20260515161735.png",
		]
		var layer: int = dark_world.current_layer
		if layer == 0:
			return DARK_BGS[0]
		elif layer < DARK_BGS.size():
			return DARK_BGS[layer]
		else:
			return DARK_BGS[randi() % DARK_BGS.size()]
	# 现实世界：用 CardImageMap 获取当前格子地点的卡面图
	if board != null and token != null:
		var card: Card = board.get_card(token.target_row, token.target_col)
		if card != null and card.location != "":
			return CardImageMap.get_location_image_path(card.location)
	return ""

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
			# ESC: 若设置面板已打开则关闭，否则打开设置面板
			if _settings_overlay and _settings_overlay.visible:
				_settings_overlay.hide_settings()
			elif _settings_overlay:
				_settings_overlay.show_settings()
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

	# NPC 点击检测 (ready 状态下才响应, 避免移动途中误触)
	# 只有玩家与 NPC 同格才能交互
	if GameData.demo_state == "ready":
		var npc_hit: Dictionary = board_visual.hit_test_npc(pos)
		if not npc_hit.is_empty():
			var same_tile: bool = (npc_hit["row"] == token.target_row \
				and npc_hit["col"] == token.target_col)
			if same_tile:
				card_interaction.handle_npc_click(npc_hit["row"], npc_hit["col"])
				return
			# 不同格：透传给棋盘，允许玩家走过去

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
	# 暗面世界时 target 由进出流程控制, 此处仅更新明面时的值
	if not dark_world.active:
		var daily_revealed: int = GameData.cards_revealed - GameData.day_start_revealed
		_bg_transition_target = minf(float(daily_revealed) / 8.0, 1.0)
		# 明面 BGM: 固定使用 day_light, 不区分昼夜氛围
		# (play_bgm 内部已跳过相同 key / 已过渡中的 key, 每帧调用安全)
		if GameData.game_phase == "playing" and not dark_world_flow.is_dark_transitioning:
			AudioManager.play_bgm("day_light")
	_bg_transition = move_toward(_bg_transition, _bg_transition_target, 2.0 * dt)

	# 3D 相机平移 (平滑跟随 _camera_offset)
	if _cam_pivot:
		var target_pivot: Vector3 = Vector3(_camera_offset.x, 0, _camera_offset.y)
		# 先去掉上一帧的 shake 残留，再 lerp 到干净的 target（匹配 Lua 绝对设置行为）
		var clean_pos: Vector3 = _cam_pivot.position - _last_shake_offset_3d
		clean_pos = clean_pos.lerp(target_pivot, minf(10.0 * dt, 1.0))
		# 在干净的 base 上叠加本帧的 shake
		var shake_3d: Vector3 = Vector3.ZERO
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

	# 白夜跟随精灵
	_update_baiye(dt)

	# 安全区光环上浮动画
	board_visual.update_glow_rings(game_time)

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

	# DebugPanel 数据刷新 (仅可见时)
	if _debug_panel and _debug_panel.visible:
		_debug_panel.refresh({
			"day": day_count,
			"phase": GameData.game_phase,
			"state": GameData.demo_state,
			"san": GameData.get_resource("san"),
			"health": GameData.get_resource("health"),
			"inspiration": GameData.get_resource("inspiration"),
			"trust": GameData.get_resource("trust"),
			"power": GameData.get_resource("power"),
			"money": GameData.get_resource("money"),
			"film": GameData.get_resource("film"),
			"order": GameData.get_resource("order"),
			"fragments": StoryManager.get_fragment_count(),
			"chapter": StoryManager.current_chapter,
			"dark_active": dark_world.active,
			"cards_revealed": GameData.cards_revealed,
		})

# ---------------------------------------------------------------------------
# 白夜跟随精灵更新
# ---------------------------------------------------------------------------

func _update_baiye(dt: float) -> void:
	if _baiye == null or _baiye_sprite == null or _camera_3d == null:
		return

	# 条件：游戏中 + Token 可见 + 白夜应该出现
	var should_show: bool = GameData.game_phase == "playing" \
		and _token_sprite.visible \
		and _baiye.should_show()

	if should_show:
		# 获取 Token 的屏幕坐标
		var token_screen: Vector2 = _camera_3d.unproject_position(_token_sprite.global_position)

		if not _baiye.visible:
			# 首次出现：定位到 Token 旁边并重置入场参数
			_baiye.show(token_screen.x, token_screen.y)
			_baiye_sprite.visible = true

		# 更新跟随目标
		_baiye.set_follow_target(token_screen.x, token_screen.y)
		_baiye.update(dt)

		# 入场动画：平滑过渡 alpha 和 scale
		_baiye.alpha = move_toward(_baiye.alpha, Baiye.SPIRIT_ALPHA, 1.5 * dt)
		_baiye.scale_x = move_toward(_baiye.scale_x, 1.0, 3.0 * dt)
		_baiye.scale_y = move_toward(_baiye.scale_y, 1.0, 3.0 * dt)
	else:
		if _baiye.visible:
			# 退场动画：渐出后隐藏
			_baiye.alpha = move_toward(_baiye.alpha, 0.0, 2.0 * dt)
			if _baiye.alpha <= 0.01:
				_baiye.hide()
				_baiye_sprite.visible = false

	# 应用绘制数据到 Sprite2D
	var draw_data: Dictionary = _baiye.get_draw_data(game_time)
	if draw_data.get("visible", false):
		_baiye_sprite.position = Vector2(draw_data["x"], draw_data["y"])
		_baiye_sprite.modulate = Color(1, 1, 1, draw_data["alpha"])
		_baiye_sprite.scale = Vector2(draw_data["scale_x"], draw_data["scale_y"])
	else:
		_baiye_sprite.modulate = Color(1, 1, 1, 0)

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

	# 雷暴天气偏移系数 (0=无雷暴, 1=完整偏移)
	var stormy_t: float = 0.0
	if _weather_particles:
		var wt: int = _weather_particles.get_weather_type()
		if wt == Weather.Type.STORMY:
			stormy_t = 1.0
		elif wt == Weather.Type.RAINY:
			stormy_t = 0.4   # 雨天轻微压暗

	# 背景色
	_env.background_color = BG_BRIGHT.lerp(BG_DARK, t)

	# 主光源
	if _dir_light:
		_dir_light.light_color = ATMO_BRIGHT["light_color"].lerp(
			ATMO_DARK["light_color"], t)
		var base_energy: float = lerpf(
			ATMO_BRIGHT["light_energy"], ATMO_DARK["light_energy"], t)
		_dir_light.light_energy = base_energy + ATMO_STORMY_OFFSET["light_energy"] * stormy_t

	# 环境光
	_env.ambient_light_color = ATMO_BRIGHT["ambient_color"].lerp(
		ATMO_DARK["ambient_color"], t)
	_env.ambient_light_energy = lerpf(
		ATMO_BRIGHT["ambient_energy"], ATMO_DARK["ambient_energy"], t)

	# Tonemap
	_env.tonemap_exposure = lerpf(
		ATMO_BRIGHT["tonemap_exposure"], ATMO_DARK["tonemap_exposure"], t)
	_env.tonemap_white = lerpf(
		ATMO_BRIGHT["tonemap_white"], ATMO_DARK["tonemap_white"], t)

	# Glow (Bloom)
	_env.glow_intensity = lerpf(
		ATMO_BRIGHT["glow_intensity"], ATMO_DARK["glow_intensity"], t)
	_env.glow_bloom = lerpf(
		ATMO_BRIGHT["glow_bloom"], ATMO_DARK["glow_bloom"], t)

	# 色彩调整 (叠加雷暴偏移)
	_env.adjustment_brightness = lerpf(
		ATMO_BRIGHT["adj_brightness"], ATMO_DARK["adj_brightness"], t) \
		+ ATMO_STORMY_OFFSET["adj_brightness"] * stormy_t
	_env.adjustment_contrast = lerpf(
		ATMO_BRIGHT["adj_contrast"], ATMO_DARK["adj_contrast"], t) \
		+ ATMO_STORMY_OFFSET["adj_contrast"] * stormy_t
	_env.adjustment_saturation = lerpf(
		ATMO_BRIGHT["adj_saturation"], ATMO_DARK["adj_saturation"], t) \
		+ ATMO_STORMY_OFFSET["adj_saturation"] * stormy_t

	# 雾效 (超过阈值才启用, 避免低值时多余开销)
	var fog_t: float = clampf((t - 0.3) / 0.7, 0.0, 1.0)  # 30% 后才开始出雾
	_env.fog_enabled = fog_t > 0.01
	if _env.fog_enabled:
		_env.fog_density = lerpf(0.0, ATMO_DARK["fog_density"], fog_t)
		_env.fog_light_color = ATMO_BRIGHT["fog_color"].lerp(
			ATMO_DARK["fog_color"], fog_t)

	# 桌面已移除，无需更新颜色

	# 物语背景层明暗同步
	if _monogatari_bg:
		_monogatari_bg.set_dark_transition(t)

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
	# 背景图最先淡入，略早于遮罩
	if _dialogue_system._bg_tex != null:
		tw.tween_property(_dialogue_system, "bg_image_alpha", 1.0, 0.45)
	tw.tween_property(_dialogue_system, "overlay_alpha", 1.0, 0.3).set_delay(0.1)
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
	# 退出时立即重置入场标志:
	# on_exit_complete() 可能在 Tween 回调（_process 之前）中同步触发下一段对话，
	# 导致下一段对话 state 已变为 "entering" 但 _dlg_enter_tweened 仍为 true，
	# 使入场 Tween 永远不触发，对话卡死，发牌链断裂。
	_dlg_enter_tweened = false
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_dialogue_system, "overlay_alpha", 0.0, 0.25)
	tw.tween_property(_dialogue_system, "box_offset_y", 60.0, 0.3) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_dialogue_system, "box_alpha", 0.0, 0.25)
	tw.tween_property(_dialogue_system, "portrait_alpha", 0.0, 0.25)
	tw.tween_property(_dialogue_system, "portrait_offset_y", 20.0, 0.25)
	# 背景图与对话框一起淡出
	tw.tween_property(_dialogue_system, "bg_image_alpha", 0.0, 0.3)
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

	# --- NPC 气泡 ---
	# 1. 同步: 与当前存活的 npc_manager.npcs 对齐（懒创建/懒删除）
	if game_flow and game_flow.npc_manager:
		var live_ids: Array = game_flow.npc_manager.npcs.keys()
		# 新增
		for npc_id in live_ids:
			if not _npc_bubbles.has(npc_id):
				_npc_bubbles[npc_id] = BubbleDialogue.create_for_npc(npc_id)
				_npc_bubble_show_tweened[npc_id] = false
				_npc_bubble_hide_tweened[npc_id] = false
		# 移除已消失的 NPC
		for npc_id in _npc_bubbles.keys():
			if not live_ids.has(npc_id):
				_npc_bubbles.erase(npc_id)
				_npc_bubble_show_tweened.erase(npc_id)
				_npc_bubble_hide_tweened.erase(npc_id)

	# 2. 更新每个 NPC 气泡的状态机 + tween
	for npc_id in _npc_bubbles:
		var bd: BubbleDialogue = _npc_bubbles[npc_id]
		bd.update_npc(dt)

		match bd.state:
			"showing":
				if not _npc_bubble_show_tweened.get(npc_id, false):
					_npc_bubble_show_tweened[npc_id] = true
					_npc_bubble_hide_tweened[npc_id] = false
					var tw: Tween = create_tween().set_parallel(true)
					tw.tween_property(bd, "bubble_alpha", 1.0, 0.2)
					tw.tween_property(bd, "bubble_scale", 1.0, 0.25) \
						.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
					tw.tween_property(bd, "offset_y", 0.0, 0.2)
					var tw_cb: Tween = create_tween()
					tw_cb.tween_callback(bd.on_show_complete).set_delay(0.3)
			"hiding":
				if not _npc_bubble_hide_tweened.get(npc_id, false):
					_npc_bubble_hide_tweened[npc_id] = true
					var tw: Tween = create_tween().set_parallel(true)
					tw.tween_property(bd, "bubble_alpha", 0.0, 0.15)
					tw.tween_property(bd, "bubble_scale", 0.5, 0.15)
					var tw_cb: Tween = create_tween()
					tw_cb.tween_callback(bd.on_hide_complete).set_delay(0.2)
			"hidden":
				_npc_bubble_show_tweened[npc_id] = false
				_npc_bubble_hide_tweened[npc_id] = false
