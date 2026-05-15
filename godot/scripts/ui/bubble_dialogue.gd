## BubbleDialogue - 气泡对话系统
## 对应原版 BubbleDialogue.lua
## 角色头顶白色气泡框 (带三角箭头)，_draw() 绘制
## 触发: 静止一段时间 / 点击角色
class_name BubbleDialogue
extends RefCounted

# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------
const IDLE_TRIGGER_TIME: float = 4.0  # 静止多久后自动弹出 (秒)
const DISPLAY_DURATION: float = 3.5  # 气泡显示时长 (秒)
const COOLDOWN: float = 5.0  # 自动触发冷却 (秒)
const CLICK_COOLDOWN: float = 1.5  # 点击触发冷却

const BUBBLE_MAX_W: float = 180.0  # 气泡最大宽度 (像素)
const BUBBLE_PAD_H: float = 10.0  # 水平内边距
const BUBBLE_PAD_V: float = 8.0  # 垂直内边距
const BUBBLE_RADIUS: float = 8.0  # 圆角半径
const BUBBLE_ARROW_W: float = 10.0  # 箭头宽度
const BUBBLE_ARROW_H: float = 8.0  # 箭头高度
const BUBBLE_OFFSET_Y: float = 12.0  # 气泡底部到角色头顶的间距
const FONT_SIZE: int = 13  # 字体大小

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
const LOCATION_LINES: Dictionary = {
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
}

# ---------------------------------------------------------------------------
# 白夜碎碎念 (约占总池 ~30%，加前缀区分说话人)
# ---------------------------------------------------------------------------
const BAIYE_LINES: Array[String] = [
	"你的右边第三块地砖是松的。小心点。",
	"下雨之前，这里会先有一股潮气。",
	"那个转角……以前有人在那里哭过。",
	"你走路的声音变了，比上周轻了。",
	"这棵树的树洞里有东西。不危险，只是很旧了。",
	"……你冷吗？",
	"嗯。这条路是安全的，我刚查过。",
	"你在想什么？",
	"门牌号这里有个地方不对，你注意到了吗？",
	"以前……这一带比现在热闹。",
	"你今天比昨天快了三步。",
	"这里的路灯要亮起来了，我感觉到了。",
	"……不喜欢这个气味。和某个地方太像了。",
	"你走过去的时候，那个人往右看了一眼。",
	"有风。很快要变天了。",
	"这面墙……我好像看过和它一模一样的另一面。",
	"那个巷子里有暗面的痕迹，不新鲜了。可以进去。",
	"你的影子今天拉得很长。",
	"……在你出现之前，我已经一个人在这条街上走了很久了。",
	"嗯，可以走了，刚才那个是假的。",
]

# ---------------------------------------------------------------------------
# 事件类型相关对话
# ---------------------------------------------------------------------------
const EVENT_LINES: Dictionary = {
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

	# 通用对话 (苏柚内心独白, 权重 1)
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

	# 白夜碎碎念 (权重 1, 加前缀区分说话人, 约占总池 ~30%)
	for line in BAIYE_LINES:
		candidates.append("白夜：" + line)

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

# ---------------------------------------------------------------------------
# NPC 专属台词池 & 工厂
# ---------------------------------------------------------------------------

## NPC 台词: npc_id → Array[String]
const NPC_LINES: Dictionary = {
	"hospital_npc": [
		"这里的走廊灯坏了好久了……",
		"最近来的病人越来越奇怪。",
		"……你最近睡得还好吗？",
		"消毒水用完了，这周也没人补货。",
		"有人总是在三楼走廊徘徊……应该只是探视者吧。",
		"今天又少了一张病历……说不清楚去哪了。",
	],
	"park_npc": [
		"这棵树我从小看到大了。",
		"最近公园里的鸟少了许多……",
		"年轻人，走慢一点也好。",
		"这雾……以前没有这么厚的。",
		"秋千那边，昨晚有小孩在笑……不知道是谁家的。",
		"老骨头了，动一动才暖和。",
	],
	"gym_npc": [
		"动起来，脑子才会清醒。",
		"最近来练的人越来越少了。",
		"身体是本钱，别等垮了才后悔。",
		"……那个深夜的哨声，你听到了吗？",
		"器械昨晚自己响了，我以为有人进来了。",
		"今天的训练量还差得远，继续。",
	],
	"qinxin": [
		"……你也感觉到了吗？",
		"这台相机有时候会自己发热。",
		"不要盯着那些影子看太久。",
		"闪光灯的电池……还剩多少？",
	],
	"fangdong": [
		"最近街上的人少了……大家都躲着出门。",
		"房租的事不着急，你先顾好自己。",
		"门锁好了吗？记得锁好。",
		"有什么动静直接来敲我的门。",
	],
	"cat": [
		"喵～",
		"……喵。",
		"（尾巴轻轻摇了一下。）",
		"（橘猫眯着眼睛打了个哈欠。）",
	],
}

## 创建一个 NPC 专用的 BubbleDialogue 实例
## npc_id: NPC 的 id 字符串
static func create_for_npc(npc_id: String) -> BubbleDialogue:
	var bd: BubbleDialogue = BubbleDialogue.new()
	bd._npc_id = npc_id
	bd._is_npc = true
	# 随机初始偏移，避免所有 NPC 同时弹出
	bd.idle_accum = randf_range(0.0, 5.5)
	# 每个 NPC 独立的触发间隔 (8~14s)，让节奏各不相同
	bd._npc_trigger_interval = randf_range(8.0, 14.0)
	return bd

# NPC 实例标记
var _npc_id: String = ""
var _is_npc: bool = false
var _npc_trigger_interval: float = 10.0  # 每实例独立触发间隔

## NPC 台词选取 (覆盖默认的 _pick_line)
func _pick_npc_line() -> String:
	var lines: Array = NPC_LINES.get(_npc_id, [])
	if lines.is_empty():
		return "……"
	return lines[randi_range(0, lines.size() - 1)]

## NPC 专用 update (无地点/事件上下文，静止即触发)
func update_npc(dt: float) -> void:
	if cooldown_timer > 0:
		cooldown_timer -= dt

	if state == "visible":
		timer += dt
		if timer >= DISPLAY_DURATION:
			hide()

	# 使用每实例独立的触发间隔
	idle_accum += dt
	if idle_accum >= _npc_trigger_interval and state == "hidden" and cooldown_timer <= 0:
		text = _pick_npc_line()
		timer = 0.0
		state = "showing"
		bubble_alpha = 0.0
		bubble_scale = 0.3
		offset_y = 8.0
		idle_accum = 0.0
		# 显示后重随机下一次间隔，保持节奏不规律
		_npc_trigger_interval = randf_range(8.0, 16.0)
