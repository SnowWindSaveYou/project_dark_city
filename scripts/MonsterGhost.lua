-- ============================================================================
-- MonsterGhost.lua - 怪物 Chibi 弹出浮动系统
-- 踩到怪物牌时小怪物们环绕玩家弹出浮动
-- 拍摄鉴定怪物时在卡牌上方显示怪物 Chibi
-- ============================================================================

local Tween = require "lib.Tween"
local Board = require "Board"

local M = {}

-- ---------------------------------------------------------------------------
-- 怪物 Chibi 贴图映射 (地点 → 主怪物贴图)
-- ---------------------------------------------------------------------------
local MONSTER_CHIBI = {
    company  = "image/怪物_无脸商人_20260426071011.png",
    school   = "image/怪物_长发女鬼v2_20260426072646.png",
    park     = "image/怪物_双尾猫妖v3_20260426071805.png",
    alley    = "image/怪物_幽灵娘v3_20260426072315.png",
    station  = "image/怪物_小幽灵_20260426072511.png",
    hospital = "image/怪物_幽灵娘v3_20260426072315.png",
    library  = "image/怪物_长发女鬼v2_20260426072646.png",
    bank     = "image/edited_怪物_面具使v3_20260426073034.png",
}
local DEFAULT_MONSTER = "image/怪物_小幽灵_20260426072511.png"

-- 小幽灵表情变体 (随机伴生)
local GHOST_VARIANTS = {
    "image/小幽灵_愤怒v2_20260426073743.png",
    "image/小幽灵_开心v2_20260426073756.png",
    "image/小幽灵_狡猾v2_20260426073758.png",
    "image/小幽灵_委屈v2_20260426073907.png",
    "image/小幽灵_瞌睡v2_20260426073910.png",
    "image/怪物_小幽灵_20260426072511.png",
}

-- ---------------------------------------------------------------------------
-- 环绕布局定义 (dx, dz 相对玩家的偏移, baseY 基础高度, size 尺寸)
-- 有高有低有前有后, 错落有致
-- ---------------------------------------------------------------------------
local SURROUND_LAYOUT = {
    -- 主怪物: 正后方偏高, 最大
    { dx =  0.00, dz =  0.20, baseY = 0.55, size = 0.32, isMain = true },
    -- 小幽灵们: 散布四周, 大小不一
    { dx = -0.35, dz = -0.15, baseY = 0.30, size = 0.18 },
    { dx =  0.32, dz =  0.08, baseY = 0.42, size = 0.20 },
    { dx = -0.18, dz =  0.30, baseY = 0.60, size = 0.15 },
    { dx =  0.25, dz = -0.20, baseY = 0.25, size = 0.16 },
}

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------
---@type userdata
local scene_ = nil
---@type userdata
local parentNode_ = nil

---@class GhostSprite
---@field node userdata Billboard 节点
---@field bbSet userdata BillboardSet
---@field bb userdata Billboard
---@field phase number 浮动相位
---@field baseY number 基础高度
---@field anchorX number 锚定世界 X
---@field anchorZ number 锚定世界 Z
---@field scale number 当前缩放 (用于弹出动画)
---@field alpha number 当前透明度
---@field size number 目标尺寸 (米)
---@field lifetime number 剩余存活时间 (-1 = 不自动消失)

local ghosts_ = {}       -- 环绕玩家的幽灵
local cardGhosts_ = {}   -- 卡牌上的怪物 chibi
local trailGhosts_ = {}  -- 踪迹箭头 (拍到非怪物格时指向最近怪物)

-- ---------------------------------------------------------------------------
-- 创建单个幽灵 Billboard
-- ---------------------------------------------------------------------------
local function createGhostBillboard(texPath, worldX, worldZ, baseY, size, phase)
    local node = parentNode_:CreateChild("Ghost")
    node:SetPosition(Vector3(worldX, 0, worldZ))

    local bbSet = node:CreateComponent("BillboardSet")
    bbSet:SetNumBillboards(1)
    bbSet:SetFaceCameraMode(FC_ROTATE_Y)
    bbSet:SetSorted(true)

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    local tex = cache:GetResource("Texture2D", texPath)
    if tex then
        mat:SetTexture(TU_DIFFUSE, tex)
    end
    bbSet:SetMaterial(mat)

    local bb = bbSet:GetBillboard(0)
    bb.position = Vector3(0, baseY, 0)
    bb.size = Vector2(0.001, 0.001) -- 初始极小, 弹出动画放大
    bb.color = Color(1, 1, 1, 0)
    bb.enabled = true
    bbSet:Commit()

    return {
        node = node,
        bbSet = bbSet,
        bb = bb,
        phase = phase,
        baseY = baseY,
        anchorX = worldX,
        anchorZ = worldZ,
        scale = 0,
        alpha = 0,
        size = size,
        lifetime = 4.0,  -- 4 秒后自动消失
    }
end

-- ---------------------------------------------------------------------------
-- 公开 API
-- ---------------------------------------------------------------------------

--- 初始化 (在 scene 创建后调用一次)
function M.init(scene)
    scene_ = scene
    parentNode_ = scene:CreateChild("MonsterGhosts")
end

--- 清除所有环绕幽灵
function M.clearSurround()
    for _, g in ipairs(ghosts_) do
        Tween.cancelTarget(g)
        if g.node then g.node:Remove() end
    end
    ghosts_ = {}
end

--- 清除所有卡牌上的 chibi
function M.clearCardGhosts()
    for _, g in ipairs(cardGhosts_) do
        Tween.cancelTarget(g)
        if g.node then g.node:Remove() end
    end
    cardGhosts_ = {}
end

--- 清除所有踪迹箭头
function M.clearTrailGhosts()
    for _, g in ipairs(trailGhosts_) do
        Tween.cancelTarget(g)
        if g.node then g.node:Remove() end
    end
    trailGhosts_ = {}
end

--- 清除全部
function M.clear()
    M.clearSurround()
    M.clearCardGhosts()
    M.clearTrailGhosts()
end

--- 相机模式进入时: 在所有已侦测的怪物卡牌上显示 chibi
---@param board table 棋盘数据 (board.cards[r][c])
---@param ROWS number 行数
---@param COLS number 列数
function M.showOnScoutedCards(board, ROWS, COLS)
    M.clearCardGhosts()
    if not parentNode_ or not board or not board.cards then return end

    for r = 1, ROWS do
        for c = 1, COLS do
            local cd = board.cards[r] and board.cards[r][c]
            if cd and cd.scouted and cd.type == "monster" then
                local texPath = MONSTER_CHIBI[cd.location] or DEFAULT_MONSTER
                local gx = cd.x or 0
                local gz = cd.y or 0
                local ghost = createGhostBillboard(texPath, gx, gz, 0.35, 0.28, math.random() * 3.0)
                ghost.lifetime = -1
                cardGhosts_[#cardGhosts_ + 1] = ghost
                -- 弹出动画
                Tween.to(ghost, { scale = 1.0, alpha = 1.0 }, 0.3, {
                    easing = Tween.Easing.easeOutBack,
                    delay = 0.1 + (#cardGhosts_ - 1) * 0.05,
                    tag = "card_ghost_pop",
                })
            end
        end
    end
    print(string.format("[MonsterGhost] showOnScoutedCards: found %d monster cards", #cardGhosts_))
end

--- 踩到怪物牌时: 在玩家周围弹出怪物 chibi
---@param worldX number 玩家世界坐标 X
---@param worldZ number 玩家世界坐标 Z
---@param location string|nil 地点名 (用于选择主怪物贴图)
function M.spawnAroundPlayer(worldX, worldZ, location)
    M.clearSurround()
    if not parentNode_ then
        print("[MonsterGhost] spawnAroundPlayer: parentNode_ is nil!")
        return
    end

    local mainTex = MONSTER_CHIBI[location] or DEFAULT_MONSTER
    print(string.format("[MonsterGhost] spawnAroundPlayer: loc=%s, pos=(%.2f, %.2f)",
        tostring(location), worldX, worldZ))

    for i, slot in ipairs(SURROUND_LAYOUT) do
        local texPath
        if slot.isMain then
            texPath = mainTex
        else
            texPath = GHOST_VARIANTS[math.random(1, #GHOST_VARIANTS)]
        end

        local gx = worldX + slot.dx
        local gz = worldZ + slot.dz
        local phase = (i - 1) * 1.3 + math.random() * 0.5

        local ghost = createGhostBillboard(texPath, gx, gz, slot.baseY, slot.size, phase)
        ghost.lifetime = -1  -- 不自动消失, 角色离开时由外部调用 clearSurround()
        ghosts_[#ghosts_ + 1] = ghost

        -- 弹出动画: 延迟交错, easeOutBack 回弹
        Tween.to(ghost, { scale = 1.0, alpha = 1.0 }, 0.35, {
            easing = Tween.Easing.easeOutBack,
            delay = i * 0.07,
            tag = "ghost_pop",
        })
    end
end

--- 拍摄鉴定怪物后: 在卡牌上方显示怪物 chibi
---@param card table 卡牌数据 (card.x → worldX, card.y → worldZ)
---@param location string|nil 地点名
function M.showOnCard(card, location)
    if not parentNode_ then
        print("[MonsterGhost] showOnCard: parentNode_ is nil!")
        return
    end
    if not card then
        print("[MonsterGhost] showOnCard: card is nil!")
        return
    end

    local texPath = MONSTER_CHIBI[location] or DEFAULT_MONSTER

    -- 直接使用卡牌逻辑坐标 (与 Card.syncNode 一致: card.x→worldX, card.y→worldZ)
    local gx = card.x or 0
    local gz = card.y or 0

    print(string.format("[MonsterGhost] showOnCard: location=%s, pos=(%.2f, %.2f), tex=%s",
        tostring(location), gx, gz, texPath))

    local ghost = createGhostBillboard(texPath, gx, gz, 0.35, 0.28, math.random() * 3.0)
    ghost.lifetime = -1  -- 不自动消失 (跟随弹窗关闭时清除)
    cardGhosts_[#cardGhosts_ + 1] = ghost

    -- 从卡面弹出
    Tween.to(ghost, { scale = 1.0, alpha = 1.0 }, 0.3, {
        easing = Tween.Easing.easeOutBack,
        delay = 0.15,
        tag = "card_ghost_pop",
    })
end

-- ---------------------------------------------------------------------------
-- 踪迹箭头: 拍到非怪物格时, 显示小幽灵指向最近怪物
-- ---------------------------------------------------------------------------

--- 在棋盘中寻找距离指定格子最近的怪物 (未翻开的)
---@param board table 棋盘数据
---@param fromRow number 起始行
---@param fromCol number 起始列
---@param ROWS number
---@param COLS number
---@return number|nil row, number|nil col, number|nil dist
local function findNearestMonster(board, fromRow, fromCol, ROWS, COLS)
    local bestR, bestC, bestDist = nil, nil, math.huge
    for r = 1, ROWS do
        for c = 1, COLS do
            if r ~= fromRow or c ~= fromCol then
                local cd = board.cards[r] and board.cards[r][c]
                -- 排除安全区内的怪物 (地标光环范围, 翻开时会自动变 safe)
                if cd and cd.type == "monster" and not cd.faceUp
                   and not Board.isInLandmarkAura(board, r, c) then
                    local dr = r - fromRow
                    local dc = c - fromCol
                    local dist = math.sqrt(dr * dr + dc * dc)
                    if dist < bestDist then
                        bestR, bestC, bestDist = r, c, dist
                    end
                end
            end
        end
    end
    return bestR, bestC, bestDist
end

--- 在卡牌上创建踪迹箭头: 小幽灵 chibi 偏移到指向怪物的方向
---@param card table 被拍照的卡牌
---@param dirX number 方向 X 分量 (世界坐标)
---@param dirZ number 方向 Z 分量 (世界坐标)
function M.showTrailOnCard(card, dirX, dirZ)
    if not parentNode_ or not card then return end

    -- 随机选一个小幽灵变体
    local texPath = GHOST_VARIANTS[math.random(1, #GHOST_VARIANTS)]

    local gx = card.x or 0
    local gz = card.y or 0

    -- 方向归一化, 小幽灵偏移到卡牌边缘 (0.38m ≈ 卡宽一半)
    local len = math.sqrt(dirX * dirX + dirZ * dirZ)
    local offsetX, offsetZ = 0, 0
    if len > 0.001 then
        offsetX = (dirX / len) * 0.38
        offsetZ = (dirZ / len) * 0.38
    end

    local ghost = createGhostBillboard(texPath, gx + offsetX, gz + offsetZ, 0.25, 0.14, math.random() * 3.0)
    ghost.lifetime = -1
    ghost.offsetX = offsetX  -- 记录偏移, update 时使用
    ghost.offsetZ = offsetZ
    ghost.cardX = gx  -- 记录卡牌基准位置
    ghost.cardZ = gz
    trailGhosts_[#trailGhosts_ + 1] = ghost

    -- 弹出动画
    Tween.to(ghost, { scale = 1.0, alpha = 0.85 }, 0.35, {
        easing = Tween.Easing.easeOutBack,
        delay = 0.2,
        tag = "trail_ghost_pop",
    })
end

--- 相机模式进入时: 显示所有已记录的踪迹箭头 (从 card.trailDir 恢复)
---@param board table 棋盘数据
---@param ROWS number
---@param COLS number
function M.showTrailsOnBoard(board, ROWS, COLS)
    M.clearTrailGhosts()
    if not parentNode_ or not board or not board.cards then return end

    for r = 1, ROWS do
        for c = 1, COLS do
            local cd = board.cards[r] and board.cards[r][c]
            if cd and cd.trailDirX and cd.trailDirZ then
                M.showTrailOnCard(cd, cd.trailDirX, cd.trailDirZ)
            end
        end
    end
    print(string.format("[MonsterGhost] showTrailsOnBoard: found %d trail arrows", #trailGhosts_))
end

--- 计算并记录踪迹方向到卡牌数据上
---@param card table 被拍照的卡牌 (非怪物)
---@param board table 棋盘数据
---@param ROWS number
---@param COLS number
---@return boolean found 是否找到了最近的怪物
function M.calculateTrail(card, board, ROWS, COLS)
    local mr, mc, dist = findNearestMonster(board, card.row, card.col, ROWS, COLS)
    if not mr then
        print(string.format("[MonsterGhost] calculateTrail(%d,%d): no monster found", card.row, card.col))
        card.trailDirX = nil
        card.trailDirZ = nil
        return false
    end

    -- 方向: 从被拍卡牌指向最近怪物 (用行列差映射到世界 XZ)
    -- col → X, row → Z
    local dirX = mc - card.col
    local dirZ = mr - card.row
    card.trailDirX = dirX
    card.trailDirZ = dirZ

    print(string.format("[MonsterGhost] calculateTrail(%d,%d) → nearest monster(%d,%d) dist=%.1f dir=(%.1f,%.1f)",
        card.row, card.col, mr, mc, dist, dirX, dirZ))
    return true
end

-- ---------------------------------------------------------------------------
-- 每帧更新
-- ---------------------------------------------------------------------------

--- 每帧更新: 浮动动画 + 生命周期
---@param dt number
---@param gameTime number
function M.update(dt, gameTime)
    -- 环绕幽灵
    local i = 1
    while i <= #ghosts_ do
        local g = ghosts_[i]
        local remove = false

        -- 生命周期倒计时
        if g.lifetime > 0 then
            g.lifetime = g.lifetime - dt
            -- 最后 0.8 秒淡出
            if g.lifetime <= 0.8 and g.alpha > 0 then
                if g.lifetime <= 0 then
                    remove = true
                else
                    g.alpha = math.max(0, g.lifetime / 0.8)
                end
            end
        end

        if remove then
            if g.node then g.node:Remove() end
            table.remove(ghosts_, i)
        else
            -- 浮动: 不同相位的正弦波, Y 轴微微上下
            local floatY = math.sin(gameTime * 2.0 + g.phase) * 0.025
            -- 微弱水平晃动
            local swayX = math.sin(gameTime * 1.2 + g.phase * 0.7) * 0.012

            local s = g.scale * g.size
            g.bb.position = Vector3(swayX, g.baseY + floatY, 0)
            g.bb.size = Vector2(s, s)
            g.bb.color = Color(1, 1, 1, g.alpha)
            g.bbSet:Commit()
            i = i + 1
        end
    end

    -- 卡牌上的 chibi
    for _, g in ipairs(cardGhosts_) do
        local floatY = math.sin(gameTime * 2.5 + g.phase) * 0.02
        local s = g.scale * g.size
        g.bb.position = Vector3(0, g.baseY + floatY, 0)
        g.bb.size = Vector2(s, s)
        g.bb.color = Color(1, 1, 1, g.alpha)
        g.bbSet:Commit()
    end

    -- 踪迹箭头 chibi (偏移方向浮动)
    for _, g in ipairs(trailGhosts_) do
        local floatY = math.sin(gameTime * 2.0 + g.phase) * 0.02
        -- 小幽灵在偏移方向上来回晃动 (像在引路, 幅度大一些更明显)
        local bobT = math.sin(gameTime * 1.8 + g.phase) * 0.15
        local ox = (g.offsetX or 0) * (1.0 + bobT)
        local oz = (g.offsetZ or 0) * (1.0 + bobT)

        local s = g.scale * g.size
        g.bb.position = Vector3(ox, g.baseY + floatY, oz)
        g.bb.size = Vector2(s, s)
        g.bb.color = Color(1, 1, 1, g.alpha)
        g.bbSet:Commit()

        -- 更新节点位置为卡牌基准 (billboard 自身偏移通过 bb.position)
        if g.node and g.cardX then
            g.node:SetPosition(Vector3(g.cardX, 0, g.cardZ))
        end
    end
end

--- 销毁
function M.destroy()
    M.clear()
    if parentNode_ then
        parentNode_:Remove()
        parentNode_ = nil
    end
end

--- 获取地点对应的怪物贴图路径 (给外部使用)
---@param location string
---@return string
function M.getMonsterTexture(location)
    return MONSTER_CHIBI[location] or DEFAULT_MONSTER
end

return M
