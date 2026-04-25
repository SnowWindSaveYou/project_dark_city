-- ============================================================================
-- DateTransition.lua - P4 风格日期转场 (多阶段动画序列)
-- Phase 1: 蓝色遮罩从左下向右上擦过遮住屏幕
-- Phase 2: 遮罩缩窄为对角光带 + 背景图淡入
-- Phase 3: 日期 UI 沿对角线从左下到右上逐个弹跳出现 + 白线延伸
-- Phase 4: 所有数字沿对角线弹性滚动一格 + 波纹特效
-- Phase 5: 光带右上滑出, UI 左下滑出(反向分离), 背景淡出
-- ============================================================================

local M = {}

-- ---------------------------------------------------------------------------
-- 角度 & 布局常量
-- ---------------------------------------------------------------------------

local BAND_ANGLE_DEG = -30
local BAND_ANGLE_RAD = math.rad(BAND_ANGLE_DEG)
local COS_A          = math.cos(BAND_ANGLE_RAD)
local SIN_A          = math.sin(BAND_ANGLE_RAD)
-- 垂直于光带方向 (用于擦入运动): 旋转+90°
local PERP_ANGLE_RAD = BAND_ANGLE_RAD + math.pi * 0.5
local COS_P          = math.cos(PERP_ANGLE_RAD)
local SIN_P          = math.sin(PERP_ANGLE_RAD)

local BAND_WIDTH_RATIO = 0.40            -- 最终光带宽度占屏高比
local DATE_COUNT       = 8               -- 显示日期数
local CURRENT_INDEX    = 4               -- 当前日在序列中的索引 (初始位置)

-- ---------------------------------------------------------------------------
-- 动画时间轴
-- ---------------------------------------------------------------------------

local T_WIPE_START     = 0.0      -- Phase 1 开始: 蓝色遮罩擦入
local T_WIPE_END       = 0.45     -- Phase 1 结束: 遮罩完全覆盖屏幕
local T_SHRINK_END     = 0.90     -- Phase 2 结束: 遮罩缩为光带
local T_POPUP_START    = 0.75     -- Phase 3 开始: 日期开始弹出 (与 Phase 2 重叠)
local T_POPUP_STAGGER  = 0.07    -- 每个日期弹出间隔
local T_POPUP_DUR      = 0.35    -- 单个日期弹出动画时长

-- Phase 4: 滚动 + 波纹
local T_SCROLL_START   = 1.60    -- 所有日期弹出完毕后，开始滚动
local T_SCROLL_DUR     = 0.50    -- 弹性滚动时长
local T_RIPPLE_START   = 2.10    -- 滚动结束后波纹开始
local T_RIPPLE_DUR     = 0.65    -- 波纹扩散时长

-- Phase 5: 分离退出
local T_EXIT_START     = 2.80    -- 退出开始
local T_EXIT_DUR       = 0.50    -- 退出时长
local T_BG_FADE_DUR    = 0.40    -- 背景淡出时长（从 T_EXIT_START 开始）
local TOTAL_DUR        = T_EXIT_START + T_EXIT_DUR

-- ---------------------------------------------------------------------------
-- 日期系统常量
-- ---------------------------------------------------------------------------

local BASE_YEAR  = 2026
local BASE_MONTH = 4
local BASE_DAY   = 24
local BASE_MOON_PHASE = 2

local WEEKDAY_NAMES = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }
local MONTH_NAMES   = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
}
local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------

local state = {
    active     = false,
    timer      = 0,
    dayCount   = 1,
    bgImage    = -1,
    bgLoaded   = false,
    onComplete = nil,
}

-- ---------------------------------------------------------------------------
-- 日期计算
-- ---------------------------------------------------------------------------

local function calcDate(dayCount)
    local y, m, d = BASE_YEAR, BASE_MONTH, BASE_DAY + (dayCount - 1)
    while d > DAYS_IN_MONTH[m] do
        d = d - DAYS_IN_MONTH[m]
        m = m + 1
        if m > 12 then m = 1; y = y + 1 end
    end
    return y, m, d
end

local function calcWeekday(y, m, d)
    local dayOfYear = d
    for i = 1, m - 1 do dayOfYear = dayOfYear + DAYS_IN_MONTH[i] end
    dayOfYear = dayOfYear - 1
    return (4 + dayOfYear) % 7 + 1  -- 1=SUN..7=SAT
end

local function calcMoonPhase(dayCount)
    local offset = (dayCount - 1) + BASE_MOON_PHASE * 3.7
    return math.floor((offset % 29.5) / 3.7) % 8
end

-- ---------------------------------------------------------------------------
-- Easing
-- ---------------------------------------------------------------------------

local function easeOutCubic(t)
    t = t - 1; return t * t * t + 1
end

local function easeInCubic(t)
    return t * t * t
end

local function easeOutBack(t)
    local c = 1.70158; t = t - 1
    return t * t * ((c + 1) * t + c) + 1
end

local function easeInQuad(t)
    return t * t
end

local function easeOutElastic(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local p = 0.35
    return math.pow(2, -10 * t) * math.sin((t - p / 4) * (2 * math.pi) / p) + 1
end

local function clamp01(t)
    if t < 0 then return 0 end
    if t > 1 then return 1 end
    return t
end

-- ---------------------------------------------------------------------------
-- 月相绘制
-- ---------------------------------------------------------------------------

local function drawMoon(vg, cx, cy, r, phase, alpha, isHighlight)
    local darkR, darkG, darkB = 100, 100, 110
    if isHighlight then darkR, darkG, darkB = 40, 40, 50 end

    local lightR, lightG, lightB = 220, 220, 230
    if isHighlight then lightR, lightG, lightB = 255, 210, 60 end

    if isHighlight then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r + 2)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, alpha))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- 暗面底色
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r)
    nvgFillColor(vg, nvgRGBA(darkR, darkG, darkB, alpha))
    nvgFill(vg)

    -- 亮面
    if phase == 0 then
        -- 新月
    elseif phase == 4 then
        nvgBeginPath(vg); nvgCircle(vg, cx, cy, r - 0.5)
        nvgFillColor(vg, nvgRGBA(lightR, lightG, lightB, alpha)); nvgFill(vg)
    elseif phase == 2 then
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, r - 0.5, -math.pi * 0.5, math.pi * 0.5, NVG_CW)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(lightR, lightG, lightB, alpha)); nvgFill(vg)
    elseif phase == 6 then
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, r - 0.5, math.pi * 0.5, -math.pi * 0.5, NVG_CW)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(lightR, lightG, lightB, alpha)); nvgFill(vg)
    elseif phase == 1 then
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, r - 0.5, -math.pi * 0.5, math.pi * 0.5, NVG_CW)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(lightR, lightG, lightB, alpha)); nvgFill(vg)
        nvgBeginPath(vg); nvgEllipse(vg, cx + r * 0.15, cy, r * 0.65, r)
        nvgFillColor(vg, nvgRGBA(darkR, darkG, darkB, alpha)); nvgFill(vg)
    elseif phase == 3 then
        nvgBeginPath(vg); nvgCircle(vg, cx, cy, r - 0.5)
        nvgFillColor(vg, nvgRGBA(lightR, lightG, lightB, alpha)); nvgFill(vg)
        nvgBeginPath(vg); nvgEllipse(vg, cx - r * 0.6, cy, r * 0.5, r)
        nvgFillColor(vg, nvgRGBA(darkR, darkG, darkB, alpha)); nvgFill(vg)
    elseif phase == 5 then
        nvgBeginPath(vg); nvgCircle(vg, cx, cy, r - 0.5)
        nvgFillColor(vg, nvgRGBA(lightR, lightG, lightB, alpha)); nvgFill(vg)
        nvgBeginPath(vg); nvgEllipse(vg, cx + r * 0.6, cy, r * 0.5, r)
        nvgFillColor(vg, nvgRGBA(darkR, darkG, darkB, alpha)); nvgFill(vg)
    elseif phase == 7 then
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, r - 0.5, math.pi * 0.5, -math.pi * 0.5, NVG_CW)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(lightR, lightG, lightB, alpha)); nvgFill(vg)
        nvgBeginPath(vg); nvgEllipse(vg, cx - r * 0.15, cy, r * 0.65, r)
        nvgFillColor(vg, nvgRGBA(darkR, darkG, darkB, alpha)); nvgFill(vg)
    end
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

function M.init(vg)
    state.bgImage = nvgCreateImage(vg, "image/edited_主角_睡觉CGv3_20260425163451.png", 0)
    state.bgLoaded = state.bgImage and state.bgImage > 0
    print("[DateTransition] BG loaded: " .. tostring(state.bgLoaded))
end

function M.play(dayCount, onComplete)
    state.active     = true
    state.timer      = 0
    state.dayCount   = dayCount
    state.onComplete = onComplete
    print("[DateTransition] Play day " .. dayCount)
end

function M.isActive()
    return state.active
end

function M.update(dt)
    if not state.active then return end
    state.timer = state.timer + dt
    if state.timer >= TOTAL_DUR then
        state.active = false
        if state.onComplete then state.onComplete() end
    end
end

-- ---------------------------------------------------------------------------
-- 绘制
-- ---------------------------------------------------------------------------

function M.draw(vg, logicalW, logicalH, gameTime)
    if not state.active then return end

    local t = state.timer
    local diagLen = math.sqrt(logicalW * logicalW + logicalH * logicalH)
    local bandTargetW = logicalH * BAND_WIDTH_RATIO
    local centerX = logicalW * 0.5
    local centerY = logicalH * 0.5

    -- ==============================================
    -- Phase 5: 退出进度 (分离滑出)
    -- ==============================================
    local exitP = 0                     -- 0=未退出, 1=完全退出
    if t > T_EXIT_START then
        exitP = clamp01((t - T_EXIT_START) / T_EXIT_DUR)
        exitP = easeInCubic(exitP)
    end
    -- 光带向右上滑出的偏移量
    local bandExitOffset = exitP * diagLen * 0.6
    -- UI (日期/月份) 向左下滑出的偏移量
    local uiExitOffset   = exitP * diagLen * 0.6
    -- 整体 alpha (用于各元素淡出)
    local exitAlpha = 1.0 - exitP

    -- ==============================================
    -- Phase 1: 蓝色遮罩擦入 (从左下到右上)
    -- ==============================================
    local wipeP = clamp01((t - T_WIPE_START) / (T_WIPE_END - T_WIPE_START))
    wipeP = easeOutCubic(wipeP)

    -- ==============================================
    -- Phase 2: 缩窄为光带
    -- ==============================================
    local shrinkP = 0
    if t > T_WIPE_END then
        shrinkP = clamp01((t - T_WIPE_END) / (T_SHRINK_END - T_WIPE_END))
        shrinkP = easeOutCubic(shrinkP)
    end

    -- 当前遮罩/光带宽度
    local fullCoverH = diagLen * 1.5
    local currentBandH = fullCoverH + (bandTargetW - fullCoverH) * shrinkP

    -- 遮罩中心位置: 从左下到屏幕中心
    local startOffset = diagLen * 0.9
    local perpOffset  = startOffset * (1 - wipeP)

    -- ==============================================
    -- 背景图 (Phase 2 开始淡入, Phase 5 淡出)
    -- ==============================================
    local bgFadeIn = clamp01(shrinkP)
    local bgFadeOut = 1.0
    if t > T_EXIT_START then
        bgFadeOut = 1.0 - clamp01((t - T_EXIT_START) / T_BG_FADE_DUR)
        bgFadeOut = 1.0 - easeInQuad(1.0 - bgFadeOut)
    end
    local bgAlpha = bgFadeIn * bgFadeOut

    if bgAlpha > 0.001 then
        if state.bgLoaded and state.bgImage > 0 then
            local imgPaint = nvgImagePattern(vg, 0, 0, logicalW, logicalH, 0, state.bgImage, bgAlpha)
            nvgBeginPath(vg)
            nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)

            -- 暗角叠加
            nvgBeginPath(vg)
            nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
            nvgFillColor(vg, nvgRGBA(10, 10, 25, math.floor(bgAlpha * 115)))
            nvgFill(vg)
        else
            nvgBeginPath(vg)
            nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
            nvgFillColor(vg, nvgRGBA(13, 13, 26, math.floor(bgAlpha * 255)))
            nvgFill(vg)
        end
    end

    -- ==============================================
    -- 绘制蓝色遮罩/光带 (Phase 5: 向右上滑出)
    -- ==============================================
    local bandAlpha = math.floor(clamp01(wipeP) * exitAlpha * 255)
    if bandAlpha > 0 then
        nvgSave(vg)
        -- 平移到屏幕中心 + 垂直方向偏移
        local bx = centerX - COS_P * perpOffset
        local by = centerY - SIN_P * perpOffset

        -- Phase 5: 光带向右上(沿对角线正方向)滑出
        if bandExitOffset > 0.1 then
            bx = bx + COS_A * bandExitOffset
            by = by + SIN_A * bandExitOffset
        end

        nvgTranslate(vg, bx, by)
        nvgRotate(vg, BAND_ANGLE_RAD)

        -- 光带渐变 (深蓝 → 亮蓝)
        local bandPaint = nvgLinearGradient(vg,
            0, -currentBandH * 0.5, 0, currentBandH * 0.5,
            nvgRGBA(20, 50, 130, bandAlpha),
            nvgRGBA(35, 80, 170, math.floor(bandAlpha * 0.9))
        )
        nvgBeginPath(vg)
        nvgRect(vg, -diagLen, -currentBandH * 0.5, diagLen * 2, currentBandH)
        nvgFillPaint(vg, bandPaint)
        nvgFill(vg)

        -- (移除了旧的装饰性波纹椭圆)

        nvgRestore(vg)
    end

    -- ==============================================
    -- Phase 3 & 4: 日期弹出 + 滚动 + 波纹
    -- Phase 5: UI 向左下滑出
    -- ==============================================
    if t >= T_POPUP_START and wipeP >= 0.99 then
        local dateSpacing = logicalW * 0.115

        -- Phase 4: 滚动进度 (所有日期沿对角线统一偏移一格)
        local scrollP = 0
        if t > T_SCROLL_START then
            local rawScroll = clamp01((t - T_SCROLL_START) / T_SCROLL_DUR)
            scrollP = easeOutElastic(rawScroll)
        end
        -- 滚动偏移量: 沿对角线正方向移动一个 dateSpacing
        local scrollOffX = scrollP * COS_A * dateSpacing
        local scrollOffY = scrollP * SIN_A * dateSpacing

        -- Phase 5: UI 向左下(对角线负方向)滑出的偏移
        local uiSlideX = 0
        local uiSlideY = 0
        if uiExitOffset > 0.1 then
            -- 负方向 = 左下
            uiSlideX = -COS_A * uiExitOffset
            uiSlideY = -SIN_A * uiExitOffset
        end

        -- 计算所有日期的锚点 (沿对角线)
        ---@type {posX: number, posY: number, dc: number, idx: number, popT: number, rawAlpha: number}[]
        local dateSlots = {}
        for i = 1, DATE_COUNT do
            local dayOffset = i - CURRENT_INDEX
            local dc = state.dayCount + dayOffset
            if dc >= 1 then
                -- 基础位置: 沿对角线排列
                local basePosX = centerX + COS_A * dayOffset * dateSpacing
                local basePosY = centerY + SIN_A * dayOffset * dateSpacing

                -- 弹出进度
                local popStart = T_POPUP_START + (i - 1) * T_POPUP_STAGGER
                local rawT = clamp01((t - popStart) / T_POPUP_DUR)
                local popT = rawT > 0 and easeOutBack(rawT) or 0

                -- 应用滚动偏移 + 退出偏移
                local finalX = basePosX + scrollOffX + uiSlideX
                local finalY = basePosY + scrollOffY + uiSlideY

                dateSlots[#dateSlots + 1] = {
                    posX = finalX, posY = finalY,
                    dc = dc, idx = i, popT = popT, rawAlpha = rawT,
                }
            end
        end

        -- ---- 白色对角线 (跟随最后一个已弹出的日期延伸) ----
        if #dateSlots >= 2 then
            local lineEndIdx = 0
            for _, slot in ipairs(dateSlots) do
                if slot.rawAlpha > 0.01 then
                    lineEndIdx = lineEndIdx + 1
                end
            end

            if lineEndIdx >= 1 then
                local firstSlot = dateSlots[1]
                local lastVisibleSlot = dateSlots[math.min(lineEndIdx, #dateSlots)]
                local extendLen = dateSpacing * 0.6
                local lx1 = firstSlot.posX - COS_A * extendLen
                local ly1 = firstSlot.posY - SIN_A * extendLen
                local lx2 = lastVisibleSlot.posX + COS_A * extendLen
                local ly2 = lastVisibleSlot.posY + SIN_A * extendLen

                local lineAlpha = math.floor(clamp01(firstSlot.rawAlpha) * exitAlpha * 150)
                if lineAlpha > 0 then
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, lx1, ly1)
                    nvgLineTo(vg, lx2, ly2)
                    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, lineAlpha))
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)
                end
            end
        end

        -- ---- 绘制日期元素 ----
        nvgFontFace(vg, "sans")

        for _, slot in ipairs(dateSlots) do
            if slot.popT <= 0.001 then goto nextDate end

            local dc = slot.dc
            local isCurrent = (slot.idx == CURRENT_INDEX)
            local year, month, day = calcDate(dc)
            local weekday = calcWeekday(year, month, day)
            local moonPhase = calcMoonPhase(dc)
            local dayStr = tostring(day)
            local wdStr  = WEEKDAY_NAMES[weekday]

            local popScale = slot.popT
            local popAlpha = math.floor(clamp01(slot.rawAlpha * 2.5) * exitAlpha * 255)
            if popAlpha <= 0 then goto nextDate end

            -- 弹跳: 从下方弹起 (仅在 Phase 3 初始弹出时)
            local bounceOffsetY = 0
            if t < T_SCROLL_START then
                bounceOffsetY = (1 - clamp01(slot.rawAlpha * 3)) * 15
            end

            local px = slot.posX
            local py = slot.posY + bounceOffsetY

            if isCurrent then
                -- ==== 当前日: 大号 ====
                nvgSave(vg)
                nvgTranslate(vg, px, py)
                local s = popScale
                nvgScale(vg, s, s)

                -- 日期数字
                nvgFontSize(vg, logicalH * 0.14)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, popAlpha))
                nvgText(vg, -dateSpacing * 0.15, 0, dayStr, nil)

                -- 星期
                local wdSize = logicalH * 0.14 * 0.28
                nvgFontSize(vg, wdSize)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, popAlpha))
                local wdX = logicalH * 0.14 * 0.18
                local wdY = -logicalH * 0.14 * 0.1
                nvgText(vg, wdX, wdY, wdStr, nil)

                -- 星期下划线
                local ulR, ulG, ulB = 255, 255, 255
                if weekday == 1 then ulR, ulG, ulB = 230, 60, 60
                elseif weekday == 7 then ulR, ulG, ulB = 80, 200, 220 end
                nvgBeginPath(vg)
                nvgRect(vg, wdX, wdY + wdSize + 2, wdSize * 2.2, 2.5)
                nvgFillColor(vg, nvgRGBA(ulR, ulG, ulB, popAlpha))
                nvgFill(vg)

                -- 月相
                local moonR = logicalH * 0.04
                drawMoon(vg, dateSpacing * 0.45, logicalH * 0.14 * 0.15, moonR, moonPhase, popAlpha, true)

                nvgRestore(vg)
            else
                -- ==== 非当前日: 小号 ====
                local dayOff = math.abs(slot.idx - CURRENT_INDEX)
                local baseScale = 0.55 - dayOff * 0.03
                if baseScale < 0.3 then baseScale = 0.3 end

                nvgSave(vg)
                nvgTranslate(vg, px, py)
                local s = popScale * baseScale
                nvgScale(vg, s, s)

                local fontSize = logicalH * 0.13
                nvgFontSize(vg, fontSize)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                local textAlpha = math.floor(popAlpha * (0.5 + baseScale * 0.5))
                nvgFillColor(vg, nvgRGBA(255, 255, 255, textAlpha))
                nvgText(vg, -dateSpacing * 0.08, 0, dayStr, nil)

                -- 星期
                local wdSize = fontSize * 0.3
                nvgFontSize(vg, wdSize)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(textAlpha * 0.8)))
                local wdX = fontSize * 0.35
                nvgText(vg, wdX, -fontSize * 0.05, wdStr, nil)

                -- 周日/周六下划线
                if weekday == 1 then
                    nvgBeginPath(vg)
                    nvgRect(vg, wdX, wdSize * 0.5, wdSize * 2, 1.5)
                    nvgFillColor(vg, nvgRGBA(230, 60, 60, math.floor(textAlpha * 0.7)))
                    nvgFill(vg)
                end

                -- 月相
                local moonR = logicalH * 0.035
                drawMoon(vg, dateSpacing * 0.3, fontSize * 0.4, moonR, moonPhase, math.floor(popAlpha * 0.7), false)

                nvgRestore(vg)
            end

            ::nextDate::
        end

        -- ---- Phase 4b: 波纹特效 (滚动后在当前日位置扩散) ----
        if t > T_RIPPLE_START then
            local rippleP = clamp01((t - T_RIPPLE_START) / T_RIPPLE_DUR)

            -- 波纹中心 = 当前日的最终位置 (含滚动偏移和退出偏移)
            local curDayOffset = CURRENT_INDEX - CURRENT_INDEX  -- = 0
            local rippleCX = centerX + scrollOffX + uiSlideX
            local rippleCY = centerY + scrollOffY + uiSlideY

            -- 绘制 3 圈同心波纹, 依次延迟扩散
            local rippleCount = 3
            for ri = 1, rippleCount do
                local delay = (ri - 1) * 0.12
                local localP = clamp01((rippleP - delay) / (1.0 - delay * rippleCount / (rippleCount + 1)))
                if localP > 0 then
                    local maxRadius = logicalH * (0.06 + ri * 0.04)
                    local radius = localP * maxRadius
                    -- 淡出: 后半段消失
                    local rippleAlpha = (1.0 - localP * localP) * exitAlpha
                    local a = math.floor(rippleAlpha * 180)
                    if a > 0 then
                        nvgBeginPath(vg)
                        nvgCircle(vg, rippleCX, rippleCY, radius)
                        nvgStrokeColor(vg, nvgRGBA(160, 200, 255, a))
                        nvgStrokeWidth(vg, 2.0 - localP * 1.0)
                        nvgStroke(vg)
                    end
                end
            end
        end

        -- ---- 左上: 月份标识 (Phase 5: 随 UI 向左下滑出) ----
        local monthPopStart = T_POPUP_START + DATE_COUNT * T_POPUP_STAGGER
        local monthRawT = clamp01((t - monthPopStart) / 0.4)
        local monthPopT = monthRawT > 0 and easeOutBack(monthRawT) or 0
        local monthAlpha = math.floor(clamp01(monthRawT * 2) * exitAlpha * 255)

        if monthAlpha > 0 then
            local year, month, _day = calcDate(state.dayCount)
            local mx = logicalW * 0.08 + uiSlideX
            local my = logicalH * 0.22 + uiSlideY
            local bounceY = (1 - clamp01(monthRawT * 3)) * 20

            nvgSave(vg)
            nvgTranslate(vg, mx, my + bounceY)
            local ms = monthPopT
            nvgScale(vg, ms, ms)

            -- 年份
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, logicalH * 0.035)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(140, 180, 220, math.floor(monthAlpha * 0.8)))
            nvgText(vg, 0, 0, tostring(year), nil)

            -- 月份英文
            nvgFontSize(vg, logicalH * 0.03)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(140, 180, 220, math.floor(monthAlpha * 0.7)))
            nvgText(vg, 0, 2, MONTH_NAMES[month], nil)

            -- 大号月份数字
            nvgFontSize(vg, logicalH * 0.22)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(monthAlpha * 0.9)))
            nvgText(vg, logicalW * 0.02, logicalH * 0.02, tostring(month), nil)

            nvgRestore(vg)
        end

        -- ---- 右上: "第 X 天" (随 UI 向左下滑出) ----
        if monthAlpha > 0 then
            local hudX = logicalW * 0.92 + uiSlideX
            local hudY = logicalH * 0.06 + uiSlideY
            local bounceY2 = (1 - clamp01(monthRawT * 3)) * 15

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, logicalH * 0.035)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(monthAlpha * 0.9)))
            nvgText(vg, hudX, hudY + bounceY2, "第 " .. state.dayCount .. " 天", nil)
        end
    end
end

return M
