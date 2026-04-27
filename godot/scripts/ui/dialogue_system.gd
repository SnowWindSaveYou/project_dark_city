## DialogueSystem - Gal 风格打字机对话系统
## 对应原版 DialogueSystem.lua
## 笔记本美学 + 视觉小说风格，立绘 + 打字机效果 + 状态机
## Godot 2D: 数据层 + _draw() 绘制，动画由 main.gd tween 驱动
class_name DialogueSystem
extends RefCounted

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

## 打字机速度 (每秒字符数)
const TYPEWRITER_SPEED := 18
## 暗色遮罩最大透明度 (0~1)
const OVERLAY_ALPHA_MAX := 0.39  # ≈100/255

## 对话框布局
const BOX_H_RATIO := 0.28       # 对话框占屏幕高度
const BOX_MARGIN_X := 20.0
const BOX_MARGIN_BOTTOM := 16.0
const BOX_PAD_X := 28.0
const BOX_PAD_TOP := 36.0       # 给名牌留空间
const BOX_PAD_BOTTOM := 16.0
const BOX_RADIUS := 12.0
const BOX_LINE_SPACING := 22.0  # 笔记本横线间距

## 名牌
const NAME_TAG_H := 26.0
const NAME_TAG_PAD_X := 14.0
const NAME_TAG_RADIUS := 6.0
const NAME_TAG_OFFSET_Y := -14.0

## 立绘
const PORTRAIT_H_RATIO := 0.75
const PORTRAIT_MARGIN_LEFT := 0.05

## 闪烁三角
const ADVANCE_BLINK_SPEED := 2.5

## 字体
const FONT_SIZE_TEXT := 16
const FONT_SIZE_NAME := 14
const LINE_H_MULT := 1.5

# ---------------------------------------------------------------------------
# 动画属性 (由 main.gd tween 驱动)
# ---------------------------------------------------------------------------

var overlay_alpha := 0.0   # 遮罩 0~1
var box_offset_y := 80.0   # 对话框上滑偏移
var box_alpha := 0.0       # 对话框透明度
var portrait_alpha := 0.0  # 立绘透明度
var portrait_offset_y := 40.0
var portrait_scale := 0.9

# ---------------------------------------------------------------------------
# 内部状态
# ---------------------------------------------------------------------------

## 状态机: "idle" → "entering" → "typing" → "waiting" → "exiting" → "idle"
var state: String = "idle"

## 对话脚本 (Array of { "speaker": String, "text": String })
var _script: Array = []
var _script_index: int = 0
var _on_complete: Callable = Callable()
var _prev_demo_state: String = "ready"

## 立绘
var portrait_tex_path: String = ""
var _portrait_tex: Texture2D = null

## 打字机
var _typewriter_pos: int = 0    # 当前显示字符数
var _typewriter_total: int = 0  # 当前行总字符数
var _typewriter_accum: float = 0.0

## 当前行数据
var _current_speaker: String = ""
var _current_text: String = ""

# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

## 开始对话
## dialogue_script: Array of { "speaker": String, "text": String }
## portrait_path: 立绘纹理路径
## on_complete: 对话结束回调
func start(dialogue_script: Array, portrait_path: String = "",
		on_complete: Callable = Callable()) -> void:
	if state != "idle":
		return
	if dialogue_script.is_empty():
		if on_complete.is_valid():
			on_complete.call()
		return

	_script = dialogue_script
	_script_index = 0
	_on_complete = on_complete
	portrait_tex_path = portrait_path

	# 加载立绘纹理
	if portrait_path != "":
		_portrait_tex = load(portrait_path) as Texture2D
	else:
		_portrait_tex = null

	# 重置动画属性
	overlay_alpha = 0.0
	box_offset_y = 80.0
	box_alpha = 0.0
	portrait_alpha = 0.0
	portrait_offset_y = 40.0
	portrait_scale = 0.9

	_prev_demo_state = GameData.demo_state
	state = "entering"
	GameData.set_demo_state("dialogue")  # 设置对话状态，禁止其他交互
	# main.gd 负责 tween 进场动画:
	#   overlay_alpha → 1.0
	#   box_offset_y → 0.0, box_alpha → 1.0
	#   portrait_alpha → 1.0, portrait_offset_y → 0.0, portrait_scale → 1.0
	# 动画完成后调用 on_enter_complete()

## 进场动画完成后由 main.gd 调用
func on_enter_complete() -> void:
	_load_line(0)

## 是否正在对话
func is_active() -> bool:
	return state != "idle"

## 点击推进 (返回 true 表示事件被消费)
func handle_click() -> bool:
	if state == "idle":
		return false
	_advance()
	return true

## 按键推进 (Return / Space)
func handle_key() -> bool:
	if state == "idle":
		return false
	_advance()
	return true

## 每帧更新 (打字机效果)
func update(dt: float) -> void:
	if state != "typing":
		return

	_typewriter_accum += dt
	var chars_to_show := int(_typewriter_accum * TYPEWRITER_SPEED)
	if chars_to_show > _typewriter_pos:
		_typewriter_pos = mini(chars_to_show, _typewriter_total)

	if _typewriter_pos >= _typewriter_total:
		state = "waiting"

## 重置
func reset() -> void:
	var was_active := (state != "idle")
	state = "idle"
	_script = []
	_script_index = 0
	_on_complete = Callable()
	overlay_alpha = 0.0
	box_alpha = 0.0
	portrait_alpha = 0.0
	_portrait_tex = null
	# 如果对话正在进行，恢复对话前的状态
	if was_active:
		GameData.set_demo_state(_prev_demo_state)

## 获取当前显示文本 (用于 _draw)
func get_display_text() -> String:
	if _current_text == "":
		return ""
	if state == "typing" and _typewriter_pos < _typewriter_total:
		return _current_text.substr(0, _typewriter_pos)
	return _current_text

## 获取当前说话人
func get_speaker() -> String:
	return _current_speaker

## 获取立绘纹理
func get_portrait_texture() -> Texture2D:
	return _portrait_tex

# ---------------------------------------------------------------------------
# 内部方法
# ---------------------------------------------------------------------------

func _load_line(index: int) -> void:
	if _script.is_empty() or index < 0 or index >= _script.size():
		return
	var line: Dictionary = _script[index]
	_current_speaker = line.get("speaker", "")
	_current_text = line.get("text", "")
	_typewriter_total = _current_text.length()
	_typewriter_pos = 0
	_typewriter_accum = 0.0
	state = "typing"

func _advance() -> void:
	if state == "typing":
		# 跳过打字，直接显示全部
		_typewriter_pos = _typewriter_total
		state = "waiting"
		return

	if state == "waiting":
		_script_index += 1
		if _script_index < _script.size():
			_load_line(_script_index)
		else:
			# 对话结束 → 退场
			state = "exiting"
			# main.gd 负责 tween 退场动画:
			#   overlay_alpha → 0.0
			#   box_offset_y → 60.0, box_alpha → 0.0
			#   portrait_alpha → 0.0, portrait_offset_y → 20.0
			# 动画完成后调用 on_exit_complete()

## 退场动画完成后由 main.gd 调用
func on_exit_complete() -> void:
	state = "idle"
	_script = []
	_script_index = 0
	_portrait_tex = null
	GameData.set_demo_state(_prev_demo_state)  # 恢复对话前的状态
	if _on_complete.is_valid():
		var cb := _on_complete
		_on_complete = Callable()
		cb.call()
