## BubbleDialogue - 气泡对话系统
## 对应原版 BubbleDialogue.lua
## 角色头顶白色气泡框 (带三角箭头)，_draw() 绘制
## 触发: 静止一段时间 / 点击角色
class_name BubbleDialogue
extends RefCounted

# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------
const IDLE_TRIGGER_TIME := 4.0   # 静止多久后自动弹出 (秒)
const DISPLAY_DURATION  := 3.5   # 气泡显示时长 (秒)
const COOLDOWN          := 5.0   # 自动触发冷却 (秒)
const CLICK_COOLDOWN    := 1.5   # 点击触发冷却

const BUBBLE_MAX_W     := 180.0  # 气泡最大宽度 (像素)
const BUBBLE_PAD_H     := 10.0   # 水平内边距
const BUBBLE_PAD_V     := 8.0    # 垂直内边距
const BUBBLE_RADIUS    := 8.0    # 圆角半径
const BUBBLE_ARROW_W   := 10.0   # 箭头宽度
const BUBBLE_ARROW_H   := 8.0    # 箭头高度
const BUBBLE_OFFSET_Y  := 12.0   # 气泡底部到角色头顶的间距
const FONT_SIZE        := 13     # 字体大小

# ---------------------------------------------------------------------------
# 通用对话池
# ---------------------------------------------------------------------------
const COMMON_LINES: Array[String] = [
	"这座城市……总感觉哪里不对劲。",
	"还好手机没电了，不然肯定会看到更可怕的东西。",
	"脚步声……是我自己的吧？",
	"深呼吸……再深呼吸……",
	"口袋里的零钱越来越少了。",
	"要是有杯热咖啡就好了……",
	"……我为什么在这里来着？",
	"总觉得有人在看我。",
	"记忆好像有些模糊了。",
	"别慌，这一切都有解释的。一定有。",
	"唔……好困。但是不能睡着。",
	"这条路我走过吗？都长一个样。",
	"明天一定会好起来的……吧？",
	"嗯？那边的影子动了一下？",
	"还有胶卷吗……得省着点用。",
	"风好冷。",
	"如果能回到正常的日子就好了。",
]

# ---------------------------------------------------------------------------
# 区域/地点相关对话池
# ---------------------------------------------------------------------------
const LOCATION_LINES := {
	"home": [
		"至少家里还算安全……大概。",
		"门锁好了吗？再检查一遍。",
		"终于能歇一会儿了。",
	],
	"company": [
		"加班到这个时候，同事们都去哪了？",
		"电脑屏幕上的文字……好像在变。",
		"茶水间的灯又闪了。",
	],
	"school": [
		"放学后的走廊好安静。",
		"黑板上多了一行字，不是老师写的。",
		"储物柜里传来敲击声。",
	],
	"park": [
		"公园的长椅上有个人……还是说那是个影子？",
		"秋千自己在晃。",
		"这棵树好像比昨天高了。",
	],
	"alley": [
		"这条巷子怎么走不到头？",
		"涂鸦在月光下好像会动。",
		"垃圾桶后面有响动。",
	],
	"station": [
		"末班车早就过了，可广播还在响。",
		"月台上只有我一个人。",
		"铁轨上传来嗡嗡声。",
	],
	"hospital": [
		"消毒水的味道让人清醒。",
		"走廊尽头的灯一直在闪。",
		"护士台空无一人。",
	],
	"library": [
		"书架后面好像有人在翻书。",
		"这本书的作者名字是我的？",
		"安静得能听见心跳。",
	],
	"convenience": [
		"店员的笑容怎么一直没变？",
		"货架上的东西似乎和昨天不一样。",
		"收银台的时钟停了。",
	],
	"church": [
		"在这里心情能平静一些。",
		"烛光摇曳，影子在墙上跳舞。",
		"祈祷真的有用吗？",
	],
	"police": [
		"巡逻车停在路边，但没人在里面。",
		"公告栏上贴着奇怪的寻人启事。",
		"这里应该是安全的。",
	],
	"shrine": [
		"鸟居下面的风好像暖一些。",
		"绘马上写着看不懂的文字。",
		"铃铛的声音在耳边回荡。",
	],
}

# ---------------------------------------------------------------------------
# 事件类型相关对话
# ---------------------------------------------------------------------------
const EVENT_LINES := {
	"monster": [
		"刚才那个东西……不要再想了。",
		"心跳还没平复下来。",
		"理智值掉了不少……得小心。",
		"下次得绕着走。",
	],
	"trap": [
		"这里的地面不太稳。",
		"还好没受重伤。",
		"得注意脚下。",
		"脑袋嗡嗡的……刚才是什么？",
		"钱包又轻了……这座城市在偷走一切。",
		"胶卷报废了一卷……好心疼。",
		"刚才那阵眩晕……我到底被传到了哪里？",
		"空间好像扭曲了一瞬间。",
		"周围的景色突然变了……太诡异了。",
		"理智值好像在慢慢流失。",
		"口袋里的硬币莫名其妙少了几枚。",
	],
	"safe": [
		"嗯，这里安全。暂时的。",
		"喘口气再继续。",
	],
	"clue": [
		"这条线索……似乎很重要。",
		"传闻背后的真相是什么？",
		"越来越接近答案了。",
	],
	"reward": [
		"运气不错，捡到好东西了。",
		"这些物资很有用。",
	],
	"shop": [
		"价格有点黑……但没得选。",
		"那个商人到底是什么来头？",
	],
	"plot": [
		"这座城市藏着太多秘密。",
		"有人在帮我？还是在算计我？",
	],
}

# ---------------------------------------------------------------------------
# 气泡实例
# ---------------------------------------------------------------------------

var text: String = ""
var bubble_alpha: float = 0.0
var bubble_scale: float = 0.0
var offset_y: float = 5.0    # 弹出时向上偏移
var timer: float = 0.0
var state: String = "hidden"  # "hidden"|"showing"|"visible"|"hiding"
var idle_accum: float = 0.0
var cooldown_timer: float = 0.0
var last_event_type: String = ""
var last_location: String = ""

# ---------------------------------------------------------------------------
# 对话选取
# ---------------------------------------------------------------------------

func _pick_line() -> String:
	var candidates: Array[String] = []

	# 通用对话
	candidates.append_array(COMMON_LINES)

	# 当前地点对话 (权重 2)
	if last_location != "" and LOCATION_LINES.has(last_location):
		var loc_lines: Array = LOCATION_LINES[last_location]
		for line in loc_lines:
			candidates.append(line)
			candidates.append(line)

	# 最近事件对话 (权重 2)
	if last_event_type != "" and EVENT_LINES.has(last_event_type):
		var evt_lines: Array = EVENT_LINES[last_event_type]
		for line in evt_lines:
			candidates.append(line)
			candidates.append(line)

	if candidates.is_empty():
		return "……"
	return candidates[randi_range(0, candidates.size() - 1)]

# ---------------------------------------------------------------------------
# 触发 / 关闭
# ---------------------------------------------------------------------------

## 显示气泡
func show(location: String = "", event_type: String = "") -> void:
	if state == "showing" or state == "visible":
		return
	if cooldown_timer > 0:
		return

	if location != "":
		last_location = location
	if event_type != "":
		last_event_type = event_type

	text = _pick_line()
	timer = 0.0
	state = "showing"
	bubble_alpha = 0.0
	bubble_scale = 0.3
	offset_y = 8.0
	# 弹入动画由 main.gd tween 驱动 → bubble_alpha=1, bubble_scale=1, offset_y=0

## 隐藏气泡
func hide() -> void:
	if state == "hidden" or state == "hiding":
		return
	state = "hiding"
	# 淡出动画由 main.gd tween 驱动

## 强制立即隐藏
func force_hide() -> void:
	state = "hidden"
	bubble_alpha = 0.0
	bubble_scale = 0.0
	timer = 0.0
	idle_accum = 0.0

## 更新上下文 (翻牌后调用)
func set_context(location: String, event_type: String) -> void:
	if location != "":
		last_location = location
	if event_type != "":
		last_event_type = event_type

# ---------------------------------------------------------------------------
# 每帧更新
# ---------------------------------------------------------------------------

func update(dt: float, is_idle: bool, can_trigger: bool) -> void:
	# 冷却
	if cooldown_timer > 0:
		cooldown_timer -= dt

	# 显示计时 → 自动隐藏
	if state == "visible":
		timer += dt
		if timer >= DISPLAY_DURATION:
			hide()

	# 静止触发
	if is_idle and can_trigger:
		idle_accum += dt
		if idle_accum >= IDLE_TRIGGER_TIME and state == "hidden":
			show()
			idle_accum = 0.0
	else:
		idle_accum = 0.0

	# 角色移动时立即关闭
	if not is_idle and state != "hidden":
		hide()

## 点击触发
func click_trigger() -> void:
	if state == "visible" or state == "showing":
		# 已在显示, 换一条
		hide()
		cooldown_timer = CLICK_COOLDOWN
		# 短延迟后弹出新的 — 由 main.gd 设 timer 调度
		return
	# 未显示 → 直接弹出
	cooldown_timer = 0.0
	show()

## 完成显示动画后调用
func on_show_complete() -> void:
	state = "visible"

## 完成隐藏动画后调用
func on_hide_complete() -> void:
	state = "hidden"
	cooldown_timer = COOLDOWN
