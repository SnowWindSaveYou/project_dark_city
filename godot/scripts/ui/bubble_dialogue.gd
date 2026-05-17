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
	# 扩充
	"我只是个普通人，真的。",
	"不要回头，不要回头，不要——好，没事了。",
	"理智是有限的，我得省着用。",
	"上一次好好睡觉是什么时候……",
	"这个城市的夜晚太长了。",
	"肚子有点饿。这种时候也会饿，真是的。",
	"手机没有信号。当然，什么时候都没有。",
	"听说只要不承认就不算真实。试试看……不管用。",
	"我只要再坚持一会儿就好了。就一会儿。",
	"这种感觉……像是有人把这条街折叠过了。",
	"脑子里那个声音在说让我走。往哪走？",
	"周围安静得不对劲。太安静了。",
	"我只是……需要一点时间。",
	"闭上眼睛数到三。一、二……算了，数不下去。",
	"如果这是梦就好了。可惜脚底的感觉太真实了。",
]

# ---------------------------------------------------------------------------
# 区域/地点相关对话池
# ---------------------------------------------------------------------------
const LOCATION_LINES: Dictionary = {
	"home": [
		"至少家里还算安全……大概。",
		"门锁好了吗？再检查一遍。",
		"终于能歇一会儿了。",
		"冰箱里还有什么……这种时候也要吃饭的。",
		"窗帘拉上，灯开着，好一点了。",
		"这个地方……还认得出来。挺好的。",
		"床好久没睡了，但我不敢躺下去。",
	],
	"company": [
		"加班到这个时候，同事们都去哪了？",
		"电脑屏幕上的文字……好像在变。",
		"茶水间的灯又闪了。",
		"打卡机显示的时间不对，但不知道哪里不对。",
		"会议室里有人在说话，可是今天没有会议。",
		"工位上的台历……停在了某一天。",
		"保安室没有保安，但监控还在转。",
	],
	"school": [
		"放学后的走廊好安静。",
		"黑板上多了一行字，不是老师写的。",
		"储物柜里传来敲击声。",
		"教室里的椅子全对着同一个方向。",
		"操场上有人在跑圈，但我数不清有几个。",
		"花名册上有一页是空的，可我记得那里应该有名字。",
		"下课铃响了，但没有人出来。",
	],
	"park": [
		"公园的长椅上有个人……还是说那是个影子？",
		"秋千自己在晃。",
		"这棵树好像比昨天高了。",
		"喂鸽子的老人没有动，已经站在那里很久了。",
		"湖面太平静了，倒影比实体清晰。",
		"草地上有脚印，方向很乱，而且只有进没有出。",
		"路灯亮了，但天还没黑。",
	],
	"alley": [
		"这条巷子怎么走不到头？",
		"涂鸦在月光下好像会动。",
		"垃圾桶后面有响动。",
		"走了好久，出口还是那么远。",
		"墙缝里塞着一张纸条，我没有拿。",
		"猫在这里不叫，只是盯着同一个角落。",
		"这里的气味……不是腐烂，是更旧的东西。",
	],
	"station": [
		"末班车早就过了，可广播还在响。",
		"月台上只有我一个人。",
		"铁轨上传来嗡嗡声。",
		"时刻表上所有班次都显示'准时'。",
		"检票口的闸机开了，但没有票。",
		"有人坐在候车椅上睡着了，我走近又消失了。",
		"隧道那头……有光，但不知道是灯还是别的什么。",
	],
	"hospital": [
		"消毒水的味道让人清醒。",
		"走廊尽头的灯一直在闪。",
		"护士台空无一人。",
		"病房门缝里透出来的光是绿色的。",
		"电梯按了，但门打开时里面是另一层走廊。",
		"告示板上贴着一张通知，上面的日期是将来的某天。",
		"轮椅自己停在走廊中间，没有人坐。",
	],
	"library": [
		"书架后面好像有人在翻书。",
		"这本书的作者名字是我的？",
		"安静得能听见心跳。",
		"目录里有一本书，但找不到它的位置。",
		"还书台上放着一本没有书名的书，我没有借。",
		"某一格书架后面……有呼吸声。",
		"借阅记录上最后一个名字的日期是很多年前。",
	],
	"convenience": [
		"店员的笑容怎么一直没变？",
		"货架上的东西似乎和昨天不一样。",
		"收银台的时钟停了。",
		"微波炉里有东西在转，但没人放进去。",
		"店里背景音乐的歌词……听起来像是在说我。",
		"买了东西，但钱没有少，货也没有少。",
		"冷柜玻璃上有人用手指写了什么，但我看不清。",
	],
	"church": [
		"在这里心情能平静一些。",
		"烛光摇曳，影子在墙上跳舞。",
		"祈祷真的有用吗？",
		"蜡烛一直在燃烧，却没有变短。",
		"管风琴发出了一个音，没有人碰它。",
		"祈祷的话说到一半，忘了后半句。",
		"这里有一种感觉……像是被什么东西看见了。不是坏的那种。",
	],
	"police": [
		"巡逻车停在路边，但没人在里面。",
		"公告栏上贴着奇怪的寻人启事。",
		"这里应该是安全的。",
		"报案电话拨通了，那边有呼吸声，但没有人说话。",
		"失物招领箱里有太多东西了，满出来了。",
		"值班室的灯是亮的，敲门没有回应。",
	],
	"bank": [
		"号码牌显示前面还有九十九号。",
		"保险柜的门是开着的，里面是空的。",
		"数字在账单上自己跳动了一下……我一定是看错了。",
		"柜台里的职员低着头，已经很久没有动了。",
		"取款机吐出一张票，上面只有一行字：'不够'。",
		"这里的时间好像比外面慢一点。",
	],
	"cemetery": [
		"这里反而是整个城市里最安静的地方。",
		"碑文上有个名字，我认识这个人。",
		"花……是新鲜的，今天刚放上去的。可是没有人来过。",
		"走错路了。所有小路都绕回同一块碑前。",
		"地面很软，比该有的更软。",
		"我在这里感觉不到害怕，只是难过。",
	],
	"gym": [
		"器械自己在动，节奏很规律。",
		"镜子里有个人在做和我不一样的动作。",
		"跑步机上有脚印，但没有人在跑。",
		"这里的时钟走得特别快，我才进来一会儿就过了一个小时。",
		"储物柜里有人的东西，但没有人来取。",
		"运动完应该出汗的，但我没有。",
	],
}

# ---------------------------------------------------------------------------
# 白夜碎碎念 (约占总池 ~30%，加前缀区分说话人)
# ---------------------------------------------------------------------------
const BAIYE_LINES: Array[String] = [
	# --- 感知/观察 ---
	"你的右边第三块地砖是松的。小心点。",
	"下雨之前，这里会先有一股潮气。",
	"那个转角……以前有人在那里哭过。",
	"你走路的声音变了，比上周轻了。",
	"这棵树的树洞里有东西。不危险，只是很旧了。",
	"你今天比昨天快了三步。",
	"这里的路灯要亮起来了，我感觉到了。",
	"你走过去的时候，那个人往右看了一眼。",
	"有风。很快要变天了。",
	"这面墙……我好像看过和它一模一样的另一面。",
	"那个巷子里有暗面的痕迹，不新鲜了。可以进去。",
	"你的影子今天拉得很长。",
	"嗯，可以走了，刚才那个是假的。",
	"门牌号这里有个地方不对，你注意到了吗？",
	"那片云……不是自然形成的。",
	"地面温度比周围低了一点。这里有东西埋过。",
	"刚才经过的那扇窗，有人在看你，但已经走了。",
	"这里的空气有点稠……不是坏事，只是旧的积累。",
	# --- 关心/陪伴 ---
	"……你冷吗？",
	"嗯。这条路是安全的，我刚查过。",
	"你在想什么？",
	"以前……这一带比现在热闹。",
	"……不喜欢这个气味。和某个地方太像了。",
	"……在你出现之前，我已经一个人在这条街上走了很久了。",
	"你今天……看起来比昨天好一点。",
	"饿了吗？我说不清楚饿是什么感觉，但你应该吃点东西。",
	"不用担心我。我不累的。",
	"……我只是不想一个人待着。陪着你，挺好的。",
	"你要是走不动了可以说，我陪你停一会儿。",
	# --- 对世界的感受 ---
	"这种地方……我见过很多次了。每次都不一样，但又都一样。",
	"光线变了，时间走得不对。这里的钟可能不准。",
	"人类觉得安静就是没有声音。但这里的安静……是别的东西。",
	"这一带很久没有人住了。但有什么东西还在。",
	"……暗面不是从天上来的。是从下面渗上来的。",
	"有时候我站在这里，觉得我看到的和你看到的不一样。",
	"雾里有时候会有东西。大多数时候是假的，但不总是。",
	"……我也不知道这些为什么发生。只是发生了。",
	"城市里有些地方，感觉被人遗忘了。不只是人。",
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
		"那双眼睛……我不会忘的。",
		"刚才到底是什么？不是人。不完全是。",
		"现在全身都是汗，但我没有感觉到热。",
		"撑过来了。先别想，先走。",
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
		"暗面的规则……和真实世界不一样。踩错要付出代价。",
		"差点了。再粗心一次可能就真的出不去了。",
	],
	"safe": [
		"嗯，这里安全。暂时的。",
		"喘口气再继续。",
		"终于有一片还算正常的地方。",
		"深呼吸。好了。继续。",
		"不知道这个安全区能维持多久……先利用吧。",
	],
	"reward": [
		"运气不错，捡到好东西了。",
		"这些物资很有用。",
		"意外收获，接受了。",
		"这个地方居然还留着东西……感谢前任探索者。",
	],
	"shop": [
		"价格有点黑……但没得选。",
		"那个商人到底是什么来头？",
		"在这种地方还开着店……真奇怪的人。",
		"买完了，希望是真货。",
		"用物资换物资……这里的货币体系很特别。",
	],
	"plot": [
		"这座城市藏着太多秘密。",
		"有人在帮我？还是在算计我？",
		"越了解越觉得事情没那么简单。",
		"这一段……感觉像是专门为我安排的。",
		"背后一定有什么人在操控这一切。",
		"想起来了，这和之前那件事有关。",
	],
	"rift": [
		"空间在这里撕开了口子……很不安稳的感觉。",
		"裂缝里传来的声音……像是很远的地方的回响。",
		"越过去了，但我不想再靠近第二次。",
		"要是裂缝扩大了怎么办……不要想，走。",
		"暗面和现实之间的边界……比我想象的薄多了。",
	],
	"intel": [
		"这个情报……价值很高。不能随便告诉别人。",
		"所以事情是这样的……原来如此。",
		"拿到这个消息，总算有方向了。",
		"这条线索的背后……还有更深的东西。",
	],
	"photo": [
		"快门按下去的一瞬间，我看到了不该看到的东西。",
		"这张照片……冲洗出来之前先别看。",
		"按下快门，像是封存了什么。",
		"拍到了吗？希望有用。",
		"胶卷少了一张，记录下来了。",
	],
	"landmark": [
		"这里是地图上标记的地方……比我想象的大。",
		"以前这里一定很重要。现在只剩痕迹了。",
		"不知道多少人来过这里，又去了哪里。",
		"这个地点……有什么意义，还没想明白。",
	],
	"consumable": [
		"用掉了，希望有效。",
		"物资越来越少了，得省着用。",
		"总算找到了用处。",
		"在这种地方能喝到热的东西……算是奢侈了。",
	],
	"checkpoint": [
		"这里可以喘一口气了。",
		"到这里就安全了——今晚。",
		"做个标记，下次知道怎么走。",
		"撑过来了，又一段路。",
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

# 教程锁定模式 (show_tutorial 使用)
var locked: bool = false
var lock_duration: float = 0.0

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

	# 白夜有独立气泡，不再混入主角池

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

## 显示固定教程文本，锁定气泡直到时间到或玩家点击
func show_tutorial(tutorial_text: String, duration: float = 7.0) -> void:
	text = tutorial_text
	timer = 0.0
	lock_duration = duration
	locked = true
	cooldown_timer = 0.0
	state = "showing"
	bubble_alpha = 0.0
	bubble_scale = 0.3
	offset_y = 8.0
	# 弹入动画由 main.gd tween 驱动 → bubble_alpha=1, bubble_scale=1, offset_y=0

## 隐藏气泡
func hide() -> void:
	if state == "hidden" or state == "hiding":
		return
	if locked:
		return  # 锁定期间忽略普通 hide
	state = "hiding"
	# 淡出动画由 main.gd tween 驱动

## 强制立即隐藏（解除锁定）
func force_hide() -> void:
	locked = false
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
		var duration: float = lock_duration if locked else DISPLAY_DURATION
		if timer >= duration:
			_unlock_and_hide()

	# 锁定期间：跳过移动隐藏和静止触发
	if locked:
		return

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
	if locked and (state == "visible" or state == "showing"):
		# 锁定中点击 → 解锁并关闭
		_unlock_and_hide()
		return
	if state == "visible" or state == "showing":
		# 已在显示, 换一条
		hide()
		cooldown_timer = CLICK_COOLDOWN
		# 短延迟后弹出新的 — 由 main.gd 设 timer 调度
		return
	# 未显示 → 直接弹出
	cooldown_timer = 0.0
	show()

func _unlock_and_hide() -> void:
	locked = false
	if state != "hidden" and state != "hiding":
		state = "hiding"
		# 淡出动画由 main.gd tween 驱动

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

# ---------------------------------------------------------------------------
# 白夜专属工厂 & update
# ---------------------------------------------------------------------------

var _is_baiye: bool = false

## 创建白夜专用 BubbleDialogue 实例
static func create_for_baiye() -> BubbleDialogue:
	var bd: BubbleDialogue = BubbleDialogue.new()
	bd._is_baiye = true
	# 比 NPC 更低频，更像偶尔说话的同伴
	bd.idle_accum = randf_range(0.0, 8.0)
	bd._npc_trigger_interval = randf_range(12.0, 20.0)
	return bd

## 白夜专用台词选取
func _pick_baiye_line() -> String:
	if BAIYE_LINES.is_empty():
		return "……"
	return BAIYE_LINES[randi_range(0, BAIYE_LINES.size() - 1)]

## 白夜专用 update（仅在白夜可见时调用）
func update_baiye(dt: float) -> void:
	if cooldown_timer > 0:
		cooldown_timer -= dt

	if state == "visible":
		timer += dt
		if timer >= DISPLAY_DURATION:
			hide()

	idle_accum += dt
	if idle_accum >= _npc_trigger_interval and state == "hidden" and cooldown_timer <= 0:
		text = _pick_baiye_line()
		timer = 0.0
		state = "showing"
		bubble_alpha = 0.0
		bubble_scale = 0.3
		offset_y = 8.0
		idle_accum = 0.0
		_npc_trigger_interval = randf_range(12.0, 22.0)
