-- ============================================================================
-- HandPanel.lua - 左侧笔记本 (日程 + 传闻 + 道具)
-- 笔记本从屏幕左侧水平弹入，折叠时轻微倾斜露出便签角
-- 米黄纸底 + 横线 + 牛皮书脊 + 多 Tab 便签贴
-- ============================================================================

local Tween        = require "lib.Tween"
local Theme        = require "Theme"
local CardManager  = require "CardManager"
local ShopPopup    = require "ShopPopup"
local ItemIcons    = require "ItemIcons"
local AudioManager = require "AudioManager"
local ResourceBar  = require "ResourceBar"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
local TAG          = "handpanel"
local TAG_SHOWCASE = "handpanel_showcase"

-- 笔记本尺寸
local PANEL_W      = 200          -- 笔记本宽度（窄一点更像笔记本）
local MARGIN_TOP   = 56           -- 上边距：ResourceBar 约 44px，再留 12px 间隙
local MARGIN_BOT   = 20           -- 下边距
local SPINE_W      = 14           -- 书脊宽度
local CORNER_R     = 5            -- 纸张圆角
local PAGE_PAD     = 10           -- 页面内边距
local LINE_SPACING = 18           -- 横线间距

-- 折叠/展开位置
local EXPANDED_X   = 6            -- 展开：左边缘距屏幕左侧
local PEEK_W       = 6            -- 折叠时露出的笔记本主体宽度
local HIDDEN_EXTRA = 50           -- 隐藏时额外移出屏幕的量

-- 折叠时倾斜角度（顺时针，弧度）
local TILT_COLLAPSED = 0.12       -- 约 6.9°

-- 便签贴：从笔记本右边缘伸出，左侧 OVERLAP 像素与笔记本重叠
local TAB_LABEL_W   = 36          -- 便签总宽
local TAB_LABEL_H   = 48          -- 便签高
local TAB_LABEL_GAP = 8           -- 便签间距
local TAB_LABEL_RADIUS = 3        -- 便签圆角
local TAB_OVERLAP   = 10          -- 便签与笔记本右边缘重叠像素

-- Tab 配置
local NUM_TABS  = 3
local TAB_NAMES = { "日程", "道具", "线索" }
-- 便签颜色 RGB
local TAB_BG_COLORS = {
    { 245, 228, 148 },   -- 暖黄
    { 180, 210, 240 },   -- 淡蓝
    { 180, 228, 185 },   -- 淡绿
}

-- 日程条目
local ITEM_H       = 26           -- 每条日程行高
local CHECK_SIZE   = 11           -- 勾选框尺寸

-- 传闻便签（内嵌在 Tab1 下半区）
local NOTE_W       = 84
local NOTE_H       = 46

-- 道具图标
local ICON_SIZE    = 40
local ICON_GAP     = 8
local ICONS_PER_ROW = 3

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------
local state = {
    visible        = false,
    expanded       = false,
    showcasing     = false,
    panelX         = -(PANEL_W + (TAB_LABEL_W - TAB_OVERLAP) + HIDDEN_EXTRA),
    panelAngle     = TILT_COLLAPSED,
    alpha          = 0,
    activeTab      = 1,
    hoverTab       = 0,
    hoverIndex     = 0,
    hoverItem      = nil,
    hoverCloseBtn   = false,   -- hover 收起按钮
    hoverEndDayBtn  = false,   -- hover 结束今天按钮
    rumorPage       = 1,
    wasAllDone      = false,   -- 上帧是否全部完成（用于过渡检测）
}

local currentGameTime = 0     -- M.draw 每帧写入，供子函数读取动效时间

-- 缓存 logicalH
local storedLogicalH = 800

-- 外部回调
local onUseExorcismCallback = nil
local onAdvanceDayCallback  = nil

-- ---------------------------------------------------------------------------
-- 布局计算
-- ---------------------------------------------------------------------------

local function getPanelH(logicalH)
    -- 限制最大高度：宽高比不超过 0.62（竖式笔记本比例），且不小于 320px
    local maxH = math.floor(PANEL_W / 0.62)   -- ≈ 323px
    local rawH = logicalH - MARGIN_TOP - MARGIN_BOT
    return math.max(320, math.min(rawH, maxH))
end

--- 返回笔记本主体矩形（不含便签贴）
local function getPanelRect(logicalH)
    local pw = PANEL_W
    local ph = getPanelH(logicalH)
    local px = state.panelX
    local py = MARGIN_TOP
    return px, py, pw, ph
end

--- 展开目标 X
local function expandedX()
    return EXPANDED_X
end

--- 折叠目标 X（只有 PEEK_W 露在屏幕内，其余滑出）
local function collapsedX()
    return -(PANEL_W - PEEK_W)
end

--- 隐藏目标 X（完全移出屏幕）
local function hiddenX()
    return -(PANEL_W + (TAB_LABEL_W - TAB_OVERLAP) + HIDDEN_EXTRA)
end

--- 目标 X（根据当前 visible/expanded 状态）
local function getTargetX()
    if not state.visible then return hiddenX() end
    if state.expanded   then return expandedX() end
    return collapsedX()
end

--- 目标倾角
local function getTargetAngle()
    if state.expanded then return 0 end
    return TILT_COLLAPSED
end

-- ---------------------------------------------------------------------------
-- 便签贴屏幕坐标（Pass2，不受旋转影响）
-- ---------------------------------------------------------------------------
local function getTabLabelRect(logicalH, tabIdx)
    -- 便签贴左侧 TAB_OVERLAP 像素与笔记本右边缘重叠，其余部分伸出去
    local lx = state.panelX + PANEL_W - TAB_OVERLAP
    local totalH = NUM_TABS * TAB_LABEL_H + (NUM_TABS - 1) * TAB_LABEL_GAP
    local startY = MARGIN_TOP + (getPanelH(logicalH) - totalH) / 2
    local ly = startY + (tabIdx - 1) * (TAB_LABEL_H + TAB_LABEL_GAP)
    return lx, ly, TAB_LABEL_W, TAB_LABEL_H
end

-- ---------------------------------------------------------------------------
-- 动画驱动
-- ---------------------------------------------------------------------------

local function animateTo(targetX, targetAngle, easing, duration, onComplete)
    Tween.cancelTag(TAG)
    Tween.to(state, { panelX = targetX, panelAngle = targetAngle, alpha = 1 }, duration, {
        easing = easing,
        tag = TAG,
        onComplete = onComplete,
    })
end

-- ---------------------------------------------------------------------------
-- 显示 / 隐藏 / 切换
-- ---------------------------------------------------------------------------

function M.show(logicalH, opts)
    if state.visible then return end
    opts = opts or {}
    local showcase = opts.showcase or false

    storedLogicalH = logicalH or 800
    state.visible  = true
    state.alpha    = 0
    state.panelX   = hiddenX()

    if showcase then
        state.expanded   = true
        state.showcasing = true

        animateTo(expandedX(), 0, Tween.Easing.easeOutBack, 0.5, function()
            local delay = { t = 0 }
            Tween.to(delay, { t = 1 }, 2.0, {
                tag = TAG_SHOWCASE,
                onComplete = function()
                    if state.showcasing then M.finishShowcase() end
                end
            })
        end)
    else
        state.expanded   = false
        state.showcasing = false
        animateTo(collapsedX(), TILT_COLLAPSED, Tween.Easing.easeOutBack, 0.45)
    end
end

function M.finishShowcase()
    if not state.showcasing then return end
    state.showcasing = false
    state.expanded   = false
    Tween.cancelTag(TAG_SHOWCASE)
    Tween.cancelTag(TAG)
    animateTo(collapsedX(), TILT_COLLAPSED, Tween.Easing.easeInOutQuad, 0.4)
end

function M.hide()
    if not state.visible then return end
    Tween.cancelTag(TAG)
    Tween.cancelTag(TAG_SHOWCASE)
    state.showcasing = false
    Tween.to(state, { panelX = hiddenX(), panelAngle = TILT_COLLAPSED, alpha = 0 }, 0.3, {
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
    local tx = getTargetX()
    local ta = getTargetAngle()
    local ease = state.expanded
        and Tween.Easing.easeOutBack
        or  Tween.Easing.easeInOutQuad
    Tween.cancelTag(TAG)
    Tween.to(state, { panelX = tx, panelAngle = ta }, 0.35, {
        easing = ease, tag = TAG
    })
end

function M.isActive()   return state.visible end
function M.isExpanded() return state.visible and state.expanded end

--- 注入"使用驱魔香"回调（由 main.lua 调用）
function M.setUseExorcismCallback(fn)
    onUseExorcismCallback = fn
end

--- 注入"结束今天"回调（由 main.lua 调用）
function M.setAdvanceDayCallback(fn)
    onAdvanceDayCallback = fn
end

--- 每帧更新：检测"全部完成"过渡，自动展开日程页
function M.update(dt, logicalH)
    if not state.visible then return end

    local schedules = CardManager.getSchedules()
    if #schedules == 0 then return end

    local allDone = true
    for _, s in ipairs(schedules) do
        if s.status == "pending" then allDone = false; break end
    end
    local su2, sm2 = ResourceBar.getSteps()
    local stepsExhausted2 = sm2 > 0 and su2 >= sm2
    local canAdvance = allDone or stepsExhausted2

    if canAdvance and not state.wasAllDone then
        -- 刚刚达成进入下一天条件：自动展开笔记本并切换到日程 tab
        state.activeTab = 1
        if not state.expanded then
            state.expanded = true
            local tx = getTargetX()
            local ta = getTargetAngle()
            Tween.cancelTag(TAG)
            Tween.to(state, { panelX = tx, panelAngle = ta }, 0.35, {
                easing = Tween.Easing.easeOutBack, tag = TAG
            })
        end
    end

    state.wasAllDone = canAdvance
end

--- 重置
function M.reset()
    Tween.cancelTag(TAG)
    Tween.cancelTag(TAG_SHOWCASE)
    state.visible    = false
    state.expanded   = false
    state.showcasing = false
    state.alpha      = 0
    state.panelX     = hiddenX()
    state.panelAngle = TILT_COLLAPSED
    state.hoverIndex = 0
    state.hoverTab   = 0
    state.hoverItem  = nil
    state.wasAllDone = false
end

-- ---------------------------------------------------------------------------
-- 渲染：笔记本主体
-- ---------------------------------------------------------------------------

local function drawNotebookBody(vg, px, py, pw, ph, t)
    -- 阴影
    local shadowPaint = nvgBoxGradient(vg,
        px + 3, py + 4, pw, ph, CORNER_R, 12,
        nvgRGBA(60, 40, 20, 50), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, px - 8, py - 8, pw + 20, ph + 20)
    nvgFillPaint(vg, shadowPaint)
    nvgFill(vg)

    -- 纸张主体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, CORNER_R)
    nvgFillColor(vg, Theme.rgba(t.notebookPaper))
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, CORNER_R)
    nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 130))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 书脊
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, SPINE_W, ph, CORNER_R)
    nvgFillColor(vg, Theme.rgba(t.notebookSpine))
    nvgFill(vg)
    -- 书脊高光线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + SPINE_W - 1.5, py + 2)
    nvgLineTo(vg, px + SPINE_W - 1.5, py + ph - 2)
    nvgStrokeColor(vg, Theme.rgbaA(t.notebookSpineH, 110))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)
    -- 书脊缝线点
    for sy = py + 14, py + ph - 12, 16 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + 4, sy)
        nvgLineTo(vg, px + 4, sy + 6)
        nvgStrokeColor(vg, Theme.rgbaA(t.notebookSpineH, 65))
        nvgStrokeWidth(vg, 1.2)
        nvgStroke(vg)
    end

    -- 横线
    local lx0 = px + SPINE_W + 6
    local lx1 = px + pw - 6
    local ly  = py + LINE_SPACING * 1.2
    while ly < py + ph - 4 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, lx0, ly)
        nvgLineTo(vg, lx1, ly)
        nvgStrokeColor(vg, Theme.rgbaA(t.notebookLine, 60))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)
        ly = ly + LINE_SPACING
    end

    -- 红色左边距竖线
    local marginX = px + SPINE_W + PAGE_PAD + CHECK_SIZE + 8
    nvgBeginPath(vg)
    nvgMoveTo(vg, marginX, py + 4)
    nvgLineTo(vg, marginX, py + ph - 4)
    nvgStrokeColor(vg, nvgRGBA(210, 120, 120, 40))
    nvgStrokeWidth(vg, 0.7)
    nvgStroke(vg)
end

-- ---------------------------------------------------------------------------
-- 渲染：页眉
-- ---------------------------------------------------------------------------

local function drawPageHeader(vg, px, py, pw, ph, t)
    local tabName = TAB_NAMES[state.activeTab]
    local cx = px + SPINE_W + (pw - SPINE_W) / 2
    local headerY = py + 14

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 140))
    nvgText(vg, cx, headerY, "— " .. tabName .. " —", nil)

    -- 页眉下分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + SPINE_W + 10, headerY + 8)
    nvgLineTo(vg, px + pw - 10, headerY + 8)
    nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 70))
    nvgStrokeWidth(vg, 0.6)
    nvgStroke(vg)

    -- 收起箭头（仅展开时显示）：右上角，点击可折叠
    if state.expanded then
        local btnX = px + pw - 9
        local btnY = py + 7
        local btnR = 7
        -- 圆形底
        nvgBeginPath(vg)
        nvgCircle(vg, btnX, btnY, btnR)
        nvgFillColor(vg, Theme.rgbaA(t.notebookBorder, state.hoverCloseBtn and 55 or 28))
        nvgFill(vg)
        -- 箭头 ‹（向左表示收起）
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, state.hoverCloseBtn and 220 or 140))
        nvgText(vg, btnX, btnY + 1, "‹", nil)
    end
end

-- ---------------------------------------------------------------------------
-- 渲染：Tab1 日程 + 传闻
-- ---------------------------------------------------------------------------

local function drawSchedules(vg, px, py, pw, ph, t)
    local schedules = CardManager.getSchedules()
    local contentX = px + SPINE_W + PAGE_PAD
    local contentY = py + 28     -- 页眉下方

    -- 可用内容高度（留出传闻区域；结束今天用叠加样式，不额外占位）
    local rumorAreaH = NOTE_H + 24
    local schedAreaH = ph - 28 - rumorAreaH - 4
    local maxVisible = math.floor(schedAreaH / ITEM_H)

    nvgFontFace(vg, "sans")

    for i = 1, math.min(#schedules, maxVisible) do
        local sched = schedules[i]
        local itemY  = contentY + (i - 1) * ITEM_H
        local centerY = itemY + ITEM_H / 2
        local isHovered = (state.hoverIndex == i
            and (sched.status == "pending" or sched.status == "deferred"))

        -- hover 高亮
        if isHovered then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, contentX - 2, itemY + 2,
                pw - SPINE_W - PAGE_PAD * 2 + 4 - 2, ITEM_H - 4, 3)
            nvgFillColor(vg, nvgRGBA(75, 163, 227, 18))
            nvgFill(vg)
        end

        -- 勾选框
        local ckX = contentX
        local ckY = centerY - CHECK_SIZE / 2
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ckX, ckY, CHECK_SIZE, CHECK_SIZE, 2)
        nvgStrokeWidth(vg, 1.0)

        if sched.status == "completed" then
            nvgFillColor(vg, Theme.rgbaA(t.completed, 180))
            nvgFill(vg)
            nvgStrokeColor(vg, Theme.rgbaA(t.completed, 220))
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, ckX + 2.5, centerY)
            nvgLineTo(vg, ckX + CHECK_SIZE * 0.42, centerY + 3)
            nvgLineTo(vg, ckX + CHECK_SIZE - 2, centerY - 3.5)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        elseif sched.status == "deferred" then
            nvgStrokeColor(vg, Theme.rgbaA(t.deferred, 120))
            nvgStroke(vg)
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, Theme.rgbaA(t.deferred, 160))
            nvgText(vg, ckX + CHECK_SIZE / 2, centerY, "↗", nil)
        else
            nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 140))
            nvgStroke(vg)
        end

        -- 地点图标 + 文字
        local textX = contentX + CHECK_SIZE + 6
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgba(t.textPrimary))
        local afterEmoji = nvgText(vg, textX, centerY, sched.icon, nil)

        nvgFontSize(vg, 11)
        if sched.status == "completed" then
            nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 130))
            local textEndX = nvgText(vg, afterEmoji + 3, centerY, sched.label, nil)
            nvgBeginPath(vg)
            nvgMoveTo(vg, afterEmoji + 2, centerY)
            nvgLineTo(vg, textEndX, centerY)
            nvgStrokeColor(vg, Theme.rgbaA(t.textSecondary, 100))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
        elseif sched.status == "deferred" then
            nvgFillColor(vg, Theme.rgbaA(t.deferred, 160))
            nvgText(vg, afterEmoji + 3, centerY, sched.label, nil)
        else
            nvgFillColor(vg, Theme.rgbaA(t.textPrimary, 220))
            nvgText(vg, afterEmoji + 3, centerY, sched.label, nil)
        end

        -- 奖励角标（右对齐）
        if sched.status ~= "deferred" then
            local resLabel = sched.reward[1] == "money" and "💰"
                or sched.reward[1] == "san" and "🧠"
                or sched.reward[1] == "order" and "⚖️"
                or "?"
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 120))
            nvgText(vg, px + pw - PAGE_PAD - 2, centerY,
                resLabel .. "+" .. sched.reward[2], nil)
        end
    end

    -- 超出显示数量时的省略提示
    if #schedules > maxVisible then
        local moreY = contentY + maxVisible * ITEM_H + 4
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 110))
        nvgText(vg, px + SPINE_W + (pw - SPINE_W) / 2, moreY,
            string.format("还有 %d 条…", #schedules - maxVisible), nil)
    end

    -- ---- 结束今天（页脚分隔线 + 文字，日程全部完成 OR 步数耗尽时显示）----
    local hasPending = false
    local pendingCount = 0
    for _, s in ipairs(schedules) do
        if s.status == "pending" then
            hasPending = true
            pendingCount = pendingCount + 1
        end
    end
    local su, sm = ResourceBar.getSteps()
    local stepsExhausted = sm > 0 and su >= sm  -- 有步数上限且已耗尽

    -- footer 定位：贴近最后一条日程下方（至多距传闻上沿 30px）
    local lastIdx = math.min(#schedules, maxVisible)
    local noteY   = py + ph - NOTE_H - 14
    local rawFooterY = contentY + lastIdx * ITEM_H + 14
    local footerY = math.min(rawFooterY, noteY - 30)
    local footerX = px + SPINE_W + PAGE_PAD
    local footerW = pw - SPINE_W - PAGE_PAD * 2
    local isHov   = state.hoverEndDayBtn

    if not hasPending or stepsExhausted then
        -- 全部完成 OR 步数耗尽：琥珀分隔线 + 呼吸光效文字
        local pulse     = 0.72 + 0.28 * math.sin(currentGameTime * 2.6)
        local lineAlpha = isHov and 200 or math.floor(90 * pulse + 40)
        nvgBeginPath(vg)
        nvgMoveTo(vg, footerX + 8, footerY)
        nvgLineTo(vg, footerX + footerW - 8, footerY)
        nvgStrokeColor(vg, nvgRGBA(210, 160, 60, lineAlpha))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        -- 箭头随时间轻微右移（邀请点击感）
        local arrowNudge = isHov and 3 or (1.5 * math.sin(currentGameTime * 2.0))
        local wc = t.warning
        local textAlpha = isHov and 255 or math.floor(170 * pulse + 55)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(wc.r, wc.g, wc.b, textAlpha))
        nvgText(vg, footerX + footerW / 2 + arrowNudge, footerY + 9, "结束今天 →", nil)
    else
        -- 有未完成项：极低调灰色小字，不抢注意力
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(160, 148, 130, 60))
        nvgText(vg, footerX + footerW / 2, footerY + 9,
            string.format("还有 %d 项待完成", pendingCount), nil)
    end
end

local function drawRumorsInline(vg, px, py, pw, ph, t)
    local rumors = CardManager.getRumors()
    if #rumors == 0 then
        -- 占位提示
        local cx = px + SPINE_W + (pw - SPINE_W) / 2
        local cy = py + ph - NOTE_H / 2 - 14
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 80))
        nvgText(vg, cx, cy, "暂无传闻", nil)
        return
    end

    -- 保证页码在范围内
    if state.rumorPage > #rumors then state.rumorPage = 1 end
    if state.rumorPage < 1 then state.rumorPage = #rumors end

    local rumor = rumors[state.rumorPage]

    -- 便签区域，位于 Tab1 下半部分
    local noteX = px + SPINE_W + (pw - SPINE_W - NOTE_W) / 2
    local noteY = py + ph - NOTE_H - 14

    -- 多条时：底层偏移便签
    if #rumors > 1 then
        local maxLayer = math.min(#rumors - 1, 2)
        for layer = maxLayer, 1, -1 do
            local peekIdx = ((state.rumorPage - 1 + layer) % #rumors) + 1
            local peekRumor = rumors[peekIdx]
            local stackOff = layer * 3
            local rotDeg = (1.5 + layer * 1.6) * ((peekIdx % 2 == 0) and -1 or 1)

            nvgSave(vg)
            nvgTranslate(vg, noteX + NOTE_W / 2 + stackOff, noteY + NOTE_H / 2 + stackOff)
            nvgRotate(vg, rotDeg * math.pi / 180)
            nvgTranslate(vg, -NOTE_W / 2, -NOTE_H / 2)
            nvgGlobalAlpha(vg, state.alpha * (0.35 - (layer - 1) * 0.1))
            local bgC = peekRumor.isSafe
                and nvgRGBA(218, 240, 218, 220)
                or  nvgRGBA(242, 224, 210, 220)
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, NOTE_W, NOTE_H)
            nvgFillColor(vg, bgC)
            nvgFill(vg)
            nvgRestore(vg)
        end
    end

    -- 顶层便签
    nvgSave(vg)
    nvgTranslate(vg, noteX + NOTE_W / 2, noteY + NOTE_H / 2)
    nvgRotate(vg, 1.8 * math.pi / 180)
    nvgTranslate(vg, -NOTE_W / 2, -NOTE_H / 2)

    -- 阴影
    nvgBeginPath(vg)
    nvgRect(vg, 2, 2, NOTE_W, NOTE_H)
    nvgFillColor(vg, nvgRGBA(80, 60, 40, 20))
    nvgFill(vg)

    -- 底色
    local noteColor = rumor.isSafe
        and nvgRGBA(228, 244, 228, 245)
        or  nvgRGBA(250, 232, 218, 245)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, NOTE_W, NOTE_H)
    nvgFillColor(vg, noteColor)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, NOTE_W, NOTE_H)
    nvgStrokeColor(vg, nvgRGBA(180, 165, 140, 60))
    nvgStrokeWidth(vg, 0.7)
    nvgStroke(vg)

    -- 胶带
    nvgBeginPath(vg)
    nvgRect(vg, NOTE_W / 2 - 14, -3, 28, 6)
    nvgFillColor(vg, nvgRGBA(210, 205, 190, 75))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    nvgFontSize(vg, 14)
    nvgFillColor(vg, Theme.rgba(t.textPrimary))
    nvgText(vg, NOTE_W / 2, 11, rumor.icon, nil)

    nvgFontSize(vg, 9)
    local sc = rumor.isSafe and t.safe or t.danger
    nvgFillColor(vg, Theme.rgba(sc))
    nvgText(vg, NOTE_W / 2, 24, rumor.isSafe and "✓ 安全" or "⚠ 危险", nil)

    nvgFontSize(vg, 7.5)
    nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 170))
    nvgText(vg, NOTE_W / 2, 37, rumor.text, nil)

    if #rumors > 1 then
        nvgFontSize(vg, 7)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 140))
        nvgText(vg, NOTE_W / 2, NOTE_H + 7,
            string.format("▶ %d/%d", state.rumorPage, #rumors), nil)
    end

    nvgRestore(vg)
end

local function drawTab1(vg, px, py, pw, ph, t)
    drawSchedules(vg, px, py, pw, ph, t)
    drawRumorsInline(vg, px, py, pw, ph, t)
end

-- ---------------------------------------------------------------------------
-- 渲染：Tab2 道具
-- ---------------------------------------------------------------------------

local function drawTab2(vg, px, py, pw, ph, t)
    local consumables = ShopPopup.getConsumableOrder()
    local contentX = px + SPINE_W + PAGE_PAD
    local contentY = py + 28
    local contentW = pw - SPINE_W - PAGE_PAD * 2

    nvgFontFace(vg, "sans")

    if #consumables == 0 then
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 100))
        nvgText(vg, px + SPINE_W + contentW / 2, contentY + 30, "背包空空如也", nil)
        return
    end

    -- 图标网格
    local col = 0
    local row = 0
    for idx, entry in ipairs(consumables) do
        local ix = contentX + col * (ICON_SIZE + ICON_GAP)
        local iy = contentY + row * (ICON_SIZE + ICON_GAP + 14)
        local cx = ix + ICON_SIZE / 2
        local cy = iy + ICON_SIZE / 2
        local isHovered = (state.hoverItem == entry.key)

        -- hover 光晕
        if isHovered then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix - 3, iy - 3, ICON_SIZE + 6, ICON_SIZE + 6, 6)
            nvgFillColor(vg, nvgRGBA(75, 163, 227, 28))
            nvgFill(vg)
        end

        -- 图标底圆
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ix, iy, ICON_SIZE, ICON_SIZE, 6)
        nvgFillColor(vg, Theme.rgbaA(t.notebookBorder, isHovered and 50 or 28))
        nvgFill(vg)
        nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, isHovered and 120 or 70))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        -- 图标
        if entry.info.iconKey and ItemIcons.drawCircle(vg, entry.info.iconKey, cx, cy, ICON_SIZE / 2 - 2) then
            -- 纹理成功
        else
            nvgFontSize(vg, 20)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, Theme.rgba(t.textPrimary))
            nvgText(vg, cx, cy, entry.info.icon, nil)
        end

        -- 数量角标
        if entry.count > 1 then
            local bx = ix + ICON_SIZE - 2
            local by = iy + 2
            nvgBeginPath(vg)
            nvgCircle(vg, bx, by, 6)
            nvgFillColor(vg, Theme.rgbaA(t.info, 210))
            nvgFill(vg)
            nvgFontSize(vg, 7)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgText(vg, bx, by, tostring(entry.count), nil)
        end

        -- 名称标签
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 160))
        nvgText(vg, cx, iy + ICON_SIZE + 2, entry.info.label, nil)

        -- hover tooltip
        if isHovered then
            local resNames = { san = "理智", order = "秩序", film = "胶卷" }
            local parts = {}
            for _, eff in ipairs(entry.info.effects) do
                if eff[1] == "exorcism" then
                    parts[#parts + 1] = "驱除怪物"
                else
                    local rn = resNames[eff[1]] or eff[1]
                    local sign = eff[2] > 0 and "+" or ""
                    parts[#parts + 1] = rn .. sign .. eff[2]
                end
            end
            local tip = table.concat(parts, " / ")
            nvgFontSize(vg, 9)
            local tw = nvgTextBounds(vg, 0, 0, tip, nil)
            local tipCX = cx
            local tipY  = iy - 6
            local padX, padY = 5, 3
            local bw2 = tw + padX * 2
            local bh2 = 10 + padY * 2
            local bx2 = tipCX - bw2 / 2
            local by2 = tipY - bh2
            -- 阴影
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx2 + 1, by2 + 1, bw2, bh2, 3)
            nvgFillColor(vg, Theme.rgbaA(t.notebookBorder, 35))
            nvgFill(vg)
            -- 填充
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx2, by2, bw2, bh2, 3)
            nvgFillColor(vg, Theme.rgbaA(t.notebookPaper, 248))
            nvgFill(vg)
            nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 110))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, Theme.rgba(t.textPrimary))
            nvgText(vg, tipCX, by2 + bh2 / 2, tip, nil)
        end

        col = col + 1
        if col >= ICONS_PER_ROW then
            col = 0
            row = row + 1
        end
    end
end

-- ---------------------------------------------------------------------------
-- 渲染：Tab3 线索（占位）
-- ---------------------------------------------------------------------------

local function drawTab3(vg, px, py, pw, ph, t)
    local cx = px + SPINE_W + (pw - SPINE_W) / 2
    local cy = py + ph / 2

    -- 占位图标
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 70))
    nvgText(vg, cx, cy - 16, "🔍", nil)

    nvgFontSize(vg, 11)
    nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 90))
    nvgText(vg, cx, cy + 14, "线索系统开发中…", nil)

    -- 装饰线
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - 40, cy + 28)
    nvgLineTo(vg, cx + 40, cy + 28)
    nvgStrokeColor(vg, Theme.rgbaA(t.notebookBorder, 50))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)
end

-- ---------------------------------------------------------------------------
-- 渲染：便签贴（Pass2，屏幕空间，不受旋转影响）
-- ---------------------------------------------------------------------------

-- activeOnly: true=只画当前激活tab, false=只画非激活tab, nil=全画
local function drawTabLabels(vg, logicalH, t, activeOnly)
    nvgFontFace(vg, "sans")

    for i = 1, NUM_TABS do
        local isActive = (state.activeTab == i)
        if activeOnly == true  and not isActive then goto continue end
        if activeOnly == false and     isActive then goto continue end
        local lx, ly, lw, lh = getTabLabelRect(logicalH, i)
        local isHovered = (state.hoverTab == i)
        local c = TAB_BG_COLORS[i]

        -- 可见部分起始 x（TAB_OVERLAP 那段叠在笔记本下面）
        local visX = lx + TAB_OVERLAP  -- 便签露出来的左边缘
        local visW = lw - TAB_OVERLAP  -- 露出宽度

        -- 展开时激活 tab 向右偏移 2px，视觉上更突出
        local nudge = (isActive and state.expanded) and 2 or 0

        -- ---- 阴影（仅露出部分投影）----
        if isActive or isHovered then
            nvgBeginPath(vg)
            nvgRoundedRectVarying(vg, visX + nudge + 2, ly + 2,
                visW, lh, 0, TAB_LABEL_RADIUS, TAB_LABEL_RADIUS, 0)
            nvgFillColor(vg, nvgRGBA(60, 45, 30, isActive and 40 or 20))
            nvgFill(vg)
        end

        -- ---- 便签主体（左直角 + 右圆角）----
        local br = isActive and 1.0 or (isHovered and 0.93 or 0.80)
        local r  = math.floor(c[1] * br)
        local g  = math.floor(c[2] * br)
        local b  = math.floor(c[3] * br)
        local bgAlpha = isActive and 250 or (isHovered and 220 or 190)

        -- 全宽矩形（含重叠部分）：左直角
        nvgBeginPath(vg)
        nvgRoundedRectVarying(vg, lx + nudge, ly, lw, lh,
            0, TAB_LABEL_RADIUS, TAB_LABEL_RADIUS, 0)
        nvgFillColor(vg, nvgRGBA(r, g, b, bgAlpha))
        nvgFill(vg)

        -- ---- 左侧暗色竖线（在 visX 处，暗示便签插入笔记本边缘）----
        nvgBeginPath(vg)
        nvgMoveTo(vg, visX + nudge, ly + 3)
        nvgLineTo(vg, visX + nudge, ly + lh - 3)
        nvgStrokeColor(vg, nvgRGBA(
            math.floor(c[1] * 0.55),
            math.floor(c[2] * 0.55),
            math.floor(c[3] * 0.55),
            isActive and 160 or 90))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)

        -- ---- 右侧/上下边框（只画露出部分的三条边）----
        nvgBeginPath(vg)
        -- 上边
        nvgMoveTo(vg, visX + nudge, ly)
        nvgLineTo(vg, lx + nudge + lw - TAB_LABEL_RADIUS, ly)
        nvgArcTo(vg, lx + nudge + lw, ly, lx + nudge + lw, ly + TAB_LABEL_RADIUS, TAB_LABEL_RADIUS)
        -- 右边
        nvgLineTo(vg, lx + nudge + lw, ly + lh - TAB_LABEL_RADIUS)
        nvgArcTo(vg, lx + nudge + lw, ly + lh, lx + nudge + lw - TAB_LABEL_RADIUS, ly + lh, TAB_LABEL_RADIUS)
        -- 下边
        nvgLineTo(vg, visX + nudge, ly + lh)
        nvgStrokeColor(vg, nvgRGBA(
            math.floor(c[1] * 0.68),
            math.floor(c[2] * 0.68),
            math.floor(c[3] * 0.68),
            isActive and 190 or 110))
        nvgStrokeWidth(vg, isActive and 1.2 or 0.8)
        nvgStroke(vg)

        -- ---- 激活时右上角折角 ----
        if isActive then
            local fold = 5
            local fx = lx + nudge + lw - fold
            nvgBeginPath(vg)
            nvgMoveTo(vg, fx, ly)
            nvgLineTo(vg, lx + nudge + lw, ly + fold)
            nvgLineTo(vg, fx, ly + fold)
            nvgFillColor(vg, nvgRGBA(
                math.floor(c[1] * 0.78),
                math.floor(c[2] * 0.78),
                math.floor(c[3] * 0.78), 150))
            nvgFill(vg)
        end

        -- ---- 展开时，激活 tab 左边渐变覆盖（融入笔记本纸色）----
        if isActive and state.expanded then
            local grad = nvgLinearGradient(vg,
                lx + nudge, ly,
                visX + nudge, ly,
                Theme.rgba(t.notebookPaper),
                nvgRGBA(r, g, b, 0))
            nvgBeginPath(vg)
            nvgRect(vg, lx + nudge, ly, TAB_OVERLAP, lh)
            nvgFillPaint(vg, grad)
            nvgFill(vg)
        end

        -- ---- 文字 ----
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(55, 45, 35, isActive and 235 or 155))
        -- 文字居中在露出区域
        nvgText(vg, visX + nudge + (visW) / 2, ly + lh / 2, TAB_NAMES[i], nil)
        ::continue::
    end
end

-- ---------------------------------------------------------------------------
-- 主渲染入口
-- ---------------------------------------------------------------------------

function M.draw(vg, logicalW, logicalH, gameTime)
    if not state.visible or state.alpha < 0.05 then return end

    currentGameTime = gameTime or 0

    local t = Theme.current
    nvgSave(vg)
    nvgGlobalAlpha(vg, state.alpha)

    local px, py, pw, ph = getPanelRect(logicalH)

    -- 裁剪到屏幕内
    nvgIntersectScissor(vg, 0, 0, logicalW, logicalH)

    -- ============ Pass 1：倾斜笔记本主体 ============
    -- 旋转轴心：面板右上角 (px+pw, py)
    local pivotX = px + pw
    local pivotY = py

    nvgSave(vg)
    nvgTranslate(vg, pivotX, pivotY)
    nvgRotate(vg, state.panelAngle)
    nvgTranslate(vg, -pivotX, -pivotY)

    -- 非激活便签先画，位于笔记本主体后面
    drawTabLabels(vg, logicalH, t, false)

    drawNotebookBody(vg, px, py, pw, ph, t)
    drawPageHeader(vg, px, py, pw, ph, t)

    -- 内容区 scissor
    nvgSave(vg)
    nvgIntersectScissor(vg, px + SPINE_W, py + 20, pw - SPINE_W, ph - 24)

    if state.activeTab == 1 then
        drawTab1(vg, px, py, pw, ph, t)
    elseif state.activeTab == 2 then
        drawTab2(vg, px, py, pw, ph, t)
    else
        drawTab3(vg, px, py, pw, ph, t)
    end

    nvgRestore(vg)  -- scissor

    -- 激活便签最后画，位于笔记本主体前面（当前页效果）
    drawTabLabels(vg, logicalH, t, true)

    nvgRestore(vg)  -- tilt transform

    nvgRestore(vg)  -- globalAlpha
end

-- ---------------------------------------------------------------------------
-- 交互：点击
-- ---------------------------------------------------------------------------

function M.handleClick(lx, ly, logicalW, logicalH)
    if not state.visible or state.alpha < 0.1 then return false end

    -- 先检查便签贴（屏幕坐标，无需逆变换）
    for i = 1, NUM_TABS do
        local tlx, tly, tlw, tlh = getTabLabelRect(logicalH, i)
        if lx >= tlx and lx <= tlx + tlw and ly >= tly and ly <= tly + tlh then
            if state.activeTab == i and state.expanded then
                -- 点当前激活便签 → 收起
                M.toggle(logicalH)
            else
                state.activeTab = i
                if not state.expanded then
                    -- 折叠时点便签 → 展开
                    M.toggle(logicalH)
                end
            end
            return true
        end
    end

    local px, py, pw, ph = getPanelRect(logicalH)

    -- 点击在面板 X 范围外 → 穿透
    if lx < px or lx > px + pw + TAB_LABEL_W then
        return false
    end

    -- showcase 期间点击主体 → 折叠
    if state.showcasing then
        M.finishShowcase()
        return true
    end

    -- 点击在折叠时露出的区域（或整个展开面板）→ 切换
    if not state.expanded then
        -- 折叠状态：点击主体任意处展开
        if lx >= px and lx <= px + pw and ly >= py and ly <= py + ph then
            M.toggle(logicalH)
            return true
        end
        return false
    end

    -- 展开状态 ——

    -- 点击在面板 Y 范围外（上下空白区域）→ 收起
    if ly < py or ly > py + ph then
        M.toggle(logicalH)
        return true
    end

    -- 关闭按钮（右上角圆形区域）→ 收起
    local closeBtnX = px + pw - 9
    local closeBtnY = py + 7
    local closeBtnR = 10   -- 点击半径略大于绘制半径
    local dx = lx - closeBtnX
    local dy = ly - closeBtnY
    if dx * dx + dy * dy <= closeBtnR * closeBtnR then
        M.toggle(logicalH)
        return true
    end

    -- Tab1：传闻便签点击翻页
    if state.activeTab == 1 then
        local rumors = CardManager.getRumors()
        if #rumors > 1 then
            -- 传闻便签位于 Tab1 下半区中央
            local noteX = px + SPINE_W + (pw - SPINE_W - NOTE_W) / 2
            local noteY = py + ph - NOTE_H - 14
            local hitPad = 8
            if lx >= noteX - hitPad and lx <= noteX + NOTE_W + hitPad
                and ly >= noteY - hitPad and ly <= noteY + NOTE_H + hitPad + 10 then
                state.rumorPage = state.rumorPage + 1
                if state.rumorPage > #rumors then state.rumorPage = 1 end
                return true
            end
        end

        -- 日程条目
        local schedules = CardManager.getSchedules()
        local contentX  = px + SPINE_W + PAGE_PAD
        local contentY  = py + 28
        for i, sched in ipairs(schedules) do
            local itemY = contentY + (i - 1) * ITEM_H
            if ly >= itemY and ly <= itemY + ITEM_H
                and lx >= contentX and lx <= px + pw - PAGE_PAD then
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

        -- 结束今天按钮点击
        local schedules2 = schedules  -- 上面已声明
        local lastIdx2   = math.min(#schedules2, math.floor((ph - 28 - (NOTE_H + 24) - 4) / ITEM_H))
        local noteY2     = py + ph - NOTE_H - 14
        local footerY2   = math.min(py + 28 + lastIdx2 * ITEM_H + 14, noteY2 - 30)
        local ebtnX2     = px + SPINE_W + PAGE_PAD
        local ebtnW2     = pw - SPINE_W - PAGE_PAD * 2
        if lx >= ebtnX2 and lx <= ebtnX2 + ebtnW2
            and ly >= footerY2 and ly <= footerY2 + 18 then
            local hasPending = false
            for _, s in ipairs(schedules) do
                if s.status == "pending" then hasPending = true; break end
            end
            local suC, smC = ResourceBar.getSteps()
            local stepsExhaustedC = smC > 0 and suC >= smC
            if (not hasPending or stepsExhaustedC) and onAdvanceDayCallback then
                onAdvanceDayCallback()
            end
            return true
        end
    end

    -- Tab2：道具点击
    if state.activeTab == 2 then
        local consumables = ShopPopup.getConsumableOrder()
        local contentX    = px + SPINE_W + PAGE_PAD
        local contentY    = py + 28
        local col = 0
        local row = 0
        for _, entry in ipairs(consumables) do
            local ix = contentX + col * (ICON_SIZE + ICON_GAP)
            local iy = contentY + row * (ICON_SIZE + ICON_GAP + 14)
            if lx >= ix and lx <= ix + ICON_SIZE and ly >= iy and ly <= iy + ICON_SIZE then
                if entry.key == "exorcism" then
                    if onUseExorcismCallback then onUseExorcismCallback() end
                else
                    local ok = ShopPopup.useConsumable(entry.key)
                    if ok then
                        AudioManager.playItemUse(entry.key)
                        local VFX = require "lib.VFX"
                        local tc = Theme.current
                        VFX.spawnBanner(entry.info.icon .. " 使用了" .. entry.info.label,
                            tc.safe.r, tc.safe.g, tc.safe.b, 18, 0.7)
                    end
                end
                return true
            end
            col = col + 1
            if col >= ICONS_PER_ROW then col = 0; row = row + 1 end
        end
    end

    return true  -- 面板内其余区域消费事件
end

-- ---------------------------------------------------------------------------
-- 交互：hover
-- ---------------------------------------------------------------------------

function M.updateHover(lx, ly, dt, logicalW, logicalH)
    state.hoverTab      = 0
    state.hoverIndex    = 0
    state.hoverItem     = nil
    state.hoverCloseBtn    = false
    state.hoverEndDayBtn   = false

    if not state.visible or state.alpha < 0.1 then return end

    -- 便签贴 hover（始终检测）
    for i = 1, NUM_TABS do
        local tlx, tly, tlw, tlh = getTabLabelRect(logicalH, i)
        if lx >= tlx and lx <= tlx + tlw and ly >= tly and ly <= tly + tlh then
            state.hoverTab = i
            return
        end
    end

    if not state.expanded or state.showcasing then return end

    local px, py, pw, ph = getPanelRect(logicalH)
    if lx < px or lx > px + pw or ly < py or ly > py + ph then return end

    -- 关闭按钮 hover
    local cbx = px + pw - 9
    local cby = py + 7
    local cdx = lx - cbx
    local cdy = ly - cby
    if cdx * cdx + cdy * cdy <= 100 then
        state.hoverCloseBtn = true
        return
    end

    -- Tab1：日程 hover
    if state.activeTab == 1 then
        local schedules = CardManager.getSchedules()
        local contentX  = px + SPINE_W + PAGE_PAD
        local contentY  = py + 28
        for i, sched in ipairs(schedules) do
            local itemY = contentY + (i - 1) * ITEM_H
            if ly >= itemY and ly <= itemY + ITEM_H
                and lx >= contentX and lx <= px + pw - PAGE_PAD then
                if sched.status == "pending" or sched.status == "deferred" then
                    state.hoverIndex = i
                end
                return
            end
        end

        -- 结束今天按钮 hover
        local schedHover   = CardManager.getSchedules()
        local lastIdxH     = math.min(#schedHover, math.floor((ph - 28 - (NOTE_H + 24) - 4) / ITEM_H))
        local noteYH       = py + ph - NOTE_H - 14
        local footerY      = math.min(py + 28 + lastIdxH * ITEM_H + 14, noteYH - 30)
        local ebtnX        = px + SPINE_W + PAGE_PAD
        local ebtnW        = pw - SPINE_W - PAGE_PAD * 2
        if lx >= ebtnX and lx <= ebtnX + ebtnW and ly >= footerY and ly <= footerY + 18 then
            state.hoverEndDayBtn = true
            return
        end
    end

    -- Tab2：道具 hover
    if state.activeTab == 2 then
        local consumables = ShopPopup.getConsumableOrder()
        local contentX    = px + SPINE_W + PAGE_PAD
        local contentY    = py + 28
        local col = 0
        local row = 0
        for _, entry in ipairs(consumables) do
            local ix = contentX + col * (ICON_SIZE + ICON_GAP)
            local iy = contentY + row * (ICON_SIZE + ICON_GAP + 14)
            if lx >= ix and lx <= ix + ICON_SIZE and ly >= iy and ly <= iy + ICON_SIZE then
                state.hoverItem = entry.key
                return
            end
            col = col + 1
            if col >= ICONS_PER_ROW then col = 0; row = row + 1 end
        end
    end
end

return M
