-- ============================================================================
-- DarkCoins.lua - 暗面世界 3D 浮空暗币 (类比 BoardItems 的道具 Billboard)
-- 在暗面卡牌 darkDot=true 的格子上放置紫色浮空硬币，玩家踩到自动拾取
-- ============================================================================

local Tween        = require "lib.Tween"
local VFX          = require "lib.VFX"
local AudioManager = require "AudioManager"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
local COIN_SIZE       = 0.16        -- 硬币图标尺寸(米)
local COIN_BASE_Y     = 0.30        -- 浮空基础高度
local FLOAT_SPEED     = 2.2         -- 上下浮动速度
local FLOAT_AMP       = 0.04        -- 浮动幅度
local CAMERA_OFFSET_Z = -0.18       -- 向相机方向偏移
local CRYSTAL_TEX     = "image/dark_coin_crystal_v3_20260519122446.png"

-- ---------------------------------------------------------------------------
-- 模块状态
-- ---------------------------------------------------------------------------
---@type Node|nil
local parentNode_ = nil
---@type table[]
local coins_ = {}
---@type userdata|nil  Texture2D 硬币纹理 (只加载一次)
local coinTex_ = nil

-- ---------------------------------------------------------------------------
-- 加载水晶贴图 (只调用一次)
-- ---------------------------------------------------------------------------
local function buildCoinTexture()
    if coinTex_ then return coinTex_ end
    coinTex_ = cache:GetResource("Texture2D", CRYSTAL_TEX)
    if coinTex_ then
        print("[DarkCoins] Crystal texture loaded: " .. CRYSTAL_TEX)
    else
        print("[DarkCoins] WARNING: failed to load crystal texture: " .. CRYSTAL_TEX)
    end
    return coinTex_
end

-- ---------------------------------------------------------------------------
-- 创建单个硬币 Billboard
-- ---------------------------------------------------------------------------
local function createCoinBillboard(worldX, worldZ, phase)
    local tex = buildCoinTexture()
    if not tex then
        print("[DarkCoins] WARNING: no coin texture")
        return nil
    end

    local node = parentNode_:CreateChild("DarkCoin")
    node:SetPosition(Vector3(worldX, 0, worldZ + CAMERA_OFFSET_Z))

    local bbSet = node:CreateComponent("BillboardSet")
    bbSet:SetNumBillboards(1)
    bbSet:SetFaceCameraMode(FC_ROTATE_Y)
    bbSet:SetSorted(true)

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    mat:SetTexture(TU_DIFFUSE, tex)
    bbSet:SetMaterial(mat)

    local bb = bbSet:GetBillboard(0)
    bb.position = Vector3(0, COIN_BASE_Y, 0)
    bb.size = Vector2(0.001, 0.001)
    bb.color = Color(1, 1, 1, 0)
    bb.enabled = true
    bbSet:Commit()

    return {
        node  = node,
        bbSet = bbSet,
        bb    = bb,
        phase = phase,
        scale = 0,
        alpha = 0,
    }
end

-- ---------------------------------------------------------------------------
-- 公开 API
-- ---------------------------------------------------------------------------

--- 初始化 (在 scene 创建后调用)
---@param scene userdata Scene
function M.init(scene)
    parentNode_ = scene:CreateChild("DarkCoins")
    coinTex_ = nil
    print("[DarkCoins] Initialized")
end

--- 清除所有硬币节点
function M.clear()
    for _, coin in ipairs(coins_) do
        if coin.node then coin.node:Remove() end
    end
    coins_ = {}
end

--- 根据暗面棋盘生成 Billboard (在 generateDarkCards 之后调用)
---@param board table  Board 数据
---@param Board table  Board 模块 (用于 cardPos/ROWS/COLS)
function M.spawnFromBoard(board, Board)
    M.clear()
    if not parentNode_ then
        print("[DarkCoins] ERROR: not initialized")
        return
    end

    local count = 0
    for r = 1, Board.ROWS do
        for c = 1, Board.COLS do
            local card = board.cards[r] and board.cards[r][c]
            if card and card.darkDot then
                local wx, wz = Board.cardPos(board, r, c)
                local phase = math.random() * math.pi * 2
                local sprite = createCoinBillboard(wx, wz, phase)
                if sprite then
                    local coin = {
                        row       = r,
                        col       = c,
                        collected = false,
                        node      = sprite.node,
                        bbSet     = sprite.bbSet,
                        bb        = sprite.bb,
                        phase     = sprite.phase,
                        scale     = sprite.scale,
                        alpha     = sprite.alpha,
                    }
                    coins_[#coins_ + 1] = coin

                    -- 弹出动画 (交错延迟)
                    Tween.to(coin, { scale = 1.0, alpha = 1.0 }, 0.35, {
                        easing = Tween.Easing.easeOutBack,
                        delay  = 0.2 + (count % 8) * 0.06,
                        tag    = "darkcoin_spawn",
                    })
                    count = count + 1
                end
            end
        end
    end
    print(string.format("[DarkCoins] Spawned %d coins", count))
end

--- 玩家到达格子时尝试拾取暗币
---@param row number
---@param col number
---@param physW number 屏幕宽度 (用于 VFX)
---@param physH number 屏幕高度 (用于 VFX)
---@param resourceBar table ResourceBar 模块
---@return boolean collected 是否拾取到
function M.tryCollect(row, col, physW, physH, resourceBar)
    for _, coin in ipairs(coins_) do
        if not coin.collected and coin.row == row and coin.col == col then
            coin.collected = true

            -- 拾取动效: 上浮 + 钟形缩放 + 淡出
            local collectAnim = { t = 0 }
            local startY      = coin.bb.position.y
            local startScale  = coin.scale

            Tween.to(collectAnim, { t = 1 }, 0.4, {
                easing   = Tween.Easing.easeOutCubic,
                tag      = "darkcoin_collect",
                onUpdate = function(_, progress)
                    coin.bb.position = Vector3(0, startY + progress * 0.22, 0)
                    local bell = 1.0 + math.sin(progress * math.pi) * 0.25
                    coin.scale = startScale * bell * (1.0 - progress * 0.6)
                    if progress > 0.45 then
                        coin.alpha = 1.0 - (progress - 0.45) / 0.55
                    end
                end,
                onComplete = function()
                    if coin.node then coin.node:Remove(); coin.node = nil end
                    for i = #coins_, 1, -1 do
                        if coins_[i] == coin then
                            table.remove(coins_, i)
                            break
                        end
                    end
                end,
            })

            -- 音效
            AudioManager.playSFX("item_pickup")

            -- VFX
            VFX.spawnBurst(physW / 2, physH / 2, 5, 200, 130, 255)
            VFX.flashScreen(160, 80, 255, 0.06, 50)

            -- 资源
            resourceBar.change("darkcoin", 1)
            return true
        end
    end
    return false
end

--- 每帧更新: 浮动动画
---@param dt number
---@param gameTime number
function M.update(dt, gameTime)
    for _, coin in ipairs(coins_) do
        if coin.bb then
            local floatY = math.sin(gameTime * FLOAT_SPEED + coin.phase) * FLOAT_AMP
            local s = coin.scale * COIN_SIZE
            coin.bb.position = Vector3(0, COIN_BASE_Y + floatY, 0)
            coin.bb.size     = Vector2(s, s)
            coin.bb.color    = Color(1, 1, 1, math.max(0, coin.alpha))
            coin.bbSet:Commit()
        end
    end
end

--- 销毁模块 (场景切换时)
function M.destroy()
    M.clear()
    parentNode_ = nil
    coinTex_    = nil
end

return M
