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
## 共享卡牌 Mesh
var _card_mesh: BoxMesh = null
## 粒子材质缓存 (landmark / home 两套)
var _particle_mat_landmark: StandardMaterial3D = null
var _particle_mat_home: StandardMaterial3D = null

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

	# 粒子材质 (地标: 金色, 家: 白色)
	_particle_mat_landmark = _create_particle_material(GameTheme.glow_color)
	_particle_mat_home = _create_particle_material(Color(0.9, 0.95, 1.0, 0.8))

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

			# 独立材质实例
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = GameTheme.card_back
			mat.roughness = 0.7
			mat.metallic = 0.0
			card_node.material_override = mat
			_card_materials["%d_%d" % [row, col]] = mat

			card_node.position = target_pos
			card_node.set_meta("row", row)
			card_node.set_meta("col", col)
			card_node.set_meta("target_pos", target_pos)

			# 地标卡初始就正面朝上: 显示事件面颜色和文字
			if card.is_flipped:
				var type_info: Dictionary = GameTheme.card_type_info(card.type)
				mat.albedo_color = type_info.get("color", GameTheme.card_face)

			# 占位 Label3D (显示卡牌类型文字)
			var label: Label3D = Label3D.new()
			label.name = "TypeLabel"
			if card.is_flipped:
				# 已翻开 (地标): 显示事件信息
				var type_info2: Dictionary = GameTheme.card_type_info(card.type)
				label.text = type_info2.get("icon", "?") + "\n" + type_info2.get("label", "")
				label.modulate = Color(1, 1, 1, 0.9)
			else:
				# 未翻开: 显示地点信息
				var loc_info: Dictionary = card.get_location_info()
				label.text = loc_info.get("icon", "?") + "\n" + loc_info.get("label", "")
				label.modulate = Color(1, 1, 1, 0.85)
			label.font_size = 48
			label.pixel_size = 0.005
			label.position = Vector3(0, Card.CARD_THICKNESS / 2.0 + 0.001, 0)
			label.rotation_degrees = Vector3(-90, 180, 0)  # 朝上平铺, 补偿相机 180° yaw
			label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			label.no_depth_test = true
			label.render_priority = 1
			card_node.add_child(label)

			# 家/地标: 创建时就挂载光环粒子 (匹配 Lua Card.createNode 行为)
			if card.should_have_glow():
				_attach_glow_particles(card_node, card.type)

			board_layer.add_child(card_node)

# ---------------------------------------------------------------------------
# 卡牌节点查询
# ---------------------------------------------------------------------------

func get_card_node(row: int, col: int) -> MeshInstance3D:
	var card_name: String = "Card_%d_%d" % [row, col]
	return board_layer.get_node_or_null(card_name) as MeshInstance3D

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

	if card.is_flipped:
		var type_info: Dictionary = GameTheme.card_type_info(card.type)
		mat.albedo_color = type_info.get("color", GameTheme.card_face)
		if card.scouted:
			mat.albedo_color = mat.albedo_color.lightened(0.15)
		# 翻开后显示事件信息
		if card_node:
			var label: Label3D = card_node.get_node_or_null("TypeLabel") as Label3D
			if label:
				var icon: String = type_info.get("icon", "?")
				var type_label: String = type_info.get("label", "")
				label.text = icon + "\n" + type_label
				label.modulate = Color(1, 1, 1, 0.9)
			# 地标 / 家: 挂载粒子光晕
			if card.type == "landmark" or card.type == "home":
				_attach_glow_particles(card_node, card.type)
			else:
				_remove_glow_particles(card_node)
	else:
		mat.albedo_color = GameTheme.card_back
		# 未翻开时显示地点信息
		if card_node:
			var label: Label3D = card_node.get_node_or_null("TypeLabel") as Label3D
			if label:
				var loc_info: Dictionary = card.get_location_info()
				var loc_icon: String = loc_info.get("icon", "?")
				var loc_label: String = loc_info.get("label", "")
				label.text = loc_icon + "\n" + loc_label
				label.modulate = Color(1, 1, 1, 0.85)
			# 家/地标即使未翻开也保留光环 (匹配 Lua Card.createNode)
			if not card.should_have_glow():
				_remove_glow_particles(card_node)

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

	if card.is_flipped:
		var dark_color: Color = GameTheme.dark_card_type_color(card.dark_type)
		mat.albedo_color = dark_color
		# 暗面卡牌显示: 类型图标 + 地点名
		var label: Label3D = card_node.get_node_or_null("TypeLabel") as Label3D
		if label:
			var dark_info: Dictionary = GameTheme.dark_card_type_info(card.dark_type)
			var icon: String = dark_info.get("icon", "?")
			# 优先使用 dark_name (具体地点名), fallback 到类型通用 label
			var display_name: String = card.dark_name if card.dark_name != "" else dark_info.get("label", "")
			label.text = icon + "\n" + display_name
			label.modulate = Color(1, 1, 1, 0.9)
	else:
		mat.albedo_color = GameTheme.card_back_dark
		var label: Label3D = card_node.get_node_or_null("TypeLabel") as Label3D
		if label:
			label.modulate = Color(1, 1, 1, 0)

# ---------------------------------------------------------------------------
# Token 精灵更新 (Sprite3D billboard)
# ---------------------------------------------------------------------------

## Token 悬浮高度 (Sprite3D 中心到卡面距离)
## Lua: nodeY=0.25 + bb内部偏移=SPRITE_3D_H/2=0.25 → 中心 Y=0.50
const TOKEN_HOVER_Y: float = 0.49
## 像素→世界单位的换算 (与 Sprite3D.pixel_size 保持一致)
const TOKEN_PX_TO_WORLD: float = 0.00065

func update_token_visual() -> void:
	var token: Token = m.token
	if not token.visible:
		m._token_sprite.visible = false
		return

	m._token_sprite.visible = true
	var tex: Texture2D = token.get_current_texture()
	if tex:
		m._token_sprite.texture = tex

	# 移动动画期间，位置和缩放由 Tween 驱动，这里只更新纹理/可见性
	if token.is_moving:
		m._token_sprite.modulate.a = token.alpha
		return

	# 3D 世界坐标定位
	var world_pos: Vector3 = get_card_world_pos(token.target_row, token.target_col)
	world_pos.y = CARD_Y + TOKEN_HOVER_Y

	# 呼吸动画 (转换像素偏移为世界单位)
	var breathe: Dictionary = token.get_breathe_offset(m.game_time)
	world_pos.y += breathe["y"] * TOKEN_PX_TO_WORLD
	world_pos.y += token.bounce_y * TOKEN_PX_TO_WORLD

	m._token_sprite.position = world_pos
	m._token_sprite.modulate.a = token.alpha
	m._token_sprite.scale = Vector3(token.squash_x, token.squash_y, 1.0)

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
		var mat: StandardMaterial3D = _get_card_mat(pos.x, pos.y)
		if mat:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.0

		var fly_dur: float = 0.35

		# 淡入 (通过材质 alpha)
		if mat:
			var tw_fade: Tween = m.create_tween()
			tw_fade.tween_method(
				func(a: float): mat.albedo_color.a = a,
				0.0, 1.0, 0.15
			).set_delay(acc_delay)
			# 淡入完成后关闭透明 (性能优化)
			tw_fade.tween_callback(func():
				mat.albedo_color.a = 1.0
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			)

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

		# 淡出 (通过材质 alpha)
		var mat: StandardMaterial3D = _get_card_mat(pos.x, pos.y)
		if mat:
			var tw_fade: Tween = m.create_tween()
			tw_fade.tween_callback(func():
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			).set_delay(fly_delay)
			tw_fade.tween_method(
				func(a: float): mat.albedo_color.a = a,
				1.0, 0.0, fly_dur
			).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

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

## 播放驱魔变形动画
func play_exorcise_animation(row: int, col: int, on_complete: Callable) -> void:
	var card_node: MeshInstance3D = get_card_node(row, col)
	if not card_node:
		on_complete.call()
		return

	var target_pos: Vector3 = card_node.position
	var tw: Tween = m.create_tween()
	# 缩小 + 升起
	tw.tween_property(card_node, "scale", Vector3(0.6, 1.5, 0.6), 0.15) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(card_node, "position:y", target_pos.y + 0.15, 0.15) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# 更新视觉
	tw.tween_callback(func(): update_card_visual(row, col))
	# 放大弹回
	tw.tween_property(card_node, "scale", Vector3(1.15, 1.15, 1.15), 0.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(card_node, "position:y", target_pos.y, 0.15)
	tw.tween_property(card_node, "scale", Vector3.ONE, 0.1)
	tw.tween_callback(on_complete)

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
	var base_y: float = CARD_Y + TOKEN_HOVER_Y
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

## 幽灵渲染参数 (匹配 Lua: nodeY=0.25, bb.position.y=0.15, bb.size=0.30)
const GHOST_BASE_Y: float = 0.40     # 中心高度 = 0.25 + 0.15
const GHOST_WORLD_SIZE: float = 0.30  # 世界空间尺寸 (米)
const GHOST_FLOAT_AMP: float = 0.04   # 浮动振幅
const GHOST_FLOAT_SPEED: float = 2.5  # 浮动频率

## 为当前暗面层创建幽灵 Sprite3D 节点
func create_ghost_nodes(ghosts: Array) -> void:
	destroy_ghost_nodes()
	for i in range(ghosts.size()):
		var ghost: DarkWorld.GhostData = ghosts[i]
		if not ghost.alive:
			continue

		var tex_path: String = DarkWorld.GHOST_TEXTURES[ghost.tex_index]
		var tex: Texture2D = load(tex_path)
		if not tex:
			continue

		var sprite: Sprite3D = Sprite3D.new()
		sprite.name = "Ghost_%d" % i
		sprite.texture = tex
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.transparent = true
		sprite.no_depth_test = false
		sprite.render_priority = 2

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

# ---------------------------------------------------------------------------
# 暗面 NPC 3D 节点 (Sprite3D billboard, 匹配 Lua DarkWorld.createNPCNodes)
# ---------------------------------------------------------------------------

const NPC_BASE_Y: float = 0.43   # node Y=0.25 + billboard offset Y=0.18
const NPC_WORLD_SIZE: float = 0.35
const NPC_OFFSET_X: float = 0.15
const NPC_BREATHE_SPEED: float = 2.0
const NPC_BREATHE_AMP: float = 0.02

func create_npc_nodes(npcs: Array) -> void:
	destroy_npc_nodes()
	for i in range(npcs.size()):
		var npc: DarkWorld.DarkNPCData = npcs[i]
		var tex: Texture2D = load(npc.tex_path)
		if not tex:
			continue
		var sprite: Sprite3D = Sprite3D.new()
		sprite.name = "DarkNPC_%s" % npc.id
		sprite.texture = tex
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.transparent = true
		sprite.no_depth_test = false
		sprite.render_priority = 2
		var tex_max: float = maxf(float(tex.get_width()), float(tex.get_height()))
		sprite.pixel_size = NPC_WORLD_SIZE / tex_max if tex_max > 0.0 else 0.001
		var world_pos: Vector3 = m.board.grid_to_world(npc.row + 1, npc.col + 1)
		world_pos.x += NPC_OFFSET_X
		world_pos.y = NPC_BASE_Y
		sprite.position = world_pos
		add_child(sprite)
		_npc_nodes[i] = { "node": sprite }

func destroy_npc_nodes() -> void:
	for key in _npc_nodes:
		var data: Dictionary = _npc_nodes[key]
		var node = data.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_npc_nodes.clear()

func update_npc_visuals(game_time: float) -> void:
	var breathe: float = 1.0 + sin(game_time * NPC_BREATHE_SPEED) * NPC_BREATHE_AMP
	for key in _npc_nodes:
		var data: Dictionary = _npc_nodes[key]
		var node = data.get("node")
		if is_instance_valid(node):
			node.scale = Vector3(breathe, breathe, breathe)

# ---------------------------------------------------------------------------
# 棋盘叠层效果 (Phase 3 用 3D 节点替代 _draw)
# ---------------------------------------------------------------------------

## 暂时空实现: 道具/裂隙标记等叠层效果
func _update_overlays() -> void:
	pass

# ---------------------------------------------------------------------------
# 地标 / 安全区粒子特效
# ---------------------------------------------------------------------------

## 创建粒子用的不透明发光材质
func _create_particle_material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = false
	mat.render_priority = 2
	return mat

## 为指定卡牌挂载粒子特效 (landmark=金色光辉, home=白色光辉)
func _attach_glow_particles(card_node: MeshInstance3D, card_type: String) -> void:
	# 已有粒子则跳过
	if card_node.get_node_or_null("GlowParticles"):
		return

	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "GlowParticles"
	particles.emitting = true
	particles.amount = 12
	particles.lifetime = 1.8
	particles.explosiveness = 0.0
	particles.randomness = 0.3
	particles.visibility_aabb = AABB(Vector3(-0.5, -0.1, -0.6), Vector3(1.0, 0.8, 1.2))
	# 粒子从卡牌表面上方发射
	particles.position = Vector3(0, Card.CARD_THICKNESS / 2.0 + 0.02, 0)

	# 粒子材质
	if card_type == "landmark":
		particles.draw_pass_1 = _make_particle_quad_mesh(0.03)
		particles.material_override = _particle_mat_landmark
	else:
		particles.draw_pass_1 = _make_particle_quad_mesh(0.025)
		particles.material_override = _particle_mat_home

	# 粒子行为 (ProcessMaterial)
	var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 25.0
	proc.initial_velocity_min = 0.05
	proc.initial_velocity_max = 0.15
	proc.gravity = Vector3(0, 0.02, 0)  # 微弱上升力

	# 发射范围: 卡牌表面区域
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(Card.CARD_W * 0.35, 0.01, Card.CARD_H * 0.35)

	# 缩放动画: 从小到大再消失
	proc.scale_min = 0.6
	proc.scale_max = 1.2
	var scale_curve: CurveTexture = CurveTexture.new()
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(0.7, 0.8))
	curve.add_point(Vector2(1.0, 0.0))
	scale_curve.curve = curve
	proc.scale_curve = scale_curve

	# 颜色渐变: 从亮到透明
	var color_ramp: GradientTexture1D = GradientTexture1D.new()
	var gradient: Gradient = Gradient.new()
	if card_type == "landmark":
		gradient.set_color(0, Color(1.0, 0.88, 0.4, 0.9))   # 起始: 暖金色
		gradient.set_color(1, Color(1.0, 0.7, 0.2, 0.0))     # 结束: 淡出
	else:
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.7))     # 起始: 柔白
		gradient.set_color(1, Color(0.85, 0.9, 1.0, 0.0))    # 结束: 淡蓝消失
	color_ramp.gradient = gradient
	proc.color_ramp = color_ramp

	particles.process_material = proc
	card_node.add_child(particles)

	# 同时添加一个柔和的 OmniLight3D 光源
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "GlowLight"
	light.position = Vector3(0, 0.15, 0)
	light.omni_range = 0.6
	light.light_energy = 0.4
	if card_type == "landmark":
		light.light_color = Color(1.0, 0.85, 0.4)
	else:
		light.light_color = Color(0.9, 0.95, 1.0)
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	card_node.add_child(light)

## 移除卡牌上的粒子特效
func _remove_glow_particles(card_node: MeshInstance3D) -> void:
	var particles: Node = card_node.get_node_or_null("GlowParticles")
	if particles:
		particles.queue_free()
	var light: Node = card_node.get_node_or_null("GlowLight")
	if light:
		light.queue_free()

## 创建粒子用的微型四边形 Mesh
func _make_particle_quad_mesh(size: float) -> QuadMesh:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size)
	return quad

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
