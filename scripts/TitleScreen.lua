-- ============================================================================
-- TitleScreen.lua - 标题/开始画面
-- 氛围感入场 + 点击/按键开始
-- ============================================================================

local Tween = require "lib.Tween"
local VFX   = require "lib.VFX"
local Theme = require "Theme"

local M = {}

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------

local state = {
    active  = false,
    phase   = "none",   -- "enter"|"idle"|"exit"

    -- 动画值
    overlayAlpha  = 1.0,  -- 初始全黑
    titleY        = 0,
    titleAlpha    = 0,
    titleScale    = 0.6,
    subtitleAlpha = 0,
    promptAlpha   = 0,

    -- 装饰
    floatingCards = {},   -- 背景浮动卡牌

    -- 回调
    onStart = nil,
}

local TAG = "titlescreen"

-- ---------------------------------------------------------------------------
-- 背景浮动卡牌
-- ---------------------------------------------------------------------------

local function initFloatingCards()
    state.floatingCards = {}
    local icons = { "🏠", "👻", "⚡", "💎", "📖", "🔍", "🛒", "📸", "⛪" }
    for i = 1, 12 do
        state.floatingCards[i] = {
            x      = math.random() * 1.4 - 0.2,   -- 0~1 标准化坐标 (含越界)
            y      = math.random() * 1.4 - 0.2,
            icon   = icons[math.random(1, #icons)],
            rot    = math.random() * 360,
            speed  = 0.3 + math.random() * 0.4,    -- 漂移速度
            phase  = math.random() * math.pi * 2,  -- 相位
            size   = 18 + math.random() * 10,
            alpha  = 20 + math.random() * 30,
        }
    end
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

function M.show(onStart)
    state.active  = true
    state.phase   = "enter"
    state.onStart = onStart

    -- 重置
    state.overlayAlpha  = 1.0
    state.titleY        = 0
    state.titleAlpha    = 0
    state.titleScale    = 0.6
    state.subtitleAlpha = 0
    state.promptAlpha   = 0

    initFloatingCards()

    -- 入场动画
    -- 1. 遮罩从全黑褪到半透明
    Tween.to(state, { overlayAlpha = 0.55 }, 1.0, {
        easing = Tween.Easing.easeOutQuad, tag = TAG,
    })

    -- 2. 标题入场
    Tween.to(state, { titleAlpha = 1.0, titleScale = 1.0 }, 0.7, {
        delay = 0.4,
        easing = Tween.Easing.easeOutBack, tag = TAG,
    })

    -- 3. 副标题
    Tween.to(state, { subtitleAlpha = 1.0 }, 0.5, {
        delay = 0.9,
        easing = Tween.Easing.easeOutQuad, tag = TAG,
        onComplete = function()
            state.phase = "idle"
        end
    })

    -- 4. 提示闪烁 (持续)
    Tween.to(state, { promptAlpha = 1.0 }, 0.6, {
        delay = 1.3,
        easing = Tween.Easing.easeOutQuad, tag = TAG,
    })
end

function M.dismiss()
    if not state.active then return end
    if state.phase == "exit" then return end
    state.phase = "exit"

    Tween.cancelTag(TAG)

    -- 标题上浮消失
    Tween.to(state, {
        titleAlpha = 0, titleScale = 1.1,
        subtitleAlpha = 0, promptAlpha = 0,
    }, 0.3, {
        easing = Tween.Easing.easeInQuad, tag = TAG,
    })

    -- 遮罩消失
    Tween.to(state, { overlayAlpha = 0 }, 0.5, {
        delay = 0.15,
        easing = Tween.Easing.easeInQuad, tag = TAG,
        onComplete = function()
            state.active = false
            state.phase  = "none"
            if state.onStart then state.onStart() end
        end
    })
end

function M.isActive()
    return state.active
end

-- ---------------------------------------------------------------------------
-- 交互
-- ---------------------------------------------------------------------------

function M.handleClick()
    if not state.active then return false end
    if state.phase == "idle" then
        M.dismiss()
    end
    return true
end

function M.handleKey(key)
    if not state.active then return false end
    if state.phase == "idle" then
        if key == KEY_RETURN or key == KEY_SPACE then
            M.dismiss()
            return true
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- 渲染
-- ---------------------------------------------------------------------------

function M.draw(vg, logicalW, logicalH, gameTime)
    if not state.active then return end

    local t = Theme.current
    local cx = logicalW / 2

    -- === 遮罩 ===
    nvgBeginPath(vg)
    nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
    nvgFillColor(vg, nvgRGBA(12, 18, 30, math.floor(state.overlayAlpha * 255)))
    nvgFill(vg)

    -- === 浮动卡牌 ===
    for _, fc in ipairs(state.floatingCards) do
        local fx = fc.x * logicalW
        local fy = fc.y * logicalH
        -- 缓慢漂移
        local drift = math.sin(gameTime * fc.speed + fc.phase)
        local driftY = math.cos(gameTime * fc.speed * 0.7 + fc.phase + 1.5)
        fx = fx + drift * 15
        fy = fy + driftY * 10

        nvgSave(vg)
        nvgTranslate(vg, fx, fy)
        nvgRotate(vg, (fc.rot + gameTime * fc.speed * 5) * math.pi / 180)
        nvgGlobalAlpha(vg, fc.alpha / 255 * state.overlayAlpha)

        -- 卡背矩形
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -20, -28, 40, 56, 5)
        nvgFillColor(vg, nvgRGBA(t.cardBack.r, t.cardBack.g, t.cardBack.b, 60))
        nvgFill(vg)

        -- 图标
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fc.size)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 50))
        nvgText(vg, 0, 0, fc.icon, nil)

        nvgRestore(vg)
    end

    -- === 标题 ===
    if state.titleAlpha > 0.01 then
        local titleY = logicalH * 0.35

        nvgSave(vg)
        nvgTranslate(vg, cx, titleY)
        nvgScale(vg, state.titleScale, state.titleScale)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 42)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        VFX.drawLayeredText(0, 0, "暗面都市",
            t.accent.r, t.accent.g, t.accent.b, state.titleAlpha)

        nvgRestore(vg)

        -- 标题光晕
        if state.titleAlpha > 0.3 then
            local pulse = 0.8 + 0.2 * math.sin(gameTime * 1.5)
            local glowR = 100 * pulse
            local glow = nvgRadialGradient(vg, cx, titleY, 0, glowR,
                nvgRGBA(t.accent.r, t.accent.g, t.accent.b,
                    math.floor(state.titleAlpha * 25 * pulse)),
                nvgRGBA(t.accent.r, t.accent.g, t.accent.b, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, titleY, glowR)
            nvgFillPaint(vg, glow)
            nvgFill(vg)
        end
    end

    -- === 副标题 ===
    if state.subtitleAlpha > 0.01 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(t.textSecondary.r, t.textSecondary.g, t.textSecondary.b,
            math.floor(state.subtitleAlpha * 180)))
        nvgText(vg, cx, logicalH * 0.44, "用镜头记录真相  ·  用光明驱散恐惧", nil)
    end

    -- === 按任意键开始 (呼吸闪烁) ===
    if state.promptAlpha > 0.01 then
        local breathe = 0.5 + 0.5 * math.sin(gameTime * 2.5)
        local alpha = state.promptAlpha * breathe

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(t.textSecondary.r, t.textSecondary.g, t.textSecondary.b,
            math.floor(alpha * 200)))
        nvgText(vg, cx, logicalH * 0.62, "- 点击或按 Enter 开始 -", nil)
    end
end

return M
