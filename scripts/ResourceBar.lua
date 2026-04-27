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
-- 暗面模式状态
-- ---------------------------------------------------------------------------
local darkMode_ = false
local darkLayerName_ = ""
local darkEnergy_ = 0
local darkMaxEnergy_ = 10
local darkLayerIdx_ = 1
local darkLayerCount_ = 3
local darkEnergyFlash_ = 0

function M.setDarkMode(enabled, opts)
    darkMode_ = enabled
    if enabled and opts then
        darkLayerName_ = opts.layerName or ""
        darkEnergy_ = opts.energy or 0
        darkMaxEnergy_ = opts.maxEnergy or 10
        darkLayerIdx_ = opts.layerIdx or 1
        darkLayerCount_ = opts.layerCount or 3
    end
end

function M.updateDarkEnergy(energy, maxEnergy)
    if darkMode_ then
        darkEnergy_ = energy or darkEnergy_
        darkMaxEnergy_ = maxEnergy or darkMaxEnergy_
    end
end

function M.flashDarkEnergy()
    darkEnergyFlash_ = 0.5
end

function M.isDarkMode()
    return darkMode_
end

-- 暗面退出按钮几何缓存 (供 hitTest 使用)
local darkExitBtnRect_ = { x = 0, y = 0, w = 0, h = 0 }

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
    if darkEnergyFlash_ > 0 then
        darkEnergyFlash_ = darkEnergyFlash_ - dt
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
-- 辅助: 暗面腐蚀边缘 (对应笔记本撕裂边)
-- ---------------------------------------------------------------------------

local function drawDarkEdge(vg, x, y, w)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y)
    local step = 4
    local cx = x
    local i = 0
    while cx < x + w do
        local nextX = math.min(cx + step, x + w)
        -- 更尖锐的锯齿, 模拟腐蚀/结晶裂痕
        local dy = (i % 2 == 0) and 2.0 or -0.3
        local jitter = math.sin(cx * 2.1 + 0.7) * 1.2
        nvgLineTo(vg, nextX, y + dy + jitter)
        cx = nextX
        i = i + 1
    end
    nvgLineTo(vg, x + w, y - 2)
    nvgLineTo(vg, x, y - 2)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(18, 14, 35, 240))
    nvgFill(vg)
end

-- ---------------------------------------------------------------------------
-- 辅助: 暗面封印装饰 (对应笔记本胶带)
-- ---------------------------------------------------------------------------

local function drawDarkSeal(vg, cx, cy, w, h, angle)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, angle)

    -- 封印主体 (半透明暗紫, 对应胶带的半透明米黄)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -w / 2, -h / 2, w, h, 1.5)
    nvgFillColor(vg, nvgRGBA(139, 92, 246, 25))
    nvgFill(vg)

    -- 封印中线灵纹 (对应胶带边缘高光)
    nvgBeginPath(vg)
    nvgMoveTo(vg, -w / 2 + 4, 0)
    nvgLineTo(vg, w / 2 - 4, 0)
    nvgStrokeColor(vg, nvgRGBA(34, 211, 238, 35))
    nvgStrokeWidth(vg, 0.4)
    nvgStroke(vg)

    -- 两端节点 (灵纹端点)
    for _, dx in ipairs({ -w / 2 + 5, w / 2 - 5 }) do
        nvgBeginPath(vg)
        nvgCircle(vg, dx, 0, 1)
        nvgFillColor(vg, nvgRGBA(34, 211, 238, 45))
        nvgFill(vg)
    end

    -- 边框轮廓
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -w / 2, -h / 2, w, h, 1.5)
    nvgStrokeColor(vg, nvgRGBA(139, 92, 246, 35))
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

    if darkMode_ then
        -- =====================================================================
        -- 暗面模式: 暗纹石板风格 (与笔记本纸条对称的暗面美学)
        -- =====================================================================

        -- 1) 深邃阴影 (比纸条阴影更浓重)
        local shadowPaint = nvgBoxGradient(vg,
            stripX, stripY + 4, stripW, STRIP_H, 6, 10,
            nvgRGBA(8, 4, 20, 100),
            nvgRGBA(0, 0, 0, 0))
        nvgBeginPath(vg)
        nvgRect(vg, stripX - 8, stripY - 4, stripW + 16, STRIP_H + 16)
        nvgFillPaint(vg, shadowPaint)
        nvgFill(vg)

        -- 2) 面板主体 (纵向渐变, 打磨暗色石面质感)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, stripX, stripY, stripW, STRIP_H, CORNER_R)
        local basePaint = nvgLinearGradient(vg,
            stripX, stripY, stripX, stripY + STRIP_H,
            nvgRGBA(30, 24, 50, 225), nvgRGBA(18, 14, 35, 240))
        nvgFillPaint(vg, basePaint)
        nvgFill(vg)

        -- 3) 横纹肌理 (对应笔记本横线, 暗面版为幽微灵纹)
        nvgSave(vg)
        nvgIntersectScissor(vg, stripX, stripY, stripW, STRIP_H)
        local dLineY = stripY + LINE_SPACING * 0.6
        while dLineY < stripY + STRIP_H do
            nvgBeginPath(vg)
            nvgMoveTo(vg, stripX + 4, dLineY)
            nvgLineTo(vg, stripX + stripW - 4, dLineY)
            nvgStrokeColor(vg, nvgRGBA(139, 92, 246, 16))
            nvgStrokeWidth(vg, 0.3)
            nvgStroke(vg)
            dLineY = dLineY + LINE_SPACING
        end
        nvgRestore(vg)

        -- 4) 底部腐蚀边缘 (对应笔记本撕裂边)
        drawDarkEdge(vg, stripX, stripY + STRIP_H, stripW)

        -- 5) 上缘灵光 (对应纸张自然高光)
        local topGlow = nvgLinearGradient(vg,
            stripX, stripY, stripX, stripY + 8,
            nvgRGBA(139, 92, 246, 45), nvgRGBA(139, 92, 246, 0))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, stripX, stripY, stripW, 8, CORNER_R)
        nvgFillPaint(vg, topGlow)
        nvgFill(vg)

        -- 6) 三边边框 (底部留给腐蚀边缘, 对应笔记本三边边框)
        nvgBeginPath(vg)
        nvgMoveTo(vg, stripX, stripY + STRIP_H)
        nvgLineTo(vg, stripX, stripY + CORNER_R)
        nvgArcTo(vg, stripX, stripY, stripX + CORNER_R, stripY, CORNER_R)
        nvgLineTo(vg, stripX + stripW - CORNER_R, stripY)
        nvgArcTo(vg, stripX + stripW, stripY, stripX + stripW, stripY + CORNER_R, CORNER_R)
        nvgLineTo(vg, stripX + stripW, stripY + STRIP_H)
        nvgStrokeColor(vg, nvgRGBA(139, 92, 246, 55))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        -- 7) 封印装饰 (对应笔记本胶带, 同位置/角度)
        drawDarkSeal(vg, stripX + 16, stripY + 1, TAPE_W, TAPE_H, -0.12)
        drawDarkSeal(vg, stripX + stripW - 16, stripY + 1, TAPE_W, TAPE_H, 0.10)
    else
        -- =====================================================================
        -- 现实模式: 笔记本纸条风格
        -- =====================================================================

        -- 纸张阴影
        local shadowPaint = nvgBoxGradient(vg,
            stripX + 1, stripY + 2, stripW, STRIP_H, CORNER_R, 6,
            nvgRGBA(60, 40, 20, 35),
            nvgRGBA(0, 0, 0, 0))
        nvgBeginPath(vg)
        nvgRect(vg, stripX - 6, stripY - 3, stripW + 12, STRIP_H + 12)
        nvgFillPaint(vg, shadowPaint)
        nvgFill(vg)

        -- 纸条主体 (米黄纸色)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, stripX, stripY, stripW, STRIP_H, CORNER_R)
        nvgFillColor(vg, Theme.rgba(t.notebookPaper))
        nvgFill(vg)

        -- 横线纹理 (淡蓝色)
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

        -- 底部撕裂边缘
        drawTornEdge(vg, stripX, stripY + STRIP_H,
            stripW, t.notebookPaper.r, t.notebookPaper.g, t.notebookPaper.b, 255)

        -- 纸条边框 (上部和两侧，底部撕裂不画边框)
        nvgBeginPath(vg)
        nvgMoveTo(vg, stripX, stripY + STRIP_H)
        nvgLineTo(vg, stripX, stripY + CORNER_R)
        nvgArcTo(vg, stripX, stripY, stripX + CORNER_R, stripY, CORNER_R)
        nvgLineTo(vg, stripX + stripW - CORNER_R, stripY)
        nvgArcTo(vg, stripX + stripW, stripY, stripX + stripW, stripY + CORNER_R, CORNER_R)
        nvgLineTo(vg, stripX + stripW, stripY + STRIP_H)
        nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 100))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        -- 胶带装饰
        drawTape(vg, stripX + 16, stripY + 1, TAPE_W, TAPE_H, -0.12)
        drawTape(vg, stripX + stripW - 16, stripY + 1, TAPE_W, TAPE_H, 0.10)
    end

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
        nvgFillColor(vg, darkMode_ and nvgRGBA(200, 180, 255, 220) or Theme.rgbaA(t.textPrimary, 200))
        local iconEnd = nvgText(vg, cx, stripCY, res.icon, nil)

        -- 标签 (手写风小字)
        nvgFontSize(vg, 9)
        nvgFillColor(vg, darkMode_ and nvgRGBA(180, 160, 220, 160) or Theme.rgbaA(t.textSecondary, 160))
        local labelEnd = nvgText(vg, iconEnd + 1, stripCY - 8, res.label, nil)

        -- 数值
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
            if darkMode_ then
                nvgFillColor(vg, nvgRGBA(rc.r, rc.g, rc.b, 200))
            else
                nvgFillColor(vg, Theme.rgba(rc))
            end
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
            if darkMode_ then
                nvgBeginPath(vg)
                nvgMoveTo(vg, nextX, stripY + SEP_PAD)
                nvgLineTo(vg, nextX, stripY + STRIP_H - SEP_PAD)
                nvgStrokeColor(vg, nvgRGBA(139, 92, 246, 50))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)
            else
                drawSeparator(vg, nextX, stripY, STRIP_H, t)
            end
            cx = nextX + 8
        end
    end

    -- ---- 右半 ----
    local rightX = stripX + stripW - PAD_X - 6

    if darkMode_ then
        -- === 暗面模式: 对称现实模式的双组双行布局 ===
        -- 现实: [Day X / 第X天] | [天气图标 / 天气名]
        -- 暗面: [层级名 / ⚡能量] | [🌀返回图标 / "返回"]

        local iconR = 10  -- 与天气图标相同半径
        local iconCX = rightX - iconR
        local iconCY = stripCY

        -- ── 返回图标 (圆形, 对应天气图标) ──
        -- 外圈光晕
        local glowPaint = nvgRadialGradient(vg,
            iconCX, iconCY, iconR * 0.3, iconR * 1.3,
            nvgRGBA(139, 92, 246, 50), nvgRGBA(139, 92, 246, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, iconCX, iconCY, iconR * 1.3)
        nvgFillPaint(vg, glowPaint)
        nvgFill(vg)

        -- 圆形背景
        nvgBeginPath(vg)
        nvgCircle(vg, iconCX, iconCY, iconR)
        nvgFillColor(vg, nvgRGBA(35, 28, 60, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(139, 92, 246, 80))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        -- 🌀 图标居中
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 180, 255, 230))
        nvgText(vg, iconCX, iconCY, "🌀", nil)

        -- "返回" 小字 (对应天气名称位置)
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 160, 220, 160))
        nvgText(vg, iconCX - iconR - 4, stripCY + 5, "返回", nil)

        -- 缓存按钮点击区域 (整个圆形 + 文字区域)
        darkExitBtnRect_.x = iconCX - iconR - 30
        darkExitBtnRect_.y = stripY
        darkExitBtnRect_.w = iconR * 2 + 30 + PAD_X
        darkExitBtnRect_.h = STRIP_H

        -- ── 层级信息组 (对应 Day X 组) ──
        local infoRightX = iconCX - iconR * 2 - 8

        -- 层级名称 (14px, 对应 "Day X" 主文字)
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(34, 211, 238, 220))
        local layerTW = nvgTextBounds(vg, 0, 0, darkLayerName_, nil) or 40
        nvgText(vg, infoRightX, stripCY - 4, darkLayerName_, nil)

        -- 能量副行 (9px, 对应 "第X天" 副文字)
        local energyRatio = darkMaxEnergy_ > 0 and (darkEnergy_ / darkMaxEnergy_) or 0
        local energyText = "⚡" .. darkEnergy_ .. "/" .. darkMaxEnergy_

        -- 迷你能量条 (嵌入副行, 在文字右侧)
        local miniBarW = 30
        local miniBarH = 4
        local miniBarY = stripCY + 5

        -- 能量文字
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        local eR, eG, eB = 34, 211, 238
        if energyRatio <= 0.3 then eR, eG, eB = 244, 63, 94 end
        local flashAlpha = 160
        if darkEnergyFlash_ > 0 then
            flashAlpha = math.floor(255 * (0.5 + 0.5 * math.sin(darkEnergyFlash_ * 20)))
        end
        nvgFillColor(vg, nvgRGBA(eR, eG, eB, flashAlpha))
        local eTxtRight = infoRightX
        nvgText(vg, eTxtRight, miniBarY, energyText, nil)

        -- 迷你能量条 (能量文字左侧)
        local eTxtW = nvgTextBounds(vg, 0, 0, energyText, nil) or 30
        local mBarX = eTxtRight - eTxtW - miniBarW - 3
        local mBarY = miniBarY - miniBarH / 2

        -- 背景槽
        nvgBeginPath(vg)
        nvgRoundedRect(vg, mBarX, mBarY, miniBarW, miniBarH, 2)
        nvgFillColor(vg, nvgRGBA(20, 15, 40, 180))
        nvgFill(vg)

        -- 填充
        local fillW = miniBarW * energyRatio
        if fillW > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, mBarX, mBarY, fillW, miniBarH, 2)
            nvgFillColor(vg, nvgRGBA(eR, eG, eB, flashAlpha))
            nvgFill(vg)
        end

        -- ── 分隔线 (层级组 和 资源区 之间) ──
        local sepDarkX = infoRightX - math.max(layerTW, eTxtW + miniBarW + 3) - 8
        nvgBeginPath(vg)
        nvgMoveTo(vg, sepDarkX, stripY + SEP_PAD)
        nvgLineTo(vg, sepDarkX, stripY + STRIP_H - SEP_PAD)
        nvgStrokeColor(vg, nvgRGBA(139, 92, 246, 50))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)
    else
        -- === 现实模式: 天数 + 天气 ===

        -- 天气图标
        local weatherType = Weather.getWeather(dayCount)
        local weatherR = 10
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

        local dayTextW = nvgTextBounds(vg, 0, 0, dayText, nil)
        local dayRightX = rightX - weatherR * 2 - 8
        nvgText(vg, dayRightX, stripCY - 4, dayText, nil)

        -- "第X天" 小字
        nvgFontSize(vg, 9)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 140))
        nvgText(vg, dayRightX, stripCY + 7, "第" .. dayCount .. "天", nil)

        -- 天数区和资源区之间的竖线分隔
        drawSeparator(vg, dayRightX - dayTextW - 8, stripY, STRIP_H, t)
    end

    nvgRestore(vg)
end

--- 暗面退出按钮点击测试
---@param lx number 逻辑坐标 X
---@param ly number 逻辑坐标 Y
---@return boolean
function M.hitTestDarkExit(lx, ly)
    if not darkMode_ then return false end
    local r = darkExitBtnRect_
    return lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h
end

return M
