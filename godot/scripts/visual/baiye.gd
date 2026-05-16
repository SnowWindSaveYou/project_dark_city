class_name Baiye
extends RefCounted

## Baiye - 白夜跟随精灵 (2D 数据层)
## 半透明灵体同伴，以飘浮姿态跟随玩家棋子
## 绘制由 main.gd _draw() 统一处理，此类仅管理状态和数据
##
## 对应原版 Baiye.lua

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

## 纹理路径
const TEXTURE_PATH: String = "res://assets/image/白夜_chibi_20260506003802.png"

## 跟随偏移 (相对 Token 的像素坐标)
const OFFSET_X: float = -20.0   # 左侧
const OFFSET_Y: float = -8.0    # 稍微上方

## 跟随平滑速度 (越大越紧, 越小越飘)
const FOLLOW_SPEED: float = 4.0

## 灵体透明度
const SPIRIT_ALPHA: float = 0.50

## 浮动动画参数
const FLOAT_FREQ_Y: float = 1.8     # Y 轴浮动频率
const FLOAT_AMP_Y: float = 3.0      # Y 轴浮动幅度 (像素)
const FLOAT_FREQ_X: float = 1.1     # X 轴浮动频率
const FLOAT_AMP_X: float = 2.0      # X 轴浮动幅度 (像素)
const BREATHE_AMP: float = 0.035    # 呼吸缩放幅度

## 显示条件（已移除 trust 门槛，白夜从一开始就跟随）

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------

## 当前世界坐标
var world_x: float = 0.0
var world_y: float = 0.0

## 跟随目标
var target_x: float = 0.0
var target_y: float = 0.0

## 显示属性
var alpha: float = 0.0
var scale_x: float = 1.0
var scale_y: float = 1.0
var visible: bool = false

## 纹理
var texture: Texture2D = null

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _init() -> void:
	if ResourceLoader.exists(TEXTURE_PATH):
		texture = load(TEXTURE_PATH) as Texture2D
		if texture:
			print("[Baiye] Loaded texture: %s" % TEXTURE_PATH)
		else:
			push_warning("[Baiye] Texture exists but failed to cast: %s" % TEXTURE_PATH)
	else:
		push_warning("[Baiye] Texture not imported yet (run editor to import): %s" % TEXTURE_PATH)

# ---------------------------------------------------------------------------
# 显示条件检查
# ---------------------------------------------------------------------------

## 是否应该显示白夜（无 trust 门槛，沉睡时除外）
func should_show() -> bool:
	return StoryManager.is_baiye_available()

# ---------------------------------------------------------------------------
# 显示 / 隐藏
# ---------------------------------------------------------------------------

## 显示白夜 (Token 出现时调用)
## token_x, token_y: Token 的像素坐标
func show(token_x: float, token_y: float) -> void:
	if not should_show():
		return

	# 直接定位到 Token 旁边
	world_x = token_x + OFFSET_X
	world_y = token_y + OFFSET_Y
	target_x = world_x
	target_y = world_y
	visible = true

	# 入场: 从小+透明 → 正常 (由外部 tween 驱动)
	scale_x = 0.3
	scale_y = 0.3
	alpha = 0.0

## 隐藏白夜 (暗面进入 / 沉睡等场景)
func hide() -> void:
	visible = false
	alpha = 0.0

## 更新跟随目标
func set_follow_target(token_x: float, token_y: float) -> void:
	target_x = token_x + OFFSET_X
	target_y = token_y + OFFSET_Y

# ---------------------------------------------------------------------------
# 每帧更新
# ---------------------------------------------------------------------------

## 平滑跟随 Token (指数衰减)
func update(dt: float) -> void:
	if not visible:
		return

	# 指数衰减跟随
	var t: float = 1.0 - exp(-FOLLOW_SPEED * dt)
	world_x = lerpf(world_x, target_x, t)
	world_y = lerpf(world_y, target_y, t)

## 获取绘制数据 (供 main.gd _draw 使用)
## game_time: 全局游戏时间 (用于动画)
func get_draw_data(game_time: float) -> Dictionary:
	if not visible or alpha <= 0.01 or texture == null:
		return { "visible": false }

	# 浮动动画
	var float_y: float = sin(game_time * FLOAT_FREQ_Y) * FLOAT_AMP_Y
	var float_x: float = sin(game_time * FLOAT_FREQ_X + 0.7) * FLOAT_AMP_X
	var breathe_scale: float = 1.0 + sin(game_time * FLOAT_FREQ_Y) * BREATHE_AMP

	var draw_x: float = world_x + float_x
	var draw_y: float = world_y + float_y

	var final_scale_x: float = scale_x * breathe_scale
	var final_scale_y: float = scale_y * breathe_scale

	return {
		"visible": true,
		"texture": texture,
		"x": draw_x,
		"y": draw_y,
		"alpha": alpha,
		"scale_x": final_scale_x,
		"scale_y": final_scale_y,
	}
