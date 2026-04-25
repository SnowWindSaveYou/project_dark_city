-- ============================================================================
-- HandPanel.lua - 底部笔记本 (日程卡 + 传闻卡)
-- 整本笔记本从屏幕底部滑入/滑出，折叠时仅露出标签栏
-- 米黄纸底 + 横线 + 牛皮书脊 + 传闻便签
-- ============================================================================

local Tween = require "lib.Tween"
local Theme = require "Theme"
local CardManager = require "CardManager"
local ShopPopup   = require "ShopPopup"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
local TAG = "handpanel"

-- 笔记本尺寸
local SPINE_W       = 10        -- 书脊宽度
local TAB_H         = 28        -- 标签栏高度
local BASE_BODY_H   = 140       -- 基础内容区高度 (3条日程)
local LINE_SPACING  = 18        -- 横线间距
local MARGIN_BOTTOM = 8         -- 距屏幕底部
local MARGIN_X      = 20        -- 左右边距
local MAX_W         = 340       -- 最大宽度
local PAGE_PAD      = 12        -- 页面内边距
local CORNER_R      = 4         -- 纸张圆角

-- 日程条目
local ITEM_H        = 28        -- 每条日程行高
local CHECK_SIZE    = 12        -- 勾选框尺寸

-- 传闻便签
local NOTE_W        = 78
local NOTE_H        = 44

-- 道具工具栏
local TOOLBAR_H     = 32        -- 工具栏高度
local TOOLBAR_ICON  = 24        -- 图标区尺寸
local TOOLBAR_GAP   = 6         -- 图标间距

-- 结束今天按钮
local BTN_H         = 26
local BTN_MARGIN    = 6

-- ---------------------------------------------------------------------------
-- 动态高度 (根据日程数量调整)
-- ---------------------------------------------------------------------------

--- 工具栏实际高度 (有消耗品才占空间)
local function getToolbarH()
    local items = ShopPopup.getConsumableOrder()
    if #items == 0 then return 0 end
    return TOOLBAR_H
end

--- 内容区高度：超过3条日程时按条目数扩展 + 工具栏
local function getBodyH()
    local count = #CardManager.getSchedules()
    local base = BASE_BODY_H
    if count > 3 then base = BASE_BODY_H + (count - 3) * ITEM_H end
    return base + getToolbarH()
end

--- 笔记本总高
local function getFullH()
    return TAB_H + getBodyH()
end

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------
local state = {
    visible  = false,
    expanded = false,
    panelY   = 0,       -- 面板顶部 Y (动画驱动)
    alpha    = 0,
    hoverIndex = 0,
    hoverEndDay = false,    -- 结束今天按钮 hover
    hoverToolbar = nil,     -- 工具栏 hover 的 consumable key
}

-- 外部注入的回调
local onEndDayCallback = nil
local onUseExorcismCallback = nil  -- 驱魔香特殊回调 (F4)

-- ---------------------------------------------------------------------------
-- 布局
-- ---------------------------------------------------------------------------

--- 笔记本总是 getFullH() 高度；折叠时大部分滑到屏幕下方
--- 展开时底部溢出屏幕，营造笔记本延伸到屏幕外的效果
local OVERFLOW = 24  -- 底部溢出屏幕的量

local function getTargetY(logicalH)
    if state.expanded then
        -- 底部有一部分在屏幕外，像真实笔记本没完全拉出来
        return logicalH - getFullH() + OVERFLOW
    else
        -- 仅标签栏露出
        return logicalH - TAB_H - MARGIN_BOTTOM
    end
end

local function getPanelRect(logicalW)
    local panelW = math.min(logicalW - MARGIN_X * 2, MAX_W)
    local panelX = (logicalW - panelW) / 2
    return panelX, state.panelY, panelW, getFullH()
end

-- ---------------------------------------------------------------------------
-- 显示 / 隐藏 / 切换
-- ---------------------------------------------------------------------------

function M.show(logicalH)
    if state.visible then return end
    state.visible  = true
    state.expanded = false
    state.alpha    = 0
    state.panelY   = (logicalH or 800) + 20  -- 从屏幕下方滑入

    local targetY = getTargetY(logicalH or 800)
    Tween.to(state, { panelY = targetY, alpha = 1 }, 0.45, {
        easing = Tween.Easing.easeOutBack,
        tag = TAG,
    })
end

function M.hide()
    if not state.visible then return end
    Tween.cancelTag(TAG)
    -- 整本滑出屏幕
    Tween.to(state, { panelY = state.panelY + getFullH() + 30, alpha = 0 }, 0.3, {
        easing = Tween.Easing.easeInQuad,
        tag = TAG,
        onComplete = function()
            state.visible  = false
            state.expanded = false
        end
    })
end

function M.toggle(logicalH)
    state.expanded = not state.expanded
    local targetY = getTargetY(logicalH)
    Tween.to(state, { panelY = targetY }, 0.35, {
        easing = state.expanded and Tween.Easing.easeOutBack or Tween.Easing.easeInOutQuad,
        tag = TAG,
    })
end

function M.isActive()
    return state.visible
end

function M.isExpanded()
    return state.visible and state.expanded
end

--- 注入"结束今天"回调 (由 main.lua 调用)
function M.setEndDayCallback(fn)
    onEndDayCallback = fn
end

--- 注入"使用驱魔香"回调 (由 main.lua 调用, F4)
function M.setUseExorcismCallback(fn)
    onUseExorcismCallback = fn
end

--- 获取"结束今天"按钮的矩形区域 (在溢出区域上方，保证可见)
local function getEndDayBtnRect(px, py, pw)
    local btnW = pw - SPINE_W - PAGE_PAD * 2
    local btnX = px + SPINE_W + PAGE_PAD
    local btnY = py + TAB_H + getBodyH() - OVERFLOW - BTN_H - BTN_MARGIN
    return btnX, btnY, btnW, BTN_H
end

--- 获取工具栏 Y 位置 (结束今天按钮上方)
local function getToolbarY(py)
    local _, btnY, _, _ = getEndDayBtnRect(0, py, 200) -- px/pw 不影响 Y
    return btnY - getToolbarH()
end

--- 获取工具栏中某个图标的矩形 (用于碰撞检测)
local function getToolbarItemRect(px, py, pw, idx, totalCount)
    local toolbarY = getToolbarY(py)
    local contentW = pw - SPINE_W - PAGE_PAD * 2
    local totalItemW = totalCount * TOOLBAR_ICON + (totalCount - 1) * TOOLBAR_GAP
    local startX = px + SPINE_W + PAGE_PAD + (contentW - totalItemW) / 2
    local ix = startX + (idx - 1) * (TOOLBAR_ICON + TOOLBAR_GAP)
    local iy = toolbarY + (TOOLBAR_H - TOOLBAR_ICON) / 2
    return ix, iy, TOOLBAR_ICON, TOOLBAR_ICON
end

-- ---------------------------------------------------------------------------
-- 交互
-- ---------------------------------------------------------------------------

function M.handleClick(lx, ly, logicalW, logicalH)
    if not state.visible or state.alpha < 0.1 then return false end

    local px, py, pw, _ = getPanelRect(logicalW)

    -- 点击不在面板范围内 → 不消费，让事件穿透到棋盘
    -- (玩家可以一边看任务一边点棋盘移动)
    if lx < px or lx > px + pw or ly < py or ly > py + getFullH() then
        return false
    end

    -- 点击标签栏区域 → 折叠/展开
    if ly < py + TAB_H then
        M.toggle(logicalH)
        return true
    end

    -- 折叠状态下标签栏以下不可能被点到（在屏幕外），直接返回
    if not state.expanded then
        return false
    end

    -- 展开状态下点击道具工具栏
    local consumables = ShopPopup.getConsumableOrder()
    if #consumables > 0 then
        for idx, entry in ipairs(consumables) do
            local ix, iy, iw, ih = getToolbarItemRect(px, py, pw, idx, #consumables)
            if lx >= ix and lx <= ix + iw and ly >= iy and ly <= iy + ih then
                if entry.key == "exorcism" then
                    -- 驱魔香：调用外部回调 (F4)
                    if onUseExorcismCallback then
                        onUseExorcismCallback()
                    end
                else
                    -- 普通消耗品：直接使用
                    local ok = ShopPopup.useConsumable(entry.key)
                    if ok then
                        local VFX = require "lib.VFX"
                        local t = Theme.current
                        VFX.spawnBanner(entry.info.icon .. " 使用了" .. entry.info.label,
                            t.safe.r, t.safe.g, t.safe.b, 18, 0.7)
                    end
                end
                return true
            end
        end
    end

    -- 展开状态下点击"结束今天"按钮
    if onEndDayCallback then
        local bx, by, bw, bh = getEndDayBtnRect(px, py, pw)
        if lx >= bx and lx <= bx + bw and ly >= by and ly <= by + bh then
            onEndDayCallback()
            return true
        end
    end

    -- 展开状态下点击日程条目
    local schedules = CardManager.getSchedules()
    local contentX = px + SPINE_W + PAGE_PAD
    local contentY = py + TAB_H + 4

    for i, sched in ipairs(schedules) do
        local itemY = contentY + (i - 1) * ITEM_H
        if ly >= itemY and ly <= itemY + ITEM_H and lx >= contentX and lx <= px + pw - PAGE_PAD then
            if sched.status == "pending" then
                local ok, reason = CardManager.deferSchedule(i)
                if not ok then
                    print("[HandPanel] Cannot defer: " .. tostring(reason))
                end
            elseif sched.status == "deferred" then
                CardManager.undeferSchedule(i)
            end
            return true
        end
    end

    return true  -- 面板内其他区域也消费（防止穿透到棋盘）
end

function M.updateHover(lx, ly, dt, logicalW, logicalH)
    if not state.visible or state.alpha < 0.1 or not state.expanded then
        state.hoverIndex = 0
        state.hoverEndDay = false
        state.hoverToolbar = nil
        return
    end

    local px, py, pw, _ = getPanelRect(logicalW)

    -- "结束今天"按钮 hover
    state.hoverEndDay = false
    if onEndDayCallback then
        local bx, by, bw, bh = getEndDayBtnRect(px, py, pw)
        if lx >= bx and lx <= bx + bw and ly >= by and ly <= by + bh then
            state.hoverEndDay = true
        end
    end

    -- 工具栏 hover
    state.hoverToolbar = nil
    local consumables = ShopPopup.getConsumableOrder()
    for idx, entry in ipairs(consumables) do
        local ix, iy, iw, ih = getToolbarItemRect(px, py, pw, idx, #consumables)
        if lx >= ix and lx <= ix + iw and ly >= iy and ly <= iy + ih then
            state.hoverToolbar = entry.key
            break
        end
    end

    -- 日程条目 hover
    local schedules = CardManager.getSchedules()
    local contentX = px + SPINE_W + PAGE_PAD
    local contentY = py + TAB_H + 4
    state.hoverIndex = 0

    for i = 1, #schedules do
        local itemY = contentY + (i - 1) * ITEM_H
        if ly >= itemY and ly <= itemY + ITEM_H and lx >= contentX and lx <= px + pw - PAGE_PAD then
            state.hoverIndex = i
            break
        end
    end
end

-- ---------------------------------------------------------------------------
-- 渲染
-- ---------------------------------------------------------------------------

function M.draw(vg, logicalW, logicalH, gameTime)
    if not state.visible or state.alpha < 0.05 then return end

    local t = Theme.current
    nvgSave(vg)
    nvgGlobalAlpha(vg, state.alpha)

    local px, py, pw, ph = getPanelRect(logicalW)

    -- 裁剪到屏幕可见区域（折叠时内容在屏幕外不需要绘制）
    nvgIntersectScissor(vg, 0, 0, logicalW, logicalH)

    -- === 纸张阴影 ===
    local shadowPaint = nvgBoxGradient(vg,
        px + 2, py + 3, pw, ph, CORNER_R, 10,
        nvgRGBA(60, 40, 20, math.floor(45 * state.alpha)),
        nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, px - 10, py - 6, pw + 20, ph + 20)
    nvgFillPaint(vg, shadowPaint)
    nvgFill(vg)

    -- === 纸张主体 ===
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, CORNER_R)
    nvgFillColor(vg, Theme.rgba(t.notebookPaper))
    nvgFill(vg)

    -- === 纸张边框 ===
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, CORNER_R)
    nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 140))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- === 左侧书脊 ===
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, SPINE_W, ph, CORNER_R)
    nvgFillColor(vg, Theme.rgba(t.notebookSpine))
    nvgFill(vg)
    -- 书脊高光线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + SPINE_W - 1.5, py + 2)
    nvgLineTo(vg, px + SPINE_W - 1.5, py + ph - 2)
    nvgStrokeColor(vg, Theme.rgbaA(t.notebookSpineH, 120))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)
    -- 书脊装饰线 (模拟缝线)
    for sy = py + 14, py + ph - 10, 16 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + 3, sy)
        nvgLineTo(vg, px + 3, sy + 6)
        nvgStrokeColor(vg, Theme.rgbaA(t.notebookSpineH, 70))
        nvgStrokeWidth(vg, 1.2)
        nvgStroke(vg)
    end

    -- === 标签栏 ===
    M.drawTabBar(vg, px, py, pw, t, gameTime)

    -- === 内容区 (横线 + 日程 + 传闻) ===
    -- 使用 scissor 防止内容溢出到标签栏
    nvgSave(vg)
    nvgIntersectScissor(vg, px + SPINE_W, py + TAB_H, pw - SPINE_W, getBodyH())

    M.drawLines(vg, px, py, pw, ph, t)
    M.drawScheduleItems(vg, px, py, pw, t, gameTime)
    M.drawRumorNote(vg, px, py, pw, t, gameTime)
    M.drawToolbar(vg, px, py, pw, t, gameTime)
    M.drawEndDayBtn(vg, px, py, pw, t)

    nvgRestore(vg)

    nvgRestore(vg)
end

-- ---------------------------------------------------------------------------
-- 标签栏
-- ---------------------------------------------------------------------------

function M.drawTabBar(vg, px, py, pw, t, gameTime)
    local completed, total = CardManager.getProgress()
    local rumors = CardManager.getRumors()

    -- 标签底色
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px + SPINE_W, py, pw - SPINE_W, TAB_H, CORNER_R)
    nvgFillColor(vg, Theme.rgbaA(t.notebookTab, 180))
    nvgFill(vg)

    -- 底部分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + SPINE_W + 6, py + TAB_H - 0.5)
    nvgLineTo(vg, px + pw - 6, py + TAB_H - 0.5)
    nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 100))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    local tabCY = py + TAB_H / 2

    -- 左: 日程
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgba(t.schedule))
    local afterIcon = nvgText(vg, px + SPINE_W + 10, tabCY, "📋", nil)
    nvgFillColor(vg, Theme.rgbaA(t.textPrimary, 200))
    nvgText(vg, afterIcon + 3, tabCY,
        string.format("日程 %d/%d", completed, total), nil)

    -- 右: 传闻
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgbaA(t.textPrimary, 200))
    nvgText(vg, px + pw - 28, tabCY, string.format("传闻 %d", #rumors), nil)
    nvgFillColor(vg, Theme.rgba(t.rumor))
    nvgText(vg, px + pw - 10, tabCY, "📰", nil)

    -- 中间: 拉手 (三条短横线，像笔记本的拉片)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local handleX = px + pw / 2
    local handleY = tabCY
    for i = -1, 1 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, handleX - 8, handleY + i * 3.5)
        nvgLineTo(vg, handleX + 8, handleY + i * 3.5)
        nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 120))
        nvgStrokeWidth(vg, 1.2)
        nvgStroke(vg)
    end
end

-- ---------------------------------------------------------------------------
-- 横线
-- ---------------------------------------------------------------------------

function M.drawLines(vg, px, py, pw, ph, t)
    local startX = px + SPINE_W + 6
    local endX   = px + pw - 6
    local y = py + TAB_H + LINE_SPACING * 0.5

    while y < py + ph - 4 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, startX, y)
        nvgLineTo(vg, endX, y)
        nvgStrokeColor(vg, Theme.rgbaA(t.notebookLine, 70))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)
        y = y + LINE_SPACING
    end

    -- 红色左边距竖线
    local marginX = px + SPINE_W + PAGE_PAD + CHECK_SIZE + 8
    nvgBeginPath(vg)
    nvgMoveTo(vg, marginX, py + TAB_H + 2)
    nvgLineTo(vg, marginX, py + ph - 4)
    nvgStrokeColor(vg, nvgRGBA(210, 120, 120, 45))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)
end

-- ---------------------------------------------------------------------------
-- 日程条目
-- ---------------------------------------------------------------------------

function M.drawScheduleItems(vg, px, py, pw, t, gameTime)
    local schedules = CardManager.getSchedules()
    local contentX = px + SPINE_W + PAGE_PAD
    local contentY = py + TAB_H + 4
    -- 奖励标签右边界：留出传闻便签的空间
    local rewardRightX = px + pw - PAGE_PAD - NOTE_W - 8

    nvgFontFace(vg, "sans")

    for i, sched in ipairs(schedules) do
        local itemY = contentY + (i - 1) * ITEM_H
        local centerY = itemY + ITEM_H / 2
        local isHovered = (state.hoverIndex == i and (sched.status == "pending" or sched.status == "deferred"))

        -- hover 高亮
        if isHovered then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, contentX - 2, itemY + 2,
                pw - SPINE_W - PAGE_PAD * 2 + 4, ITEM_H - 4, 3)
            nvgFillColor(vg, nvgRGBA(75, 163, 227, 18))
            nvgFill(vg)
        end

        -- 勾选框
        local checkX = contentX
        local checkY = centerY - CHECK_SIZE / 2
        nvgBeginPath(vg)
        nvgRoundedRect(vg, checkX, checkY, CHECK_SIZE, CHECK_SIZE, 2)
        nvgStrokeWidth(vg, 1.0)

        if sched.status == "completed" then
            nvgFillColor(vg, Theme.rgbaA(t.completed, 180))
            nvgFill(vg)
            nvgStrokeColor(vg, Theme.rgbaA(t.completed, 220))
            nvgStroke(vg)
            -- 勾号
            nvgBeginPath(vg)
            nvgMoveTo(vg, checkX + 2.5, centerY)
            nvgLineTo(vg, checkX + CHECK_SIZE * 0.4, centerY + 3)
            nvgLineTo(vg, checkX + CHECK_SIZE - 2, centerY - 3.5)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        elseif sched.status == "deferred" then
            nvgStrokeColor(vg, Theme.rgbaA(t.deferred, 120))
            nvgStroke(vg)
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, Theme.rgbaA(t.deferred, 160))
            nvgText(vg, checkX + CHECK_SIZE / 2, centerY, "↗", nil)
        else
            nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 140))
            nvgStroke(vg)
        end

        -- 地点图标
        local textStartX = contentX + CHECK_SIZE + 10
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgba(t.textPrimary))
        local afterEmoji = nvgText(vg, textStartX, centerY, sched.icon, nil)

        -- 日程描述
        nvgFontSize(vg, 12)
        if sched.status == "completed" then
            nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 140))
            local textEndX = nvgText(vg, afterEmoji + 4, centerY, sched.label, nil)
            -- 删除线
            nvgBeginPath(vg)
            nvgMoveTo(vg, afterEmoji + 3, centerY)
            nvgLineTo(vg, textEndX + 1, centerY)
            nvgStrokeColor(vg, Theme.rgbaA(t.textSecondary, 100))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
        elseif sched.status == "deferred" then
            nvgFillColor(vg, Theme.rgbaA(t.deferred, 160))
            nvgText(vg, afterEmoji + 4, centerY, sched.label .. " (明天)", nil)
        else
            nvgFillColor(vg, Theme.rgbaA(t.textPrimary, 220))
            nvgText(vg, afterEmoji + 4, centerY, sched.label, nil)
        end

        -- 奖励标记 (在便签左侧，不会被挡住)
        if sched.status ~= "deferred" then
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            local resLabel = sched.reward[1] == "money" and "💰"
                or sched.reward[1] == "san" and "🧠"
                or sched.reward[1] == "order" and "⚖️"
                or "?"
            nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 140))
            nvgText(vg, rewardRightX, centerY,
                resLabel .. "+" .. sched.reward[2], nil)
        end

        -- hover 提示
        if isHovered then
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            if sched.status == "deferred" then
                nvgFillColor(vg, Theme.rgbaA(t.deferred, 160))
                nvgText(vg, rewardRightX - 40, centerY, "点击取消", nil)
            else
                nvgFillColor(vg, Theme.rgbaA(t.schedule, 160))
                nvgText(vg, rewardRightX - 40, centerY, "点击推迟", nil)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 传闻便签 (贴在笔记本右侧，与日程列表错开)
-- ---------------------------------------------------------------------------

function M.drawRumorNote(vg, px, py, pw, t, gameTime)
    local rumors = CardManager.getRumors()
    if #rumors == 0 then return end

    -- 日程区高度（不含工具栏）
    local count = #CardManager.getSchedules()
    local schedH = BASE_BODY_H
    if count > 3 then schedH = BASE_BODY_H + (count - 3) * ITEM_H end

    -- 便签基准位置：右侧，垂直居中于日程区
    local noteX = px + pw - NOTE_W - PAGE_PAD + 2
    local noteBaseY = py + TAB_H + (schedH - NOTE_H) / 2

    -- 多条传闻堆叠：底层先画 (微偏移)，顶层最后画
    local maxShow = math.min(#rumors, 3)  -- 最多堆叠3张

    for idx = maxShow, 1, -1 do
        local rumor = rumors[idx]
        local stackOffset = (idx - 1) * 4  -- 每层偏移4px
        local rotDeg = 2.0 + (idx - 1) * 1.5 * ((idx % 2 == 0) and -1 or 1)

        nvgSave(vg)
        nvgTranslate(vg, noteX + NOTE_W / 2 + stackOffset, noteBaseY + NOTE_H / 2 + stackOffset)
        nvgRotate(vg, rotDeg * math.pi / 180)
        nvgTranslate(vg, -NOTE_W / 2, -NOTE_H / 2)

        -- 底层便签半透明
        local layerAlpha = (idx == 1) and 1.0 or (0.7 - (idx - 2) * 0.15)
        nvgGlobalAlpha(vg, state.alpha * layerAlpha)

        -- 阴影
        nvgBeginPath(vg)
        nvgRect(vg, 2, 2, NOTE_W, NOTE_H)
        nvgFillColor(vg, nvgRGBA(80, 60, 40, 25))
        nvgFill(vg)

        -- 底色
        local noteColor = rumor.isSafe
            and nvgRGBA(228, 242, 228, 240)
            or  nvgRGBA(248, 232, 218, 240)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, NOTE_W, NOTE_H)
        nvgFillColor(vg, noteColor)
        nvgFill(vg)

        -- 边框
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, NOTE_W, NOTE_H)
        nvgStrokeColor(vg, nvgRGBA(180, 165, 140, 70))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        -- 胶带
        nvgBeginPath(vg)
        nvgRect(vg, NOTE_W / 2 - 16, -3, 32, 7)
        nvgFillColor(vg, nvgRGBA(210, 205, 190, 80))
        nvgFill(vg)

        -- 图标 + 状态
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        nvgFontSize(vg, 15)
        nvgFillColor(vg, Theme.rgba(t.textPrimary))
        nvgText(vg, NOTE_W / 2, 12, rumor.icon, nil)

        nvgFontSize(vg, 10)
        local sc = rumor.isSafe and t.safe or t.danger
        nvgFillColor(vg, Theme.rgba(sc))
        nvgText(vg, NOTE_W / 2, 26, rumor.isSafe and "✓ 安全" or "⚠ 危险", nil)

        -- 传闻文字
        nvgFontSize(vg, 7.5)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 180))
        nvgText(vg, NOTE_W / 2, 38, rumor.text, nil)

        nvgRestore(vg)
    end
end

-- ---------------------------------------------------------------------------
-- 道具工具栏 (日程区下方，横排小图标)
-- ---------------------------------------------------------------------------

function M.drawToolbar(vg, px, py, pw, t, gameTime)
    local consumables = ShopPopup.getConsumableOrder()
    if #consumables == 0 then return end

    local toolbarY = getToolbarY(py)

    -- 虚线分隔 (工具栏上方)
    local dashX = px + SPINE_W + PAGE_PAD
    local dashEndX = px + pw - PAGE_PAD
    local dashLineY = toolbarY + 2
    nvgBeginPath(vg)
    local dx = dashX
    while dx < dashEndX do
        nvgMoveTo(vg, dx, dashLineY)
        nvgLineTo(vg, math.min(dx + 3, dashEndX), dashLineY)
        dx = dx + 7
    end
    nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 60))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- "背包" 小标签
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 120))
    nvgText(vg, dashX, dashLineY + 2, "🎒 道具", nil)

    -- 图标列表
    local count = #consumables
    for idx, entry in ipairs(consumables) do
        local ix, iy, iw, ih = getToolbarItemRect(px, py, pw, idx, count)
        local isHovered = (state.hoverToolbar == entry.key)
        local cx = ix + iw / 2
        local cy = iy + ih / 2

        -- hover 底色
        if isHovered then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix - 2, iy - 2, iw + 4, ih + 4, 4)
            nvgFillColor(vg, nvgRGBA(75, 163, 227, 30))
            nvgFill(vg)
        end

        -- 图标背景圆
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, iw / 2)
        local bgAlpha = isHovered and 50 or 30
        nvgFillColor(vg, Theme.rgbaA(t.notebookBorder, bgAlpha))
        nvgFill(vg)

        -- 图标
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgba(t.textPrimary))
        nvgText(vg, cx, cy, entry.info.icon, nil)

        -- 数量角标
        if entry.count > 1 then
            local badgeX = ix + iw - 1
            local badgeY = iy + 2
            nvgBeginPath(vg)
            nvgCircle(vg, badgeX, badgeY, 5)
            nvgFillColor(vg, Theme.rgbaA(t.info, 200))
            nvgFill(vg)
            nvgFontSize(vg, 7)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgText(vg, badgeX, badgeY, tostring(entry.count), nil)
        end

        -- hover 时显示效果提示
        if isHovered then
            -- 构建效果文本
            local resNames = { san = "理智", order = "秩序", film = "胶卷" }
            local parts = {}
            for _, eff in ipairs(entry.info.effects) do
                local rn = resNames[eff[1]] or eff[1]
                if eff[1] == "exorcism" then
                    parts[#parts + 1] = "驱除当前怪物"
                else
                    local sign = eff[2] > 0 and "+" or ""
                    parts[#parts + 1] = rn .. sign .. eff[2]
                end
            end
            local tip = entry.info.label .. ": " .. table.concat(parts, ", ")

            -- 气泡背景 (笔记本纸色 + 边框)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 9)
            local tw = nvgTextBounds(vg, 0, 0, tip, nil)
            local tipX = cx
            local tipY = iy - 4
            local padX, padY = 6, 3
            local bx = tipX - tw / 2 - padX
            local by = tipY - 9 - padY
            local bw = tw + padX * 2
            local bh = 10 + padY * 2
            -- 阴影
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx + 1, by + 1, bw, bh, 3)
            nvgFillColor(vg, Theme.rgbaA(t.notebookBorder, 40))
            nvgFill(vg)
            -- 填充
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, bw, bh, 3)
            nvgFillColor(vg, Theme.rgbaA(t.notebookPaper, 245))
            nvgFill(vg)
            -- 边框
            nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 120))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)

            -- 文字
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, Theme.rgba(t.textPrimary))
            nvgText(vg, tipX, tipY, tip, nil)
        end
    end
end

-- ---------------------------------------------------------------------------
-- "结束今天"按钮 (笔记本底部，像手写的一行字)
-- ---------------------------------------------------------------------------

function M.drawEndDayBtn(vg, px, py, pw, t)
    if not onEndDayCallback then return end

    local bx, by, bw, bh = getEndDayBtnRect(px, py, pw)
    local centerY = by + bh / 2

    -- hover 底色
    if state.hoverEndDay then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bw, bh, 3)
        nvgFillColor(vg, nvgRGBA(180, 120, 80, 25))
        nvgFill(vg)
    end

    -- 虚线分隔
    local dashX = bx + 4
    local dashEndX = bx + bw - 4
    local dashY = by - 1
    nvgBeginPath(vg)
    local dx = dashX
    while dx < dashEndX do
        nvgMoveTo(vg, dx, dashY)
        nvgLineTo(vg, math.min(dx + 4, dashEndX), dashY)
        dx = dx + 8
    end
    nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 80))
    nvgStrokeWidth(vg, 0.6)
    nvgStroke(vg)

    -- 文字：像手写的笔记
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local alpha = state.hoverEndDay and 240 or 160
    nvgFillColor(vg, nvgRGBA(140, 90, 50, alpha))
    nvgText(vg, bx + bw / 2, centerY, "☾ 结束今天，回家休息", nil)
end

--- 重置
function M.reset()
    Tween.cancelTag(TAG)
    state.visible  = false
    state.expanded = false
    state.alpha    = 0
    state.hoverIndex = 0
    state.hoverEndDay = false
    state.hoverToolbar = nil
end

return M
