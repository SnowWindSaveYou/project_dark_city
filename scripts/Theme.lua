-- ============================================================================
-- Theme.lua - 统一主题系统
-- 所有 UI/卡牌/特效颜色从此处获取，支持运行时切换
-- ============================================================================

local Tween = require "lib.Tween"

local M = {}

-- ---------------------------------------------------------------------------
-- Color helper
-- ---------------------------------------------------------------------------

---@class ThemeColor
---@field r number 0-255
---@field g number 0-255
---@field b number 0-255
---@field a number 0-255

---@param r number
---@param g number
---@param b number
---@param a? number
---@return ThemeColor
local function rgb(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 255 }
end

M.rgb = rgb  -- 暴露给外部使用

--- 从 hex 字符串创建颜色 (如 "#4BA3E3")
local function hex(str, a)
    str = str:gsub("#", "")
    return rgb(
        tonumber(str:sub(1, 2), 16),
        tonumber(str:sub(3, 4), 16),
        tonumber(str:sub(5, 6), 16),
        a or 255
    )
end

--- 从 ThemeColor 创建 NanoVG 颜色
---@param c ThemeColor
---@return userdata
function M.rgba(c)
    return nvgRGBA(c.r, c.g, c.b, c.a)
end

--- 带 alpha 覆盖
function M.rgbaA(c, a)
    return nvgRGBA(c.r, c.g, c.b, a)
end

--- 颜色插值 (用于主题过渡)
function M.lerpColor(a, b, t)
    return rgb(
        math.floor(a.r + (b.r - a.r) * t),
        math.floor(a.g + (b.g - a.g) * t),
        math.floor(a.b + (b.b - a.b) * t),
        math.floor(a.a + (b.a - a.a) * t)
    )
end

--- 颜色变暗
function M.darken(c, factor)
    return rgb(
        math.floor(c.r * factor),
        math.floor(c.g * factor),
        math.floor(c.b * factor),
        c.a
    )
end

--- 颜色变亮
function M.lighten(c, factor)
    return rgb(
        math.min(255, math.floor(c.r + (255 - c.r) * factor)),
        math.min(255, math.floor(c.g + (255 - c.g) * factor)),
        math.min(255, math.floor(c.b + (255 - c.b) * factor)),
        c.a
    )
end

-- ---------------------------------------------------------------------------
-- Theme 定义
-- ---------------------------------------------------------------------------

---@class ThemeData
M.themes = {
    -- ====================================================================
    -- 明亮都市 (世界表面 / 默认主题)
    -- 参考: 动漫都市日常插画，蓝天白云，校园少女
    -- ====================================================================
    bright = {
        name = "bright",

        -- 背景渐变
        bgTop       = hex("#87C3EB"),       -- 天空蓝上部
        bgBottom    = hex("#C8E1F5"),       -- 天空蓝下部

        -- 卡牌
        cardFace    = hex("#F5F0E8"),       -- 奶白纸色
        cardBack    = hex("#4BA3E3"),       -- 明亮天蓝
        cardBackAlt = hex("#3D8BC7"),       -- 卡背深色（花纹用）
        cardBorder  = hex("#2A5C78"),       -- 深青边框
        cardShadow  = rgb(30, 50, 70, 60), -- 阴影

        -- 表面 / 面板
        panelBg     = rgb(255, 255, 255, 220),
        panelBorder = rgb(42, 92, 120, 80),

        -- 文本
        textPrimary   = hex("#232D3C"),     -- 深色主文本
        textSecondary = hex("#64788C"),     -- 次要文本
        textOnCard    = hex("#2A5C78"),     -- 卡面文字

        -- 功能色
        accent    = hex("#FF7F66"),         -- 珊瑚/暖粉
        safe      = hex("#5CAD6E"),         -- 叶绿(安全)
        danger    = hex("#DC4B4B"),         -- 红(怪物/危险)
        warning   = hex("#FFC350"),         -- 琥珀(陷阱)
        info      = hex("#4BA3E3"),         -- 蓝(信息/线索)
        highlight = hex("#FFD685"),         -- 暖金(高光/奖励)
        plot      = hex("#9B7ED8"),         -- 紫(剧情)

        -- 相机模式
        cameraBtn       = hex("#FFD685"),   -- 相机按钮(暖金)
        cameraBtnActive = hex("#FF7F66"),   -- 相机按钮激活(珊瑚)
        cameraTint      = hex("#1A1A2E"),   -- 取景器暗角色

        -- 特效
        glowColor     = hex("#FFD685"),     -- 光晕暖金
        particleHue   = 40,                -- 粒子色相(金色系)
        shakeColor    = hex("#FF7F66"),     -- 抖动闪烁色

        -- 字体尺寸
        fontSize = {
            title    = 28,
            subtitle = 18,
            body     = 14,
            caption  = 11,
            cardIcon = 28,
            cardLabel = 11,
        },

        -- 间距
        spacing = {
            xs = 4,
            sm = 8,
            md = 16,
            lg = 24,
            xl = 32,
        },

        -- 卡牌场地类型视觉映射
        cardTypes = {
            safe     = { icon = "🏠", label = "安全",  colorKey = "safe" },
            landmark = { icon = "⛪", label = "地标",  colorKey = "highlight" },
            shop     = { icon = "🛒", label = "商店",  colorKey = "info" },
            monster  = { icon = "👻", label = "怪物",  colorKey = "danger" },
            trap     = { icon = "⚡", label = "陷阱",  colorKey = "warning" },
            reward   = { icon = "💎", label = "奖励",  colorKey = "highlight" },
            plot     = { icon = "📖", label = "剧情",  colorKey = "plot" },
            clue     = { icon = "🔍", label = "线索",  colorKey = "info" },
            photo    = { icon = "📸", label = "相片",  colorKey = "safe" },  -- 驱除后的安全格
        },
    },
}

-- ---------------------------------------------------------------------------
-- 当前主题 & 过渡
-- ---------------------------------------------------------------------------

---@type ThemeData
M.current = nil

--- 初始化主题
function M.init(themeName)
    M.current = M.themes[themeName or "bright"]
    print("[Theme] Initialized: " .. M.current.name)
end

--- 获取当前主题的功能色
---@param key string  如 "safe", "danger", "accent" 等
---@return ThemeColor
function M.color(key)
    return M.current[key] or M.current.textPrimary
end

--- 获取卡牌类型的视觉信息
function M.cardTypeInfo(cardType)
    return M.current.cardTypes[cardType]
end

--- 获取卡牌类型对应的颜色
function M.cardTypeColor(cardType)
    local info = M.current.cardTypes[cardType]
    if info then
        return M.current[info.colorKey] or M.current.accent
    end
    return M.current.accent
end

return M
