## CameraButton - 相机模式按钮 + 取景框
## 对应原版 CameraButton.lua
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal camera_mode_entered
signal camera_mode_exited
signal photograph_requested  # 请求拍摄 (未翻卡)
signal exorcise_requested    # 请求驱魔 (已翻怪物卡)

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const BUTTON_SIZE: float = 44.0
const BTN_MARGIN_R: float = 20.0
const BTN_MARGIN_B: float = 90.0  # 避开底部 HandPanel
const BRACKET_LEN: float = 28.0
const BRACKET_MARGIN: float = 20.0
const SCAN_SPEED: float = 60.0  # px/s

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _visible_flag: bool = false
var _in_camera_mode: bool = false

# 按钮动画
var _btn_scale: float = 0.0
var _btn_alpha: float = 0.0
var _icon_rot: float = 0.0  # 图标旋转角(度)
var _hover_t: float = 0.0
var _shake_x: float = 0.0

# 取景器
var _viewfinder_alpha: float = 0.0
var _scan_line_y: float = 0.0
var _rec_blink_timer: float = 0.0

# 内部计时
var _time: float = 0.0

# 缓存
var _btn_center: Vector2 = Vector2.ZERO
var _film_texture: Texture2D = null
var _film_tex_loaded: bool = false

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
func is_camera_mode() -> bool:
	return _in_camera_mode

func show_button() -> void:
	if _visible_flag:
		return
	_visible_flag = true
	visible = true
	_btn_scale = 0.3
	_btn_alpha = 0.0
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_btn_scale", 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_btn_alpha", 1.0, 0.3)

func hide_button() -> void:
	if not _visible_flag:
		return
	if _in_camera_mode:
		_in_camera_mode = false
		_viewfinder_alpha = 0.0
		_icon_rot = 0.0
	_visible_flag = false
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_btn_scale", 0.3, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "_btn_alpha", 0.0, 0.2)
	tw.chain().tween_callback(func(): visible = false)

func enter_camera_mode() -> void:
	if _in_camera_mode:
		return
	_in_camera_mode = true
	_scan_line_y = 0.0
	_rec_blink_timer = 0.0

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_icon_rot", 15.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_viewfinder_alpha", 1.0, 0.3)
	camera_mode_entered.emit()

func exit_camera_mode() -> void:
	if not _in_camera_mode:
		return
	_in_camera_mode = false

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_icon_rot", 0.0, 0.2)
	tw.tween_property(self, "_viewfinder_alpha", 0.0, 0.25)
	camera_mode_exited.emit()

func shake_no_film() -> void:
	var tw: Tween = create_tween()
	tw.tween_method(func(p: float):
		var decay: float = (1.0 - p) * (1.0 - p)
		_shake_x = sin(p * PI * 7.0) * 6.0 * decay
	, 0.0, 1.0, 0.4)
	tw.tween_callback(func(): _shake_x = 0.0)

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _visible_flag and _viewfinder_alpha <= 0.01:
		return

	_time += delta

	if _in_camera_mode:
		var vp: Vector2 = get_viewport_rect().size
		var area_h: float = vp.y - 80.0 - 14.0  # ResourceBar下方到底部
		_scan_line_y += SCAN_SPEED * delta
		if _scan_line_y > area_h:
			_scan_line_y = 0.0
		_rec_blink_timer += delta

	queue_redraw()

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if not _visible_flag:
		return

	if event is InputEventMouseMotion:
		var inside: bool = _hit_test_button(event.position)
		var target: float = 1.0 if inside else 0.0
		# 直接设置，平滑在 _process 中处理也可
		_hover_t = lerpf(_hover_t, target, 0.3)
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return

		if _hit_test_button(mb.position):
			if _in_camera_mode:
				exit_camera_mode()
			else:
				enter_camera_mode()
			accept_event()

func _hit_test_button(pos: Vector2) -> bool:
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x - BTN_MARGIN_R - BUTTON_SIZE / 2.0
	var cy: float = vp.y - BTN_MARGIN_B - BUTTON_SIZE / 2.0
	var dx: float = pos.x - cx
	var dy: float = pos.y - cy
	var r: float = BUTTON_SIZE / 2.0 + 4.0
	return (dx * dx + dy * dy) <= r * r

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var t = GameTheme
	var font: Font = ThemeDB.fallback_font

	# --- 取景框覆盖 ---
	if _viewfinder_alpha > 0.01:
		_draw_viewfinder(vp, t, font)

	# --- 相机按钮 ---
	if not _visible_flag or _btn_alpha <= 0.01:
		return

	var cx: float = vp.x - BTN_MARGIN_R - BUTTON_SIZE / 2.0 + _shake_x
	var cy: float = vp.y - BTN_MARGIN_B - BUTTON_SIZE / 2.0
	var r: float = BUTTON_SIZE / 2.0

	# 按钮变换
	var hover_scale: float = 1.0 + _hover_t * 0.1
	var total_scale: float = _btn_scale * hover_scale
	var xf: Transform2D = Transform2D()
	xf = xf.translated(-Vector2(cx, cy))
	xf = xf.scaled(Vector2(total_scale, total_scale))
	xf = xf.translated(Vector2(cx, cy))
	draw_set_transform_matrix(xf)
	modulate.a = _btn_alpha

	# 阴影
	draw_circle(Vector2(cx + 1, cy + 2), r * 1.3, Color(0, 0, 0, 0.15))

	# 按钮背景
	var btn_color: Color = t.camera_btn_active if _in_camera_mode else t.camera_btn
	draw_circle(Vector2(cx, cy), r, btn_color)

	# 激活态脉冲光晕
	if _in_camera_mode:
		var glow_phase: float = 0.4 + 0.6 * absf(sin(_time * 2.5))
		var glow_r: float = r + 4.0 + glow_phase * 3.0
		var glow_color: Color = Color(btn_color.r, btn_color.g, btn_color.b, glow_phase * 0.2)
		draw_circle(Vector2(cx, cy), glow_r, glow_color)

	# Hover 高光
	if _hover_t > 0.01:
		draw_circle(Vector2(cx, cy), r, Color(1, 1, 1, _hover_t * 0.15))

	# 边框
	var border_alpha: float = 0.78 if _in_camera_mode else 0.59
	_draw_circle_outline(Vector2(cx, cy), r, Color(1, 1, 1, border_alpha + _hover_t * 0.2), 1.5)

	# 图标 (📷) - 带旋转
	var icon_xf: Transform2D = Transform2D()
	icon_xf = icon_xf.translated(-Vector2(cx, cy))
	icon_xf = icon_xf.rotated(deg_to_rad(_icon_rot))
	icon_xf = icon_xf.scaled(Vector2(total_scale, total_scale))
	icon_xf = icon_xf.translated(Vector2(cx, cy))
	draw_set_transform_matrix(icon_xf)
	draw_string(font, Vector2(cx, cy + 7), "📷",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color.WHITE)

	# 恢复变换到按钮级别
	draw_set_transform_matrix(xf)

	# === 胶卷计数 (按钮左侧) ===
	var film: int = GameData.get_resource("film")
	var film_alpha: bool = 0.86 if film <= 1 else 0.78

	# 胶卷数字
	var num_text: String = str(film)
	var num_x: float = cx - r - 8.0
	var num_color: Color
	if film <= 1:
		num_color = Color(0.86, 0.31, 0.31, film_alpha)
	else:
		num_color = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, film_alpha)
	draw_string(font, Vector2(num_x, cy + 5), num_text,
		HORIZONTAL_ALIGNMENT_RIGHT, -1, 13, num_color)

	# 胶卷图标 (纹理优先)
	var icon_x: float = num_x - 18.0
	_ensure_film_texture()
	if _film_texture:
		var tex_size: float = 16.0
		var tex_rect: Rect2 = Rect2(icon_x - tex_size / 2.0, cy - tex_size / 2.0, tex_size, tex_size)
		draw_texture_rect(_film_texture, tex_rect, false, Color(1, 1, 1, film_alpha))
	else:
		draw_string(font, Vector2(icon_x, cy + 5), "🎞️",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 13, num_color)

	# 重置
	draw_set_transform_matrix(Transform2D.IDENTITY)
	modulate.a = 1.0

func _ensure_film_texture() -> void:
	if _film_tex_loaded:
		return
	_film_tex_loaded = true
	_film_texture = ItemIcons.get_texture("film")

func _draw_viewfinder(vp: Vector2, t, font: Font) -> void:
	var alpha: float = _viewfinder_alpha

	# 取景器区域
	var area_top: float = 80.0
	var area_bottom: float = vp.y - 14.0

	# 四角暗角
	var vignette: Color = Color(t.camera_tint.r, t.camera_tint.g, t.camera_tint.b, alpha * 0.2)
	var corner_size: float = vp.x * 0.15
	draw_rect(Rect2(0, 0, corner_size, corner_size), vignette)
	draw_rect(Rect2(vp.x - corner_size, 0, corner_size, corner_size), vignette)
	draw_rect(Rect2(0, vp.y - corner_size, corner_size, corner_size), vignette)
	draw_rect(Rect2(vp.x - corner_size, vp.y - corner_size, corner_size, corner_size), vignette)

	# 四角 L 形标记
	var bm: float = BRACKET_MARGIN - 6.0
	var bl: float = BRACKET_LEN
	var bracket_color: Color = Color(t.camera_viewfinder.r, t.camera_viewfinder.g, t.camera_viewfinder.b, alpha * 0.7)
	var bw: float = 2.5

	var left: float = bm
	var right_edge: float = vp.x - bm
	var top: float = area_top + bm
	var bottom: float = area_bottom - bm

	# 左上
	draw_rect(Rect2(left, top, bl, bw), bracket_color)
	draw_rect(Rect2(left, top, bw, bl), bracket_color)
	# 右上
	draw_rect(Rect2(right_edge - bl, top, bl, bw), bracket_color)
	draw_rect(Rect2(right_edge - bw, top, bw, bl), bracket_color)
	# 左下
	draw_rect(Rect2(left, bottom - bw, bl, bw), bracket_color)
	draw_rect(Rect2(left, bottom - bl, bw, bl), bracket_color)
	# 右下
	draw_rect(Rect2(right_edge - bl, bottom - bw, bl, bw), bracket_color)
	draw_rect(Rect2(right_edge - bw, bottom - bl, bw, bl), bracket_color)

	# 扫描线
	var scan_abs_y: float = area_top + _scan_line_y
	if scan_abs_y <= area_bottom:
		var scan_color: Color = Color(t.camera_viewfinder.r, t.camera_viewfinder.g, t.camera_viewfinder.b, alpha * 0.2)
		draw_line(Vector2(0, scan_abs_y), Vector2(vp.x, scan_abs_y), scan_color, 1.5)

	# REC 指示灯
	var rec_visible: float = sin(_rec_blink_timer * 3.0) > -0.3
	if rec_visible:
		var rec_x: float = left + 8.0
		var rec_y: float = top + bl + 12.0
		var rec_color: Color = Color(t.camera_rec.r, t.camera_rec.g, t.camera_rec.b, alpha)
		draw_circle(Vector2(rec_x, rec_y), 4, rec_color)
		# 光晕
		draw_circle(Vector2(rec_x, rec_y), 7, Color(rec_color.r, rec_color.g, rec_color.b, alpha * 0.16))
		# "CAMERA MODE" 文字
		draw_string(font, Vector2(rec_x + 12, rec_y + 4), "CAMERA MODE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(1, 1, 1, alpha * 0.63))

# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------
func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	var segments: int = 32
	var prev: float = center + Vector2(radius, 0)
	for i in range(1, segments + 1):
		var angle: float = TAU * i / segments
		var next: float = center + Vector2(cos(angle) * radius, sin(angle) * radius)
		draw_line(prev, next, color, width)
		prev = next
