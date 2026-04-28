## GameFlow - 游戏流程控制器
## 负责: 发牌编排、日期推进、日终结算、胜负判定、道具生成
extends RefCounted

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const MAX_DAYS: int = 3

# ---------------------------------------------------------------------------
# 引用 (由 main.gd 注入)
# ---------------------------------------------------------------------------
var m = null  # 主场景引用

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func setup(main_ref) -> void:
	m = main_ref

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
	GameData.current_day = m.day_count
	GameData.set_demo_state("dealing")
	m._vfx.action_banner("第 %d 天" % m.day_count, Color.WHITE, 1.2)
	m.board_visual.start_deal_animation(_on_deal_complete)

func _on_deal_complete() -> void:
	GameData.set_demo_state("ready")

	# Token 出现在 "家"
	var home_row: int = m.board.home_row
	var home_col: int = m.board.home_col
	m.token.target_row = home_row
	m.token.target_col = home_col
	m.token.visible = true
	m.token.alpha = 1.0
	m.board_visual.update_token_visual()

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
	_animate_item_spawn()

	# 通知 HandPanel 刷新并显示
	if m._hand_panel:
		m._hand_panel.setup(m.card_manager)
		m._hand_panel.show_panel()

## 道具弹出动画
func _animate_item_spawn() -> void:
	for i in range(m.board_items.items.size()):
		var item: BoardItems.BoardItem = m.board_items.items[i]
		var delay: float = 0.3 + i * 0.15
		var tw: Tween = m.create_tween()
		tw.tween_property(item, "scale", 1.0, 0.3) \
			.set_delay(delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		var tw2: Tween = m.create_tween()
		tw2.tween_property(item, "alpha", 1.0, 0.2).set_delay(delay)
		var tw3: Tween = m.create_tween()
		tw3.tween_property(item, "glow_alpha", 1.0, 0.3).set_delay(delay)

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

	# 恢复资源
	GameData.modify_resource("san", 1)
	GameData.modify_resource("order", 1)
	var current_film: int = GameData.get_resource("film")
	if current_film < 3:
		GameData.modify_resource("film", 3 - current_film)
	GameData.modify_resource("money", 10)

	GameData.set_demo_state("dealing")
	m.token.visible = false
	m.board_items.clear()

	m.day_count += 1
	GameData.current_day = m.day_count

	if m.day_count > MAX_DAYS:
		_trigger_victory()
		return

	m._date_transition.play(m.day_count)

## 日期过渡完成回调 (由 main.gd 信号桥接)
func on_date_transition_complete() -> void:
	m.board = Board.new()
	generate_board()
	start_deal()

# ---------------------------------------------------------------------------
# 胜负判定
# ---------------------------------------------------------------------------

func check_defeat() -> void:
	if GameData.game_phase != "playing":
		return
	if GameData.check_defeat():
		GameData.set_game_phase("gameover")
		GameData.set_demo_state("idle")
		m.token.set_emotion("dead")
		m._vfx.screen_shake(8.0, 0.4, 20.0)
		m._vfx.screen_flash(Color(0.7, 0.12, 0.12, 0.78), 0.5)
		m._game_over.show_result(false, GameData.get_stats())

func _trigger_victory() -> void:
	GameData.set_game_phase("gameover")
	GameData.set_demo_state("idle")
	m.token.set_emotion("happy")
	m._vfx.screen_flash(Color(1.0, 0.84, 0.39, 0.7), 0.5)
	m._game_over.show_result(true, GameData.get_stats())

# ---------------------------------------------------------------------------
# 道具拾取
# ---------------------------------------------------------------------------

## 尝试拾取当前格子道具, 返回拾取结果
func try_collect_item(row: int, col: int) -> Dictionary:
	var result: Dictionary = m.board_items.try_collect(row, col)
	if result.is_empty():
		return {}

	var item_key: String = result["key"]
	var item_label: String = result["label"]
	var item_icon: String = result["icon"]

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
	pick.scouted = true
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

	# 重置数据和核心对象
	GameData.reset()
	m.card_manager = CardManager.new()
	m.board = Board.new()
	m.board_items.clear()
	
	# 重置暗面世界 (用 reset() 保留回调注入)
	m.dark_world.reset()
	
	# 退出相机模式（如果正在拍照）
	if m._camera_button.is_camera_mode():
		m._camera_button.exit_camera_mode()
	
	# 隐藏/重置所有 UI 面板
	m._resource_bar.set_dark_mode(false)
	m._event_popup.clear_toasts()
	if m._shop_popup.is_active():
		m._shop_popup.close_shop()
	if m._dialogue_system.is_active():
		m._dialogue_system.reset()
	
	# 重新生成棋盘
	generate_board()
	m.token = Token.new()
	m.token.load_textures()
	
	# 重新显示手牌面板
	m._hand_panel.setup(m.card_manager)
	m._hand_panel.show_panel()

	GameData.set_game_phase("playing")
	start_deal()
