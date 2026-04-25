-- ============================================================================
-- Weather.lua - 天气系统模块
-- 确定性天气生成 + 极简矢量天气图标绘制
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
-- 确定性天气生成 (基于 dayCount 的哈希)
-- ---------------------------------------------------------------------------

---@param dayCount integer 游戏天数 (可以是负数/0, 对应游戏开始前的日期)
---@return string weatherType
function M.getWeather(dayCount)
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

return M
