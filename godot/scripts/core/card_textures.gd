## CardTextures - 卡牌纹理生成与缓存
## 负责:
##   1. PNG 插画纹理加载 (复用 CardImageMap 接口)
##   2. 程序化 overlay 纹理生成 (拍立得边框 + 色条, 透明底)
##   3. 程序化背面纹理 (背景色 + 对角线 + 白边框)
##   4. 暗面纹理 (暗色调背景 + 类型色条)
## 全部结果做 Dictionary 缓存，构建后重用
class_name CardTextures
extends RefCounted

# ---------------------------------------------------------------------------
# 纹理尺寸常量 (与 Lua CardTextures.lua 对齐)
# ---------------------------------------------------------------------------
const TEX_W: int = 256
const TEX_H: int = 360

# ---------------------------------------------------------------------------
# 缓存
# ---------------------------------------------------------------------------
var _overlay_cache: Dictionary = {}   # accent_hex → ImageTexture
var _back_tex: ImageTexture = null
var _back_dark_tex: ImageTexture = null
var _dark_tex_cache: Dictionary = {}  # dark_type → ImageTexture

# ---------------------------------------------------------------------------
# 公共接口：PNG 纹理 (直接转发 CardImageMap)
# ---------------------------------------------------------------------------

## 获取地点卡背面 PNG 插画 (未翻开状态的正面，即地点图)
static func get_location_texture(loc_key: String) -> Texture2D:
	return CardImageMap.get_location_texture(loc_key)

## 获取事件卡正面 PNG 插画 (翻开后显示)
static func get_event_texture(loc_key: String, event_type: String) -> Texture2D:
	return CardImageMap.get_event_texture(loc_key, event_type)

# ---------------------------------------------------------------------------
# 公共接口：overlay 纹理 (程序化，透明底叠加在 PNG 上)
# ---------------------------------------------------------------------------

## 获取或生成一张 overlay 纹理
## accent: 类型强调色 (用于顶部色条)
func get_overlay(accent: Color) -> ImageTexture:
	var key: String = "#%02x%02x%02x" % [
		int(accent.r * 255), int(accent.g * 255), int(accent.b * 255)
	]
	if _overlay_cache.has(key):
		return _overlay_cache[key]
	var tex: ImageTexture = _render_overlay_image(accent)
	_overlay_cache[key] = tex
	return tex

## 获取空白 overlay (无 accent 色，仅边框；用于未翻开状态叠在地点图上)
func get_plain_overlay() -> ImageTexture:
	return get_overlay(Color(0.85, 0.80, 0.72, 1.0))  # 米白色条

# ---------------------------------------------------------------------------
# 公共接口：背面纹理
# ---------------------------------------------------------------------------

## 获取或生成表面世界背面纹理
func get_back_texture() -> ImageTexture:
	if _back_tex != null:
		return _back_tex
	_back_tex = _build_back_texture(GameTheme.card_back, true)
	return _back_tex

## 获取或生成暗面世界背面纹理
func get_back_dark_texture() -> ImageTexture:
	if _back_dark_tex != null:
		return _back_dark_tex
	_back_dark_tex = _build_back_texture(GameTheme.card_back_dark, false)
	return _back_dark_tex

# ---------------------------------------------------------------------------
# 公共接口：暗面类型纹理
# ---------------------------------------------------------------------------

## 获取暗面卡正面纹理 (深色背景 + 类型色条)
func get_dark_face_texture(dark_type: String) -> ImageTexture:
	if _dark_tex_cache.has(dark_type):
		return _dark_tex_cache[dark_type]
	var dark_color: Color = GameTheme.dark_card_type_color(dark_type)
	var tex: ImageTexture = _build_dark_face_texture(dark_color)
	_dark_tex_cache[dark_type] = tex
	return tex

# ---------------------------------------------------------------------------
# 内部：overlay 纹理生成
# ---------------------------------------------------------------------------

func _render_overlay_image(accent: Color) -> ImageTexture:
	var img: Image = Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	# Image.create 初始全透明 (RGBA 全零)

	const BORDER: int = 6

	# 外边框 (白色半透明, 4条矩形带)
	var frame_col: Color = Color(0.96, 0.93, 0.88, 0.88)
	_fill_border(img, BORDER, frame_col)

	# 内边框 (装饰细线)
	_fill_border_inset(img, BORDER + 3, 2, Color(0.96, 0.93, 0.88, 0.38))

	# 顶部类型色条 (accent 半透明)
	var accent_a: Color = Color(accent.r, accent.g, accent.b, 0.72)
	img.fill_rect(Rect2i(BORDER, BORDER, TEX_W - BORDER * 2, 18), accent_a)

	# 底部标签色条 (拍立得白底 - 与边框同色，形成宽白区供文字叠加)
	img.fill_rect(Rect2i(BORDER, TEX_H - BORDER - 52, TEX_W - BORDER * 2, 52),
		Color(0.96, 0.93, 0.88, 0.95))

	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------------------
# 内部：背面纹理生成
# ---------------------------------------------------------------------------

func _build_back_texture(bg_color: Color, light_lines: bool) -> ImageTexture:
	var img: Image = Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	img.fill(bg_color)

	# 稀疏对角线 (~22K 次 set_pixel, 避免 92K 全图遍历)
	var line_col: Color
	if light_lines:
		line_col = Color(1.0, 1.0, 1.0, 0.10)
	else:
		line_col = Color(0.0, 0.0, 0.0, 0.12)

	var step: int = 20
	for offset in range(-TEX_H, TEX_W, step):
		for py in range(TEX_H):
			# 正对角线 (左上 → 右下)
			for lw in range(2):
				var px: int = offset + py + lw
				if px >= 0 and px < TEX_W:
					img.set_pixel(px, py, line_col)

	# 白色外边框 (明显白边)
	var border_col: Color = Color(1.0, 1.0, 1.0, 0.88) if light_lines else Color(1.0, 1.0, 1.0, 0.22)
	_fill_border(img, 6, border_col)
	_fill_border_inset(img, 9, 2, Color(1.0, 1.0, 1.0, 0.30) if light_lines else Color(1.0, 1.0, 1.0, 0.10))

	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------------------
# 内部：暗面正面纹理生成
# ---------------------------------------------------------------------------

func _build_dark_face_texture(type_color: Color) -> ImageTexture:
	var img: Image = Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)

	# 深色背景 (比类型色更深)
	var bg: Color = type_color.darkened(0.55)
	bg.a = 1.0
	img.fill(bg)

	# 顶部类型色条
	img.fill_rect(Rect2i(6, 6, TEX_W - 12, 20), Color(type_color, 0.80))

	# 底部标签条
	img.fill_rect(Rect2i(6, TEX_H - 58, TEX_W - 12, 52), Color(0.06, 0.05, 0.04, 0.80))

	# 边框
	_fill_border(img, 6, Color(1.0, 1.0, 1.0, 0.20))

	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------------------
# 内部：Image 工具函数
# ---------------------------------------------------------------------------

## 填充外边框 (4条矩形带)
func _fill_border(img: Image, thickness: int, col: Color) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	# 上
	img.fill_rect(Rect2i(0, 0, w, thickness), col)
	# 下
	img.fill_rect(Rect2i(0, h - thickness, w, thickness), col)
	# 左
	img.fill_rect(Rect2i(0, 0, thickness, h), col)
	# 右
	img.fill_rect(Rect2i(w - thickness, 0, thickness, h), col)

## 填充内嵌边框 (offset 像素向内, 宽度 thickness)
func _fill_border_inset(img: Image, offset: int, thickness: int, col: Color) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var inner_w: int = w - offset * 2
	var inner_h: int = h - offset * 2
	if inner_w <= 0 or inner_h <= 0:
		return
	# 上
	img.fill_rect(Rect2i(offset, offset, inner_w, thickness), col)
	# 下
	img.fill_rect(Rect2i(offset, h - offset - thickness, inner_w, thickness), col)
	# 左
	img.fill_rect(Rect2i(offset, offset, thickness, inner_h), col)
	# 右
	img.fill_rect(Rect2i(w - offset - thickness, offset, thickness, inner_h), col)
