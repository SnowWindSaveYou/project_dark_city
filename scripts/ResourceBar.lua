-- ============================================================================
-- ResourceBar.lua - 资源数值 HUD (动画滚动 + 闪光)
-- 笔记本撕页纸条风格，与底部 HandPanel 画风统一
-- San(理智) / Order(秩序) / Money(钱币) + 天数 / 天气
-- ============================================================================

local Tween = require "lib.Tween"
local Theme = require "Theme"
local Weather = require "Weather"

local M = {}

-- ---------------------------------------------------------------------------
-- 资源定义
-- ---------------------------------------------------------------------------

---@class ResourceDef
---@field key string
---@field icon string
---@field label string
---@field value number       实际值
---@field displayValue number 显示值 (动画插值)
---@field maxValue number
---@field colorKey string    Theme 中对应的功能色 key
---@field flashTimer number  变化闪烁计时
---@field flashDir number    +1 增长 / -1 减少
---@field deltaText string   变化量文字 (如 "+5")
---@field deltaAlpha number  变化量透明度

local resources = {}

function M.init()
    resources = {
        { key = "san",   icon = "🧠", label = "理智", value = 10, displayValue = 10, maxValue = 10,
          colorKey = "info",      flashTimer = 0, flashDir = 0, deltaText = "", deltaAlpha = 0 },
        { key = "order", icon = "⚖️",  label = "秩序", value = 10,  displayValue = 10,  maxValue = 10,
          colorKey = "safe",      flashTimer = 0, flashDir = 0, deltaText = "", deltaAlpha = 0 },
        { key = "money", icon = "💰", label = "钱币", value = 50,  displayValue = 50,  maxValue = 999,
          colorKey = "warning",   flashTimer = 0, flashDir = 0, deltaText = "", deltaAlpha = 0 },
    }
    -- film 不在资源栏显示，但仍可通过 get/change 操作
    filmData = { key = "film", value = 3, displayValue = 3, maxValue = 10,
                 colorKey = "highlight", flashTimer = 0, flashDir = 0, deltaText = "", deltaAlpha = 0 }
end

-- ---------------------------------------------------------------------------
-- 数值变更 (触发动画)
-- ---------------------------------------------------------------------------

--- 改变资源值
---@param key string 资源 key: "san"|"order"|"film"|"money"
---@param delta number 变化量 (正数增加，负数减少)
function M.change(key, delta)
    local res = nil
    if key == "film" then
        res = filmData
    else
        for _, r in ipairs(resources) do
            if r.key == key then res = r; break end
        end
    end
    if not res then return end

    local oldValue = res.value
    res.value = math.max(0, math.min(res.maxValue, res.value + delta))
    local actualDelta = res.value - oldValue
    if actualDelta == 0 then return end

    Tween.to(res, { displayValue = res.value }, 0.5, {
        easing = Tween.Easing.easeOutCubic,
        tag = "resource_" .. key,
    })

    res.flashTimer = 0.6
    res.flashDir = actualDelta > 0 and 1 or -1

    res.deltaText = actualDelta > 0 and ("+" .. actualDelta) or tostring(actualDelta)
    res.deltaAlpha = 1.0
    Tween.to(res, { deltaAlpha = 0 }, 0.8, {
        delay = 0.3,
        easing = Tween.Easing.easeOutQuad,
        tag = "resource_delta_" .. key,
    })
end

--- 获取资源值
function M.get(key)
    if key == "film" then return filmData.value end
    for _, res in ipairs(resources) do
        if res.key == key then return res.value end
    end
    return 0
end

--- 重置所有资源到初始值
function M.reset()
    M.init()
end

-- ---------------------------------------------------------------------------
-- 更新
-- ---------------------------------------------------------------------------

function M.update(dt)
    for _, res in ipairs(resources) do
        if res.flashTimer > 0 then
            res.flashTimer = res.flashTimer - dt
        end
    end
    if filmData.flashTimer > 0 then
        filmData.flashTimer = filmData.flashTimer - dt
    end
end

-- ---------------------------------------------------------------------------
-- 常量 — 纸条布局
-- ---------------------------------------------------------------------------

local MARGIN_X    = 12    -- 左右距屏幕边
local MARGIN_TOP  = 8     -- 距屏幕顶部
local STRIP_H     = 36    -- 纸条高度
local CORNER_R    = 3     -- 纸张圆角
local PAD_X       = 10    -- 纸条内横向边距
local PAD_Y       = 0     -- 纸条内纵向边距（居中靠字体大小）
local LINE_SPACING = 9    -- 横线间距（装饰用）

-- 胶带装饰
local TAPE_W      = 32    -- 胶带宽度
local TAPE_H      = 10    -- 胶带高度

-- 分隔线
local SEP_PAD     = 6     -- 分隔竖线上下间距

-- ---------------------------------------------------------------------------
-- 辅助: 绘制撕裂边缘 (底部)
-- ---------------------------------------------------------------------------

local function drawTornEdge(vg, x, y, w, color_r, color_g, color_b, alpha)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y)
    -- 沿底边绘制锯齿
    local step = 5
    local cx = x
    local i = 0
    while cx < x + w do
        local nextX = math.min(cx + step, x + w)
        -- 交替上下偏移，模拟撕裂感
        local dy = (i % 2 == 0) and 1.5 or -0.5
        -- 加一点随机感 (用位置做种子)
        local jitter = math.sin(cx * 1.7) * 0.8
        nvgLineTo(vg, nextX, y + dy + jitter)
        cx = nextX
        i = i + 1
    end
    -- 回到纸条内侧闭合
    nvgLineTo(vg, x + w, y - 2)
    nvgLineTo(vg, x, y - 2)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(color_r, color_g, color_b, alpha))
    nvgFill(vg)
end

-- ---------------------------------------------------------------------------
-- 辅助: 绘制胶带
-- ---------------------------------------------------------------------------

local function drawTape(vg, cx, cy, w, h, angle)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, angle)

    -- 半透明胶带主体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -w / 2, -h / 2, w, h, 1.5)
    nvgFillColor(vg, nvgRGBA(245, 235, 200, 60))
    nvgFill(vg)

    -- 胶带边缘高光
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -w / 2, -h / 2, w, h, 1.5)
    nvgStrokeColor(vg, nvgRGBA(220, 210, 180, 40))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    nvgRestore(vg)
end

-- ---------------------------------------------------------------------------
-- 辅助: 绘制竖线分隔符
-- ---------------------------------------------------------------------------

local function drawSeparator(vg, x, y, h, t)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y + SEP_PAD)
    nvgLineTo(vg, x, y + h - SEP_PAD)
    nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 100))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)
end

-- ---------------------------------------------------------------------------
-- 渲染 — 顶部笔记本纸条
-- ---------------------------------------------------------------------------

---@param vg userdata
---@param logicalW number
---@param logicalH number
---@param dayCount number   当前天数
function M.draw(vg, logicalW, logicalH, dayCount)
    local t = Theme.current
    local count = #resources
    if count == 0 then return end

    dayCount = dayCount or 1

    -- === 纸条几何 ===
    local stripW = math.min(logicalW - MARGIN_X * 2, 360)
    local stripX = (logicalW - stripW) / 2   -- 水平居中
    local stripY = MARGIN_TOP
    local stripCY = stripY + STRIP_H / 2     -- 纸条垂直中心

    nvgSave(vg)

    -- === 纸张阴影 ===
    local shadowPaint = nvgBoxGradient(vg,
        stripX + 1, stripY + 2, stripW, STRIP_H, CORNER_R, 6,
        nvgRGBA(60, 40, 20, 35),
        nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, stripX - 6, stripY - 3, stripW + 12, STRIP_H + 12)
    nvgFillPaint(vg, shadowPaint)
    nvgFill(vg)

    -- === 纸条主体 (米黄纸色) ===
    nvgBeginPath(vg)
    nvgRoundedRect(vg, stripX, stripY, stripW, STRIP_H, CORNER_R)
    nvgFillColor(vg, Theme.rgba(t.notebookPaper))
    nvgFill(vg)

    -- === 横线纹理 (淡蓝色，与笔记本页面一致) ===
    nvgSave(vg)
    nvgIntersectScissor(vg, stripX, stripY, stripW, STRIP_H)
    local lineY = stripY + LINE_SPACING * 0.6
    while lineY < stripY + STRIP_H do
        nvgBeginPath(vg)
        nvgMoveTo(vg, stripX + 4, lineY)
        nvgLineTo(vg, stripX + stripW - 4, lineY)
        nvgStrokeColor(vg, Theme.rgbaA(t.notebookLine, 50))
        nvgStrokeWidth(vg, 0.4)
        nvgStroke(vg)
        lineY = lineY + LINE_SPACING
    end
    nvgRestore(vg)

    -- === 底部撕裂边缘 ===
    drawTornEdge(vg, stripX, stripY + STRIP_H,
        stripW, t.notebookPaper.r, t.notebookPaper.g, t.notebookPaper.b, 255)

    -- === 纸条边框 (上部和两侧，底部撕裂不画边框) ===
    nvgBeginPath(vg)
    -- 只画顶部 + 两侧，不闭合底部
    nvgMoveTo(vg, stripX, stripY + STRIP_H)
    nvgLineTo(vg, stripX, stripY + CORNER_R)
    nvgArcTo(vg, stripX, stripY, stripX + CORNER_R, stripY, CORNER_R)
    nvgLineTo(vg, stripX + stripW - CORNER_R, stripY)
    nvgArcTo(vg, stripX + stripW, stripY, stripX + stripW, stripY + CORNER_R, CORNER_R)
    nvgLineTo(vg, stripX + stripW, stripY + STRIP_H)
    nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 100))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    -- === 胶带装饰 (两端各一条) ===
    drawTape(vg, stripX + 16, stripY + 1, TAPE_W, TAPE_H, -0.12)
    drawTape(vg, stripX + stripW - 16, stripY + 1, TAPE_W, TAPE_H, 0.10)

    -- === 内容区域 ===
    nvgFontFace(vg, "sans")

    -- ---- 左半: 资源数值 ----
    local resStartX = stripX + PAD_X + 6
    local cx = resStartX

    for i, res in ipairs(resources) do
        local rc = Theme.color(res.colorKey)
        local displayNum = math.floor(res.displayValue + 0.5)

        -- 图标
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgbaA(t.textPrimary, 200))
        local iconEnd = nvgText(vg, cx, stripCY, res.icon, nil)

        -- 标签 (手写风小字)
        nvgFontSize(vg, 9)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 160))
        local labelEnd = nvgText(vg, iconEnd + 1, stripCY - 8, res.label, nil)

        -- 数值 (大号醒目)
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        -- 数值颜色: 闪烁变色
        if res.flashTimer > 0 then
            local pulse = 0.5 + 0.5 * math.sin(res.flashTimer * 20)
            if res.flashDir > 0 then
                nvgFillColor(vg, nvgRGBA(
                    math.floor(rc.r + (t.safe.r - rc.r) * pulse),
                    math.floor(rc.g + (t.safe.g - rc.g) * pulse),
                    math.floor(rc.b + (t.safe.b - rc.b) * pulse), 255))
            else
                nvgFillColor(vg, nvgRGBA(
                    math.floor(rc.r + (t.danger.r - rc.r) * pulse),
                    math.floor(rc.g + (t.danger.g - rc.g) * pulse),
                    math.floor(rc.b + (t.danger.b - rc.b) * pulse), 255))
            end
        else
            nvgFillColor(vg, Theme.rgba(rc))
        end
        local numEnd = nvgText(vg, iconEnd + 1, stripCY + 5, tostring(displayNum), nil)

        -- 变化量浮动文字
        if res.deltaAlpha > 0.01 then
            local dy = -12 * (1 - res.deltaAlpha)
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
            if res.flashDir > 0 then
                nvgFillColor(vg, nvgRGBA(t.safe.r, t.safe.g, t.safe.b,
                    math.floor(res.deltaAlpha * 255)))
            else
                nvgFillColor(vg, nvgRGBA(t.danger.r, t.danger.g, t.danger.b,
                    math.floor(res.deltaAlpha * 255)))
            end
            nvgText(vg, numEnd + 2, stripCY - 2 + dy, res.deltaText, nil)
        end

        -- 分隔竖线 (除最后一项)
        local nextX = math.max(numEnd, labelEnd) + 10
        if i < count then
            drawSeparator(vg, nextX, stripY, STRIP_H, t)
            cx = nextX + 8
        end
    end

    -- ---- 右半: 天数 + 天气 ----
    local rightX = stripX + stripW - PAD_X - 6

    -- 天气图标
    local weatherType = Weather.getWeather(dayCount)
    local weatherR = 10  -- 图标半径
    Weather.drawIcon(vg, rightX - weatherR, stripCY, weatherR, weatherType, 220, true)

    -- 天气名称 (小字)
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 160))
    nvgText(vg, rightX - weatherR * 2 - 4, stripCY + 5, Weather.getName(weatherType), nil)

    -- 天数 + 分隔线
    local dayText = "Day " .. dayCount
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgbaA(t.textPrimary, 220))

    -- 先测量天气区域宽度用于分隔线定位
    local dayTextW = nvgTextBounds(vg, 0, 0, dayText, nil)
    local dayRightX = rightX - weatherR * 2 - 8
    nvgText(vg, dayRightX, stripCY - 4, dayText, nil)

    -- "第X天" 小字
    nvgFontSize(vg, 9)
    nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 140))
    nvgText(vg, dayRightX, stripCY + 7, "第" .. dayCount .. "天", nil)

    -- 天数区和资源区之间的竖线分隔
    drawSeparator(vg, dayRightX - dayTextW - 8, stripY, STRIP_H, t)

    nvgRestore(vg)
end

return M
