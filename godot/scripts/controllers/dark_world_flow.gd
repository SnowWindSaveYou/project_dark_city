## DarkWorldFlow - 暗面世界流程控制器
## 负责: 暗面进出(棋盘保存/交换/恢复)、层间移动、
##       暗面卡牌翻牌效果分发、幽灵碰撞处理、暗面相机驱除
##
## 事件处理: 统一使用 EventHandler 处理所有事件效果
extends RefCounted

# ---------------------------------------------------------------------------
# 引用 (由 main.gd 注入)
# ---------------------------------------------------------------------------
var m = null
var _event_handler: EventHandler = null

# ---------------------------------------------------------------------------
# 暗面世界状态
# ---------------------------------------------------------------------------
## 保存的现实棋盘 (进入暗面时保存, 退出时恢复)
var _saved_board: Board = null
## 保存的现实 token 位置
var _saved_token_row: int = 0
var _saved_token_col: int = 0
## 白夜是否跟随进入暗面 (trust>=3 且 available)
var _baiye_following: bool = false
## 保存的现实 NPC 快照 (进入暗面时保存, 退出时恢复)
var _saved_real_npcs: Dictionary = {}
## 暗面过渡中标志: enter/exit 动画期间为 true
## main.gd _process 用此标志屏蔽明面 BGM 自动切换, 避免覆盖 dark_world BGM
var is_dark_transitioning: bool = false

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func setup(main_ref) -> void:
	m = main_ref
	# 初始化事件处理器
	_event_handler = EventHandler.new()
	_event_handler.setup(main_ref)
	# 注入退出回调
	m.dark_world.exit_request_callback = func(): on_dark_exit_requested()

# =========================================================================
# 进入暗面
# =========================================================================

func enter_dark_world(rift_row: int, rift_col: int, force: bool = false) -> void:
	if not force and not m.dark_world.can_enter():
		m._vfx.action_banner("裂隙能量不足", Color(0.7, 0.7, 0.7), 0.7)
		return

	GameData.set_demo_state("transition")
	is_dark_transitioning = true   # 屏蔽 main.gd _process 的明面 BGM 自动切换
	AudioManager.play_sfx("dark_world_enter")
	AudioManager.play_bgm("dark_world")
	AudioManager.play_ambient("dark_ambient")

	# 判断白夜是否跟随 (trust>=3 且 available)
	_baiye_following = m._baiye != null and m._baiye.should_show()

	# 里程碑 hook: enter_dark_world
	var ms_event = MilestoneManager.try_trigger("enter_dark_world")
	if ms_event != null and m._dialogue_system:
		m._dialogue_system.start(ms_event.get("dialogue", []), "", "", func():
			MilestoneManager.on_event_complete(ms_event)
		)

	# 清除所有 MonsterGhost chibi + 裂隙 chibi (进入暗面前)
	m.board_visual.mg_clear_all()
	m.board_visual.rift_clear_all()
	# 进入暗面时隐藏目的地提示（暗面棋盘与现实无关）
	m.board_visual.clear_destination_hints()

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

		# 保存现实 NPC 快照 (只在初次进入时保存, 换层不覆盖)
		if _saved_real_npcs.is_empty():
			_saved_real_npcs = m.game_flow.npc_manager.npcs.duplicate()
		# 销毁现实 NPC 3D 节点 (避免它们在暗面中可见)
		m.board_visual.destroy_npc_nodes()

		# 生成暗面棋盘
		_generate_dark_board()

		# UI 切换到暗面模式
		m._resource_bar.set_dark_mode(true, {
			"layer_name": m.dark_world.get_layer_name(),
			"energy": m.dark_world.get_energy(),
			"max_energy": m.dark_world.get_max_energy(),
			"layer_idx": m.dark_world.current_layer + 1,
			"layer_count": 3,
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

		# 清除现实 NPC 数据，注入共享 manager 给暗面使用
		m.game_flow.npc_manager.clear()
		m.dark_world._npc_manager = m.game_flow.npc_manager
		m.dark_world.generate_overlay_data(layer_idx, m.board)
	else:
		# 层已生成: 恢复已保存的棋盘，避免重新随机生成导致暗币点位/卡牌状态丢失
		m.game_flow.npc_manager.clear()
		m.dark_world._npc_manager = m.game_flow.npc_manager
		m.dark_world.generate_npcs(layer_idx, m.game_flow.npc_manager, null)
		if layer_data.saved_board != null:
			m.board = layer_data.saved_board
		else:
			# 兜底: 没有保存棋盘则重新生成 (首次进入非当前层时的异常情况)
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
	is_dark_transitioning = false  # 进入完成, BGM 已稳定, 解除屏蔽
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
	m.board_visual.create_npc_nodes(m.game_flow.npc_manager.npcs)

	# 翻开玩家所在卡牌
	var entry_card: Card = m.board.get_card(pr, pc)
	if entry_card:
		m.board.flip_card(pr, pc)
		m.board_visual.update_dark_card_visual(pr, pc)

	# 刷新通道 chibi: 扫描所有已翻开的通道牌，符合条件则显示
	_refresh_passage_chibis()

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
				"",
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
		m.dark_world.get_energy(), m.dark_world.get_max_energy())

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
			await _handle_dark_card_effect(arrived_card, row, col)
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
# 暗面卡牌效果 (统一使用 EventHandler)
# ---------------------------------------------------------------------------

func _handle_dark_card_effect(card: Card, row: int, col: int) -> void:
	var result: EventHandler.EventResult = _event_handler.parse_dark_world_card(
		card, row, col, m.day_count)
	
	# 保存原始 dark_type，collect_card 会将其覆写为 "normal"
	var original_dark_type: String = card.dark_type
	
	# 特殊处理：标记收集状态
	if card.dark_collected and (card.dark_type == "clue" or card.dark_type == "item"):
		m.dark_world.collect_card(row, col, card)
	
	# 统一表情
	# 对于会立即触发弹窗的事件类型，直接赋值跳过 squash 动画
	# 避免 squash_x 压缩到 0 时角色变成"小方块"
	var emo: String = EventHandler.get_emotion_for_event(result.event_type)
	match result.event_type:
		EventHandler.EventType.CLUE, EventHandler.EventType.DARK_CLUE, \
		EventHandler.EventType.ABYSS_CORE:
			# 弹窗类事件：直接切换，不触发 squash 翻面动画
			m.token.emotion = emo
			m.token._pending_emotion = ""
		_:
			m.token.set_emotion(emo)
	
	# 根据事件类型处理
	match result.event_type:
		EventHandler.EventType.NONE:
			# 暗币点收集
			if card.dark_dot:
				card.dark_dot = false
				GameData.modify_resource("darkcoin", 1)
				m._vfx.action_banner("暗币 +1", Color(0.75, 0.45, 0.95), 0.7)
				m.board_visual.update_dark_card_visual(row, col)
			m.dark_world.set_ready()
		
		EventHandler.EventType.CLUE, EventHandler.EventType.DARK_CLUE:
			m._vfx.spawn_burst(m.board_visual.get_card_center(row, col), 10, Color(0.6, 0.8, 0.5))
			# 淡出 → 执行收集 → 淡入 (对齐 Lua collectCard 动画)
			m.board_visual.animate_dark_card_collect(row, col, func() -> void:
				_event_handler.execute_event(result, card)
			)
			# 碎片掉落检查
			var frag_id: String = m.dark_world.check_fragment_drop(
				StoryManager.get_fragment_count(), StoryManager.flags)
			if frag_id != "":
				var is_new: bool = StoryManager.collect_fragment(frag_id)
				if is_new:
					# 碎片掉落给 inspiration+1 (对齐 Lua 版本)
					GameData.modify_resource("inspiration", 1)
					var frag_info: Dictionary = StoryManager.get_fragment_info(frag_id)
					# 设置防重复 flag
					var drops: Array = CardConfig.get_dw_fragment_drops()
					for drop in drops:
						if drop.get("frag_id", "") == frag_id:
							var flag_key: String = drop.get("flag", "")
							if flag_key != "":
								StoryManager.set_flag(flag_key)
							break
					# 通过弹窗展示碎片全文，等待玩家关闭后再继续
					m.dark_world.dark_state = "popup"
					m._event_popup.show_fragment(frag_info)
					await m._event_popup.popup_closed
					m.dark_world.dark_state = "ready"
			# 精英遭遇检查 (线索卡触发)
			if m.dark_world.check_elite_encounter(
					StoryManager.get_fragment_count(), _baiye_following,
					true, StoryManager.flags):
				_trigger_encounter_dialogue(CardConfig.get_dw_elite_encounter())
				return
			m.dark_world.set_ready()
		
		EventHandler.EventType.ITEM:
			m._vfx.spawn_burst(m.board_visual.get_card_center(row, col), 8, Color(0.8, 0.7, 0.3))
			# 淡出 → 执行收集 → 淡入
			m.board_visual.animate_dark_card_collect(row, col, func() -> void:
				_event_handler.execute_event(result, card)
			)
			# 从奖池额外抽取奖励
			var reward: Dictionary = m.dark_world.roll_item_reward()
			if not reward.is_empty():
				GameData.modify_resource(reward["res"], reward["amt"])
				m._vfx.action_banner(reward["label"], Color(0.9, 0.8, 0.3), 0.8)
			m.dark_world.set_ready()
		
		EventHandler.EventType.SHOP:
			_event_handler.execute_event(result, card)
		
		EventHandler.EventType.INTEL:
			if GameData.get_resource("money") >= result.effects.get("money", 15):
				_event_handler.execute_event(result, card)
			else:
				m._vfx.action_banner("金钱不足", Color(0.86, 0.63, 0.31), 0.7)
			m.dark_world.set_ready()
		
		EventHandler.EventType.PASSAGE:
			# L2 双向通道: 根据当前层决定目标
			var cur_layer: int = m.dark_world.current_layer
			if cur_layer == 1:
				# L2 有两个通道: 第一个回 L1, 第二个去 L3
				# 检查 L3 是否解锁来决定是否提供选择
				if m.dark_world.is_layer_unlocked(2,
						StoryManager.get_fragment_count()):
					# 弹出选择对话框
					m.dark_world.dark_state = "popup"
					_show_passage_choice()
					return
				else:
					_change_layer(0)  # L3 未解锁，回 L1
			elif cur_layer == 0:
				_change_layer(1)  # L1 → L2
			else:
				_change_layer(1)  # L3 → L2
			m.dark_world.set_ready()
		
		EventHandler.EventType.ABYSS_CORE:
			_event_handler.execute_event(result, card)
			m._vfx.screen_flash(Color(0.3, 0.1, 0.5, 0.6), 0.5)
			m._vfx.screen_shake(5.0, 0.3)
			# Boss 遭遇检查 (深渊核心触发)
			if m.dark_world.check_boss_encounter(
					StoryManager.get_fragment_count(), _baiye_following,
					true, StoryManager.flags):
				_trigger_encounter_dialogue(CardConfig.get_dw_boss_encounter())
				return
			m.dark_world.set_ready()
		
		_:
			_event_handler.execute_event(result, card)
			m.dark_world.set_ready()

# ---------------------------------------------------------------------------
# 精英/Boss 遭遇对话
# ---------------------------------------------------------------------------

## 触发精英或 Boss 遭遇对话 (带选择)
## encounter_data: CardConfig.get_dw_elite_encounter() 或 get_dw_boss_encounter()
func _trigger_encounter_dialogue(encounter_data: Dictionary) -> void:
	if encounter_data == null or encounter_data.is_empty():
		m.dark_world.set_ready()
		return
	var dialogue: Array = encounter_data.get("dialogue", [])
	var choices: Array = encounter_data.get("choices", [])

	if dialogue.is_empty():
		m.dark_world.set_ready()
		return

	# 对话系统忙碌时静默跳过遭遇（否则 on_complete 永远不会被调用，dark_state 卡在 popup）
	if m._dialogue_system == null or m._dialogue_system.state != "idle":
		print("[DarkWorldFlow] _trigger_encounter_dialogue: dialogue_system busy (state=%s), skipping encounter" % [
			m._dialogue_system.state if m._dialogue_system != null else "null"
		])
		m.dark_world.set_ready()
		return

	m.dark_world.dark_state = "popup"

	# 播放对话 → 完成后展示选择
	m._dialogue_system.start(dialogue, "", "", func():
		if choices.is_empty():
			m.dark_world.set_ready()
			return
		# 构建选择按钮
		var choice_labels: Array = []
		for ch in choices:
			choice_labels.append(ch.get("label", "..."))
		m._event_popup.show_choice(choice_labels, func(idx: int):
			var chosen: Dictionary = choices[idx] if idx < choices.size() else {}
			var effects: Dictionary = chosen.get("effects", {})
			var result_text: String = chosen.get("result_text", "")
			# 应用效果（可能含碎片弹窗，需等待完成后再 set_ready）
			await _apply_encounter_effects(effects)
			# 显示结果文本
			if result_text != "":
				m._vfx.action_banner(result_text, Color(0.8, 0.7, 0.4), 1.5)
			m.dark_world.set_ready()
		)
	)

## 应用遭遇选择效果
func _apply_encounter_effects(effects: Dictionary) -> void:
	# set_flags: { "elite_defeated": true, ... }
	var set_flags: Dictionary = effects.get("set_flags", {})
	for flag_key in set_flags:
		StoryManager.set_flag(flag_key, set_flags[flag_key])

	# 资源修改
	if effects.has("san"):
		GameData.modify_resource("san", int(effects["san"]))
	if effects.has("set_power"):
		GameData.set_resource("power", int(effects["set_power"]))

	# 强制休息天数
	if effects.has("add_sleep_days"):
		GameData.modify_resource("sleep_days", int(effects["add_sleep_days"]))

	# 碎片奖励
	if effects.has("add_fragment"):
		var frag: String = effects["add_fragment"]
		var is_new: bool = StoryManager.collect_fragment(frag)
		if is_new:
			var info: Dictionary = StoryManager.get_fragment_info(frag)
			# 通过弹窗展示碎片全文，等待玩家关闭后再继续
			m.dark_world.dark_state = "popup"
			m._event_popup.show_fragment(info)
			await m._event_popup.popup_closed
			m.dark_world.dark_state = "ready"

# ---------------------------------------------------------------------------
# L2 双向通道选择
# ---------------------------------------------------------------------------

## 在 L2 层展示通道方向选择
func _show_passage_choice() -> void:
	var labels: Array = ["返回 表层·暗巷", "前往 深层·暗渊"]
	m._event_popup.show_choice(labels, func(idx: int):
		if idx == 0:
			_change_layer(0)  # → L1
		else:
			_change_layer(2)  # → L3
		m.dark_world.set_ready()
	)

# ---------------------------------------------------------------------------
# 通道 chibi 刷新
# ---------------------------------------------------------------------------

## 扫描棋盘所有通道牌, 符合条件时显示 chibi (不重复添加)
## 在发牌完成 / 层切换完成时调用
func _refresh_passage_chibis() -> void:
	m.board_visual.passage_clear_all()
	var fragments: int = StoryManager.get_fragment_count()
	var can_pass: bool = m.dark_world.can_use_passage(fragments)
	if not can_pass:
		return  # 不满足条件，不显示任何通道 chibi

	for row in range(1, Board.ROWS + 1):
		for col in range(1, Board.COLS + 1):
			var card: Card = m.board.get_card(row, col)
			if card == null:
				continue
			if card.dark_type == "passage":
				m.board_visual.passage_show_on_card(row, col)

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
	AudioManager.play_sfx("ghost_encounter")
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
	# 换层前先保存当前层棋盘，回层时可直接恢复
	var cur_layer_data = m.dark_world.get_layer_data()
	if cur_layer_data != null:
		cur_layer_data.saved_board = m.board

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
		# 清理旧层幽灵 & NPC 节点 & 通道 chibi
		m.board_visual.destroy_ghost_nodes()
		m.board_visual.destroy_npc_nodes()
		m.board_visual.passage_clear_all()

		# 重新生成棋盘
		_generate_dark_board()

		# 更新 UI
		m._resource_bar.update_dark_energy(
			m.dark_world.get_energy(), m.dark_world.get_max_energy())

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

	# 里程碑 hook: exit_dark_world
	var ms_event = MilestoneManager.try_trigger("exit_dark_world")
	if ms_event != null and m._dialogue_system:
		m._dialogue_system.start(ms_event.get("dialogue", []), "", "", func():
			MilestoneManager.on_event_complete(ms_event)
		)

	GameData.set_demo_state("transition")
	is_dark_transitioning = true   # 屏蔽 main.gd _process, 避免退出瞬间覆盖恢复的日间 BGM
	AudioManager.play_sfx("dark_world_exit")
	AudioManager.stop_ambient()
	# BGM 根据当前氛围值恢复 (与 Lua savedBgTransition 逻辑对齐)
	var daily_rev: int = GameData.cards_revealed - GameData.day_start_revealed
	var restore_target: float = minf(float(daily_rev) / 8.0, 1.0)
	if restore_target > 0.5:
		AudioManager.play_bgm("day_dark")
	else:
		AudioManager.play_bgm("day_light")
	is_dark_transitioning = false  # BGM 已提交给淡入淡出系统, 解除屏蔽
	m.dark_world.begin_exit()
	_baiye_following = false

	# 隐藏 Token
	m.token.visible = false
	m.token.alpha = 0.0

	# 收牌动画 → 清理 → 重建现实棋盘 → 发牌动画
	m.board_visual.play_undeal_animation(func():
		# 清理幽灵 & NPC 节点 & 通道 chibi
		m.board_visual.destroy_ghost_nodes()
		m.board_visual.destroy_npc_nodes()
		m.board_visual.passage_clear_all()

		# 恢复现实棋盘
		m.board = _saved_board
		_saved_board = null
		m.board_visual.rebuild_card_nodes()

		# 恢复现实 NPC 数据 & 节点
		m.game_flow.npc_manager.npcs.clear()
		for npc_id: String in _saved_real_npcs:
			m.game_flow.npc_manager.npcs[npc_id] = _saved_real_npcs[npc_id]
		_saved_real_npcs = {}
		if not m.game_flow.npc_manager.npcs.is_empty():
			m.board_visual.create_npc_nodes(m.game_flow.npc_manager.npcs)

		# UI 切回正常模式
		m._resource_bar.set_dark_mode(false)

		# 恢复大气
		daily_rev = GameData.cards_revealed - GameData.day_start_revealed
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

			# 消除裂隙: 清除 has_rift 标记 + 销毁 chibi, 防止玩家再次进入
			var rift_card: Card = m.board.get_card(_saved_token_row, _saved_token_col)
			if rift_card != null and rift_card.has_rift:
				rift_card.has_rift = false
				m.board_visual.rift_clear_all()
				print("[DarkWorldFlow] Rift consumed at (%d,%d)" % [_saved_token_row, _saved_token_col])

			# 更新所有卡牌视觉
			for r in range(1, Board.ROWS + 1):
				for c in range(1, Board.COLS + 1):
					m.board_visual.update_card_visual(r, c)

			# 恢复目的地提示（回到现实棋盘后重建）
			m.board_visual.refresh_destination_hints()

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
