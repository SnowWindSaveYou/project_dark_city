## Card - 卡牌数据定义与工厂
## 对应原版 Card.lua (数据部分)
## @description 表示棋盘上的一张卡牌，包含地点、事件类型、状态等信息
class_name Card
extends RefCounted

# ---------------------------------------------------------------------------
# 常量: 卡牌物理尺寸 (3D 世界坐标, 单位: 米)
# 建议通过 GameConfig 读取，此处保留用于向后兼容
# ---------------------------------------------------------------------------
## @deprecated 请使用 GameConfig.get_card_width()
const CARD_W: float = 0.64
## @deprecated 请使用 GameConfig.get_card_height()
const CARD_H: float = 0.90
## @deprecated 请使用 GameConfig.get_card_thickness()
const CARD_THICKNESS: float = 0.015

# ---------------------------------------------------------------------------
# 结构常量 (保留在代码中，不外部化)
# ---------------------------------------------------------------------------
const REGULAR_LOCATIONS: Array = [
	"company", "school", "park", "alley",
	"station", "hospital", "library", "bank",
	"cemetery", "gym",
]

const LANDMARK_LOCATIONS: Array = ["church", "police"]

# ---------------------------------------------------------------------------
# 实例属性
# ---------------------------------------------------------------------------
var location: String = ""         # 地点 key
var type: String = ""             # 事件类型 key
var row: int = 0                  # 棋盘行 (1-based)
var col: int = 0                  # 棋盘列 (1-based)
var is_flipped: bool = false      # 是否已翻开
var is_dealt: bool = false        # 是否已发到棋盘
var scouted: bool = false         # 是否被相机侦察过
var revealed: bool = false        # 是否被地图碎片揭示过
var is_flipping: bool = false     # 是否正在翻转动画中
var event_id: String = ""         # 事件池事件 ID（关联 EventPool 定义）

# --- 暗面世界字段 ---
var is_dark: bool = false         # 是否是暗面卡牌
var dark_type: String = ""        # 暗面卡牌类型 (normal/shop/passage/abyss_core/...)
var dark_name: String = ""        # 暗面卡牌显示名
var dark_icon: String = ""        # 暗面卡牌图标
var dark_collected: bool = false  # 暗面道具/线索是否已被收集

# --- 陷阱/裂隙 ---
var trap_subtype: String = ""     # 陷阱子类型 (sanity/money/film/teleport)
var has_rift: bool = false        # 是否伪装了裂隙入口

# --- MonsterGhost 踪迹 ---
var trail_dir_x: float = 0.0     # 踪迹方向 (列偏移)
var trail_dir_y: float = 0.0     # 踪迹方向 (行偏移)
var has_trail: bool = false      # 是否有踪迹记录

# --- 光晕 ---
var safe_glow_active: bool = false  # 安全区光环是否激活
var glow_intensity: float = 0.0     # 翻牌闪光强度 0-1 (渲染层使用)

# --- 悬停 ---
var hover_t: float = 0.0             # 悬停插值 0→1 (渲染层使用)

# ---------------------------------------------------------------------------
# 方法
# ---------------------------------------------------------------------------

## 获取暗面信息 (显示用图标和标签)
func get_darkside_info() -> Dictionary:
	if type in ["landmark", "home", "shop"]:
		var loc_data: Dictionary = Locations.get_real_location(location)
		if not loc_data.is_empty():
			return { "icon": loc_data.get("icon", "❓"), "label": loc_data.get("label", "未知") }
		# fallback: CardConfig
		var loc_info: Dictionary = CardConfig.location_info.get(location, { "icon": "❓", "label": "未知" })
		return { "icon": loc_info["icon"], "label": loc_info["label"] }
	# 优先从 Locations 获取暗面显示
	var dark_disp: Dictionary = Locations.get_dark_display(location)
	if not dark_disp.is_empty() and type in dark_disp:
		return dark_disp[type]
	# fallback: CardConfig.darkside_info
	var ds: Dictionary = CardConfig.darkside_info
	if location in ds and type in ds[location]:
		return ds[location][type]
	# fallback: 主题
	var type_info: Dictionary = GameTheme.card_type_info(type)
	return { "icon": type_info["icon"], "label": type_info["label"] }

## 获取事件效果 (trap 按子类型返回)
func get_effects() -> Dictionary:
	# 优先从 EventPool 获取
	if event_id != "":
		var effects: Dictionary = EventPool.get_event_effects(event_id)
		if not effects.is_empty():
			return effects
	# fallback: 旧逻辑
	if type == "trap" and trap_subtype != "":
		var sub_info: Dictionary = CardConfig.trap_subtype_info.get(trap_subtype, {})
		return sub_info.get("effect", {})
	return CardConfig.card_effects.get(type, {})

## 获取随机事件文本 (trap 按子类型返回)
func get_event_text() -> String:
	# 优先从 EventPool 获取
	if event_id != "":
		var text: String = EventPool.get_event_random_text(event_id)
		if text != "发生了什么...":
			return text
	# fallback: 旧逻辑
	if type == "trap" and trap_subtype != "":
		var texts: Array = CardConfig.trap_subtype_texts.get(trap_subtype, ["发生了一些事情..."])
		return texts[randi() % texts.size()]
	var texts: Array = CardConfig.event_texts.get(type, ["发生了一些事情..."])
	return texts[randi() % texts.size()]

## 获取陷阱子类型信息
func get_trap_subtype_info() -> Dictionary:
	# 优先从 EventPool 获取
	if trap_subtype != "":
		var sub: Dictionary = EventPool.get_trap_subtype(trap_subtype)
		if not sub.is_empty():
			return sub
	return CardConfig.trap_subtype_info.get(trap_subtype, { "icon": "⚡", "label": "陷阱", "effect": {} })

## 获取地点信息
func get_location_info() -> Dictionary:
	var loc_data: Dictionary = Locations.get_real_location(location)
	if not loc_data.is_empty():
		return {
			"icon": loc_data.get("icon", "❓"),
			"label": loc_data.get("label", "未知"),
			"image_path": loc_data.get("image_path", "")
		}
	return CardConfig.location_info.get(location, { "icon": "❓", "label": "未知" })

## 是否是地标
func is_landmark() -> bool:
	return location in LANDMARK_LOCATIONS

## 工厂方法 (现实世界卡牌)
static func create(loc: String, evt_type: String, r: int, c: int, evt_id: String = "") -> Card:
	var card: Card = Card.new()
	card.location = loc
	card.type = evt_type
	card.event_id = evt_id
	card.row = r
	card.col = c
	# 地标从发牌起就正面朝上 (匹配 Lua: faceUp = (cardType == "landmark"))
	if evt_type == "landmark":
		card.is_flipped = true
	return card

## 工厂方法 (暗面世界卡牌)
static func create_dark(dt: String, dn: String, r: int, c: int, evt_id: String = "") -> Card:
	var card: Card = Card.new()
	card.is_dark = true
	card.dark_type = dt
	card.dark_name = dn
	card.type = dt
	card.event_id = evt_id
	card.location = ""
	card.row = r
	card.col = c
	card.is_flipped = true  # 暗面卡牌全明牌
	return card

# ---------------------------------------------------------------------------
# 安全区光晕
# ---------------------------------------------------------------------------

## 是否应该拥有安全区光晕 (home / landmark)
func should_have_glow() -> bool:
	return type == "home" or type == "landmark"

## 光晕颜色 (home=白色, landmark=金色)
func get_glow_color() -> Color:
	if type == "landmark":
		return GameTheme.glow_color  # 金色
	return Color(1.0, 1.0, 1.0, 0.6)  # 白色

## 激活安全区光环
func show_safe_glow() -> void:
	safe_glow_active = true

## 关闭安全区光环
func hide_safe_glow() -> void:
	safe_glow_active = false
