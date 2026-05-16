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
const TYPEWRITER_SPEED: int = 18
## 暗色遮罩最大透明度 (0~1)
const OVERLAY_ALPHA_MAX: float = 0.39  # ≈100/255

## 对话框布局
const BOX_H_RATIO: float = 0.28  # 对话框占屏幕高度
const BOX_MARGIN_X: float = 20.0
const BOX_MARGIN_BOTTOM: float = 16.0
const BOX_PAD_X: float = 28.0
const BOX_PAD_TOP: float = 36.0  # 给名牌留空间
const BOX_PAD_BOTTOM: float = 16.0
const BOX_RADIUS: float = 12.0
const BOX_LINE_SPACING: float = 22.0  # 笔记本横线间距

## 名牌
const NAME_TAG_H: float = 26.0
const NAME_TAG_PAD_X: float = 14.0
const NAME_TAG_RADIUS: float = 6.0
const NAME_TAG_OFFSET_Y: float = -14.0

## 立绘
const PORTRAIT_H_RATIO: float = 0.75
const PORTRAIT_MARGIN_LEFT: float = 0.05

## 闪烁三角
const ADVANCE_BLINK_SPEED: float = 2.5

## 字体
const FONT_SIZE_TEXT: int = 16
const FONT_SIZE_NAME: int = 14
const LINE_H_MULT: float = 1.5

# ---------------------------------------------------------------------------
# 动画属性 (由 main.gd tween 驱动)
# ---------------------------------------------------------------------------

var overlay_alpha: float = 0.0  # 遮罩 0~1
var box_offset_y: float = 80.0  # 对话框上滑偏移
var box_alpha: float = 0.0  # 对话框透明度
var portrait_alpha: float = 0.0  # 立绘透明度
var portrait_offset_y: float = 40.0
var portrait_scale: float = 0.9
var bg_image_alpha: float = 0.0  # 背景图透明度

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

## 背景图
var bg_image_path: String = ""
var _bg_tex: Texture2D = null
## 行级背景切换：crossfade 用第二层（新图），alpha 从 0→1，旧图同步 1→0
var _bg_tex_next: Texture2D = null
var bg_next_alpha: float = 0.0
## 行级背景切换：_load_line 检测到新路径时置为非空，main.gd 消费后清空
var bg_pending_path: String = ""

## 打字机
var _typewriter_pos: int = 0    # 当前显示字符数
var _typewriter_total: int = 0  # 当前行总字符数
var _typewriter_accum: float = 0.0

## 当前行数据
var _current_speaker: String = ""
var _current_text: String = ""
var _current_choices: Array = []  ## 当前行的选项列表 (可为空)
var _selected_choice: Dictionary = {}  ## 玩家选择的选项 (on_complete 后可读)

# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

## 开始对话
## dialogue_script: Array of { "speaker": String, "text": String }
## portrait_path: 立绘纹理路径
## bg_path: 背景图路径 (空字符串 = 无背景)
## on_complete: 对话结束回调
func start(dialogue_script: Array, portrait_path: String = "",
		bg_path: String = "", on_complete: Callable = Callable()) -> void:
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

	# 加载背景图纹理
	bg_image_path = bg_path
	if bg_path != "":
		_bg_tex = load(bg_path) as Texture2D
	else:
		_bg_tex = null

	# 重置动画属性
	overlay_alpha = 0.0
	box_offset_y = 80.0
	box_alpha = 0.0
	portrait_alpha = 0.0
	portrait_offset_y = 40.0
	portrait_scale = 0.9
	bg_image_alpha = 0.0

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

## 跳过整段对话 (非 choosing 状态可用)
## 直接结束对话并触发退场动画
func skip() -> void:
	if state == "idle" or state == "exiting" or state == "entering":
		return
	# 有选项时不允许跳过 (必须做选择)
	if state == "waiting" and not _current_choices.is_empty():
		return
	# 直接跳到末尾并触发退场
	_script_index = _script.size()
	_current_choices = []
	state = "exiting"

## 每帧更新 (打字机效果)
func update(dt: float) -> void:
	if state != "typing":
		return

	_typewriter_accum += dt
	var chars_to_show: int = int(_typewriter_accum * TYPEWRITER_SPEED)
	if chars_to_show > _typewriter_pos:
		_typewriter_pos = mini(chars_to_show, _typewriter_total)

	if _typewriter_pos >= _typewriter_total:
		state = "waiting"

## 重置
func reset() -> void:
	var was_active: bool = (state != "idle")
	state = "idle"
	_script = []
	_script_index = 0
	_on_complete = Callable()
	_current_choices = []
	_selected_choice = {}
	overlay_alpha = 0.0
	box_alpha = 0.0
	portrait_alpha = 0.0
	bg_image_alpha = 0.0
	_portrait_tex = null
	_bg_tex = null
	bg_pending_path = ""
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

## 获取当前行选项列表 (空数组 = 无选项)
func get_current_choices() -> Array:
	return _current_choices

## 获取玩家选择的选项 (对话结束后有效)
func get_selected_choice() -> Dictionary:
	return _selected_choice

## 玩家选择了某个选项 (由 dialogue_overlay 调用)
func select_choice(index: int) -> void:
	if state != "waiting" or _current_choices.is_empty():
		return
	if index < 0 or index >= _current_choices.size():
		return
	_selected_choice = _current_choices[index]
	_current_choices = []   # 清空, 让 _advance 正常推进
	_advance()

## 获取立绘纹理
func get_portrait_texture() -> Texture2D:
	return _portrait_tex

## 获取背景图纹理
func get_bg_texture() -> Texture2D:
	return _bg_tex

# ---------------------------------------------------------------------------
# 内部方法
# ---------------------------------------------------------------------------

func _load_line(index: int) -> void:
	if _script.is_empty() or index < 0 or index >= _script.size():
		return
	var line: Dictionary = _script[index]
	_current_speaker = line.get("speaker", "")
	_current_text = line.get("text", "")
	_current_choices = line.get("choices", [])
	_typewriter_total = _current_text.length()
	_typewriter_pos = 0
	_typewriter_accum = 0.0
	# 行级背景切换：路径非空且与当前不同时，通知 main.gd 做 cross-fade
	var line_bg: String = line.get("bg_image", "")
	if line_bg != "" and line_bg != bg_image_path:
		bg_pending_path = line_bg
	state = "typing"

func _advance() -> void:
	if state == "typing":
		# 跳过打字，直接显示全部
		_typewriter_pos = _typewriter_total
		state = "waiting"
		return

	if state == "waiting":
		# 有选项时必须等玩家选择，不可直接推进
		if not _current_choices.is_empty():
			return
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
	# 过渡态（flipping/dealing 等）不能直接恢复，否则游戏卡死，统一回退到 ready
	const TRANSIT_STATES: Array = ["flipping", "dealing", "moving"]
	var restore_state: String = _prev_demo_state if _prev_demo_state not in TRANSIT_STATES else "ready"
	print("[DialogueSystem] on_exit_complete: restoring demo_state='%s' (prev='%s'), current='%s', has_cb=%s" % [restore_state, _prev_demo_state, GameData.demo_state, _on_complete.is_valid()])
	state = "idle"
	_script = []
	_script_index = 0
	_portrait_tex = null
	_bg_tex = null
	bg_pending_path = ""
	# 仅当 demo_state 仍为 "dialogue" 时才恢复，防止异步场景切换（如进入暗面）后状态被覆盖
	if GameData.demo_state == "dialogue":
		GameData.set_demo_state(restore_state)
	if _on_complete.is_valid():
		var cb: Callable = _on_complete
		_on_complete = Callable()
		cb.call()
