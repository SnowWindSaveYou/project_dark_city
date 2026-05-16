## CardInteraction - 卡牌交互控制器
## 负责: 普通点击(翻牌/移动)、相机模式(拍照/驱魔)、
##       NPC 对话触发、裂隙确认、道具使用
## Phase 5: StoryEventManager 故事事件拦截、NPC 同格对话、灵感退化、步数限制
extends RefCounted

# ---------------------------------------------------------------------------
# 依赖
# ---------------------------------------------------------------------------
const TutorialBubble = preload("res://scripts/ui/tutorial_bubble.gd")

# ---------------------------------------------------------------------------
# 引用 (由 main.gd 注入)
# ---------------------------------------------------------------------------
var m: Node = null
var _event_handler: EventHandler = null

## 最近一次拍照的卡牌坐标 (row, col)，用于弹窗关闭后只标记该卡牌
var _photo_row: int = -1
var _photo_col: int = -1

## 照片弹窗关闭后是否继续驱除流程（怪物/陷阱拍照时为 true，跳过 on_photo_popup_dismissed 的 ready 恢复）
var _pending_exorcise: bool = false

## Phase 5: 每日步数计数
var _steps_today: int = 0
## 天开始时的 health 快照 (用于计算当日最大步数, 避免天中 health 变化影响步数上限)
var _day_start_health: int = 0

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func setup(main_ref) -> void:
	m = main_ref
	_event_handler = EventHandler.new()
	_event_handler.setup(main_ref)

## Phase 5: 每日重置步数 (由 game_flow 在新一天开始时调用)
## 此时记录 health 快照作为当日步数上限
func reset_daily_steps() -> void:
	_steps_today = 0
	_day_start_health = GameData.get_resource("health")
	_sync_steps_to_gamedata()

## 将步数状态同步到 GameData，供 resource_bar_scene UI 读取
## 使用天开始时的 health 快照 / 2，而非实时 health (避免天中 health 变化影响步数上限)
func _sync_steps_to_gamedata() -> void:
	var max_steps: int = _day_start_health / 2
	GameData.steps_total = max_steps
	GameData.steps_remaining = max_steps - _steps_today

# =========================================================================
# 普通模式卡牌交互
# =========================================================================

func handle_card_click(row: int, col: int) -> void:
	if GameData.game_phase != "playing":
		return
	if GameData.demo_state != "ready":
		return

	var card: Card = m.board.get_card(row, col)
	if card == null:
		return

	# 相机模式走不同分支
	if m._camera_button.is_camera_mode():
		_handle_camera_mode_click(card, row, col)
		return

	var is_current: bool = (m.token.target_row == row and m.token.target_col == col)

	if is_current:
		# 翻当前格子
		if not card.is_flipped:
			_flip_current_card(card, row, col)
		return

	# Phase 5: 步数限制 (天开始时 health 快照 / 2 = 当日最大步数) — 统一检查
	var max_steps: int = _day_start_health / 2

	# 检查相邻
	if not m.board.is_adjacent(m.token.target_row, m.token.target_col, row, col):
		# 非相邻 → 尝试 BFS 自动寻路 (沿已翻开卡牌路径)
		var path: Array = _find_path(m.token.target_row, m.token.target_col, row, col)
		if path.is_empty():
			m.board_visual.play_shake_animation(row, col)
			m._vfx.action_banner("沿途有未翻开的卡牌, 无法到达", Color(0.7, 0.7, 0.7), 0.6)
			return
		# 步数预算检查 (整条路径)
		if max_steps > 0 and _steps_today + path.size() > max_steps:
			m.board_visual.play_shake_animation(row, col)
			m._vfx.action_banner("体力不足! (需要 %d 步, 剩余 %d 步)" % [
				path.size(), max_steps - _steps_today],
				Color(0.86, 0.31, 0.31), 0.8)
			return
		_execute_auto_walk(path)
		return

	# 相邻: 单步步数检查
	if max_steps > 0 and _steps_today >= max_steps:
		m.board_visual.play_shake_animation(row, col)
		m._vfx.action_banner("体力不足! (已走 %d/%d 步)" % [_steps_today, max_steps],
			Color(0.86, 0.31, 0.31), 0.8)
		return

	# 移动 Token
	_move_token(card, row, col)

# ---------------------------------------------------------------------------
# 翻牌
# ---------------------------------------------------------------------------

func _flip_current_card(card: Card, row: int, col: int) -> void:
	GameData.set_demo_state("flipping")
	AudioManager.play_sfx("card_flip")
	m.board.flip_card(row, col)
	card.is_flipping = true

	m.board_visual.play_flip_animation(row, col, func():
		card.is_flipping = false
		m.board_visual.update_card_visual(row, col)
		_on_card_flipped(card, row, col)
	)

# ---------------------------------------------------------------------------
# Token 移动
# ---------------------------------------------------------------------------

func _move_token(_card: Card, row: int, col: int) -> void:
	GameData.set_demo_state("moving")
	# 移动前清除环绕幽灵
	m.board_visual.mg_clear_surround()
	m.token.target_row = row
	m.token.target_col = col
	m.token.set_emotion("running")

	# Phase 5: 计步
	_steps_today += 1
	_sync_steps_to_gamedata()

	m.board_visual.animate_token_move(row, col, func():
		# 道具拾取 (到达后才触发, 而非移动开始时)
		m.game_flow.try_collect_item(row, col)

		var arrived_card: Card = m.board.get_card(row, col)
		if arrived_card and not arrived_card.is_flipped:
			GameData.set_demo_state("flipping")
			AudioManager.play_sfx("card_flip")
			m.board.flip_card(row, col)
			arrived_card.is_flipping = true

			m.board_visual.play_flip_animation(row, col, func():
				arrived_card.is_flipping = false
				m.board_visual.update_card_visual(row, col)
				_on_card_flipped(arrived_card, row, col)
			)
		else:
			# 已翻开格子: 检查日程到达并尝试触发中段事件
			var mid_loc: String = ""
			if arrived_card and arrived_card.location != "":
				var completed: Dictionary = m.card_manager.complete_schedule_at(arrived_card.location)
				if not completed.is_empty():
					mid_loc = arrived_card.location
					m.board_visual.hide_destination_hint(mid_loc)
					var reward: Array = completed.get("reward", [])
					if reward.size() >= 2:
						GameData.modify_resource(reward[0], reward[1])
						m._vfx.action_banner("日程完成! %s +%d" % [reward[0], reward[1]],
							Color(0.4, 0.8, 0.5), 0.8)
			m.token.set_emotion("default")
			if mid_loc != "" and not _try_mid_day_event(mid_loc):
				GameData.set_demo_state("ready")
				m._camera_button.show_button()
			elif mid_loc == "":
				GameData.set_demo_state("ready")
				m._camera_button.show_button()
			# else: 对话完成回调里恢复 ready
	)

# ---------------------------------------------------------------------------
# 翻牌后效果处理
# ---------------------------------------------------------------------------

func _on_card_flipped(card: Card, row: int, col: int) -> void:
	var card_type: String = card.type
	print("[Flip] (%d,%d) 翻面触发, 类型: %s, trap_subtype: %s" % [row, col, card_type, card.trap_subtype if card_type == "trap" else "N/A"])
	GameData.cards_revealed += 1

	# 地标光环净化已在 board.generate_cards() 阶段完成 (_apply_landmark_aura)
	# 地标邻近的 monster/trap 在生成时已转为 safe，翻牌时无需重复净化

	# Phase 5: 灵感阈值退化 — inspiration < 20 时线索牌退化为 safe
	if card_type == "clue" and GameData.get_resource("inspiration") < 20:
		print("[Flip] inspiration=%d < 20, 线索牌(%d,%d)退化为 safe" % [
			GameData.get_resource("inspiration"), row, col])
		card.type = "safe"
		card_type = "safe"
		m.board_visual.update_card_visual(row, col)
		m._vfx.action_banner("灵感不足, 线索消散...", Color(0.6, 0.6, 0.6), 0.8)

	# 日程完成检查 (翻牌到达时)
	var arrived_location_for_mid: String = ""
	if card.location != "":
		var completed: Dictionary = m.card_manager.complete_schedule_at(card.location)
		if not completed.is_empty():
			arrived_location_for_mid = card.location
			m.board_visual.hide_destination_hint(arrived_location_for_mid)
			var reward: Array = completed.get("reward", [])
			if reward.size() >= 2:
				GameData.modify_resource(reward[0], reward[1])
				m._vfx.action_banner("日程完成! %s +%d" % [reward[0], reward[1]],
					Color(0.4, 0.8, 0.5), 0.8)

	# 怪物翻出: 生成环绕幽灵 chibi + 音效
	if card_type == "monster":
		AudioManager.play_sfx("ghost_encounter")
		m.board_visual.mg_spawn_around_player(row, col, card.location)

	# 表情映射
	var emotion_map: Dictionary = {
		"monster": "scared", "trap": "nervous", "shop": "confused",
		"clue": "surprised", "home": "relieved", "landmark": "relieved",
		"safe": "relieved",
	}
	m.token.set_emotion(emotion_map.get(card_type, "default"))

	# 粒子
	var center: Vector2 = m.board_visual.get_card_center(row, col)
	var tc: Color = GameTheme.card_type_color(card_type)
	m._vfx.spawn_burst(center, 8, tc)

	# 安全区域直接通过
	if card_type == "home" or card_type == "landmark":
		m._vfx.action_banner("安全", GameTheme.safe, 0.8)
		GameData.set_demo_state("ready")
		m._camera_button.show_button()
		# 裂隙检查
		if card.has_rift:
			m.board_visual.rift_show_on_card(row, col)
			_show_rift_confirm(row, col)
			return
		return

	m._vfx.screen_shake(3.0, 0.15)

	# 陷阱走 Toast 流 (传送陷阱需异步等待)
	if card_type == "trap":
		await _handle_trap(card, row, col)
		return

	# 判断是否阻断
	var is_blocking: bool = EventPopupScene.is_blocking_event(card_type)

	if is_blocking:
		# 阻断事件: 商店 (未来: 带选项的剧情)
		GameData.set_demo_state("popup")
		m._camera_button.hide_button()
		await m.get_tree().create_timer(0.4).timeout
		if card_type == "shop":
			# 商店首见教程
			if not GameData.tutorial_flags.get("shop_seen", false):
				GameData.tutorial_flags["shop_seen"] = true
				m.show_sequence([
					{"speaker": "苏柚", "text": "这是……便利店还开着？"},
					{"speaker": "白夜", "text": "用灵石换道具。\n护身符能挡一次怪物伤害，摄影胶卷能多拍几次。"},
					{"speaker": "苏柚", "text": "灵石从哪来？"},
					{"speaker": "白夜", "text": "翻线索牌、完成日程、或者暗面里找——\n省着点花。"},
				])
				await m.get_tree().create_timer(0.3).timeout
			m._shop_popup.open_shop()
		else:
			m._event_popup.show_event(card)
	else:
		# 非阻断事件: monster, safe, reward, plot, clue 等
		# 立即结算资源
		var shield_used: bool = false
		var effects: Dictionary = card.get_effects()

		# 怪物: 护盾检查
		if card_type == "monster":
			if effects.size() > 0 and GameData.has_item("shield"):
				GameData.remove_item("shield")
				shield_used = true
				m._vfx.action_banner("🧿 护身符抵消了伤害!", GameTheme.safe, 0.8)
				effects = {}  # 清空伤害

		# 应用资源变化
		if not shield_used:
			for key in effects:
				GameData.modify_resource(key, effects[key])

		# Phase 5: 剧情/线索事件 — 优先走 StoryEventManager (条件匹配), 然后 event_id, 最后 fallback
		if card_type == "plot" or card_type == "clue":
			var story_event_handled: bool = _try_story_event(card, card_type, row, col)
			if not story_event_handled:
				# 次优先: event_id (EventPool 驱动)
				if card.event_id != "":
					var evt_result: EventHandler.EventResult = _event_handler.resolve_event_by_id(card.event_id, card)
					_event_handler.execute_event(evt_result, card)
				else:
					# fallback: 旧路径 (StoryManager.pick_xxx_event)
					if card_type == "plot":
						var story_evt: Dictionary = StoryManager.pick_plot_event()
						if not story_evt.is_empty():
							var result: Dictionary = StoryManager.apply_event_effects(story_evt)
							if result["is_new_clue"]:
								m._vfx.action_banner("获得线索: %s" % result["clue_name"],
									Color(0.5, 0.8, 0.6), 1.0)
					else:  # clue
						var clue_evt: Dictionary = StoryManager.pick_clue_event()
						if not clue_evt.is_empty():
							var result: Dictionary = StoryManager.apply_event_effects(clue_evt)
							if result["is_new_clue"]:
								m._vfx.action_banner("获得线索: %s" % result["clue_name"],
									Color(0.5, 0.8, 0.6), 1.0)
							else:
								m._vfx.action_banner("发现了新线索!", GameTheme.info, 0.8)
						else:
							m._vfx.action_banner("发现了新线索!", GameTheme.info, 0.8)

		# 非阻断事件: 弹窗展示（等待玩家点击"知道了"再继续）
		GameData.set_demo_state("popup")
		m._camera_button.hide_button()
		m._event_popup.show_event_data(card_type, effects, shield_used, card.location, card.trap_subtype)
		await m._event_popup.popup_closed

		# 弹窗关闭后恢复状态
		m.token.set_emotion("default")
		GameData.set_demo_state("ready")
		m._camera_button.show_button()

		# 教程触发：怪物首遇 / 安全区首次踏入
		if card_type == "monster" and not GameData.tutorial_flags.get("monster_seen", false):
			GameData.tutorial_flags["monster_seen"] = true
			m.show_sequence([
				{"speaker": "苏柚", "text": "……它伤我多深？"},
				{"speaker": "白夜", "text": "取决于你的灵感。\n灵感越高，它造成的伤害越重。"},
				{"speaker": "苏柚", "text": "灵感……是从哪里来的？"},
				{"speaker": "白夜", "text": "翻线索牌会涨。进暗面也会涨。\n想少受伤，就别让它堆太高。"},
			])
		elif card_type == "safe" and \
				m.board.is_in_landmark_aura(row, col) and \
				not GameData.tutorial_flags.get("safe_zone_seen", false):
			GameData.tutorial_flags["safe_zone_seen"] = true
			m.show_tutorial(
				"发光的格子待着——妖魔进不来。\n教堂和警察局周围四格都是。\n被追了，往那里跑。",
				"白夜", TutorialBubble.IDLE_TIME_LONG
			)

		# 裂隙检查
		if card.has_rift:
			m.board_visual.rift_show_on_card(row, col)
			_show_rift_confirm(row, col)
			return

		# 中段事件: 日程完成时触发
		if arrived_location_for_mid != "" and not _try_mid_day_event(arrived_location_for_mid):
			m.game_flow.check_defeat()
		elif arrived_location_for_mid == "":
			m.game_flow.check_defeat()
		# else: _try_mid_day_event 返回 true, 对话完成回调里负责恢复 ready

# ---------------------------------------------------------------------------
# 陷阱处理 (Toast 非阻塞)
# ---------------------------------------------------------------------------

func _handle_trap(card: Card, row: int, col: int) -> void:
	var shield_used: bool = false

	# 护身符检查
	if GameData.has_item("shield"):
		GameData.remove_item("shield")
		shield_used = true
		m._vfx.action_banner("🧿 护身符抵消了陷阱!", GameTheme.safe, 0.8)
	else:
		# 应用陷阱效果
		var effects: Dictionary = card.get_effects()
		for key in effects:
			GameData.modify_resource(key, effects[key])

		# 特殊: 传送陷阱 — 先弹窗告知再传送
		if card.trap_subtype == "teleport":
			GameData.set_demo_state("popup")
			m._camera_button.hide_button()
			m._event_popup.show_event_data(card.type, card.get_effects(), shield_used, card.location, card.trap_subtype)
			await m._event_popup.popup_closed
			# 传送流程（内部会设置 ready 状态）
			await _teleport_to_random()
			return

	# 陷阱弹窗（等待玩家点击"知道了"）
	GameData.set_demo_state("popup")
	m._camera_button.hide_button()
	m._event_popup.show_event_data(card.type, card.get_effects(), shield_used, card.location, card.trap_subtype)
	await m._event_popup.popup_closed

	GameData.set_demo_state("ready")
	m._camera_button.show_button()

	# 裂隙检查
	if card.has_rift:
		m.board_visual.rift_show_on_card(row, col)
		_show_rift_confirm(row, col)

	m.game_flow.check_defeat()

## 传送到随机未翻开格子 (回调链: 移动动画 → 翻面 → 处理翻面效果)
func _teleport_to_random() -> void:
	var unflipped: Array = m.board.get_unflipped_cards()
	if unflipped.is_empty():
		GameData.set_demo_state("ready")
		m._camera_button.show_button()
		return

	var pick: Card = unflipped[randi() % unflipped.size()]
	var dest_row: int = pick.row
	var dest_col: int = pick.col

	GameData.set_demo_state("teleporting")

	# 紫色闪光 + 标语
	m._vfx.screen_flash(Color(0.6, 0.2, 0.8, 0.5), 0.3)
	m._vfx.action_banner("空间错位!", Color(0.6, 0.2, 0.8), 0.8)

	# 短暂延迟让玩家看到效果
	await m.get_tree().create_timer(0.5).timeout

	# 移动 token 到目标格
	m.token.target_row = dest_row
	m.token.target_col = dest_col

	# 移动动画完成后 → 翻面 → 处理效果 (嵌套回调，与 _move_token 一致)
	m.board_visual.animate_token_move(dest_row, dest_col, func():
		var arrived_card: Card = m.board.get_card(dest_row, dest_col)
		if arrived_card and not arrived_card.is_flipped and not arrived_card.is_flipping:
			print("[Teleport] 到达(%d,%d), 翻面卡牌类型: %s" % [dest_row, dest_col, arrived_card.type])
			GameData.set_demo_state("flipping")
			m.board.flip_card(dest_row, dest_col)
			arrived_card.is_flipping = true

			m.board_visual.play_flip_animation(dest_row, dest_col, func():
				arrived_card.is_flipping = false
				m.board_visual.update_card_visual(dest_row, dest_col)
				_on_card_flipped(arrived_card, dest_row, dest_col)
			)
		else:
			print("[Teleport] 到达(%d,%d), 目标格已翻开, 恢复 ready" % [dest_row, dest_col])
			m.token.set_emotion("default")
			GameData.set_demo_state("ready")
			m._camera_button.show_button()
	)

# ---------------------------------------------------------------------------
# 裂隙确认
# ---------------------------------------------------------------------------

func _show_rift_confirm(row: int, col: int) -> void:
	var center: Vector2 = m.board_visual.get_card_center(row, col)
	GameData.set_demo_state("rift_confirm")
	# 裂隙首见教程
	if not GameData.tutorial_flags.get("rift_seen", false):
		GameData.tutorial_flags["rift_seen"] = true
		m.show_sequence([
			{"speaker": "苏柚", "text": "……这是什么地方？"},
			{"speaker": "白夜", "text": "暗面的入口。\n你现在能进去——灵感够高的时候才能感知到它。"},
			{"speaker": "苏柚", "text": "灵感越高越容易看见？"},
			{"speaker": "白夜", "text": "进去之前想好。\n暗面会拉高灵感，出来时妖魔的伤害也会更重。"},
		])
	m._event_popup.show_rift_confirm(center.x, center.y)

## 裂隙确认回调
func on_rift_confirmed() -> void:
	var row: int = m.token.target_row
	var col: int = m.token.target_col
	GameData.set_demo_state("ready")
	m._camera_button.show_button()
	m.dark_world_flow.enter_dark_world(row, col)

func on_rift_cancelled() -> void:
	GameData.set_demo_state("ready")
	m._camera_button.show_button()

# =========================================================================
# 弹窗关闭回调
# =========================================================================

func on_popup_dismissed(card: Card) -> void:
	# TODO: _event_popup.popup_closed 信号在 main.gd 无条件连接到此回调，
	# 暗面也复用同一 _event_popup，导致暗面弹窗关闭时 demo_state 被错误地
	# 从 "dark_world" 覆写为 "ready"。需要从架构上拆分两套弹窗信号或加路由层。

	if card:
		var effects: Dictionary = card.get_effects()
		for key in effects:
			GameData.modify_resource(key, effects[key])

	# 表情
	if card:
		var positive: Array = ["clue", "safe", "home", "landmark"]
		if card.type in positive:
			m.token.set_emotion("happy")
		else:
			m.token.set_emotion("default")

	GameData.set_demo_state("ready")
	m._camera_button.show_button()

	# 裂隙检查 (弹窗关闭后)
	if card and card.has_rift:
		m.board_visual.rift_show_on_card(card.row, card.col)
		_show_rift_confirm(card.row, card.col)
		return

	m.game_flow.check_defeat()

func on_shop_closed() -> void:
	GameData.set_demo_state("ready")
	m._camera_button.show_button()

# =========================================================================
# 相机模式
# =========================================================================

func _handle_camera_mode_click(card: Card, row: int, col: int) -> void:
	var film: int = GameData.get_resource("film")

	# 已翻开的怪物 → 驱魔
	if card.is_flipped and card.type == "monster" and not card.is_flipping:
		if film <= 0:
			m._vfx.action_banner("胶卷不足!", Color(0.86, 0.31, 0.31), 0.8)
			return
		# 相机驱除首见教程
		if not GameData.tutorial_flags.get("camera_exorcise_seen", false):
			GameData.tutorial_flags["camera_exorcise_seen"] = true
			m.show_tutorial(
				"现身的可以直接拍。\n比正面硬挡……安全一点。\n会消耗胶卷，省着用。",
				"白夜", TutorialBubble.IDLE_TIME_LONG
			)
		_do_exorcise(card, row, col)
		return

	# 已侦察的卡牌 → 再次查看
	if card.scouted and card.is_flipped and not card.is_flipping:
		GameData.set_demo_state("popup")
		m._event_popup.show_photo(card)
		return

	# 胶卷不足
	if film <= 0:
		m._vfx.action_banner("胶卷不足!", Color(0.86, 0.31, 0.31), 0.8)
		m._camera_button.shake_no_film()
		return

	# 未翻开 → 拍照
	if not card.is_flipped and not card.is_flipping:
		do_photograph(card, row, col)
	else:
		m.board_visual.play_shake_animation(row, col)
		m._vfx.action_banner("无法拍摄", Color(0.7, 0.7, 0.7), 0.6)

# ---------------------------------------------------------------------------
# 拍照逻辑
# ---------------------------------------------------------------------------

func do_photograph(card: Card, row: int, col: int) -> void:
	GameData.modify_resource("film", -1)
	GameData.photos_used += 1
	_photo_row = row
	_photo_col = col

	GameData.set_demo_state("photographing")
	m._camera_button.exit_camera_mode()
	m.token.set_emotion("determined")
	AudioManager.play_sfx("card_flip")

	# 快门闪光
	m._vfx.screen_flash(Color.WHITE, 0.5)
	m.token.hop(0.05)

	await m.get_tree().create_timer(0.25).timeout

	if not card.is_flipped and not card.is_flipping:
		card.is_flipping = true
		m.board.flip_card(row, col)

		m.board_visual.play_flip_animation(row, col, func():
			card.is_flipping = false
			m.board_visual.update_card_visual(row, col)

			# 粒子
			var center: Vector2 = m.board_visual.get_card_center(row, col)
			var tc: Color = GameTheme.card_type_color(card.type)
			m._vfx.spawn_burst(center, 8, tc)
			m._vfx.screen_shake(2.0, 0.1)

			GameData.cards_revealed += 1

			# -----------------------------------------------------------
			# 侦察=清除: 怪物/陷阱 → 先弹出照片弹窗，关闭后驱除，变为安全格 (photo)
			# -----------------------------------------------------------
			if card.type == "monster" or card.type == "trap":
				var is_monster: bool = (card.type == "monster")

				# 怪物: 在卡牌上显示 chibi
				if is_monster:
					m.board_visual.mg_show_on_card(row, col, card.location)
					GameData.monsters_slain += 1

				# — Phase 0: 弹出照片弹窗，让玩家看到拍到的东西
				m.token.set_emotion("scared" if is_monster else "nervous")
				GameData.set_demo_state("popup")
				_photo_row = -1
				_photo_col = -1

				# 传递怪物 chibi 贴图路径供弹窗叠加显示
				var monster_tex: String = ""
				if is_monster:
					monster_tex = MonsterGhost.get_monster_texture(card.location)
				_pending_exorcise = true
				m._event_popup.show_photo_with_chibi(card, monster_tex)
				await m._photo_popup.photo_popup_closed
				_pending_exorcise = false

				# — Phase 1: 认知状态过渡 (短暂停顿)
				GameData.set_demo_state("exorcising")
				await m.get_tree().create_timer(0.4).timeout

				# — Phase 2: 蓄力 (0.6s)
				var pc: Color = GameTheme.card_type_color("plot")
				m.token.set_emotion("determined")
				m.token.hop(0.04)
				# 卡牌 emission 蓄力发光
				m.board_visual.start_card_emission_glow(row, col,
					Color(0.6, 0.3, 1.0), 0.6, 2.0)

				await m.get_tree().create_timer(0.6).timeout

				# — Phase 3: 爆发
				m.token.set_emotion("angry")
				m.token.hop(0.06)
				# 冲击闪光 (白色)
				m._vfx.screen_flash(Color.WHITE, 0.5)
				m._vfx.screen_shake(5.0, 0.25)
				# 粒子爆发
				var center2: Vector2 = m.board_visual.get_card_center(row, col)
				m._vfx.spawn_burst(center2, 16, pc)

				# chibi 死亡动画 (抖动→膨胀→淡出)
				m.board_visual.mg_exorcise_card_ghosts()

				# 变形: 当前类型 → photo (安全格)
				card.type = "photo"
				m.board_visual.update_card_visual(row, col)

				# 卡牌翻转变形动画
				m.board_visual.play_exorcise_animation(row, col, func():
					# — Phase 4: 余韵
					m._vfx.screen_flash(pc, 0.25)
					m._vfx.spawn_burst(center2, 8, pc,
						{"speed": 50.0, "size": 2.0, "upward": 30.0})
					if is_monster:
						m._vfx.action_banner(
							"👻 发现怪物! 已驱除!", pc, 1.0)
					else:
						var trap_info: Dictionary = card.get_trap_subtype_info()
						m._vfx.action_banner(
							"⚡ 发现%s! 已清除!" % trap_info.get("label", "陷阱"),
							pc, 1.0)
					m._vfx.score_popup(center2 + Vector2(0, -20), "+10", pc)
					m.token.set_emotion("happy")
					GameData.set_demo_state("ready")
					m._camera_button.show_button()
				)
				return

			# -----------------------------------------------------------
			# 非危险格: 显示踪迹箭头 + 侦察预览弹窗
			# (先计算踪迹方向, 等 0.4s 后再显示幽灵 + 弹窗, 匹配 Lua 时序)
			# -----------------------------------------------------------
			var has_trail: bool = MonsterGhost.calculate_trail(card, m.board)

			GameData.set_demo_state("popup")
			await m.get_tree().create_timer(0.4).timeout

			if has_trail:
				m.board_visual.mg_show_trail_on_card(
					row, col, card.trail_dir_x, card.trail_dir_y)
			m._event_popup.show_photo(card)
		)
	else:
		m.token.set_emotion("default")
		GameData.set_demo_state("ready")

## 拍照弹窗关闭
func on_photo_popup_dismissed(_card_type: String) -> void:
	# cards_revealed 已在 do_photograph 翻牌回调中计数，此处不再重复

	# 怪物/陷阱情况：弹窗关闭后继续驱除流程，跳过此处的状态恢复
	if _pending_exorcise:
		return

	# 清除踪迹幽灵 (拍照结果弹窗关闭后)
	m.board_visual.mg_clear_trail_ghosts()

	# 只标记被拍照的那张卡牌为侦察 + 翻回
	if _photo_row > 0 and _photo_col > 0:
		var card: Card = m.board.get_card(_photo_row, _photo_col)
		if card and card.is_flipped and not card.scouted:
			card.scouted = true
			m.board.flip_back(_photo_row, _photo_col)
			m.board_visual.play_flip_back_animation(_photo_row, _photo_col)
		_photo_row = -1
		_photo_col = -1

	m.token.set_emotion("happy")
	GameData.set_demo_state("ready")
	m._camera_button.show_button()

# ---------------------------------------------------------------------------
# 驱魔逻辑
# ---------------------------------------------------------------------------

func _do_exorcise(card: Card, row: int, col: int, free_exorcise: bool = false) -> void:
	if free_exorcise:
		m._vfx.action_banner("🪔 驱魔香驱除!", GameTheme.safe, 0.8)
	elif GameData.remove_item("exorcism"):
		m._vfx.action_banner("🪔 驱魔香免费驱除!", GameTheme.safe, 0.8)
	else:
		GameData.modify_resource("film", -1)

	GameData.photos_used += 1
	GameData.monsters_slain += 1
	AudioManager.play_sfx("ghost_encounter")

	GameData.set_demo_state("exorcising")
	m._camera_button.exit_camera_mode()
	m.token.set_emotion("angry")
	m.token.hop(0.06)

	var pc: Color = GameTheme.card_type_color("plot")

	# — 蓄力: 卡牌 emission + 环绕 chibi 飞散
	m.board_visual.start_card_emission_glow(row, col,
		Color(0.6, 0.3, 1.0), 0.3, 2.5)
	m.board_visual.mg_scatter_surround()

	await m.get_tree().create_timer(0.3).timeout

	# — 爆发
	m._vfx.screen_flash(Color.WHITE, 0.5)
	m._vfx.screen_shake(5.0, 0.25)
	var center: Vector2 = m.board_visual.get_card_center(row, col)
	m._vfx.spawn_burst(center, 16, pc)

	# chibi 死亡动画
	m.board_visual.mg_exorcise_card_ghosts()

	card.type = "photo"
	m.board_visual.update_card_visual(row, col)

	m.board_visual.play_exorcise_animation(row, col, func():
		# — 余韵
		m._vfx.screen_flash(pc, 0.25)
		m._vfx.spawn_burst(center, 8, pc,
			{"speed": 50.0, "size": 2.0, "upward": 30.0})
		m._vfx.action_banner("驱除成功!", pc, 1.0)
		m._vfx.score_popup(center + Vector2(0, -20), "+10", pc)
		m.token.set_emotion("happy")
		GameData.set_demo_state("ready")
		m._camera_button.show_button()
	)

## 道具栏驱魔 (F4 快捷键)
func handle_inventory_exorcism() -> void:
	if GameData.demo_state != "ready":
		return

	if not GameData.remove_item("exorcism"):
		m._vfx.action_banner("没有驱魔香!", Color(0.86, 0.31, 0.31), 0.7)
		return

	var row: int = m.token.target_row
	var col: int = m.token.target_col
	var card: Card = m.board.get_card(row, col)

	if card == null:
		GameData.add_item("exorcism")
		m._vfx.action_banner("无效位置", Color(0.7, 0.7, 0.7), 0.6)
		return

	if card.is_flipped and card.type == "monster":
		# Phase 5: 使用道具 → 触发里程碑 hook
		MilestoneManager.try_trigger("use_item")
		_do_exorcise(card, row, col, true)
	else:
		GameData.add_item("exorcism")
		if not card.is_flipped:
			m._vfx.action_banner("需要先翻开卡牌!", Color(0.86, 0.63, 0.31), 0.7)
		else:
			m._vfx.action_banner("当前格子没有怪物", Color(0.7, 0.7, 0.7), 0.6)

# =========================================================================
# Phase 5: 故事事件 + NPC 对话辅助方法
# =========================================================================

## 尝试触发 StoryEventManager 故事事件 (plot/clue 翻牌时优先调用)
## 返回 true 表示事件已匹配并正在走对话流程; false 表示无匹配, 交由下级处理
func _try_story_event(card: Card, card_type: String, _row: int, _col: int) -> bool:
	var sem: StoryEventManager = m.game_flow.story_event_mgr
	if sem == null:
		return false

	var event = sem.query_event(card_type)
	if event == null:
		return false

	# 触发事件 (设置 onceFlag)
	event = sem.trigger_event(event)

	# 通过 game_flow 信号委托 main.gd 展示对话
	# 对话完成后应用效果 (碎片收集、里程碑 hook 等)
	m.game_flow.event_dialogue_requested.emit(event, func(chosen_id: String) -> void:
		var result: Dictionary = sem.on_event_complete(event, chosen_id)

		# 碎片收集通知
		if result.get("is_new_fragment", false):
			m._vfx.action_banner("获得记忆碎片: %s" % result.get("fragment_name", ""),
				Color(0.6, 0.4, 0.9), 1.0)

		# 线索收集通知
		if result.get("is_new_clue", false):
			m._vfx.action_banner("获得线索: %s" % result.get("clue_name", ""),
				Color(0.5, 0.8, 0.6), 1.0)
	)

	AudioManager.play_sfx("story_event")
	print("[CardInteraction] StoryEvent '%s' triggered for %s card" % [
		event.get("id", ""), card_type])
	return true

## 尝试触发中段事件 (玩家完成当日日程时调用)
## location: 到达的地点 key
## 返回 true 表示触发了对话; false 表示无匹配, 调用方应自行恢复 ready 状态
func _try_mid_day_event(location: String) -> bool:
	var sem: StoryEventManager = m.game_flow.story_event_mgr
	if sem == null:
		return false

	var event = sem.query_mid_event(location)
	if event == null:
		return false

	event = sem.trigger_mid_event(event)

	# 通过 event_dialogue_requested 信号委托 main.gd 展示对话
	m.game_flow.event_dialogue_requested.emit(event, func(chosen_id: String) -> void:
		var result: Dictionary = sem.on_mid_event_complete(event, chosen_id)

		if result.get("is_new_fragment", false):
			m._vfx.action_banner("获得记忆碎片: %s" % result.get("fragment_name", ""),
				Color(0.6, 0.4, 0.9), 1.0)

		GameData.set_demo_state("ready")
		m._camera_button.show_button()
		m.game_flow.check_defeat()
	)

	print("[CardInteraction] Mid-day event '%s' triggered for location '%s'" % [
		event.get("id", ""), location])
	return true

## NPC 点击对话: 点击棋盘上的 NPC sprite 时触发
func handle_npc_click(row: int, col: int) -> void:
	var npc_mgr: NPCManager = m.game_flow.npc_manager
	if npc_mgr == null:
		return

	var npc: NPCManager.NPCData = npc_mgr.get_npc_at(row, col)
	if npc == null:
		return

	# 获取随机对话组
	var lines: Array = npc_mgr.get_random_dialogue(npc.id)
	if lines.is_empty():
		return

	print("[CardInteraction] NPC dialogue triggered: %s at (%d,%d)" % [npc.npc_name, row, col])
	AudioManager.play_sfx("npc_talk")

	# 通过对话系统展示 NPC 对话
	GameData.set_demo_state("popup")
	m.token.set_emotion("surprised")

	# 构建对话 + 选项数据, 委托对话系统
	if m._dialogue_system:
		m._dialogue_system.start(
			lines,
			npc.tex_path,
			"",
			func() -> void:
				# 读取玩家选择的选项并执行 action
				var selected: Dictionary = m._dialogue_system.get_selected_choice()
				if not selected.is_empty() and selected.get("action", "none") != "none":
					npc_mgr.execute_choice_action(npc.id, selected)
				m.token.set_emotion("default")
				GameData.set_demo_state("ready")
				m._camera_button.show_button()
		)


# =========================================================================
# Phase 5: BFS 自动寻路
# =========================================================================

## BFS 寻找从 (sr,sc) 到 (er,ec) 的最短路径 (沿已翻开卡牌)
## 中间格子必须 is_flipped; 目标格子无此限制 (到达后会自动翻面)
## 返回路径数组 [{row, col}, ...] (不含起点, 含终点), 空数组表示不可达
func _find_path(sr: int, sc: int, er: int, ec: int) -> Array:
	var board: Board = m.board
	var dirs: Array = [[-1, 0], [1, 0], [0, -1], [0, 1]]

	# key 函数: 5x5 棋盘, r*10+c 保证唯一
	var visited: Dictionary = {}
	var parent: Dictionary = {}
	var queue: Array = []

	var start_key: int = sr * 10 + sc
	visited[start_key] = true
	queue.append([sr, sc])
	var head: int = 0

	while head < queue.size():
		var cr: int = queue[head][0]
		var cc: int = queue[head][1]
		head += 1

		for d in dirs:
			var nr: int = cr + d[0]
			var nc: int = cc + d[1]
			if nr < 1 or nr > Board.ROWS or nc < 1 or nc > Board.COLS:
				continue
			var nk: int = nr * 10 + nc
			if visited.has(nk):
				continue

			var card: Card = board.get_card(nr, nc)
			if card == null:
				continue

			var is_target: bool = (nr == er and nc == ec)
			# 中间格子必须已翻开; 目标格子无限制
			if is_target or card.is_flipped:
				visited[nk] = true
				parent[nk] = [cr, cc]

				if is_target:
					# 回溯重建路径
					var path: Array = []
					var pr: int = nr
					var pc: int = nc
					while pr != sr or pc != sc:
						path.insert(0, {"row": pr, "col": pc})
						var prev: Array = parent[pr * 10 + pc]
						pr = prev[0]
						pc = prev[1]
					return path

				queue.append([nr, nc])

	return []  # 不可达

## 沿 BFS 路径逐步自动行走
func _execute_auto_walk(path: Array) -> void:
	GameData.set_demo_state("moving")
	m.board_visual.mg_clear_surround()
	m._camera_button.hide_button()
	m.token.set_emotion("running")

	_walk_step(path, 0)

## 递归执行自动行走的每一步
func _walk_step(path: Array, step_idx: int) -> void:
	var step: Dictionary = path[step_idx]
	var row: int = step["row"]
	var col: int = step["col"]
	var is_last: bool = (step_idx == path.size() - 1)

	_steps_today += 1
	_sync_steps_to_gamedata()
	m.token.target_row = row
	m.token.target_col = col

	m.board_visual.animate_token_move(row, col, func():
		# 道具拾取
		m.game_flow.try_collect_item(row, col)

		if is_last:
			# 最后一步: 翻牌或恢复状态
			var arrived_card: Card = m.board.get_card(row, col)
			if arrived_card and not arrived_card.is_flipped and not arrived_card.is_flipping:
				GameData.set_demo_state("flipping")
				m.board.flip_card(row, col)
				arrived_card.is_flipping = true
				m.board_visual.play_flip_animation(row, col, func():
					arrived_card.is_flipping = false
					m.board_visual.update_card_visual(row, col)
					_on_card_flipped(arrived_card, row, col)
				)
			else:
				# 已翻开格子: 检查日程到达 + 中段事件
				var walk_mid_loc: String = ""
				if arrived_card and arrived_card.is_flipped and arrived_card.location != "":
					var completed: Dictionary = m.card_manager.complete_schedule_at(arrived_card.location)
					if not completed.is_empty():
						walk_mid_loc = arrived_card.location
						m.board_visual.hide_destination_hint(walk_mid_loc)
						var reward: Array = completed.get("reward", [])
						if reward.size() >= 2:
							GameData.modify_resource(reward[0], reward[1])
							m._vfx.action_banner("日程完成! %s +%d" % [reward[0], reward[1]],
								Color(0.4, 0.8, 0.5), 0.8)
				m.token.set_emotion("default")
				if walk_mid_loc != "" and not _try_mid_day_event(walk_mid_loc):
					GameData.set_demo_state("ready")
					m._camera_button.show_button()
				elif walk_mid_loc == "":
					GameData.set_demo_state("ready")
					m._camera_button.show_button()
				# else: 对话完成回调里恢复 ready
		else:
			# 中间步: 检查日程到达, 然后继续下一步
			var mid_card: Card = m.board.get_card(row, col)
			if mid_card and mid_card.is_flipped and mid_card.location != "":
				var completed: Dictionary = m.card_manager.complete_schedule_at(mid_card.location)
				if not completed.is_empty():
					m.board_visual.hide_destination_hint(mid_card.location)
					var reward: Array = completed.get("reward", [])
					if reward.size() >= 2:
						GameData.modify_resource(reward[0], reward[1])
						m._vfx.action_banner("日程完成! %s +%d" % [reward[0], reward[1]],
							Color(0.4, 0.8, 0.5), 0.8)
			_walk_step(path, step_idx + 1)
	)

# =========================================================================
