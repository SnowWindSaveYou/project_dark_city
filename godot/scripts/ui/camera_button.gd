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
# 状态
# ---------------------------------------------------------------------------
var _in_camera_mode := false
var _viewfinder_alpha := 0.0
var _scan_line_y := 0.0   # 扫描线 Y 位置
var _rec_blink_timer := 0.0

const BUTTON_SIZE := 44.0
const BUTTON_MARGIN := 16.0
const SCAN_SPEED := 60.0  # px/s

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

func enter_camera_mode() -> void:
	if _in_camera_mode:
		return
	if GameData.get_resource("film") <= 0:
		# 胶卷不足 - TODO: 抖动动画
		return
	_in_camera_mode = true
	_scan_line_y = 0.0

	var tw := create_tween()
	tw.tween_property(self, "_viewfinder_alpha", 1.0, 0.3)
	camera_mode_entered.emit()

func exit_camera_mode() -> void:
	if not _in_camera_mode:
		return
	_in_camera_mode = false
	var tw := create_tween()
	tw.tween_property(self, "_viewfinder_alpha", 0.0, 0.2)
	camera_mode_exited.emit()

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _in_camera_mode:
		var vp := get_viewport_rect().size
		_scan_line_y += SCAN_SPEED * delta
		if _scan_line_y > vp.y:
			_scan_line_y = 0.0
		_rec_blink_timer += delta
	queue_redraw()

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return

		var btn_rect := _get_button_rect()
		if btn_rect.has_point(mb.position):
			if _in_camera_mode:
				exit_camera_mode()
			else:
				enter_camera_mode()
			accept_event()

# ---------------------------------------------------------------------------
# 布局
# ---------------------------------------------------------------------------

func _get_button_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var x := vp.x - BUTTON_SIZE - BUTTON_MARGIN
	var y := vp.y - BUTTON_SIZE - BUTTON_MARGIN - 60  # 手账本上方
	return Rect2(x, y, BUTTON_SIZE, BUTTON_SIZE)

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _draw() -> void:
	var vp := get_viewport_rect().size
	var t = Theme
	var font := ThemeDB.fallback_font

	# --- 取景框覆盖 ---
	if _viewfinder_alpha > 0.01:
		_draw_viewfinder(vp, t, font)

	# --- 相机按钮 ---
	var btn := _get_button_rect()
	var btn_color := t.camera_viewfinder if _in_camera_mode else t.accent
	btn_color.a = 0.9

	# 圆形按钮
	var cx := btn.position.x + btn.size.x / 2
	var cy := btn.position.y + btn.size.y / 2
	draw_circle(Vector2(cx, cy), BUTTON_SIZE / 2, btn_color)

	# 相机图标
	draw_string(font, Vector2(cx, cy + 6), "📷",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color.WHITE)

	# 胶卷计数 (始终显示)
	var film := GameData.get_resource("film")
	var film_text := "×" + str(film)
	var film_color := Color.WHITE if film > 0 else t.danger
	draw_string(font, Vector2(cx, cy + BUTTON_SIZE / 2 + 14), film_text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 11, film_color)

func _draw_viewfinder(vp: Vector2, t, font: Font) -> void:
	var alpha := _viewfinder_alpha

	# 暗角
	var vignette := Color(0, 0, 0, alpha * 0.3)
	var corner_size := vp.x * 0.15
	# 四角暗角 (简化为矩形渐变效果)
	draw_rect(Rect2(0, 0, corner_size, corner_size), vignette)
	draw_rect(Rect2(vp.x - corner_size, 0, corner_size, corner_size), vignette)
	draw_rect(Rect2(0, vp.y - corner_size, corner_size, corner_size), vignette)
	draw_rect(Rect2(vp.x - corner_size, vp.y - corner_size, corner_size, corner_size), vignette)

	# 四角 L 形标记
	var bracket_len := 30.0
	var bracket_w := 2.5
	var bracket_margin := 24.0
	var bracket_color := Color(t.camera_viewfinder.r, t.camera_viewfinder.g, t.camera_viewfinder.b, alpha * 0.8)

	# 左上
	draw_rect(Rect2(bracket_margin, bracket_margin, bracket_len, bracket_w), bracket_color)
	draw_rect(Rect2(bracket_margin, bracket_margin, bracket_w, bracket_len), bracket_color)
	# 右上
	draw_rect(Rect2(vp.x - bracket_margin - bracket_len, bracket_margin, bracket_len, bracket_w), bracket_color)
	draw_rect(Rect2(vp.x - bracket_margin - bracket_w, bracket_margin, bracket_w, bracket_len), bracket_color)
	# 左下
	draw_rect(Rect2(bracket_margin, vp.y - bracket_margin - bracket_w, bracket_len, bracket_w), bracket_color)
	draw_rect(Rect2(bracket_margin, vp.y - bracket_margin - bracket_len, bracket_w, bracket_len), bracket_color)
	# 右下
	draw_rect(Rect2(vp.x - bracket_margin - bracket_len, vp.y - bracket_margin - bracket_w, bracket_len, bracket_w), bracket_color)
	draw_rect(Rect2(vp.x - bracket_margin - bracket_w, vp.y - bracket_margin - bracket_len, bracket_w, bracket_len), bracket_color)

	# 扫描线
	var scan_color := Color(t.camera_viewfinder.r, t.camera_viewfinder.g, t.camera_viewfinder.b, alpha * 0.3)
	draw_line(Vector2(0, _scan_line_y), Vector2(vp.x, _scan_line_y), scan_color, 1.5)

	# REC 指示灯
	var rec_visible := fmod(_rec_blink_timer, 1.0) < 0.6
	if rec_visible:
		var rec_color := Color(t.camera_rec.r, t.camera_rec.g, t.camera_rec.b, alpha)
		draw_circle(Vector2(vp.x - 50, 40), 5, rec_color)
		draw_string(font, Vector2(vp.x - 38, 45), "REC",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, rec_color)
