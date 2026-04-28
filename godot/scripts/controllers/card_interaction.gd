## CardInteraction - 卡牌交互控制器
## 负责: 普通点击(翻牌/移动)、相机模式(拍照/驱魔)、
##       NPC 对话触发、裂隙确认、道具使用
extends RefCounted

# ---------------------------------------------------------------------------
# 引用 (由 main.gd 注入)
# ---------------------------------------------------------------------------
var m = null

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func setup(main_ref) -> void:
	m = main_ref

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

	# 检查相邻
	if not m.board.is_adjacent(m.token.target_row, m.token.target_col, row, col):
		m._vfx.action_banner("只能移动到相邻格子", Color(0.7, 0.7, 0.7), 0.6)
		return

	# 移动 Token
	_move_token(card, row, col)

# ---------------------------------------------------------------------------
# 翻牌
# ---------------------------------------------------------------------------

func _flip_current_card(card: Card, row: int, col: int) -> void:
	GameData.set_demo_state("flipping")
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
	m.token.target_row = row
	m.token.target_col = col
	m.token.set_emotion("running")

	# 道具拾取
	m.game_flow.try_collect_item(row, col)

	m.board_visual.animate_token_move(row, col, func():
		var arrived_card: Card = m.board.get_card(row, col)
		if arrived_card and not arrived_card.is_flipped:
			GameData.set_demo_state("flipping")
			m.board.flip_card(row, col)
			arrived_card.is_flipping = true

			m.board_visual.play_flip_animation(row, col, func():
				arrived_card.is_flipping = false
				m.board_visual.update_card_visual(row, col)
				_on_card_flipped(arrived_card, row, col)
			)
		else:
			m.token.set_emotion("default")
			GameData.set_demo_state("ready")
			m._camera_button.show_button()
	)

# ---------------------------------------------------------------------------
# 翻牌后效果处理
# ---------------------------------------------------------------------------

func _on_card_flipped(card: Card, row: int, col: int) -> void:
	var card_type: String = card.type
	GameData.cards_revealed += 1

	# 地标光环净化已在 board.generate_cards() 阶段完成 (_apply_landmark_aura)
	# 地标邻近的 monster/trap 在生成时已转为 safe，翻牌时无需重复净化

	# 日程完成检查
	if card.location != "":
		var completed: Dictionary = m.card_manager.complete_schedule_at(card.location)
		if not completed.is_empty():
			var reward: Array = completed.get("reward", [])
			if reward.size() >= 2:
				GameData.modify_resource(reward[0], reward[1])
				m._vfx.action_banner("日程完成! %s +%d" % [reward[0], reward[1]],
					Color(0.4, 0.8, 0.5), 0.8)

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
			_show_rift_confirm(row, col)
		return

	m._vfx.screen_shake(3.0, 0.15)

	# 陷阱走 Toast 流 (非阻塞)
	if card_type == "trap":
		_handle_trap(card, row, col)
		return

	# 判断是否阻断
	var is_blocking: bool = EventPopup.is_blocking_event(card_type)

	if is_blocking:
		# 阻断事件: 商店 (未来: 带选项的剧情)
		GameData.set_demo_state("popup")
		m._camera_button.hide_button()
		await m.get_tree().create_timer(0.4).timeout
		if card_type == "shop":
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

		# 线索: 触发传闻
		if card_type == "clue":
			m._vfx.action_banner("发现了新线索!", GameTheme.info, 0.8)

		# Toast 通知
		m._event_popup.show_toast(card_type, effects, shield_used, card.location)

		GameData.set_demo_state("ready")
		m._camera_button.show_button()

		# 裂隙检查
		if card.has_rift:
			_show_rift_confirm(row, col)
			return

		m.game_flow.check_defeat()

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

		# 特殊: 传送陷阱
		if card.trap_subtype == "teleport":
			_teleport_to_random()

	# Toast 通知
	m._event_popup.show_toast(card.type, card.get_effects(),
		shield_used, card.location, card.trap_subtype)

	GameData.set_demo_state("ready")
	m._camera_button.show_button()

	# 裂隙检查
	if card.has_rift:
		_show_rift_confirm(row, col)

	m.game_flow.check_defeat()

## 传送到随机未翻开格子
func _teleport_to_random() -> void:
	var unflipped: Array = m.board.get_unflipped_cards()
	if unflipped.is_empty():
		return
	var pick: Card = unflipped[randi() % unflipped.size()]
	m.token.target_row = pick.row
	m.token.target_col = pick.col
	m.board_visual.update_token_visual()
	m._vfx.screen_flash(Color(0.6, 0.2, 0.8, 0.5), 0.3)
	m._vfx.action_banner("空间错位!", Color(0.6, 0.2, 0.8), 0.8)

# ---------------------------------------------------------------------------
# 裂隙确认
# ---------------------------------------------------------------------------

func _show_rift_confirm(row: int, col: int) -> void:
	var center: Vector2 = m.board_visual.get_card_center(row, col)
	GameData.set_demo_state("rift_confirm")
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
		m._vfx.action_banner("无法拍摄", Color(0.7, 0.7, 0.7), 0.6)

# ---------------------------------------------------------------------------
# 拍照逻辑
# ---------------------------------------------------------------------------

func do_photograph(card: Card, row: int, col: int) -> void:
	GameData.modify_resource("film", -1)
	GameData.photos_used += 1

	GameData.set_demo_state("photographing")
	m._camera_button.exit_camera_mode()
	m.token.set_emotion("determined")

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

			# 弹窗
			GameData.set_demo_state("popup")
			await m.get_tree().create_timer(0.4).timeout
			m._event_popup.show_photo(card)
		)
	else:
		m.token.set_emotion("default")
		GameData.set_demo_state("ready")

## 拍照弹窗关闭
func on_photo_popup_dismissed(_card_type: String) -> void:
	GameData.cards_revealed += 1

	# 标记侦察 + 翻回
	for r in range(1, Board.ROWS + 1):
		for c in range(1, Board.COLS + 1):
			var card: Card = m.board.get_card(r, c)
			if card and card.is_flipped and not card.scouted:
				card.scouted = true
				m.board.flip_back(r, c)
				m.board_visual.play_flip_back_animation(r, c)

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

	GameData.set_demo_state("exorcising")
	m._camera_button.exit_camera_mode()
	m.token.set_emotion("angry")

	# 闪光 + 震动
	var pc: Color = GameTheme.card_type_color("plot")
	m._vfx.screen_flash(pc, 0.5)
	m._vfx.screen_shake(4.0, 0.2)
	m.token.hop(0.06)

	await m.get_tree().create_timer(0.3).timeout

	card.type = "photo"
	m.board_visual.update_card_visual(row, col)

	m.board_visual.play_exorcise_animation(row, col, func():
		var center: Vector2 = m.board_visual.get_card_center(row, col)
		m._vfx.spawn_burst(center, 16, pc)
		m._vfx.action_banner("驱除成功!", pc, 1.0)
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
		_do_exorcise(card, row, col, true)
	else:
		GameData.add_item("exorcism")
		if not card.is_flipped:
			m._vfx.action_banner("需要先翻开卡牌!", Color(0.86, 0.63, 0.31), 0.7)
		else:
			m._vfx.action_banner("当前格子没有怪物", Color(0.7, 0.7, 0.7), 0.6)
