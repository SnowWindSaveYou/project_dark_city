-- ============================================================================
-- Card.lua - 卡牌数据、渲染与动画
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

-- 卡牌类型列表（用于随机生成）
M.ALL_TYPES = { "safe", "landmark", "shop", "monster", "trap", "reward", "plot", "clue" }

-- ---------------------------------------------------------------------------
-- 构造
-- ---------------------------------------------------------------------------

---@class CardData
---@field type string
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

function M.new(cardType, row, col)
    return {
        type = cardType or "safe",
        row = row or 1,
        col = col or 1,
        faceUp = (cardType == "landmark"),  -- 地标正面朝上

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

    -- 卡体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -w / 2, -h / 2, w, h, r)
    if card.faceUp then
        nvgFillColor(vg, Theme.rgba(t.cardFace))
    else
        nvgFillColor(vg, Theme.rgba(t.cardBack))
    end
    nvgFill(vg)

    -- 内容
    if card.faceUp then
        M.drawFace(vg, card, w, h)
    else
        M.drawBack(vg, card, w, h, gameTime)
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
-- 卡面 (正面)
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

    -- 图标 (emoji)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, t.fontSize.cardIcon)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgba(t.textPrimary))
    nvgText(vg, 0, -4, info.icon, nil)

    -- 标签
    nvgFontSize(vg, t.fontSize.cardLabel)
    nvgFillColor(vg, Theme.rgbaA(tc, 220))
    nvgText(vg, 0, h / 2 - 14, info.label, nil)
end

-- ---------------------------------------------------------------------------
-- 卡背 (反面) — 装饰图案
-- ---------------------------------------------------------------------------

function M.drawBack(vg, card, w, h, gameTime)
    local t = Theme.current
    local hw, hh = w / 2, h / 2

    -- 内边框
    local inset = 5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw + inset, -hh + inset, w - inset * 2, h - inset * 2, M.RADIUS - 2)
    nvgStrokeColor(vg, Theme.rgbaA(t.cardBackAlt, 120))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 中心菱形装饰
    local dSize = math.min(w, h) * 0.28
    nvgSave(vg)
    nvgRotate(vg, math.pi / 4)
    nvgBeginPath(vg)
    nvgRect(vg, -dSize / 2, -dSize / 2, dSize, dSize)
    nvgStrokeColor(vg, Theme.rgbaA(t.cardBackAlt, 100))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)
    -- 内部小菱形
    local dSmall = dSize * 0.5
    nvgBeginPath(vg)
    nvgRect(vg, -dSmall / 2, -dSmall / 2, dSmall, dSmall)
    nvgFillColor(vg, Theme.rgbaA(t.cardBackAlt, 40))
    nvgFill(vg)
    nvgRestore(vg)

    -- 四角小点
    local cornerOff = 12
    local dotR = 2.5
    for _, pos in ipairs({
        { -hw + cornerOff, -hh + cornerOff },
        {  hw - cornerOff, -hh + cornerOff },
        { -hw + cornerOff,  hh - cornerOff },
        {  hw - cornerOff,  hh - cornerOff },
    }) do
        nvgBeginPath(vg)
        nvgCircle(vg, pos[1], pos[2], dotR)
        nvgFillColor(vg, Theme.rgbaA(t.cardBackAlt, 80))
        nvgFill(vg)
    end

    -- 微妙呼吸光 (idle 动画)
    local breathe = 0.3 + 0.15 * math.sin(gameTime * 2.0 + card.row * 0.5 + card.col * 0.7)
    local glowPaint = nvgRadialGradient(vg, 0, 0, 0, dSize * 1.2,
        nvgRGBA(255, 255, 255, math.floor(breathe * 25)),
        nvgRGBA(255, 255, 255, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, dSize * 1.2)
    nvgFillPaint(vg, glowPaint)
    nvgFill(vg)
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
