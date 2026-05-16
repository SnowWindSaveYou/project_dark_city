## DestinationHint — 目的地提示浮标
## 物语系列风格：竖排扭曲文字，白色主体 + 灰色重影
## 显示在未完成当日日程的目的地卡牌上方
##
## 使用方式（由 board_visual 管理）：
##   var hint = DestinationHint.new()
##   parent.add_child(hint)
##   hint.show_hint("park", "公园") 或 hint.show_hint_with_text("自定义文字")
##   hint.hide_hint()
class_name DestinationHint
extends Node3D

# ---------------------------------------------------------------------------
# 主角对各地点的内心独白池（每个地点 4~6 条，随机抽取）
# 风格参考：物语系列——简短、片段式、带情绪
# ---------------------------------------------------------------------------
const HINT_POOL: Dictionary = {
	"park": [
		"想\n去\n走\n走",
		"空\n气\n很\n好",
		"今\n天\n去\n吗",
		"要\n不\n要\n去",
		"草\n地\n很\n软",
	],
	"convenience": [
		"买\n点\n吃\n的",
		"还\n有\n存\n货",
		"顺\n路\n去\n下",
		"泡\n面\n还\n有",
		"去\n看\n看",
	],
	"church": [
		"去\n祈\n祷\n吧",
		"需\n要\n平\n静",
		"我\n信\n什\n么",
		"安\n静\n的\n地\n方",
		"神\n明\n在\n吗",
	],
	"police": [
		"说\n了\n会\n信\n吗",
		"还\n是\n去\n吧",
		"能\n怎\n么\n说",
		"有\n用\n吗",
		"试\n试\n看",
	],
	"company": [
		"得\n去\n上\n班",
		"装\n作\n正\n常",
		"一\n切\n如\n常",
		"撑\n过\n今\n天",
		"不\n能\n缺\n勤",
	],
	"school": [
		"去\n上\n课\n吧",
		"别\n旷\n课\n了",
		"装\n作\n专\n注",
		"还\n是\n得\n去",
		"今\n天\n也\n是",
	],
	"alley": [
		"不\n太\n安\n全",
		"快\n点\n过\n去",
		"别\n停\n下\n来",
		"有\n什\n么\n在\n看",
		"走\n快\n一\n点",
	],
	"station": [
		"还\n在\n等\n吗",
		"不\n会\n来\n的",
		"还\n是\n去\n吧",
		"只\n是\n车\n站",
		"等\n一\n下\n就\n好",
	],
	"hospital": [
		"去\n检\n查\n下",
		"没\n事\n的\n吧",
		"别\n想\n太\n多",
		"只\n是\n看\n看",
		"不\n会\n有\n事",
	],
	"library": [
		"查\n点\n东\n西",
		"那\n里\n安\n静",
		"书\n里\n有\n答\n案\n吗",
		"找\n找\n线\n索",
		"翻\n翻\n旧\n书",
	],
	"bank": [
		"去\n办\n一\n下",
		"没\n多\n少\n钱",
		"快\n去\n快\n回",
		"手\n续\n很\n烦",
		"得\n去\n一\n趟",
	],
	"cemetery": [
		"有\n点\n怕",
		"别\n想\n太\n多",
		"白\n天\n去\n吧",
		"查\n一\n查\n吧",
		"到\n底\n是\n谁",
	],
	"gym": [
		"动\n一\n动\n吧",
		"出\n点\n汗",
		"跑\n一\n会\n儿",
		"忘\n掉\n那\n些",
		"累\n了\n就\n好\n了",
	],
	"home": [
		"回\n家\n吧",
		"待\n着\n也\n好",
		"休\n息\n一\n下",
		"今\n天\n就\n这\n样",
		"哪\n也\n不\n去",
	],
}

## 当地点不在池中时的默认文字
const DEFAULT_POOL: Array[String] = [
	"得\n去\n一\n趟",
	"去\n看\n看\n吧",
	"该\n去\n的",
	"还\n没\n去",
	"今\n天\n去",
]

# ---------------------------------------------------------------------------
# 视觉参数
# ---------------------------------------------------------------------------
## 文字颜色：白色主体
const COLOR_MAIN: Color   = Color(1.00, 0.98, 0.97, 0.90)
## 重影颜色：灰色，偏移 1~2 像素
const COLOR_GHOST1: Color = Color(0.72, 0.68, 0.70, 0.55)
const COLOR_GHOST2: Color = Color(0.55, 0.52, 0.54, 0.30)

## 字号（pixel 空间，后续按 pixel_size 换算）
const FONT_SIZE: int = 36

## Label3D 离卡面上方高度
const BASE_Y: float = 0.82

## 扭曲振幅（左右摇摆幅度，单位：米）
const WAVE_AMP: float = 0.012
## 扭曲频率
const WAVE_FREQ: float = 0.55

## 呼吸透明度参数
const BREATH_AMP: float  = 0.18
const BREATH_FREQ: float = 0.45

## 弹出动画时长
const POP_DUR: float = 0.38
## 隐藏动画时长
const HIDE_DUR: float = 0.22

# ---------------------------------------------------------------------------
# 运行时状态
# ---------------------------------------------------------------------------
var _label_main: Label3D  = null    # 白色主文字
var _label_ghost1: Label3D = null   # 灰色重影1（偏右下）
var _label_ghost2: Label3D = null   # 灰色重影2（偏左上）

var _hint_text: String = ""
var _time: float = 0.0
var _base_y: float = BASE_Y

var _visible_anim: bool = false
var _anim_tween: Tween = null

# 扭曲基准相位（每个实例随机，避免多个 hint 同步晃动）
var _wave_phase: float = 0.0

# Node3D 没有 modulate，用 _alpha 统一控制三个 Label3D 子节点的透明度
var _alpha: float = 1.0:
	set(v):
		_alpha = v
		if _label_main:   _label_main.modulate.a   = v
		if _label_ghost1: _label_ghost1.modulate.a = v
		if _label_ghost2: _label_ghost2.modulate.a = v

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	_wave_phase = randf() * TAU
	_build_labels()
	visible = false


func _build_labels() -> void:
	var font: Font = ThemeDB.fallback_font

	# 重影2（最底层，偏左上）
	_label_ghost2 = Label3D.new()
	_label_ghost2.font = font
	_label_ghost2.font_size = FONT_SIZE
	_label_ghost2.modulate = COLOR_GHOST2
	_label_ghost2.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label_ghost2.no_depth_test = false
	_label_ghost2.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	_label_ghost2.render_priority = 1
	_label_ghost2.outline_size = 0
	_label_ghost2.double_sided = true
	_label_ghost2.shaded = false
	_label_ghost2.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label_ghost2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label_ghost2)

	# 重影1（中层，偏右下）
	_label_ghost1 = Label3D.new()
	_label_ghost1.font = font
	_label_ghost1.font_size = FONT_SIZE
	_label_ghost1.modulate = COLOR_GHOST1
	_label_ghost1.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label_ghost1.no_depth_test = false
	_label_ghost1.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	_label_ghost1.render_priority = 2
	_label_ghost1.outline_size = 0
	_label_ghost1.double_sided = true
	_label_ghost1.shaded = false
	_label_ghost1.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label_ghost1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label_ghost1)

	# 主文字（最上层）
	_label_main = Label3D.new()
	_label_main.font = font
	_label_main.font_size = FONT_SIZE
	_label_main.modulate = COLOR_MAIN
	_label_main.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label_main.no_depth_test = false
	_label_main.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	_label_main.render_priority = 3
	_label_main.outline_size = 0
	_label_main.double_sided = true
	_label_main.shaded = false
	_label_main.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label_main)

	# 初始文字
	_set_text_all("？")


func _set_text_all(text: String) -> void:
	if _label_main:
		_label_main.text = text
	if _label_ghost1:
		_label_ghost1.text = text
	if _label_ghost2:
		_label_ghost2.text = text

# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

## 根据地点 ID 随机选取内心独白并显示
func show_hint(location_id: String) -> void:
	var pool: Array = HINT_POOL.get(location_id, DEFAULT_POOL)
	var text: String = pool[randi() % pool.size()]
	show_hint_with_text(text)


## 直接指定文字显示（文字需已是竖排换行格式）
func show_hint_with_text(text: String) -> void:
	_hint_text = text
	_set_text_all(text)

	# 停止旧的 tween
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	visible = true
	_visible_anim = true

	# 初始状态：缩小 + 透明
	scale = Vector3(0.05, 0.05, 0.05)
	_alpha = 0.0

	_anim_tween = get_tree().create_tween().set_parallel(true)
	_anim_tween.tween_property(self, "scale", Vector3.ONE, POP_DUR)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_anim_tween.tween_property(self, "_alpha", 1.0, POP_DUR * 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_LINEAR)


## 隐藏提示（带淡出动画）
func hide_hint() -> void:
	if not visible or not _visible_anim:
		return
	_visible_anim = false

	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = get_tree().create_tween().set_parallel(true)
	_anim_tween.tween_property(self, "_alpha", 0.0, HIDE_DUR)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_anim_tween.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), HIDE_DUR)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_anim_tween.chain().tween_callback(func() -> void:
		visible = false
	)


## 立即隐藏（无动画，用于重置）
func force_hide() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()
	_visible_anim = false
	visible = false
	scale = Vector3.ONE
	_alpha = 1.0

# ---------------------------------------------------------------------------
# 每帧更新：扭曲波动 + 呼吸透明
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible or not _visible_anim:
		return

	_time += delta

	# --- 整体呼吸透明（主节点 modulate.a 不干扰动画过渡，在稳定阶段才激活）---
	# 动画结束后 scale≈1.0 才激活呼吸
	if scale.x > 0.9:
		var breath: float = 1.0 - BREATH_AMP + BREATH_AMP * sin(_time * BREATH_FREQ * TAU + _wave_phase)
		_alpha = breath

	# --- 扭曲：主文字 X 轴摆动 ---
	var wave_x: float = WAVE_AMP * sin(_time * WAVE_FREQ * TAU + _wave_phase)

	# 主文字：居中 + 轻微摆动
	if _label_main:
		_label_main.position = Vector3(wave_x, _base_y, 0.0)

	# 重影1：轻微偏右下 + 半相位延迟
	if _label_ghost1:
		var g1_x: float = WAVE_AMP * 1.4 * sin(_time * WAVE_FREQ * TAU + _wave_phase + 0.6)
		_label_ghost1.position = Vector3(
			g1_x + 0.008,        # 偏右
			_base_y - 0.006,     # 偏下（像素级）
			0.001                # 正Z：比主文字更远离相机（在主文字后方）
		)

	# 重影2：轻微偏左上 + 更大相位差
	if _label_ghost2:
		var g2_x: float = WAVE_AMP * 1.1 * sin(_time * WAVE_FREQ * TAU + _wave_phase + 1.3)
		_label_ghost2.position = Vector3(
			g2_x - 0.007,        # 偏左
			_base_y + 0.007,     # 偏上
			0.002                # 正Z：比ghost1更远离相机（最底层）
		)
