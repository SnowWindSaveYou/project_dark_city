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

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func setup(main_ref) -> void:
	m = main_ref
	board_layer = m._board_layer

	# 创建共享 BoxMesh
	_card_mesh = BoxMesh.new()
	_card_mesh.size = Vector3(Card.CARD_W, Card.CARD_THICKNESS, Card.CARD_H)

# ---------------------------------------------------------------------------
# 卡牌节点创建 (全量重建)
# ---------------------------------------------------------------------------

## 清空并重新创建所有 3D 卡牌
func rebuild_card_nodes() -> void:
	for child in board_layer.get_children():
		child.queue_free()
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

	if card.is_flipped:
		var type_info: Dictionary = GameTheme.card_type_info(card.type)
		mat.albedo_color = type_info.get("color", GameTheme.card_face)
		if card.scouted:
			mat.albedo_color = mat.albedo_color.lightened(0.15)
	else:
		mat.albedo_color = GameTheme.card_back

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
	else:
		mat.albedo_color = GameTheme.card_back_dark

# ---------------------------------------------------------------------------
# Token 精灵更新 (Sprite3D billboard)
# ---------------------------------------------------------------------------

## Token 悬浮高度 (Sprite3D 中心点到卡面的距离)
const TOKEN_HOVER_Y: float = 0.28
## 像素→世界单位的换算 (与 Sprite3D.pixel_size 保持一致)
const TOKEN_PX_TO_WORLD: float = 0.005

func update_token_visual() -> void:
	var token: Token = m.token
	if not token.visible:
		m._token_sprite.visible = false
		return

	m._token_sprite.visible = true
	var tex: Texture2D = token.get_current_texture()
	if tex:
		m._token_sprite.texture = tex

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
# 翻牌动画 (绕 Y 轴旋转 180°)
# ---------------------------------------------------------------------------

## 播放翻牌动画, 完成后调用 on_complete
func play_flip_animation(row: int, col: int, on_complete: Callable) -> void:
	var card_node: MeshInstance3D = get_card_node(row, col)
	if not card_node:
		on_complete.call()
		return

	var tw: Tween = m.create_tween()
	# 前半: 旋转到 90° (侧面)
	tw.tween_property(card_node, "rotation_degrees:y", 90.0, FLIP_HALF_DUR) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# 中间: 更换颜色
	tw.tween_callback(func(): update_card_visual(row, col))
	# 后半: 旋转到 180° (完成翻面)
	tw.tween_property(card_node, "rotation_degrees:y", 180.0, FLIP_HALF_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(on_complete)

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

## 播放翻回动画 (拍照侦察后)
func play_flip_back_animation(row: int, col: int) -> void:
	var card_node: MeshInstance3D = get_card_node(row, col)
	if not card_node:
		return
	var tw: Tween = m.create_tween()
	tw.tween_property(card_node, "rotation_degrees:y", 90.0, 0.1)
	tw.tween_callback(func(): update_card_visual(row, col))
	tw.tween_property(card_node, "rotation_degrees:y", 0.0, 0.1)

# ---------------------------------------------------------------------------
# Token 移动动画
# ---------------------------------------------------------------------------

## Token 移动到目标格 (3D 世界坐标), 完成后调用 on_arrive
func animate_token_move(row: int, col: int, on_arrive: Callable) -> void:
	var world_pos: Vector3 = get_card_world_pos(row, col)
	world_pos.y = CARD_Y + TOKEN_HOVER_Y
	var tween: Tween = m.create_tween()
	tween.tween_property(m._token_sprite, "position", world_pos, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(on_arrive)

# ---------------------------------------------------------------------------
# 棋盘叠层效果 (Phase 3 用 3D 节点替代 _draw)
# ---------------------------------------------------------------------------

## 暂时空实现: 安全光晕/道具/裂隙标记等叠层效果
## 将在 Phase 3 中用 OmniLight3D / Sprite3D 替代
func _update_overlays() -> void:
	pass

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
