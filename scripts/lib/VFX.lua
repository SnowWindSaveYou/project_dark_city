-- ============================================================================
-- VFX.lua - 视觉特效系统 v2 (adapted)
-- 屏幕抖动 / 行动飘字(逐字错时) / 粒子爆发 / 分数弹出(4段) / 阶段过渡
-- ============================================================================

local M = {}

-- 渲染上下文（每帧由 setContext 设置）
local vg = nil
local logicalW, logicalH = 0, 0
local gameTime = 0

function M.setContext(_vg, _logicalW, _logicalH, _gameTime)
    vg = _vg
    logicalW = _logicalW
    logicalH = _logicalH
    gameTime = _gameTime
end

-- ============================================================================
-- 内部缓动函数
-- ============================================================================

local function easeOutElastic(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local c4 = (2 * math.pi) / 3
    return (2 ^ (-10 * t)) * math.sin((t * 10 - 0.75) * c4) + 1
end

local function easeOutBack(t)
    local c1, c3 = 1.70158, 2.70158
    return 1 + c3 * ((t - 1) ^ 3) + c1 * ((t - 1) ^ 2)
end

local function easeInQuad(t)  return t * t end
local function easeOutQuad(t) local u = 1 - t; return 1 - u * u end
local function lerp(a, b, t)  return a + (b - a) * t end

-- ============================================================================
-- HSV 工具
-- ============================================================================

local function rgbToHsv(r, g, b)
    r, g, b = r / 255, g / 255, b / 255
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local d   = max - min
    local h   = 0
    if d > 0 then
        if     max == r then h = ((g - b) / d) % 6
        elseif max == g then h = (b - r) / d + 2
        else                 h = (r - g) / d + 4
        end
        h = h * 60
    end
    return h, (max > 0 and d / max or 0), max
end

local function hsvToRgb(h, s, v)
    h = h % 360
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b = 0, 0, 0
    if     h < 60  then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else                r, g, b = c, 0, x
    end
    return math.floor((r + m) * 255), math.floor((g + m) * 255), math.floor((b + m) * 255)
end

local function hueToRgb(h)
    h = h % 360
    local c, x, m = 1.0, 0, 0
    x = c * (1 - math.abs((h / 60) % 2 - 1))
    local r, g, b = 0, 0, 0
    if     h < 60  then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else                r, g, b = c, 0, x
    end
    return math.floor((r + m) * 255), math.floor((g + m) * 255), math.floor((b + m) * 255)
end

--- 同色系加深阴影
local function shadowColor(r, g, b, alpha)
    local h, s, _ = rgbToHsv(r, g, b)
    h = (h - 30 + 360) % 360
    s = math.max(0.85, s * 1.05)
    local v = 0.50
    local sr, sg, sb = hsvToRgb(h, s, v)
    return nvgRGBA(sr, sg, sb, alpha)
end

M.shadowColor = shadowColor

--- 4层文字渲染辅助
function M.drawLayeredText(x, y, text, r, g, b, alpha)
    nvgFillColor(vg, shadowColor(r, g, b, math.floor(alpha * 200)))
    nvgText(vg, x + 2.5, y + 3.5, text, nil)
    nvgFillColor(vg, nvgRGBA(
        math.floor(r * 0.65), math.floor(g * 0.65), math.floor(b * 0.65),
        math.floor(alpha * 160)))
    nvgText(vg, x + 1.0, y + 1.5, text, nil)
    nvgFillColor(vg, nvgRGBA(r, g, b, math.floor(alpha * 255)))
    nvgText(vg, x, y, text, nil)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 85)))
    nvgText(vg, x - 1.0, y - 1.5, text, nil)
end

-- ============================================================================
-- UTF-8 字符分割
-- ============================================================================

local function utf8Split(str)
    local chars = {}
    local i = 1
    while i <= #str do
        local b = str:byte(i)
        local len = (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or (b >= 0xC0 and 2) or 1
        chars[#chars + 1] = str:sub(i, i + len - 1)
        i = i + len
    end
    return chars
end

-- ============================================================================
-- 屏幕抖动 (Screen Shake)
-- ============================================================================

local shake = {
    offsetX = 0, offsetY = 0,
    intensity = 0, duration = 0,
    timer = 0, frequency = 25,
}

function M.triggerShake(intensity, duration, frequency)
    shake.intensity = math.max(shake.intensity, intensity)
    shake.duration  = math.max(shake.duration, duration)
    shake.timer     = 0
    shake.frequency = frequency or 25
end

local function updateShake(dt)
    if shake.intensity <= 0 then shake.offsetX = 0; shake.offsetY = 0; return end
    shake.timer = shake.timer + dt
    local progress = shake.timer / shake.duration
    if progress >= 1.0 then shake.intensity = 0; shake.offsetX = 0; shake.offsetY = 0; return end
    local decay = (1.0 - progress) ^ 1.5
    local amp   = shake.intensity * decay
    local t     = shake.timer * shake.frequency
    shake.offsetX = math.sin(t * 2.17 + 0.3) * amp + math.sin(t * 3.51) * amp * 0.3
    shake.offsetY = math.cos(t * 1.73 + 0.7) * amp + math.cos(t * 2.89) * amp * 0.3
end

function M.getShakeOffset() return shake.offsetX, shake.offsetY end

-- ============================================================================
-- 行动飘字 — 逐字错时弹入 + 光晕背景
-- ============================================================================

local actionBanners = {}

function M.spawnBanner(text, r, g, b, size, duration)
    local chars = utf8Split(text)
    actionBanners[#actionBanners + 1] = {
        chars    = chars,
        text     = text,
        timer    = 0,
        maxTime  = duration or 1.5,
        r = r or 255, g = g or 255, b = b or 255,
        size     = size or 32,
    }
end

local function updateBanners(dt)
    for i = #actionBanners, 1, -1 do
        local b = actionBanners[i]
        b.timer = b.timer + dt
        if b.timer >= b.maxTime + (#b.chars - 1) * 0.055 + 0.1 then
            table.remove(actionBanners, i)
        end
    end
end

local function charDisplayWidth(ch, size)
    local b = ch:byte(1)
    return (b >= 0x80) and (size * 0.92) or (size * 0.52)
end

function M.drawBanners()
    local cx   = logicalW / 2
    local baseY = logicalH / 2 - 20
    local STAGGER   = 0.055
    local ENTRY_DUR = 0.18
    local SETTLE_DUR = 0.12
    local FADE_START = 0.70

    for idx, banner in ipairs(actionBanners) do
        local nChars = #banner.chars
        local totalStagger = (nChars - 1) * STAGGER
        local effectiveMax = banner.maxTime + totalStagger
        local progress     = banner.timer / effectiveMax

        local globalAlpha = 1.0
        if progress > FADE_START then
            globalAlpha = math.max(0, 1.0 - (progress - FADE_START) / (1.0 - FADE_START))
        end
        globalAlpha = easeOutQuad(globalAlpha)

        local globalOffY = 0
        if progress > FADE_START then
            globalOffY = -35 * easeOutQuad((progress - FADE_START) / (1.0 - FADE_START))
        end

        local totalW = 0
        local charW  = {}
        for ci, ch in ipairs(banner.chars) do
            charW[ci] = charDisplayWidth(ch, banner.size)
            totalW    = totalW + charW[ci]
        end

        local rowY = baseY - (idx - 1) * (banner.size * 1.3) + globalOffY

        if globalAlpha > 0.05 then
            local hW = totalW * 0.65 + banner.size
            local hH = banner.size * 0.7
            local glow = nvgRadialGradient(vg, cx, rowY, 0, math.max(hW, hH) * 1.4,
                nvgRGBA(banner.r, banner.g, banner.b, math.floor(globalAlpha * 38)),
                nvgRGBA(banner.r, banner.g, banner.b, 0))
            nvgBeginPath(vg)
            nvgRect(vg, cx - hW * 1.4, rowY - hH * 1.4, hW * 2.8, hH * 2.8)
            nvgFillPaint(vg, glow)
            nvgFill(vg)
        end

        local curX = cx - totalW / 2
        for ci, ch in ipairs(banner.chars) do
            local delay  = (ci - 1) * STAGGER
            local localT = banner.timer - delay

            local cAlpha  = globalAlpha
            local cY      = rowY
            local cScaleX = 1.0
            local cScaleY = 1.0

            if localT < 0 then
                curX = curX + charW[ci]
                goto continue_char
            elseif localT < ENTRY_DUR then
                local t  = localT / ENTRY_DUR
                local es = easeOutBack(t)
                cY     = cY + lerp(28, 0, easeOutQuad(t))
                cAlpha = globalAlpha * math.min(1.0, t * 5)
                cScaleX = lerp(0.4, 1.0, es)
                cScaleY = lerp(1.6, 1.0, easeOutBack(math.min(1, t * 1.2))) * (0.8 + 0.2 * es)
            elseif localT < ENTRY_DUR + SETTLE_DUR then
                local t = (localT - ENTRY_DUR) / SETTLE_DUR
                cScaleY = lerp(0.88, 1.0, easeOutQuad(t))
                cScaleX = lerp(1.12, 1.0, easeOutQuad(t))
            else
                local wave = math.sin(gameTime * 3.2 + ci * 0.9) * 2.5
                cY = cY + wave
                cScaleY = 1.0 + math.sin(gameTime * 2.8 + ci * 0.7) * 0.018
            end

            if cAlpha > 0.01 then
                local cx_char = curX + charW[ci] * 0.5
                nvgSave(vg)
                nvgTranslate(vg, cx_char, cY)
                nvgScale(vg, cScaleX, cScaleY)
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, banner.size)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                M.drawLayeredText(0, 0, ch, banner.r, banner.g, banner.b, cAlpha)
                nvgRestore(vg)
            end

            curX = curX + charW[ci]
            ::continue_char::
        end
    end
end

-- ============================================================================
-- 粒子爆发 (Burst Particles) — 通用版
-- ============================================================================

local burstParticles = {}

function M.spawnBurst(sx, sy, count, r, g, b, opts)
    opts = opts or {}
    count = count or 12
    r = r or 255; g = g or 215; b = b or 0
    for i = 1, count do
        local angle    = math.random() * math.pi * 2
        local speed    = (opts.speed or 60) + math.random() * (opts.speedVar or 40)
        local life     = (opts.life or 0.6) + math.random() * (opts.lifeVar or 0.4)
        burstParticles[#burstParticles + 1] = {
            x = sx, y = sy,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed - (opts.upward or 20),
            life = life, maxLife = life,
            r = r, g = g, b = b,
            size = (opts.size or 3) + math.random() * (opts.sizeVar or 3),
            gravity = opts.gravity or 80,
            sparkle = math.random() * math.pi * 2,
        }
    end
end

local function updateBurst(dt)
    for i = #burstParticles, 1, -1 do
        local p = burstParticles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy + p.gravity * dt
        p.life = p.life - dt
        if p.life <= 0 then table.remove(burstParticles, i) end
    end
end

function M.drawBurst()
    for _, p in ipairs(burstParticles) do
        local alpha = p.life / p.maxLife
        local size  = p.size * alpha
        local sa    = 0.7 + 0.3 * math.sin(gameTime * 15 + p.sparkle)

        -- 光晕
        local glow = nvgRadialGradient(vg, p.x, p.y, 0, size * 3,
            nvgRGBA(p.r, p.g, p.b, math.floor(alpha * sa * 50)),
            nvgRGBA(p.r, p.g, p.b, 0))
        nvgBeginPath(vg); nvgCircle(vg, p.x, p.y, size * 3)
        nvgFillPaint(vg, glow); nvgFill(vg)

        -- 核心
        nvgBeginPath(vg); nvgCircle(vg, p.x, p.y, size)
        nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(alpha * sa * 240)))
        nvgFill(vg)
    end
end

-- ============================================================================
-- 分数弹出 — 4段动画 + 数字滚动 + 运动拖影
-- ============================================================================

local scorePopups = {}

local function parseNumText(text)
    local prefix = text:match("^([+%-]?)") or ""
    local numStr = text:match("[%d]+")
    local suffix = numStr and text:match("%d+(.*)") or ""
    if numStr then
        return prefix, tonumber(numStr), suffix
    end
    return nil, nil, nil
end

function M.spawnPopup(text, x, y, r, g, b, scale)
    local prefix, numVal, suffix = parseNumText(text)
    scorePopups[#scorePopups + 1] = {
        text   = text,
        prefix = prefix,
        numVal = numVal,
        suffix = suffix,
        x = x, y = y,
        timer   = 0,
        maxTime = 1.25,
        r = r or 255, g = g or 255, b = b or 100,
        scale   = scale or 1.0,
    }
end

local function updatePopups(dt)
    for i = #scorePopups, 1, -1 do
        local p = scorePopups[i]
        p.timer = p.timer + dt
        if p.timer >= p.maxTime then
            table.remove(scorePopups, i)
        end
    end
end

local function drawOnePopup(p)
    local progress = p.timer / p.maxTime
    local baseScale = p.scale

    local curX, curY = p.x, p.y
    local curScale   = baseScale
    local alpha      = 1.0
    local rotation   = 0.0

    if progress < 0.15 then
        local t  = progress / 0.15
        curScale = baseScale * easeOutElastic(t) * 2.0
        alpha    = math.min(1.0, t * 8)
    elseif progress < 0.30 then
        local t  = (progress - 0.15) / 0.15
        curScale = baseScale * lerp(2.0, 1.0, easeInQuad(t))
    elseif progress < 0.75 then
        local t  = (progress - 0.30) / 0.45
        curScale = baseScale
        curY     = curY - math.sin(t * math.pi * 2.5) * 3.5
        rotation = math.sin(t * math.pi * 2.0) * 5.0
    else
        local t  = (progress - 0.75) / 0.25
        alpha    = 1.0 - easeOutQuad(t)
        curY     = curY - 85 * easeOutQuad(t)
        curScale = baseScale * (1.0 + t * 0.25)
        rotation = 8 * t
    end

    if alpha <= 0.01 then return end

    local displayText = p.text
    if p.numVal and progress >= 0.30 and progress < 0.68 then
        local t = (progress - 0.30) / 0.38
        if t < 0.75 then
            local base  = math.floor(p.numVal * t)
            local noise = math.floor(math.abs(math.sin(p.timer * 47.3 + 1.7)) * p.numVal * 0.45)
            local shown = math.min(base + noise, p.numVal + math.floor(p.numVal * 0.3))
            displayText = (p.prefix or "") .. tostring(shown) .. (p.suffix or "")
        end
    end

    -- 拖影
    if progress >= 0.75 then
        local t = (progress - 0.75) / 0.25
        for gi = 1, 3 do
            local ghostT = t - gi * 0.06
            if ghostT >= 0 then
                local ghostOff = -85 * easeOutQuad(ghostT)
                local ghostA   = alpha * (0.35 - gi * 0.10)
                if ghostA > 0.01 then
                    nvgSave(vg)
                    nvgTranslate(vg, curX, p.y + ghostOff)
                    nvgScale(vg, curScale * 0.92, curScale * 0.92)
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, 26)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(ghostA * 255)))
                    nvgText(vg, 0, 0, displayText, nil)
                    nvgRestore(vg)
                end
            end
        end
    end

    -- 主体
    nvgSave(vg)
    nvgTranslate(vg, curX, curY)
    nvgScale(vg, curScale, curScale)
    nvgRotate(vg, rotation * math.pi / 180)

    if alpha > 0.3 then
        local glowR = 28 + 14 * (curScale / baseScale)
        local glow = nvgRadialGradient(vg, 0, 0, 0, glowR,
            nvgRGBA(p.r, p.g, p.b, math.floor(alpha * 90)),
            nvgRGBA(p.r, p.g, p.b, 0))
        nvgBeginPath(vg)
        nvgRect(vg, -glowR, -glowR, glowR * 2, glowR * 2)
        nvgFillPaint(vg, glow)
        nvgFill(vg)
    end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    M.drawLayeredText(0, 0, displayText, p.r, p.g, p.b, alpha)

    nvgRestore(vg)
end

function M.drawPopups()
    for _, p in ipairs(scorePopups) do
        drawOnePopup(p)
    end
end

-- ============================================================================
-- 阶段过渡
-- ============================================================================

local phaseTrans = { text = "", timer = 0, duration = 1.2, r = 180, g = 120, b = 255 }

function M.showTransition(text, r, g, b)
    phaseTrans.text  = text
    phaseTrans.timer = phaseTrans.duration
    phaseTrans.r     = r or 180
    phaseTrans.g     = g or 120
    phaseTrans.b     = b or 255
end

local function updateTransition(dt)
    if phaseTrans.timer > 0 then phaseTrans.timer = phaseTrans.timer - dt end
end

function M.drawTransition()
    if phaseTrans.timer <= 0 then return end
    local progress = 1.0 - phaseTrans.timer / phaseTrans.duration
    local alpha, scale = 0, 1.0
    if progress < 0.25 then
        local t = progress / 0.25
        alpha = t; scale = easeOutBack(t)
    elseif progress < 0.72 then
        alpha = 1.0; scale = 1.0
    else
        local t = (progress - 0.72) / 0.28
        alpha = 1.0 - easeOutQuad(t); scale = 1.0 + t * 0.08
    end

    local tr, tg, tb = phaseTrans.r, phaseTrans.g, phaseTrans.b
    local cx, cy = logicalW / 2, logicalH / 2 - 20

    nvgSave(vg)
    nvgTranslate(vg, cx, cy); nvgScale(vg, scale, scale)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    M.drawLayeredText(0, 0, phaseTrans.text, tr, tg, tb, alpha)
    nvgRestore(vg)
end

-- ============================================================================
-- 屏幕闪光 (Flash Screen) — 快门/驱除效果
-- ============================================================================

local flash = { timer = 0, duration = 0, r = 255, g = 255, b = 255, peakAlpha = 200 }

--- 触发全屏闪光
---@param r? number 红 0-255 (默认白)
---@param g? number 绿
---@param b? number 蓝
---@param duration? number 持续时间 (默认 0.3)
---@param peakAlpha? number 峰值透明度 0-255 (默认 200)
function M.flashScreen(r, g, b, duration, peakAlpha)
    flash.r = r or 255
    flash.g = g or 255
    flash.b = b or 255
    flash.duration = duration or 0.3
    flash.peakAlpha = peakAlpha or 200
    flash.timer = flash.duration
end

local function updateFlash(dt)
    if flash.timer > 0 then
        flash.timer = flash.timer - dt
    end
end

function M.drawFlash()
    if flash.timer <= 0 then return end
    local progress = flash.timer / flash.duration
    -- 快速出现，缓慢消退：前 20% 满亮，后 80% 衰减
    local alpha
    if progress > 0.8 then
        -- 快速升起
        local t = (progress - 0.8) / 0.2
        alpha = (1 - t) * flash.peakAlpha
    else
        -- 缓慢消退
        alpha = progress / 0.8 * flash.peakAlpha
    end

    nvgBeginPath(vg)
    nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
    nvgFillColor(vg, nvgRGBA(flash.r, flash.g, flash.b, math.floor(alpha)))
    nvgFill(vg)
end

-- ============================================================================
-- 统一 update / reset
-- ============================================================================

function M.updateAll(dt)
    updateShake(dt)
    updateBanners(dt)
    updateBurst(dt)
    updatePopups(dt)
    updateTransition(dt)
    updateFlash(dt)
end

function M.resetAll()
    shake.intensity = 0; shake.offsetX = 0; shake.offsetY = 0
    actionBanners   = {}
    burstParticles  = {}
    scorePopups     = {}
    phaseTrans.timer = 0
    flash.timer = 0
end

return M
