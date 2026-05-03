## EventHandler - 统一事件处理系统
## 所有事件效果统一通过此模块处理，Real World 和 Dark World 共用
class_name EventHandler
extends RefCounted

# ============================================================================
# 事件类型枚举 (统一所有事件类型)
# ============================================================================

enum EventType {
	NONE = 0,           # 无效果
	SAFE = 1,           # 安全区域 (home/landmark)
	MONSTER = 2,        # 怪物遭遇
	TRAP = 3,           # 陷阱触发
	SHOP = 4,           # 商店入口
	CLUE = 5,           # 线索发现
	PLOT = 6,           # 剧情事件
	ITEM = 7,           # 道具拾取
	INTEL = 8,          # 情报购买
	CHECKPOINT = 9,     # 检查点
	PASSAGE = 10,       # 层间通道
	ABYSS_CORE = 11,    # 深渊核心
	NPC_DIALOGUE = 12,  # NPC对话
	PHOTO = 13,         # 拍照结果
	DARK_CLUE = 14,     # 暗世界线索
	DARK_ITEM = 15,     # 暗世界道具
}

# ============================================================================
# 事件结果
# ============================================================================

class EventResult:
	var event_type: EventType = EventType.NONE
	var is_blocking: bool = false           # 是否需要弹窗确认
	var auto_apply: bool = true            # 是否自动应用效果
	var effects: Dictionary = {}           # 资源变化 { "san": -1, "money": -10 }
	var message: String = ""               # 显示消息
	var popup_data: Dictionary = {}        # 弹窗数据
	var on_complete: Callable = Callable() # 完成回调
	
	func _to_string() -> String:
		return "EventResult(type=%s, blocking=%s, effects=%s)" % [event_type, is_blocking, effects]

# ============================================================================
# 引用 (由 main.gd 注入)
# ============================================================================

var _main: Node = null

func setup(main_ref) -> void:
	_main = main_ref

# ============================================================================
# 表情映射 (统一)
# ============================================================================

static func get_emotion_for_event(event_type: EventType) -> String:
	match event_type:
		EventType.MONSTER: return "scared"
		EventType.TRAP: return "nervous"
		EventType.SHOP: return "confused"
		EventType.CLUE: return "surprised"
		EventType.SAFE: return "relieved"
		EventType.ITEM: return "happy"
		EventType.INTEL: return "confused"
		EventType.NPC_DIALOGUE: return "surprised"
		EventType.ABYSS_CORE: return "scared"
		EventType.DARK_CLUE: return "surprised"
	return "default"

# ============================================================================
# 事件类型转换 (兼容旧代码)
# ============================================================================

static func is_blocking_type(event_type: EventType) -> bool:
	match event_type:
		EventType.SHOP, EventType.NPC_DIALOGUE:
			return true
	return false

# ============================================================================
# 统一入口: 从 Real World Card 解析事件
# ============================================================================

func parse_real_world_card(card: Card) -> EventResult:
	var result := EventResult.new()
	result.event_type = _card_type_to_event_type(card.type)
	result.effects = card.get_effects()
	result.auto_apply = true
	
	match card.type:
		"home", "landmark":
			result.event_type = EventType.SAFE
			result.message = "安全区域"
		
		"shop":
			result.event_type = EventType.SHOP
			result.is_blocking = true
			result.auto_apply = false
			result.popup_data = { "card": card }
		
		"monster":
			result.event_type = EventType.MONSTER
			# 检查护盾
			if GameData.has_item("shield"):
				result.effects = {}
				result.message = "护身符抵消了伤害!"
		
		"trap":
			result.event_type = EventType.TRAP
			if GameData.has_item("shield"):
				result.effects = {}
				result.message = "护身符抵消了陷阱!"
		
		"plot":
			result.event_type = EventType.PLOT
			var story_evt: Dictionary = StoryManager.pick_plot_event()
			if not story_evt.is_empty():
				var apply_result: Dictionary = StoryManager.apply_event_effects(story_evt)
				if apply_result.get("is_new_clue"):
					result.message = "获得线索: %s" % apply_result["clue_name"]
		
		"clue":
			result.event_type = EventType.CLUE
			var clue_evt: Dictionary = StoryManager.pick_clue_event()
			if not clue_evt.is_empty():
				var apply_result: Dictionary = StoryManager.apply_event_effects(clue_evt)
				if apply_result.get("is_new_clue"):
					result.message = "获得线索: %s" % apply_result["clue_name"]
	
	return result

# ============================================================================
# 统一入口: 从 Dark World Card 解析事件
# ============================================================================

func parse_dark_world_card(card: Card, row: int, col: int, day_count: int) -> EventResult:
	var result := EventResult.new()
	result.event_type = _dark_type_to_event_type(card.dark_type)
	
	match card.dark_type:
		"normal":
			result.event_type = EventType.NONE
		
		"shop":
			result.event_type = EventType.SHOP
			result.is_blocking = true
			result.auto_apply = false
			result.popup_data = { "name": card.dark_name }
		
		"intel":
			result.event_type = EventType.INTEL
			var cost: int = 15
			result.effects = { "money": -cost }
			result.popup_data = { "cost": cost }
		
		"checkpoint":
			result.event_type = EventType.CHECKPOINT
			result.message = "检查点"
		
		"clue":
			if not card.dark_collected:
				result.event_type = EventType.CLUE
				result.message = card.dark_name
				result.effects = { "san": 1 }
				card.dark_collected = true
			else:
				result.event_type = EventType.NONE
		
		"item":
			if not card.dark_collected:
				result.event_type = EventType.ITEM
				var rewards: Array = [["san", 10], ["money", 20], ["film", 1]]
				var pick: Array = rewards[randi() % rewards.size()]
				result.effects = { pick[0]: pick[1] }
				result.message = "获得 %s +%d" % [pick[0], pick[1]]
				card.dark_collected = true
			else:
				result.event_type = EventType.NONE
		
		"passage":
			result.event_type = EventType.PASSAGE
			result.auto_apply = false
		
		"abyss_core":
			result.event_type = EventType.ABYSS_CORE
			result.message = "深渊核心..."
	
	return result

# ============================================================================
# 统一入口: 从 NPC 数据解析事件
# ============================================================================

func parse_npc_dialogue(npc_data: Dictionary) -> EventResult:
	var result := EventResult.new()
	result.event_type = EventType.NPC_DIALOGUE
	result.is_blocking = true
	result.auto_apply = false
	result.popup_data = npc_data
	return result

# ============================================================================
# 执行事件效果
# ============================================================================

func execute_event(result: EventResult, card: Card = null) -> void:
	# 应用资源效果
	for key in result.effects:
		GameData.modify_resource(key, result.effects[key])

	# 应用 set_flags + clue_id（事件驱动的剧情效果）
	var set_flags: Dictionary = result.popup_data.get("set_flags", {})
	if not set_flags.is_empty():
		for key in set_flags:
			if key == "current_chapter":
				StoryManager.set_chapter(str(set_flags[key]))
			else:
				StoryManager.set_flag(key, set_flags[key])

	var clue_id: String = str(result.popup_data.get("clue_id", ""))
	if clue_id != "":
		var is_new: bool = StoryManager.collect_clue(clue_id)
		if is_new:
			var info: Dictionary = StoryManager.get_clue_info(clue_id)
			var clue_name: String = info.get("name", clue_id)
			if _main:
				_main._vfx.action_banner("获得线索: %s" % clue_name,
					Color(0.5, 0.8, 0.6), 1.0)

	# 显示消息
	if result.message != "":
		var color: Color = GameTheme.info
		if result.event_type == EventType.SAFE:
			color = GameTheme.safe
		elif result.event_type in [EventType.MONSTER, EventType.TRAP]:
			color = Color(0.86, 0.31, 0.31)
		if _main:
			_main._vfx.action_banner(result.message, color, 0.8)

	# 显示弹窗
	if result.is_blocking:
		match result.event_type:
			EventType.SHOP:
				if _main:
					_main._shop_popup.open_shop()
			EventType.NPC_DIALOGUE:
				var dialogue: Array = result.popup_data.get("dialogue", [])
				var tex: String = result.popup_data.get("tex", "")
				if _main:
					_main._dialogue_system.start(dialogue, tex, result.on_complete)

	# 执行回调
	if result.on_complete.is_valid():
		result.on_complete.call()

# ============================================================================
# 辅助方法
# ============================================================================

## Real World 卡牌类型 → 统一事件类型
static func _card_type_to_event_type(card_type: String) -> EventType:
	match card_type:
		"home", "landmark": return EventType.SAFE
		"monster": return EventType.MONSTER
		"trap": return EventType.TRAP
		"shop": return EventType.SHOP
		"clue": return EventType.CLUE
		"plot": return EventType.PLOT
		"photo": return EventType.PHOTO
	return EventType.NONE

## Dark World 卡牌类型 → 统一事件类型
static func _dark_type_to_event_type(dark_type: String) -> EventType:
	match dark_type:
		"normal": return EventType.NONE
		"shop": return EventType.SHOP
		"intel": return EventType.INTEL
		"checkpoint": return EventType.CHECKPOINT
		"clue": return EventType.DARK_CLUE
		"item": return EventType.DARK_ITEM
		"passage": return EventType.PASSAGE
		"abyss_core": return EventType.ABYSS_CORE
	return EventType.NONE

# ============================================================================
# 统一入口: resolve_event (Phase 3 新增)
# 根据 event_id 或 card 数据解析事件，统一处理明面/暗面
# ============================================================================

## 从已知 event_id 解析事件结果（优先路径）
## 当 card 携带 event_id 时，效果/文本/flags/clue 全部从 EventPool 事件定义驱动
func resolve_event_by_id(event_id: String, card: Card = null) -> EventResult:
	var evt: Dictionary = EventPool.get_event(event_id)
	if evt.is_empty():
		push_warning("EventHandler: 未知 event_id '%s', 降级为 NONE" % event_id)
		return EventResult.new()
	return _build_result_from_event(evt, card)

## 从事件定义构建 EventResult
func _build_result_from_event(evt: Dictionary, card: Card = null) -> EventResult:
	var result := EventResult.new()
	var evt_type: String = evt.get("type", "safe")
	result.event_type = _string_to_event_type(evt_type)

	# 效果
	var effects: Dictionary = evt.get("effects", {})
	if evt_type == "trap" and effects.is_empty():
		# trap 类型走子类型逻辑
		var sub_key: String = evt.get("trap_subtype", "random")
		if sub_key == "random":
			sub_key = EventPool.get_random_trap_subtype()
		var sub: Dictionary = EventPool.get_trap_subtype(sub_key)
		effects = sub.get("effect", {})
		# 同步 trap_subtype 到 card
		if card:
			card.trap_subtype = sub_key

	# item 类型随机奖励
	if evt_type == "item" and effects.is_empty():
		var rewards: Array = evt.get("item_rewards", [])
		if rewards.size() > 0:
			var pick: Array = rewards[randi() % rewards.size()]
			if pick.size() >= 2:
				effects = { pick[0]: int(pick[1]) }

	result.effects = effects

	# 文本
	var texts: Array = evt.get("texts", [])
	if texts.size() > 0:
		result.message = texts[randi() % texts.size()]

	# 阻塞判断
	var is_blocking_override = evt.get("is_blocking")
	if is_blocking_override != null:
		result.is_blocking = bool(is_blocking_override)
	else:
		result.is_blocking = EventPool.is_blocking_type(evt_type)

	result.auto_apply = not result.is_blocking

	# 弹窗数据
	if result.is_blocking and card:
		result.popup_data = { "card": card }

	# 护盾检查（怪物/陷阱）
	if evt_type == "monster" or evt_type == "trap":
		if GameData.has_item("shield"):
			result.effects = {}
			result.message = "护身符抵消了伤害!"

	# 剧情事件: set_flags + clue_id
	if evt.has("set_flags") and not evt["set_flags"].is_empty():
		result.popup_data["set_flags"] = evt["set_flags"]
	if evt.has("clue_id") and evt["clue_id"] != null and evt["clue_id"] != "":
		result.popup_data["clue_id"] = evt["clue_id"]

	return result

## 检查事件条件，不满足时返回降级后的事件类型字符串
## 返回 "" 表示条件满足（不需要降级）
func _check_event_condition(evt: Dictionary) -> String:
	var cond = evt.get("condition")
	if cond == null:
		return ""  # 无条件，通过
	if StoryManager.check_condition(cond):
		return ""  # 条件满足
	# 条件不满足 → 降级
	var fallback = evt.get("fallback_type")
	if fallback != null and fallback != "":
		return fallback
	return "safe"

## 字符串事件类型 → EventType 枚举
static func _string_to_event_type(type_str: String) -> EventType:
	match type_str:
		"safe", "home", "landmark": return EventType.SAFE
		"monster": return EventType.MONSTER
		"trap": return EventType.TRAP
		"shop": return EventType.SHOP
		"clue": return EventType.CLUE
		"plot": return EventType.PLOT
		"photo": return EventType.PHOTO
		"item": return EventType.ITEM
		"intel": return EventType.INTEL
		"checkpoint": return EventType.CHECKPOINT
		"passage": return EventType.PASSAGE
		"abyss_core": return EventType.ABYSS_CORE
		"reward": return EventType.SAFE  # reward 归为安全类（资源效果已内置）
	return EventType.NONE

# ============================================================================
# 辅助方法
# ============================================================================

## 获取事件类型名称
static func get_event_type_name(event_type: EventType) -> String:
	match event_type:
		EventType.NONE: return "无"
		EventType.SAFE: return "安全"
		EventType.MONSTER: return "怪物"
		EventType.TRAP: return "陷阱"
		EventType.SHOP: return "商店"
		EventType.CLUE: return "线索"
		EventType.PLOT: return "剧情"
		EventType.ITEM: return "道具"
		EventType.INTEL: return "情报"
		EventType.CHECKPOINT: return "检查点"
		EventType.PASSAGE: return "通道"
		EventType.ABYSS_CORE: return "深渊"
		EventType.NPC_DIALOGUE: return "对话"
		EventType.PHOTO: return "拍照"
		EventType.DARK_CLUE: return "暗线索"
		EventType.DARK_ITEM: return "暗道具"
	return "未知"
