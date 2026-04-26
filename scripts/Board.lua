-- ============================================================================
-- Board.lua - 5x5 棋盘布局与卡牌管理 (3D 版本)
-- 世界坐标系: X=左右, Y=上下(高度), Z=前后(深度)
-- 卡牌平铺在 Y=0 平面上
-- ============================================================================

local Card = require "Card"
local Theme = require "Theme"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
M.ROWS = 5
M.COLS = 5
M.GAP  = 0.12  -- 卡牌间距 (米)

-- 牌堆位置 (世界坐标, 在棋盘右侧外)
M.DECK_X = 3.0
M.DECK_Z = -1.5

-- ---------------------------------------------------------------------------
-- 构造
-- ---------------------------------------------------------------------------

---@class BoardData
---@field cards table[]  二维数组 [row][col]
---@field homeRow number 家的行号
---@field homeCol number 家的列号
---@field boardNode userdata 棋盘根节点 (3D)

function M.new()
    return {
        cards = {},
        homeRow = 3,
        homeCol = 3,
        isDealt = false,
        boardNode = nil,  -- 3D 场景节点

        -- 兼容旧代码 (发牌起点)
        deckX = M.DECK_X,
        deckY = M.DECK_Z,  -- card.y → worldZ
    }
end

-- ---------------------------------------------------------------------------
-- 世界坐标计算 (棋盘中心在原点)
-- ---------------------------------------------------------------------------

--- 获取指定格子的世界坐标 (中心)
---@return number worldX, number worldZ
function M.cardPos(board, row, col)
    local cw, ch = Card.CARD_W, Card.CARD_H
    local gap = M.GAP

    -- 以 (0,0) 为中心
    -- col: 1..5 → (col - 3) * stride
    -- row: 1..5 → (row - 3) * stride
    local worldX = (col - 3) * (cw + gap)
    local worldZ = (row - 3) * (ch + gap)

    return worldX, worldZ
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
-- 生成卡牌 (地点 + 事件双层系统) — 逻辑不变
-- ---------------------------------------------------------------------------

function M.generateCards(board, requiredLocations)
    -- 先销毁旧的 3D 节点
    M.destroyAllNodes(board)

    board.cards = {}
    local usedPositions = {}

    -- 1. 家
    local homePos = randomPositions(1, nil)
    board.homeRow = homePos[1][1]
    board.homeCol = homePos[1][2]
    usedPositions[#usedPositions + 1] = { board.homeRow, board.homeCol }

    -- 2. 地标
    local landmarkCount = math.random(1, 2)
    local landmarkPositions = randomPositions(landmarkCount, usedPositions)
    for _, pos in ipairs(landmarkPositions) do
        usedPositions[#usedPositions + 1] = pos
    end

    -- 3. 商店
    local shopPositions = randomPositions(1, usedPositions)
    for _, pos in ipairs(shopPositions) do
        usedPositions[#usedPositions + 1] = pos
    end

    -- 4. 地点池 (普通格子: 排除地标/商店地点, 避免与专用格子混淆)
    local normalSlots = M.ROWS * M.COLS - #usedPositions
    local locationPool = {}
    local usedInPool = {}

    -- 地标和商店地点集合 (不应出现在普通格子中)
    local specialLocSet = { home = true, convenience = true }
    for _, lmLoc in ipairs(Card.LANDMARK_LOCATIONS) do
        specialLocSet[lmLoc] = true
    end

    if requiredLocations then
        for _, loc in ipairs(requiredLocations) do
            -- 只接纳非地标/非商店的地点
            if not usedInPool[loc] and not specialLocSet[loc] then
                locationPool[#locationPool + 1] = loc
                usedInPool[loc] = true
            end
        end
    end

    -- 回填: 从 REGULAR_LOCATIONS 中选择未使用的地点, 避免重复
    local fillCandidates = {}
    for _, loc in ipairs(Card.REGULAR_LOCATIONS) do
        if not usedInPool[loc] then
            fillCandidates[#fillCandidates + 1] = loc
        end
    end
    for i = #fillCandidates, 2, -1 do
        local j = math.random(1, i)
        fillCandidates[i], fillCandidates[j] = fillCandidates[j], fillCandidates[i]
    end
    local fillIdx = 1

    -- 优先用不重复的地点, 用完后允许重复 (棋盘格子可能多于地点种类)
    while #locationPool < normalSlots do
        if fillIdx <= #fillCandidates then
            locationPool[#locationPool + 1] = fillCandidates[fillIdx]
            fillIdx = fillIdx + 1
        else
            -- 已无不重复地点可用, 从全部 REGULAR_LOCATIONS 随机补
            locationPool[#locationPool + 1] = Card.REGULAR_LOCATIONS[
                math.random(1, #Card.REGULAR_LOCATIONS)
            ]
        end
    end
    for i = #locationPool, 2, -1 do
        local j = math.random(1, i)
        locationPool[i], locationPool[j] = locationPool[j], locationPool[i]
    end
    local locIdx = 1

    -- 5. 事件池
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
    local specialMap = {}
    specialMap[board.homeRow .. "," .. board.homeCol] = "home"
    for _, pos in ipairs(landmarkPositions) do
        specialMap[pos[1] .. "," .. pos[2]] = "landmark"
    end
    for _, pos in ipairs(shopPositions) do
        specialMap[pos[1] .. "," .. pos[2]] = "shop"
    end

    local landmarkLocations = {}
    for i, loc in ipairs(Card.LANDMARK_LOCATIONS) do
        landmarkLocations[i] = loc
    end
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
                location = "convenience"
            else
                cardType = randomEvent()
                location = locationPool[locIdx]
                locIdx = locIdx + 1
            end

            local card = Card.new(cardType, row, col, location)
            -- 初始位置在牌堆 (世界坐标)
            card.x = M.DECK_X
            card.y = M.DECK_Z
            board.cards[row][col] = card
        end
    end

    print(string.format("[Board] Generated: home=(%d,%d), landmarks=%d, shops=%d",
        board.homeRow, board.homeCol, landmarkCount, #shopPositions))
end

-- ---------------------------------------------------------------------------
-- 3D 节点管理
-- ---------------------------------------------------------------------------

--- 为所有卡牌创建 3D 节点
function M.createAllNodes(board, parentNode, CardTextures)
    board.boardNode = parentNode:CreateChild("Board")

    for row = 1, M.ROWS do
        if board.cards[row] then
            for col = 1, M.COLS do
                local card = board.cards[row][col]
                if card then
                    Card.createNode(card, board.boardNode, CardTextures)
                end
            end
        end
    end
    print("[Board] Created 3D nodes for all cards")
end

--- 销毁所有卡牌 3D 节点
function M.destroyAllNodes(board)
    for row = 1, M.ROWS do
        if board.cards[row] then
            for col = 1, M.COLS do
                local card = board.cards[row][col]
                if card then
                    Card.destroyNode(card)
                end
            end
        end
    end
    if board.boardNode then
        board.boardNode:Remove()
        board.boardNode = nil
    end
end

--- 每帧同步所有卡牌的 3D 节点 Transform
function M.syncAllNodes(board)
    for row = 1, M.ROWS do
        if board.cards[row] then
            for col = 1, M.COLS do
                local card = board.cards[row][col]
                if card then
                    Card.syncNode(card)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 查询: 地标光环
-- ---------------------------------------------------------------------------

function M.isInLandmarkAura(board, row, col)
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
-- 发牌动画 (螺旋顺序)
-- ---------------------------------------------------------------------------

function M.dealAll(board, onComplete)
    board.isDealt = false
    local order = M.spiralOrder()
    local totalCards = #order

    -- 渐进加速延迟: 前几张牌出得从容，后面越来越快
    -- 间隔从 0.09s 逐渐降到 0.03s
    local accDelay = 0
    local lastDelay = 0

    for i, pos in ipairs(order) do
        local row, col = pos[1], pos[2]
        local card = board.cards[row][col]
        if card then
            local tx, tz = M.cardPos(board, row, col)
            Card.dealTo(card, tx, tz, accDelay)
            lastDelay = accDelay

            -- 间隔随进度递减: lerp(0.09, 0.03, progress)
            local progress = i / totalCards
            local interval = 0.09 - 0.06 * progress
            accDelay = accDelay + interval
        end
    end

    if onComplete then
        board._dealTimer = lastDelay + 0.50
        board._dealCallback = onComplete
    end
end

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
-- 收牌动画
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
            Card.undeal(card, M.DECK_X, M.DECK_Z, delay, isLast and onComplete or nil)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 螺旋遍历顺序
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
-- 碰撞检测: 射线-平面交汇 + 卡牌矩形检测
-- ---------------------------------------------------------------------------

--- 从屏幕坐标射线检测卡牌 (3D ray-plane 交汇)
---@param board BoardData
---@param camera userdata Camera 组件
---@param screenX number 物理像素 X
---@param screenY number 物理像素 Y
---@param screenW number 屏幕物理宽
---@param screenH number 屏幕物理高
---@return CardData|nil card, number row, number col
function M.hitTest(board, camera, screenX, screenY, screenW, screenH)
    if not camera then
        return nil, 0, 0
    end

    -- 屏幕坐标归一化到 [0,1]
    local nx = screenX / screenW
    local ny = screenY / screenH

    -- 获取射线
    local ray = camera:GetScreenRay(nx, ny)
    local origin = ray.origin
    local dir = ray.direction

    -- 与 Y=0 平面求交
    if math.abs(dir.y) < 0.0001 then
        return nil, 0, 0  -- 射线几乎平行于平面
    end

    local t = -origin.y / dir.y
    if t < 0 then
        return nil, 0, 0  -- 交点在射线背面
    end

    local hitX = origin.x + dir.x * t
    local hitZ = origin.z + dir.z * t

    -- 遍历卡牌检测
    for row = 1, M.ROWS do
        for col = 1, M.COLS do
            local card = board.cards[row][col]
            if card and Card.hitTest(card, hitX, hitZ) then
                return card, row, col
            end
        end
    end
    return nil, 0, 0
end

--- 世界坐标点击检测 (用于已知世界坐标的快捷检测)
function M.hitTestWorld(board, worldX, worldZ)
    for row = 1, M.ROWS do
        for col = 1, M.COLS do
            local card = board.cards[row][col]
            if card and Card.hitTest(card, worldX, worldZ) then
                return card, row, col
            end
        end
    end
    return nil, 0, 0
end

return M
