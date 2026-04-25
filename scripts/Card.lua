-- ============================================================================
-- Card.lua - 卡牌数据、渲染与动画
-- 双层卡牌系统: 地点层 (明牌) + 事件层 (暗牌, 翻开后显示)
-- 纯 NanoVG 矢量绘制，Balatro 风格动效
-- ============================================================================

local Tween = require "lib.Tween"
local Theme = require "Theme"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
M.WIDTH  = 64
M.HEIGHT = 90
M.RADIUS = 8

-- ---------------------------------------------------------------------------
-- 地点信息 (卡牌正面显示的都市地点)
-- ---------------------------------------------------------------------------
M.LOCATION_INFO = {
    home        = { icon = "🏠", label = "家" },
    company     = { icon = "🏢", label = "公司" },
    school      = { icon = "🏫", label = "学校" },
    convenience = { icon = "🏪", label = "便利店" },
    park        = { icon = "🌳", label = "公园" },
    church      = { icon = "⛪", label = "教堂" },
    alley       = { icon = "🌙", label = "小巷" },
    station     = { icon = "🚉", label = "车站" },
    hospital    = { icon = "🏥", label = "医院" },
    library     = { icon = "📚", label = "图书馆" },
    bank        = { icon = "🏦", label = "银行" },
}

-- 可随机分配的普通地点 (不含 home/landmark/shop 等特殊位置)
M.REGULAR_LOCATIONS = {
    "company", "school", "convenience", "park", "church",
    "alley", "station", "hospital", "library", "bank",
}

-- ---------------------------------------------------------------------------
-- 事件类型 (翻开卡牌后显示的隐藏事件)
-- ---------------------------------------------------------------------------
-- 事件类型视觉信息由 Theme.cardTypeInfo() 提供
M.EVENT_TYPES = { "safe", "monster", "trap", "reward", "plot", "clue" }

-- 兼容旧代码的完整类型列表 (含特殊类型)
M.ALL_TYPES = { "safe", "home", "landmark", "shop", "monster", "trap", "reward", "plot", "clue" }

-- ---------------------------------------------------------------------------
-- 构造
-- ---------------------------------------------------------------------------

---@class CardData
---@field type string       事件类型 (safe/monster/trap/reward/plot/clue/home/landmark/shop)
---@field location string   地点类型 (home/company/school/convenience/park/church/alley/station/...)
---@field row number
---@field col number
---@field faceUp boolean
---@field x number 渲染位置
---@field y number 渲染位置
---@field scaleX number
---@field scaleY number
---@field rotation number degrees
---@field alpha number
---@field bounceY number 翻牌弹跳偏移
---@field glowIntensity number 0-1
---@field isFlipping boolean
---@field isDealing boolean
---@field hoverT number 0-1 hover 过渡

function M.new(cardType, row, col, location)
    return {
        type = cardType or "safe",
        location = location or "company",
        row = row or 1,
        col = col or 1,
        faceUp = (cardType == "landmark"),  -- 地标正面朝上（显示事件层）

        -- 渲染属性
        x = 0, y = 0,
        scaleX = 1.0,
        scaleY = 1.0,
        rotation = 0,
        alpha = 0,           -- 初始透明，deal 动画时渐入
        bounceY = 0,
        glowIntensity = 0,

        -- 状态
        isFlipping = false,
        isDealing = false,
        hoverT = 0,
        shakeX = 0,         -- 无效操作抖动偏移
    }
end

-- ---------------------------------------------------------------------------
-- 动画: 翻牌
-- ---------------------------------------------------------------------------

function M.flip(card, onComplete)
    if card.isFlipping or card.faceUp then return end
    card.isFlipping = true

    -- 阶段1: scaleX → 0 (收缩消失)
    Tween.to(card, { scaleX = 0, scaleY = 1.08 }, 0.14, {
        easing = Tween.Easing.easeInQuad,
        tag = "cardflip",
        onComplete = function()
            -- 切换正反面
            card.faceUp = true

            -- 阶段2: scaleX → 1 (弹出展开)
            Tween.to(card, { scaleX = 1.0, scaleY = 1.0 }, 0.28, {
                easing = Tween.Easing.easeOutBack,
                tag = "cardflip",
                onComplete = function()
                    card.isFlipping = false
                    -- 揭示光晕
                    card.glowIntensity = 1.0
                    Tween.to(card, { glowIntensity = 0 }, 0.6, {
                        easing = Tween.Easing.easeOutQuad,
                    })
                    if onComplete then onComplete(card) end
                end
            })
        end
    })

    -- 弹跳 Y
    Tween.to(card, { bounceY = -10 }, 0.12, {
        easing = Tween.Easing.easeOutQuad,
        tag = "cardflip",
        onComplete = function()
            Tween.to(card, { bounceY = 0 }, 0.35, {
                easing = Tween.Easing.easeOutBounce,
                tag = "cardflip",
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 无效操作抖动 (reject shake)
-- ---------------------------------------------------------------------------

function M.shake(card)
    if card._shaking then return end
    card._shaking = true
    card._shakeT = 0
    Tween.to(card, { _shakeT = 1 }, 0.35, {
        easing = Tween.Easing.linear,
        tag = "cardshake",
        onUpdate = function(_, t)
            local decay = (1 - t) ^ 2
            card.shakeX = math.sin(t * math.pi * 6) * 5 * decay
        end,
        onComplete = function()
            card.shakeX = 0
            card._shaking = false
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 发牌 (从 deck 位置飞到目标位置)
-- ---------------------------------------------------------------------------

function M.dealTo(card, targetX, targetY, delay)
    card.isDealing = true
    card.alpha = 0
    card.scaleX = 0.3
    card.scaleY = 0.3
    card.rotation = math.random(-15, 15)

    Tween.to(card, {
        x = targetX,
        y = targetY,
        alpha = 1.0,
        scaleX = 1.0,
        scaleY = 1.0,
        rotation = 0,
    }, 0.45, {
        delay = delay or 0,
        easing = Tween.Easing.easeOutBack,
        tag = "carddeal",
        onComplete = function()
            card.isDealing = false
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 重置 (反向收回)
-- ---------------------------------------------------------------------------

function M.undeal(card, deckX, deckY, delay, onComplete)
    Tween.to(card, {
        x = deckX,
        y = deckY,
        alpha = 0,
        scaleX = 0.2,
        scaleY = 0.2,
        rotation = math.random(-20, 20),
    }, 0.3, {
        delay = delay or 0,
        easing = Tween.Easing.easeInBack,
        tag = "carddeal",
        onComplete = function()
            card.faceUp = (card.type == "landmark")
            card.glowIntensity = 0
            card.bounceY = 0
            if onComplete then onComplete(card) end
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 变形 (monster → photo 驱除)
-- 先 scaleX/Y 收缩 + 抖动 → 类型切换 → 弹出展开 + 光晕
-- ---------------------------------------------------------------------------

function M.transformTo(card, newType, onComplete)
    if card._transforming then return end
    card._transforming = true

    -- 阶段1: 收缩 + 快速抖动 (0.25s)
    card._shakeT = 0
    Tween.to(card, { scaleX = 0.3, scaleY = 0.3, _shakeT = 1 }, 0.25, {
        easing = Tween.Easing.easeInQuad,
        tag = "cardtransform",
        onUpdate = function(_, t)
            -- 衰减抖动
            card.shakeX = math.sin(t * math.pi * 10) * 6 * (1 - t * 0.5)
        end,
        onComplete = function()
            -- 切换类型
            card.type = newType
            card.shakeX = 0

            -- 阶段2: 弹出展开 (0.35s)
            Tween.to(card, { scaleX = 1.0, scaleY = 1.0 }, 0.35, {
                easing = Tween.Easing.easeOutBack,
                tag = "cardtransform",
                onComplete = function()
                    card._transforming = false
                    -- 光晕
                    card.glowIntensity = 1.0
                    Tween.to(card, { glowIntensity = 0 }, 0.8, {
                        easing = Tween.Easing.easeOutQuad,
                    })
                    if onComplete then onComplete(card) end
                end
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 传闻角标 (外部注入查询函数，避免循环依赖)
-- ---------------------------------------------------------------------------

---@type fun(location: string): table|nil
local rumorQueryFn = nil

--- 设置传闻查询函数 (由 main.lua 注入)
--- fn(location) → { isSafe = bool } | nil
function M.setRumorQuery(fn)
    rumorQueryFn = fn
end

-- ---------------------------------------------------------------------------
-- 渲染
-- ---------------------------------------------------------------------------

function M.draw(vg, card, gameTime)
    if card.alpha <= 0.01 then return end
    local t = Theme.current
    local w, h, r = M.WIDTH, M.HEIGHT, M.RADIUS

    nvgSave(vg)
    local hoverFloat = card.hoverT * -4
    nvgTranslate(vg, card.x + card.shakeX, card.y + card.bounceY + hoverFloat)
    nvgRotate(vg, card.rotation * math.pi / 180)

    -- hover 放大
    local hoverScale = 1.0 + card.hoverT * 0.08
    nvgScale(vg, card.scaleX * hoverScale, card.scaleY * hoverScale)

    nvgGlobalAlpha(vg, card.alpha)

    -- 阴影
    local shadowPaint = nvgBoxGradient(vg, -w / 2 + 2, -h / 2 + 4, w, h, r, 10,
        nvgRGBA(t.cardShadow.r, t.cardShadow.g, t.cardShadow.b, math.floor(t.cardShadow.a * card.alpha)),
        nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, -w / 2 - 10, -h / 2 - 6, w + 20, h + 20)
    nvgFillPaint(vg, shadowPaint)
    nvgFill(vg)

    -- 卡体 — 两面都使用浅色底 (地点面和事件面都有内容)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -w / 2, -h / 2, w, h, r)
    if card.faceUp then
        nvgFillColor(vg, Theme.rgba(t.cardFace))
    else
        -- 地点面：用略带色调的浅底色，区别于翻开后的纯白
        nvgFillColor(vg, Theme.rgba(t.cardLocationBg or t.cardFace))
    end
    nvgFill(vg)

    -- 内容
    if card.faceUp then
        M.drawFace(vg, card, w, h)
    else
        M.drawLocation(vg, card, w, h, gameTime)
    end

    -- 边框 (hover 时高亮加粗)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -w / 2, -h / 2, w, h, r)
    if card.hoverT > 0.01 then
        local borderAlpha = math.floor(180 * card.alpha + 75 * card.hoverT)
        nvgStrokeColor(vg, Theme.rgbaA(t.highlight, borderAlpha))
        nvgStrokeWidth(vg, 1.5 + card.hoverT * 1.2)
    else
        nvgStrokeColor(vg, Theme.rgbaA(t.cardBorder, math.floor(180 * card.alpha)))
        nvgStrokeWidth(vg, 1.5)
    end
    nvgStroke(vg)

    -- hover 外发光
    if card.hoverT > 0.05 then
        local glowA = math.floor(card.hoverT * 40 * card.alpha)
        local hglow = nvgBoxGradient(vg, -w / 2 - 3, -h / 2 - 3, w + 6, h + 6, r + 2, 8,
            nvgRGBA(t.highlight.r, t.highlight.g, t.highlight.b, glowA),
            nvgRGBA(t.highlight.r, t.highlight.g, t.highlight.b, 0))
        nvgBeginPath(vg)
        nvgRect(vg, -w / 2 - 15, -h / 2 - 15, w + 30, h + 30)
        nvgFillPaint(vg, hglow)
        nvgFill(vg)
    end

    -- 翻牌光晕
    if card.glowIntensity > 0.01 then
        local gc = Theme.cardTypeColor(card.type)
        local glowR = math.max(w, h) * 0.8
        local glow = nvgRadialGradient(vg, 0, 0, 0, glowR,
            nvgRGBA(gc.r, gc.g, gc.b, math.floor(card.glowIntensity * 120)),
            nvgRGBA(gc.r, gc.g, gc.b, 0))
        nvgBeginPath(vg)
        nvgRect(vg, -glowR, -glowR, glowR * 2, glowR * 2)
        nvgFillPaint(vg, glow)
        nvgFill(vg)
    end

    nvgRestore(vg)
end

-- ---------------------------------------------------------------------------
-- 卡面 (翻开后 — 显示事件类型)
-- ---------------------------------------------------------------------------

function M.drawFace(vg, card, w, h)
    local t = Theme.current
    local info = Theme.cardTypeInfo(card.type)
    if not info then return end

    local tc = Theme.cardTypeColor(card.type)

    -- 顶部色条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -w / 2 + 3, -h / 2 + 3, w - 6, 6, 3)
    nvgFillColor(vg, Theme.rgbaA(tc, 200))
    nvgFill(vg)

    -- 事件图标 (emoji)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, t.fontSize.cardIcon)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgba(t.textPrimary))
    nvgText(vg, 0, -4, info.icon, nil)

    -- 事件标签
    nvgFontSize(vg, t.fontSize.cardLabel)
    nvgFillColor(vg, Theme.rgbaA(tc, 220))
    nvgText(vg, 0, h / 2 - 14, info.label, nil)
end

-- ---------------------------------------------------------------------------
-- 地点面 (未翻开 — 显示都市地点)
-- ---------------------------------------------------------------------------

function M.drawLocation(vg, card, w, h, gameTime)
    local t = Theme.current
    local hw, hh = w / 2, h / 2

    local locInfo = M.LOCATION_INFO[card.location]
    if not locInfo then
        -- 兜底：显示默认图案
        locInfo = { icon = "❓", label = "未知" }
    end

    -- 地点图标 (大 emoji，卡片中上部)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, t.fontSize.cardIcon)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgba(t.textPrimary))
    nvgText(vg, 0, -8, locInfo.icon, nil)

    -- 地点名称 (卡片下方)
    nvgFontSize(vg, t.fontSize.cardLabel)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 200))
    nvgText(vg, 0, h / 2 - 14, locInfo.label, nil)

    -- 内边框装饰 (微弱边线，暗示可翻开)
    local inset = 4
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw + inset, -hh + inset, w - inset * 2, h - inset * 2, M.RADIUS - 2)
    nvgStrokeColor(vg, Theme.rgbaA(t.cardBorder, 40))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    -- 微妙呼吸光 (暗示卡牌可交互)
    local breathe = 0.2 + 0.1 * math.sin(gameTime * 2.0 + card.row * 0.5 + card.col * 0.7)
    local glowPaint = nvgRadialGradient(vg, 0, -5, 0, 30,
        nvgRGBA(255, 255, 255, math.floor(breathe * 20)),
        nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, 0, -5, 30)
    nvgFillPaint(vg, glowPaint)
    nvgFill(vg)

    -- 传闻角标 (右上角小圆点: 绿=安全, 红=危险)
    if rumorQueryFn then
        local rumor = rumorQueryFn(card.location)
        if rumor then
            local badgeR = 6
            local bx = hw - 4
            local by = -hh + 4
            local pulse = 0.8 + 0.2 * math.sin(gameTime * 3.5)

            -- 角标底色
            local bc = rumor.isSafe and t.safe or t.danger
            nvgBeginPath(vg)
            nvgCircle(vg, bx, by, badgeR * pulse)
            nvgFillColor(vg, Theme.rgbaA(bc, 200))
            nvgFill(vg)

            -- 角标图标
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 8)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgText(vg, bx, by, rumor.isSafe and "✓" or "!", nil)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 碰撞检测 (点是否在卡牌内)
-- ---------------------------------------------------------------------------

function M.hitTest(card, px, py)
    if card.alpha < 0.1 then return false end
    local dx = math.abs(px - card.x)
    local dy = math.abs(py - (card.y + card.bounceY))
    return dx < M.WIDTH / 2 and dy < M.HEIGHT / 2
end

return M
