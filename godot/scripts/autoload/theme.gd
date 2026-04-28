## Theme - 全局配色与字体常量 (Autoload)
## 对应原版 Theme.lua (bright 主题)
extends Node

# ---------------------------------------------------------------------------
# ThemeColor 辅助
# ---------------------------------------------------------------------------

## 255-based RGBA → Godot Color
static func c(r: int, g: int, b: int, a: int = 255) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0)

## Hex string → Godot Color
static func h(hex_str: String, a: int = 255) -> Color:
	var color: Color = Color.html(hex_str)
	color.a = a / 255.0
	return color

## 颜色变暗
static func darken(color: Color, factor: float) -> Color:
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a)

## 颜色变亮
static func lighten(color: Color, factor: float) -> Color:
	return Color(
		minf(1.0, color.r + (1.0 - color.r) * factor),
		minf(1.0, color.g + (1.0 - color.g) * factor),
		minf(1.0, color.b + (1.0 - color.b) * factor),
		color.a
	)

# ---------------------------------------------------------------------------
# 背景渐变
# ---------------------------------------------------------------------------
var bg_top: Color = h("#87C3EB")
var bg_bottom: Color = h("#C8E1F5")

# ---------------------------------------------------------------------------
# 卡牌色
# ---------------------------------------------------------------------------
var card_face: Color = h("#F5F0E8")
var card_location_bg: Color = h("#E8EDF5")
var card_back: Color = h("#4BA3E3")
var card_back_alt: Color = h("#3D8BC7")
var card_border: Color = h("#2A5C78")
var card_back_dark: Color = h("#3A2F6B")
var card_shadow: Color = c(30, 50, 70, 60)

# ---------------------------------------------------------------------------
# 面板
# ---------------------------------------------------------------------------
var panel_bg: Color = c(255, 255, 255, 220)
var panel_border: Color = c(42, 92, 120, 80)

# ---------------------------------------------------------------------------
# 功能色
# ---------------------------------------------------------------------------
var accent: Color = h("#FF7F66")
var safe: Color = h("#5CAD6E")
var danger: Color = h("#DC4B4B")
var warning: Color = h("#FFC350")
var info: Color = h("#4BA3E3")
var highlight: Color = h("#FFD685")
var plot: Color = h("#9B7ED8")

# ---------------------------------------------------------------------------
# 手牌系统
# ---------------------------------------------------------------------------
var schedule: Color = h("#3A7CC0")
var rumor: Color = h("#C87D2A")
var completed: Color = h("#5CAD6E")
var deferred: Color = h("#A0A8B4")

# ---------------------------------------------------------------------------
# 文字色
# ---------------------------------------------------------------------------
var text_primary: Color = h("#232D3C")
var text_secondary: Color = h("#64788C")
var text_on_card: Color = h("#2A5C78")

# ---------------------------------------------------------------------------
# 笔记本色
# ---------------------------------------------------------------------------
var notebook_paper: Color = h("#FAF6EE")
var notebook_line: Color = h("#C5D4E8")
var notebook_spine: Color = h("#8B6544")
var notebook_spine_h: Color = h("#A37B56")
var notebook_tab: Color = h("#F0EBE1")
var notebook_border: Color = h("#C4B8A4")

# ---------------------------------------------------------------------------
# 相机
# ---------------------------------------------------------------------------
var camera_btn: Color = h("#FFD685")
var camera_btn_active: Color = h("#FF7F66")
var camera_tint: Color = h("#1A1A2E")
var camera_viewfinder: Color = Color.WHITE
var camera_rec: Color = c(220, 50, 50)

# ---------------------------------------------------------------------------
# 特效
# ---------------------------------------------------------------------------
var glow_color: Color = h("#FFD685")
var shake_color: Color = h("#FF7F66")

# ---------------------------------------------------------------------------
# 暗面世界 (Dark World) 颜色
# ---------------------------------------------------------------------------
var dark_bg_top: Color = h("#0D0F1A")
var dark_bg_bottom: Color = h("#1A1025")
var dark_card_face: Color = h("#1E1A2C")
var dark_card_border: Color = h("#5A4E8C")
var dark_panel: Color = c(20, 16, 35, 220)
var dark_accent: Color = h("#8B5CF6")
var dark_glow: Color = h("#C084FC")
var dark_energy: Color = h("#22D3EE")
var dark_energy_low: Color = h("#F43F5E")
var dark_passage: Color = h("#6366F1")
var dark_abyss: Color = h("#DC2626")

# ---------------------------------------------------------------------------
# 字号
# ---------------------------------------------------------------------------
const FONT_SIZE_TITLE: int = 28
const FONT_SIZE_SUBTITLE: int = 18
const FONT_SIZE_BODY: int = 14
const FONT_SIZE_CAPTION: int = 11
const FONT_SIZE_HUD: int = 13
const FONT_SIZE_CARD_ICON: int = 28
const FONT_SIZE_CARD_LABEL: int = 11

# ---------------------------------------------------------------------------
# 查询接口 (数据从 CardConfig 读取)
# ---------------------------------------------------------------------------

## 获取卡牌类型信息 (现实)
func card_type_info(type_key: String) -> Dictionary:
	return CardConfig.card_types.get(type_key, { "icon": "❓", "label": "未知", "color_key": "accent" })

## 获取卡牌类型对应颜色 (现实)
func card_type_color(type_key: String) -> Color:
	var info: Dictionary = card_type_info(type_key)
	return get(info.get("color_key", "accent"))

## 获取暗面世界卡牌类型信息
func dark_card_type_info(dark_type: String) -> Dictionary:
	return CardConfig.dark_card_types.get(dark_type, { "icon": "❓", "label": "未知", "color_key": "dark_accent" })

## 获取暗面世界卡牌类型对应颜色
func dark_card_type_color(dark_type: String) -> Color:
	var info: Dictionary = dark_card_type_info(dark_type)
	return get(info.get("color_key", "dark_accent"))
