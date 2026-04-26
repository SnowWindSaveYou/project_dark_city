## Theme - 全局配色与字体常量 (Autoload)
## 对应原版 Theme.lua
extends Node

# ---------------------------------------------------------------------------
# ThemeColor 辅助
# ---------------------------------------------------------------------------

## 255-based RGBA → Godot Color
static func c(r: int, g: int, b: int, a: int = 255) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0)

# ---------------------------------------------------------------------------
# 背景色
# ---------------------------------------------------------------------------
var bg_top      := c(235, 230, 220)
var bg_bottom   := c(215, 208, 195)

# ---------------------------------------------------------------------------
# 卡牌色
# ---------------------------------------------------------------------------
var card_face        := c(252, 250, 245)
var card_location_bg := c(245, 242, 235)
var card_back        := c(62, 68, 82)
var card_back_alt    := c(85, 92, 108)
var card_border      := c(180, 172, 160)

# ---------------------------------------------------------------------------
# 功能色
# ---------------------------------------------------------------------------
var accent    := c(70, 130, 210)
var safe      := c(76, 175, 80)
var danger    := c(220, 60, 60)
var warning   := c(245, 180, 50)
var info      := c(60, 180, 200)
var highlight := c(100, 140, 230)
var plot      := c(156, 100, 210)
var schedule  := c(230, 130, 60)
var rumor     := c(180, 140, 100)
var completed := c(76, 175, 80)
var deferred  := c(180, 160, 120)

# ---------------------------------------------------------------------------
# 文字色
# ---------------------------------------------------------------------------
var text_primary   := c(50, 45, 40)
var text_secondary := c(120, 110, 100)

# ---------------------------------------------------------------------------
# 笔记本色
# ---------------------------------------------------------------------------
var notebook_paper  := c(255, 252, 240)
var notebook_line   := c(180, 210, 240)
var notebook_spine  := c(140, 120, 100)
var notebook_tab    := c(230, 220, 200)
var notebook_border := c(200, 190, 175)

# ---------------------------------------------------------------------------
# 相机
# ---------------------------------------------------------------------------
var camera_viewfinder := c(0, 255, 80)
var camera_rec        := c(255, 50, 50)

# ---------------------------------------------------------------------------
# 字号
# ---------------------------------------------------------------------------
const FONT_SIZE_TITLE := 28
const FONT_SIZE_BODY  := 14
const FONT_SIZE_SMALL := 11
const FONT_SIZE_HUD   := 13

# ---------------------------------------------------------------------------
# 卡牌类型信息
# ---------------------------------------------------------------------------
const CARD_TYPES := {
	"safe":     { "icon": "🌙", "label": "安全",  "color_key": "safe" },
	"monster":  { "icon": "👻", "label": "怪物",  "color_key": "danger" },
	"trap":     { "icon": "⚡", "label": "陷阱",  "color_key": "warning" },
	"reward":   { "icon": "💎", "label": "奖励",  "color_key": "highlight" },
	"plot":     { "icon": "📖", "label": "剧情",  "color_key": "plot" },
	"clue":     { "icon": "🔍", "label": "线索",  "color_key": "info" },
	"landmark": { "icon": "🏰", "label": "地标",  "color_key": "safe" },
	"home":     { "icon": "🏠", "label": "家",    "color_key": "safe" },
	"shop":     { "icon": "🛒", "label": "商店",  "color_key": "highlight" },
	"photo":    { "icon": "📸", "label": "照片",  "color_key": "schedule" },
}

## 获取卡牌类型信息
func card_type_info(type_key: String) -> Dictionary:
	return CARD_TYPES.get(type_key, { "icon": "❓", "label": "未知", "color_key": "accent" })

## 获取卡牌类型对应颜色
func card_type_color(type_key: String) -> Color:
	var info := card_type_info(type_key)
	return get(info.get("color_key", "accent"))
