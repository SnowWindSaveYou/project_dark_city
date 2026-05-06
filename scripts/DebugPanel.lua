-- ============================================================================
-- DebugPanel.lua - 开发调试面板
-- KEY_1 切换显隐, NanoVG 绘制, 提供状态查看 + 快捷操作按钮
-- ============================================================================

local StoryManager = require "StoryManager"
local StoryConfig  = require "StoryConfig"
local ResourceBar  = require "ResourceBar"

local M = {}

-- ── 状态 ──
local visible_ = false
---@type table|nil  共享游戏状态 G
local G_ = nil
---@type table|nil  回调表: { enterDarkWorld, advanceDay }
local callbacks_ = {}

-- ── 布局常量 ──
local PANEL_W   = 280
local PANEL_PAD = 10
local BTN_H     = 28
local BTN_GAP   = 4
local FONT_SIZE = 13
local TITLE_H   = 24
local LINE_H    = 16
local STATUS_LINES = 7   -- 状态区固定行数
local SEP_H     = 8      -- 分隔线占用高度

-- ── 按钮定义 ──
local buttons_ = {}

local function buildButtons()
    buttons_ = {
        { label = "进入暗面世界", action = function(G, sm)
            if callbacks_.enterDarkWorld then
                M.hide()
                callbacks_.enterDarkWorld()
            end
        end },
        { label = "灵感 +10", action = function(G, sm)
            ResourceBar.change("inspiration", 10)
        end },
        { label = "灵感 +50", action = function(G, sm)
            ResourceBar.change("inspiration", 50)
        end },
        { label = "信任 +1", action = function(G, sm)
            if sm then StoryManager.addTrust(sm, 1) end
        end },
        { label = "信任 -1", action = function(G, sm)
            if sm then StoryManager.addTrust(sm, -1) end
        end },
        { label = "力量 +1", action = function(G, sm)
            if sm then StoryManager.addPower(sm, 1) end
        end },
        { label = "力量 MAX (5)", action = function(G, sm)
            if sm then sm.baiye_power = 5 end
        end },
        { label = "清除 sleep", action = function(G, sm)
            if sm then sm.sleep_days_left = 0 end
        end },
        { label = "+1 碎片 (下一个)", action = function(G, sm)
            if not sm then return end
            for _, frag in ipairs(StoryConfig.FRAGMENTS) do
                if not sm.fragments[frag.id] then
                    StoryManager.addFragment(sm, frag.id)
                    print("[DebugPanel] Added fragment: " .. frag.id)
                    return
                end
            end
            print("[DebugPanel] All fragments collected")
        end },
        { label = "碎片 = 4 (精英门槛)", action = function(G, sm)
            if not sm then return end
            sm.fragments = {}
            for i = 1, 4 do
                sm.fragments[StoryConfig.FRAGMENTS[i].id] = true
            end
            print("[DebugPanel] Fragments set to 4")
        end },
        { label = "碎片 = 9 (Boss 门槛)", action = function(G, sm)
            if not sm then return end
            sm.fragments = {}
            for i = 1, 9 do
                sm.fragments[StoryConfig.FRAGMENTS[i].id] = true
            end
            print("[DebugPanel] Fragments set to 9")
        end },
        { label = "重置 story flags", action = function(G, sm)
            if not sm then return end
            sm.flags["elite_defeated"] = nil
            sm.flags["boss_defeated"] = nil
            sm.flags["memory_complete"] = nil
            print("[DebugPanel] Cleared elite/boss/memory flags")
        end },
        { label = "跳到下一天", action = function(G, sm)
            if callbacks_.advanceDay then
                M.hide()
                callbacks_.advanceDay()
            end
        end },
    }
end

-- ── 统一计算按钮起始 Y 偏移 (相对于面板顶部) ──
local function btnAreaOffsetY()
    return TITLE_H + PANEL_PAD + STATUS_LINES * LINE_H + SEP_H
end

-- ── 面板总高度 ──
local function calcPanelH()
    return btnAreaOffsetY() + #buttons_ * (BTN_H + BTN_GAP) + PANEL_PAD
end

-- ============================================================================
-- 公共 API
-- ============================================================================

function M.init(gameState, cbs)
    G_ = gameState
    callbacks_ = cbs or {}
    buildButtons()
end

function M.toggle()  visible_ = not visible_ end
function M.show()    visible_ = true end
function M.hide()    visible_ = false end
function M.isActive() return visible_ end

-- ============================================================================
-- 点击处理
-- ============================================================================

function M.handleClick(lx, ly, logicalW, logicalH)
    if not visible_ then return false end

    local panelH = calcPanelH()
    local px = (logicalW - PANEL_W) / 2
    local py = (logicalH - panelH) / 2

    -- 点击面板外 → 关闭
    if lx < px or lx > px + PANEL_W or ly < py or ly > py + panelH then
        M.hide()
        return true
    end

    -- 按钮 hit test (使用统一偏移)
    local btnStartY = py + btnAreaOffsetY()
    local sm = G_ and G_.storyMgr

    for i, btn in ipairs(buttons_) do
        local by = btnStartY + (i - 1) * (BTN_H + BTN_GAP)
        if lx >= px + PANEL_PAD and lx <= px + PANEL_W - PANEL_PAD
            and ly >= by and ly <= by + BTN_H then
            btn.action(G_, sm)
            return true
        end
    end

    return true
end

-- ============================================================================
-- 绘制
-- ============================================================================

function M.draw(vg, logicalW, logicalH, gameTime)
    if not visible_ or not vg then return end

    local panelH = calcPanelH()
    local px = (logicalW - PANEL_W) / 2
    local py = (logicalH - panelH) / 2

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logicalW, logicalH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, PANEL_W, panelH, 8)
    nvgFillColor(vg, nvgRGBA(30, 30, 40, 230))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 200, 255, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
    nvgText(vg, px + PANEL_W / 2, py + TITLE_H / 2, "DEBUG PANEL")

    -- ── 状态区 (固定 STATUS_LINES 行) ──
    local sx = px + PANEL_PAD
    local sy = py + TITLE_H + PANEL_PAD
    local lineIdx = 0

    nvgFontSize(vg, FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    local sm = G_ and G_.storyMgr

    local function drawLine(text, r, g, b)
        if lineIdx >= STATUS_LINES then return end
        nvgFillColor(vg, nvgRGBA(r or 200, g or 200, b or 200, 220))
        nvgText(vg, sx, sy + lineIdx * LINE_H, text)
        lineIdx = lineIdx + 1
    end

    -- Line 1: 游戏状态
    local ins = ResourceBar.get and ResourceBar.get("inspiration") or "?"
    drawLine("Day:" .. (G_ and G_.dayCount or "?")
        .. " Phase:" .. (G_ and G_.gamePhase or "?")
        .. " Ins:" .. ins, 180, 180, 180)

    -- Line 2: 章节
    drawLine("Chapter: " .. (sm and sm.currentChapter or "N/A")
        .. "  State: " .. (G_ and G_.demoState or "?"), 180, 180, 180)

    -- Line 3-4: 白夜
    if sm then
        local avail = StoryManager.isBaiyeAvailable(sm) and "YES" or "NO"
        drawLine("Baiye: trust=" .. sm.baiye_trust
            .. " power=" .. sm.baiye_power
            .. " avail=" .. avail, 180, 220, 255)
        drawLine("  sleep=" .. sm.sleep_days_left
            .. " followDark=" .. tostring(G_.baiyeFollowDark or false), 160, 200, 240)
    else
        drawLine("StoryManager: not initialized", 255, 100, 100)
        drawLine("", 0, 0, 0)
    end

    -- Line 5: 碎片数
    local fragCount = sm and StoryManager.getFragmentCount(sm) or 0
    drawLine("Fragments: " .. fragCount .. "/10", 220, 200, 130)

    -- Line 6: 碎片列表
    if sm then
        local ids = {}
        for _, frag in ipairs(StoryConfig.FRAGMENTS) do
            if sm.fragments[frag.id] then
                table.insert(ids, frag.id:sub(-2))
            end
        end
        drawLine("  [" .. (#ids > 0 and table.concat(ids, ",") or "none") .. "]", 200, 180, 120)
    else
        drawLine("", 0, 0, 0)
    end

    -- Line 7: flags
    if sm then
        local fl = {}
        for k, v in pairs(sm.flags) do
            if v then table.insert(fl, k) end
        end
        drawLine("Flags: " .. (#fl > 0 and table.concat(fl, ",") or "none"), 200, 180, 160)
    else
        drawLine("Flags: N/A", 200, 180, 160)
    end

    -- 分隔线
    local sepY = sy + STATUS_LINES * LINE_H + SEP_H / 2
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + PANEL_PAD, sepY)
    nvgLineTo(vg, px + PANEL_W - PANEL_PAD, sepY)
    nvgStrokeColor(vg, nvgRGBA(100, 200, 255, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ── 按钮区 (使用统一偏移, 和 handleClick 完全一致) ──
    local btnStartY = py + btnAreaOffsetY()
    local mousePos = input:GetMousePosition()
    local dpr = graphics:GetDPR()
    local mx = mousePos.x / dpr
    local my = mousePos.y / dpr

    for i, btn in ipairs(buttons_) do
        local bx = px + PANEL_PAD
        local by = btnStartY + (i - 1) * (BTN_H + BTN_GAP)
        local bw = PANEL_W - PANEL_PAD * 2

        local hovered = mx >= bx and mx <= bx + bw and my >= by and my <= by + BTN_H

        -- 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bw, BTN_H, 4)
        nvgFillColor(vg, nvgRGBA(hovered and 70 or 50, hovered and 140 or 55, hovered and 200 or 70, hovered and 180 or 200))
        nvgFill(vg)

        -- 边框
        nvgStrokeColor(vg, nvgRGBA(100, 160, 220, hovered and 200 or 80))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 230, 255, hovered and 255 or 200))
        nvgText(vg, bx + bw / 2, by + BTN_H / 2, btn.label)
    end
end

return M
