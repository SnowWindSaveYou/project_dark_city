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
	var color := Color.html(hex_str)
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
var bg_top      := h("#87C3EB")
var bg_bottom   := h("#C8E1F5")

# ---------------------------------------------------------------------------
# 卡牌色
# ---------------------------------------------------------------------------
var card_face        := h("#F5F0E8")
var card_location_bg := h("#E8EDF5")
var card_back        := h("#4BA3E3")
var card_back_alt    := h("#3D8BC7")
var card_border      := h("#2A5C78")
var card_back_dark   := h("#3A2F6B")
var card_shadow      := c(30, 50, 70, 60)

# ---------------------------------------------------------------------------
# 面板
# ---------------------------------------------------------------------------
var panel_bg     := c(255, 255, 255, 220)
var panel_border := c(42, 92, 120, 80)

# ---------------------------------------------------------------------------
# 功能色
# ---------------------------------------------------------------------------
var accent    := h("#FF7F66")
var safe      := h("#5CAD6E")
var danger    := h("#DC4B4B")
var warning   := h("#FFC350")
var info      := h("#4BA3E3")
var highlight := h("#FFD685")
var plot      := h("#9B7ED8")

# ---------------------------------------------------------------------------
# 手牌系统
# ---------------------------------------------------------------------------
var schedule  := h("#3A7CC0")
var rumor     := h("#C87D2A")
var completed := h("#5CAD6E")
var deferred  := h("#A0A8B4")

# ---------------------------------------------------------------------------
# 文字色
# ---------------------------------------------------------------------------
var text_primary   := h("#232D3C")
var text_secondary := h("#64788C")
var text_on_card   := h("#2A5C78")

# ---------------------------------------------------------------------------
# 笔记本色
# ---------------------------------------------------------------------------
var notebook_paper   := h("#FAF6EE")
var notebook_line    := h("#C5D4E8")
var notebook_spine   := h("#8B6544")
var notebook_spine_h := h("#A37B56")
var notebook_tab     := h("#F0EBE1")
var notebook_border  := h("#C4B8A4")

# ---------------------------------------------------------------------------
# 相机
# ---------------------------------------------------------------------------
var camera_btn        := h("#FFD685")
var camera_btn_active := h("#FF7F66")
var camera_tint       := h("#1A1A2E")
var camera_viewfinder := Color.WHITE
var camera_rec        := c(220, 50, 50)

# ---------------------------------------------------------------------------
# 特效
# ---------------------------------------------------------------------------
var glow_color   := h("#FFD685")
var shake_color  := h("#FF7F66")

# ---------------------------------------------------------------------------
# 暗面世界 (Dark World) 颜色
# ---------------------------------------------------------------------------
var dark_bg_top      := h("#0D0F1A")
var dark_bg_bottom   := h("#1A1025")
var dark_card_face   := h("#1E1A2C")
var dark_card_border := h("#5A4E8C")
var dark_panel       := c(20, 16, 35, 220)
var dark_accent      := h("#8B5CF6")
var dark_glow        := h("#C084FC")
var dark_energy      := h("#22D3EE")
var dark_energy_low  := h("#F43F5E")
var dark_passage     := h("#6366F1")
var dark_abyss       := h("#DC2626")

# ---------------------------------------------------------------------------
# 字号
# ---------------------------------------------------------------------------
const FONT_SIZE_TITLE    := 28
const FONT_SIZE_SUBTITLE := 18
const FONT_SIZE_BODY     := 14
const FONT_SIZE_CAPTION  := 11
const FONT_SIZE_HUD      := 13
const FONT_SIZE_CARD_ICON  := 28
const FONT_SIZE_CARD_LABEL := 11

# ---------------------------------------------------------------------------
# 卡牌类型信息 (现实世界)
# ---------------------------------------------------------------------------
const CARD_TYPES := {
	"safe":     { "icon": "✨", "label": "安全",  "color_key": "safe" },
	"home":     { "icon": "🏠", "label": "家",    "color_key": "safe" },
	"landmark": { "icon": "🏛️", "label": "地标",  "color_key": "highlight" },
	"shop":     { "icon": "🛒", "label": "商店",  "color_key": "info" },
	"monster":  { "icon": "👻", "label": "怪物",  "color_key": "danger" },
	"trap":     { "icon": "⚡", "label": "陷阱",  "color_key": "warning" },
	"reward":   { "icon": "💎", "label": "奖励",  "color_key": "highlight" },
	"plot":     { "icon": "📖", "label": "剧情",  "color_key": "plot" },
	"clue":     { "icon": "🔍", "label": "线索",  "color_key": "info" },
	"photo":    { "icon": "📸", "label": "相片",  "color_key": "safe" },
	"rift":     { "icon": "🌀", "label": "裂隙",  "color_key": "dark_accent" },
}

# ---------------------------------------------------------------------------
# 暗面世界卡牌类型信息
# ---------------------------------------------------------------------------
const DARK_CARD_TYPES := {
	"normal":     { "icon": "🌑", "label": "暗巷",    "color_key": "dark_accent" },
	"shop":       { "icon": "🏪", "label": "暗市",    "color_key": "info" },
	"intel":      { "icon": "👁️", "label": "情报点",  "color_key": "plot" },
	"checkpoint": { "icon": "🚧", "label": "关卡",    "color_key": "warning" },
	"clue":       { "icon": "🔮", "label": "线索",    "color_key": "dark_glow" },
	"item":       { "icon": "📦", "label": "道具",    "color_key": "highlight" },
	"passage":    { "icon": "🕳️", "label": "通道",    "color_key": "dark_passage" },
	"abyss_core": { "icon": "💀", "label": "深渊核心", "color_key": "dark_abyss" },
	"rift":       { "icon": "🌀", "label": "裂隙",    "color_key": "dark_accent" },
}

# ---------------------------------------------------------------------------
# 查询接口
# ---------------------------------------------------------------------------

## 获取卡牌类型信息 (现实)
func card_type_info(type_key: String) -> Dictionary:
	return CARD_TYPES.get(type_key, { "icon": "❓", "label": "未知", "color_key": "accent" })

## 获取卡牌类型对应颜色 (现实)
func card_type_color(type_key: String) -> Color:
	var info := card_type_info(type_key)
	return get(info.get("color_key", "accent"))

## 获取暗面世界卡牌类型信息
func dark_card_type_info(dark_type: String) -> Dictionary:
	return DARK_CARD_TYPES.get(dark_type, { "icon": "❓", "label": "未知", "color_key": "dark_accent" })

## 获取暗面世界卡牌类型对应颜色
func dark_card_type_color(dark_type: String) -> Color:
	var info := dark_card_type_info(dark_type)
	return get(info.get("color_key", "dark_accent"))
