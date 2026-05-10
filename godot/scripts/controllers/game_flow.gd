## GameFlow - 游戏流程控制器
## 负责: 发牌编排、日期推进、日终结算、胜负判定、道具生成
## Phase 5 升级: 晨间事件、里程碑链、NPC出场、动态天数、多结局
extends RefCounted

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------

## 请求显示事件对话 (由 main.gd 连接到具体 UI)
## event: 事件 Dictionary (含 dialogue, choices 等)
## on_complete: Callable(chosen_choice_id: String) — 对话结束后回调
signal event_dialogue_requested(event: Dictionary, on_complete: Callable)

## NPC 交互信号 (转发自 NPCManager, 供 main.gd 做 VFX)
signal npc_trade_executed(banner_text: String)
signal npc_trade_failed(reason: String)
signal npc_action_executed(action: String, banner_text: String)

# ---------------------------------------------------------------------------
# 引用 (由 main.gd 注入)
# ---------------------------------------------------------------------------
var m = null  # 主场景引用

# ---------------------------------------------------------------------------
# 子系统实例 (Phase 5)
# ---------------------------------------------------------------------------
var npc_manager: NPCManager = null
var story_event_mgr: StoryEventManager = null

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func setup(main_ref) -> void:
	m = main_ref

	# Phase 5: 初始化子系统
	npc_manager = NPCManager.new()
	story_event_mgr = StoryEventManager.new()

	# 转发 NPC 信号
	npc_manager.trade_executed.connect(func(txt): npc_trade_executed.emit(txt))
	npc_manager.trade_failed.connect(func(reason): npc_trade_failed.emit(reason))
	npc_manager.action_executed.connect(func(act, txt): npc_action_executed.emit(act, txt))

# ---------------------------------------------------------------------------
# 棋盘生成
# ---------------------------------------------------------------------------

## 生成新棋盘 (含预选地点注入)
func generate_board() -> void:
	var req_locs: Array = m.card_manager.pre_select_locations()
	m.board.required_locations = req_locs
	m.board.generate_cards()
	m.board_visual.rebuild_card_nodes()

# ---------------------------------------------------------------------------
# 发牌流程
# ---------------------------------------------------------------------------

## 启动发牌 → 横幅 → 螺旋飞牌 → _on_deal_complete
func start_deal() -> void:
	print("[GameFlow] start_deal: day=%d, demo_state=%s" % [m.day_count, GameData.demo_state])
	GameData.current_day = m.day_count
	GameData.set_demo_state("dealing")
	# 每日氛围重置 (匹配 Lua: dayStartRevealed = cardsRevealed)
	GameData.day_start_revealed = GameData.cards_revealed
	# BGM (首次或重新开始时播放)
	AudioManager.play_bgm("main")
	m._vfx.action_banner("第 %d 天" % m.day_count, Color.WHITE, 1.2)
	m.board_visual.start_deal_animation(_on_deal_complete)

func _on_deal_complete() -> void:
	GameData.set_demo_state("ready")
	m._camera_button.show_button()
	# 安全区光晕: 发牌完成后显式激活 (匹配 Lua showSafeGlow 逻辑)
	m.board_visual.show_safe_glows()

	# Token 出现在 "家"
	var home_row: int = m.board.home_row
	var home_col: int = m.board.home_col
	m.token.target_row = home_row
	m.token.target_col = home_col
	m.token.visible = true
	m.token.alpha = 1.0
	m.board_visual.update_token_visual()

	# 刷新所有卡牌视觉 (显示地点文字)
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			m.board_visual.update_card_visual(r, c)

	# 翻开家的卡牌
	var home_card: Card = m.board.get_card(home_row, home_col)
	if home_card:
		m.board.flip_card(home_row, home_col)
		m.board_visual.update_card_visual(home_row, home_col)

	# 生成日程与传闻
	m.card_manager.generate_daily(m.board)
	m.card_manager.generate_rumor_from_board(m.board)

	# 生成棋盘道具
	m.board_items.spawn_daily(m.board, home_row, home_col)
	m.board_visual.create_item_nodes(m.board_items.items)
	_animate_item_spawn()

	# 通知 HandPanel 刷新并显示 (注入 ConsumableController 解耦数据访问)
	if m._hand_panel:
		m._hand_panel.setup(m.card_manager, m.consumable_controller)
		m._hand_panel.show_panel()

	# Phase 5: 发牌完成后生成当日 NPC
	_spawn_daily_npcs()

	# Phase 5: Day 1 晨间事件 (restart_game 不经过 on_date_transition_complete,
	# 需在发牌完成后单独触发, 仅显示对话, 不重新发牌)
	if m.day_count == 1:
		_try_day1_morning_events()

## Day 1 专用晨间事件触发 (仅对话, 不调用 _begin_new_day)
func _try_day1_morning_events() -> void:
	# 先做故事 Tick (与 on_date_transition_complete 保持一致)
	StoryManager.advance_baiye_sleep()
	StoryManager.update_chapter_by_day()

	var event = story_event_mgr.query_morning_event()
	if event != null:
		event = story_event_mgr.trigger_morning_event(event)
		event_dialogue_requested.emit(event, func(chosen_id: String) -> void:
			story_event_mgr.on_morning_event_complete(event, chosen_id)
			# Day 1 不需要继续里程碑链或重新发牌
		)

## 道具弹出动画
func _animate_item_spawn() -> void:
	for i in range(m.board_items.items.size()):
		var item: BoardItems.BoardItem = m.board_items.items[i]
		var delay: float = 0.3 + i * 0.15
		# 数据层 tween (保留兼容 overlay 绘制)
		var tw: Tween = m.create_tween()
		tw.tween_property(item, "scale", 1.0, 0.3) \
			.set_delay(delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		var tw2: Tween = m.create_tween()
		tw2.tween_property(item, "alpha", 1.0, 0.2).set_delay(delay)
		var tw3: Tween = m.create_tween()
		tw3.tween_property(item, "glow_alpha", 1.0, 0.3).set_delay(delay)
		# 3D 节点弹出动画
		m.board_visual.animate_item_spawn(i, delay)

# ---------------------------------------------------------------------------
# NPC 出场 (Phase 5)
# ---------------------------------------------------------------------------

## 根据当天规则生成 NPC (匹配 Lua GameFlow.startDeal NPC 逻辑)
func _spawn_daily_npcs() -> void:
	# 清除上一天的 NPC 视觉节点
	m.board_visual.destroy_npc_nodes()
	npc_manager.clear()

	var day: int = m.day_count

	# Day 1: 琴馨 (相机教学)
	if day == 1:
		var tile: Vector2i = _pick_free_tile()
		npc_manager.spawn_npc("qinxin", tile.x, tile.y)

	# Day 3+: 房东 (资源交换)
	if day >= 3:
		var tile: Vector2i = _pick_free_tile()
		npc_manager.spawn_npc("fangdong", tile.x, tile.y)

	# 随机 50%: 猫咪
	if randf() < 0.5:
		var tile: Vector2i = _pick_free_tile()
		npc_manager.spawn_npc("cat", tile.x, tile.y)

	# 创建 NPC 3D 节点 (如有 NPC 被生成)
	if not npc_manager.npcs.is_empty():
		m.board_visual.create_npc_nodes(npc_manager.npcs)

## 在棋盘上选取一个空闲格子 (避开家和已有 NPC)
func _pick_free_tile() -> Vector2i:
	var candidates: Array = []
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			# 跳过家
			if r == m.board.home_row and c == m.board.home_col:
				continue
			# 跳过已有 NPC
			var occupied := false
			for npc in npc_manager.npcs.values():
				if npc.row == r and npc.col == c:
					occupied = true
					break
			if not occupied:
				candidates.append(Vector2i(r, c))

	if candidates.is_empty():
		return Vector2i(1, 1)  # 兜底
	return candidates[randi() % candidates.size()]

# ---------------------------------------------------------------------------
# 日期推进
# ---------------------------------------------------------------------------

func advance_day() -> void:
	if GameData.game_phase != "playing":
		return
	if GameData.demo_state != "ready":
		return

	# 日终结算
	var effects: Array = m.card_manager.settle_day()
	for eff in effects:
		GameData.modify_resource(eff[0], eff[1])

	# 恢复资源 (匹配 Lua: san+1, order+1, film→3, money+10)
	GameData.modify_resource("san", 1)
	GameData.modify_resource("order", 1)
	var current_film: int = GameData.get_resource("film")
	if current_film < 3:
		GameData.modify_resource("film", 3 - current_film)
	GameData.modify_resource("money", 10)

	AudioManager.play_sfx("day_transition")
	GameData.set_demo_state("dealing")
	m._camera_button.hide_button()
	m.token.visible = false
	m.board_visual.mg_clear_all()
	m.board_visual.destroy_item_nodes()
	m.board_visual.destroy_npc_nodes()  # Phase 5: 清理 NPC 节点
	m.board_items.clear()

	m.day_count += 1
	GameData.current_day = m.day_count

	# Phase 5: 动态天数 (替代硬编码 MAX_DAYS)
	var max_days: int = StoryManager.get_max_days()
	if m.day_count > max_days:
		_trigger_victory()
		return

	# 收牌前关闭安全区光晕
	m.board_visual.hide_safe_glows()
	# 收牌动画 → 日期过渡
	m.board_visual.play_undeal_animation(func() -> void:
		m._date_transition.play(m.day_count)
	)

# ---------------------------------------------------------------------------
# 日期过渡完成 → 晨间事件 → 里程碑链 → 开始新一天 (Phase 5)
# ---------------------------------------------------------------------------

## 日期过渡完成回调 (由 main.gd 信号桥接)
func on_date_transition_complete() -> void:
	print("[GameFlow] on_date_transition_complete: day=%d, demo_state=%s" % [m.day_count, GameData.demo_state])
	# ① 故事 Tick: 白夜沉睡递减 + 章节推进
	StoryManager.advance_baiye_sleep()
	StoryManager.update_chapter_by_day()

	# ② NPC 每日冷却重置
	npc_manager.reset_daily()

	# ③ 启动晨间链: 晨间事件 → 里程碑链 → 新一天
	_try_morning_event()

## 晨间事件检查
func _try_morning_event() -> void:
	var event = story_event_mgr.query_morning_event()
	print("[GameFlow] _try_morning_event: event=%s" % ("null" if event == null else event.get("id", "?")))
	if event != null:
		event = story_event_mgr.trigger_morning_event(event)
		event_dialogue_requested.emit(event, func(chosen_id: String) -> void:
			print("[GameFlow] morning event on_complete called, chosen='%s'" % chosen_id)
			story_event_mgr.on_morning_event_complete(event, chosen_id)
			_try_milestone_chain()
		)
	else:
		_try_milestone_chain()

## 里程碑链: baiye_return → chapter_enter → resource_low → 开始新一天
func _try_milestone_chain() -> void:
	print("[GameFlow] _try_milestone_chain entered")
	_try_milestone("baiye_return", func() -> void:
		_try_milestone("chapter_enter", func() -> void:
			_try_milestone("resource_low", func() -> void:
				_begin_new_day()
			)
		)
	)

## 尝试触发单个里程碑; 有对话则显示后回调, 否则直接回调
func _try_milestone(hook_id: String, on_done: Callable) -> void:
	var event = MilestoneManager.try_trigger(hook_id)
	print("[GameFlow] _try_milestone '%s': event=%s" % [hook_id, "null" if event == null else event.get("id", "?")])
	if event != null:
		event_dialogue_requested.emit(event, func(chosen_id: String) -> void:
			MilestoneManager.on_event_complete(event, chosen_id)
			on_done.call()
		)
	else:
		on_done.call()

## 晨间链完毕, 真正开始新一天
func _begin_new_day() -> void:
	print("[GameFlow] _begin_new_day: day=%d, demo_state=%s" % [m.day_count, GameData.demo_state])
	# Phase 5: 重置每日步数
	m.card_interaction.reset_daily_steps()
	m.board = Board.new()
	generate_board()
	start_deal()

# ---------------------------------------------------------------------------
# 胜负判定 (Phase 5: EndingSystem 多结局)
# ---------------------------------------------------------------------------

func check_defeat() -> void:
	if GameData.game_phase != "playing":
		return
	if GameData.check_defeat():
		AudioManager.stop_bgm()
		GameData.set_game_phase("gameover")
		GameData.set_demo_state("idle")
		m.token.set_emotion("dead")
		m._vfx.screen_shake(8.0, 0.4, 20.0)
		m._vfx.screen_flash(Color(0.7, 0.12, 0.12, 0.78), 0.5)

		# Phase 5: 通过 EndingSystem 判定败北结局
		var ending: Dictionary = EndingSystem.evaluate()
		m._game_over.show_result(false, GameData.get_stats(), ending)

func _trigger_victory() -> void:
	AudioManager.stop_bgm()
	AudioManager.play_sfx("ending_reveal")
	GameData.set_game_phase("gameover")
	GameData.set_demo_state("idle")
	m.token.set_emotion("happy")
	m._vfx.screen_flash(Color(1.0, 0.84, 0.39, 0.7), 0.5)

	# Phase 5: 通过 EndingSystem 判定胜利结局
	var ending: Dictionary = EndingSystem.evaluate()
	# 根据结局类型调整 token 表情
	if not EndingSystem.is_victory_ending(ending):
		m.token.set_emotion("dead")
	m._game_over.show_result(EndingSystem.is_victory_ending(ending), GameData.get_stats(), ending)

# ---------------------------------------------------------------------------
# 道具拾取
# ---------------------------------------------------------------------------

## 尝试拾取当前格子道具, 返回拾取结果
func try_collect_item(row: int, col: int) -> Dictionary:
	var result: Dictionary = m.board_items.try_collect(row, col)
	if result.is_empty():
		return {}

	# 3D 拾取动画
	var item_idx: int = result.get("index", -1)
	if item_idx >= 0:
		m.board_visual.animate_item_collect(item_idx)

	var item_key: String = result["key"]
	var item_label: String = result["label"]
	var item_icon: String = result["icon"]

	# 道具拾取音效 (匹配 Lua: item_use_xxx)
	var sfx_key: String = "item_use_" + item_key if AudioManager.sfx_map.has("item_use_" + item_key) else "item_use"
	AudioManager.play_sfx(sfx_key)

	# 应用效果
	match item_key:
		"coffee":
			GameData.modify_resource("san", 2)
			m._vfx.action_banner("%s +2 SAN" % item_icon, Color(0.5, 0.8, 0.4), 0.7)
		"film":
			GameData.modify_resource("film", 1)
			m._vfx.action_banner("%s +1 胶卷" % item_icon, Color(0.5, 0.7, 0.9), 0.7)
		"shield":
			GameData.add_item("shield")
			m._vfx.action_banner("%s 获得护身符" % item_icon, Color(0.8, 0.7, 0.3), 0.7)
		"exorcism":
			GameData.add_item("exorcism")
			m._vfx.action_banner("%s 获得驱魔香" % item_icon, Color(0.7, 0.5, 0.8), 0.7)
		"mapReveal":
			_reveal_random_card()
			m._vfx.action_banner("%s 地图碎片: 揭示一张卡" % item_icon, Color(0.6, 0.8, 0.6), 0.7)

	# 收集粒子
	var center: Vector2 = m.board_visual.get_card_center(row, col)
	m._vfx.spawn_burst(center, 6, Color(1.0, 0.9, 0.4))

	return result

## 地图碎片: 揭示一张随机未翻开的卡牌
func _reveal_random_card() -> void:
	var unflipped: Array = m.board.get_unflipped_cards()
	if unflipped.is_empty():
		return
	var pick: Card = unflipped[randi() % unflipped.size()]
	pick.revealed = true
	m.board_visual.update_card_visual(pick.row, pick.col)

# ---------------------------------------------------------------------------
# 游戏重置
# ---------------------------------------------------------------------------

func restart_game() -> void:
	m.day_count = 1
	GameData.current_day = 1
	m.game_time = 0.0
	m._bg_transition = 0.0
	m._bg_transition_target = 0.0
	m._camera_offset = Vector2.ZERO
	m._hovered_card = null

	# 重置音频 combo
	AudioManager.reset_combo()
	# 重置 VFX (匹配 Lua: VFX.resetAll())
	m._vfx.reset_all()

	# 退出相机模式（如果正在拍照）— 必须在清理 3D 节点前
	if m._camera_button.is_camera_mode():
		m._camera_button.exit_camera_mode()

	# 清理所有 3D 视觉节点 (chibi / ghost / NPC / item)
	m.board_visual.mg_clear_all()
	m.board_visual.destroy_ghost_nodes()
	m.board_visual.destroy_npc_nodes()
	m.board_visual.destroy_item_nodes()
	m.board_visual.hide_safe_glows()

	# 重置数据和核心对象
	GameData.reset()
	m.card_manager = CardManager.new()
	m.board = Board.new()
	m.board_items.clear()

	# 重置暗面世界 (用 reset() 保留回调注入)
	m.dark_world.reset()

	# Phase 5: 重置故事/事件/NPC/里程碑子系统
	StoryManager.reset()
	MilestoneManager.reset()
	npc_manager.reset()
	story_event_mgr.reset()

	# 重置氛围 (匹配 Lua: updateSceneAtmosphere(0))
	m._apply_atmosphere(0.0)

	# 重置气泡对话
	m._bubble_dialogue.text = ""
	m._bubble_dialogue.bubble_alpha = 0.0
	m._bubble_dialogue.bubble_scale = 0.0
	m._bubble_dialogue.state = "hidden"
	m._bubble_show_tweened = false
	m._bubble_hide_tweened = false

	# 隐藏/重置所有 UI 面板
	m._resource_bar.set_dark_mode(false)
	m._event_popup.clear_toasts()
	if m._event_popup.is_active():
		m._event_popup.dismiss()
	if m._shop_popup.is_active():
		m._shop_popup.close_shop()
	if m._dialogue_system.is_active():
		m._dialogue_system.reset()
	m._hand_panel.reset()
	m._clue_log.reset()

	# 重新生成棋盘
	generate_board()
	m.token = Token.new()
	m.token.load_textures()

	# 重新显示手牌面板 (注入 ConsumableController 解耦数据访问)
	m._hand_panel.setup(m.card_manager, m.consumable_controller)
	m._hand_panel.show_panel()

	GameData.set_game_phase("playing")
	# 重置步数 (restart_game 不经过 _begin_new_day, 需要在此补调)
	m.card_interaction.reset_daily_steps()
	start_deal()
