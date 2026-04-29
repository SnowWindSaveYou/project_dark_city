-- ============================================================================
-- Balatro 风格卡牌动效 - 最小示例入口
-- 使用方式：复制此文件到 scripts/main.lua，三个模块复制到 scripts/balatro/
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local Card     = require "balatro.Card"
local CardHand = require "balatro.CardHand"
local Tween    = require "balatro.Tween"

---@type userdata NanoVG context
local vg = nil

-- 屏幕 (Mode B: 系统逻辑分辨率)
local dpr = 1.0
local logicalW, logicalH = 0, 0

-- 游戏
local hand = nil
local gameTime = 0

-- ============================================================================
-- 入口
-- ============================================================================

function Start()
    SampleStart()
    SampleInitMouseMode(MM_FREE)

    vg = nvgCreate(1)
    nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")

    updateScreenSize()

    hand = CardHand.new({
        -- 可覆盖默认配置，例如：
        -- hoverLift = 50,
        -- hoverScale = 1.25,
        -- maxHandSize = 10,
    })
    hand:recalcLayout(logicalW, logicalH)
    hand.deck = Card.shuffle(Card.createDeck())

    -- 自动抽 5 张初始手牌
    hand:drawCards(5)

    SubscribeToEvent(vg, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
end

function Stop()
    if vg then nvgDelete(vg); vg = nil end
end

-- ============================================================================
-- 屏幕
-- ============================================================================

function updateScreenSize()
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    dpr = graphics:GetDPR()
    logicalW = physW / dpr
    logicalH = physH / dpr
end

function HandleScreenMode()
    updateScreenSize()
    if hand then
        hand:recalcLayout(logicalW, logicalH)
    end
end

-- ============================================================================
-- 事件
-- ============================================================================

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    gameTime = gameTime + dt

    local mousePos = input:GetMousePosition()
    local mx, my = mousePos.x / dpr, mousePos.y / dpr

    if hand then hand:update(dt, mx, my) end
end

function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    local mx = eventData["X"]:GetInt() / dpr
    local my = eventData["Y"]:GetInt() / dpr
    if hand then hand:onMouseDown(mx, my, button) end
end

function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    local mx = eventData["X"]:GetInt() / dpr
    local my = eventData["Y"]:GetInt() / dpr
    if hand then hand:onMouseUp(mx, my, button) end
end

function HandleMouseMove(eventType, eventData)
    local mx = eventData["X"]:GetInt() / dpr
    local my = eventData["Y"]:GetInt() / dpr
    if hand then hand:onMouseMove(mx, my) end
end

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_ESCAPE and hand and hand.inspecting then
        hand:endInspect()
    elseif key == KEY_D then
        -- 抽牌
        if hand and #hand.deck > 0 then
            hand:drawCards(5)
        end
    elseif key == KEY_P then
        -- 出牌
        if hand then hand:playSelected() end
    elseif key == KEY_X then
        -- 弃牌
        if hand then hand:discardSelected() end
    elseif key == KEY_R then
        -- 洗牌重置
        if hand then hand:resetDeck() end
    elseif key == KEY_H then
        -- 切换闪卡
        if hand then
            for _, card in ipairs(hand:getSelectedCards()) do
                card.holoEnabled = not card.holoEnabled
            end
        end
    end
end

-- ============================================================================
-- 渲染
-- ============================================================================

function HandleRender(eventType, eventData)
    if not vg then return end

    nvgBeginFrame(vg, logicalW, logicalH, dpr)

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logicalW, logicalH)
    local bg = nvgLinearGradient(vg, 0, 0, 0, logicalH,
        nvgRGBA(18, 24, 38, 255), nvgRGBA(12, 16, 28, 255))
    nvgFillPaint(vg, bg)
    nvgFill(vg)

    -- 手牌场景
    if hand then hand:draw(vg, gameTime) end

    -- 操作提示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(120, 140, 170, 120))
    nvgText(vg, logicalW / 2, logicalH - 10,
        "[D] \xe6\x8a\xbd\xe7\x89\x8c  [P] \xe5\x87\xba\xe7\x89\x8c  [X] \xe5\xbc\x83\xe7\x89\x8c  [R] \xe6\xb4\x97\xe7\x89\x8c  [H] \xe9\x97\xaa\xe5\x8d\xa1  \xe5\xb7\xa6\xe9\x94\xae\xe9\x80\x89/\xe6\x8b\x96  \xe5\x8f\xb3\xe9\x94\xae\xe6\x9f\xa5\xe9\x98\x85",
        nil)

    nvgEndFrame(vg)
end
