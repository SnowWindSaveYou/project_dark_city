-- ============================================================================
-- Weather.lua - 天气系统模块
-- 确定性天气生成 + 极简矢量天气图标绘制 + NanoVG 粒子特效
-- 可被 DateTransition 和其他游戏模块复用
-- ============================================================================

local M = {}

-- ---------------------------------------------------------------------------
-- 天气类型
-- ---------------------------------------------------------------------------

M.SUNNY         = "sunny"          -- 晴
M.PARTLY_CLOUDY = "partly_cloudy"  -- 多云
M.CLOUDY        = "cloudy"         -- 阴
M.RAINY         = "rainy"          -- 雨
M.STORMY        = "stormy"         -- 雷暴

M.ALL_TYPES = { M.SUNNY, M.PARTLY_CLOUDY, M.CLOUDY, M.RAINY, M.STORMY }

-- ---------------------------------------------------------------------------
-- 剧情固定天气 (优先级最高, 覆盖哈希结果)
-- 依据 morning_events.lua / milestone_events.lua 中的环境描述确定
-- ---------------------------------------------------------------------------

M.STORY_WEATHER = {
    [2] = M.STORMY,  -- "入夜后暴雨倾盆，闪电劈开天际" (morning_day2)
}

-- ---------------------------------------------------------------------------
-- 确定性天气生成 (基于 dayCount 的哈希)
-- ---------------------------------------------------------------------------

---@param dayCount integer 游戏天数 (可以是负数/0, 对应游戏开始前的日期)
---@return string weatherType
function M.getWeather(dayCount)
    -- 剧情固定天气优先
    if M.STORY_WEATHER[dayCount] then
        return M.STORY_WEATHER[dayCount]
    end
    -- 简单的确定性哈希, 同一天总是返回相同天气
    local hash = ((dayCount * 2654435761) % 2147483647) % 100
    if hash < 30 then
        return M.SUNNY
    elseif hash < 50 then
        return M.PARTLY_CLOUDY
    elseif hash < 72 then
        return M.CLOUDY
    elseif hash < 90 then
        return M.RAINY
    else
        return M.STORMY
    end
end

-- ---------------------------------------------------------------------------
-- 天气名称 (中文)
-- ---------------------------------------------------------------------------

M.NAMES = {
    [M.SUNNY]         = "晴",
    [M.PARTLY_CLOUDY] = "多云",
    [M.CLOUDY]        = "阴",
    [M.RAINY]         = "雨",
    [M.STORMY]        = "雷暴",
}

---@param weatherType string
---@return string
function M.getName(weatherType)
    return M.NAMES[weatherType] or "未知"
end

-- ---------------------------------------------------------------------------
-- 极简矢量天气图标绘制 (NanoVG)
-- ---------------------------------------------------------------------------

-- 辅助: 绘制太阳 (圆盘 + 光线)
local function drawSun(vg, cx, cy, r, alpha, color)
    local cr, cg, cb = color[1], color[2], color[3]
    -- 圆盘
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r * 0.45)
    nvgFillColor(vg, nvgRGBA(cr, cg, cb, alpha))
    nvgFill(vg)
    -- 8 条光线
    nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, alpha))
    nvgStrokeWidth(vg, math.max(1.0, r * 0.08))
    for i = 0, 7 do
        local a = i * math.pi * 0.25
        local cosA, sinA = math.cos(a), math.sin(a)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + cosA * r * 0.6, cy + sinA * r * 0.6)
        nvgLineTo(vg, cx + cosA * r * 0.9, cy + sinA * r * 0.9)
        nvgStroke(vg)
    end
end

-- 辅助: 绘制云 (两个半圆 + 底部矩形)
local function drawCloud(vg, cx, cy, r, alpha, color)
    local cr, cg, cb = color[1], color[2], color[3]
    nvgBeginPath(vg)
    -- 底部矩形圆角
    local bw = r * 1.4
    local bh = r * 0.35
    local by = cy + r * 0.05
    nvgRoundedRect(vg, cx - bw * 0.5, by - bh * 0.5, bw, bh, bh * 0.4)
    -- 左侧凸起
    nvgCircle(vg, cx - r * 0.3, by - bh * 0.35, r * 0.35)
    -- 右侧凸起 (稍大)
    nvgCircle(vg, cx + r * 0.15, by - bh * 0.5, r * 0.45)
    nvgFillColor(vg, nvgRGBA(cr, cg, cb, alpha))
    nvgFill(vg)
end

---@param vg any NanoVG context
---@param cx number 图标中心 X
---@param cy number 图标中心 Y
---@param r number 图标半径 (整体包围圆)
---@param weatherType string 天气类型
---@param alpha number 不透明度 (0~255)
---@param isHighlight boolean 是否高亮 (当前日)
function M.drawIcon(vg, cx, cy, r, weatherType, alpha, isHighlight)
    if alpha <= 0 then return end

    -- 颜色方案
    local sunColor   = isHighlight and {255, 220, 60} or {220, 200, 140}
    local cloudColor = isHighlight and {240, 240, 250} or {180, 180, 195}
    local rainColor  = isHighlight and {140, 200, 255} or {120, 160, 200}
    local boltColor  = isHighlight and {255, 240, 80} or {220, 200, 100}

    if weatherType == M.SUNNY then
        drawSun(vg, cx, cy, r, alpha, sunColor)

    elseif weatherType == M.PARTLY_CLOUDY then
        -- 太阳 (偏左上)
        drawSun(vg, cx - r * 0.2, cy - r * 0.15, r * 0.65, math.floor(alpha * 0.7), sunColor)
        -- 云 (偏右下, 遮住部分太阳)
        drawCloud(vg, cx + r * 0.1, cy + r * 0.15, r * 0.7, alpha, cloudColor)

    elseif weatherType == M.CLOUDY then
        drawCloud(vg, cx, cy, r * 0.9, alpha, cloudColor)

    elseif weatherType == M.RAINY then
        -- 云 (偏上)
        drawCloud(vg, cx, cy - r * 0.15, r * 0.75, alpha, cloudColor)
        -- 3 条雨线
        nvgStrokeColor(vg, nvgRGBA(rainColor[1], rainColor[2], rainColor[3], alpha))
        nvgStrokeWidth(vg, math.max(1.0, r * 0.07))
        local rainY = cy + r * 0.25
        for i = -1, 1 do
            local rx = cx + i * r * 0.3
            nvgBeginPath(vg)
            nvgMoveTo(vg, rx, rainY)
            nvgLineTo(vg, rx - r * 0.08, rainY + r * 0.35)
            nvgStroke(vg)
        end

    elseif weatherType == M.STORMY then
        -- 深色云 (偏上)
        local darkCloud = isHighlight and {160, 160, 180} or {130, 130, 150}
        drawCloud(vg, cx, cy - r * 0.2, r * 0.8, alpha, darkCloud)
        -- 闪电 (Z字形)
        nvgBeginPath(vg)
        local lx = cx + r * 0.05
        local ly = cy + r * 0.1
        nvgMoveTo(vg, lx - r * 0.1, ly)
        nvgLineTo(vg, lx + r * 0.05, ly + r * 0.25)
        nvgLineTo(vg, lx - r * 0.05, ly + r * 0.25)
        nvgLineTo(vg, lx + r * 0.1, ly + r * 0.55)
        nvgStrokeColor(vg, nvgRGBA(boltColor[1], boltColor[2], boltColor[3], alpha))
        nvgStrokeWidth(vg, math.max(1.5, r * 0.1))
        nvgStroke(vg)

    else
        -- fallback: 小圆点
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r * 0.3)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, alpha))
        nvgFill(vg)
    end

    -- 高亮外圈
    if isHighlight then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r + 2)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 0.6)))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end
end

-- ============================================================================
-- 天气粒子特效 (FX) — NanoVG 绘制
-- ============================================================================

local MAX_RAIN  = 80
local MAX_STORM = 120

local fx_ = {
    particles    = {},   -- 活跃粒子列表
    thunderTimer = 0,    -- 距下次雷声的剩余时间 (秒)
    lightFlash   = 0,    -- 闪电白色叠加层强度 (0~1)
    lastType     = nil,  -- 上一帧天气类型, 用于检测变化
}

-- 随机生成一个雨滴粒子
local function makeRainDrop(weatherType, w, h, fromTop)
    local isStorm = weatherType == M.STORMY
    return {
        x     = math.random() * (w + 200) - 100,
        y     = fromTop and (-math.random() * 40) or (math.random() * h),
        vx    = isStorm and (-75 - math.random() * 95) or (-15 - math.random() * 28),
        vy    = isStorm and (360 + math.random() * 190) or (245 + math.random() * 125),
        len   = isStorm and (10 + math.random() * 11) or (6  + math.random() * 7),
        alpha = isStorm and (135 + math.random() * 85) or (90 + math.random() * 80),
        lw    = isStorm and (1.0 + math.random() * 0.6) or (0.7 + math.random() * 0.4),
    }
end

--- 初始化天气特效系统 (在 Start() 中调用一次)
function M.initFX()
    fx_.particles    = {}
    fx_.thunderTimer = 6 + math.random() * 12
    fx_.lightFlash   = 0
    fx_.lastType     = nil
end

--- 每帧更新粒子 (在 HandleUpdate 中调用)
---@param dt number
---@param weatherType string|nil  当前天气; nil 表示不显示粒子
---@param w number  逻辑宽
---@param h number  逻辑高
---@param audioMgr table|nil  AudioManager 引用 (雷声用)
function M.updateFX(dt, weatherType, w, h, audioMgr)
    local isRain = weatherType == M.RAINY or weatherType == M.STORMY

    -- 非降水天气: 清空粒子
    if not isRain then
        if #fx_.particles > 0 then fx_.particles = {} end
        fx_.lightFlash = 0
        fx_.lastType   = weatherType
        return
    end

    local targetCount = (weatherType == M.STORMY) and MAX_STORM or MAX_RAIN

    -- 天气类型发生变化: 清空重建
    if fx_.lastType ~= weatherType then
        fx_.particles    = {}
        fx_.thunderTimer = 6 + math.random() * 12
    end
    fx_.lastType = weatherType

    -- 填充粒子池 (首批散布在屏幕上, 后续从顶部补入)
    local scattered = #fx_.particles >= math.floor(targetCount * 0.45)
    while #fx_.particles < targetCount do
        fx_.particles[#fx_.particles + 1] = makeRainDrop(weatherType, w, h, scattered)
        scattered = true
    end

    -- 更新位置
    local i = 1
    while i <= #fx_.particles do
        local p = fx_.particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        -- 出界 → 从顶部重置
        if p.y > h + 60 or p.x < -180 then
            fx_.particles[i] = makeRainDrop(weatherType, w, h, true)
        end
        i = i + 1
    end

    -- 雷暴专属: 随机闪电 + 雷声
    if weatherType == M.STORMY then
        fx_.thunderTimer = fx_.thunderTimer - dt
        if fx_.thunderTimer <= 0 then
            fx_.thunderTimer = 10 + math.random() * 18
            fx_.lightFlash   = 0.9
            if audioMgr then audioMgr.playSFX("weather_thunder") end
        end
    end

    -- 闪电衰减
    if fx_.lightFlash > 0 then
        fx_.lightFlash = math.max(0, fx_.lightFlash - dt * 5)
    end
end

--- 绘制天气粒子 (在 NanoVGRender 中调用, 位于 HUD 层之前)
---@param vg any
---@param w number 逻辑宽
---@param h number 逻辑高
---@param weatherType string
---@param globalAlpha number 整体透明度 0~1
function M.drawFX(vg, w, h, weatherType, globalAlpha)
    globalAlpha = globalAlpha or 1.0
    if globalAlpha <= 0 or #fx_.particles == 0 then return end

    local isStorm = weatherType == M.STORMY

    -- 闪电白色叠加层
    if isStorm and fx_.lightFlash > 0 then
        local flashA = math.floor(fx_.lightFlash * 52 * globalAlpha)
        if flashA > 0 then
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, w, h)
            nvgFillColor(vg, nvgRGBA(215, 228, 255, flashA))
            nvgFill(vg)
        end
    end

    -- 雨天: 顶部细薄雾气渐变
    local fogA = math.floor((isStorm and 40 or 20) * globalAlpha)
    if fogA > 0 then
        local fog = nvgLinearGradient(vg, 0, 0, 0, h * 0.25,
            nvgRGBA(160, 190, 220, fogA), nvgRGBA(160, 190, 220, 0))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h * 0.25)
        nvgFillPaint(vg, fog)
        nvgFill(vg)
    end

    -- 雨滴线段
    local baseR = isStorm and 150 or 170
    local baseG = isStorm and 182 or 208
    local baseB = isStorm and 225 or 252

    for _, p in ipairs(fx_.particles) do
        local a = math.floor(p.alpha * globalAlpha)
        if a > 0 then
            local spd = math.sqrt(p.vx * p.vx + p.vy * p.vy)
            if spd > 0.01 then
                local nx = p.vx / spd
                local ny = p.vy / spd
                nvgBeginPath(vg)
                nvgMoveTo(vg, p.x, p.y)
                nvgLineTo(vg, p.x + nx * p.len, p.y + ny * p.len)
                nvgStrokeColor(vg, nvgRGBA(baseR, baseG, baseB, a))
                nvgStrokeWidth(vg, p.lw)
                nvgStroke(vg)
            end
        end
    end
end

--- 获取当前天气对应的环境音 key (传给 AudioManager.playAmbient)
---@param weatherType string
---@return string|nil
function M.getAmbientKey(weatherType)
    if weatherType == M.STORMY then return "wind" end
    if weatherType == M.RAINY  then return "rain" end
    return nil
end

--- 重置特效状态 (游戏重启时调用)
function M.resetFX()
    fx_.particles    = {}
    fx_.lightFlash   = 0
    fx_.thunderTimer = 6 + math.random() * 12
    fx_.lastType     = nil
end

return M
