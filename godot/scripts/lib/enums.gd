## Enums - 统一枚举定义
## 所有游戏相关的枚举、状态常量集中管理
class_name Enums

# ============================================================================
# 游戏阶段
# ============================================================================

## 游戏主阶段
enum GamePhase {
	IDLE = 0,
	EXPLORE = 1,    # 现实世界探索
	BATTLE = 2,     # 战斗/事件处理
	SHOP = 3,       # 商店
	DARK_WORLD = 4, # 暗面世界探索
	TRANSITION = 5, # 阶段转换
}

# ============================================================================
# 回合状态
# ============================================================================

## 回合状态
enum TurnState {
	PLAYER = 0,     # 玩家回合
	ENEMY = 1,      # 敌人回合
	NPC = 2,        # NPC回合
}

# ============================================================================
# 暗世界状态
# ============================================================================

## 暗面世界子状态
enum DarkState {
	IDLE = 0,       # 空闲
	READY = 1,      # 就绪(可操作)
	MOVING = 2,     # 移动中
	POPUP = 3,      # 弹窗显示中
	TRANSITION = 4, # 过渡/转换中
}

# ============================================================================
# 卡牌类型
# ============================================================================

## 卡牌类型
enum CardType {
	SAFE = 0,       # 安全区
	MONSTER = 1,    # 怪物
	TRAP = 2,       # 陷阱
	SHOP = 3,       # 商店
	HOME = 4,       # 家
	LANDMARK = 5,  # 地标
	EVENT = 6,      # 事件
}

## 卡牌子类型 (陷阱)
enum TrapSubtype {
	SANITY = 0,     # 阴气侵蚀
	MONEY = 1,      # 财物散失
	FILM = 2,       # 灵雾曝光
	TELEPORT = 3,   # 空间错位
}

## 暗面卡牌类型
enum DarkCardType {
	NORMAL = 0,         # 普通走廊
	SHOP = 1,           # 暗市
	INTEL = 2,          # 情报点
	CLUE = 3,           # 线索
	ITEM = 4,           # 道具
	PASSAGE = 5,        # 层间通道
	ABYSS_CORE = 6,     # 深渊核心
	CHECKPOINT = 7,     # 检查点
	NPC = 8,            # NPC
}

# ============================================================================
# 事件类型
# ============================================================================

## 事件来源
enum EventSource {
	RIFT = 0,       # 裂隙
	CARD = 1,       # 卡牌事件
	RANDOM = 2,     # 随机事件
	STORY = 3,      # 剧情事件
}

# ============================================================================
# 资源类型
# ============================================================================

## 资源类型
enum ResourceType {
	SANITY = 0,     # 理智
	MONEY = 1,      # 金钱
	FILM = 2,       # 胶卷
	FRAGMENT = 3,   # 碎片
}

# ============================================================================
# UI状态
# ============================================================================

## 弹窗类型
enum PopupType {
	NONE = 0,
	EVENT = 1,
	SHOP = 2,
	DIALOGUE = 3,
	CONFIRM = 4,
}

## 对话来源
enum DialogueSource {
	NPC = 0,
	SYSTEM = 1,
	ITEM = 2,
}

# ============================================================================
# 相机模式
# ============================================================================

## 相机模式
enum CameraMode {
	ORBIT = 0,      # 环绕模式
	FIXED = 1,      # 固定视角
	FOLLOW = 2,     # 跟随模式
}

# ============================================================================
# 动画状态
# ============================================================================

## 动画播放状态
enum AnimationState {
	IDLE = 0,
	PLAYING = 1,
	PAUSED = 2,
	COMPLETED = 3,
}

# ============================================================================
# 工具函数
# ============================================================================

## 获取游戏阶段名称
static func get_game_phase_name(phase: GamePhase) -> String:
	match phase:
		GamePhase.IDLE: return "空闲"
		GamePhase.EXPLORE: return "探索"
		GamePhase.BATTLE: return "战斗"
		GamePhase.SHOP: return "商店"
		GamePhase.DARK_WORLD: return "暗世界"
		GamePhase.TRANSITION: return "过渡"
	return "未知"

## 获取暗世界状态名称
static func get_dark_state_name(state: DarkState) -> String:
	match state:
		DarkState.IDLE: return "空闲"
		DarkState.READY: return "就绪"
		DarkState.MOVING: return "移动中"
		DarkState.POPUP: return "弹窗"
		DarkState.TRANSITION: return "过渡"
	return "未知"

## 获取资源类型名称
static func get_resource_name(type: ResourceType) -> String:
	match type:
		ResourceType.SANITY: return "理智"
		ResourceType.MONEY: return "金钱"
		ResourceType.FILM: return "胶卷"
		ResourceType.FRAGMENT: return "碎片"
	return "未知"
