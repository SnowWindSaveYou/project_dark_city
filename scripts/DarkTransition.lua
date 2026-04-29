-- ============================================================================
-- DarkTransition.lua - 暗面世界过渡转场 (NanoVG 叠加层)
--
-- 三种过渡类型:
--   1. Enter  - 从现实世界进入暗面世界 (~2.8s)
--   2. Exit   - 从暗面世界返回现实世界 (~2.2s)
--   3. Layer  - 暗面世界层间切换 (~2.0s)
--
-- 设计原则:
--   - 纯视觉叠加层, 不干预卡牌逻辑 (undeal/deal 在遮罩下同步进行)
--   - 遮罩不透明时段 > 卡牌切换耗时, 确保用户看不到底层重建
--   - onComplete 回调在过渡结束时触发, 用于恢复交互
--   - 风格参考 DateTransition.lua 的多阶段动画序列
-- ============================================================================

local Theme = require "Theme"

local M = {}

-- ---------------------------------------------------------------------------
-- Easing 函数
-- ---------------------------------------------------------------------------

local function clamp01(t)
    if t < 0 then return 0 end
    if t > 1 then return 1 end
    return t
end

local function easeOutCubic(t) t = t - 1; return t * t * t + 1 end
local function easeInCubic(t) return t * t * t end
local function easeOutQuad(t) return 1 - (1 - t) * (1 - t) end
local function easeInQuad(t) return t * t end

local function easeOutBack(t)
    local c = 1.70158; t = t - 1
    return t * t * ((c + 1) * t + c) + 1
end

local function easeInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    t = t - 1
    return 1 + 4 * t * t * t
end

local function easeOutElastic(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local p = 0.4
    return math.pow(2, -10 * t) * math.sin((t - p / 4) * (2 * math.pi) / p) + 1
end

-- ---------------------------------------------------------------------------
-- 时间轴常量
-- ---------------------------------------------------------------------------

-- Enter: 白闪 → 紫黑吞噬 → 裂隙纹 → 层名显示 → 揭幕
local ENTER = {
    TOTAL       = 2.8,
    FLASH_END   = 0.20,     -- 白闪
    COVER_START = 0.10,     -- 紫黑幕布开始展开
    COVER_END   = 0.65,     -- 幕布完全覆盖
    CRACK_START = 0.50,     -- 裂纹出现
    CRACK_END   = 1.80,     -- 裂纹消失
    INFO_START  = 0.80,     -- 层名+图标
    INFO_END    = 2.00,     -- 层名淡出
    REVEAL_START = 2.00,    -- 幕布开始退出
    REVEAL_END  = 2.80,     -- 完全揭幕
}

-- Exit: 暗幕收紧 → 白光爆发 → 文字 → 渐淡 → 眨眼
local EXIT = {
    TOTAL       = 2.2,
    DARKEN_END  = 0.35,     -- 暗幕覆盖
    WHITE_START = 0.35,     -- 白光爆发
    WHITE_END   = 0.65,     -- 白光巅峰
    TEXT_START  = 0.55,     -- "返回现实" 文字
    TEXT_END    = 1.40,     -- 文字消失
    FADE_START  = 1.00,     -- 整体淡出
    FADE_END    = 1.80,     -- 淡出完成
    BLINK_START = 1.80,     -- 眨眼效果
    BLINK_END   = 2.20,     -- 完成
}

-- Layer: 水平裂缝 → 上下推移 → 层名 → 回收
local LAYER = {
    TOTAL       = 2.0,
    CRACK_START = 0.0,      -- 中央裂缝出现
    CRACK_END   = 0.25,     -- 裂缝拉开
    PUSH_START  = 0.20,     -- 上下幕布推开
    PUSH_END    = 0.55,     -- 完全遮盖
    INFO_START  = 0.50,     -- 层名
    INFO_END    = 1.20,     -- 层名淡出
    RETRACT_START = 1.10,   -- 幕布回收
    RETRACT_END = 1.90,     -- 完全收回
    GLOW_END    = 2.00,     -- 余辉消散
}

-- ---------------------------------------------------------------------------
-- 层级视觉配置
-- ---------------------------------------------------------------------------

local LAYER_COLORS = {
    -- Layer 1: 表层·暗巷 → 紫色系
    { r = 139, g = 92, b = 246 },   -- darkAccent 紫
    -- Layer 2: 中层·暗市 → 靛蓝系
    { r = 99, g = 102, b = 241 },   -- darkPassage 靛蓝
    -- Layer 3: 深层·暗渊 → 暗红系
    { r = 220, g = 38, b = 38 },    -- darkAbyss 红
}

local LAYER_ICONS = { "🌑", "🏪", "💀" }

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------

---@type table 内部状态
local state = {
    active     = false,
    type       = "none",   -- "enter" | "exit" | "layer"
    timer      = 0,
    onComplete = nil,

    -- Enter/Layer 附加信息
    layerName  = "",
    layerIdx   = 1,

    -- 裂隙种子 (用于随机裂纹路径, 每次过渡不同)
    crackSeed  = 0,

    -- 背景图 handle
    bgImage    = -1,
    bgLoaded   = false,
    bgAspect   = 16 / 9,
    bgSizeQueried = false,
}

-- ---------------------------------------------------------------------------
-- 裂纹路径生成 (基于种子的伪随机, 确保同一次过渡内稳定)
-- ---------------------------------------------------------------------------

---@type {x: number, y: number}[][]
local crackPaths = {}

--- 用简单 LCG 生成伪随机
local function seededRandom(seed)
    seed = (seed * 1103515245 + 12345) % (2 ^ 31)
    return seed, (seed % 10000) / 10000
end

--- 生成一条裂纹路径 (从中心向外)
---@param cx number 起点 X
---@param cy number 起点 Y
---@param angle number 初始角度 (弧度)
---@param length number 总长度
---@param seed number
---@return {x: number, y: number}[]
local function generateCrackPath(cx, cy, angle, length, seed)
    local path = { { x = cx, y = cy } }
    local segments = math.floor(length / 12) + 3
    local segLen = length / segments
    local curAngle = angle

    for i = 1, segments do
        local rVal
        seed, rVal = seededRandom(seed)
        curAngle = curAngle + (rVal - 0.5) * 0.8   -- 随机偏转
        local nx = path[#path].x + math.cos(curAngle) * segLen
        local ny = path[#path].y + math.sin(curAngle) * segLen
        path[#path + 1] = { x = nx, y = ny }
    end
    return path
end

--- 生成全屏裂纹路径组
local function generateCracks(cx, cy, diagLen, seed)
    crackPaths = {}
    local crackCount = 5 + (seed % 4)  -- 5~8 条主裂纹
    for i = 1, crackCount do
        local angle = (i - 1) * (2 * math.pi / crackCount) + (seed % 100) / 100 * 0.5
        local length = diagLen * (0.2 + (seed % 50) / 100 * 0.3)
        local path = generateCrackPath(cx, cy, angle, length, seed + i * 7919)
        crackPaths[#crackPaths + 1] = path
    end
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

function M.init(vg)
    state.bgImage = nvgCreateImage(vg, "image/edited_都市天际线_暗夜版_20260426105650.png", 0)
    state.bgLoaded = state.bgImage and state.bgImage > 0
    state.bgSizeQueried = false
    print("[DarkTransition] Init, bg image loaded: " .. tostring(state.bgLoaded))
end

--- 播放进入暗面世界过渡
---@param layerName string 层名 (如 "表层·暗巷")
---@param layerIdx number 1-3
---@param onComplete function 过渡完成回调
function M.playEnter(layerName, layerIdx, onComplete)
    state.active     = true
    state.type       = "enter"
    state.timer      = 0
    state.layerName  = layerName or "暗面世界"
    state.layerIdx   = layerIdx or 1
    state.onComplete = onComplete
    state.crackSeed  = math.floor(math.random() * 100000)
    crackPaths = {}  -- 延迟到 draw 时生成 (需要屏幕尺寸)
    print("[DarkTransition] Play ENTER → " .. state.layerName)
end

--- 播放退出暗面世界过渡
---@param onComplete function
function M.playExit(onComplete)
    state.active     = true
    state.type       = "exit"
    state.timer      = 0
    state.layerName  = ""
    state.layerIdx   = 1
    state.onComplete = onComplete
    state.crackSeed  = math.floor(math.random() * 100000)
    crackPaths = {}
    print("[DarkTransition] Play EXIT")
end

--- 播放层间切换过渡
---@param layerName string 目标层名
---@param layerIdx number 1-3
---@param onComplete function
function M.playLayerChange(layerName, layerIdx, onComplete)
    state.active     = true
    state.type       = "layer"
    state.timer      = 0
    state.layerName  = layerName or "未知区域"
    state.layerIdx   = layerIdx or 1
    state.onComplete = onComplete
    state.crackSeed  = math.floor(math.random() * 100000)
    crackPaths = {}
    print("[DarkTransition] Play LAYER → " .. state.layerName)
end

function M.isActive()
    return state.active
end

function M.update(dt)
    if not state.active then return end
    state.timer = state.timer + dt

    local total
    if state.type == "enter" then total = ENTER.TOTAL
    elseif state.type == "exit" then total = EXIT.TOTAL
    elseif state.type == "layer" then total = LAYER.TOTAL
    else total = 0
    end

    if state.timer >= total then
        state.active = false
        if state.onComplete then
            state.onComplete()
        end
    end
end

-- ---------------------------------------------------------------------------
-- 辅助: 获取层级颜色
-- ---------------------------------------------------------------------------

local function getLayerColor(idx)
    return LAYER_COLORS[idx] or LAYER_COLORS[1]
end

-- ---------------------------------------------------------------------------
-- 辅助: 背景图 cover 模式 (暗夜天际线)
-- ---------------------------------------------------------------------------

local function drawBgCover(vg, w, h, alpha)
    if not state.bgLoaded or state.bgImage <= 0 then return end

    if not state.bgSizeQueried then
        state.bgSizeQueried = true
        local iw, ih = nvgImageSize(vg, state.bgImage)
        if iw and ih and iw > 0 and ih > 0 then
            state.bgAspect = iw / ih
        end
    end

    local screenAspect = w / h
    local drawW, drawH, drawX, drawY
    if state.bgAspect > screenAspect then
        drawH = h
        drawW = h * state.bgAspect
        drawX = (w - drawW) * 0.5
        drawY = 0
    else
        drawW = w
        drawH = w / state.bgAspect
        drawX = 0
        drawY = (h - drawH) * 0.5
    end

    local imgPaint = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, state.bgImage, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, -10, -10, w + 20, h + 20)
    nvgFillPaint(vg, imgPaint)
    nvgFill(vg)
end

-- ---------------------------------------------------------------------------
-- 辅助: 绘制裂纹 (发光路径)
-- ---------------------------------------------------------------------------

local function drawCracks(vg, cx, cy, progress, alpha, lc)
    if #crackPaths == 0 then return end

    for _, path in ipairs(crackPaths) do
        local visiblePts = math.floor(#path * progress)
        if visiblePts < 2 then goto nextCrack end

        -- 发光底层 (粗, 低透明度)
        nvgBeginPath(vg)
        nvgMoveTo(vg, path[1].x, path[1].y)
        for i = 2, visiblePts do
            nvgLineTo(vg, path[i].x, path[i].y)
        end
        nvgStrokeColor(vg, nvgRGBA(lc.r, lc.g, lc.b, math.floor(alpha * 80)))
        nvgStrokeWidth(vg, 6)
        nvgStroke(vg)

        -- 中间层 (中等)
        nvgBeginPath(vg)
        nvgMoveTo(vg, path[1].x, path[1].y)
        for i = 2, visiblePts do
            nvgLineTo(vg, path[i].x, path[i].y)
        end
        nvgStrokeColor(vg, nvgRGBA(lc.r, lc.g, lc.b, math.floor(alpha * 160)))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)

        -- 明亮核心
        nvgBeginPath(vg)
        nvgMoveTo(vg, path[1].x, path[1].y)
        for i = 2, visiblePts do
            nvgLineTo(vg, path[i].x, path[i].y)
        end
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 200)))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)

        ::nextCrack::
    end
end

-- ---------------------------------------------------------------------------
-- 辅助: 绘制发光文字 (带 fontBlur 辉光)
-- ---------------------------------------------------------------------------

local function drawGlowText(vg, x, y, text, fontSize, lc, alpha)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 辉光层 (大号 blur)
    nvgFontSize(vg, fontSize)
    nvgFontBlur(vg, 8)
    nvgFillColor(vg, nvgRGBA(lc.r, lc.g, lc.b, math.floor(alpha * 120)))
    nvgText(vg, x, y, text, nil)

    -- 中间辉光
    nvgFontBlur(vg, 3)
    nvgFillColor(vg, nvgRGBA(lc.r, lc.g, lc.b, math.floor(alpha * 180)))
    nvgText(vg, x, y, text, nil)

    -- 清晰文字
    nvgFontBlur(vg, 0)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 255)))
    nvgText(vg, x, y, text, nil)
end

-- ---------------------------------------------------------------------------
-- 辅助: 绘制发光图标 (Emoji)
-- ---------------------------------------------------------------------------

local function drawGlowIcon(vg, x, y, icon, fontSize, lc, alpha)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    nvgFontSize(vg, fontSize)
    nvgFontBlur(vg, 6)
    nvgFillColor(vg, nvgRGBA(lc.r, lc.g, lc.b, math.floor(alpha * 100)))
    nvgText(vg, x, y, icon, nil)

    nvgFontBlur(vg, 0)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 255)))
    nvgText(vg, x, y, icon, nil)
end

-- ============================================================================
-- ENTER 过渡绘制
-- ============================================================================

local function drawEnter(vg, w, h)
    local t = state.timer
    local cx, cy = w * 0.5, h * 0.5
    local diagLen = math.sqrt(w * w + h * h)
    local lc = getLayerColor(state.layerIdx)

    -- 延迟生成裂纹
    if #crackPaths == 0 then
        generateCracks(cx, cy, diagLen, state.crackSeed)
    end

    -- === Phase 1: 白闪 ===
    if t < ENTER.FLASH_END then
        local flashP = clamp01(t / ENTER.FLASH_END)
        -- 快速升到峰值再衰减
        local flashAlpha
        if flashP < 0.4 then
            flashAlpha = flashP / 0.4
        else
            flashAlpha = 1.0 - (flashP - 0.4) / 0.6
        end
        flashAlpha = flashAlpha * 0.85

        nvgBeginPath(vg)
        nvgRect(vg, -10, -10, w + 20, h + 20)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(flashAlpha * 255)))
        nvgFill(vg)
    end

    -- === Phase 2: 紫黑幕布覆盖 (从中心径向展开) ===
    local coverP = 0
    if t >= ENTER.COVER_START then
        coverP = clamp01((t - ENTER.COVER_START) / (ENTER.COVER_END - ENTER.COVER_START))
        coverP = easeOutCubic(coverP)
    end

    -- 幕布退出
    local revealP = 0
    if t >= ENTER.REVEAL_START then
        revealP = clamp01((t - ENTER.REVEAL_START) / (ENTER.REVEAL_END - ENTER.REVEAL_START))
        revealP = easeInCubic(revealP)
    end

    local coverAlpha = coverP * (1.0 - revealP)

    if coverAlpha > 0.001 then
        -- 背景图 (暗夜天际线, 在幕布下方)
        local bgAlpha = coverAlpha * 0.5
        drawBgCover(vg, w, h, bgAlpha)

        -- 紫黑径向渐变幕布
        local maxR = diagLen * 0.75
        local currentR = maxR * coverP

        -- 核心暗区 (从中心向外)
        nvgBeginPath(vg)
        nvgRect(vg, -10, -10, w + 20, h + 20)
        local coverGrad = nvgRadialGradient(vg, cx, cy,
            currentR * 0.3, currentR,
            nvgRGBA(13, 15, 26, math.floor(coverAlpha * 240)),   -- darkBgTop
            nvgRGBA(26, 16, 37, math.floor(coverAlpha * 220))    -- darkBgBottom
        )
        nvgFillPaint(vg, coverGrad)
        nvgFill(vg)

        -- 边缘紫光辉 (径向渐变边缘)
        nvgBeginPath(vg)
        nvgRect(vg, -10, -10, w + 20, h + 20)
        local edgeGrad = nvgRadialGradient(vg, cx, cy,
            currentR * 0.6, currentR * 1.1,
            nvgRGBA(0, 0, 0, 0),
            nvgRGBA(lc.r, lc.g, lc.b, math.floor(coverAlpha * 40))
        )
        nvgFillPaint(vg, edgeGrad)
        nvgFill(vg)
    end

    -- === Phase 3: 裂纹 ===
    if t >= ENTER.CRACK_START and t < ENTER.CRACK_END then
        local crackGrow = clamp01((t - ENTER.CRACK_START) / 0.4)
        crackGrow = easeOutQuad(crackGrow)
        local crackFade = 1.0
        if t > ENTER.CRACK_END - 0.4 then
            crackFade = clamp01((ENTER.CRACK_END - t) / 0.4)
        end
        drawCracks(vg, cx, cy, crackGrow, crackFade * coverAlpha, lc)
    end

    -- === Phase 4: 层信息显示 ===
    if t >= ENTER.INFO_START and t < ENTER.INFO_END then
        local infoIn = clamp01((t - ENTER.INFO_START) / 0.3)
        infoIn = easeOutBack(infoIn)
        local infoOut = 1.0
        if t > ENTER.INFO_END - 0.3 then
            infoOut = clamp01((ENTER.INFO_END - t) / 0.3)
            infoOut = easeInQuad(infoOut)
        end
        local infoAlpha = infoIn * infoOut * coverAlpha

        if infoAlpha > 0.01 then
            local iconY = cy - h * 0.06
            local nameY = cy + h * 0.05

            -- 图标
            local icon = LAYER_ICONS[state.layerIdx] or "🌑"
            local iconScale = 0.6 + 0.4 * infoIn
            drawGlowIcon(vg, cx, iconY, icon, h * 0.08 * iconScale, lc, infoAlpha)

            -- 层名
            drawGlowText(vg, cx, nameY, state.layerName, h * 0.055, lc, infoAlpha)

            -- 副标题 "—— 进入暗面世界 ——"
            local subAlpha = infoAlpha * 0.7
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, h * 0.025)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontBlur(vg, 0)
            nvgFillColor(vg, nvgRGBA(200, 200, 220, math.floor(subAlpha * 255)))
            nvgText(vg, cx, nameY + h * 0.055, "—— 进入暗面世界 ——", nil)
        end
    end

    -- === 中心光点 (贯穿全程的微妙呼吸光) ===
    if coverAlpha > 0.1 then
        local pulse = 0.5 + 0.5 * math.sin(state.timer * 4.0)
        local glowR = h * 0.08 * (0.8 + 0.2 * pulse)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, glowR)
        local glowGrad = nvgRadialGradient(vg, cx, cy, 0, glowR,
            nvgRGBA(lc.r, lc.g, lc.b, math.floor(coverAlpha * 30 * pulse)),
            nvgRGBA(lc.r, lc.g, lc.b, 0)
        )
        nvgFillPaint(vg, glowGrad)
        nvgFill(vg)
    end
end

-- ============================================================================
-- EXIT 过渡绘制
-- ============================================================================

local function drawExit(vg, w, h)
    local t = state.timer
    local cx, cy = w * 0.5, h * 0.5
    local diagLen = math.sqrt(w * w + h * h)

    -- === Phase 1: 暗幕收紧 ===
    local darkenP = clamp01(t / EXIT.DARKEN_END)
    darkenP = easeInQuad(darkenP)

    -- 整体淡出 (Phase 4-5)
    local fadeP = 0
    if t >= EXIT.FADE_START then
        fadeP = clamp01((t - EXIT.FADE_START) / (EXIT.FADE_END - EXIT.FADE_START))
        fadeP = easeOutCubic(fadeP)
    end

    local masterAlpha = (1.0 - fadeP)

    -- 暗幕 (从边缘向中心收紧, 然后被白光替代)
    if darkenP > 0.001 and masterAlpha > 0.001 then
        local darkAlpha = darkenP * masterAlpha

        nvgBeginPath(vg)
        nvgRect(vg, -10, -10, w + 20, h + 20)
        nvgFillColor(vg, nvgRGBA(10, 8, 20, math.floor(darkAlpha * 230)))
        nvgFill(vg)

        -- 紫色边缘辉光
        local edgeR = diagLen * 0.5 * (1.0 - darkenP * 0.3)
        nvgBeginPath(vg)
        nvgRect(vg, -10, -10, w + 20, h + 20)
        local edgeGrad = nvgRadialGradient(vg, cx, cy, edgeR * 0.5, edgeR,
            nvgRGBA(0, 0, 0, 0),
            nvgRGBA(139, 92, 246, math.floor(darkAlpha * 50))
        )
        nvgFillPaint(vg, edgeGrad)
        nvgFill(vg)
    end

    -- === Phase 2: 白光爆发 (从中心向外) ===
    if t >= EXIT.WHITE_START and masterAlpha > 0.001 then
        local whiteP = clamp01((t - EXIT.WHITE_START) / (EXIT.WHITE_END - EXIT.WHITE_START))
        whiteP = easeOutQuad(whiteP)

        local whiteDecay = 1.0
        if t > EXIT.WHITE_END then
            whiteDecay = clamp01(1.0 - (t - EXIT.WHITE_END) / 0.5)
        end

        local whiteR = diagLen * 0.6 * whiteP
        local whiteAlpha = whiteP * whiteDecay * masterAlpha

        nvgBeginPath(vg)
        nvgRect(vg, -10, -10, w + 20, h + 20)
        local whiteGrad = nvgRadialGradient(vg, cx, cy, 0, whiteR,
            nvgRGBA(255, 255, 255, math.floor(whiteAlpha * 200)),
            nvgRGBA(200, 220, 255, 0)
        )
        nvgFillPaint(vg, whiteGrad)
        nvgFill(vg)
    end

    -- === Phase 3: "返回现实" 文字 ===
    if t >= EXIT.TEXT_START and t < EXIT.TEXT_END then
        local textIn = clamp01((t - EXIT.TEXT_START) / 0.25)
        textIn = easeOutBack(textIn)
        local textOut = 1.0
        if t > EXIT.TEXT_END - 0.3 then
            textOut = clamp01((EXIT.TEXT_END - t) / 0.3)
        end
        local textAlpha = textIn * textOut * masterAlpha

        if textAlpha > 0.01 then
            -- 浅蓝光晕文字
            local blueC = { r = 135, g = 195, b = 235 }
            drawGlowText(vg, cx, cy - h * 0.02, "返回现实", h * 0.06, blueC, textAlpha)

            -- 副标题
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, h * 0.025)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontBlur(vg, 0)
            nvgFillColor(vg, nvgRGBA(180, 210, 240, math.floor(textAlpha * 180)))
            nvgText(vg, cx, cy + h * 0.04, "—— ☀️ ——", nil)
        end
    end

    -- === Phase 5: 眨眼效果 (上下黑条闭合再打开) ===
    if t >= EXIT.BLINK_START then
        local blinkP = clamp01((t - EXIT.BLINK_START) / (EXIT.BLINK_END - EXIT.BLINK_START))
        -- 先闭合再打开: sin 曲线峰值在中间
        local blinkClose = math.sin(blinkP * math.pi)
        local barH = h * 0.5 * blinkClose * 0.6  -- 最多覆盖 30% 高度

        if barH > 0.5 then
            nvgBeginPath(vg)
            nvgRect(vg, -10, -10, w + 20, barH + 10)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRect(vg, -10, h - barH, w + 20, barH + 10)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            nvgFill(vg)
        end
    end
end

-- ============================================================================
-- LAYER 过渡绘制
-- ============================================================================

local function drawLayer(vg, w, h)
    local t = state.timer
    local cx, cy = w * 0.5, h * 0.5
    local lc = getLayerColor(state.layerIdx)

    -- === Phase 1: 中央水平裂缝 ===
    local crackP = clamp01((t - LAYER.CRACK_START) / (LAYER.CRACK_END - LAYER.CRACK_START))
    crackP = easeOutQuad(crackP)

    -- === Phase 2: 上下幕布推开 (从中线向上下展开) ===
    local pushP = 0
    if t >= LAYER.PUSH_START then
        pushP = clamp01((t - LAYER.PUSH_START) / (LAYER.PUSH_END - LAYER.PUSH_START))
        pushP = easeOutCubic(pushP)
    end

    -- === Phase 5: 幕布回收 ===
    local retractP = 0
    if t >= LAYER.RETRACT_START then
        retractP = clamp01((t - LAYER.RETRACT_START) / (LAYER.RETRACT_END - LAYER.RETRACT_START))
        retractP = easeInCubic(retractP)
    end

    -- 幕布高度: 从0到半屏再回0
    local maskH = h * 0.5 * pushP * (1.0 - retractP)

    -- 中央裂缝发光线 (在幕布出现前就开始)
    if crackP > 0.01 and retractP < 0.99 then
        local lineLen = w * crackP
        local lineAlpha = (1.0 - retractP)
        local pulse = 0.7 + 0.3 * math.sin(t * 8.0)

        -- 发光底层
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - lineLen * 0.5, cy)
        nvgLineTo(vg, cx + lineLen * 0.5, cy)
        nvgStrokeColor(vg, nvgRGBA(lc.r, lc.g, lc.b, math.floor(lineAlpha * 80 * pulse)))
        nvgStrokeWidth(vg, 8)
        nvgStroke(vg)

        -- 明亮核心
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - lineLen * 0.5, cy)
        nvgLineTo(vg, cx + lineLen * 0.5, cy)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(lineAlpha * 220 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- 上下幕布
    if maskH > 0.5 then
        -- 上半幕布 (从中线向上)
        nvgBeginPath(vg)
        nvgRect(vg, -10, cy - maskH, w + 20, maskH + 2)
        local topGrad = nvgLinearGradient(vg, 0, cy - maskH, 0, cy,
            nvgRGBA(13, 15, 26, 245),     -- 顶部深色
            nvgRGBA(26, 16, 37, 230)      -- 中线附近略紫
        )
        nvgFillPaint(vg, topGrad)
        nvgFill(vg)

        -- 下半幕布 (从中线向下)
        nvgBeginPath(vg)
        nvgRect(vg, -10, cy - 2, w + 20, maskH + 2)
        local botGrad = nvgLinearGradient(vg, 0, cy, 0, cy + maskH,
            nvgRGBA(26, 16, 37, 230),
            nvgRGBA(13, 15, 26, 245)
        )
        nvgFillPaint(vg, botGrad)
        nvgFill(vg)

        -- 幕布边缘发光线 (上边缘和下边缘)
        local edgeAlpha = (1.0 - retractP) * 0.6

        nvgBeginPath(vg)
        nvgMoveTo(vg, -10, cy - maskH)
        nvgLineTo(vg, w + 10, cy - maskH)
        nvgStrokeColor(vg, nvgRGBA(lc.r, lc.g, lc.b, math.floor(edgeAlpha * 120)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        nvgBeginPath(vg)
        nvgMoveTo(vg, -10, cy + maskH)
        nvgLineTo(vg, w + 10, cy + maskH)
        nvgStrokeColor(vg, nvgRGBA(lc.r, lc.g, lc.b, math.floor(edgeAlpha * 120)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- === Phase 3: 层信息 ===
    if t >= LAYER.INFO_START and t < LAYER.INFO_END then
        local infoIn = clamp01((t - LAYER.INFO_START) / 0.25)
        infoIn = easeOutBack(infoIn)
        local infoOut = 1.0
        if t > LAYER.INFO_END - 0.25 then
            infoOut = clamp01((LAYER.INFO_END - t) / 0.25)
        end
        local infoAlpha = infoIn * infoOut

        if infoAlpha > 0.01 then
            local icon = LAYER_ICONS[state.layerIdx] or "🌑"
            drawGlowIcon(vg, cx, cy - h * 0.04, icon, h * 0.07, lc, infoAlpha)
            drawGlowText(vg, cx, cy + h * 0.04, state.layerName, h * 0.045, lc, infoAlpha)
        end
    end

    -- === 余辉光点 (回收后残留) ===
    if t >= LAYER.RETRACT_START and t < LAYER.GLOW_END then
        local glowP = clamp01((t - LAYER.RETRACT_START) / (LAYER.GLOW_END - LAYER.RETRACT_START))
        local glowAlpha = (1.0 - glowP) * 0.4

        nvgBeginPath(vg)
        local glowR = h * 0.03 * (1.0 + glowP)
        nvgCircle(vg, cx, cy, glowR)
        local residualGrad = nvgRadialGradient(vg, cx, cy, 0, glowR,
            nvgRGBA(lc.r, lc.g, lc.b, math.floor(glowAlpha * 255)),
            nvgRGBA(lc.r, lc.g, lc.b, 0)
        )
        nvgFillPaint(vg, residualGrad)
        nvgFill(vg)
    end
end

-- ============================================================================
-- 主绘制入口
-- ============================================================================

function M.draw(vg, logicalW, logicalH, gameTime)
    if not state.active then return end

    nvgSave(vg)

    if state.type == "enter" then
        drawEnter(vg, logicalW, logicalH)
    elseif state.type == "exit" then
        drawExit(vg, logicalW, logicalH)
    elseif state.type == "layer" then
        drawLayer(vg, logicalW, logicalH)
    end

    nvgRestore(vg)
end

return M
