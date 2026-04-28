## BoardVisual - 棋盘渲染层
## 负责: 卡牌 ColorRect 节点管理、视觉更新、发牌/收牌动画、
##       Token 渲染、棋盘道具/安全光晕/NPC/暗面幽灵叠层绘制
## 作为 Node2D 子节点挂在 Main 下方, z_index = 2
extends Node2D

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const CARD_PX_W: float = 90.0
const CARD_PX_H: float = 126.0
const CARD_PX_GAP: float = 8.0

## 安全光晕
const SAFE_GLOW_RADIUS: float = 18.0
const SAFE_GLOW_COLOR: Color = Color(0.35, 0.75, 0.45, 0.25)

## 棋盘道具
const ITEM_ICON_SIZE: float = 20.0
const ITEM_GLOW_RADIUS: float = 14.0

# ---------------------------------------------------------------------------
# 引用 (由 main.gd 注入)
# ---------------------------------------------------------------------------
var m = null  # 主场景引用 (untyped 避免循环依赖)

# ---------------------------------------------------------------------------
# 缓存
# ---------------------------------------------------------------------------
## 卡牌节点容器 (即 main._board_layer)
var board_layer: Node2D = null
## 牌堆起始位置
var deck_spawn_pos: Vector2 = Vector2.ZERO
## 屏幕尺寸缓存
var _screen_size: Vector2 = Vector2.ZERO

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func setup(main_ref) -> void:
	m = main_ref
	board_layer = m._board_layer
	_screen_size = m.get_viewport_rect().size

# ---------------------------------------------------------------------------
# 卡牌节点创建 (全量重建)
# ---------------------------------------------------------------------------

## 清空并重新创建所有卡牌 ColorRect
func rebuild_card_nodes() -> void:
	for child in board_layer.get_children():
		child.queue_free()

	_screen_size = m.get_viewport_rect().size
	var board_center: float = _screen_size * 0.5
	deck_spawn_pos = Vector2(_screen_size.x + 60, -60)

	var total_w: float = Board.COLS * (CARD_PX_W + CARD_PX_GAP) - CARD_PX_GAP
	var total_h: float = Board.ROWS * (CARD_PX_H + CARD_PX_GAP) - CARD_PX_GAP
	var start_x: float = board_center.x - total_w * 0.5
	var start_y: float = board_center.y - total_h * 0.5 - 30

	for r in range(Board.ROWS):
		for c in range(Board.COLS):
			var card: Card = m.board.get_card(r + 1, c + 1)
			if card == null:
				continue

			var card_node: ColorRect = ColorRect.new()
			card_node.name = "Card_%d_%d" % [r + 1, c + 1]
			card_node.size = Vector2(CARD_PX_W, CARD_PX_H)

			var target_pos: Vector2 = Vector2(
				start_x + c * (CARD_PX_W + CARD_PX_GAP),
				start_y + r * (CARD_PX_H + CARD_PX_GAP)
			)
			card_node.position = target_pos
			card_node.color = GameTheme.card_back
			card_node.set_meta("row", r + 1)
			card_node.set_meta("col", c + 1)
			card_node.set_meta("target_pos", target_pos)
			board_layer.add_child(card_node)

# ---------------------------------------------------------------------------
# 卡牌节点查询
# ---------------------------------------------------------------------------

func get_card_node(row: int, col: int) -> ColorRect:
	var card_name: String = "Card_%d_%d" % [row, col]
	return board_layer.get_node_or_null(card_name) as ColorRect

func get_card_center(row: int, col: int) -> Vector2:
	var card_node: ColorRect = get_card_node(row, col)
	if card_node:
		return card_node.position + card_node.size * 0.5
	return _screen_size * 0.5

# ---------------------------------------------------------------------------
# 卡牌视觉更新
# ---------------------------------------------------------------------------

func update_card_visual(row: int, col: int) -> void:
	var card_node: ColorRect = get_card_node(row, col)
	if not card_node:
		return

	var card: Card = m.board.get_card(row, col)
	if card == null:
		return

	if card.is_flipped:
		var type_info: Dictionary = GameTheme.card_type_info(card.type)
		card_node.color = type_info.get("color", GameTheme.card_face)
		if card.scouted:
			card_node.color = card_node.color.lightened(0.15)
	else:
		card_node.color = GameTheme.card_back

## 暗面世界卡牌视觉 (墙壁=null → 隐藏节点)
func update_dark_card_visual(row: int, col: int) -> void:
	var card_node: ColorRect = get_card_node(row, col)
	if not card_node:
		return

	var card: Card = m.board.get_card(row, col)
	if card == null:
		card_node.visible = false
		return

	card_node.visible = true
	if card.is_flipped:
		var dark_color: Color = GameTheme.dark_card_type_color(card.dark_type)
		card_node.color = dark_color
	else:
		card_node.color = GameTheme.card_back_dark

# ---------------------------------------------------------------------------
# Token 精灵更新
# ---------------------------------------------------------------------------

func update_token_visual() -> void:
	var token: Token = m.token
	if not token.visible:
		m._token_sprite.visible = false
		return

	m._token_sprite.visible = true
	var tex: Texture2D = token.get_current_texture()
	if tex:
		m._token_sprite.texture = tex

	var base_pos: Vector2 = get_card_center(token.target_row, token.target_col)

	# 呼吸动画
	var breathe: Dictionary = token.get_breathe_offset(m.game_time)
	base_pos.y += breathe["y"]
	base_pos.y += token.bounce_y

	m._token_sprite.position = base_pos
	m._token_sprite.modulate.a = token.alpha
	m._token_sprite.scale = Vector2(token.squash_x, token.squash_y)

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
		var card_node: ColorRect = get_card_node(pos.x, pos.y)
		if card_node == null:
			continue

		var target_pos: Vector2 = card_node.get_meta("target_pos")

		# 起始: 牌堆位置, 透明, 缩小
		card_node.position = deck_spawn_pos
		card_node.modulate.a = 0.0
		card_node.scale = Vector2(0.4, 0.4)
		card_node.visible = true

		var fly_dur: float = 0.35

		# 淡入
		var tw: Tween = m.create_tween()
		tw.tween_property(card_node, "modulate:a", 1.0, 0.15).set_delay(acc_delay)

		# 飞行
		var tw2: Tween = m.create_tween()
		tw2.tween_property(card_node, "position", target_pos, fly_dur) \
			.set_delay(acc_delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

		# 缩放
		var tw3: Tween = m.create_tween()
		tw3.tween_property(card_node, "scale", Vector2.ONE, fly_dur) \
			.set_delay(acc_delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

		# 弹跳
		var bounce_delay: float = acc_delay + fly_dur * 0.6
		var tw4: Tween = m.create_tween()
		tw4.tween_property(card_node, "scale", Vector2(1.08, 0.92), 0.1) \
			.set_delay(bounce_delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw4.tween_property(card_node, "scale", Vector2.ONE, 0.1) \
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
# 翻牌动画 (缩放模拟)
# ---------------------------------------------------------------------------

## 播放翻牌动画, 完成后调用 on_complete
func play_flip_animation(row: int, col: int, on_complete: Callable) -> void:
	var card_node: ColorRect = get_card_node(row, col)
	if not card_node:
		on_complete.call()
		return

	var tw: Tween = m.create_tween()
	tw.tween_property(card_node, "scale:x", 0.0, 0.12) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): update_card_visual(row, col))
	tw.tween_property(card_node, "scale:x", 1.0, 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(on_complete)

## 播放驱魔变形动画
func play_exorcise_animation(row: int, col: int, on_complete: Callable) -> void:
	var card_node: ColorRect = get_card_node(row, col)
	if not card_node:
		on_complete.call()
		return

	var tw: Tween = m.create_tween()
	tw.tween_property(card_node, "scale", Vector2(0.6, 0.6), 0.15) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): update_card_visual(row, col))
	tw.tween_property(card_node, "scale", Vector2(1.15, 1.15), 0.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(card_node, "scale", Vector2.ONE, 0.1)
	tw.tween_callback(on_complete)

## 播放翻回动画 (拍照侦察后)
func play_flip_back_animation(row: int, col: int) -> void:
	var card_node: ColorRect = get_card_node(row, col)
	if not card_node:
		return
	var tw: Tween = m.create_tween()
	tw.tween_property(card_node, "scale:x", 0.0, 0.1)
	tw.tween_callback(func(): update_card_visual(row, col))
	tw.tween_property(card_node, "scale:x", 1.0, 0.1)

# ---------------------------------------------------------------------------
# Token 移动动画
# ---------------------------------------------------------------------------

## Token 移动到目标格, 完成后调用 on_arrive
func animate_token_move(row: int, col: int, on_arrive: Callable) -> void:
	var target_pos: Vector2 = get_card_center(row, col)
	var tween: Tween = m.create_tween()
	tween.tween_property(m._token_sprite, "position", target_pos, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(on_arrive)

# ---------------------------------------------------------------------------
# 棋盘叠层绘制 (_draw)
# ---------------------------------------------------------------------------

func _draw() -> void:
	if m == null:
		return
	_draw_safe_glow()
	_draw_board_items()
	_draw_rift_marks()

## 安全光晕 (地标相邻格子底部发光)
func _draw_safe_glow() -> void:
	if m.board == null:
		return
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			if m.board.is_in_landmark_aura(r, c):
				var center: Vector2 = get_card_center(r, c)
				center.y += CARD_PX_H * 0.4
				draw_circle(center, SAFE_GLOW_RADIUS, SAFE_GLOW_COLOR)

## 棋盘道具图标 (浮动 emoji)
func _draw_board_items() -> void:
	if m.board_items == null:
		return
	for item in m.board_items.items:
		if item.collected or item.alpha <= 0.01:
			continue
		var center: Vector2 = get_card_center(item.row, item.col)
		var float_offset: float = sin(m.game_time * BoardItems.FLOAT_SPEED + item.phase) * BoardItems.FLOAT_AMP
		center.y += float_offset - 10.0  # 偏上显示

		# 光晕
		if item.glow_alpha > 0.01:
			var glow_color: Color = Color(1.0, 0.9, 0.5, item.glow_alpha * 0.3)
			draw_circle(center, ITEM_GLOW_RADIUS * item.scale, glow_color)

		# 图标 (用 draw_string 绘制 emoji)
		if item.alpha > 0.01:
			var font: Font = ThemeDB.fallback_font
			var fsize: int = int(ITEM_ICON_SIZE * item.scale)
			if font and fsize > 0:
				var text_pos: float = center - Vector2(float(fsize) * 0.3, -float(fsize) * 0.3)
				draw_string(font, text_pos, item.icon, HORIZONTAL_ALIGNMENT_CENTER,
					-1, fsize, Color(1, 1, 1, item.alpha))

## 裂隙标记 (未翻开的裂隙卡底部微光)
func _draw_rift_marks() -> void:
	if m.board == null:
		return
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = m.board.get_card(r, c)
			if card and card.has_rift and not card.is_flipped:
				var center: Vector2 = get_card_center(r, c)
				center.y += CARD_PX_H * 0.4
				var pulse: float = 0.15 + sin(m.game_time * 3.0) * 0.08
				var rift_color: Color = Color(0.6, 0.2, 0.8, pulse)
				draw_circle(center, 10.0, rift_color)

# ---------------------------------------------------------------------------
# 点击检测辅助
# ---------------------------------------------------------------------------

## 检测点击位置对应的棋盘格子, 返回 Vector2i (row, col) 或 Vector2i.ZERO
func hit_test(click_pos: Vector2) -> Vector2i:
	for child in board_layer.get_children():
		if child is ColorRect and child.visible:
			var rect: Rect2 = Rect2(child.position, child.size)
			if rect.has_point(click_pos):
				var row: int = child.get_meta("row", 0)
				var col: int = child.get_meta("col", 0)
				if row > 0 and col > 0:
					return Vector2i(row, col)
	return Vector2i.ZERO
