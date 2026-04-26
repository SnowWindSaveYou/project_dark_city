## Card - 卡牌数据定义与工厂
## 对应原版 Card.lua (数据部分)
class_name Card
extends RefCounted

# ---------------------------------------------------------------------------
# 常量: 卡牌物理尺寸 (3D 世界坐标, 单位: 米)
# ---------------------------------------------------------------------------
const CARD_W := 0.64
const CARD_H := 0.90
const CARD_THICKNESS := 0.015

# ---------------------------------------------------------------------------
# 地点信息
# ---------------------------------------------------------------------------
const LOCATION_INFO := {
	# 普通地点 (8)
	"company":    { "icon": "🏢", "label": "公司" },
	"park":       { "icon": "🌳", "label": "公园" },
	"hospital":   { "icon": "🏥", "label": "医院" },
	"school":     { "icon": "🏫", "label": "学校" },
	"station":    { "icon": "🚉", "label": "车站" },
	"market":     { "icon": "🏪", "label": "商场" },
	"shrine":     { "icon": "⛩️", "label": "神社" },
	"alley":      { "icon": "🌃", "label": "小巷" },
	# 地标地点 (3) — 有光环效果
	"lighthouse": { "icon": "🗼", "label": "灯塔" },
	"library":    { "icon": "📚", "label": "图书馆" },
	"temple":     { "icon": "⛪", "label": "教堂" },
	# 特殊地点 (2)
	"home":       { "icon": "🏠", "label": "家" },
	"shop":       { "icon": "🛒", "label": "商店" },
}

const REGULAR_LOCATIONS := ["company", "park", "hospital", "school", "station", "market", "shrine", "alley"]
const LANDMARK_LOCATIONS := ["lighthouse", "library", "temple"]

# ---------------------------------------------------------------------------
# 事件权重 (用于随机生成)
# ---------------------------------------------------------------------------
const EVENT_WEIGHTS := {
	"safe": 30,
	"monster": 20,
	"trap": 15,
	"reward": 15,
	"plot": 10,
	"clue": 10,
}

# ---------------------------------------------------------------------------
# 暗面信息表 (地点 × 事件类型 → 独特图标和名称)
# ---------------------------------------------------------------------------
const DARKSIDE_INFO := {
	"company": {
		"monster": { "icon": "👔", "label": "影子上司" },
		"trap":    { "icon": "📄", "label": "无尽加班" },
		"reward":  { "icon": "💼", "label": "隐藏奖金" },
		"plot":    { "icon": "🕳️", "label": "裁员阴谋" },
		"clue":    { "icon": "📊", "label": "异常数据" },
	},
	"park": {
		"monster": { "icon": "🌑", "label": "暗影行者" },
		"trap":    { "icon": "🕸️", "label": "迷雾陷阱" },
		"reward":  { "icon": "🍀", "label": "幸运草" },
		"plot":    { "icon": "🗿", "label": "移动雕像" },
		"clue":    { "icon": "🐾", "label": "神秘足迹" },
	},
	"hospital": {
		"monster": { "icon": "💀", "label": "游荡护士" },
		"trap":    { "icon": "💉", "label": "错误处方" },
		"reward":  { "icon": "💊", "label": "急救药箱" },
		"plot":    { "icon": "🧪", "label": "禁忌实验" },
		"clue":    { "icon": "📋", "label": "失踪病历" },
	},
	"school": {
		"monster": { "icon": "👧", "label": "走廊幽影" },
		"trap":    { "icon": "📐", "label": "诅咒教室" },
		"reward":  { "icon": "📓", "label": "旧日记" },
		"plot":    { "icon": "🎹", "label": "自鸣钢琴" },
		"clue":    { "icon": "✏️", "label": "黑板留言" },
	},
	"station": {
		"monster": { "icon": "🚇", "label": "末班幽灵" },
		"trap":    { "icon": "⏰", "label": "时间回溯" },
		"reward":  { "icon": "🎫", "label": "黄金车票" },
		"plot":    { "icon": "🚂", "label": "幽灵列车" },
		"clue":    { "icon": "📡", "label": "异常信号" },
	},
	"market": {
		"monster": { "icon": "🎭", "label": "镜中人影" },
		"trap":    { "icon": "🪤", "label": "自动扶梯" },
		"reward":  { "icon": "🎁", "label": "神秘礼包" },
		"plot":    { "icon": "🖼️", "label": "活动海报" },
		"clue":    { "icon": "🔔", "label": "广播暗号" },
	},
	"shrine": {
		"monster": { "icon": "👹", "label": "封印之物" },
		"trap":    { "icon": "🎐", "label": "风铃诅咒" },
		"reward":  { "icon": "🧧", "label": "许愿成真" },
		"plot":    { "icon": "⛩️", "label": "结界裂缝" },
		"clue":    { "icon": "📿", "label": "遗落御守" },
	},
	"alley": {
		"monster": { "icon": "🐈‍⬛", "label": "黑猫魅影" },
		"trap":    { "icon": "🌧️", "label": "酸雨积水" },
		"reward":  { "icon": "🗝️", "label": "旧箱钥匙" },
		"plot":    { "icon": "🚪", "label": "消失之门" },
		"clue":    { "icon": "👣", "label": "回声脚步" },
	},
}

# ---------------------------------------------------------------------------
# 卡牌事件效果
# ---------------------------------------------------------------------------
const CARD_EFFECTS := {
	"safe":     {},
	"monster":  { "san": -2, "order": -1 },
	"trap":     { "san": -1, "order": -1 },
	"reward":   { "money": 15, "film": 1 },
	"plot":     { "san": -1 },
	"clue":     { "order": 1 },
	"photo":    { "money": 5 },
	"landmark": { "san": 1, "order": 1 },
	"home":     { "san": 1 },
	"shop":     {},
}

# ---------------------------------------------------------------------------
# 事件文本模板 (每种 3 个变体)
# ---------------------------------------------------------------------------
const EVENT_TEXTS := {
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
}

# ---------------------------------------------------------------------------
# 实例属性
# ---------------------------------------------------------------------------
var location: String = ""        # 地点 key
var type: String = ""            # 事件类型 key
var row: int = 0                 # 棋盘行 (1-based)
var col: int = 0                 # 棋盘列 (1-based)
var is_flipped: bool = false     # 是否已翻开
var is_dealt: bool = false       # 是否已发到棋盘
var scouted: bool = false        # 是否被相机侦察过 (翻看后翻回)
var is_flipping: bool = false    # 是否正在翻转动画中

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
	var type_info: Dictionary = Theme.card_type_info(type)
	return { "icon": type_info["icon"], "label": type_info["label"] }

## 获取事件效果
func get_effects() -> Dictionary:
	return CARD_EFFECTS.get(type, {})

## 获取随机事件文本
func get_event_text() -> String:
	var texts: Array = EVENT_TEXTS.get(type, ["发生了一些事情..."])
	return texts[randi() % texts.size()]

## 获取地点信息
func get_location_info() -> Dictionary:
	return LOCATION_INFO.get(location, { "icon": "❓", "label": "未知" })

## 是否是地标
func is_landmark() -> bool:
	return location in LANDMARK_LOCATIONS

## 工厂方法
static func create(loc: String, evt_type: String, r: int, c: int) -> Card:
	var card := Card.new()
	card.location = loc
	card.type = evt_type
	card.row = r
	card.col = c
	return card
