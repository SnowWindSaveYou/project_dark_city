-- ============================================================================
-- ResourceBar.lua - 资源数值 HUD (动画滚动 + 闪光)
-- San(理智) / Order(秩序) / Film(胶卷) / Money(钱币)
-- ============================================================================

local Tween = require "lib.Tween"
local Theme = require "Theme"

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
        { key = "san",   icon = "🧠", label = "理智", value = 100, displayValue = 100, maxValue = 100,
          colorKey = "info",      flashTimer = 0, flashDir = 0, deltaText = "", deltaAlpha = 0 },
        { key = "order", icon = "⚖️",  label = "秩序", value = 80,  displayValue = 80,  maxValue = 100,
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
    -- 查找资源 (包括独立的 filmData)
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

    -- 数值滚动动画
    Tween.to(res, { displayValue = res.value }, 0.5, {
        easing = Tween.Easing.easeOutCubic,
        tag = "resource_" .. key,
    })

    -- 闪烁
    res.flashTimer = 0.6
    res.flashDir = actualDelta > 0 and 1 or -1

    -- 变化量浮动文字
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
-- 渲染 — 顶部水平资源栏
-- ---------------------------------------------------------------------------

---@param vg userdata
---@param logicalW number
---@param logicalH number
function M.draw(vg, logicalW, logicalH)
    local t = Theme.current
    local count = #resources
    if count == 0 then return end

    -- 布局参数 (图标 + 数字，无标签，无面板背景)
    local gap = 24
    local startY = 16   -- 顶部 Y
    local startX = 20   -- 左侧起始 X

    nvgFontFace(vg, "sans")

    -- 各资源项：图标 数字，横排
    local cx = startX
    for i, res in ipairs(resources) do
        local rc = Theme.color(res.colorKey)
        local displayNum = math.floor(res.displayValue + 0.5)

        -- 图标
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgba(t.textPrimary))
        local iconEnd = nvgText(vg, cx, startY + 10, res.icon, nil)

        -- 数值
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        -- 数值颜色：闪烁时变色
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
        local numEnd = nvgText(vg, iconEnd + 2, startY + 10, tostring(displayNum), nil)

        -- 变化量浮动文字
        if res.deltaAlpha > 0.01 then
            local dy = -10 * (1 - res.deltaAlpha)
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
            if res.flashDir > 0 then
                nvgFillColor(vg, nvgRGBA(t.safe.r, t.safe.g, t.safe.b,
                    math.floor(res.deltaAlpha * 255)))
            else
                nvgFillColor(vg, nvgRGBA(t.danger.r, t.danger.g, t.danger.b,
                    math.floor(res.deltaAlpha * 255)))
            end
            nvgText(vg, numEnd + 2, startY + 10 + dy, res.deltaText, nil)
        end

        cx = numEnd + gap
    end
end

return M
