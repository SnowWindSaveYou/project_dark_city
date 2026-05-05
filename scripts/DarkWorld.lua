-- ============================================================================
-- DarkWorld.lua - 暗面世界主控制器 (复用 Board 卡牌系统)
-- 3层持久化地图 + 能量系统 + 小幽灵AI + 进出/层间转移 + HUD绘制
-- 不再管理3D节点 — 所有卡牌由 Board.lua 统一管理
-- ============================================================================

local Tween       = require "lib.Tween"
local VFX         = require "lib.VFX"
local Theme       = require "Theme"
local Card        = require "Card"
local Board       = require "Board"
local Token       = require "Token"
local ResourceBar = require "ResourceBar"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
local ROWS = Board.ROWS
local COLS = Board.COLS
local MAX_ENERGY   = 10      -- 每层独立能量
local GHOST_SAN    = -2      -- 幽灵碰撞扣除理智
local GHOST_COUNT  = { 2, 3, 2 } -- 各层幽灵数量
local GHOST_CHASE_DIST = 2   -- 曼哈顿距离 ≤ 此值时 100% 追逐玩家

-- 层级配置 (灵感阈值解锁)
local LAYER_CONFIG = {
    { name = "表层·暗巷", unlockInspiration = 15 },
    { name = "中层·暗市", unlockInspiration = 25 },
    { name = "深层·暗渊", unlockInspiration = 45 },
}

-- 暗面世界地点名称池 (按层级)
local DARK_LOCATIONS = {
    -- Layer 1: 暗巷
    {
        normal = { "锈蚀小巷", "断灯走廊", "裂墙弄堂", "落灰阶梯", "无名死路",
                   "潮湿拐角", "暗影墙根", "废弃车库", "野猫巢穴", "塌陷天桥" },
        shop   = { },
        intel  = { },
        clue   = { "旧档案室", "碎纸堆", "褪色涂鸦" },
        item   = { "废弃背包", "暗格" },
    },
    -- Layer 2: 暗市
    {
        normal = { "无光集市", "影子摊位", "假面人群", "沉默柜台", "回声茶馆",
                   "钟表废铺", "药粉小巷", "纸灯笼路", "地下水渠", "迷雾广场" },
        shop   = { "无光集市", "暗巷当铺" },
        intel  = { "回声茶馆", "低语井" },
        clue   = { "密封信件", "帐本残页", "暗号墙" },
        item   = { "上锁匣子", "遗落药包" },
    },
    -- Layer 3: 深渊
    {
        normal = { "崩塌深穴", "骨架走廊", "回声深渊", "凝视大厅", "泣血石室",
                   "虚无阶梯", "裂缝祭坛", "悬浮残桥", "镜像迷宫", "最终长廊" },
        shop   = { },
        intel  = { },
        clue   = { "深渊碑文", "模糊日记", "封印遗物" },
        item   = { "黑曜石碎片" },
    },
}

-- 暗面世界 NPC 配置 (per layer)
local DARK_NPCS = {
    -- Layer 1: 双尾猫妖
    {
        { id = "nekomata", name = "双尾猫妖", tex = "image/怪物_双尾猫妖v3_20260426071805.png",
          dialogue = {
              { speaker = "双尾猫妖", text = "喵~你也迷路了吗？这里的巷子会自己改变方向的……" },
              { speaker = "双尾猫妖", text = "小心那些飘来飘去的家伙，它们可不像我这么友好。" },
              { speaker = "双尾猫妖", text = "要是走不动了就回去吧，反正下次来还是这条路。" },
          },
        },
    },
    -- Layer 2: 幽灵娘 + 无脸商人
    {
        { id = "ghost_girl", name = "幽灵娘", tex = "image/怪物_幽灵娘v3_20260426072315.png",
          dialogue = {
              { speaker = "幽灵娘", text = "……你在找什么？" },
              { speaker = "幽灵娘", text = "她留下过很多东西，散落在各个角落里……" },
              { speaker = "幽灵娘", text = "那些碎片……拼在一起也许能看到些什么。" },
          },
        },
        { id = "faceless", name = "无脸商人", tex = "image/怪物_无脸商人_20260426071011.png",
          dialogue = {
              { speaker = "无脸商人", text = "……" },
              { speaker = "无脸商人", text = "只认钱。不问来历。" },
              { speaker = "无脸商人", text = "想要什么……自己看。" },
          },
        },
    },
    -- Layer 3: 面具使
    {
        { id = "mask_user", name = "面具使", tex = "image/edited_怪物_面具使v3_20260426073034.png",
          dialogue = {
              { speaker = "面具使", text = "到这里来的人……都在找什么东西。" },
              { speaker = "面具使", text = "最深处有一个地方……但你需要足够的碎片。" },
              { speaker = "面具使", text = "去看看吧，如果你觉得自己准备好了的话。" },
          },
        },
    },
}

-- 小幽灵贴图
local GHOST_TEXTURES = {
    "image/小幽灵_愤怒v2_20260426073743.png",
    "image/小幽灵_开心v2_20260426073756.png",
    "image/小幽灵_狡猾v2_20260426073758.png",
    "image/小幽灵_委屈v2_20260426073907.png",
    "image/小幽灵_瞌睡v2_20260426073910.png",
}

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------

---@type boolean 暗面世界是否激活
local active_ = false

---@type number 当前层级 1-3
local currentLayer_ = 1

---@type table[3] 层级数据 (持久化)
local layers_ = nil

---@type userdata 3D 场景引用
local scene_ = nil

---@type table 暗面幽灵 Billboard 节点列表
local ghostNodes_ = {}

---@type table NPC Billboard 节点列表
local npcNodes_ = {}

---@type userdata NanoVG context
local vg_ = nil

---@type number 全局游戏时间 (由 update 同步)
local gameTime_ = 0

---@type number 进入时的裂隙位置 (现实世界)
local riftRow_ = 0
local riftCol_ = 0

---@type function 退出回调
local onExit_ = nil

---@type table CardTextures 模块引用
local CardTextures_ = nil

---@type table 入场/退场过渡
local transition_ = { alpha = 0, phase = "none" }

---@type number 能量变化闪烁计时器
local energyFlash_ = 0

---@type string 暗面世界子状态
local darkState_ = "idle"  -- "idle" | "ready" | "moving" | "popup" | "transition"

-- 相机引用
local camera_ = nil
local physW_, physH_ = 0, 0

-- Board 引用 (main.lua 的 board 对象)
local board_ = nil

-- ---------------------------------------------------------------------------
-- 层级数据构造
-- ---------------------------------------------------------------------------

local function newLayerData(layerIdx)
    return {
        index       = layerIdx,
        config      = LAYER_CONFIG[layerIdx],
        unlocked    = false,
        generated   = false,
        walkable    = {},      -- [row][col] = bool
        ghosts      = {},      -- { {row, col, alive, texIdx}, ... }
        npcs        = {},      -- { {id, name, row, col, tex, dialogue}, ... }
        playerRow   = 3,
        playerCol   = 3,
        energy      = MAX_ENERGY,
        entryRow    = 3,
        entryCol    = 3,
        collected   = {},      -- [row..","..col] = true
    }
end

-- ---------------------------------------------------------------------------
-- 辅助函数
-- ---------------------------------------------------------------------------

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

--- 获取格子可通行的邻居
local function getWalkableNeighbors(layer, row, col)
    local neighbors = {}
    local dirs = { {-1,0}, {1,0}, {0,-1}, {0,1} }
    for _, d in ipairs(dirs) do
        local nr, nc = row + d[1], col + d[2]
        if nr >= 1 and nr <= ROWS and nc >= 1 and nc <= COLS then
            if layer.walkable[nr] and layer.walkable[nr][nc] then
                neighbors[#neighbors + 1] = { nr, nc }
            end
        end
    end
    return neighbors
end

-- ---------------------------------------------------------------------------
-- 暗面层级配置 (供 Board.generateDarkCards 使用)
-- ---------------------------------------------------------------------------

--- 获取指定层的卡牌生成配置
---@param layerIdx number 1-3
---@return table darkConfig
function M.getDarkConfig(layerIdx)
    if layerIdx == 1 then
        return {
            layerIdx = 1,
            wallCount = math.random(5, 7),
            passageCount = 1,
            shopCount = 0,
            intelCount = 0,
            checkpointCount = 0,
            clueCount = math.random(3, 5),
            itemCount = math.random(1, 3),
            hasAbyssCore = false,
        }
    elseif layerIdx == 2 then
        return {
            layerIdx = 2,
            wallCount = math.random(4, 6),
            passageCount = 2,
            shopCount = math.random(1, 2),
            intelCount = math.random(1, 2),
            checkpointCount = math.random(1, 2),
            clueCount = math.random(3, 5),
            itemCount = math.random(1, 3),
            hasAbyssCore = false,
        }
    else
        return {
            layerIdx = 3,
            wallCount = math.random(6, 8),
            passageCount = 0,
            shopCount = 0,
            intelCount = 0,
            checkpointCount = math.random(1, 2),
            clueCount = math.random(3, 5),
            itemCount = math.random(1, 3),
            hasAbyssCore = true,
        }
    end
end

--- 获取指定层的地点名称池
---@param layerIdx number 1-3
---@return table darkLocations
function M.getDarkLocations(layerIdx)
    return DARK_LOCATIONS[layerIdx] or DARK_LOCATIONS[1]
end

-- ---------------------------------------------------------------------------
-- 幽灵 & NPC 生成 (在 Board 生成卡牌后调用)
-- ---------------------------------------------------------------------------

--- 为当前层生成幽灵数据 (不创建节点)
local function generateGhosts(layerIdx, layer)
    local ghostCount = GHOST_COUNT[layerIdx]
    local walkablePositions = {}
    for r = 1, ROWS do
        for c = 1, COLS do
            if layer.walkable[r] and layer.walkable[r][c] then
                -- 排除入口
                if not (r == 3 and c == 3) then
                    walkablePositions[#walkablePositions + 1] = { r, c }
                end
            end
        end
    end
    shuffle(walkablePositions)

    layer.ghosts = {}
    for i = 1, math.min(ghostCount, #walkablePositions) do
        layer.ghosts[i] = {
            row   = walkablePositions[i][1],
            col   = walkablePositions[i][2],
            alive = true,
            texIdx = math.random(1, #GHOST_TEXTURES),
        }
    end
end

--- 为当前层生成 NPC 数据 (不创建节点)
local function generateNPCs(layerIdx, layer)
    local npcDefs = DARK_NPCS[layerIdx]
    if not npcDefs then return end

    local walkablePositions = {}
    for r = 1, ROWS do
        for c = 1, COLS do
            if layer.walkable[r] and layer.walkable[r][c] then
                if not (r == 3 and c == 3) then
                    walkablePositions[#walkablePositions + 1] = { r, c }
                end
            end
        end
    end
    shuffle(walkablePositions)

    layer.npcs = {}
    for i, def in ipairs(npcDefs) do
        local pos = walkablePositions[i]
        if pos then
            layer.npcs[#layer.npcs + 1] = {
                id       = def.id,
                name     = def.name,
                row      = pos[1],
                col      = pos[2],
                tex      = def.tex,
                dialogue = def.dialogue,
            }
        end
    end
end

-- ---------------------------------------------------------------------------
-- 幽灵 & NPC 3D 节点 (Billboard, 独立于 Board 管理)
-- ---------------------------------------------------------------------------

--- 创建幽灵 Billboard 节点 (附着在 boardNode 上)
---@param layer table
---@param parentNode userdata
function M.createGhostNodes(layer, parentNode)
    M.destroyGhostNodes()
    if not parentNode then return end

    for i, ghost in ipairs(layer.ghosts) do
        if ghost.alive then
            local texPath = GHOST_TEXTURES[ghost.texIdx]
            local wx, wz = Board.cardPos(nil, ghost.row, ghost.col)

            local node = parentNode:CreateChild("Ghost_" .. i)
            node:SetPosition(Vector3(wx, 0.25, wz))

            local bs = node:CreateComponent("BillboardSet")
            bs:SetNumBillboards(1)
            bs:SetFaceCameraMode(FC_ROTATE_Y)
            bs:SetSorted(true)

            local mat = Material:new()
            mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
            local tex = cache:GetResource("Texture2D", texPath)
            if tex then
                mat:SetTexture(TU_DIFFUSE, tex)
            end
            mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
            bs:SetMaterial(mat)

            local bb = bs:GetBillboard(0)
            bb.size = Vector2(0.30, 0.30)
            bb.position = Vector3(0, 0.15, 0)
            bb.enabled = true
            bs:Commit()

            ghostNodes_[#ghostNodes_ + 1] = {
                node = node,
                mat  = mat,
                ghostIdx = i,
                baseY = 0.25,
                floatPhase = math.random() * 6.28,
                posX = wx,   -- 当前动画位置 (用于 Tween 插值)
                posZ = wz,
            }
        end
    end
end

--- 创建 NPC Billboard 节点
---@param layer table
---@param parentNode userdata
function M.createNPCNodes(layer, parentNode)
    M.destroyNPCNodes()
    if not parentNode then return end

    for _, npc in ipairs(layer.npcs) do
        local wx, wz = Board.cardPos(nil, npc.row, npc.col)

        local node = parentNode:CreateChild("DarkNPC_" .. npc.id)
        node:SetPosition(Vector3(wx + 0.15, 0.25, wz))

        local bs = node:CreateComponent("BillboardSet")
        bs:SetNumBillboards(1)
        bs:SetFaceCameraMode(FC_ROTATE_Y)
        bs:SetSorted(true)

        local npcMat = Material:new()
        npcMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
        local npcTex = cache:GetResource("Texture2D", npc.tex)
        if npcTex then
            npcMat:SetTexture(TU_DIFFUSE, npcTex)
        end
        npcMat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
        bs:SetMaterial(npcMat)

        local bb = bs:GetBillboard(0)
        bb.size = Vector2(0.35, 0.35)
        bb.position = Vector3(0, 0.18, 0)
        bb.enabled = true
        bs:Commit()

        npcNodes_[#npcNodes_ + 1] = { node = node, npcId = npc.id }
    end
end

--- 销毁幽灵节点
function M.destroyGhostNodes()
    for _, gn in ipairs(ghostNodes_) do
        if gn.node then gn.node:Remove() end
    end
    ghostNodes_ = {}
end

--- 销毁 NPC 节点
function M.destroyNPCNodes()
    for _, nn in ipairs(npcNodes_) do
        if nn.node then nn.node:Remove() end
    end
    npcNodes_ = {}
end

-- ---------------------------------------------------------------------------
-- 幽灵碰撞检测 (需在 moveGhosts 之前定义)
-- ---------------------------------------------------------------------------

--- 检测玩家与幽灵碰撞
local function checkGhostCollision(playerRow, playerCol, resourceBarRef)
    local layer = layers_[currentLayer_]
    if not layer then return false end

    for i, ghost in ipairs(layer.ghosts) do
        if ghost.alive and ghost.row == playerRow and ghost.col == playerCol then
            ghost.alive = false
            for _, gn in ipairs(ghostNodes_) do
                if gn.ghostIdx == i and gn.node then
                    local node = gn.node
                    local mat = gn.mat
                    Tween.to(gn, { fadeOut = 1 }, 0.5, {
                        tag = "darkghost",
                        onUpdate = function(self)
                            if mat then
                                mat:SetShaderParameter("MatDiffColor",
                                    Variant(Color(1, 1, 1, 1 - (self.fadeOut or 0))))
                            end
                        end,
                        onComplete = function()
                            if node then node:Remove() end
                        end,
                    })
                    break
                end
            end
            if resourceBarRef then
                resourceBarRef.change("san", GHOST_SAN)
            end
            VFX.triggerShake(6, 0.3, 15)
            VFX.flashScreen(100, 30, 180, 0.3, 150)
            VFX.spawnBanner("👻 小幽灵! 理智-" .. math.abs(GHOST_SAN), 180, 80, 220, 18, 0.8)
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- 幽灵 AI 移动
-- ---------------------------------------------------------------------------

local function moveGhosts(playerRow, playerCol, resourceBarRef, playerOldRow, playerOldCol)
    local layer = layers_[currentLayer_]
    if not layer then return end

    for i, ghost in ipairs(layer.ghosts) do
        if ghost.alive then
            local neighbors = getWalkableNeighbors(layer, ghost.row, ghost.col)
            if #neighbors > 0 then
                local dist = math.abs(ghost.row - playerRow) + math.abs(ghost.col - playerCol)
                local target

                if dist <= GHOST_CHASE_DIST then
                    -- 追逐模式: 100% 朝玩家移动
                    local bestDist = math.huge
                    for _, nb in ipairs(neighbors) do
                        local d = math.abs(nb[1] - playerRow) + math.abs(nb[2] - playerCol)
                        if d < bestDist then
                            bestDist = d
                            target = nb
                        end
                    end
                else
                    -- 游荡模式: 50% 朝玩家 / 50% 随机
                    if math.random() < 0.5 then
                        local bestDist = math.huge
                        for _, nb in ipairs(neighbors) do
                            local d = math.abs(nb[1] - playerRow) + math.abs(nb[2] - playerCol)
                            if d < bestDist then
                                bestDist = d
                                target = nb
                            end
                        end
                    else
                        target = neighbors[math.random(#neighbors)]
                    end
                end

                if target then
                    local oldRow, oldCol = ghost.row, ghost.col
                    ghost.row = target[1]
                    ghost.col = target[2]

                    -- 幽灵移动后碰撞检测 (幽灵主动撞上玩家)
                    if ghost.row == playerRow and ghost.col == playerCol then
                        checkGhostCollision(playerRow, playerCol, resourceBarRef)
                    end

                    -- 互相换位检测: 幽灵从玩家新位置走到玩家旧位置 (擦肩而过)
                    if ghost.alive and playerOldRow and
                       oldRow == playerRow and oldCol == playerCol and
                       ghost.row == playerOldRow and ghost.col == playerOldCol then
                        checkGhostCollision(playerOldRow, playerOldCol, resourceBarRef)
                    end

                    -- 碰撞后幽灵已死亡, 跳过移动动画 (让淡出 Tween 正常播放)
                    if not ghost.alive then goto continue_ghost end

                    for _, gn in ipairs(ghostNodes_) do
                        if gn.ghostIdx == i then
                            local wx, wz = Board.cardPos(nil, ghost.row, ghost.col)
                            Tween.cancelTarget(gn)
                            local moveSpeed = (dist <= GHOST_CHASE_DIST) and 0.28 or 0.4
                            Tween.to(gn, { posX = wx, posZ = wz }, moveSpeed, {
                                tag = "darkghost",
                                easing = Tween.Easing.easeInOutCubic,
                                onUpdate = function()
                                    if gn.node then
                                        local floatY = math.sin(gameTime_ * 2.5 + gn.floatPhase) * 0.04
                                        gn.node:SetPosition(Vector3(gn.posX, gn.baseY + floatY, gn.posZ))
                                    end
                                end,
                            })
                            break
                        end
                    end
                end
                ::continue_ghost::
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 公开 API
-- ---------------------------------------------------------------------------

--- 初始化暗面世界模块
function M.init(vg)
    vg_ = vg
    layers_ = { newLayerData(1), newLayerData(2), newLayerData(3) }
    active_ = false
    currentLayer_ = 1
    darkState_ = "idle"
    print("[DarkWorld] Module initialized")
end

--- 完全重置
function M.reset()
    M.destroyGhostNodes()
    M.destroyNPCNodes()
    layers_ = { newLayerData(1), newLayerData(2), newLayerData(3) }
    active_ = false
    currentLayer_ = 1
    darkState_ = "idle"
    transition_ = { alpha = 0, phase = "none" }
    energyFlash_ = 0
    Tween.cancelTag("darkworld")
    Tween.cancelTag("darkghost")
    Tween.cancelTag("darktransition")
end

function M.canEnter()
    return ResourceBar.get("inspiration") >= LAYER_CONFIG[1].unlockInspiration
end

function M.isLayerUnlocked(layerIdx)
    local cfg = LAYER_CONFIG[layerIdx]
    if not cfg then return false end
    return ResourceBar.get("inspiration") >= cfg.unlockInspiration
end

function M.isActive()
    return active_
end

function M.getCurrentLayer()
    return currentLayer_
end

function M.getEnergy()
    if not layers_ or not layers_[currentLayer_] then return 0 end
    return layers_[currentLayer_].energy
end

function M.getLayerName()
    return LAYER_CONFIG[currentLayer_].name
end

function M.getState()
    return darkState_
end

function M.setState(s)
    darkState_ = s
end

--- 获取当前层数据
function M.getLayerData()
    if not layers_ then return nil end
    return layers_[currentLayer_]
end

--- 设置 board 引用 (main.lua 在切换时传入)
function M.setBoard(board)
    board_ = board
end

--- 进入暗面世界 (由 main.lua 调用, 仅设置状态)
--- 卡牌生成/发牌/节点创建由 main.lua 的 enterDarkWorld 流程统一处理
---@param dayCount number
---@param riftRow number
---@param riftCol number
---@param scene userdata
---@param camera userdata
---@param cardTextures table
---@param pw number
---@param ph number
---@param onExit function
function M.enter(dayCount, riftRow, riftCol, scene, camera, cardTextures, pw, ph, onExit)
    scene_ = scene
    camera_ = camera
    CardTextures_ = cardTextures
    physW_ = pw
    physH_ = ph
    riftRow_ = riftRow
    riftCol_ = riftCol
    onExit_ = onExit
    active_ = true

    -- 确定进入层级
    if not layers_[currentLayer_].generated then
        currentLayer_ = 1
    end

    -- 解锁层级 (基于灵感值)
    for i = 1, 3 do
        if M.isLayerUnlocked(i) then
            layers_[i].unlocked = true
        end
    end

    -- 生成幽灵和NPC数据 (首次)
    local layer = layers_[currentLayer_]
    if not layer.generated then
        -- Board.generateDarkCards 会设置 layer.walkable
        -- 幽灵和NPC在 Board 生成后由 main.lua 调用 generateOverlayData
    end

    -- 能量 = 当前理智值
    local sanNow = ResourceBar.get("san")
    layer.energy    = sanNow
    layer.maxEnergy = sanNow   -- 记录初始能量上限 (供 HUD 能量条使用)
    darkState_ = "transition"

    print("[DarkWorld] Enter requested, layer=" .. currentLayer_ .. ", energy=" .. sanNow)
end

--- 在 Board 生成卡牌后，生成幽灵和NPC数据
---@param layerIdx number
function M.generateOverlayData(layerIdx)
    local layer = layers_[layerIdx]
    if not layer then return end

    -- walkable 已由 Board.generateDarkCards 设置
    generateGhosts(layerIdx, layer)
    generateNPCs(layerIdx, layer)
    layer.generated = true

    print(string.format("[DarkWorld] Overlay data generated: layer=%d, %d ghosts, %d NPCs",
        layerIdx, #layer.ghosts, #layer.npcs))
end

--- 创建幽灵和NPC的3D节点 (在 Board.createAllNodes 之后调用)
---@param parentNode userdata Board 根节点
function M.createOverlayNodes(parentNode)
    local layer = layers_[currentLayer_]
    if not layer then return end
    M.createGhostNodes(layer, parentNode)
    M.createNPCNodes(layer, parentNode)
end

--- 销毁所有叠加层节点
function M.destroyOverlayNodes()
    M.destroyGhostNodes()
    M.destroyNPCNodes()
end

--- 暗面世界已经完全进入 (发牌完成后调用)
function M.onEnterComplete()
    darkState_ = "ready"
    print("[DarkWorld] Entered Layer " .. currentLayer_)
end

--- 退出暗面世界 (由 main.lua 驱动收牌流程)
--- 返回裂隙位置和退出回调
---@return number riftRow
---@return number riftCol
---@return function onExit
function M.beginExit()
    darkState_ = "transition"
    local rr, rc, cb = riftRow_, riftCol_, onExit_
    return rr, rc, cb
end

--- 退出完成 (main.lua 在收牌+恢复现实棋盘后调用)
function M.onExitComplete()
    M.destroyOverlayNodes()
    active_ = false
    darkState_ = "idle"
    onExit_ = nil
    print("[DarkWorld] Exited to reality")
end

--- 层间移动 — 返回目标层信息 (由 main.lua 驱动收发牌)
---@param targetLayer number
---@return boolean success
---@return string|nil layerName
function M.beginChangeLayer(targetLayer)
    if targetLayer < 1 or targetLayer > 3 then return false end
    if not layers_[targetLayer].unlocked then
        VFX.spawnBanner("该层尚未解锁", 180, 80, 80, 18, 0.8)
        return false
    end

    darkState_ = "transition"
    currentLayer_ = targetLayer

    local layer = layers_[currentLayer_]
    -- 能量 = 当前理智值
    local sanNow = ResourceBar.get("san")
    layer.energy    = sanNow
    layer.maxEnergy = sanNow

    return true, LAYER_CONFIG[targetLayer].name
end

--- 层间移动完成 (新层发牌完成后)
function M.onChangeLayerComplete()
    darkState_ = "ready"
    print("[DarkWorld] Arrived at Layer " .. currentLayer_)
end

--- 处理暗面世界中的卡牌点击
---@param board table Board 实例
---@param token table Token 实例
---@param inputX number
---@param inputY number
---@param resourceBar table
---@param dialogueSystem table
---@param shopPopup table
---@param dayCount number
---@return boolean consumed
function M.handleClick(board, token, inputX, inputY, resourceBar, dialogueSystem, shopPopup, dayCount)
    if not active_ or darkState_ ~= "ready" then return false end

    local layer = layers_[currentLayer_]
    if not layer then return false end

    local card, row, col = Board.hitTest(board, camera_, inputX, inputY, physW_, physH_)
    if not card then return false end

    local pRow = layer.playerRow
    local pCol = layer.playerCol

    -- 只能移动到相邻格子
    local dr = math.abs(row - pRow)
    local dc = math.abs(col - pCol)
    if not (dr + dc == 1) then
        Card.shake(card)
        return true
    end

    -- 检查能量
    if layer.energy <= 0 then
        VFX.spawnBanner("能量耗尽!", 220, 80, 80, 18, 0.8)
        M.requestExit()
        return true
    end

    -- 消耗能量
    layer.energy = layer.energy - 1
    energyFlash_ = 0.5
    -- 同步到 ResourceBar 暗面能量条
    if resourceBar and resourceBar.updateDarkEnergy then
        resourceBar.updateDarkEnergy(layer.energy, layer.maxEnergy or layer.energy)
        resourceBar.flashDarkEnergy()
    end

    -- 移动 Token
    darkState_ = "moving"
    local wx, wz = Board.cardPos(nil, row, col)
    Token.moveTo(token, wx, wz, function()
        layer.playerRow = row
        layer.playerCol = col

        moveGhosts(row, col, resourceBar, pRow, pCol)
        checkGhostCollision(row, col, resourceBar)
        M.handleCardEffect(card, row, col, board, resourceBar, dialogueSystem, shopPopup, dayCount)

        if layer.energy <= 0 then
            Tween.to({ t = 0 }, { t = 1 }, 0.8, {
                tag = "darkworld",
                onComplete = function()
                    VFX.spawnBanner("⚡ 能量耗尽，被迫返回!", 220, 120, 80, 18, 1.0)
                    M.requestExit()
                end,
            })
        elseif darkState_ == "moving" then
            -- 仅在状态仍为 moving 时恢复 ready
            -- (handleCardEffect 可能已将状态改为 popup/transition, 不可覆盖)
            darkState_ = "ready"
        end
    end)

    return true
end

-- 请求退出 (触发 main.lua 退出流程)
local exitRequestCallback_ = nil

function M.setExitCallback(fn)
    exitRequestCallback_ = fn
end

function M.requestExit()
    if exitRequestCallback_ then
        exitRequestCallback_()
    end
end

--- 处理踩上卡牌的效果
function M.handleCardEffect(card, row, col, board, resourceBar, dialogueSystem, shopPopup, dayCount)
    local layer = layers_[currentLayer_]
    local darkType = card.darkType
    local key = row..","..col

    -- NPC 对话检测
    for _, npc in ipairs(layer.npcs) do
        if npc.row == row and npc.col == col and npc.dialogue then
            darkState_ = "popup"
            dialogueSystem.start(npc.dialogue, npc.tex, function()
                darkState_ = "ready"
            end)
            return
        end
    end

    if darkType == "normal" then
        return

    elseif darkType == "shop" then
        local tc = Theme.current
        VFX.spawnBanner("🏪 " .. card.darkName, tc.info.r, tc.info.g, tc.info.b, 18, 0.8)
        shopPopup.show(0, 0, function()
            darkState_ = "ready"
        end, { dark = true })
        darkState_ = "popup"

    elseif darkType == "intel" then
        local cost = 15
        if resourceBar.get("money") >= cost then
            resourceBar.change("money", -cost)
            local tc = Theme.current
            VFX.spawnBanner("👁️ 获得情报!", tc.plot.r, tc.plot.g, tc.plot.b, 18, 0.8)
            VFX.spawnBurst(physW_ / 2, physH_ / 2, 6, tc.plot.r, tc.plot.g, tc.plot.b)
        else
            VFX.spawnBanner("💰 金币不足 (需要" .. cost .. ")", 220, 80, 80, 16, 0.8)
        end

    elseif darkType == "checkpoint" then
        local tc = Theme.current
        VFX.spawnBanner("🚧 " .. card.darkName .. " - 已通过", tc.warning.r, tc.warning.g, tc.warning.b, 16, 0.8)

    elseif darkType == "clue" and not card.darkCollected then
        card.darkCollected = true
        layer.collected[key] = true
        local tc = Theme.current
        VFX.spawnBanner("🔮 发现线索: " .. card.darkName, tc.info.r, tc.info.g, tc.info.b, 18, 1.0)
        VFX.spawnBurst(physW_ / 2, physH_ / 2, 10, 180, 130, 255)
        -- 更新为已收集 → 重新渲染纹理
        card.darkType = "normal"
        card.darkName = "空走廊"
        card.darkIcon = "🌑"
        card.darkLabel = "暗巷"
        if CardTextures_ then
            Card.updateTexture(card, CardTextures_)
        end

    elseif darkType == "item" and not card.darkCollected then
        card.darkCollected = true
        layer.collected[key] = true
        -- 加权奖励池: 常规资源(各2份) + 灵感(2份) + 上限提升(各1份,稀有)
        local rewards = {
            { res = "san",         amt = 5,  label = "🧠理智+5" },
            { res = "san",         amt = 5,  label = "🧠理智+5" },
            { res = "money",       amt = 15, label = "💰金币+15" },
            { res = "money",       amt = 15, label = "💰金币+15" },
            { res = "film",        amt = 1,  label = "🎞️胶卷+1" },
            { res = "film",        amt = 1,  label = "🎞️胶卷+1" },
            { res = "inspiration", amt = 3,  label = "💡灵感+3" },
            { res = "inspiration", amt = 3,  label = "💡灵感+3" },
            { res = "sanMax",      amt = 2,  label = "🧠理智上限+2" },
            { res = "healthMax",   amt = 2,  label = "❤️健康上限+2" },
        }
        local pick = rewards[math.random(#rewards)]
        -- 处理效果
        if pick.res == "sanMax" or pick.res == "healthMax" then
            local baseKey = (pick.res == "sanMax") and "san" or "health"
            local oldMax = resourceBar.getMax(baseKey)
            resourceBar.setMax(baseKey, oldMax + pick.amt)
            resourceBar.change(baseKey, pick.amt)
        else
            resourceBar.change(pick.res, pick.amt)
        end
        local tc = Theme.current
        local isRare = pick.res == "sanMax" or pick.res == "healthMax"
        local bannerIcon = isRare and "✨" or "📦"
        VFX.spawnBanner(bannerIcon .. " " .. pick.label,
            tc.highlight.r, tc.highlight.g, tc.highlight.b, 18, 1.0)
        card.darkType = "normal"
        card.darkName = "空走廊"
        card.darkIcon = "🌑"
        card.darkLabel = "暗巷"
        if CardTextures_ then
            Card.updateTexture(card, CardTextures_)
        end

    elseif darkType == "passage" then
        local targetLayer
        if currentLayer_ == 1 then
            targetLayer = 2
        elseif currentLayer_ == 2 then
            -- L2: 双通道, 判断去向
            local passageIdx = 0
            for r = 1, ROWS do
                for c = 1, COLS do
                    local cd = board.cards[r] and board.cards[r][c]
                    if cd and cd.darkType == "passage" then
                        passageIdx = passageIdx + 1
                        if r == row and c == col then
                            targetLayer = (passageIdx == 1) and 1 or 3
                        end
                    end
                end
            end
            if not targetLayer then targetLayer = 1 end
        elseif currentLayer_ == 3 then
            targetLayer = 2
        end

        if targetLayer and M.isLayerUnlocked(targetLayer) then
            -- 请求层间移动 (由 main.lua 驱动)
            if M.changeLayerCallback then
                M.changeLayerCallback(targetLayer, dayCount)
            end
        else
            VFX.spawnBanner("🔒 目标层未解锁", 180, 80, 80, 16, 0.8)
        end

    elseif darkType == "abyss_core" then
        local tc = Theme.current
        VFX.spawnBanner("💀 你来到了最深处……", tc.danger.r, tc.danger.g, tc.danger.b, 20, 1.5)
        VFX.triggerShake(4, 0.6, 10)
    end
end

--- 设置层间移动回调 (main.lua 注入)
---@type fun(targetLayer: number, dayCount: number)
M.changeLayerCallback = nil

--- 暗面世界中使用相机驱除幽灵
function M.handleCameraShot(board, token, inputX, inputY, resourceBar)
    if not active_ or darkState_ ~= "ready" then return false end
    local layer = layers_[currentLayer_]
    if not layer then return false end

    local card, row, col = Board.hitTest(board, camera_, inputX, inputY, physW_, physH_)
    if not card then return false end

    for i, ghost in ipairs(layer.ghosts) do
        if ghost.alive and ghost.row == row and ghost.col == col then
            ghost.alive = false
            VFX.flashScreen(180, 100, 255, 0.3, 150)
            VFX.spawnBanner("📷 驱除了小幽灵!", 180, 130, 255, 18, 0.8)
            VFX.spawnBurst(physW_ / 2, physH_ / 2, 8, 180, 130, 255)

            for _, gn in ipairs(ghostNodes_) do
                if gn.ghostIdx == i and gn.node then
                    local node = gn.node
                    local mat = gn.mat
                    Tween.to(gn, { fadeOut = 1 }, 0.5, {
                        tag = "darkghost",
                        onUpdate = function(self)
                            if mat then
                                mat:SetShaderParameter("MatDiffColor",
                                    Variant(Color(1, 1, 1, 1 - (self.fadeOut or 0))))
                            end
                        end,
                        onComplete = function()
                            if node then node:Remove() end
                        end,
                    })
                    break
                end
            end
            return true
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- 每帧更新 (幽灵浮动, NPC呼吸)
-- ---------------------------------------------------------------------------

function M.update(dt, gameTime)
    if not active_ then return end

    gameTime_ = gameTime  -- 同步给 Tween 回调使用

    if energyFlash_ > 0 then
        energyFlash_ = math.max(0, energyFlash_ - dt * 2)
    end

    -- 幽灵浮动 (使用 posX/posZ 作为基准, Tween 移动时也同步更新)
    for _, gn in ipairs(ghostNodes_) do
        if gn.node then
            local floatY = math.sin(gameTime * 2.5 + gn.floatPhase) * 0.04
            gn.node:SetPosition(Vector3(gn.posX, gn.baseY + floatY, gn.posZ))
        end
    end

    -- NPC 呼吸
    local layer = layers_[currentLayer_]
    if layer then
        for i, _ in ipairs(layer.npcs) do
            local nn = npcNodes_[i]
            if nn and nn.node then
                local breathe = 1.0 + math.sin(gameTime * 2.0) * 0.02
                nn.node:SetScale(Vector3(breathe, breathe, breathe))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- HUD 绘制
-- ---------------------------------------------------------------------------

function M.draw(vg, logicalW, logicalH, gameTime)
    if not active_ then return end

    local layer = layers_[currentLayer_]
    if not layer then return end

    local tc = Theme.current

    -- 暗角氛围 (单层居中径向渐变, 避免四角叠加产生过重蒙版)
    nvgSave(vg)
    local cx, cy = logicalW * 0.5, logicalH * 0.5
    local innerR = math.min(logicalW, logicalH) * 0.35
    local outerR = math.max(logicalW, logicalH) * 0.72
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logicalW, logicalH)
    local grad = nvgRadialGradient(vg, cx, cy, innerR, outerR,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(10, 5, 25, 50))
    nvgFillPaint(vg, grad)
    nvgFill(vg)
    nvgRestore(vg)

    -- 层级指示器 + 能量条 已整合到 ResourceBar 暗面模式, 此处不再绘制

    -- 退出按钮已整合到 ResourceBar 暗面模式面板

    -- NPC 对话提示
    if darkState_ == "ready" then
        for _, npc in ipairs(layer.npcs) do
            if npc.row == layer.playerRow and npc.col == layer.playerCol then
                local pulse = 0.7 + 0.3 * math.sin(gameTime * 2.5)
                nvgSave(vg)
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 11)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, Theme.rgbaA(tc.darkGlow, math.floor(200 * pulse)))
                nvgText(vg, logicalW / 2, logicalH - 40, "💬 " .. npc.name .. " - 点击对话")
                nvgRestore(vg)
                break
            end
        end
    end
end

-- hitTestExitButton 已迁移到 ResourceBar.hitTestDarkExit

function M.setReady()
    darkState_ = "ready"
end

function M.updateScreenParams(camera, pw, ph)
    camera_ = camera
    physW_ = pw
    physH_ = ph
end

return M
