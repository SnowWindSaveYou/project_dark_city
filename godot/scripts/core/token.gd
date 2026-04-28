## Token - 玩家棋子
## 对应原版 Token.lua
## 15 种表情，呼吸/弹跳/挤压/翻面动效
## 在 Godot 中作为 Sprite2D 或 TextureRect 子节点使用
class_name Token
extends RefCounted

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

## 显示尺寸 (像素，实际渲染时由场景缩放)
const SPRITE_W: float = 64.0
const SPRITE_H: float = 96.0
const DEAD_W: float = 96.0
const DEAD_H: float = 64.0

# ---------------------------------------------------------------------------
# 表情映射 (路径相对于 assets/textures/)
# 实际项目中需替换为真实贴图路径
# ---------------------------------------------------------------------------
const EMOTIONS: Dictionary = {
	"default":    "res://assets/textures/token/token_default.png",
	"happy":      "res://assets/textures/token/token_happy.png",
	"scared":     "res://assets/textures/token/token_scared.png",
	"surprised":  "res://assets/textures/token/token_surprised.png",
	"nervous":    "res://assets/textures/token/token_nervous.png",
	"angry":      "res://assets/textures/token/token_angry.png",
	"determined": "res://assets/textures/token/token_determined.png",
	"relieved":   "res://assets/textures/token/token_relieved.png",
	"sleepy":     "res://assets/textures/token/token_sleepy.png",
	"confused":   "res://assets/textures/token/token_confused.png",
	"sad":        "res://assets/textures/token/token_sad.png",
	"dead":       "res://assets/textures/token/token_dead.png",
	"disgusted":  "res://assets/textures/token/token_disgusted.png",
	"dazed":      "res://assets/textures/token/token_dazed.png",
	"running":    "res://assets/textures/token/token_running.png",
}

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------

## 逻辑坐标 (棋盘行列)
var target_row: int = 1
var target_col: int = 1

## 渲染坐标 (像素)
var pos_x: float = 0.0
var pos_y: float = 0.0
var bounce_y: float = 0.0  # 跳跃偏移 (负值=向上)

## 变换
var scale_x: float = 1.0
var scale_y: float = 1.0
var alpha: float = 0.0
var squash_x: float = 1.0
var squash_y: float = 1.0

## 状态
var is_moving: bool = false
var visible: bool = false
var idle_timer: float = 0.0

## 表情
var emotion: String = "default"
var _pending_emotion: String = ""

## 纹理缓存 { emotion_name: Texture2D }
var textures: Dictionary = {}

# ---------------------------------------------------------------------------
# 纹理加载
# ---------------------------------------------------------------------------

## 加载所有表情纹理，返回加载数量
func load_textures() -> int:
	var loaded: int = 0
	var loaded_paths: Dictionary = {}
	for key in EMOTIONS:
		var path: String = EMOTIONS[key]
		if loaded_paths.has(path):
			textures[key] = loaded_paths[path]
			loaded += 1
		else:
			if ResourceLoader.exists(path):
				var tex: Texture2D = load(path) as Texture2D
				if tex:
					textures[key] = tex
					loaded_paths[path] = tex
					loaded += 1
			# 缺少纹理时生成占位色块
			if not textures.has(key):
				textures[key] = _generate_placeholder(key)
				loaded += 1
	return loaded

## 生成占位纹理 (纯色 + 文字标签)
func _generate_placeholder(emotion_name: String) -> Texture2D:
	var img: Image = Image.create(64, 96, false, Image.FORMAT_RGBA8)
	var base_color: Color = Color(0.4, 0.35, 0.5)
	if emotion_name == "dead":
		base_color = Color(0.3, 0.2, 0.2)
	elif emotion_name == "happy":
		base_color = Color(0.5, 0.6, 0.3)
	elif emotion_name == "scared":
		base_color = Color(0.6, 0.3, 0.5)
	img.fill(base_color)
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------------------
# 表情切换
# ---------------------------------------------------------------------------

## 获取当前表情纹理
func get_current_texture() -> Texture2D:
	return textures.get(emotion, textures.get("default"))

## 切换表情 (返回是否需要翻面动画)
func set_emotion(new_emotion: String) -> bool:
	if not EMOTIONS.has(new_emotion):
		new_emotion = "default"
	if emotion == new_emotion:
		return false
	if is_moving:
		# 移动中直接切换
		emotion = new_emotion
		return false
	# 需要翻面动画
	_pending_emotion = new_emotion
	return true

## 完成翻面 (在 squash_x = 0 时调用)
func apply_pending_emotion() -> void:
	if _pending_emotion != "":
		emotion = _pending_emotion
		_pending_emotion = ""

## 弹跳 (拍照/驱魔时的小跳)
func hop(height: float = 0.05) -> void:
	# height 参数是归一化值，乘以基准高度得到像素偏移
	var px_height: float = height * 200.0  # 0.05 → 10px, 0.06 → 12px
	bounce_y = -px_height

# ---------------------------------------------------------------------------
# 动画参数计算
# ---------------------------------------------------------------------------

## 呼吸动画偏移 (非移动时)
func get_breathe_offset(game_time: float) -> Dictionary:
	if is_moving:
		return { "y": 0.0, "scale": 1.0 }
	var breathe_y: float = sin(game_time * 2.5) * 1.5
	var breathe_scale: float = 1.0 + sin(game_time * 2.5) * 0.02
	return { "y": breathe_y, "scale": breathe_scale }

## 获取当前渲染尺寸
func get_render_size(breathe_scale: float = 1.0) -> Vector2:
	var base_w: float = DEAD_W if emotion == "dead" else SPRITE_W
	var base_h: float = DEAD_H if emotion == "dead" else SPRITE_H
	return Vector2(
		base_w * scale_x * squash_x * breathe_scale,
		base_h * scale_y * squash_y * breathe_scale
	)

# ---------------------------------------------------------------------------
# 移动辅助
# ---------------------------------------------------------------------------

## 计算移动时长 (基于距离)
func calc_move_duration(target_x: float, target_y: float) -> float:
	var dx: float = target_x - pos_x
	var dy: float = target_y - pos_y
	var dist: float = sqrt(dx * dx + dy * dy)
	return clampf(dist / 250.0, 0.25, 0.6)

## 计算跳跃高度 (基于距离)
func calc_jump_height(target_x: float, target_y: float) -> float:
	var dx: float = target_x - pos_x
	var dy: float = target_y - pos_y
	var dist: float = sqrt(dx * dx + dy * dy)
	return minf(15.0, dist * 0.1 + 5.0)

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------

func update(dt: float) -> void:
	if not visible:
		return
	idle_timer += dt

	# 弹跳衰减 (弹簧阻尼)
	if abs(bounce_y) > 0.1:
		bounce_y = lerpf(bounce_y, 0.0, minf(1.0, dt * 10.0))
	else:
		bounce_y = 0.0

	# 翻面动画 (squash_x 趋向目标)
	if _pending_emotion != "" and squash_x > 0.01:
		squash_x = lerpf(squash_x, 0.0, minf(1.0, dt * 12.0))
		if squash_x < 0.05:
			squash_x = 0.0
			apply_pending_emotion()
	elif _pending_emotion == "" and squash_x < 1.0:
		squash_x = lerpf(squash_x, 1.0, minf(1.0, dt * 12.0))
		if squash_x > 0.95:
			squash_x = 1.0
