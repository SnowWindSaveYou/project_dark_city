## Card - 卡牌数据定义与工厂
## 对应原版 Card.lua (数据部分)
class_name Card
extends RefCounted

# ---------------------------------------------------------------------------
# 常量: 卡牌物理尺寸 (3D 世界坐标, 单位: 米)
# ---------------------------------------------------------------------------
const CARD_W: float = 0.64
const CARD_H: float = 0.90
const CARD_THICKNESS: float = 0.015

# ---------------------------------------------------------------------------
# 地点信息 (与 Card.lua LOCATION_INFO 同步)
# ---------------------------------------------------------------------------
const LOCATION_INFO: Dictionary = {
	# 特殊地点
	"home":        { "icon": "🏠", "label": "家" },
	# 商店地点
	"convenience": { "icon": "🏪", "label": "便利店" },
	# 地标地点 (有祛邪光环)
	"church":      { "icon": "⛪", "label": "教堂" },
	"police":      { "icon": "🚔", "label": "警察局" },
	"shrine":      { "icon": "⛩️", "label": "神社" },
	# 普通地点
	"company":     { "icon": "🏢", "label": "公司" },
	"school":      { "icon": "🏫", "label": "学校" },
	"park":        { "icon": "🌳", "label": "公园" },
	"alley":       { "icon": "🌙", "label": "小巷" },
	"station":     { "icon": "🚉", "label": "车站" },
	"hospital":    { "icon": "🏥", "label": "医院" },
	"library":     { "icon": "📚", "label": "图书馆" },
	"bank":        { "icon": "🏦", "label": "银行" },
}

const REGULAR_LOCATIONS: Array = [
	"company", "school", "park", "alley",
	"station", "hospital", "library", "bank",
]

const LANDMARK_LOCATIONS: Array = ["church", "police", "shrine"]

# ---------------------------------------------------------------------------
# 事件权重 (用于随机生成)
# ---------------------------------------------------------------------------
const EVENT_WEIGHTS: Dictionary = {
	"safe": 30,
	"monster": 20,
	"trap": 15,
	"reward": 15,
	"plot": 10,
	"clue": 10,
}

# ---------------------------------------------------------------------------
# 陷阱子类型信息
# ---------------------------------------------------------------------------
const TRAP_SUBTYPE_INFO: Dictionary = {
	"sanity":   { "icon": "😱", "label": "阴气侵蚀", "effect": { "san": -1 } },
	"money":    { "icon": "💸", "label": "财物散失", "effect": { "money": -10 } },
	"film":     { "icon": "📷", "label": "灵雾曝光", "effect": { "film": -1 } },
	"teleport": { "icon": "🌀", "label": "空间错位", "effect": {} },
}

# ---------------------------------------------------------------------------
# 暗面信息表 (地点 × 事件类型 → 独特图标和名称)
# ---------------------------------------------------------------------------
const DARKSIDE_INFO: Dictionary = {
	"company": {
		"safe":    { "icon": "🏢", "label": "空荡办公室" },
		"monster": { "icon": "🕴️", "label": "影子上司" },
		"trap":    { "icon": "📋", "label": "无尽加班令" },
		"reward":  { "icon": "💼", "label": "遗落的公文包" },
		"plot":    { "icon": "🖥️", "label": "异常邮件" },
		"clue":    { "icon": "📂", "label": "机密档案" },
	},
	"school": {
		"safe":    { "icon": "🏫", "label": "安静教室" },
		"monster": { "icon": "👤", "label": "无面教师" },
		"trap":    { "icon": "🔔", "label": "永不下课" },
		"reward":  { "icon": "📒", "label": "旧笔记本" },
		"plot":    { "icon": "🎒", "label": "无主书包" },
		"clue":    { "icon": "📝", "label": "黑板留言" },
	},
	"park": {
		"safe":    { "icon": "🌳", "label": "寂静长椅" },
		"monster": { "icon": "🌑", "label": "树影低语" },
		"trap":    { "icon": "🕸️", "label": "缠绕藤蔓" },
		"reward":  { "icon": "🍃", "label": "净化之风" },
		"plot":    { "icon": "🗿", "label": "奇怪雕像" },
		"clue":    { "icon": "🪶", "label": "地上羽毛" },
	},
	"alley": {
		"safe":    { "icon": "🌙", "label": "寂静小巷" },
		"monster": { "icon": "👁️", "label": "墙缝窥视" },
		"trap":    { "icon": "🕳️", "label": "地面塌陷" },
		"reward":  { "icon": "📦", "label": "角落包裹" },
		"plot":    { "icon": "🚪", "label": "不存在的门" },
		"clue":    { "icon": "✍️", "label": "涂鸦暗号" },
	},
	"station": {
		"safe":    { "icon": "🚉", "label": "末班列车" },
		"monster": { "icon": "🚇", "label": "不停靠的车" },
		"trap":    { "icon": "🌀", "label": "循环站台" },
		"reward":  { "icon": "🎫", "label": "神秘车票" },
		"plot":    { "icon": "📻", "label": "广播异响" },
		"clue":    { "icon": "🗺️", "label": "失落线路图" },
	},
	"hospital": {
		"safe":    { "icon": "🏥", "label": "空病房" },
		"monster": { "icon": "💉", "label": "游走护士" },
		"trap":    { "icon": "🩺", "label": "错误诊断" },
		"reward":  { "icon": "💊", "label": "遗留药品" },
		"plot":    { "icon": "📋", "label": "诡异病历" },
		"clue":    { "icon": "🔬", "label": "实验记录" },
	},
	"library": {
		"safe":    { "icon": "📚", "label": "安静角落" },
		"monster": { "icon": "📖", "label": "自翻的书" },
		"trap":    { "icon": "🔇", "label": "沉默诅咒" },
		"reward":  { "icon": "📜", "label": "古老卷轴" },
		"plot":    { "icon": "📕", "label": "禁书" },
		"clue":    { "icon": "🔖", "label": "夹页纸条" },
	},
	"bank": {
		"safe":    { "icon": "🏦", "label": "空金库" },
		"monster": { "icon": "🎭", "label": "面具柜员" },
		"trap":    { "icon": "🔒", "label": "锁死的门" },
		"reward":  { "icon": "💰", "label": "无主存款" },
		"plot":    { "icon": "🏧", "label": "异常终端" },
		"clue":    { "icon": "🧾", "label": "可疑账单" },
	},
}

# ---------------------------------------------------------------------------
# 卡牌事件效果 (注: trap 效果由 trap_subtype 决定)
# ---------------------------------------------------------------------------
const CARD_EFFECTS: Dictionary = {
	"safe":     {},
	"monster":  { "san": -2, "order": -1 },
	"trap":     {},  # 由 trap_subtype 决定
	"reward":   { "money": 15, "film": 1 },
	"plot":     { "san": -1 },
	"clue":     { "order": 1 },
	"photo":    { "money": 5 },
	"landmark": { "san": 1, "order": 1 },
	"home":     { "san": 1 },
	"shop":     {},
	"rift":     {},
}

# ---------------------------------------------------------------------------
# 事件文本模板
# ---------------------------------------------------------------------------
const EVENT_TEXTS: Dictionary = {
	"safe": [
		"周围一片宁静，什么也没有发生。",
		"微风拂过，带来一丝安心的感觉。",
		"这里很安全，可以稍作休息。",
	],
	"monster": [
		"阴影从角落窜出，一股寒意直冲脑门...",
		"黑暗中传来沉重的呼吸声，越来越近...",
		"地板上浮现诡异的符文，空气凝固了...",
	],
	"trap": [
		"脚下突然传来咔嚓声，是陷阱！",
		"一股无形的力量困住了你的脚步...",
		"周围的墙壁开始缓缓合拢...",
	],
	"reward": [
		"角落里发现了一个被遗忘的保险箱！",
		"在废墟中找到了一袋未开封的补给品。",
		"一道神秘的光芒指引你找到了宝物。",
	],
	"plot": [
		"你发现了一段被掩盖的真相...",
		"墙上的涂鸦似乎在诉说着什么...",
		"一张泛黄的照片掉落在你面前...",
	],
	"clue": [
		"地上有一串奇怪的脚印，值得追踪。",
		"角落里有人留下了一条隐秘的信息。",
		"你注意到了一个不寻常的细节...",
	],
	"photo": [
		"快门声响起，画面被永远定格。",
		"镜头捕捉到了肉眼看不见的东西...",
		"照片慢慢显影，真相浮出水面。",
	],
	"rift": [
		"空间仿佛被撕裂开一道口子...",
		"脚下的阴影开始漩涡般旋转...",
		"一股来自深处的力量在召唤你...",
	],
}

# ---------------------------------------------------------------------------
# 陷阱子类型文本模板 (每种 3 个变体)
# ---------------------------------------------------------------------------
const TRAP_SUBTYPE_TEXTS: Dictionary = {
	"sanity": [
		"阴气侵蚀，寒意刺骨...",
		"一阵恶寒掠过全身，精神恍惚...",
		"黑暗低语萦绕耳边，心智动摇...",
	],
	"money": [
		"口袋里的东西莫名消失了...",
		"财物不翼而飞，像是被什么拿走了...",
		"一阵诡异的风过后，钱包空了...",
	],
	"film": [
		"相机镜头突然起雾，胶卷曝光了！",
		"灵雾渗入相机，一卷胶卷报废了...",
		"闪光灯自行触发，浪费了珍贵的胶卷...",
	],
	"teleport": [
		"脚下空间扭曲，瞬间转移到了别处！",
		"眼前一花，人已经不在原地了...",
		"一股力量将你拽向了未知的方向...",
	],
}

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
var is_flipping: bool = false     # 是否正在翻转动画中

# --- 暗面世界字段 ---
var is_dark: bool = false         # 是否是暗面卡牌
var dark_type: String = ""        # 暗面卡牌类型 (normal/shop/passage/abyss_core/...)
var dark_name: String = ""        # 暗面卡牌显示名

# --- 陷阱/裂隙 ---
var trap_subtype: String = ""     # 陷阱子类型 (sanity/money/film/teleport)
var has_rift: bool = false        # 是否伪装了裂隙入口

# --- 光晕 ---
var safe_glow_active: bool = false  # 安全区光环是否激活
var glow_intensity: float = 0.0     # 翻牌闪光强度 0-1 (渲染层使用)

# ---------------------------------------------------------------------------
# 方法
# ---------------------------------------------------------------------------

## 获取暗面信息 (显示用图标和标签)
func get_darkside_info() -> Dictionary:
	if type in ["landmark", "home", "shop"]:
		var loc_info: Dictionary = LOCATION_INFO.get(location, { "icon": "❓", "label": "未知" })
		return { "icon": loc_info["icon"], "label": loc_info["label"] }
	if location in DARKSIDE_INFO and type in DARKSIDE_INFO[location]:
		return DARKSIDE_INFO[location][type]
	# fallback
	var type_info: Dictionary = GameTheme.card_type_info(type)
	return { "icon": type_info["icon"], "label": type_info["label"] }

## 获取事件效果 (trap 按子类型返回)
func get_effects() -> Dictionary:
	if type == "trap" and trap_subtype != "":
		var sub_info: Dictionary = TRAP_SUBTYPE_INFO.get(trap_subtype, {})
		return sub_info.get("effect", {})
	return CARD_EFFECTS.get(type, {})

## 获取随机事件文本 (trap 按子类型返回)
func get_event_text() -> String:
	if type == "trap" and trap_subtype != "":
		var texts: Array = TRAP_SUBTYPE_TEXTS.get(trap_subtype, ["发生了一些事情..."])
		return texts[randi() % texts.size()]
	var texts: Array = EVENT_TEXTS.get(type, ["发生了一些事情..."])
	return texts[randi() % texts.size()]

## 获取陷阱子类型信息
func get_trap_subtype_info() -> Dictionary:
	return TRAP_SUBTYPE_INFO.get(trap_subtype, { "icon": "⚡", "label": "陷阱", "effect": {} })

## 获取地点信息
func get_location_info() -> Dictionary:
	return LOCATION_INFO.get(location, { "icon": "❓", "label": "未知" })

## 是否是地标
func is_landmark() -> bool:
	return location in LANDMARK_LOCATIONS

## 工厂方法 (现实世界卡牌)
static func create(loc: String, evt_type: String, r: int, c: int) -> Card:
	var card: Card = Card.new()
	card.location = loc
	card.type = evt_type
	card.row = r
	card.col = c
	return card

## 工厂方法 (暗面世界卡牌)
static func create_dark(dt: String, dn: String, r: int, c: int) -> Card:
	var card: Card = Card.new()
	card.is_dark = true
	card.dark_type = dt
	card.dark_name = dn
	card.type = dt
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
