-- ============================================================================
-- Board.lua - 5x5 棋盘布局与卡牌管理
-- 管理卡牌位置、发牌编排、碰撞检测
-- ============================================================================

local Card = require "Card"
local Theme = require "Theme"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
M.ROWS = 5
M.COLS = 5
M.GAP  = 10          -- 卡牌间距

-- ---------------------------------------------------------------------------
-- 构造
-- ---------------------------------------------------------------------------

---@class BoardData
---@field cards table[]  二维数组 [row][col]
---@field originX number 棋盘左上角 X
---@field originY number 棋盘左上角 Y
---@field totalW number 棋盘总宽
---@field totalH number 棋盘总高
---@field deckX number 牌堆位置 X (发牌起点)
---@field deckY number 牌堆位置 Y

function M.new()
    return {
        cards = {},
        originX = 0,
        originY = 0,
        totalW = 0,
        totalH = 0,
        deckX = 0,
        deckY = 0,
        isDealt = false,
    }
end

-- ---------------------------------------------------------------------------
-- 布局计算 (居中于给定区域)
-- ---------------------------------------------------------------------------

--- 重新计算棋盘位置 (在屏幕改变时调用)
---@param board BoardData
---@param centerX number 棋盘中心 X
---@param centerY number 棋盘中心 Y
function M.recalcLayout(board, centerX, centerY)
    local cw, ch = Card.WIDTH, Card.HEIGHT
    local gap = M.GAP

    board.totalW = M.COLS * cw + (M.COLS - 1) * gap
    board.totalH = M.ROWS * ch + (M.ROWS - 1) * gap
    board.originX = centerX - board.totalW / 2
    board.originY = centerY - board.totalH / 2

    -- 牌堆在棋盘右侧偏上
    board.deckX = centerX + board.totalW / 2 + cw * 0.8
    board.deckY = centerY - board.totalH / 2 + ch * 0.5

    -- 更新已有卡牌的目标位置 (不触发动画，仅用于 deal)
    for row = 1, M.ROWS do
        if board.cards[row] then
            for col = 1, M.COLS do
                local card = board.cards[row][col]
                if card then
                    -- 已发的牌直接跳到位置
                    if not card.isDealing and card.alpha > 0 then
                        card.x, card.y = M.cardPos(board, row, col)
                    end
                end
            end
        end
    end
end

--- 获取指定格子的中心位置
---@return number x, number y
function M.cardPos(board, row, col)
    local cw, ch = Card.WIDTH, Card.HEIGHT
    local gap = M.GAP
    local x = board.originX + (col - 1) * (cw + gap) + cw / 2
    local y = board.originY + (row - 1) * (ch + gap) + ch / 2
    return x, y
end

-- ---------------------------------------------------------------------------
-- 生成卡牌 (随机类型填充)
-- ---------------------------------------------------------------------------

function M.generateCards(board)
    board.cards = {}
    local types = Card.ALL_TYPES
    local numTypes = #types

    for row = 1, M.ROWS do
        board.cards[row] = {}
        for col = 1, M.COLS do
            -- 中心是 landmark
            local cardType
            if row == 3 and col == 3 then
                cardType = "landmark"
            else
                cardType = types[math.random(1, numTypes)]
            end
            local card = Card.new(cardType, row, col)
            -- 初始位置在牌堆
            card.x = board.deckX
            card.y = board.deckY
            board.cards[row][col] = card
        end
    end
end

-- ---------------------------------------------------------------------------
-- 发牌动画 (螺旋顺序，逐张延迟)
-- ---------------------------------------------------------------------------

function M.dealAll(board, onComplete)
    board.isDealt = false
    local order = M.spiralOrder()
    local totalCards = #order

    for i, pos in ipairs(order) do
        local row, col = pos[1], pos[2]
        local card = board.cards[row][col]
        if card then
            local tx, ty = M.cardPos(board, row, col)
            local delay = (i - 1) * 0.06
            Card.dealTo(card, tx, ty, delay)
        end
    end

    -- 最后一张牌发完后回调
    if onComplete then
        -- 粗略延迟: 最后一张的 delay + deal 动画时间
        local lastDelay = (totalCards - 1) * 0.06 + 0.5
        -- 用一个简单的 timer 代替
        board._dealTimer = lastDelay
        board._dealCallback = onComplete
    end
end

--- 更新发牌计时器
function M.update(board, dt)
    if board._dealTimer and board._dealTimer > 0 then
        board._dealTimer = board._dealTimer - dt
        if board._dealTimer <= 0 then
            board._dealTimer = nil
            board.isDealt = true
            if board._dealCallback then
                board._dealCallback()
                board._dealCallback = nil
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 收牌动画 (全部收回牌堆)
-- ---------------------------------------------------------------------------

function M.undealAll(board, onComplete)
    local order = M.spiralOrder()
    local totalCards = #order

    for i, pos in ipairs(order) do
        local row, col = pos[1], pos[2]
        local card = board.cards[row][col]
        if card then
            local delay = (i - 1) * 0.04
            local isLast = (i == totalCards)
            Card.undeal(card, board.deckX, board.deckY, delay, isLast and onComplete or nil)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 螺旋遍历顺序 (从外到内)
-- ---------------------------------------------------------------------------

function M.spiralOrder()
    local result = {}
    local top, bottom = 1, M.ROWS
    local left, right = 1, M.COLS

    while top <= bottom and left <= right do
        -- 从左到右
        for c = left, right do result[#result + 1] = { top, c } end
        top = top + 1
        -- 从上到下
        for r = top, bottom do result[#result + 1] = { r, right } end
        right = right - 1
        -- 从右到左
        if top <= bottom then
            for c = right, left, -1 do result[#result + 1] = { bottom, c } end
            bottom = bottom - 1
        end
        -- 从下到上
        if left <= right then
            for r = bottom, top, -1 do result[#result + 1] = { r, left } end
            left = left + 1
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- 碰撞检测
-- ---------------------------------------------------------------------------

--- 找到被点击的卡牌
---@return CardData|nil card, number row, number col
function M.hitTest(board, px, py)
    for row = 1, M.ROWS do
        for col = 1, M.COLS do
            local card = board.cards[row][col]
            if card and Card.hitTest(card, px, py) then
                return card, row, col
            end
        end
    end
    return nil, 0, 0
end

-- ---------------------------------------------------------------------------
-- 渲染
-- ---------------------------------------------------------------------------

function M.draw(vg, board, gameTime)
    -- 牌堆指示 (简单背景牌)
    M.drawDeck(vg, board)

    -- 所有卡牌
    for row = 1, M.ROWS do
        for col = 1, M.COLS do
            local card = board.cards[row][col]
            if card then
                Card.draw(vg, card, gameTime)
            end
        end
    end
end

--- 牌堆视觉 (3 张堆叠效果)
function M.drawDeck(vg, board)
    local t = Theme.current
    local cw, ch, cr = Card.WIDTH, Card.HEIGHT, Card.RADIUS
    local dx, dy = board.deckX, board.deckY

    for i = 3, 1, -1 do
        local offX = (i - 1) * 2
        local offY = (i - 1) * -1.5
        local alpha = 120 + (4 - i) * 40

        nvgBeginPath(vg)
        nvgRoundedRect(vg, dx - cw / 2 + offX, dy - ch / 2 + offY, cw, ch, cr)
        nvgFillColor(vg, Theme.rgbaA(t.cardBack, alpha))
        nvgFill(vg)
        nvgStrokeColor(vg, Theme.rgbaA(t.cardBorder, math.floor(alpha * 0.5)))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)
    end
end

return M
