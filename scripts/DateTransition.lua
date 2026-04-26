-- ============================================================================
-- DateTransition.lua - P4 风格日期转场 (多阶段动画序列)
--
-- 关键设计: 光带和日期线构成 X 形交叉!
--   - 蓝色光带: +22° (左上→右下), 作为宽幅背景条纹
--   - 日期排列线: -42° (左下→右上), 日期沿此线排列, 与光带交叉
--
-- Phase 1: 蓝色遮罩擦入
-- Phase 2: 遮罩缩窄为对角光带 + 背景图淡入
-- Phase 3: 日期沿陡线逐个弹跳出现 + 白线延伸
-- Phase 4: 弹性滚动 (前一天→当天) + 波纹
-- Phase 5: 光带右上滑出, UI 左下滑出, 背景淡出
-- ============================================================================

local Weather = require "Weather"

local M = {}

-- ---------------------------------------------------------------------------
-- 双角度系统
-- ---------------------------------------------------------------------------

-- 光带角度 (左上→右下, 较平缓)
local BAND_ANGLE_DEG  = 22
local BAND_ANGLE_RAD  = math.rad(BAND_ANGLE_DEG)
local BAND_COS        = math.cos(BAND_ANGLE_RAD)
local BAND_SIN        = math.sin(BAND_ANGLE_RAD)

-- 光带垂直方向 (用于擦入)
local BAND_PERP_RAD   = BAND_ANGLE_RAD + math.pi * 0.5
local BAND_PERP_COS   = math.cos(BAND_PERP_RAD)
local BAND_PERP_SIN   = math.sin(BAND_PERP_RAD)

-- 日期线角度 (左下→右上, 与光带交叉成 X 形!)
local DATE_ANGLE_DEG  = -42
local DATE_ANGLE_RAD  = math.rad(DATE_ANGLE_DEG)
local DATE_COS        = math.cos(DATE_ANGLE_RAD)
local DATE_SIN        = math.sin(DATE_ANGLE_RAD)

local BAND_WIDTH_RATIO = 0.22            -- 光带宽度占屏高比
local DATE_COUNT       = 8               -- 显示日期数
local CURRENT_INDEX    = 4               -- 当前日在序列中的索引

-- ---------------------------------------------------------------------------
-- 动画时间轴
-- ---------------------------------------------------------------------------

local T_WIPE_START     = 0.0
local T_WIPE_END       = 0.45
local T_SHRINK_END     = 0.90
local T_POPUP_START    = 0.75
local T_POPUP_STAGGER  = 0.07
local T_POPUP_DUR      = 0.35

local T_SCROLL_START   = 1.60
local T_SCROLL_DUR     = 0.50
local T_RIPPLE_START   = 2.10
local T_RIPPLE_DUR     = 0.65

local T_EXIT_START     = 2.80
local T_EXIT_DUR       = 0.50
local T_BG_FADE_DUR    = 0.40
local TOTAL_DUR        = T_EXIT_START + T_EXIT_DUR

-- ---------------------------------------------------------------------------
-- 日期系统常量
-- ---------------------------------------------------------------------------

local BASE_YEAR  = 2026
local BASE_MONTH = 4
local BASE_DAY   = 24

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
    bgAspect   = 16 / 9,
    onComplete = nil,
}

-- ---------------------------------------------------------------------------
-- 日期计算
-- ---------------------------------------------------------------------------

local function isLeapYear(y)
    return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

local function daysInMonth(y, m)
    if m == 2 and isLeapYear(y) then return 29 end
    return DAYS_IN_MONTH[m]
end

local function calcDate(dayCount)
    local y, m, d = BASE_YEAR, BASE_MONTH, BASE_DAY + (dayCount - 1)
    while d < 1 do
        m = m - 1
        if m < 1 then m = 12; y = y - 1 end
        d = d + daysInMonth(y, m)
    end
    while d > daysInMonth(y, m) do
        d = d - daysInMonth(y, m)
        m = m + 1
        if m > 12 then m = 1; y = y + 1 end
    end
    return y, m, d
end

local function calcWeekday(y, m, d)
    local t = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}
    if m < 3 then y = y - 1 end
    return (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + t[m] + d) % 7 + 1
end

-- ---------------------------------------------------------------------------
-- Easing
-- ---------------------------------------------------------------------------

local function easeOutCubic(t) t = t - 1; return t * t * t + 1 end
local function easeInCubic(t)  return t * t * t end
local function easeInQuad(t)   return t * t end

local function easeOutBack(t)
    local c = 1.70158; t = t - 1
    return t * t * ((c + 1) * t + c) + 1
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
-- API
-- ---------------------------------------------------------------------------

function M.init(vg)
    state.bgImage = nvgCreateImage(vg, "image/edited_主角_睡觉CGv3_20260425163451.png", 0)
    state.bgLoaded = state.bgImage and state.bgImage > 0
    state.bgSizeQueried = false  -- 延迟到 draw 时获取尺寸 (确保 NanoVG 就绪)
    print("[DateTransition] BG image handle: " .. tostring(state.bgImage) .. " loaded: " .. tostring(state.bgLoaded))
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
-- 辅助: cover 模式背景图
-- ---------------------------------------------------------------------------

local function drawBgCover(vg, logicalW, logicalH, alpha)
    if not state.bgLoaded or state.bgImage <= 0 then
        nvgBeginPath(vg)
        nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
        nvgFillColor(vg, nvgRGBA(13, 13, 26, math.floor(alpha * 255)))
        nvgFill(vg)
        return
    end

    -- 延迟获取图片尺寸 (在 draw 阶段 NanoVG context 已就绪)
    if not state.bgSizeQueried then
        state.bgSizeQueried = true
        local w, h = nvgImageSize(vg, state.bgImage)
        print("[DateTransition] Image size: " .. tostring(w) .. "x" .. tostring(h))
        if w and h and w > 0 and h > 0 then
            state.bgAspect = w / h
            print("[DateTransition] Aspect ratio: " .. state.bgAspect)
        else
            print("[DateTransition] WARNING: Failed to get image size, using fallback 16:9")
        end
    end

    local screenAspect = logicalW / logicalH
    local drawW, drawH, drawX, drawY
    if state.bgAspect > screenAspect then
        -- 图片更宽: 高度填满, 宽度裁剪
        drawH = logicalH
        drawW = logicalH * state.bgAspect
        drawX = (logicalW - drawW) * 0.5
        drawY = 0
    else
        -- 图片更高: 宽度填满, 高度裁剪
        drawW = logicalW
        drawH = logicalW / state.bgAspect
        drawX = 0
        drawY = (logicalH - drawH) * 0.5
    end

    local imgPaint = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, state.bgImage, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
    nvgFillPaint(vg, imgPaint)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
    nvgFillColor(vg, nvgRGBA(10, 10, 25, math.floor(alpha * 115)))
    nvgFill(vg)
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
    -- Phase 5: 退出进度
    -- ==============================================
    local exitP = 0
    if t > T_EXIT_START then
        exitP = clamp01((t - T_EXIT_START) / T_EXIT_DUR)
        exitP = easeInCubic(exitP)
    end
    -- 光带沿光带方向(右上)滑出
    local bandExitOffset = exitP * diagLen * 0.6
    -- UI 沿日期线负方向(左下)滑出
    local uiExitOffset   = exitP * diagLen * 0.6
    local exitAlpha      = 1.0 - exitP

    -- ==============================================
    -- Phase 1: 蓝色遮罩擦入
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

    local fullCoverH = diagLen * 1.5
    local currentBandH = fullCoverH + (bandTargetW - fullCoverH) * shrinkP

    local startOffset = diagLen * 0.9
    local perpOffset  = startOffset * (1 - wipeP)

    -- ==============================================
    -- 背景图 (cover 模式)
    -- ==============================================
    local bgFadeIn = clamp01(shrinkP)
    local bgFadeOut = 1.0
    if t > T_EXIT_START then
        bgFadeOut = 1.0 - clamp01((t - T_EXIT_START) / T_BG_FADE_DUR)
        bgFadeOut = 1.0 - easeInQuad(1.0 - bgFadeOut)
    end
    local bgAlpha = bgFadeIn * bgFadeOut
    if bgAlpha > 0.001 then
        drawBgCover(vg, logicalW, logicalH, bgAlpha)
    end

    -- ==============================================
    -- 蓝色光带 (使用 BAND_ANGLE, 较平缓)
    -- ==============================================
    local bandAlpha = math.floor(clamp01(wipeP) * exitAlpha * 255)
    if bandAlpha > 0 then
        nvgSave(vg)
        -- 光带中心: 沿光带垂直方向擦入
        local bx = centerX - BAND_PERP_COS * perpOffset
        local by = centerY - BAND_PERP_SIN * perpOffset

        -- Phase 5: 光带沿光带方向(右上)滑出
        if bandExitOffset > 0.1 then
            bx = bx + BAND_COS * bandExitOffset
            by = by + BAND_SIN * bandExitOffset
        end

        nvgTranslate(vg, bx, by)
        nvgRotate(vg, BAND_ANGLE_RAD)

        local bandPaint = nvgLinearGradient(vg,
            0, -currentBandH * 0.5, 0, currentBandH * 0.5,
            nvgRGBA(20, 50, 130, bandAlpha),
            nvgRGBA(35, 80, 170, math.floor(bandAlpha * 0.9))
        )
        nvgBeginPath(vg)
        nvgRect(vg, -diagLen, -currentBandH * 0.5, diagLen * 2, currentBandH)
        nvgFillPaint(vg, bandPaint)
        nvgFill(vg)

        nvgRestore(vg)
    end

    -- ==============================================
    -- 日期元素 (使用 DATE_ANGLE, 较陡, 穿过光带)
    -- ==============================================
    if t >= T_POPUP_START and wipeP >= 0.99 then
        local dateSpacing = logicalW * 0.28

        -- Phase 4: 滚动 (沿日期线负方向)
        local scrollP = 0
        if t > T_SCROLL_START then
            local rawScroll = clamp01((t - T_SCROLL_START) / T_SCROLL_DUR)
            scrollP = easeOutElastic(rawScroll)
        end
        local scrollOffX = -scrollP * DATE_COS * dateSpacing
        local scrollOffY = -scrollP * DATE_SIN * dateSpacing

        -- 用于高亮/注意力计算的 clamp 版本 (弹性缓动会超过 1.0 导致闪缩)
        local highlightP = clamp01(scrollP)

        -- Phase 5: UI 沿日期线负方向(左下)滑出
        local uiSlideX = 0
        local uiSlideY = 0
        if uiExitOffset > 0.1 then
            uiSlideX = -DATE_COS * uiExitOffset
            uiSlideY = -DATE_SIN * uiExitOffset
        end

        -- 以 dayCount-1 为初始中心 (上一天先高亮, 滚动后过渡到新一天)
        local displayDayCount = state.dayCount - 1
        local prevDC = state.dayCount - 1
        -- 注意力中心: 从上一天渐变到新一天 (用 clamp 版本防止弹性过冲)
        local attentionCenter = prevDC + highlightP

        ---@type {posX: number, posY: number, dc: number, idx: number, popT: number, rawAlpha: number, highlightW: number}[]
        local dateSlots = {}
        for i = 1, DATE_COUNT do
            local dayOffset = i - CURRENT_INDEX
            local dc = displayDayCount + dayOffset

            -- 沿日期线排列 (DATE_ANGLE)
            local basePosX = centerX + DATE_COS * dayOffset * dateSpacing
            local basePosY = centerY + DATE_SIN * dayOffset * dateSpacing

            local popStart = T_POPUP_START + (i - 1) * T_POPUP_STAGGER
            local rawT = clamp01((t - popStart) / T_POPUP_DUR)
            local popT = rawT > 0 and easeOutBack(rawT) or 0

            local finalX = basePosX + scrollOffX + uiSlideX
            local finalY = basePosY + scrollOffY + uiSlideY

            -- 高亮权重: 上一天从1→0, 新一天从0→1 (用 clamp 版本防止弹性过冲)
            local highlightW = 0
            if dc == prevDC then
                highlightW = 1.0 - highlightP
            elseif dc == state.dayCount then
                highlightW = highlightP
            end

            dateSlots[#dateSlots + 1] = {
                posX = finalX, posY = finalY,
                dc = dc, idx = i, popT = popT, rawAlpha = rawT,
                highlightW = highlightW,
            }
        end

        -- ---- 白色对角线 (沿日期线) ----
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
                local extendLen = diagLen * 0.5
                local lx1 = firstSlot.posX - DATE_COS * extendLen
                local ly1 = firstSlot.posY - DATE_SIN * extendLen
                local lx2 = lastVisibleSlot.posX + DATE_COS * extendLen
                local ly2 = lastVisibleSlot.posY + DATE_SIN * extendLen

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

        -- ---- 绘制日期元素 (统一路径, highlightW 控制大小过渡) ----
        nvgFontFace(vg, "sans")

        for _, slot in ipairs(dateSlots) do
            if slot.popT <= 0.001 then goto nextDate end

            local dc = slot.dc
            local hw = slot.highlightW
            local year, month, day = calcDate(dc)
            local weekday = calcWeekday(year, month, day)
            local weather = Weather.getWeather(dc)
            local dayStr = tostring(day)
            local wdStr  = WEEKDAY_NAMES[weekday]

            local popScale = slot.popT
            local popAlpha = math.floor(clamp01(slot.rawAlpha * 2.5) * exitAlpha * 255)
            if popAlpha <= 0 then goto nextDate end

            local bounceOffsetY = 0
            if t < T_SCROLL_START then
                bounceOffsetY = (1 - clamp01(slot.rawAlpha * 3)) * 15
            end

            local px = slot.posX
            local py = slot.posY + bounceOffsetY

            -- 基于注意力中心计算距离, 越远越小
            local dayOff = math.abs(dc - attentionCenter)
            local smallScale = 0.50 - dayOff * 0.04
            if smallScale < 0.25 then smallScale = 0.25 end

            -- 渲染缩放: 高亮权重越高越大
            local renderScale = smallScale + (1.0 - smallScale) * hw

            -- 透明度: 高亮项更亮
            local alphaScale = 0.4 + renderScale * 0.6
            local textAlpha = math.floor(alphaScale * popAlpha)

            nvgSave(vg)
            nvgTranslate(vg, px, py)
            nvgScale(vg, popScale * renderScale, popScale * renderScale)

            local fontSize = logicalH * 0.15

            -- 日期数字 (偏左)
            nvgFontSize(vg, fontSize)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, textAlpha))
            nvgText(vg, fontSize * 0.05, 0, dayStr, nil)

            -- 星期 (数字右侧, 留出间隙)
            local wdSize = fontSize * 0.28
            nvgFontSize(vg, wdSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(textAlpha * 0.85)))
            local wdX = fontSize * 0.15
            local wdY = -fontSize * 0.22
            nvgText(vg, wdX, wdY, wdStr, nil)

            -- 星期下划线 (高亮项 + 周日/周六)
            local ulR, ulG, ulB = 255, 255, 255
            if weekday == 1 then ulR, ulG, ulB = 230, 60, 60
            elseif weekday == 7 then ulR, ulG, ulB = 80, 200, 220 end
            if weekday == 1 or weekday == 7 or hw > 0.3 then
                nvgBeginPath(vg)
                nvgRect(vg, wdX, wdY + wdSize + 3, wdSize * 2.2, 2)
                nvgFillColor(vg, nvgRGBA(ulR, ulG, ulB, math.floor(textAlpha * 0.7)))
                nvgFill(vg)
            end

            -- 天气图标 (数字右下方, 与星期错开)
            local weatherR = logicalH * 0.035
            Weather.drawIcon(vg, fontSize * 0.35, fontSize * 0.25, weatherR, weather,
                math.floor(popAlpha * (0.4 + hw * 0.6)), hw > 0.3)

            nvgRestore(vg)

            ::nextDate::
        end

        -- ---- 波纹 (滚动后在当前日位置) ----
        if t > T_RIPPLE_START then
            local rippleP = clamp01((t - T_RIPPLE_START) / T_RIPPLE_DUR)
            -- 波纹在当前日位置 (滚动完成后当前日在屏幕中心)
            local rippleCX = centerX + uiSlideX
            local rippleCY = centerY + uiSlideY

            for ri = 1, 3 do
                local delay = (ri - 1) * 0.12
                local localP = clamp01((rippleP - delay) / (1.0 - delay * 3 / 4))
                if localP > 0 then
                    local maxR = logicalH * (0.06 + ri * 0.04)
                    local radius = localP * maxR
                    local a = math.floor((1.0 - localP * localP) * exitAlpha * 180)
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

        -- ---- 光带上: "第 X 天" (沿光带中心线定位) ----
        local monthPopStart = T_POPUP_START + DATE_COUNT * T_POPUP_STAGGER
        local monthRawT = clamp01((t - monthPopStart) / 0.4)
        local monthPopT = monthRawT > 0 and easeOutBack(monthRawT) or 0
        local monthAlpha = math.floor(clamp01(monthRawT * 2) * exitAlpha * 255)

        if monthAlpha > 0 then
            -- 沿光带中心线计算位置: 选取光带左上段的一个点
            local bandTan = math.tan(BAND_ANGLE_RAD)
            local hudX = logicalW * 0.10
            local hudY = centerY + bandTan * (hudX - centerX)

            -- 退出时跟随光带一起滑出 (而非 UI 方向)
            if bandExitOffset > 0.1 then
                hudX = hudX + BAND_COS * bandExitOffset
                hudY = hudY + BAND_SIN * bandExitOffset
            end

            local bounceY = (1 - clamp01(monthRawT * 3)) * 20

            nvgSave(vg)
            nvgTranslate(vg, hudX, hudY + bounceY)
            nvgScale(vg, monthPopT, monthPopT)

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, logicalH * 0.09)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, monthAlpha))
            nvgText(vg, 0, 0, "第 " .. state.dayCount .. " 天", nil)

            nvgRestore(vg)
        end

        -- ---- 右下角: 年份月份 (小号) ----
        if monthAlpha > 0 then
            local year, month, _day = calcDate(state.dayCount)
            local mx = logicalW * 0.95 + uiSlideX
            local my = logicalH * 0.92 + uiSlideY
            local bounceY2 = (1 - clamp01(monthRawT * 3)) * 12

            nvgSave(vg)
            nvgTranslate(vg, mx, my + bounceY2)
            nvgScale(vg, monthPopT, monthPopT)

            nvgFontFace(vg, "sans")

            -- 年份
            nvgFontSize(vg, logicalH * 0.035)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(180, 210, 240, math.floor(monthAlpha * 0.7)))
            nvgText(vg, 0, 0, tostring(year), nil)

            -- 月份英文
            nvgFontSize(vg, logicalH * 0.03)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(180, 210, 240, math.floor(monthAlpha * 0.6)))
            nvgText(vg, 0, 3, MONTH_NAMES[month], nil)

            nvgRestore(vg)
        end
    end
end

return M
