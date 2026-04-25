-- ============================================================================
-- Board.lua - 5x5 棋盘布局与卡牌管理
-- 管理地点分配、事件分配、发牌编排、碰撞检测
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
---@field homeRow number 家的行号
---@field homeCol number 家的列号

function M.new()
    return {
        cards = {},
        originX = 0,
        originY = 0,
        totalW = 0,
        totalH = 0,
        deckX = 0,
        deckY = 0,
        homeRow = 3,
        homeCol = 3,
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
-- 工具: 随机取不重复位置
-- ---------------------------------------------------------------------------

local function randomPositions(count, exclude)
    local positions = {}
    for r = 1, M.ROWS do
        for c = 1, M.COLS do
            local skip = false
            if exclude then
                for _, ex in ipairs(exclude) do
                    if ex[1] == r and ex[2] == c then skip = true; break end
                end
            end
            if not skip then
                positions[#positions + 1] = { r, c }
            end
        end
    end
    -- 洗牌
    for i = #positions, 2, -1 do
        local j = math.random(1, i)
        positions[i], positions[j] = positions[j], positions[i]
    end
    local result = {}
    for i = 1, math.min(count, #positions) do
        result[i] = positions[i]
    end
    return result
end

-- ---------------------------------------------------------------------------
-- 生成卡牌 (地点 + 事件双层系统)
-- ---------------------------------------------------------------------------

--- @param requiredLocations string[]|nil 必须出现在棋盘上的地点列表 (由 CardManager.preSelectLocations 提供)
function M.generateCards(board, requiredLocations)
    board.cards = {}
    local usedPositions = {}

    -- 1. 随机放置"家" (起始安全位置)
    local homePos = randomPositions(1, nil)
    board.homeRow = homePos[1][1]
    board.homeCol = homePos[1][2]
    usedPositions[#usedPositions + 1] = { board.homeRow, board.homeCol }

    -- 2. 随机放置 1~2 个地标 (避开家)
    local landmarkCount = math.random(1, 2)
    local landmarkPositions = randomPositions(landmarkCount, usedPositions)
    for _, pos in ipairs(landmarkPositions) do
        usedPositions[#usedPositions + 1] = pos
    end

    -- 3. 随机放置 1 个商店 (避开已用位置)
    local shopPositions = randomPositions(1, usedPositions)
    for _, pos in ipairs(shopPositions) do
        usedPositions[#usedPositions + 1] = pos
    end

    -- 4. 准备地点池 (优先放入日程所需地点，再随机填充)
    local normalSlots = M.ROWS * M.COLS - #usedPositions
    local locationPool = {}
    local usedInPool = {}

    -- 4a. 先放入必须出现的地点 (日程预选)
    if requiredLocations then
        for _, loc in ipairs(requiredLocations) do
            if not usedInPool[loc] then
                locationPool[#locationPool + 1] = loc
                usedInPool[loc] = true
            end
        end
    end

    -- 4b. 用随机地点填充到所需数量
    while #locationPool < normalSlots do
        locationPool[#locationPool + 1] = Card.REGULAR_LOCATIONS[
            math.random(1, #Card.REGULAR_LOCATIONS)
        ]
    end
    -- 洗牌
    for i = #locationPool, 2, -1 do
        local j = math.random(1, i)
        locationPool[i], locationPool[j] = locationPool[j], locationPool[i]
    end
    local locIdx = 1

    -- 5. 准备事件池 (加权随机)
    local eventWeights = {
        { "safe",   30 },
        { "monster", 20 },
        { "trap",   15 },
        { "reward", 15 },
        { "plot",   10 },
        { "clue",   10 },
    }

    local function randomEvent()
        local total = 0
        for _, w in ipairs(eventWeights) do total = total + w[2] end
        local roll = math.random(1, total)
        local acc = 0
        for _, w in ipairs(eventWeights) do
            acc = acc + w[2]
            if roll <= acc then return w[1] end
        end
        return "safe"
    end

    -- 6. 填充棋盘
    -- 先创建位置查找表
    local specialMap = {}
    specialMap[board.homeRow .. "," .. board.homeCol] = "home"
    for _, pos in ipairs(landmarkPositions) do
        specialMap[pos[1] .. "," .. pos[2]] = "landmark"
    end
    for _, pos in ipairs(shopPositions) do
        specialMap[pos[1] .. "," .. pos[2]] = "shop"
    end

    -- 地标使用的地点 (有祛邪力量的场所 — 教堂/警察局/神社)
    local landmarkLocations = {}
    for i, loc in ipairs(Card.LANDMARK_LOCATIONS) do
        landmarkLocations[i] = loc
    end
    -- 洗牌，让地标地点随机化
    for i = #landmarkLocations, 2, -1 do
        local j = math.random(1, i)
        landmarkLocations[i], landmarkLocations[j] = landmarkLocations[j], landmarkLocations[i]
    end
    local lmLocIdx = 1

    for row = 1, M.ROWS do
        board.cards[row] = {}
        for col = 1, M.COLS do
            local key = row .. "," .. col
            local special = specialMap[key]
            local cardType, location

            if special == "home" then
                cardType = "home"
                location = "home"
            elseif special == "landmark" then
                cardType = "landmark"
                location = landmarkLocations[lmLocIdx] or "church"
                lmLocIdx = lmLocIdx + 1
            elseif special == "shop" then
                cardType = "shop"
                location = "convenience" -- 商店默认显示为便利店
            else
                -- 普通格子：随机地点 + 随机事件
                cardType = randomEvent()
                location = locationPool[locIdx]
                locIdx = locIdx + 1
            end

            local card = Card.new(cardType, row, col, location)
            -- 初始位置在牌堆
            card.x = board.deckX
            card.y = board.deckY
            board.cards[row][col] = card
        end
    end

    print(string.format("[Board] Generated: home=(%d,%d), landmarks=%d, shops=%d",
        board.homeRow, board.homeCol, landmarkCount, #shopPositions))
end

-- ---------------------------------------------------------------------------
-- 查询: 地标光环 (上下左右4格变安全)
-- ---------------------------------------------------------------------------

--- 检查指定位置是否在地标光环范围内
---@return boolean
function M.isInLandmarkAura(board, row, col)
    -- 四邻方向
    local dirs = { {-1, 0}, {1, 0}, {0, -1}, {0, 1} }
    for _, d in ipairs(dirs) do
        local nr, nc = row + d[1], col + d[2]
        if nr >= 1 and nr <= M.ROWS and nc >= 1 and nc <= M.COLS then
            local neighbor = board.cards[nr] and board.cards[nr][nc]
            if neighbor and neighbor.type == "landmark" then
                return true
            end
        end
    end
    return false
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
        local lastDelay = (totalCards - 1) * 0.06 + 0.5
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
        for c = left, right do result[#result + 1] = { top, c } end
        top = top + 1
        for r = top, bottom do result[#result + 1] = { r, right } end
        right = right - 1
        if top <= bottom then
            for c = right, left, -1 do result[#result + 1] = { bottom, c } end
            bottom = bottom - 1
        end
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
