## BoardVisual - 棋盘渲染层 (3D 版)
## 负责: 3D 卡牌节点管理、视觉更新、发牌/翻牌动画、
##       Token 渲染、棋盘叠层效果
## 作为 Node3D 子节点挂在 Main 下方
extends Node3D

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
## 牌堆起飞位置 (3D 世界坐标)
const DECK_SPAWN_POS: Vector3 = Vector3(3.0, 1.0, -2.5)
## 翻牌动画时长 (单边)
const FLIP_HALF_DUR: float = 0.12
## 卡牌悬浮高度 (Y 轴微偏, 避免 Z-fighting)
const CARD_Y: float = 0.008
## PNG底图 / overlay Sprite3D 的 Y 高度 (卡面正上方 ~3mm)
const SPRITE_Y: float = CARD_Y + Card.CARD_THICKNESS / 2.0 + 0.003
## overlay 纹理 pixel_size = CARD_W / TEX_W (256×360 程序化纹理)
const OVERLAY_PIXEL_SIZE: float = Card.CARD_W / 256.0
## PNG 底图纹理高度 (515×768 资源图)
const PNG_TEX_HEIGHT: int = 768

# ---------------------------------------------------------------------------
# 引用 (由 main.gd 注入)
# ---------------------------------------------------------------------------
var m = null  # 主场景引用 (untyped 避免循环依赖)

# ---------------------------------------------------------------------------
# 缓存
# ---------------------------------------------------------------------------
## 卡牌节点容器
var board_layer: Node3D = null
## 卡牌材质缓存 (每张卡牌独立材质实例)
var _card_materials: Dictionary = {}  # "row_col" -> StandardMaterial3D
## 卡牌纹理生成器 (PNG加载 + 程序化overlay/back纹理)
var _card_textures: CardTextures = null
## 共享卡牌 Mesh
var _card_mesh: BoxMesh = null
## 光环 Shader (方形发光边框上浮特效)
var _glow_border_shader: Shader = null
## 光环共享 QuadMesh (比卡牌外扩一圈, 水平放置; 卡牌本体遮住中心, 只露出外圈)
var _glow_quad_mesh: QuadMesh = null
## 光环外扩边距 (卡牌四边各向外扩出的距离, 单位: 米)
const GLOW_MARGIN: float = 0.055
## 光环层数
const GLOW_RING_COUNT: int = 3
## 光环动画参数 — home / 辐射区 (柔和)
const GLOW_CYCLE: float = 3.5        # 循环周期 (秒)
const GLOW_Y_BASE: float = Card.CARD_THICKNESS / 2.0 + 0.001  # 紧贴卡面顶部, 卡体遮住中心
## 光环动画参数 — landmark (更华丽)
const GLOW_LM_CYCLE: float = 2.5     # 更快的周期
const GLOW_LM_RING_COUNT: int = 4    # 多一层

## 侦察/揭示图标常量
const ICON_QUAD: float = 0.18        # 图标边长 (米)
const ICON_Y: float = 0.15           # 图标浮在卡面上方的高度
## 预加载图标纹理
var _tex_scouted: Texture2D = null
var _tex_revealed: Texture2D = null

## 暗面幽灵 Sprite3D 节点缓存: ghost_index(int) → Dictionary
var _ghost_nodes: Dictionary = {}
## 暗面 NPC Sprite3D 节点缓存: npc_index(int) → Dictionary
var _npc_nodes: Dictionary = {}

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func setup(main_ref) -> void:
	m = main_ref
	board_layer = m._board_layer

	# 创建共享 BoxMesh
	_card_mesh = BoxMesh.new()
	_card_mesh.size = Vector3(Card.CARD_W, Card.CARD_THICKNESS, Card.CARD_H)

	# 光环 Shader & 共享 Mesh
	_glow_border_shader = load("res://shaders/glow_border.gdshader")
	_glow_quad_mesh = QuadMesh.new()
	_glow_quad_mesh.size = Vector2(Card.CARD_W + GLOW_MARGIN * 2.0, Card.CARD_H + GLOW_MARGIN * 2.0)
	_glow_quad_mesh.orientation = PlaneMesh.FACE_Y  # 水平放置, 面朝 +Y

	# 侦察/揭示图标纹理 (预加载)
	_tex_scouted = preload("res://assets/image/icon_scouted_v2_20260426051601.png")
	_tex_revealed = preload("res://assets/image/icon_revealed_v2_20260426051619.png")

	# 卡牌纹理生成器
	_card_textures = CardTextures.new()

# ---------------------------------------------------------------------------
# 卡牌节点创建 (全量重建)
# ---------------------------------------------------------------------------

## 清空并重新创建所有 3D 卡牌
func rebuild_card_nodes() -> void:
	# 必须立即删除，不能用 queue_free()，否则同名新节点会被旧节点遮蔽
	var children: Array = board_layer.get_children()
	for child in children:
		board_layer.remove_child(child)
		child.free()
	_card_materials.clear()

	for r in range(Board.ROWS):
		for c in range(Board.COLS):
			var row: int = r + 1
			var col: int = c + 1
			var card: Card = m.board.get_card(row, col)
			if card == null:
				continue

			var target_pos: Vector3 = m.board.grid_to_world(row, col)
			target_pos.y = CARD_Y

			var card_node: MeshInstance3D = MeshInstance3D.new()
			card_node.name = "Card_%d_%d" % [row, col]
			card_node.mesh = _card_mesh

			# 独立材质实例 (白色底色，PNG 纹理叠在独立 Sprite3D 上)
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = Color.WHITE
			mat.roughness = 0.7
			mat.metallic = 0.0
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # 支持淡入淡出
			card_node.material_override = mat
			_card_materials["%d_%d" % [row, col]] = mat

			card_node.position = target_pos
			card_node.set_meta("row", row)
			card_node.set_meta("col", col)
			card_node.set_meta("target_pos", target_pos)

			# PNG 底图 Sprite3D (平铺在卡面正上方)
			# pixel_size 由 _set_png_texture() 按纹理实际高度计算，此处给默认值
			var png_sprite: Sprite3D = Sprite3D.new()
			png_sprite.name = "PngSprite"
			png_sprite.pixel_size = Card.CARD_H / float(PNG_TEX_HEIGHT)
			png_sprite.position = Vector3(0, SPRITE_Y, 0)
			png_sprite.rotation_degrees = Vector3(-90, 180, 0)
			png_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			png_sprite.transparent = true
			png_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			png_sprite.no_depth_test = false
			card_node.add_child(png_sprite)

			# overlay Sprite3D (拍立得边框 + 色条，透明底)
			var overlay_sprite: Sprite3D = Sprite3D.new()
			overlay_sprite.name = "OverlaySprite"
			overlay_sprite.pixel_size = OVERLAY_PIXEL_SIZE
			overlay_sprite.position = Vector3(0, SPRITE_Y + 0.001, 0)
			overlay_sprite.rotation_degrees = Vector3(-90, 180, 0)
			overlay_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			overlay_sprite.transparent = true
			overlay_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			overlay_sprite.no_depth_test = false
			card_node.add_child(overlay_sprite)

			# 地标卡初始就正面朝上: 设置正面纹理
			if card.is_flipped:
				var type_info: Dictionary = GameTheme.card_type_info(card.type)
				var accent: Color = type_info.get("color", GameTheme.card_face)
				var png_tex: Texture2D = _card_textures.get_event_texture(card.location, card.type)
				if png_tex == null:
					png_tex = _card_textures.get_location_texture(card.location)
				_set_png_texture(png_sprite, png_tex)
				overlay_sprite.texture = _card_textures.get_overlay(accent)
			else:
				# 未翻开: 地点插画 + 米白色 overlay 边框
				_set_png_texture(png_sprite, _card_textures.get_location_texture(card.location))
				overlay_sprite.texture = _card_textures.get_plain_overlay()

			# 占位 Label3D (显示卡牌类型文字)
			var label: Label3D = Label3D.new()
			label.name = "TypeLabel"
			if card.is_flipped:
				# 已翻开 (地标): 显示事件信息 (单行)
				var type_info2: Dictionary = GameTheme.card_type_info(card.type)
				label.text = type_info2.get("label", "")
				label.modulate = Color(0.28, 0.28, 0.30, 0.90)
			else:
				# 未翻开: 显示地点信息 (单行)
				var loc_info: Dictionary = card.get_location_info()
				label.text = loc_info.get("label", "")
				label.modulate = Color(0.28, 0.28, 0.30, 0.90)
			label.font_size = 34
			label.pixel_size = 0.002
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			# 放在 overlay 底部白条中心：Z≈-0.37 (贴图底部在世界 -Z 方向)
			# Sprite3D rotation(-90,180,0): 贴图顶部→+Z, 底部→-Z
			# strip 中心 = -(328/360 - 0.5) × CARD_H ≈ -0.37m
			# Y 比 SPRITE_Y 高一点保证在 sprite 层上方渲染
			label.position = Vector3(0, SPRITE_Y + 0.002, -0.37)
			label.rotation_degrees = Vector3(-90, 180, 0)  # 朝上平铺, 补偿相机 180° yaw
			label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			label.no_depth_test = false
			label.render_priority = 0
			card_node.add_child(label)

			# 侦察/揭示图标 Sprite3D (右上角, 平铺在卡面上方)
			var half_w: float = Card.CARD_W / 2.0
			var half_h: float = Card.CARD_H / 2.0
			var icon_margin: float = ICON_QUAD * 0.55
			var icon_x: float = half_w - icon_margin               # 右侧
			var icon_z1: float = -(half_h - icon_margin)            # 卡面顶部 (-Z = 视觉上方)
			var icon_z2: float = -(half_h - icon_margin - ICON_QUAD * 1.15)  # 第二个稍下

			if _tex_scouted:
				var ico_s: Sprite3D = Sprite3D.new()
				ico_s.name = "IcoScouted"
				ico_s.texture = _tex_scouted
				ico_s.pixel_size = ICON_QUAD / float(_tex_scouted.get_width())
				ico_s.position = Vector3(icon_x, ICON_Y, icon_z1)
				ico_s.rotation_degrees = Vector3(-90, 0, 0)  # 朝上平铺
				ico_s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
				ico_s.no_depth_test = false
				ico_s.render_priority = 0
				ico_s.visible = card.scouted
				card_node.add_child(ico_s)

			if _tex_revealed:
				var ico_r: Sprite3D = Sprite3D.new()
				ico_r.name = "IcoRevealed"
				ico_r.texture = _tex_revealed
				ico_r.pixel_size = ICON_QUAD / float(_tex_revealed.get_width())
				ico_r.position = Vector3(icon_x, ICON_Y, icon_z2)
				ico_r.rotation_degrees = Vector3(-90, 0, 0)
				ico_r.billboard = BaseMaterial3D.BILLBOARD_DISABLED
				ico_r.no_depth_test = false
				ico_r.render_priority = 0
				ico_r.visible = card.revealed
				card_node.add_child(ico_r)

			# 家/地标: 创建时就挂载光环 (匹配 Lua Card.createNode 行为)
			if card.should_have_glow():
				_attach_glow_rings(card_node, card.type)

			board_layer.add_child(card_node)

# ---------------------------------------------------------------------------
# 卡牌节点查询
# ---------------------------------------------------------------------------

func get_card_node(row: int, col: int) -> MeshInstance3D:
	if board_layer == null:
		return null
	var card_name: String = "Card_%d_%d" % [row, col]
	return board_layer.get_node_or_null(card_name) as MeshInstance3D

## 设置卡牌节点整体透明度
## MeshInstance3D 没有 modulate 属性，需要分别处理各类子节点
func _set_card_alpha(card_node: MeshInstance3D, a: float) -> void:
	if card_node == null:
		return
	# 卡牌底板 mesh 材质
	var mat := card_node.material_override as StandardMaterial3D
	if mat:
		var c := mat.albedo_color
		c.a = a
		mat.albedo_color = c
	# 子节点：Sprite3D / Label3D 都有 modulate
	for child in card_node.get_children():
		if child is Sprite3D or child is Label3D:
			child.modulate.a = a
		elif child is Node3D:
			# 递归处理更深层子节点（图标等）
			for grandchild in child.get_children():
				if grandchild is Sprite3D or grandchild is Label3D:
					grandchild.modulate.a = a

## 获取卡牌 3D 世界位置
func get_card_world_pos(row: int, col: int) -> Vector3:
	var card_node: MeshInstance3D = get_card_node(row, col)
	if card_node:
		return card_node.global_position
	return Vector3.ZERO

## 获取卡牌屏幕坐标 (兼容接口: 投影 3D → 2D)
func get_card_center(row: int, col: int) -> Vector2:
	var world_pos: Vector3 = get_card_world_pos(row, col)
	if m._camera_3d and m._camera_3d.current:
		return m._camera_3d.unproject_position(world_pos)
	# 3D 相机未激活时, 用 board.grid_to_world 估算屏幕坐标 (过渡方案)
	var vp_size: Vector2 = m.get_viewport_rect().size
	var grid_pos: Vector3 = m.board.grid_to_world(row, col)
	# 将 3D 世界坐标映射到屏幕中心区域 (简易线性映射)
	var total_w: float = Board.COLS * (Card.CARD_W + Board.GAP) - Board.GAP
	var total_h: float = Board.ROWS * (Card.CARD_H + Board.GAP) - Board.GAP
	var norm_x: float = (grid_pos.x + total_w * 0.5) / total_w
	var norm_z: float = (grid_pos.z + total_h * 0.5) / total_h
	return Vector2(
		vp_size.x * (0.15 + norm_x * 0.7),
		vp_size.y * (0.15 + norm_z * 0.7)
	)

# ---------------------------------------------------------------------------
# 卡牌视觉更新
# ---------------------------------------------------------------------------

## 设置 PNG 底图纹理并按实际高度计算 pixel_size，防止尺寸溢出卡面
## 程序化 overlay 纹理 (360px 高) → CARD_H/360 = OVERLAY_PIXEL_SIZE (保持一致)
## 资源 PNG 纹理 (768px 高) → CARD_H/768 ≈ 0.00117 (正好铺满卡面高度)
func _set_png_texture(sprite: Sprite3D, tex: Texture2D) -> void:
	sprite.texture = tex
	if tex == null:
		return
	var th: int = tex.get_height()
	if th > 0:
		sprite.pixel_size = Card.CARD_H / float(th)

func _get_card_mat(row: int, col: int) -> StandardMaterial3D:
	var key: String = "%d_%d" % [row, col]
	return _card_materials.get(key) as StandardMaterial3D

func update_card_visual(row: int, col: int) -> void:
	var mat: StandardMaterial3D = _get_card_mat(row, col)
	if not mat:
		return

	var card: Card = m.board.get_card(row, col)
	if card == null:
		return

	var card_node: MeshInstance3D = get_card_node(row, col)

	var png_sprite: Sprite3D = card_node.get_node_or_null("PngSprite") as Sprite3D if card_node else null
	var overlay_sprite: Sprite3D = card_node.get_node_or_null("OverlaySprite") as Sprite3D if card_node else null

	if card.is_flipped:
		var type_info: Dictionary = GameTheme.card_type_info(card.type)
		var accent: Color = type_info.get("color", GameTheme.card_face)
		# mat 保留为白色底，用 emission 做高亮效果 (动画时用)
		mat.albedo_color = Color.WHITE
		# 更新 PNG + overlay 纹理
		if png_sprite:
			var png_tex: Texture2D = _card_textures.get_event_texture(card.location, card.type)
			if png_tex == null:
				png_tex = _card_textures.get_location_texture(card.location)
			_set_png_texture(png_sprite, png_tex)
		if overlay_sprite:
			overlay_sprite.texture = _card_textures.get_overlay(accent)
		# 翻开后显示事件信息
		if card_node:
			var label: Label3D = card_node.get_node_or_null("TypeLabel") as Label3D
			if label:
				label.text = type_info.get("label", "")
				label.modulate = Color(0.28, 0.28, 0.30, 0.90)
			# 地标 / 家: 挂载光环 (尊重 safe_glow_active 开关)
			if card.type == "landmark" or card.type == "home":
				_attach_glow_rings(card_node, card.type)
				_set_glow_visible(card_node, card.safe_glow_active)
			elif card.safe_glow_active:
				# 地标辐射区: 确保挂载光环并显示
				_attach_glow_rings(card_node, "home")
				_set_glow_visible(card_node, true)
			else:
				_remove_glow_rings(card_node)
	else:
		mat.albedo_color = Color.WHITE
		# 未翻开: 地点插画 + 米白 overlay
		if png_sprite:
			_set_png_texture(png_sprite, _card_textures.get_location_texture(card.location))
		if overlay_sprite:
			overlay_sprite.texture = _card_textures.get_plain_overlay()
		# 未翻开时显示地点信息
		if card_node:
			var label: Label3D = card_node.get_node_or_null("TypeLabel") as Label3D
			if label:
				var loc_info: Dictionary = card.get_location_info()
				label.text = loc_info.get("label", "")
				label.modulate = Color(0.28, 0.28, 0.30, 0.90)
			# 家/地标/辐射区即使未翻开也保留光环 (匹配 Lua Card.createNode)
			if not card.should_have_glow() and not card.safe_glow_active:
				_remove_glow_rings(card_node)

	# 侦察/揭示图标: 只要卡牌可见就显示 (不论正反面)
	if card_node:
		var ico_s: Sprite3D = card_node.get_node_or_null("IcoScouted") as Sprite3D
		if ico_s:
			ico_s.visible = card.scouted
		var ico_r: Sprite3D = card_node.get_node_or_null("IcoRevealed") as Sprite3D
		if ico_r:
			ico_r.visible = card.revealed

## 应用所有卡牌的悬停缩放 (hover_t → scale 1.0+0.08)
## 仅在非动画状态调用; dealing/flipping 等由 Tween 控制 scale
func apply_hover_scales() -> void:
	var state: String = GameData.demo_state
	# 动画状态下不干预卡牌 scale (Tween 正在控制)
	if state == "dealing" or state == "transition" or state == "flipping" \
			or state == "exorcising":
		return
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = m.board.get_card(r, c)
			if card == null:
				continue
			var card_node: MeshInstance3D = get_card_node(r, c)
			if card_node == null:
				continue
			var hover_scale: float = 1.0 + card.hover_t * 0.08
			# 仅修改 X 和 Z (保持 Y=1, 卡牌厚度不变)
			card_node.scale = Vector3(hover_scale, 1.0, hover_scale)

## 暗面世界卡牌视觉 (墙壁=null → 隐藏节点)
func update_dark_card_visual(row: int, col: int) -> void:
	var card_node: MeshInstance3D = get_card_node(row, col)
	if not card_node:
		return

	var card: Card = m.board.get_card(row, col)
	if card == null:
		card_node.visible = false
		return

	card_node.visible = true
	var mat: StandardMaterial3D = _get_card_mat(row, col)
	if not mat:
		return

	var png_sprite_d: Sprite3D = card_node.get_node_or_null("PngSprite") as Sprite3D
	var overlay_sprite_d: Sprite3D = card_node.get_node_or_null("OverlaySprite") as Sprite3D

	if card.is_flipped:
		# 暗面正面: evt_icon PNG（按事件类型）+ 标签，fallback 程序化纹理
		mat.albedo_color = Color.WHITE
		if png_sprite_d:
			var icon_tex: Texture2D = CardImageMap.get_dark_icon_texture(card.dark_type)
			if icon_tex:
				_set_png_texture(png_sprite_d, icon_tex)
			else:
				_set_png_texture(png_sprite_d, _card_textures.get_dark_face_texture(card.dark_type))
		if overlay_sprite_d:
			overlay_sprite_d.texture = null
		var label: Label3D = card_node.get_node_or_null("TypeLabel") as Label3D
		if label:
			var dark_info: Dictionary = GameTheme.dark_card_type_info(card.dark_type)
			# 优先使用 dark_name (具体地点名), fallback 到类型通用 label
			var display_name: String = card.dark_name if card.dark_name != "" else dark_info.get("label", "")
			label.text = display_name
			label.modulate = Color(0.78, 0.74, 0.88, 0.90)  # 暗面用浅紫色文字
	else:
		# 暗面背面: 程序化暗面背面纹理
		mat.albedo_color = Color.WHITE
		if png_sprite_d:
			_set_png_texture(png_sprite_d, _card_textures.get_back_dark_texture())
		if overlay_sprite_d:
			overlay_sprite_d.texture = null
		var label: Label3D = card_node.get_node_or_null("TypeLabel") as Label3D
		if label:
			label.modulate = Color(1, 1, 1, 0)

	# 暗面世界隐藏侦察/揭示图标 (表面世界概念)
	var ico_s: Sprite3D = card_node.get_node_or_null("IcoScouted") as Sprite3D
	if ico_s:
		ico_s.visible = false
	var ico_r: Sprite3D = card_node.get_node_or_null("IcoRevealed") as Sprite3D
	if ico_r:
		ico_r.visible = false

# ---------------------------------------------------------------------------
# Token 精灵更新 (Sprite3D billboard)
# ---------------------------------------------------------------------------

## ---- Billboard 尺寸修正 ----
## Urho3D BillboardSet.size 是 **半尺寸(half-extents)**:
##   顶点从 -size 到 +size, 实际渲染四边形 = 2×size
## Godot Sprite3D.pixel_size 是 **全尺寸(full-extents)**:
##   四边形 = texture_pixels × pixel_size
## 因此 Godot 的 pixel_size 需要 ×2 才能匹配 UrhoX 的视觉尺寸。
const BILLBOARD_HALF_EXTENT_FACTOR: float = 2.0

## Token pixel_size: Lua bb.size=(0.335, 0.50) → 实际渲染 0.67×1.00m
## Godot: 768px × pixel_size 需等于 1.00m → pixel_size = 1.00/768 ≈ 0.0013
const TOKEN_PIXEL_SIZE: float = 0.00065 * BILLBOARD_HALF_EXTENT_FACTOR
## 死亡横版 pixel_size: Lua DEAD_3D_H=0.38 (half) → 实际 0.76m → 0.76/515 ≈ 0.001476
const TOKEN_DEAD_PIXEL_SIZE: float = 0.000738 * BILLBOARD_HALF_EXTENT_FACTOR

## Token 世界坐标 Y (Sprite3D 中心, centered=true)
## Lua: node.Y=0.25, bb.offset.y=0.25, half-height=0.50
##   → billboard 中心 Y=0.50, 底部 Y=0.00, 顶部 Y=1.00
## Godot ×2 后: 全高=1.00, 中心需在 Y=0.50 → 底部 Y=0.00 ✓
const TOKEN_CENTER_Y: float = 0.50
## 像素→世界单位换算 (用于呼吸/弹跳动画位移)
## 注意: 此处 **不** 乘 BILLBOARD_HALF_EXTENT_FACTOR。
## breathe/bounce 是节点世界坐标偏移 (米), 与 billboard 的半尺寸特性无关。
## token.gd 中的像素值 (如 12.3px) 是按 0.00065 换算的: 0.008m / 0.00065 ≈ 12.3px
const TOKEN_PX_TO_WORLD: float = 0.00065

## Token blob shadow 常量
## Lua: SPRITE_3D_W=0.335 (half) → 实际宽 0.67m
## shadow_w = 实际宽 × 1.1, shadow_z = 实际宽 × 0.5
const TOKEN_WORLD_W: float = 515.0 * TOKEN_PIXEL_SIZE   # ≈ 0.67m (实际渲染宽度)
const TOKEN_SHADOW_W: float = TOKEN_WORLD_W * 1.1        # ≈ 0.737
const TOKEN_SHADOW_Z: float = TOKEN_WORLD_W * 0.5        # ≈ 0.335
const TOKEN_SHADOW_Y: float = 0.02            # 略高于卡面 (Lua=0.015, 抬高避免Z-fighting)

func update_token_visual() -> void:
	var token: Token = m.token
	if not token.visible:
		m._token_sprite.visible = false
		if m._token_shadow:
			m._token_shadow.visible = false
		return

	m._token_sprite.visible = true
	var tex: Texture2D = token.get_current_texture()
	if tex:
		m._token_sprite.texture = tex

	# 死亡横版: 调整 pixel_size 匹配 Lua DEAD_3D_H=0.38 (正常 SPRITE_3D_H=0.50)
	var is_dead: bool = (token.emotion == "dead")
	m._token_sprite.pixel_size = TOKEN_DEAD_PIXEL_SIZE if is_dead else TOKEN_PIXEL_SIZE

	# 移动动画期间，位置和缩放由 Tween 驱动，这里只更新纹理/可见性
	if token.is_moving:
		m._token_sprite.modulate.a = token.alpha
		# 阴影跟随 Tween 位置 (XZ 跟随 sprite, Y 固定在地面)
		if m._token_shadow:
			m._token_shadow.visible = true
			m._token_shadow.position = Vector3(
				m._token_sprite.position.x, TOKEN_SHADOW_Y,
				m._token_sprite.position.z)
		return

	# 3D 世界坐标定位 (Token 中心 Y 直接使用绝对值, 与 Lua 一致)
	var world_pos: Vector3 = get_card_world_pos(token.target_row, token.target_col)
	world_pos.y = TOKEN_CENTER_Y

	# 同格 NPC: Token 向左偏移 (与 Lua SHARE_OFFSET=0.18 保持对称)
	# Lua: NPC wx + 0.18, Token wx - 0.18
	var npc_mgr: NPCManager = m.game_flow.npc_manager if m.game_flow else null
	if npc_mgr:
		var share_px: float = npc_mgr.get_share_offset(token.target_row, token.target_col)
		if share_px != 0.0:
			world_pos.x -= 0.18  # Lua SHARE_OFFSET=0.18, 与 NPC_OFFSET_X 对称

	# 呼吸动画 (转换像素偏移为世界单位)
	var breathe: Dictionary = token.get_breathe_offset(m.game_time)
	world_pos.y += breathe["y"] * TOKEN_PX_TO_WORLD
	world_pos.y += token.bounce_y * TOKEN_PX_TO_WORLD

	m._token_sprite.position = world_pos
	m._token_sprite.modulate.a = token.alpha

	# 呼吸缩放 + squash/stretch
	var bs: float = breathe["scale"]
	m._token_sprite.scale = Vector3(token.squash_x * bs, token.squash_y * bs, 1.0)

	# Blob shadow: 固定在地面, 跳起时变淡变小
	if m._token_shadow:
		m._token_shadow.visible = true
		m._token_shadow.position = Vector3(world_pos.x, TOKEN_SHADOW_Y, world_pos.z)
		var bounce_world: float = abs(token.bounce_y * TOKEN_PX_TO_WORLD)
		var shadow_scale: float = maxf(0.6, 1.0 - bounce_world * 1.5)  # Lua: 1.0 - bounceY * 1.5
		var shadow_alpha: float = maxf(0.1, 0.3 - bounce_world * 0.8)  # Lua: 0.3 - bounceY * 0.8
		m._token_shadow.scale = Vector3(
			TOKEN_SHADOW_W * shadow_scale, 0.001,
			TOKEN_SHADOW_Z * shadow_scale)
		var shadow_mat: StandardMaterial3D = m._token_shadow.material_override as StandardMaterial3D
		if shadow_mat:
			shadow_mat.albedo_color.a = shadow_alpha

# ---------------------------------------------------------------------------
# 发牌动画
# ---------------------------------------------------------------------------

## 启动螺旋发牌, 完成后调用 on_complete
func start_deal_animation(on_complete: Callable) -> void:
	var order: Array = m.board.get_spiral_order()
	var total_cards: int = order.size()

	var acc_delay: float = 0.3
	var last_arrival: float = acc_delay

	for i in range(total_cards):
		var pos: Vector2i = order[i]
		var card_node: MeshInstance3D = get_card_node(pos.x, pos.y)
		if card_node == null:
			continue

		var target_pos: Vector3 = card_node.get_meta("target_pos")

		# 起始: 牌堆位置, 不可见
		card_node.position = DECK_SPAWN_POS
		card_node.scale = Vector3(0.4, 0.4, 0.4)
		card_node.visible = true

		# 设置初始透明度
		_set_card_alpha(card_node, 0.0)

		var fly_dur: float = 0.35

		# 淡入
		var tw_fade: Tween = m.create_tween()
		tw_fade.tween_method(
			func(a: float): _set_card_alpha(card_node, a),
			0.0, 1.0, 0.15
		).set_delay(acc_delay)

		# 飞行
		var tw2: Tween = m.create_tween()
		tw2.tween_property(card_node, "position", target_pos, fly_dur) \
			.set_delay(acc_delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

		# 缩放
		var tw3: Tween = m.create_tween()
		tw3.tween_property(card_node, "scale", Vector3.ONE, fly_dur) \
			.set_delay(acc_delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

		# 弹跳 (Y 轴弹起)
		var bounce_delay: float = acc_delay + fly_dur * 0.6
		var tw4: Tween = m.create_tween()
		var bounce_pos: Vector3 = Vector3(target_pos.x, target_pos.y + 0.08, target_pos.z)
		tw4.tween_property(card_node, "position", bounce_pos, 0.1) \
			.set_delay(bounce_delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw4.tween_property(card_node, "position", target_pos, 0.1) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

		last_arrival = acc_delay + fly_dur

		var progress: float = float(i) / float(total_cards)
		var interval: float = 0.09 - 0.06 * progress
		acc_delay += interval

	# 完成回调
	var finish_delay: float = last_arrival + 0.4
	var tw_finish: Tween = m.create_tween()
	tw_finish.tween_callback(on_complete).set_delay(finish_delay)

# ---------------------------------------------------------------------------
# 收牌动画 (日终收回牌堆, 匹配原版 Card.undeal)
# ---------------------------------------------------------------------------

## 播放收牌动画: 反向螺旋顺序, 弹起→飞回牌堆+缩小+旋转+淡出
func play_undeal_animation(on_complete: Callable) -> void:
	var order: Array = m.board.get_spiral_order()
	order.reverse()  # 内→外, 反向收牌
	var total_cards: int = order.size()
	if total_cards == 0:
		on_complete.call()
		return

	var acc_delay: float = 0.05
	var last_end: float = acc_delay

	for i in range(total_cards):
		var pos: Vector2i = order[i]
		var card_node: MeshInstance3D = get_card_node(pos.x, pos.y)
		if card_node == null:
			continue

		var start_pos: Vector3 = card_node.position

		# 随机旋转方向 (±15~25°)
		var rot_sign: float = 1.0 if randi() % 2 == 0 else -1.0
		var rot_deg: float = rot_sign * randf_range(15.0, 25.0)

		# Phase A: 弹起 (0.10s)
		var bounce_pos: Vector3 = Vector3(start_pos.x, start_pos.y + 0.30, start_pos.z)
		var tw_bounce: Tween = m.create_tween()
		tw_bounce.tween_property(card_node, "position", bounce_pos, 0.10) \
			.set_delay(acc_delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

		# Phase B: 飞回牌堆 (0.30s, easeInBack)
		var fly_delay: float = acc_delay + 0.10
		var fly_dur: float = 0.30

		var tw_fly: Tween = m.create_tween()
		tw_fly.tween_property(card_node, "position", DECK_SPAWN_POS, fly_dur) \
			.set_delay(fly_delay) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)

		# 缩小到 20%
		var tw_shrink: Tween = m.create_tween()
		tw_shrink.tween_property(card_node, "scale",
			Vector3(0.2, 0.2, 0.2), fly_dur) \
			.set_delay(fly_delay) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

		# 旋转
		var tw_rot: Tween = m.create_tween()
		tw_rot.tween_property(card_node, "rotation_degrees:y", rot_deg, fly_dur) \
			.set_delay(fly_delay) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

		# 淡出
		var tw_fade: Tween = m.create_tween()
		tw_fade.tween_method(
			func(a: float): _set_card_alpha(card_node, a),
			1.0, 0.0, fly_dur
		).set_delay(fly_delay).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

		# 飞行结束后隐藏
		var tw_hide: Tween = m.create_tween()
		tw_hide.tween_callback(func():
			card_node.visible = false
		).set_delay(fly_delay + fly_dur)

		last_end = fly_delay + fly_dur

		# 间隔: 快速连续收牌
		var progress: float = float(i) / float(total_cards)
		var interval: float = 0.06 - 0.03 * progress
		acc_delay += interval

	# 完成回调
	var tw_done: Tween = m.create_tween()
	tw_done.tween_callback(on_complete).set_delay(last_end + 0.15)

# ---------------------------------------------------------------------------
# 翻牌动画 (绕 Z 轴掀起翻转, 同步原版 Card.flip)
# ---------------------------------------------------------------------------

## 翻牌安全高度: cardW/2 + 余量, 确保 90° 时底边不穿桌面
const FLIP_LIFT: float = Card.CARD_W / 2.0 + 0.04  # ~0.36m

## 播放翻牌动画, 完成后调用 on_complete
## 流程: 下压蓄力 → 弹起到安全高度 → 绕Z轴翻转到90° → 换面 → 翻回0° + 落下
func play_flip_animation(row: int, col: int, on_complete: Callable) -> void:
	var card_node: MeshInstance3D = get_card_node(row, col)
	if not card_node:
		on_complete.call()
		return

	var base_pos: Vector3 = card_node.position

	# --- 阶段 1: 下压蓄力 (0.05s) ---
	var tw1: Tween = m.create_tween()
	tw1.set_parallel(true)
	tw1.tween_property(card_node, "scale", Vector3(1.03, 1.0, 0.97), 0.05) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw1.tween_property(card_node, "position:y", base_pos.y - 0.01, 0.05) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	tw1.chain().tween_callback(func():
		# --- 阶段 2: 弹起 + 缩放恢复 (并行) ---
		var tw2: Tween = m.create_tween()
		tw2.tween_property(card_node, "position:y", base_pos.y + FLIP_LIFT, 0.12) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		var tw2s: Tween = m.create_tween()
		tw2s.tween_property(card_node, "scale", Vector3.ONE, 0.08) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

		# --- 阶段 3: 绕 Z 轴翻转 0→90° (稍延后, 与弹起重叠) ---
		var tw3: Tween = m.create_tween()
		tw3.tween_property(card_node, "rotation:z", deg_to_rad(90.0), 0.16) \
			.set_delay(0.04) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
		tw3.tween_callback(func():
			# 90° 时换面 (侧面不可见, 完美切换)
			update_card_visual(row, col)

			# --- 阶段 4: 翻回 0° + 落下 (同步) ---
			var tw4: Tween = m.create_tween()
			tw4.set_parallel(true)
			tw4.tween_property(card_node, "rotation:z", 0.0, 0.25) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw4.tween_property(card_node, "position:y", base_pos.y, 0.25) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw4.chain().tween_callback(on_complete)
		)
	)

## 卡牌 emission 蓄力发光 (渐亮到 peak, duration 秒)
func start_card_emission_glow(row: int, col: int, color: Color,
		duration: float = 0.6, peak: float = 2.0) -> void:
	var mat: StandardMaterial3D = _get_card_mat(row, col)
	if not mat:
		return
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.0
	var tw: Tween = m.create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", peak, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

## 播放驱魔变形动画 (匹配 Lua Card.transformTo: 抬升→70°翻转+震动→换面→落回+光晕)
func play_exorcise_animation(row: int, col: int, on_complete: Callable) -> void:
	var card_node: MeshInstance3D = get_card_node(row, col)
	if not card_node:
		on_complete.call()
		return

	var base_pos: Vector3 = card_node.position
	var base_x: float = base_pos.x

	# --- Phase 1: 抬升到安全高度 (0.12s) ---
	var tw_lift: Tween = m.create_tween()
	tw_lift.tween_property(card_node, "position:y",
		base_pos.y + FLIP_LIFT, 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# --- Phase 2: 翻转到 70° + 震动 (0.25s, 延迟 0.04s) ---
	var tw_rot: Tween = m.create_tween()
	tw_rot.tween_property(card_node, "rotation:z",
		deg_to_rad(70.0), 0.25) \
		.set_delay(0.04) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# 震动 (10Hz, 与翻转并行)
	var tw_shake: Tween = m.create_tween()
	tw_shake.tween_method(func(t: float) -> void:
		var decay: float = 1.0 - t * 0.5
		var offset: float = sin(t * PI * 10.0) * 0.05 * decay
		card_node.position.x = base_x + offset
	, 0.0, 1.0, 0.25).set_delay(0.04)

	# --- Phase 3: 翻转到峰值时换面 + 落回 ---
	tw_rot.tween_callback(func() -> void:
		tw_shake.kill()  # 确保震动 tween 已停止
		card_node.position.x = base_x  # 重置震动偏移
		update_card_visual(row, col)

		# 落回: 翻转归零 + 高度归位 + scale 弹性 (0.35s)
		var tw_back: Tween = m.create_tween()
		tw_back.set_parallel(true)
		tw_back.tween_property(card_node, "rotation:z", 0.0, 0.35) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw_back.tween_property(card_node, "position:y", base_pos.y, 0.35) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw_back.tween_property(card_node, "scale", Vector3.ONE, 0.35) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw_back.chain().tween_callback(func() -> void:
			# 光晕脉冲 (翻牌闪光: glow_intensity 1→0, 0.8s)
			var card: Card = m.board.get_card(row, col)
			if card:
				card.glow_intensity = 1.0
			var mat: StandardMaterial3D = _get_card_mat(row, col)
			if mat:
				# 翻牌闪光颜色: 用卡牌类型 accent 色 (比白色更生动)
				var flipped_card: Card = m.board.get_card(row, col)
				var glow_color: Color = Color.WHITE
				if flipped_card and flipped_card.is_flipped:
					var ti: Dictionary = GameTheme.card_type_info(flipped_card.type)
					glow_color = ti.get("color", Color.WHITE)
				var tw_glow: Tween = m.create_tween()
				tw_glow.tween_method(func(t: float) -> void:
					if card:
						card.glow_intensity = 1.0 - t
					if mat:
						mat.emission_enabled = true
						mat.emission = glow_color
						mat.emission_energy_multiplier = (1.0 - t) * 2.0
				, 0.0, 1.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				tw_glow.tween_callback(func() -> void:
					if mat:
						mat.emission_enabled = false
					if card:
						card.glow_intensity = 0.0
				)
			on_complete.call()
		)
	)

## 正在 shake 的卡牌 key 集合 (防重入, 匹配 Lua: if card._shaking then return end)
var _shaking_keys: Dictionary = {}

## 播放无效操作震动动画 (0.35s, 6Hz 衰减正弦)
func play_shake_animation(row: int, col: int) -> void:
	var key: int = row * 100 + col
	if _shaking_keys.has(key):
		return
	var card_node: MeshInstance3D = get_card_node(row, col)
	if not card_node:
		return
	_shaking_keys[key] = true
	var base_x: float = card_node.position.x
	var tw: Tween = m.create_tween()
	tw.tween_method(func(t: float) -> void:
		var decay: float = (1.0 - t) * (1.0 - t)  # (1-t)² 衰减
		var offset: float = sin(t * PI * 6.0) * 0.04 * decay
		card_node.position.x = base_x + offset
	, 0.0, 1.0, 0.35).set_trans(Tween.TRANS_LINEAR)
	tw.tween_callback(func() -> void:
		card_node.position.x = base_x
		_shaking_keys.erase(key)
	)

## 播放翻回动画 (拍照侦察后, 同步原版 Card.flipBack)
func play_flip_back_animation(row: int, col: int) -> void:
	var card_node: MeshInstance3D = get_card_node(row, col)
	if not card_node:
		return
	var base_pos: Vector3 = card_node.position

	# 弹起
	var tw1: Tween = m.create_tween()
	tw1.tween_property(card_node, "position:y", base_pos.y + FLIP_LIFT * 0.8, 0.10) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# 翻转到 90° (稍延后)
	var tw2: Tween = m.create_tween()
	tw2.tween_property(card_node, "rotation:z", deg_to_rad(90.0), 0.14) \
		.set_delay(0.02) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw2.tween_callback(func():
		# 换面
		update_card_visual(row, col)
		# 翻回 + 落下
		var tw3: Tween = m.create_tween()
		tw3.set_parallel(true)
		tw3.tween_property(card_node, "rotation:z", 0.0, 0.22) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw3.tween_property(card_node, "position:y", base_pos.y, 0.22) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	)

# ---------------------------------------------------------------------------
# Token 移动动画
# ---------------------------------------------------------------------------

## Token 移动到目标格 (3D 世界坐标), 完成后调用 on_arrive
func animate_token_move(row: int, col: int, on_arrive: Callable) -> void:
	var token: Token = m.token
	var start_pos: Vector3 = m._token_sprite.position
	var end_pos: Vector3 = get_card_world_pos(row, col)
	var base_y: float = TOKEN_CENTER_Y
	end_pos.y = base_y

	# 距离计算 (XZ 平面)
	var dx: float = end_pos.x - start_pos.x
	var dz: float = end_pos.z - start_pos.z
	var dist: float = sqrt(dx * dx + dz * dz)

	# 动画参数 (匹配原版 Lua Token.moveTo)
	var move_dur: float = clampf(dist / 2.5, 0.25, 0.60)
	var jump_height: float = minf(0.20, dist * 0.15 + 0.08)

	token.is_moving = true

	# --- Phase 1: 预跳蓄力压扁 ---
	var t1: Tween = m.create_tween()
	t1.tween_property(m._token_sprite, "scale",
		Vector3(1.2, 0.8, 1.0), 0.08) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# --- Phase 2: 起跳拉伸 ---
	t1.tween_property(m._token_sprite, "scale",
		Vector3(0.85, 1.15, 1.0), 0.06) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# --- Phase 3: 空中移动 (多 Tween 并行) ---
	t1.tween_callback(func() -> void:
		# Tween A: XZ 水平移动
		var t_xz: Tween = m.create_tween()
		t_xz.tween_method(func(ratio: float) -> void:
			m._token_sprite.position.x = start_pos.x + dx * ratio
			m._token_sprite.position.z = start_pos.z + dz * ratio
		, 0.0, 1.0, move_dur) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

		# Tween B: Y 弧线 (上升 → 下降, 顺序)
		var up_dur: float = move_dur * 0.45
		var down_dur: float = move_dur * 0.55
		var t_y: Tween = m.create_tween()
		t_y.tween_method(func(ratio: float) -> void:
			m._token_sprite.position.y = base_y + jump_height * ratio
		, 0.0, 1.0, up_dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t_y.tween_method(func(ratio: float) -> void:
			m._token_sprite.position.y = base_y + jump_height * (1.0 - ratio)
		, 0.0, 1.0, down_dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)

		# Tween C: 空中姿态 → 落地压扁 → 弹性恢复
		var t_scale: Tween = m.create_tween()
		# 空中微拉伸
		t_scale.tween_property(m._token_sprite, "scale",
			Vector3(0.95, 1.05, 1.0), move_dur * 0.4) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		# 等到飞行结束
		t_scale.tween_interval(move_dur * 0.6)
		# 落地压扁
		t_scale.tween_property(m._token_sprite, "scale",
			Vector3(1.25, 0.75, 1.0), 0.06) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		# 弹性恢复
		t_scale.tween_property(m._token_sprite, "scale",
			Vector3(1.0, 1.0, 1.0), 0.20) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
		t_scale.tween_callback(func() -> void:
			token.is_moving = false
			token.squash_x = 1.0
			token.squash_y = 1.0
			m._token_sprite.position = end_pos
			on_arrive.call()
		)
	)

# ---------------------------------------------------------------------------
# 暗面幽灵 3D 节点 (Sprite3D billboard, 匹配 Lua DarkWorld.createGhostNodes)
# ---------------------------------------------------------------------------

## 幽灵渲染参数 (精确匹配 Lua DarkWorld, ×2 half-extent 修正)
## Lua: bb.size=0.30 (half) → 实际 0.60m
## Lua: nodeY=0.25, bb.offset.y=0.15, half-height=0.30 → 中心 Y=0.40, 底部 Y=0.10
## Godot ×2: 全高=0.60, 底部 Y=0.10 → 中心 Y=0.10+0.30=0.40 ✓
const GHOST_BASE_Y: float = 0.40
const GHOST_WORLD_SIZE: float = 0.30 * BILLBOARD_HALF_EXTENT_FACTOR
const GHOST_FLOAT_AMP: float = 0.04   # 浮动振幅
const GHOST_FLOAT_SPEED: float = 2.5  # 浮动频率

## 为当前暗面层创建幽灵 Sprite3D 节点
func create_ghost_nodes(ghosts: Array) -> void:
	destroy_ghost_nodes()
	for i in range(ghosts.size()):
		var ghost: DarkWorld.GhostData = ghosts[i]
		if not ghost.alive:
			continue

		var ghost_textures: Array = CardConfig.get_dw_ghost_textures()
		if ghost.tex_index < 0 or ghost.tex_index >= ghost_textures.size():
			continue
		var tex_path: String = ghost_textures[ghost.tex_index]
		var tex: Texture2D = load(tex_path)
		if not tex:
			continue

		var sprite: Sprite3D = Sprite3D.new()
		sprite.name = "Ghost_%d" % i
		sprite.texture = tex
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.transparent = true
		sprite.no_depth_test = false
		sprite.render_priority = 0
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		sprite.alpha_scissor_threshold = 0.5

		# pixel_size: 使纹理映射到 GHOST_WORLD_SIZE 米
		var tex_max: float = maxf(float(tex.get_width()), float(tex.get_height()))
		sprite.pixel_size = GHOST_WORLD_SIZE / tex_max if tex_max > 0.0 else 0.001

		# 世界坐标定位 (ghost.row/col 是 0-based)
		var world_pos: Vector3 = m.board.grid_to_world(ghost.row + 1, ghost.col + 1)
		world_pos.y = GHOST_BASE_Y
		sprite.position = world_pos

		# 挂在 board_visual 自身下 (与 board_layer 分离, 避免 rebuild_card_nodes 误删)
		add_child(sprite)

		_ghost_nodes[i] = {
			"node": sprite,
			"base_y": GHOST_BASE_Y,
			"float_phase": ghost.float_phase,
			"pos_x": world_pos.x,
			"pos_z": world_pos.z,
		}

## 销毁所有幽灵节点
func destroy_ghost_nodes() -> void:
	for key in _ghost_nodes:
		var data: Dictionary = _ghost_nodes[key]
		var node = data.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_ghost_nodes.clear()

## 每帧更新幽灵浮动动画 (sin 波上下飘动)
func update_ghost_visuals(game_time: float) -> void:
	for key in _ghost_nodes:
		var data: Dictionary = _ghost_nodes[key]
		var node = data.get("node")
		if not is_instance_valid(node):
			continue
		var float_y: float = sin(game_time * GHOST_FLOAT_SPEED + data["float_phase"]) * GHOST_FLOAT_AMP
		node.position = Vector3(data["pos_x"], data["base_y"] + float_y, data["pos_z"])

## 幽灵移动动画 (从当前视觉位置平滑移动到目标格)
## target_row/col: 0-based
func animate_ghost_move(ghost_index: int, target_row_0: int, target_col_0: int, duration: float) -> void:
	if not _ghost_nodes.has(ghost_index):
		return
	var data: Dictionary = _ghost_nodes[ghost_index]
	var node = data.get("node")
	if not is_instance_valid(node):
		return

	var target_world: Vector3 = m.board.grid_to_world(target_row_0 + 1, target_col_0 + 1)
	var start_x: float = data["pos_x"]
	var start_z: float = data["pos_z"]
	var end_x: float = target_world.x
	var end_z: float = target_world.z

	var tw: Tween = m.create_tween()
	tw.tween_method(func(t: float) -> void:
		data["pos_x"] = lerpf(start_x, end_x, t)
		data["pos_z"] = lerpf(start_z, end_z, t)
	, 0.0, 1.0, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)

## 幽灵消灭淡出动画 (0.5s alpha→0, 然后删除节点)
func animate_ghost_fade(ghost_index: int) -> void:
	if not _ghost_nodes.has(ghost_index):
		return
	var data: Dictionary = _ghost_nodes[ghost_index]
	var node = data.get("node")
	if not is_instance_valid(node):
		_ghost_nodes.erase(ghost_index)
		return

	var tw: Tween = m.create_tween()
	tw.tween_property(node, "modulate:a", 0.0, 0.5) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		if is_instance_valid(node):
			node.queue_free()
		_ghost_nodes.erase(ghost_index)
	)

## 暗面卡牌收集动画: 淡出 0.18s → 执行 callback → 淡入 0.22s
## 用于 clue/item 收集时的视觉反馈 (对齐 Lua collectCard 动画)
func animate_dark_card_collect(row: int, col: int, callback: Callable) -> void:
	var card_node: MeshInstance3D = get_card_node(row, col)
	if card_node == null:
		callback.call()
		return
	# 淡出
	var tw_out: Tween = m.create_tween()
	tw_out.tween_method(func(a: float) -> void:
		_set_card_alpha(card_node, a)
	, 1.0, 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_out.tween_callback(func() -> void:
		callback.call()
		# 执行 callback 后刷新卡牌视觉 (类型已被更改为 normal)
		update_dark_card_visual(row, col)
		# 淡入
		var tw_in: Tween = m.create_tween()
		tw_in.tween_method(func(a: float) -> void:
			_set_card_alpha(card_node, a)
		, 0.0, 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)

# ---------------------------------------------------------------------------
# 暗面 NPC 3D 节点 (Sprite3D billboard, 匹配 Lua DarkWorld.createNPCNodes)
# ---------------------------------------------------------------------------

## NPC 渲染参数 (精确匹配 Lua NPCManager.lua)
## Lua: SPRITE_3D_H=0.50 (半尺寸) → 全高=1.00m
## Lua: node.Y=0.25, bb.position.y=SPRITE_3D_H/2=0.25 → billboard 中心 Y=0.50m
## Godot Sprite3D: pixel_size=NPC_WORLD_SIZE/tex_max (tex_max=最长边像素数)
##   全高 = pixel_size × tex_height = NPC_WORLD_SIZE × (tex_h/tex_max) ≤ 1.00m
##   Sprite3D 中心就是位置坐标, 故 position.y = billboard 中心 Y = 0.50m
## Lua: SHARE_OFFSET=0.18 → NPC 右移 0.18, Token 左移 0.18
const NPC_BASE_Y: float = 0.50        # Lua: node(0.25) + bb.offset(0.25) = 0.50m
const NPC_WORLD_SIZE: float = 1.00    # Lua: SPRITE_3D_H(0.50) × 2 = 1.00m
const NPC_OFFSET_X: float = 0.18     # Lua SHARE_OFFSET=0.18
const NPC_BREATHE_SPEED: float = 2.0
const NPC_BREATHE_AMP: float = 0.02

## npcs_dict: NPCManager.npcs (id → NPCManager.NPCData)
func create_npc_nodes(npcs_dict: Dictionary) -> void:
	destroy_npc_nodes()
	var i: int = 0
	for npc in npcs_dict.values():
		var tex: Texture2D = load(npc.tex_path)
		if not tex:
			push_warning("[BoardVisual] NPC '%s' 贴图加载失败: %s" % [npc.id, npc.tex_path])
			i += 1
			continue

		# npc.row/npc.col 由 NPCManager.spawn_npc(tile.x, tile.y) 设置，
		# _pick_free_tile 返回 1-based 坐标，不需要 +1
		var world_pos: Vector3 = m.board.grid_to_world(npc.row, npc.col)
		world_pos.x += NPC_OFFSET_X
		world_pos.y = NPC_BASE_Y

		# --- 阴影 blob (扁平半透明椭球) ---
		var shadow_mesh: MeshInstance3D = MeshInstance3D.new()
		shadow_mesh.name = "NPCShadow_%s" % npc.id
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.10
		sphere.height = 0.04
		shadow_mesh.mesh = sphere
		var shadow_mat: StandardMaterial3D = StandardMaterial3D.new()
		shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.35)
		shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shadow_mesh.set_surface_override_material(0, shadow_mat)
		shadow_mesh.position = Vector3(world_pos.x, 0.02, world_pos.z)  # 贴地面
		shadow_mesh.scale = Vector3(1.0, 0.25, 1.0)  # 压扁成椭圆
		add_child(shadow_mesh)

		# --- NPC Sprite3D ---
		var sprite: Sprite3D = Sprite3D.new()
		sprite.name = "NPC_%s" % npc.id
		sprite.texture = tex
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.transparent = true
		sprite.no_depth_test = false
		sprite.render_priority = 0
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		sprite.alpha_scissor_threshold = 0.5
		var tex_max: float = maxf(float(tex.get_width()), float(tex.get_height()))
		var scale_val: float = npc.sprite_scale if npc.sprite_scale > 0.0 else 1.0
		var base_size: float = NPC_WORLD_SIZE * scale_val
		sprite.pixel_size = base_size / tex_max if tex_max > 0.0 else 0.001
		sprite.position = world_pos
		# 弹出动画: 初始缩放为 0
		sprite.scale = Vector3.ZERO
		sprite.modulate = Color(1, 1, 1, 0)
		add_child(sprite)

		# 弹出 Tween (easeOutBack: scale 0→1, alpha 0→1, 延迟 0.3s)
		# 注意: pop_done=false 期间, update_npc_visuals 不覆盖 scale
		var entry: Dictionary = {
			"node": sprite,
			"shadow": shadow_mesh,
			"row": npc.row,
			"col": npc.col,
			"npc_id": npc.id,
			"pop_done": false,
		}
		_npc_nodes[i] = entry
		var tw: Tween = create_tween()
		tw.set_parallel(true)
		tw.tween_interval(0.3)
		tw.tween_property(sprite, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.3)
		tw.tween_property(sprite, "modulate:a", 1.0, 0.3).set_delay(0.3)
		tw.chain().tween_callback(func(): entry["pop_done"] = true)
		i += 1

func destroy_npc_nodes() -> void:
	for key in _npc_nodes:
		var data: Dictionary = _npc_nodes[key]
		var node = data.get("node")
		if is_instance_valid(node):
			node.queue_free()
		var shadow = data.get("shadow")
		if is_instance_valid(shadow):
			shadow.queue_free()
	_npc_nodes.clear()

## NPC 点击检测 — 返回 {row, col, npc_id}，未命中返回空 {}
## click_pos: 屏幕坐标
func hit_test_npc(click_pos: Vector2) -> Dictionary:
	# 移除 .current 检查: 相机激活时序不稳定，直接判断引用有效性即可
	if not m._camera_3d:
		return {}
	for key in _npc_nodes:
		var data: Dictionary = _npc_nodes[key]
		var node = data.get("node")
		if not is_instance_valid(node) or not node.visible:
			continue
		# 将 NPC 3D 位置投影到屏幕，检测点击距离
		var screen_pos: Vector2 = m._camera_3d.unproject_position(node.global_position)
		# NPC 渲染高度 1.00m, 相机 ~204 px/m → 半径 ~102px, 使用 80px 宽松阈值
		if click_pos.distance_to(screen_pos) <= 80.0:
			return { "row": data["row"], "col": data["col"], "npc_id": data["npc_id"] }
	return {}

func update_npc_visuals(game_time: float) -> void:
	var breathe: float = 1.0 + sin(game_time * NPC_BREATHE_SPEED) * NPC_BREATHE_AMP
	for key in _npc_nodes:
		var data: Dictionary = _npc_nodes[key]
		# 弹出 Tween 未完成时不覆盖 scale，避免打断弹出动画
		if not data.get("pop_done", false):
			continue
		var node = data.get("node")
		if is_instance_valid(node):
			node.scale = Vector3(breathe, breathe, breathe)

# ---------------------------------------------------------------------------
# 地图道具 3D 节点 (Sprite3D billboard, 匹配 Lua BoardItems)
# ---------------------------------------------------------------------------
## 道具渲染参数 (精确匹配 Lua BoardItems, ×2 half-extent 修正)
## Lua: bb.size=0.22 (half) → 实际 0.44m
## Lua: ITEM_BASE_Y=0.35, bb.offset.y=0.11 → 中心 Y=0.35+0.11=0.46
## 但 Godot 之前直接用 0.35 作为中心, 保持不变 (视觉微调)
const ITEM_SCALED_SIZE: float = 0.22 * BILLBOARD_HALF_EXTENT_FACTOR
const ITEM_SCALED_BASE_Y: float = 0.35

## 道具 Sprite3D 节点缓存: item_index(int) → Dictionary
var _item_nodes: Dictionary = {}

func create_item_nodes(items: Array) -> void:
	destroy_item_nodes()
	for i in range(items.size()):
		var item: BoardItems.BoardItem = items[i]
		if item.collected:
			continue
		var tex_path: String = BoardItems.ICON_TEXTURES.get(item.key, "")
		if tex_path.is_empty():
			continue
		var tex: Texture2D = load(tex_path)
		if not tex:
			continue
		var sprite: Sprite3D = Sprite3D.new()
		sprite.name = "Item_%d_%s" % [i, item.key]
		sprite.texture = tex
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.transparent = true
		sprite.no_depth_test = false
		sprite.render_priority = 0
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		sprite.alpha_scissor_threshold = 0.5
		var tex_max: float = maxf(float(tex.get_width()), float(tex.get_height()))
		sprite.pixel_size = ITEM_SCALED_SIZE / tex_max if tex_max > 0.0 else 0.001
		var world_pos: Vector3 = m.board.grid_to_world(item.row, item.col)
		world_pos.y = ITEM_SCALED_BASE_Y
		world_pos.z -= 0.18  # CAMERA_OFFSET_Z — 向相机方向偏移
		sprite.position = world_pos
		# 初始不可见 (弹出动画会设置)
		sprite.modulate = Color(1, 1, 1, 0)
		sprite.scale = Vector3(0.01, 0.01, 0.01)
		add_child(sprite)
		_item_nodes[i] = {
			"node": sprite,
			"base_y": ITEM_SCALED_BASE_Y,
			"phase": item.phase,
			"pos_x": world_pos.x,
			"pos_z": world_pos.z,
		}

func destroy_item_nodes() -> void:
	for key in _item_nodes:
		var data: Dictionary = _item_nodes[key]
		var node = data.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_item_nodes.clear()

func update_item_visuals(game_time: float) -> void:
	for key in _item_nodes:
		var data: Dictionary = _item_nodes[key]
		var node = data.get("node")
		if not is_instance_valid(node):
			continue
		var float_y: float = sin(game_time * BoardItems.FLOAT_SPEED_3D + data["phase"]) * BoardItems.FLOAT_AMP_3D
		node.position = Vector3(data["pos_x"], data["base_y"] + float_y, data["pos_z"])

## 道具弹出动画 (scale 0→1, alpha 0→1)
func animate_item_spawn(item_index: int, delay: float) -> void:
	if not _item_nodes.has(item_index):
		return
	var data: Dictionary = _item_nodes[item_index]
	var node = data.get("node")
	if not is_instance_valid(node):
		return
	var tw: Tween = m.create_tween()
	tw.tween_property(node, "scale", Vector3.ONE, 0.3) \
		.set_delay(delay) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	var tw2: Tween = m.create_tween()
	tw2.tween_property(node, "modulate:a", 1.0, 0.2).set_delay(delay)

## 道具拾取动画 (上飘 + 淡出 + 移除节点)
func animate_item_collect(item_index: int) -> void:
	if not _item_nodes.has(item_index):
		return
	var data: Dictionary = _item_nodes[item_index]
	var node = data.get("node")
	if not is_instance_valid(node):
		_item_nodes.erase(item_index)
		return
	var start_y: float = node.position.y
	var tw: Tween = m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "position:y", start_y + 0.3, 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(node, "modulate:a", 0.0, 0.35) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(node, "scale", Vector3(1.3, 1.3, 1.3), 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(node):
			node.queue_free()
		_item_nodes.erase(item_index)
	)

# ---------------------------------------------------------------------------
# 怪物 Chibi 3D 节点 (MonsterGhost — 环绕/卡牌/踪迹)
# ---------------------------------------------------------------------------

## MonsterGhost 节点缓存
var _mg_surround_nodes: Array = []   # 环绕玩家的 chibi Sprite3D
var _mg_card_nodes: Array = []       # 卡牌上的 chibi Sprite3D
var _mg_trail_nodes: Array = []      # 踪迹箭头 chibi Sprite3D
var _rift_card_nodes: Array = []     # 裂隙入口卡牌上的 chibi Sprite3D
var _passage_card_nodes: Array = [] # 暗面层通道卡牌上的 chibi Sprite3D

## 环绕布局 (精确匹配 Lua SURROUND_LAYOUT, size ×2 half-extent 修正)
const MG_SURROUND_LAYOUT: Array = [
	{ "dx":  0.00, "dz":  0.20, "baseY": 0.55, "size": 0.32 * 2.0, "is_main": true },
	{ "dx": -0.35, "dz": -0.15, "baseY": 0.30, "size": 0.18 * 2.0, "is_main": false },
	{ "dx":  0.32, "dz":  0.08, "baseY": 0.42, "size": 0.20 * 2.0, "is_main": false },
	{ "dx": -0.18, "dz":  0.30, "baseY": 0.60, "size": 0.15 * 2.0, "is_main": false },
	{ "dx":  0.25, "dz": -0.20, "baseY": 0.25, "size": 0.16 * 2.0, "is_main": false },
]
## 卡牌 chibi 参数 (Lua: size=0.28 half → 实际 0.56m)
const MG_CARD_BASE_Y: float = 0.35
const MG_CARD_SIZE: float = 0.28 * BILLBOARD_HALF_EXTENT_FACTOR
## 裂隙 chibi 参数 (略大于怪物 chibi, 突出感)
const RIFT_CARD_BASE_Y: float = 0.40
const RIFT_CARD_SIZE: float = 0.32 * BILLBOARD_HALF_EXTENT_FACTOR
const RIFT_TEX_PATH: String = "res://assets/image/rift_chibi.png"
## 通道 chibi 参数 (暗面层间传送门, 与裂隙相近大小)
const PASSAGE_CARD_BASE_Y: float = 0.40
const PASSAGE_CARD_SIZE: float = 0.30 * BILLBOARD_HALF_EXTENT_FACTOR
const PASSAGE_TEX_PATH: String = "res://assets/image/passage_chibi.png"
## 踪迹箭头参数 (Lua: size=0.14 half → 实际 0.28m)
const MG_TRAIL_BASE_Y: float = 0.25
const MG_TRAIL_SIZE: float = 0.14 * BILLBOARD_HALF_EXTENT_FACTOR
const MG_TRAIL_OFFSET_DIST: float = 0.38  # 偏移到卡牌边缘

## 创建单个 MonsterGhost Sprite3D (通用)
func _mg_create_sprite(tex_path: String, world_x: float, world_z: float,
		base_y: float, world_size: float, phase: float) -> Dictionary:
	var tex: Texture2D = load(tex_path) as Texture2D
	if not tex:
		return {}
	var sprite: Sprite3D = Sprite3D.new()
	sprite.texture = tex
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.transparent = true
	sprite.no_depth_test = false
	sprite.render_priority = 0
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.alpha_scissor_threshold = 0.5
	var tex_max: float = maxf(float(tex.get_width()), float(tex.get_height()))
	sprite.pixel_size = world_size / tex_max if tex_max > 0.0 else 0.001
	sprite.position = Vector3(world_x, base_y, world_z)
	# 初始不可见 (弹出动画会设置)
	sprite.modulate = Color(1, 1, 1, 0)
	sprite.scale = Vector3(0.01, 0.01, 0.01)
	add_child(sprite)
	return {
		"node": sprite,
		"base_y": base_y,
		"phase": phase,
		"anchor_x": world_x,
		"anchor_z": world_z,
		"size": world_size,
	}

## 环绕弹出: 踩到怪物牌时在玩家周围弹出 chibi
func mg_spawn_around_player(row: int, col: int, location: String) -> void:
	mg_clear_surround()
	var world_pos: Vector3 = m.board.grid_to_world(row, col)
	var wx: float = world_pos.x
	var wz: float = world_pos.z
	var main_tex: String = MonsterGhost.get_monster_texture(location)

	for i in range(MG_SURROUND_LAYOUT.size()):
		var slot: Dictionary = MG_SURROUND_LAYOUT[i]
		var tex_path: String
		if slot.get("is_main", false):
			tex_path = main_tex
		else:
			tex_path = MonsterGhost.GHOST_VARIANTS[randi_range(0, MonsterGhost.GHOST_VARIANTS.size() - 1)]
		var gx: float = wx + slot["dx"]
		var gz: float = wz + slot["dz"]
		var phase: float = float(i) * 1.3 + randf() * 0.5
		var data: Dictionary = _mg_create_sprite(tex_path, gx, gz,
			slot["baseY"], slot["size"], phase)
		if data.is_empty():
			continue
		_mg_surround_nodes.append(data)
		# 弹出动画 (交错延迟, easeOutBack)
		var node: Sprite3D = data["node"]
		var delay: float = float(i + 1) * 0.07
		var tw: Tween = m.create_tween()
		tw.set_parallel(true)
		tw.tween_property(node, "scale", Vector3.ONE, 0.35) \
			.set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(node, "modulate:a", 1.0, 0.25).set_delay(delay)

## 清除环绕 chibi
func mg_clear_surround() -> void:
	for data in _mg_surround_nodes:
		var node = data.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_mg_surround_nodes.clear()

## 驱魔: 环绕 chibi 飞散动画 (各自向随机方向飞出 + 缩小 + 淡出)
func mg_scatter_surround() -> void:
	for data in _mg_surround_nodes:
		var node: Sprite3D = data.get("node")
		if not is_instance_valid(node):
			continue
		# 随机飞散方向
		var angle: float = randf() * TAU
		var fly_dist: float = 0.4 + randf() * 0.3
		var target_x: float = node.position.x + cos(angle) * fly_dist
		var target_z: float = node.position.z + sin(angle) * fly_dist
		var tw: Tween = m.create_tween()
		tw.set_parallel(true)
		tw.tween_property(node, "position:x", target_x, 0.4) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(node, "position:z", target_z, 0.4) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(node, "scale", Vector3(0.1, 0.1, 0.1), 0.4) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(node, "modulate:a", 0.0, 0.35) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.chain().tween_callback(func() -> void:
			if is_instance_valid(node):
				node.queue_free()
		)
	# 延迟清空数组
	var nodes_ref: Array = _mg_surround_nodes
	_mg_surround_nodes = []
	var tw_cleanup: Tween = m.create_tween()
	tw_cleanup.tween_callback(func() -> void:
		for d in nodes_ref:
			var n = d.get("node")
			if is_instance_valid(n):
				n.queue_free()
		nodes_ref.clear()
	).set_delay(0.5)

## 在卡牌上方显示怪物 chibi (拍照鉴定后)
func mg_show_on_card(row: int, col: int, location: String) -> void:
	var world_pos: Vector3 = m.board.grid_to_world(row, col)
	var tex_path: String = MonsterGhost.get_monster_texture(location)
	var phase: float = randf() * 3.0
	var data: Dictionary = _mg_create_sprite(tex_path, world_pos.x, world_pos.z,
		MG_CARD_BASE_Y, MG_CARD_SIZE, phase)
	if data.is_empty():
		return
	_mg_card_nodes.append(data)
	# 弹出动画
	var node: Sprite3D = data["node"]
	var tw: Tween = m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "scale", Vector3.ONE, 0.3) \
		.set_delay(0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(node, "modulate:a", 1.0, 0.2).set_delay(0.15)

## 清除卡牌 chibi
func mg_clear_card_ghosts() -> void:
	for data in _mg_card_nodes:
		var node = data.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_mg_card_nodes.clear()

# ---------------------------------------------------------------------------
# 裂隙 chibi (翻开含裂隙的卡牌时显示在卡牌上)
# ---------------------------------------------------------------------------

## 在指定卡牌上显示裂隙 chibi (弹出动画 + 持续脉冲)
func rift_show_on_card(row: int, col: int) -> void:
	var world_pos: Vector3 = m.board.grid_to_world(row, col)
	var phase: float = randf() * TAU
	var data: Dictionary = _mg_create_sprite(RIFT_TEX_PATH,
		world_pos.x, world_pos.z, RIFT_CARD_BASE_Y, RIFT_CARD_SIZE, phase)
	if data.is_empty():
		push_warning("[BoardVisual] rift_show_on_card: 裂隙贴图加载失败 " + RIFT_TEX_PATH)
		return
	_rift_card_nodes.append(data)
	# 弹出动画: 略大于怪物 chibi, 加入轻微旋转感
	var node: Sprite3D = data["node"]
	var tw: Tween = m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "scale", Vector3(1.1, 1.1, 1.1), 0.4) \
		.set_delay(0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(node, "modulate:a", 1.0, 0.25).set_delay(0.1)
	# 弹出后轻微回弹到标准大小
	tw.chain().tween_property(node, "scale", Vector3.ONE, 0.15) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

## 清除所有裂隙 chibi (不带动画, 用于重置棋盘)
func rift_clear_all() -> void:
	for data in _rift_card_nodes:
		var node = data.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_rift_card_nodes.clear()

# ---------------------------------------------------------------------------
# 通道 chibi (暗面层间通道翻开且可通行时显示在卡牌上)
# ---------------------------------------------------------------------------

## 在指定卡牌上显示通道 chibi (弹出动画 + 持续青色脉冲)
func passage_show_on_card(row: int, col: int) -> void:
	var world_pos: Vector3 = m.board.grid_to_world(row, col)
	var phase: float = randf() * TAU
	var data: Dictionary = _mg_create_sprite(PASSAGE_TEX_PATH,
		world_pos.x, world_pos.z, PASSAGE_CARD_BASE_Y, PASSAGE_CARD_SIZE, phase)
	if data.is_empty():
		push_warning("[BoardVisual] passage_show_on_card: 通道贴图加载失败 " + PASSAGE_TEX_PATH)
		return
	_passage_card_nodes.append(data)
	# 弹出动画: 与裂隙相同风格但更轻盈 (传送门感)
	var node: Sprite3D = data["node"]
	var tw: Tween = m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "scale", Vector3(1.05, 1.05, 1.05), 0.35) \
		.set_delay(0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(node, "modulate:a", 1.0, 0.25).set_delay(0.1)
	tw.chain().tween_property(node, "scale", Vector3.ONE, 0.15) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

## 清除所有通道 chibi (不带动画, 用于层切换/棋盘重置)
func passage_clear_all() -> void:
	for data in _passage_card_nodes:
		var node = data.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_passage_card_nodes.clear()

## 驱魔: 卡牌 chibi 死亡动画 (抖动→膨胀→淡出→清除)
## on_burst: 膨胀开始时触发一次 (用于同步闪光/粒子)
func mg_exorcise_card_ghosts(on_burst: Callable = Callable()) -> void:
	if _mg_card_nodes.is_empty():
		if on_burst.is_valid():
			on_burst.call()
		return
	var burst_fired: bool = false
	for data in _mg_card_nodes:
		var node: Sprite3D = data.get("node")
		if not is_instance_valid(node):
			continue
		var anchor_x: float = data.get("anchor_x", node.position.x)
		# Phase A: 抖动 (0.15s, 高频小幅)
		var tw_shake: Tween = m.create_tween()
		tw_shake.tween_method(func(t: float) -> void:
			if is_instance_valid(node):
				node.position.x = anchor_x + sin(t * PI * 16.0) * 0.03 * (1.0 - t)
		, 0.0, 1.0, 0.15)
		# Phase B: 膨胀 + 淡出 (0.25s)
		tw_shake.tween_callback(func() -> void:
			if not burst_fired:
				burst_fired = true
				if on_burst.is_valid():
					on_burst.call()
			if not is_instance_valid(node):
				return
			var tw_die: Tween = m.create_tween()
			tw_die.set_parallel(true)
			tw_die.tween_property(node, "scale", Vector3(1.5, 1.5, 1.5), 0.25) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw_die.tween_property(node, "modulate:a", 0.0, 0.25) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw_die.chain().tween_callback(func() -> void:
				if is_instance_valid(node):
					node.queue_free()
			)
		)
	# 延迟清空数组 (等动画完成)
	var tw_cleanup: Tween = m.create_tween()
	tw_cleanup.tween_callback(func() -> void:
		_mg_card_nodes.clear()
	).set_delay(0.45)

## 显示已侦测的怪物卡牌 chibi (相机模式进入时)
func mg_show_on_scouted_cards() -> void:
	mg_clear_card_ghosts()
	var idx: int = 0
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = m.board.get_card(r, c)
			if card and card.scouted and card.type == "monster":
				var world_pos: Vector3 = m.board.grid_to_world(r, c)
				var tex_path: String = MonsterGhost.get_monster_texture(card.location)
				var phase: float = randf() * 3.0
				var data: Dictionary = _mg_create_sprite(tex_path,
					world_pos.x, world_pos.z, MG_CARD_BASE_Y, MG_CARD_SIZE, phase)
				if data.is_empty():
					continue
				_mg_card_nodes.append(data)
				var node: Sprite3D = data["node"]
				var delay: float = 0.1 + float(idx) * 0.05
				var tw: Tween = m.create_tween()
				tw.set_parallel(true)
				tw.tween_property(node, "scale", Vector3.ONE, 0.3) \
					.set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
				tw.tween_property(node, "modulate:a", 1.0, 0.2).set_delay(delay)
				idx += 1

## 在卡牌边缘显示踪迹箭头 chibi
func mg_show_trail_on_card(row: int, col: int, dir_x: float, dir_z: float) -> void:
	var world_pos: Vector3 = m.board.grid_to_world(row, col)
	var tex_path: String = MonsterGhost.GHOST_VARIANTS[randi_range(0, MonsterGhost.GHOST_VARIANTS.size() - 1)]
	var len: float = sqrt(dir_x * dir_x + dir_z * dir_z)
	var offset_x: float = 0.0
	var offset_z: float = 0.0
	if len > 0.001:
		offset_x = (dir_x / len) * MG_TRAIL_OFFSET_DIST
		offset_z = (dir_z / len) * MG_TRAIL_OFFSET_DIST
	var phase: float = randf() * 3.0
	var data: Dictionary = _mg_create_sprite(tex_path,
		world_pos.x + offset_x, world_pos.z + offset_z,
		MG_TRAIL_BASE_Y, MG_TRAIL_SIZE, phase)
	if data.is_empty():
		return
	data["offset_x"] = offset_x
	data["offset_z"] = offset_z
	data["card_x"] = world_pos.x
	data["card_z"] = world_pos.z
	_mg_trail_nodes.append(data)
	# 弹出动画
	var node: Sprite3D = data["node"]
	var tw: Tween = m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "scale", Vector3.ONE, 0.35) \
		.set_delay(0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(node, "modulate:a", 0.85, 0.25).set_delay(0.2)

## 清除踪迹箭头
func mg_clear_trail_ghosts() -> void:
	for data in _mg_trail_nodes:
		var node = data.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_mg_trail_nodes.clear()

## 显示所有已记录的踪迹箭头 (相机模式进入时)
func mg_show_trails_on_board() -> void:
	mg_clear_trail_ghosts()
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = m.board.get_card(r, c)
			if card and card.has_trail:
				mg_show_trail_on_card(r, c, card.trail_dir_x, card.trail_dir_y)

## 清除所有 MonsterGhost 节点
func mg_clear_all() -> void:
	mg_clear_surround()
	mg_clear_card_ghosts()
	mg_clear_trail_ghosts()

## 每帧更新 MonsterGhost 动画 (浮动 + 晃动)
func update_monster_ghost_visuals(game_time: float) -> void:
	# 环绕幽灵: sin 浮动 + 水平晃动
	for data in _mg_surround_nodes:
		var node = data.get("node")
		if not is_instance_valid(node):
			continue
		var float_y: float = sin(game_time * 2.0 + data["phase"]) * 0.025
		var sway_x: float = sin(game_time * 1.2 + data["phase"] * 0.7) * 0.012
		node.position = Vector3(
			data["anchor_x"] + sway_x,
			data["base_y"] + float_y,
			data["anchor_z"])

	# 卡牌 chibi: sin 浮动
	for data in _mg_card_nodes:
		var node = data.get("node")
		if not is_instance_valid(node):
			continue
		var float_y: float = sin(game_time * 2.5 + data["phase"]) * 0.02
		node.position = Vector3(
			data["anchor_x"],
			data["base_y"] + float_y,
			data["anchor_z"])

	# 裂隙 chibi: 较慢的脉冲浮动 (营造神秘感)
	for data in _rift_card_nodes:
		var node = data.get("node")
		if not is_instance_valid(node):
			continue
		var float_y: float = sin(game_time * 1.8 + data["phase"]) * 0.025
		# 加入轻微的色相脉冲 (紫色调明暗)
		var pulse: float = 0.85 + sin(game_time * 2.2 + data["phase"] * 0.7) * 0.15
		node.modulate = Color(pulse, pulse * 0.7, 1.0, node.modulate.a)
		node.position = Vector3(
			data["anchor_x"],
			data["base_y"] + float_y,
			data["anchor_z"])

	# 通道 chibi: 青色脉冲浮动 (传送门感, 稍快于裂隙)
	for data in _passage_card_nodes:
		var node = data.get("node")
		if not is_instance_valid(node):
			continue
		var float_y: float = sin(game_time * 2.0 + data["phase"]) * 0.022
		# 青绿色调脉冲
		var pulse: float = 0.80 + sin(game_time * 2.6 + data["phase"] * 0.8) * 0.20
		node.modulate = Color(pulse * 0.6, 1.0, pulse, node.modulate.a)
		node.position = Vector3(
			data["anchor_x"],
			data["base_y"] + float_y,
			data["anchor_z"])

	# 踪迹箭头: sin 浮动 + 方向晃动
	for data in _mg_trail_nodes:
		var node = data.get("node")
		if not is_instance_valid(node):
			continue
		var float_y: float = sin(game_time * 2.0 + data["phase"]) * 0.02
		var bob_t: float = sin(game_time * 1.8 + data["phase"]) * 0.15
		var ox: float = data.get("offset_x", 0.0) * (1.0 + bob_t)
		var oz: float = data.get("offset_z", 0.0) * (1.0 + bob_t)
		node.position = Vector3(
			data.get("card_x", 0.0) + ox,
			data["base_y"] + float_y,
			data.get("card_z", 0.0) + oz)

# ---------------------------------------------------------------------------
# 棋盘叠层效果 (Phase 3 用 3D 节点替代 _draw)
# ---------------------------------------------------------------------------

## 叠层效果刷新: 根据当前棋盘状态重建裂隙 chibi
## 在棋盘重新生成或状态恢复时调用
func _update_overlays() -> void:
	# 清除旧的裂隙 chibi
	rift_clear_all()
	# 重建: 扫描所有已翻开且含裂隙的卡牌
	if not m.board:
		return
	var grid: Array = m.board.grid
	for r in grid.size():
		for c in grid[r].size():
			var card = grid[r][c]
			if card and card.has_rift and card.is_revealed:
				rift_show_on_card(r, c)

# ---------------------------------------------------------------------------
# 地标 / 安全区: 方形发光边框上浮特效 (匹配 Lua 版 Card.attachGlowRings)
# ---------------------------------------------------------------------------

## 为卡牌创建光环 ShaderMaterial (每层独立实例, 便于独立设 alpha)
func _create_glow_ring_material(color: Color, is_landmark: bool) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _glow_border_shader
	mat.set_shader_parameter("border_color", color)
	if is_landmark:
		mat.set_shader_parameter("border_width", 0.09)   # 更粗边框
		mat.set_shader_parameter("glow_spread", 0.12)    # 更宽辉光
	else:
		mat.set_shader_parameter("border_width", 0.06)
		mat.set_shader_parameter("glow_spread", 0.08)
	mat.render_priority = 0  # 与 chibi/token 同组, 由深度排序决定先后; chibi 世界 Y≈0.5 远高于光环 Y≈0.018, 相机俯视时 chibi 自然更近
	return mat

## 为指定卡牌挂载方形发光边框 (landmark=4层金色华丽, home=3层柔白)
func _attach_glow_rings(card_node: MeshInstance3D, card_type: String) -> void:
	# 已有光环则跳过
	if card_node.get_node_or_null("GlowRing_1"):
		return

	var is_landmark: bool = (card_type == "landmark")
	var ring_count: int = GLOW_LM_RING_COUNT if is_landmark else GLOW_RING_COUNT
	var base_color: Color = Color(0.55, 0.38, 0.05, 0.55)  # 统一金色, 降低亮度与透明度

	for i in range(1, ring_count + 1):
		var ring: MeshInstance3D = MeshInstance3D.new()
		ring.name = "GlowRing_%d" % i
		ring.mesh = _glow_quad_mesh
		ring.material_override = _create_glow_ring_material(base_color, is_landmark)
		ring.position = Vector3(0, GLOW_Y_BASE, 0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.visible = false  # 默认隐藏, 由 show_safe_glows() 激活
		ring.set_meta("is_landmark", is_landmark)
		card_node.add_child(ring)

## 移除卡牌上的光环层 (兼容 3 层 home 和 4 层 landmark)
func _remove_glow_rings(card_node: MeshInstance3D) -> void:
	var max_rings: int = maxi(GLOW_RING_COUNT, GLOW_LM_RING_COUNT)
	for i in range(1, max_rings + 1):
		var ring: Node = card_node.get_node_or_null("GlowRing_%d" % i)
		if ring:
			ring.queue_free()

## 设置单张卡牌光晕可见性 (显示/隐藏所有光环层, 兼容 3/4 层)
func _set_glow_visible(card_node: MeshInstance3D, visible: bool) -> void:
	var max_rings: int = maxi(GLOW_RING_COUNT, GLOW_LM_RING_COUNT)
	for i in range(1, max_rings + 1):
		var ring: MeshInstance3D = card_node.get_node_or_null("GlowRing_%d" % i) as MeshInstance3D
		if ring:
			ring.visible = visible

## 每帧更新所有激活光环的上浮/淡出/放大动画 (由 main._process 调用)
func update_glow_rings(game_time: float) -> void:
	var max_rings: int = maxi(GLOW_RING_COUNT, GLOW_LM_RING_COUNT)
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = m.board.get_card(r, c)
			if card == null or not card.safe_glow_active:
				continue
			var card_node: MeshInstance3D = get_card_node(r, c)
			if card_node == null:
				continue
			for i in range(1, max_rings + 1):
				var ring: MeshInstance3D = card_node.get_node_or_null("GlowRing_%d" % i) as MeshInstance3D
				if ring == null or ring.material_override == null:
					continue
				# 根据 metadata 选择动画参数 (landmark vs home/aura)
				var is_lm: bool = ring.get_meta("is_landmark", false)
				var cycle: float = GLOW_LM_CYCLE if is_lm else GLOW_CYCLE
				var ring_count: int = GLOW_LM_RING_COUNT if is_lm else GLOW_RING_COUNT
				# 交错相位: 每层偏移 1/ring_count 个周期
				var phase: float = fmod(game_time / cycle + float(i - 1) / float(ring_count), 1.0)
				# sin 脉冲: 0.15 ~ 0.75 之间呼吸, 不完全消失
				var alpha: float = 0.15 + 0.60 * sin(phase * PI)
				# 更新 shader uniform 中的 alpha (保留原始 RGB 颜色)
				var mat: ShaderMaterial = ring.material_override as ShaderMaterial
				var col: Color = mat.get_shader_parameter("border_color") as Color
				col.a = alpha
				mat.set_shader_parameter("border_color", col)

## 显式激活所有安全区光晕: home/landmark + 地标辐射区 (发牌完成后调用)
func show_safe_glows() -> void:
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = m.board.get_card(r, c)
			if card == null:
				continue
			# home/landmark 自身 + 地标辐射区 (上下左右相邻格)
			var has_glow: bool = card.should_have_glow() \
				or m.board.is_in_landmark_aura(r, c)
			if not has_glow:
				continue
			var card_node: MeshInstance3D = get_card_node(r, c)
			if card_node:
				# 辐射区卡牌也挂载光环 (白色, 与 home 相同)
				_attach_glow_rings(card_node, "home")
				_set_glow_visible(card_node, true)
			card.show_safe_glow()

## 显式关闭所有卡牌的安全区光晕
func hide_safe_glows() -> void:
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = m.board.get_card(r, c)
			if card == null:
				continue
			card.hide_safe_glow()
			var card_node: MeshInstance3D = get_card_node(r, c)
			if card_node:
				_set_glow_visible(card_node, false)

# ---------------------------------------------------------------------------
# 点击检测 (3D raycast → Y=0 平面)
# ---------------------------------------------------------------------------

## 检测点击位置对应的棋盘格子, 返回 Vector2i (row, col) 或 Vector2i.ZERO
func hit_test(click_pos: Vector2) -> Vector2i:
	if not m._camera_3d or not m._camera_3d.current:
		# 3D 相机未激活, 使用简易屏幕坐标映射 (过渡方案)
		return _hit_test_screen_fallback(click_pos)

	# 从相机发射射线
	var ray_origin: Vector3 = m._camera_3d.project_ray_origin(click_pos)
	var ray_dir: Vector3 = m._camera_3d.project_ray_normal(click_pos)

	# 与 Y=CARD_Y 平面相交
	if abs(ray_dir.y) < 0.001:
		return Vector2i.ZERO  # 射线平行于地面

	var t: float = (CARD_Y - ray_origin.y) / ray_dir.y
	if t < 0:
		return Vector2i.ZERO  # 交点在相机后方

	var hit_point: Vector3 = ray_origin + ray_dir * t

	# 检测命中哪张卡牌
	var half_w: float = Card.CARD_W * 0.5
	var half_h: float = Card.CARD_H * 0.5
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card_node: MeshInstance3D = get_card_node(r, c)
			if card_node == null or not card_node.visible:
				continue
			var card_pos: Vector3 = card_node.position
			if abs(hit_point.x - card_pos.x) <= half_w \
					and abs(hit_point.z - card_pos.z) <= half_h:
				return Vector2i(r, c)

	return Vector2i.ZERO

## 回退方案: 3D 相机未激活时通过屏幕坐标估算
func _hit_test_screen_fallback(click_pos: Vector2) -> Vector2i:
	var vp_size: Vector2 = m.get_viewport_rect().size
	var total_w: float = Board.COLS * (Card.CARD_W + Board.GAP) - Board.GAP
	var total_h: float = Board.ROWS * (Card.CARD_H + Board.GAP) - Board.GAP

	# 反向映射屏幕坐标到归一化格子坐标
	var norm_x: float = (click_pos.x / vp_size.x - 0.15) / 0.7
	var norm_z: float = (click_pos.y / vp_size.y - 0.15) / 0.7

	if norm_x < 0 or norm_x > 1 or norm_z < 0 or norm_z > 1:
		return Vector2i.ZERO

	# 计算最近的格子
	var world_x: float = norm_x * total_w - total_w * 0.5
	var world_z: float = norm_z * total_h - total_h * 0.5

	var half_w: float = Card.CARD_W * 0.5
	var half_h: float = Card.CARD_H * 0.5
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var grid_pos: Vector3 = m.board.grid_to_world(r, c)
			if abs(world_x - grid_pos.x) <= half_w \
					and abs(world_z - grid_pos.z) <= half_h:
				return Vector2i(r, c)

	return Vector2i.ZERO
