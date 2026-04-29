## DarkWorldFlow - 暗面世界流程控制器
## 负责: 暗面进出(棋盘保存/交换/恢复)、层间移动、
##       暗面卡牌翻牌效果分发、幽灵碰撞处理、暗面相机驱除
extends RefCounted

# ---------------------------------------------------------------------------
# 引用 (由 main.gd 注入)
# ---------------------------------------------------------------------------
var m = null

# ---------------------------------------------------------------------------
# 暗面世界状态
# ---------------------------------------------------------------------------
## 保存的现实棋盘 (进入暗面时保存, 退出时恢复)
var _saved_board: Board = null
## 保存的现实 token 位置
var _saved_token_row: int = 0
var _saved_token_col: int = 0

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func setup(main_ref) -> void:
	m = main_ref
	# 注入退出回调
	m.dark_world.exit_request_callback = func(): on_dark_exit_requested()

# =========================================================================
# 进入暗面
# =========================================================================

func enter_dark_world(rift_row: int, rift_col: int) -> void:
	if not m.dark_world.can_enter(m.day_count):
		m._vfx.action_banner("裂隙能量不足", Color(0.7, 0.7, 0.7), 0.7)
		return

	GameData.set_demo_state("transition")

	# 清除所有 MonsterGhost chibi (进入暗面前)
	m.board_visual.mg_clear_all()

	# 隐藏 Token + 手牌面板
	m.token.visible = false
	m.token.alpha = 0.0
	m._hand_panel.hide_panel()

	# 保存现实棋盘
	_saved_board = m.board
	_saved_token_row = m.token.target_row
	_saved_token_col = m.token.target_col

	# 进入暗面
	m.dark_world.enter(m.day_count, rift_row, rift_col, func():
		_on_dark_exit_complete()
	)

	# 收牌动画 → 重建暗面棋盘 → 发牌动画
	m.board_visual.play_undeal_animation(func():
		# 清理现实世界物品节点
		m.board_visual.destroy_item_nodes()

		# 生成暗面棋盘
		_generate_dark_board()

		# UI 切换到暗面模式
		m._resource_bar.set_dark_mode(true, {
			"layer_name": m.dark_world.get_layer_name(),
			"energy": m.dark_world.get_energy(),
			"max_energy": CardConfig.get_dw_max_energy(),
		})
		m._camera_button.show_button()

		# 背景变暗
		m._bg_transition_target = 1.0

		# 发牌
		GameData.set_demo_state("dealing")
		m.board_visual.start_deal_animation(func():
			m.dark_world.on_enter_complete()
			_on_dark_deal_complete()
		)
	)

func _generate_dark_board() -> void:
	var layer_idx: int = m.dark_world.current_layer
	var layer_data = m.dark_world.get_layer_data()

	# 生成幽灵/NPC (如果该层还没生成过)
	if not layer_data.generated:
		# 先生成卡牌地图
		m.board = Board.new()
		var dark_config: Dictionary = m.dark_world.get_dark_config(layer_idx)
		var dark_locs: Dictionary = m.dark_world.get_dark_locations(layer_idx)

		# 将 LayerData 转为 Board.generate_dark_cards 需要的 dict
		var ld_dict: Dictionary = {
			"walkable": {},
			"entry_row": 3,
			"entry_col": 3,
			"collected": layer_data.collected,
		}
		m.board.generate_dark_cards(ld_dict, dark_locs, dark_config)

		# 回写 walkable 到 LayerData
		var walkable: Array = ld_dict.get("walkable", [])
		for r in range(walkable.size()):
			for c in range(walkable[r].size()):
				var key: String = "%d,%d" % [r, c]
				layer_data.walkable[key] = walkable[r][c]

		# 生成幽灵和 NPC
		m.dark_world.generate_overlay_data(layer_idx)
	else:
		# 层已生成, 复用已有数据重建 Board
		m.board = Board.new()
		var dark_config: Dictionary = m.dark_world.get_dark_config(layer_idx)
		var dark_locs: Dictionary = m.dark_world.get_dark_locations(layer_idx)
		var ld_dict: Dictionary = {
			"walkable": {},
			"entry_row": 3,
			"entry_col": 3,
			"collected": layer_data.collected,
		}
		m.board.generate_dark_cards(ld_dict, dark_locs, dark_config)

	m.board_visual.rebuild_card_nodes()

	# 隐藏墙壁节点
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			m.board_visual.update_dark_card_visual(r, c)

func _on_dark_deal_complete() -> void:
	GameData.set_demo_state("dark_world")

	# Token 出现在玩家当前位置 (首次=入口, 换层后=上次位置)
	var layer_data = m.dark_world.get_layer_data()
	var pr: int = layer_data.player_row + 1  # 0-based → 1-based
	var pc: int = layer_data.player_col + 1
	m.token.target_row = pr
	m.token.target_col = pc
	m.token.visible = true
	m.token.alpha = 1.0
	m.token.set_emotion("nervous")
	m.board_visual.update_token_visual()

	# 创建幽灵 & NPC 3D 节点
	m.board_visual.create_ghost_nodes(layer_data.ghosts)
	m.board_visual.create_npc_nodes(layer_data.npcs)

	# 翻开玩家所在卡牌
	var entry_card: Card = m.board.get_card(pr, pc)
	if entry_card:
		m.board.flip_card(pr, pc)
		m.board_visual.update_dark_card_visual(pr, pc)

# =========================================================================
# 暗面卡牌交互
# =========================================================================

func handle_dark_card_click(row: int, col: int) -> void:
	if m.dark_world.dark_state != "ready":
		return

	var card: Card = m.board.get_card(row, col)
	if card == null:
		return

	# 相机模式
	if m._camera_button.is_camera_mode():
		_handle_dark_camera(row, col)
		return

	var layer_data = m.dark_world.get_layer_data()
	var player_row: int = layer_data.player_row  # 0-based
	var player_col: int = layer_data.player_col

	# 转换为 0-based 用于 DarkWorld API
	var target_r0: int = row - 1
	var target_c0: int = col - 1

	# 点击当前格: NPC 对话 (与明面琴馨一致 — 点击触发)
	var is_current: bool = (target_r0 == player_row and target_c0 == player_col)
	if is_current:
		var npc_data: Dictionary = m.dark_world.get_npc_at(target_r0, target_c0)
		if not npc_data.is_empty() and m._dialogue_system:
			m.dark_world.dark_state = "popup"
			m.token.set_emotion("surprised")
			m._dialogue_system.start(
				npc_data["dialogue"],
				npc_data.get("tex", ""),
				func(): m.dark_world.set_ready()
			)
		return

	# 检查是否可移动
	var move_result: Dictionary = m.dark_world.try_move(target_r0, target_c0)
	if not move_result["can_move"]:
		if move_result["reason"] == "no_energy":
			m._vfx.action_banner("能量耗尽!", Color(0.86, 0.31, 0.31), 0.7)
			m._resource_bar.flash_dark_energy()
			m.dark_world.request_exit()
		elif move_result["reason"] == "not_adjacent":
			m._vfx.action_banner("只能移动到相邻格", Color(0.7, 0.7, 0.7), 0.6)
		return

	# 消耗能量
	var old: Dictionary = m.dark_world.consume_move(target_r0, target_c0)

	# 更新能量 UI
	m._resource_bar.update_dark_energy(
		m.dark_world.get_energy(), CardConfig.get_dw_max_energy())

	# Token 移动
	m.token.target_row = row
	m.token.target_col = col
	m.token.set_emotion("running")

	m.board_visual.animate_token_move(row, col, func():
		# 完成移动
		m.dark_world.on_move_complete(target_r0, target_c0)

		# 幽灵移动 + 碰撞
		var collisions: Array = m.dark_world.move_ghosts(
			target_r0, target_c0, old["old_row"], old["old_col"])
		_animate_alive_ghost_moves()
		_process_ghost_collisions(collisions)

		# 直接碰撞检测
		var direct_collision = m.dark_world.check_ghost_collision(target_r0, target_c0)
		if direct_collision:
			_process_single_ghost_collision(direct_collision)

		# 暗面卡牌效果 (暗面卡牌全明牌, 不需要翻牌检查)
		var arrived_card: Card = m.board.get_card(row, col)
		if arrived_card:
			_handle_dark_card_effect(arrived_card, row, col)
		else:
			m.token.set_emotion("default")
			m.dark_world.set_ready()

		# 移动后能量耗尽 → 延迟退出 (匹配 Lua: 0.8s 后 requestExit)
		if m.dark_world.get_energy() <= 0:
			var tw_exit: Tween = m.create_tween()
			tw_exit.tween_interval(0.8)
			tw_exit.tween_callback(func():
				m._vfx.action_banner("⚡ 能量耗尽，被迫返回!",
					Color(0.86, 0.47, 0.31), 1.0)
				m.dark_world.request_exit()
			)
	)

# ---------------------------------------------------------------------------
# 暗面卡牌效果
# ---------------------------------------------------------------------------

func _handle_dark_card_effect(card: Card, row: int, col: int) -> void:
	var effect: Dictionary = m.dark_world.handle_card_effect(card, row, col, m.day_count)
	var effect_type: String = effect["type"]

	match effect_type:
		"none":
			m.token.set_emotion("default")
			m.dark_world.set_ready()

		"npc_dialogue":
			# 不自动触发对话 — 玩家需要再次点击当前格 (与明面琴馨一致)
			var npc_name: String = effect["data"].get("npc_name", "NPC")
			m.token.set_emotion("surprised")
			m._vfx.action_banner("💬 点击与 %s 对话" % npc_name,
				Color(0.6, 0.8, 0.9), 0.8)
			m.dark_world.set_ready()

		"shop":
			m.token.set_emotion("confused")
			m._shop_popup.open_shop()

		"intel":
			var cost: int = effect["data"].get("cost", 15)
			if GameData.get_resource("money") >= cost:
				GameData.modify_resource("money", -cost)
				# 添加传闻
				m.card_manager.add_rumor_from_board(m.board)
				m._vfx.action_banner("获得情报! -$%d" % cost, Color(0.5, 0.7, 0.9), 0.8)
			else:
				m._vfx.action_banner("金钱不足", Color(0.86, 0.63, 0.31), 0.7)
			m.dark_world.set_ready()

		"checkpoint":
			m._vfx.action_banner("检查点", Color(0.7, 0.6, 0.4), 0.8)
			m.dark_world.set_ready()

		"clue":
			var clue_name: String = effect["data"].get("name", "线索")
			# 尝试从 StoryManager 选择条件化暗世界线索事件
			var dark_evt: Dictionary = StoryManager.pick_dark_clue_event()
			if not dark_evt.is_empty():
				var result: Dictionary = StoryManager.apply_event_effects(dark_evt)
				if result["is_new_clue"]:
					m._vfx.action_banner("获得线索: %s" % result["clue_name"],
						Color(0.5, 0.8, 0.6), 1.0)
				else:
					m._vfx.action_banner("发现线索: %s" % clue_name,
						Color(0.6, 0.8, 0.5), 0.8)
			else:
				m._vfx.action_banner("发现线索: %s" % clue_name,
					Color(0.6, 0.8, 0.5), 0.8)
			m._vfx.spawn_burst(m.board_visual.get_card_center(row, col), 10, Color(0.6, 0.8, 0.5))
			GameData.modify_resource("san", 1)
			m.dark_world.set_ready()

		"item":
			var res_key: String = effect["data"].get("resource", "money")
			var amount: int = effect["data"].get("amount", 10)
			GameData.modify_resource(res_key, amount)
			m._vfx.action_banner("获得 %s +%d" % [res_key, amount], Color(0.8, 0.7, 0.3), 0.8)
			m._vfx.spawn_burst(m.board_visual.get_card_center(row, col), 8, Color(0.8, 0.7, 0.3))
			m.dark_world.set_ready()

		"passage":
			var target_layer: int = effect["data"].get("target_layer", -1)
			if target_layer >= 0:
				_change_layer(target_layer)
			else:
				# L2 双通道 → 选择目标层
				m._vfx.action_banner("通道连接更深处...", Color(0.5, 0.4, 0.7), 0.8)
				_change_layer(2)  # 默认往更深走

		"abyss_core":
			m._vfx.action_banner("🌑 深渊核心...", Color(0.3, 0.1, 0.5), 1.0)
			m._vfx.screen_flash(Color(0.3, 0.1, 0.5, 0.6), 0.5)
			m._vfx.screen_shake(5.0, 0.3)
			m.dark_world.set_ready()

		_:
			m.dark_world.set_ready()

# ---------------------------------------------------------------------------
# 幽灵 3D 渲染辅助
# ---------------------------------------------------------------------------

## 查找幽灵在当前层 ghosts 数组中的索引
func _find_ghost_index(ghost: DarkWorld.GhostData) -> int:
	var layer_data = m.dark_world.get_layer_data()
	if not layer_data:
		return -1
	for i in range(layer_data.ghosts.size()):
		if layer_data.ghosts[i] == ghost:
			return i
	return -1

## 动画: 所有存活幽灵平滑移动到数据层的新位置
func _animate_alive_ghost_moves() -> void:
	var layer_data = m.dark_world.get_layer_data()
	if not layer_data:
		return
	for i in range(layer_data.ghosts.size()):
		var ghost: DarkWorld.GhostData = layer_data.ghosts[i]
		if ghost.alive:
			m.board_visual.animate_ghost_move(i, ghost.row, ghost.col, 0.35)

# ---------------------------------------------------------------------------
# 幽灵碰撞处理
# ---------------------------------------------------------------------------

func _process_ghost_collisions(collisions: Array) -> void:
	for ghost in collisions:
		_process_single_ghost_collision(ghost)

func _process_single_ghost_collision(ghost: DarkWorld.GhostData) -> void:
	GameData.modify_resource("san", CardConfig.get_dw_ghost_san_damage())
	m._vfx.screen_flash(Color(0.5, 0.1, 0.6, 0.6), 0.3)
	m._vfx.screen_shake(4.0, 0.2)
	m.token.set_emotion("scared")
	m.token.hop(0.04)

	var ghost_idx: int = _find_ghost_index(ghost)
	if ghost_idx >= 0:
		m.board_visual.animate_ghost_fade(ghost_idx)

	m._vfx.action_banner("幽灵接触! SAN %d" % CardConfig.get_dw_ghost_san_damage(),
		Color(0.7, 0.2, 0.8), 0.8)

	m.game_flow.check_defeat()

# ---------------------------------------------------------------------------
# 暗面相机驱魔
# ---------------------------------------------------------------------------

func _handle_dark_camera(row: int, col: int) -> void:
	var film: int = GameData.get_resource("film")
	if film <= 0:
		m._vfx.action_banner("胶卷不足!", Color(0.86, 0.31, 0.31), 0.8)
		m._camera_button.shake_no_film()
		return

	# 0-based 坐标
	var ghost = m.dark_world.handle_camera_shot(row - 1, col - 1)
	if ghost:
		GameData.modify_resource("film", -1)
		GameData.photos_used += 1
		GameData.monsters_slain += 1

		m._camera_button.exit_camera_mode()
		m._vfx.screen_flash(Color.WHITE, 0.5)
		m._vfx.screen_shake(3.0, 0.15)
		m.token.hop(0.05)

		var cam_ghost_idx: int = _find_ghost_index(ghost)
		if cam_ghost_idx >= 0:
			m.board_visual.animate_ghost_fade(cam_ghost_idx)

		var center: Vector2 = m.board_visual.get_card_center(row, col)
		m._vfx.spawn_burst(center, 12, Color(0.7, 0.3, 0.9))
		m._vfx.action_banner("驱除幽灵!", Color(0.7, 0.3, 0.9), 0.8)
	else:
		m._vfx.action_banner("这里没有幽灵", Color(0.7, 0.7, 0.7), 0.6)

# =========================================================================
# 层间移动
# =========================================================================

func _change_layer(target_layer: int) -> void:
	var result: Dictionary = m.dark_world.begin_change_layer(target_layer, m.day_count)
	if not result["success"]:
		m._vfx.action_banner("该层尚未解锁", Color(0.7, 0.5, 0.3), 0.7)
		m.dark_world.set_ready()
		return

	GameData.set_demo_state("transition")

	m._vfx.action_banner("进入 %s" % result["layer_name"], Color(0.6, 0.4, 0.8), 1.0)
	m._vfx.screen_flash(Color(0.3, 0.1, 0.5, 0.5), 0.4)

	# 隐藏 Token
	m.token.visible = false
	m.token.alpha = 0.0

	# 收牌动画 → 清理 → 重建新层 → 发牌动画
	m.board_visual.play_undeal_animation(func():
		# 清理旧层幽灵 & NPC 节点
		m.board_visual.destroy_ghost_nodes()
		m.board_visual.destroy_npc_nodes()

		# 重新生成棋盘
		_generate_dark_board()

		# 更新 UI
		m._resource_bar.update_dark_energy(
			m.dark_world.get_energy(), CardConfig.get_dw_max_energy())

		# 发牌
		GameData.set_demo_state("dealing")
		m.board_visual.start_deal_animation(func():
			m.dark_world.on_change_layer_complete()
			_on_dark_deal_complete()
		)
	)

# =========================================================================
# 退出暗面
# =========================================================================

func on_dark_exit_requested() -> void:
	if m.dark_world.dark_state != "ready":
		return

	GameData.set_demo_state("transition")
	m.dark_world.begin_exit()

	# 隐藏 Token
	m.token.visible = false
	m.token.alpha = 0.0

	# 收牌动画 → 清理 → 重建现实棋盘 → 发牌动画
	m.board_visual.play_undeal_animation(func():
		# 清理幽灵 & NPC 节点
		m.board_visual.destroy_ghost_nodes()
		m.board_visual.destroy_npc_nodes()

		# 恢复现实棋盘
		m.board = _saved_board
		_saved_board = null
		m.board_visual.rebuild_card_nodes()

		# UI 切回正常模式
		m._resource_bar.set_dark_mode(false)

		# 恢复大气
		var daily_rev: int = GameData.cards_revealed - GameData.day_start_revealed
		m._bg_transition_target = minf(float(daily_rev) / 8.0, 1.0)

		# 发牌动画
		GameData.set_demo_state("dealing")
		m.board_visual.start_deal_animation(func():
			# 恢复 Token 位置
			m.token.target_row = _saved_token_row
			m.token.target_col = _saved_token_col
			m.token.visible = true
			m.token.alpha = 1.0
			m.token.set_emotion("relieved")
			m.board_visual.update_token_visual()

			# 更新所有卡牌视觉
			for r in range(1, Board.ROWS + 1):
				for c in range(1, Board.COLS + 1):
					m.board_visual.update_card_visual(r, c)

			# 完成退出
			m.dark_world.on_exit_complete()
			GameData.set_demo_state("ready")
			m._hand_panel.show_panel()
		)
	)

func _on_dark_exit_complete() -> void:
	# 由 DarkWorld._on_exit 回调触发
	pass

# =========================================================================
# 暗面 UI 回调
# =========================================================================

func on_dark_shop_closed() -> void:
	m.dark_world.set_ready()
