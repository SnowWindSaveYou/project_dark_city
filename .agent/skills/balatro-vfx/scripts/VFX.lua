-- ============================================================================
-- VFX.lua - 视觉特效系统 v2
-- 屏幕抖动 / 行动飘字(逐字错时) / 筹码粒子 / 底池脉冲 / 分数弹出(4段) /
-- 融合特效 / 对手融合动画 / 阶段过渡 / 补牌特效
-- ============================================================================

local Tween = require "balatro.Tween"
local Card  = require "balatro.Card"

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
-- 缓动函数
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

-- RGB → HSV
local function rgbToHsv(r, g, b)
    r, g, b = r/255, g/255, b/255
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

-- HSV → RGB (0-255)
local function hsvToRgb(h, s, v)
    h = h % 360
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b = 0, 0, 0
    if     h < 60  then r,g,b = c,x,0
    elseif h < 120 then r,g,b = x,c,0
    elseif h < 180 then r,g,b = 0,c,x
    elseif h < 240 then r,g,b = 0,x,c
    elseif h < 300 then r,g,b = x,0,c
    else               r,g,b = c,0,x
    end
    return math.floor((r+m)*255), math.floor((g+m)*255), math.floor((b+m)*255)
end

-- 同色系加深阴影：色相偏转 -30°（保持色系感），高饱和，中暗亮度
-- 金色→深橙影，紫色→深蓝紫影，自然插画风，不对撞
local function shadowColor(r, g, b, alpha)
    local h, s, _ = rgbToHsv(r, g, b)
    h = (h - 30 + 360) % 360      -- 向暖侧偏转 30°，保持同色系
    s = math.max(0.85, s * 1.05)  -- 拉高饱和度，让阴影更鲜
    local v = 0.50                 -- 中暗亮度：作为阴影够深，颜色依然可见
    local sr, sg, sb = hsvToRgb(h, s, v)
    return nvgRGBA(sr, sg, sb, alpha)
end

-- 暴露给外部模块使用（ATK显示等静态文字也用同款渲染方案）
M.shadowColor = shadowColor

--- 4层文字渲染辅助：深影 → 内描 → 主色 → 白色高光
--- 调用前需已设置好 nvgFontFace / nvgFontSize / nvgTextAlign
---@param x number  绘制中心 X（相对当前变换）
---@param y number  绘制中心 Y
---@param text string
---@param r number  主色 R (0-255)
---@param g number  主色 G
---@param b number  主色 B
---@param alpha number  整体不透明度 (0.0-1.0)
function M.drawLayeredText(x, y, text, r, g, b, alpha)
    -- 层1：同色系深影
    nvgFillColor(vg, shadowColor(r, g, b, math.floor(alpha * 200)))
    nvgText(vg, x + 2.5, y + 3.5, text, nil)
    -- 层2：同色系内描
    nvgFillColor(vg, nvgRGBA(
        math.floor(r * 0.65), math.floor(g * 0.65), math.floor(b * 0.65),
        math.floor(alpha * 160)))
    nvgText(vg, x + 1.0, y + 1.5, text, nil)
    -- 层3：主色
    nvgFillColor(vg, nvgRGBA(r, g, b, math.floor(alpha * 255)))
    nvgText(vg, x, y, text, nil)
    -- 层4：白色高光
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
-- 行动飘字 v2 — 逐字错时弹入 + 光晕背景
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
        -- 最后一个字的 stagger + maxTime 之后才删除
        if b.timer >= b.maxTime + (#b.chars - 1) * 0.055 + 0.1 then
            table.remove(actionBanners, i)
        end
    end
end

-- 估算单字符显示宽度（用于居中）
local function charDisplayWidth(ch, size)
    local b = ch:byte(1)
    return (b >= 0x80) and (size * 0.92) or (size * 0.52)
end

function M.drawBanners()
    local cx   = logicalW / 2
    local baseY = logicalH / 2 - 20
    local STAGGER   = 0.055   -- 每字延迟
    local ENTRY_DUR = 0.18    -- 弹入时长
    local SETTLE_DUR = 0.12   -- 回弹时长
    local FADE_START = 0.70   -- 相对 maxTime 的比例：何时开始淡出

    for idx, banner in ipairs(actionBanners) do
        local nChars = #banner.chars
        local totalStagger = (nChars - 1) * STAGGER
        local effectiveMax = banner.maxTime + totalStagger
        local progress     = banner.timer / effectiveMax

        -- 全局淡出（最后 30% 时间）
        local globalAlpha = 1.0
        local fadeFrom = FADE_START
        if progress > fadeFrom then
            globalAlpha = math.max(0, 1.0 - (progress - fadeFrom) / (1.0 - fadeFrom))
        end
        globalAlpha = easeOutQuad(globalAlpha)  -- 让淡出更平滑

        -- 全局纵向偏移（淡出阶段向上飘）
        local globalOffY = 0
        if progress > fadeFrom then
            globalOffY = -35 * easeOutQuad((progress - fadeFrom) / (1.0 - fadeFrom))
        end

        -- 计算总宽度，用于居中
        local totalW = 0
        local charW  = {}
        for ci, ch in ipairs(banner.chars) do
            charW[ci] = charDisplayWidth(ch, banner.size)
            totalW    = totalW + charW[ci]
        end

        local rowY = baseY - (idx - 1) * (banner.size * 1.3) + globalOffY

        -- ── 背景光晕 ──────────────────────────────────────────────────────
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

        -- ── 逐字绘制 ───────────────────────────────────────────────────────
        local curX = cx - totalW / 2
        for ci, ch in ipairs(banner.chars) do
            local delay  = (ci - 1) * STAGGER
            local localT = banner.timer - delay   -- 该字的本地时间

            local cAlpha  = globalAlpha
            local cY      = rowY
            local cScaleX = 1.0
            local cScaleY = 1.0

            if localT < 0 then
                -- 还未开始：跳过（但占位）
                curX = curX + charW[ci]
                goto continue_char
            elseif localT < ENTRY_DUR then
                -- 弹入：从上方掉入，弹性放大
                local t  = localT / ENTRY_DUR
                local es = easeOutBack(t)
                cY     = cY + lerp(28, 0, easeOutQuad(t))
                cAlpha = globalAlpha * math.min(1.0, t * 5)
                -- x 方向轻微挤压感
                cScaleX = lerp(0.4, 1.0, es)
                cScaleY = lerp(1.6, 1.0, easeOutBack(math.min(1, t * 1.2))) * (0.8 + 0.2 * es)
            elseif localT < ENTRY_DUR + SETTLE_DUR then
                -- 回弹：轻微竖向压扁
                local t = (localT - ENTRY_DUR) / SETTLE_DUR
                cScaleY = lerp(0.88, 1.0, easeOutQuad(t))
                cScaleX = lerp(1.12, 1.0, easeOutQuad(t))
            else
                -- 悬停：轻微 sin 浮动（每字相位不同）
                local wave = math.sin(gameTime * 3.2 + ci * 0.9) * 2.5
                cY = cY + wave
                cScaleY = 1.0 + math.sin(gameTime * 2.8 + ci * 0.7) * 0.018
            end

            if cAlpha > 0.01 then
                local cx_char = curX + charW[ci] * 0.5
                nvgSave(vg)
                nvgTranslate(vg, cx_char, cY)
                nvgScale(vg, cScaleX, cScaleY)

                nvgFontFace(vg, "bold")
                nvgFontSize(vg, banner.size)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

                -- 对比色投影（HSV旋转155°）
                nvgFillColor(vg, shadowColor(banner.r, banner.g, banner.b,
                    math.floor(cAlpha * 200)))
                nvgText(vg, 2.5, 3.5, ch, nil)

                -- 近距内描（同色系略暗，增加立体感）
                nvgFillColor(vg, nvgRGBA(
                    math.floor(banner.r * 0.65),
                    math.floor(banner.g * 0.65),
                    math.floor(banner.b * 0.65),
                    math.floor(cAlpha * 160)))
                nvgText(vg, 1.0, 1.5, ch, nil)

                -- 主色
                nvgFillColor(vg, nvgRGBA(banner.r, banner.g, banner.b, math.floor(cAlpha * 255)))
                nvgText(vg, 0, 0, ch, nil)

                -- 白色高光（左上角，浅色背景下适当减弱）
                nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(cAlpha * 85)))
                nvgText(vg, -1, -1.2, ch, nil)

                nvgRestore(vg)
            end

            curX = curX + charW[ci]
            ::continue_char::
        end
    end
end

-- ============================================================================
-- 筹码粒子 (Chip Particles) — 不变
-- ============================================================================

local chipParticles = {}

function M.spawnChips(sx, sy, tx, ty, count, r, g, b)
    count = count or 12
    r = r or 255; g = g or 215; b = b or 0
    for i = 1, count do
        local delay    = (i - 1) * 0.03 + math.random() * 0.05
        local duration = 0.4 + math.random() * 0.3
        chipParticles[#chipParticles + 1] = {
            sx = sx, sy = sy, tx = tx, ty = ty,
            midOffX = (math.random() - 0.5) * 80,
            midOffY = -30 - math.random() * 40,
            timer = -delay, duration = duration,
            r = r, g = g, b = b,
            size    = 3 + math.random() * 3,
            sparkle = math.random() * math.pi * 2,
        }
    end
end

local function updateChips(dt)
    for i = #chipParticles, 1, -1 do
        local p = chipParticles[i]
        p.timer = p.timer + dt
        if p.timer >= p.duration then table.remove(chipParticles, i) end
    end
end

function M.drawChips()
    for _, p in ipairs(chipParticles) do
        if p.timer <= 0 then goto skip_chip end
        local t   = math.min(1.0, p.timer / p.duration)
        local et  = t * t
        local midX = (p.sx + p.tx) / 2 + p.midOffX
        local midY = (p.sy + p.ty) / 2 + p.midOffY
        local omt  = 1 - et
        local px   = omt*omt*p.sx + 2*omt*et*midX + et*et*p.tx
        local py   = omt*omt*p.sy + 2*omt*et*midY + et*et*p.ty
        local alpha = t < 0.7 and 1.0 or (1.0 - (t-0.7)/0.3)
        local size  = p.size * (1.0 - t*0.3)
        local sa    = 0.7 + 0.3 * math.sin(gameTime*15 + p.sparkle)

        local glow = nvgRadialGradient(vg, px, py, 0, size*3,
            nvgRGBA(p.r,p.g,p.b, math.floor(alpha*sa*60)),
            nvgRGBA(p.r,p.g,p.b, 0))
        nvgBeginPath(vg); nvgCircle(vg, px, py, size*3)
        nvgFillPaint(vg, glow); nvgFill(vg)

        nvgBeginPath(vg); nvgCircle(vg, px, py, size)
        nvgFillColor(vg, nvgRGBA(p.r,p.g,p.b, math.floor(alpha*sa*240)))
        nvgFill(vg)
        ::skip_chip::
    end
end

-- ============================================================================
-- 底池脉冲 (Pot Pulse) — 不变
-- ============================================================================

local potPulse = { active=false, timer=0, duration=0.6, intensity=1.0 }

function M.triggerPotPulse(intensity)
    potPulse.active = true; potPulse.timer = 0; potPulse.intensity = intensity or 1.0
end

local function updatePotPulse(dt)
    if not potPulse.active then return end
    potPulse.timer = potPulse.timer + dt
    if potPulse.timer >= potPulse.duration then potPulse.active = false end
end

function M.getPotPulseState()
    if not potPulse.active then return 1.0, 0, 0 end
    local t        = potPulse.timer / potPulse.duration
    local envelope = math.sin(t * math.pi)
    local intensity = potPulse.intensity
    return 1.0 + 0.15*envelope*intensity, envelope*intensity,
           math.floor(40*envelope*intensity)
end

-- ============================================================================
-- 分数弹出 v2 — 4段动画 + 数字滚动 + 运动拖影
-- ============================================================================

local scorePopups = {}

-- 从文本中提取数字信息（用于滚动效果）
local function parseNumText(text)
    local prefix = text:match("^([+%-]?)")  or ""
    local numStr = text:match("[%d]+")
    local suffix = numStr and text:match("%d+(.*)")  or ""
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
        -- 拖影历史（exit 阶段用）
        trailPositions = {},
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

-- 绘制单个 popup（含拖影）
local function drawOnePopup(p)
    local progress = p.timer / p.maxTime
    local baseScale = p.scale

    -- ── 4段时序 ─────────────────────────────────────────────────────────────
    -- Phase 1: 0~0.15  弹出  easeOutElastic, scale 0→2.0
    -- Phase 2: 0.15~0.30  回弹  easeInQuad, scale 2.0→1.0
    -- Phase 3: 0.30~0.75  浮动  sin漂移 + 数字滚动
    -- Phase 4: 0.75~1.00  飞出  向上80px + 淡出 + 拖影

    local curX, curY = p.x, p.y
    local curScale   = baseScale
    local alpha      = 1.0
    local rotation   = 0.0      -- 度数

    if progress < 0.15 then
        local t  = progress / 0.15
        curScale = baseScale * easeOutElastic(t) * 2.0
        alpha    = math.min(1.0, t * 8)   -- 快速淡入
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
        rotation = 8 * t   -- 轻微旋转漂移
    end

    if alpha <= 0.01 then return end

    -- ── 数字滚动文本 ─────────────────────────────────────────────────────────
    local displayText = p.text
    if p.numVal and progress >= 0.30 and progress < 0.68 then
        local t = (progress - 0.30) / 0.38
        if t < 0.75 then
            -- 快速跳动：用 sin 产生伪随机跳动值
            local base  = math.floor(p.numVal * t)
            local noise = math.floor(math.abs(math.sin(p.timer * 47.3 + 1.7)) * p.numVal * 0.45)
            local shown = math.min(base + noise, p.numVal + math.floor(p.numVal * 0.3))
            displayText = (p.prefix or "") .. tostring(shown) .. (p.suffix or "")
        end
    end

    -- ── 拖影（phase 4 专用）─────────────────────────────────────────────────
    if progress >= 0.75 then
        local t = (progress - 0.75) / 0.25
        local baseOffY = -85 * easeOutQuad(t)
        local ghostCount = 3
        for gi = 1, ghostCount do
            local ghostT   = t - gi * 0.06
            if ghostT < 0 then goto skip_ghost end
            local ghostOff = -85 * easeOutQuad(ghostT)
            local ghostA   = alpha * (0.35 - gi * 0.10)
            if ghostA <= 0.01 then goto skip_ghost end

            nvgSave(vg)
            nvgTranslate(vg, curX, p.y + ghostOff)
            nvgScale(vg, curScale * 0.92, curScale * 0.92)
            nvgFontFace(vg, "pixel")
            nvgFontSize(vg, 26)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(ghostA * 255)))
            nvgText(vg, 0, 0, displayText, nil)
            nvgRestore(vg)
            ::skip_ghost::
        end
    end

    -- ── 主体绘制 ─────────────────────────────────────────────────────────────
    nvgSave(vg)
    nvgTranslate(vg, curX, curY)
    nvgScale(vg, curScale, curScale)
    nvgRotate(vg, rotation * math.pi / 180)

    -- 光晕（在文字背后）
    if alpha > 0.3 then
        local glowR = 28 + 14 * (curScale / baseScale)
        local glow = nvgRadialGradient(vg, 0, 0, 0, glowR,
            nvgRGBA(p.r, p.g, p.b, math.floor(alpha * 90)),
            nvgRGBA(p.r, p.g, p.b, 0))
        nvgBeginPath(vg)
        nvgRect(vg, -glowR, -glowR, glowR*2, glowR*2)
        nvgFillPaint(vg, glow)
        nvgFill(vg)
    end

    -- pixel 字体，四层渲染
    nvgFontFace(vg, "pixel")
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 对比色投影（HSV旋转155°）
    nvgFillColor(vg, shadowColor(p.r, p.g, p.b, math.floor(alpha * 210)))
    nvgText(vg, 2, 3, displayText, nil)

    -- 近距内描（同色系略暗，增加立体感）
    nvgFillColor(vg, nvgRGBA(
        math.floor(p.r * 0.65),
        math.floor(p.g * 0.65),
        math.floor(p.b * 0.65),
        math.floor(alpha * 160)))
    nvgText(vg, 1, 1.5, displayText, nil)

    -- 主色
    nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(alpha * 255)))
    nvgText(vg, 0, 0, displayText, nil)

    -- 白色高光（左上角，浅色背景下减弱）
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 90)))
    nvgText(vg, -1, -1.5, displayText, nil)

    nvgRestore(vg)
end

function M.drawPopups()
    for _, p in ipairs(scorePopups) do
        drawOnePopup(p)
    end
end

-- ============================================================================
-- 融合特效 (Fuse Effects) — 不变
-- ============================================================================

local fuseEffects = {}

function M.spawnFuseEffect(x, y, label)
    local particles = {}
    for i = 1, 24 do
        local angle = math.random() * math.pi * 2
        local speed = 30 + math.random() * 80
        local life  = 0.5 + math.random() * 0.8
        particles[i] = {
            x = 0, y = 0,
            vx = math.cos(angle)*speed, vy = math.sin(angle)*speed,
            life = life, maxLife = life,
            size = 2 + math.random() * 4,
            hue  = math.random() * 60 + 30,
        }
    end
    fuseEffects[#fuseEffects + 1] = {
        x = x, y = y,
        timer = 0, duration = 1.8,
        particles = particles,
        label = label,
        ringScale = 0,
    }
end

local function hueToRgb(h)
    h = h % 360
    local c = 1.0
    local x = c * (1 - math.abs((h/60)%2 - 1))
    local m = 0
    local r, g, b = 0, 0, 0
    if h < 60 then r,g,b=c,x,0 elseif h < 120 then r,g,b=x,c,0
    elseif h < 180 then r,g,b=0,c,x elseif h < 240 then r,g,b=0,x,c
    elseif h < 300 then r,g,b=x,0,c else r,g,b=c,0,x end
    return math.floor((r+m)*255), math.floor((g+m)*255), math.floor((b+m)*255)
end

local function updateFuseEffects(dt)
    for i = #fuseEffects, 1, -1 do
        local fx = fuseEffects[i]
        fx.timer     = fx.timer + dt
        fx.ringScale = math.min(1.0, fx.timer / 0.3)
        for _, p in ipairs(fx.particles) do
            p.x = p.x + p.vx * dt; p.y = p.y + p.vy * dt
            p.vy = p.vy + 20*dt;   p.life = p.life - dt
        end
        if fx.timer >= fx.duration then table.remove(fuseEffects, i) end
    end
end

function M.drawFuseEffects()
    for _, fx in ipairs(fuseEffects) do
        local progress = fx.timer / fx.duration
        local alpha    = progress < 0.7 and 1.0 or (1.0 - (progress-0.7)/0.3)
        nvgSave(vg)
        nvgTranslate(vg, fx.x, fx.y)

        local ringR = fx.ringScale * 40
        if ringR > 0 then
            nvgBeginPath(vg); nvgCircle(vg, 0, 0, ringR)
            nvgStrokeColor(vg, nvgRGBA(255,215,0, math.floor(alpha*180*(1-fx.ringScale*0.3))))
            nvgStrokeWidth(vg, 2.5*(1-progress*0.5)); nvgStroke(vg)
            local glow = nvgRadialGradient(vg,0,0,0,ringR*0.8,
                nvgRGBA(255,230,100,math.floor(alpha*60)),nvgRGBA(255,200,50,0))
            nvgBeginPath(vg); nvgCircle(vg,0,0,ringR*0.8)
            nvgFillPaint(vg,glow); nvgFill(vg)
        end

        for _, p in ipairs(fx.particles) do
            if p.life > 0 then
                local pa = (p.life/p.maxLife)*alpha
                local r,g,b = hueToRgb(p.hue)
                nvgBeginPath(vg); nvgCircle(vg,p.x,p.y,p.size*pa)
                nvgFillColor(vg,nvgRGBA(r,g,b,math.floor(pa*220))); nvgFill(vg)
            end
        end

        if fx.label and alpha > 0.1 then
            local labelY = -50 * fx.ringScale
            nvgFontFace(vg,"sans"); nvgFontSize(vg,14)
            nvgTextAlign(vg,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            nvgFillColor(vg,nvgRGBA(255,240,180,math.floor(alpha*240)))
            nvgText(vg,0,labelY,fx.label,nil)
        end
        nvgRestore(vg)
    end
end

-- ============================================================================
-- 对手融合动画 — 不变
-- ============================================================================

local opponentFuseAnim = {}

function M.setOpponentFuseAnim(anim) opponentFuseAnim = anim end
function M.getOpponentFuseAnim()    return opponentFuseAnim end

local function updateOpponentFuseAnim(dt)
    if opponentFuseAnim.phase == "active" then
        opponentFuseAnim.timer = opponentFuseAnim.timer + dt
        if opponentFuseAnim.timer >= opponentFuseAnim.duration then
            opponentFuseAnim.phase = "done"
        end
    end
end

function M.drawOpponentFuseAnim()
    if opponentFuseAnim.phase ~= "active" then return end
    local progress = opponentFuseAnim.timer / opponentFuseAnim.duration
    local alpha    = progress < 0.7 and math.min(1, progress/0.2)
                     or (1.0 - (progress-0.7)/0.3)
    local cx, cy   = logicalW/2, 45

    nvgSave(vg)
    for i = 1, opponentFuseAnim.count do
        local offsetX    = (i - (opponentFuseAnim.count+1)/2) * 50
        local pulseScale = 1.0 + 0.2*math.sin(progress*math.pi*4+i)
        local glow = nvgRadialGradient(vg,cx+offsetX,cy,0,25*pulseScale,
            nvgRGBA(200,150,255,math.floor(alpha*150)),nvgRGBA(150,100,200,0))
        nvgBeginPath(vg); nvgCircle(vg,cx+offsetX,cy,25*pulseScale)
        nvgFillPaint(vg,glow); nvgFill(vg)
        nvgBeginPath(vg); nvgRoundedRect(vg,cx+offsetX-15,cy-20,30,40,4)
        nvgStrokeColor(vg,nvgRGBA(200,150,255,math.floor(alpha*120)))
        nvgStrokeWidth(vg,1.5); nvgStroke(vg)
        nvgFontFace(vg,"sans"); nvgFontSize(vg,16)
        nvgTextAlign(vg,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
        nvgFillColor(vg,nvgRGBA(200,150,255,math.floor(alpha*180)))
        nvgText(vg,cx+offsetX,cy,"?",nil)
    end
    nvgFontFace(vg,"sans"); nvgFontSize(vg,11)
    nvgTextAlign(vg,NVG_ALIGN_CENTER+NVG_ALIGN_TOP)
    nvgFillColor(vg,nvgRGBA(200,150,255,math.floor(alpha*200)))
    nvgText(vg,cx,cy+30,"对手融合了 "..opponentFuseAnim.count.." 组...",nil)
    nvgRestore(vg)
end

-- ============================================================================
-- 阶段过渡 — 不变
-- ============================================================================

local phaseTrans = { text="", timer=0, duration=1.2, r=180, g=120, b=255 }

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
    nvgFontFace(vg, "bold"); nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 对比色投影（HSV旋转155°）
    nvgFillColor(vg, shadowColor(tr, tg, tb, math.floor(alpha * 210)))
    nvgText(vg, 2.5, 3.5, phaseTrans.text, nil)

    -- 近距内描（同色系略暗，增加立体感）
    nvgFillColor(vg, nvgRGBA(
        math.floor(tr * 0.65), math.floor(tg * 0.65), math.floor(tb * 0.65),
        math.floor(alpha * 160)))
    nvgText(vg, 1, 1.5, phaseTrans.text, nil)

    -- 主色
    nvgFillColor(vg, nvgRGBA(tr, tg, tb, math.floor(alpha * 255)))
    nvgText(vg, 0, 0, phaseTrans.text, nil)

    -- 白色高光
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 85)))
    nvgText(vg, -1, -1.5, phaseTrans.text, nil)

    nvgRestore(vg)
end

-- ============================================================================
-- 补牌特效 (Reshuffle Effect) — 不变
-- ============================================================================

local reshuffleCards = {}
local deckGlow = { active=false, timer=0, duration=0.8, intensity=0 }

function M.triggerReshuffle(cardCount)
    cardCount   = cardCount or 8
    local count = math.min(cardCount, 14)
    M.spawnBanner("补牌！", 120, 200, 255, 32, 2.0)
    M.triggerShake(3, 0.25, 30)
    -- 与 drawDeckAndDiscard 卡背堆位置对齐
    local sx = logicalW - 36; local sy = 180   -- 弃牌堆中心
    local tx = logicalW - 36; local ty = 80    -- 牌库堆中心
    for i = 1, count do
        local delay    = (i-1)*0.04 + math.random()*0.03
        local duration = 0.45 + math.random()*0.25
        reshuffleCards[#reshuffleCards+1] = {
            sx = sx+(math.random()-0.5)*20, sy = sy+(math.random()-0.5)*14,
            tx = tx+(math.random()-0.5)*8,  ty = ty+(math.random()-0.5)*8,
            arcOffX = -30-math.random()*50, arcOffY = -20-math.random()*30,
            delay=delay, duration=duration, timer=-delay,
            hue = 200+math.random()*60, arrived=false,
        }
    end
    local lastArrival = (count-1)*0.04 + 0.55
    deckGlow.active   = false
    deckGlow._pending = lastArrival
    deckGlow._pendingT = 0
end

function M.getDeckGlowState()
    if not deckGlow.active then return 0 end
    local t = deckGlow.timer / deckGlow.duration
    return math.sin(t*math.pi) * deckGlow.intensity
end

local function updateReshuffle(dt)
    if deckGlow._pending and deckGlow._pending > 0 then
        deckGlow._pendingT = deckGlow._pendingT + dt
        if deckGlow._pendingT >= deckGlow._pending then
            deckGlow.active = true; deckGlow.timer = 0
            deckGlow.intensity = 1.0; deckGlow._pending = nil
        end
    end
    if deckGlow.active then
        deckGlow.timer = deckGlow.timer + dt
        if deckGlow.timer >= deckGlow.duration then deckGlow.active = false end
    end
    for i = #reshuffleCards, 1, -1 do
        local p = reshuffleCards[i]
        p.timer = p.timer + dt
        if p.timer >= p.duration then table.remove(reshuffleCards, i) end
    end
end

function M.drawReshuffleEffect()
    if #reshuffleCards == 0 then return end
    for _, p in ipairs(reshuffleCards) do
        if p.timer <= 0 then goto skip_rc end
        local t   = math.min(1.0, p.timer/p.duration)
        local mx  = (p.sx+p.tx)/2 + p.arcOffX
        local my  = (p.sy+p.ty)/2 + p.arcOffY
        local omt = 1-t
        local px  = omt*omt*p.sx + 2*omt*t*mx + t*t*p.tx
        local py  = omt*omt*p.sy + 2*omt*t*my + t*t*p.ty
        local alpha = t<0.15 and t/0.15 or (t>0.75 and (1-t)/0.25 or 1.0)
        alpha = math.max(0, math.min(1, alpha))
        local scale = 0.38*(1.0-t*0.25)
        local r,g,b = hueToRgb(p.hue + t*30)
        local tanX = 2*(1-t)*(mx-p.sx) + 2*t*(p.tx-mx)
        local tanY = 2*(1-t)*(my-p.sy) + 2*t*(p.ty-my)
        local angle = math.atan(tanY,tanX)
        local cw,ch,cr = 90*scale, 130*scale, 8*scale

        nvgSave(vg)
        nvgTranslate(vg,px,py); nvgRotate(vg,angle)
        local glow = nvgRadialGradient(vg,0,0,0,cw*1.4,
            nvgRGBA(r,g,b,math.floor(alpha*60)),nvgRGBA(r,g,b,0))
        nvgBeginPath(vg); nvgRect(vg,-cw*1.4,-ch*1.4,cw*2.8,ch*2.8)
        nvgFillPaint(vg,glow); nvgFill(vg)
        nvgGlobalAlpha(vg, alpha)
        nvgScale(vg, scale, scale)
        Card.drawBackBase(vg, Card.WIDTH/2, Card.HEIGHT/2,
            Card.WIDTH, Card.HEIGHT, Card.RADIUS, gameTime, 0, 0)
        nvgRestore(vg)
        ::skip_rc::
    end
end

-- ============================================================================
-- 统一 update / reset
-- ============================================================================

function M.updateAll(dt)
    updateShake(dt)
    updateBanners(dt)
    updateChips(dt)
    updatePotPulse(dt)
    updatePopups(dt)
    updateFuseEffects(dt)
    updateOpponentFuseAnim(dt)
    updateTransition(dt)
    updateReshuffle(dt)
end

function M.resetAll()
    shake.intensity = 0; shake.offsetX = 0; shake.offsetY = 0
    actionBanners  = {}
    chipParticles  = {}
    potPulse.active = false
    scorePopups    = {}
    fuseEffects    = {}
    opponentFuseAnim = {}
    phaseTrans.timer = 0
    reshuffleCards = {}
    deckGlow.active = false
end

return M
