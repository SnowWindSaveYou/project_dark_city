## CameraButton - 相机模式按钮 + 取景框
## 视觉设计：📷 emoji 图标为主体，无实心圆背景
##   idle:    极淡暖色光晕（barely visible）
##   hover:   光晕加强 + 图标微放大
##   active:  橘红脉冲光晕 + 图标 15° 倾斜
##   胶卷计数：图标正下方小 pill 标签
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal camera_mode_entered
signal camera_mode_exited
signal photograph_requested
signal exorcise_requested

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const BUTTON_SIZE: float  = 132.0   # 点击判定半径的来源（不变，保持手感）
const BTN_MARGIN_B: float =  56.0   # 底部边距
const ICON_SIZE: float    =  76.0   # 保留旧名，现在仅供外部引用；图标尺寸由 _draw_camera_icon 内部控制
const BRACKET_LEN: float  =  84.0
const BRACKET_MARGIN: float = 60.0
const SCAN_SPEED: float   = 180.0   # px/s

# pill
const PILL_W: float  = 80.0
const PILL_H: float  = 30.0
const PILL_GAP: float = 4.0    # 与图标底部的间距
const PILL_FONT_SIZE: int = 20  # 数字字号

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _visible_flag: bool = false
var _in_camera_mode: bool = false

var _btn_scale: float = 0.0
var _btn_alpha: float = 0.0
var _icon_rot: float  = 0.0
var _hover_t: float   = 0.0
var _shake_x: float   = 0.0

var _viewfinder_alpha: float = 0.0
var _scan_line_y: float = 0.0
var _rec_blink_timer: float = 0.0

var _time: float = 0.0

var _film_texture: Texture2D = null
var _film_tex_loaded: bool = false

# 暗角
var _vignette_rect: ColorRect = null
var _vignette_material: ShaderMaterial = null

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_setup_vignette()

func _setup_vignette() -> void:
	var shader: Shader = load("res://shaders/vignette.gdshader")
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = shader

	_vignette_rect = ColorRect.new()
	_vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.show_behind_parent = true
	_vignette_rect.material = _vignette_material
	_vignette_rect.visible = false
	add_child(_vignette_rect)

func _has_point(point: Vector2) -> bool:
	if not _visible_flag:
		return false
	return _hit_test_button(point)

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
	var tw: Tween = create_tween().set_parallel(true)
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
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(self, "_btn_scale", 0.3, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "_btn_alpha", 0.0, 0.2)
	tw.chain().tween_callback(func(): visible = false)

func enter_camera_mode() -> void:
	if _in_camera_mode:
		return
	_in_camera_mode = true
	_scan_line_y = 0.0
	_rec_blink_timer = 0.0
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(self, "_icon_rot", 15.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_viewfinder_alpha", 1.0, 0.3)
	camera_mode_entered.emit()

func exit_camera_mode() -> void:
	if not _in_camera_mode:
		return
	_in_camera_mode = false
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(self, "_icon_rot", 0.0, 0.2)
	tw.tween_property(self, "_viewfinder_alpha", 0.0, 0.25)
	camera_mode_exited.emit()

func shake_no_film() -> void:
	var tw: Tween = create_tween()
	tw.tween_method(func(p: float):
		var decay: float = (1.0 - p) * (1.0 - p)
		_shake_x = sin(p * PI * 7.0) * 18.0 * decay
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
		var area_h: float = vp.y - 240.0 - 42.0
		_scan_line_y += SCAN_SPEED * delta
		if _scan_line_y > area_h:
			_scan_line_y = 0.0
		_rec_blink_timer += delta

	# 更新暗角
	if _vignette_rect != null:
		var show: bool = _viewfinder_alpha > 0.01
		_vignette_rect.visible = show
		if show:
			var t = GameTheme
			_vignette_material.set_shader_parameter("tint_color",
				Color(t.camera_tint.r, t.camera_tint.g, t.camera_tint.b, 0.12))
			_vignette_material.set_shader_parameter("overall_alpha", _viewfinder_alpha)

	# modulate 在 _process 里统一设置，避免在 _draw() 内修改节点属性引发死循环
	modulate.a = _btn_alpha
	queue_redraw()

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if not _visible_flag:
		return

	if event is InputEventMouseMotion:
		var inside: bool = _hit_test_button(event.position)
		_hover_t = lerpf(_hover_t, 1.0 if inside else 0.0, 0.3)
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
	var cx: float = vp.x / 2.0
	var cy: float = vp.y - BTN_MARGIN_B - BUTTON_SIZE / 2.0
	var dx: float = pos.x - cx
	var dy: float = pos.y - cy
	var r: float = BUTTON_SIZE / 2.0 + 12.0
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

	var cx: float = vp.x / 2.0 + _shake_x
	var cy: float = vp.y - BTN_MARGIN_B - BUTTON_SIZE / 2.0

	var hover_scale: float = 1.0 + _hover_t * 0.08
	var total_scale: float = _btn_scale * hover_scale

	# ── 1. 柔光晕（draw_arc 环形，从 emoji 外缘向外，绝对不会覆盖图标中心）
	var glow_color: Color = t.camera_btn_active if _in_camera_mode else t.camera_btn
	var glow_intensity: float
	if _in_camera_mode:
		var pulse: float = 0.5 + 0.5 * absf(sin(_time * 2.5))
		glow_intensity = 0.55 + pulse * 0.25
	else:
		glow_intensity = 0.20 + _hover_t * 0.30
	# 图标机身宽 100px，半径 50；glow 从外缘 52 开始向外扩散
	_draw_soft_glow(Vector2(cx, cy), 52.0 * total_scale, 44.0, glow_color, glow_intensity)

	# ── 2. 相机图标（手绘，不依赖字体 emoji）
	var icon_color: Color
	if _in_camera_mode:
		icon_color = Color(t.camera_btn_active.r, t.camera_btn_active.g, t.camera_btn_active.b, 1.0)
	else:
		icon_color = Color(0.14, 0.18, 0.24, 1.0)   # text_primary #232D3C
	var lens_ring_color: Color = Color(
		lerpf(icon_color.r, 1.0, 0.35),
		lerpf(icon_color.g, 1.0, 0.35),
		lerpf(icon_color.b, 1.0, 0.35), 1.0)
	draw_set_transform(Vector2(cx, cy), deg_to_rad(_icon_rot), Vector2(total_scale, total_scale))
	_draw_camera_icon(icon_color, lens_ring_color)

	# ── 3. 胶卷计数 pill（重置变换，用绝对坐标绘制）
	draw_set_transform(Vector2.ZERO)
	var film: int = GameData.get_resource("film")
	_draw_film_pill(cx, cy, film, t, font)

# ---------------------------------------------------------------------------
# 胶卷 pill
# ---------------------------------------------------------------------------

## 图标正下方的小圆角标签
## cy 是图标中心 y；emoji 渲染后底部约在 cy + ICON_SIZE*0.72
func _draw_film_pill(cx: float, cy: float, film: int, t: Object, font: Font) -> void:
	# 图标机身底部：local y = body_y(4) + bh/2(34) = 38，screen = cy + 38
	var icon_bottom: float = cy + 38.0
	var pill_top: float = icon_bottom + PILL_GAP
	var pill_rect: Rect2 = Rect2(cx - PILL_W / 2.0, pill_top, PILL_W, PILL_H)

	var film_alpha: float = _btn_alpha * 0.90

	# pill 背景色：胶卷不足时偏粉警示，正常时白色半透明
	var pill_bg: Color
	var text_col: Color
	if film <= 1:
		pill_bg  = Color(1.0, 0.90, 0.90, 0.82 * film_alpha)
		text_col = Color(0.78, 0.18, 0.18, film_alpha)
	else:
		pill_bg  = Color(1.0, 1.0, 1.0, 0.76 * film_alpha)
		text_col = Color(t.text_secondary.r, t.text_secondary.g, t.text_secondary.b, film_alpha)

	# pill 背景（圆角矩形 + 极细阴影）
	_draw_pill_shadow(pill_rect, film_alpha * 0.12)
	_draw_rounded_pill(pill_rect, PILL_H / 2.0, pill_bg)

	# pill 内容：胶卷图标 + 数字
	_ensure_film_texture()
	if _film_texture:
		# 贴图在左，数字在右
		var tex_size: float = 22.0
		var tex_x: float = cx - 26.0
		var tex_y: float = pill_top + (PILL_H - tex_size) / 2.0
		draw_texture_rect(_film_texture,
			Rect2(tex_x, tex_y, tex_size, tex_size), false,
			Color(text_col.r, text_col.g, text_col.b, film_alpha))
		draw_string(font,
			Vector2(tex_x + tex_size + 4.0, pill_top + PILL_H * 0.74),
			str(film), HORIZONTAL_ALIGNMENT_LEFT, -1, PILL_FONT_SIZE, text_col)
	else:
		# fallback: 数字居中（字体不含胶卷 emoji，只显示数字）
		draw_string(font,
			Vector2(cx, pill_top + PILL_H * 0.74),
			str(film), HORIZONTAL_ALIGNMENT_CENTER, PILL_W, PILL_FONT_SIZE, text_col)

# ---------------------------------------------------------------------------
# 取景框
# ---------------------------------------------------------------------------
func _draw_viewfinder(vp: Vector2, t: Object, font: Font) -> void:
	var alpha: float = _viewfinder_alpha
	var area_top: float = 240.0
	var area_bottom: float = vp.y - 42.0

	var bm: float = BRACKET_MARGIN - 18.0
	var bl: float = BRACKET_LEN
	var bracket_color: Color = Color(t.camera_viewfinder.r, t.camera_viewfinder.g,
		t.camera_viewfinder.b, alpha * 0.7)
	var bw: float = 7.5
	var left: float = bm
	var right_edge: float = vp.x - bm
	var top: float = area_top + bm
	var bottom: float = area_bottom - bm

	# 四角 L 形标记
	draw_rect(Rect2(left,             top,          bl, bw), bracket_color)
	draw_rect(Rect2(left,             top,          bw, bl), bracket_color)
	draw_rect(Rect2(right_edge - bl,  top,          bl, bw), bracket_color)
	draw_rect(Rect2(right_edge - bw,  top,          bw, bl), bracket_color)
	draw_rect(Rect2(left,             bottom - bw,  bl, bw), bracket_color)
	draw_rect(Rect2(left,             bottom - bl,  bw, bl), bracket_color)
	draw_rect(Rect2(right_edge - bl,  bottom - bw,  bl, bw), bracket_color)
	draw_rect(Rect2(right_edge - bw,  bottom - bl,  bw, bl), bracket_color)

	# 扫描线
	var scan_abs_y: float = area_top + _scan_line_y
	if scan_abs_y <= area_bottom:
		var scan_color: Color = Color(t.camera_viewfinder.r, t.camera_viewfinder.g,
			t.camera_viewfinder.b, alpha * 0.2)
		draw_line(Vector2(0, scan_abs_y), Vector2(vp.x, scan_abs_y), scan_color, 4.5)

	# REC 指示灯
	if sin(_rec_blink_timer * 3.0) > -0.3:
		var rec_x: float = left + 24.0
		var rec_y: float = top + bl + 36.0
		var rec_color: Color = Color(t.camera_rec.r, t.camera_rec.g, t.camera_rec.b, alpha)
		draw_circle(Vector2(rec_x, rec_y), 12.0, rec_color)
		draw_circle(Vector2(rec_x, rec_y), 21.0,
			Color(rec_color.r, rec_color.g, rec_color.b, alpha * 0.16))
		draw_string(font, Vector2(rec_x + 36.0, rec_y + 12.0), "CAMERA MODE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 33, Color(1, 1, 1, alpha * 0.63))

# ---------------------------------------------------------------------------
# 辅助：加载胶卷纹理
# ---------------------------------------------------------------------------
func _ensure_film_texture() -> void:
	if _film_tex_loaded:
		return
	_film_tex_loaded = true
	_film_texture = ItemIcons.get_texture("film")

# ---------------------------------------------------------------------------
# 辅助：绘制
# ---------------------------------------------------------------------------

## 向外辐射的柔和光晕（draw_arc 环形，从 emoji 外缘向外扩散，绝不覆盖中心）
## inner_r: 起始半径（emoji 外缘）
## expand:  向外扩散的总像素数
## intensity: 最内环的最大 alpha
func _draw_soft_glow(center: Vector2, inner_r: float, expand: float,
		color: Color, intensity: float) -> void:
	if intensity < 0.01:
		return
	var steps: int = 7
	for i in range(steps):
		var ratio: float = float(i) / float(steps - 1)
		var r: float = inner_r + 2.0 + ratio * expand
		var a: float = intensity * pow(1.0 - ratio, 1.6)
		if a < 0.01:
			continue
		var thickness: float = lerpf(5.0, 1.5, ratio)
		draw_arc(center, r, 0.0, TAU, 64,
			Color(color.r, color.g, color.b, a), thickness)


## 手绘相机图标，坐标以 (0,0) 为中心（配合 draw_set_transform 使用）
## body_color: 机身/镜头内芯颜色；lens_ring: 镜头外环颜色
func _draw_camera_icon(body_color: Color, lens_ring: Color) -> void:
	# 所有尺寸为原始设计值 × 2，坐标以 (0,0) = 图标中心
	# ---- 机身（圆角矩形）----
	var bw: float = 100.0
	var bh: float =  68.0
	var br: float =  12.0
	var body_y: float = 4.0   # 中心稍偏下，给上方凸起留空间
	var body_sb := StyleBoxFlat.new()
	body_sb.bg_color = body_color
	body_sb.corner_radius_top_left     = int(br)
	body_sb.corner_radius_top_right    = int(br)
	body_sb.corner_radius_bottom_left  = int(br)
	body_sb.corner_radius_bottom_right = int(br)
	body_sb.shadow_size = 0
	draw_style_box(body_sb, Rect2(-bw / 2.0, body_y - bh / 2.0, bw, bh))

	# ---- 取景器凸起（机身左上方）----
	var bump_w: float = 32.0
	var bump_h: float = 18.0
	var bump_sb := StyleBoxFlat.new()
	bump_sb.bg_color = body_color
	bump_sb.corner_radius_top_left     = 8
	bump_sb.corner_radius_top_right    = 8
	bump_sb.corner_radius_bottom_left  = 0
	bump_sb.corner_radius_bottom_right = 0
	bump_sb.shadow_size = 0
	draw_style_box(bump_sb, Rect2(-bw / 4.0 - bump_w / 2.0,
		body_y - bh / 2.0 - bump_h, bump_w, bump_h))

	# ---- 闪光灯小点（机身右上角）----
	draw_circle(Vector2(bw / 4.0, body_y - bh / 2.0 + 12.0), 8.0, lens_ring)

	# ---- 镜头外环（亮色）----
	var lens_cy: float = body_y + 2.0
	draw_circle(Vector2(0.0, lens_cy), 27.0, lens_ring)

	# ---- 镜头内芯（深色）----
	draw_circle(Vector2(0.0, lens_cy), 17.0, body_color)

	# ---- 镜头高光（小白点）----
	draw_circle(Vector2(-7.0, lens_cy - 7.0), 5.0,
		Color(1.0, 1.0, 1.0, body_color.a * 0.55))


## 圆角 pill 背景
func _draw_rounded_pill(rect: Rect2, radius: float, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left     = int(radius)
	sb.corner_radius_top_right    = int(radius)
	sb.corner_radius_bottom_left  = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	sb.set_content_margin_all(0)
	draw_style_box(sb, rect)


## pill 专用小阴影（向下 2px，spread 4px）
func _draw_pill_shadow(rect: Rect2, alpha: float) -> void:
	if alpha < 0.01:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.corner_radius_top_left     = int(PILL_H / 2.0)
	sb.corner_radius_top_right    = int(PILL_H / 2.0)
	sb.corner_radius_bottom_left  = int(PILL_H / 2.0)
	sb.corner_radius_bottom_right = int(PILL_H / 2.0)
	sb.shadow_color  = Color(0.1, 0.18, 0.28, alpha)
	sb.shadow_size   = 4
	sb.shadow_offset = Vector2(0.0, 2.0)
	draw_style_box(sb, rect)
