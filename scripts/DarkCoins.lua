-- ============================================================================
-- DarkCoins.lua - 暗面世界 3D 浮空暗币 (类比 BoardItems 的道具 Billboard)
-- 在暗面卡牌 darkDot=true 的格子上放置紫色浮空硬币，玩家踩到自动拾取
-- ============================================================================

local Tween = require "lib.Tween"
local VFX   = require "lib.VFX"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
local COIN_SIZE       = 0.16        -- 硬币图标尺寸(米)
local COIN_BASE_Y     = 0.30        -- 浮空基础高度
local FLOAT_SPEED     = 2.2         -- 上下浮动速度
local FLOAT_AMP       = 0.04        -- 浮动幅度
local CAMERA_OFFSET_Z = -0.18       -- 向相机方向偏移
local TEX_SIZE        = 64          -- NanoVG 烘焙纹理尺寸

-- ---------------------------------------------------------------------------
-- 模块状态
-- ---------------------------------------------------------------------------
---@type Node|nil
local parentNode_ = nil
---@type table[]
local coins_ = {}
---@type userdata|nil  NanoVG context (由 init 注入)
local vg_ = nil
---@type userdata|nil  Texture2D 硬币纹理 (只创建一次)
local coinTex_ = nil

-- ---------------------------------------------------------------------------
-- 创建暗币 NanoVG 纹理 (只调用一次)
-- ---------------------------------------------------------------------------
local function buildCoinTexture()
    if coinTex_ then return coinTex_ end
    if not vg_ then return nil end

    local tex = Texture2D:new()
    tex:SetNumLevels(1)
    tex:SetSize(TEX_SIZE, TEX_SIZE, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    tex:SetFilterMode(FILTER_BILINEAR)

    local w, h = TEX_SIZE, TEX_SIZE

    nvgSetRenderTarget(vg_, tex)
    nvgBeginFrame(vg_, w, h, 1.0)
    -- render-target Y轴翻转
    nvgTranslate(vg_, 0, h)
    nvgScale(vg_, 1, -1)

    -- 清透明背景
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, w, h)
    nvgFillColor(vg_, nvgRGBA(0, 0, 0, 0))
    nvgFill(vg_)

    local cx, cy, r = w * 0.5, h * 0.5, w * 0.38

    -- 外发光晕
    local glow = nvgRadialGradient(vg_, cx, cy, r * 0.5, r * 1.6,
        nvgRGBA(180, 80, 255, 100), nvgRGBA(100, 40, 200, 0))
    nvgBeginPath(vg_)
    nvgCircle(vg_, cx, cy, r * 1.6)
    nvgFillPaint(vg_, glow)
    nvgFill(vg_)

    -- 硬币主体 (深紫渐变)
    local bodyGrad = nvgLinearGradient(vg_, cx - r, cy - r, cx + r, cy + r,
        nvgRGBA(200, 100, 255, 240), nvgRGBA(100, 30, 180, 240))
    nvgBeginPath(vg_)
    nvgCircle(vg_, cx, cy, r)
    nvgFillPaint(vg_, bodyGrad)
    nvgFill(vg_)

    -- 内圈暗边
    nvgBeginPath(vg_)
    nvgCircle(vg_, cx, cy, r)
    nvgStrokeColor(vg_, nvgRGBA(60, 0, 120, 180))
    nvgStrokeWidth(vg_, 2.5)
    nvgStroke(vg_)

    -- 币面符文 "⚫" 用 ¥ 替代为暗界符号 (简单十字)
    local sr = r * 0.38
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, cx, cy - sr)
    nvgLineTo(vg_, cx, cy + sr)
    nvgMoveTo(vg_, cx - sr, cy)
    nvgLineTo(vg_, cx + sr, cy)
    nvgStrokeColor(vg_, nvgRGBA(230, 180, 255, 200))
    nvgStrokeWidth(vg_, 3.0)
    nvgStroke(vg_)

    -- 高光弧
    local hlGrad = nvgLinearGradient(vg_, cx - r * 0.5, cy - r * 0.8,
        cx + r * 0.2, cy - r * 0.1,
        nvgRGBA(255, 220, 255, 160), nvgRGBA(255, 200, 255, 0))
    nvgBeginPath(vg_)
    nvgEllipse(vg_, cx - r * 0.12, cy - r * 0.3, r * 0.42, r * 0.22)
    nvgFillPaint(vg_, hlGrad)
    nvgFill(vg_)

    nvgEndFrame(vg_)
    nvgSetRenderTarget(vg_, nil)

    coinTex_ = tex
    print("[DarkCoins] Coin texture built (" .. TEX_SIZE .. "x" .. TEX_SIZE .. ")")
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

--- 初始化 (在 scene 创建后、NanoVG 就绪后调用)
---@param scene userdata Scene
---@param vg userdata NanoVG context
function M.init(scene, vg)
    parentNode_ = scene:CreateChild("DarkCoins")
    vg_ = vg
    coinTex_ = nil   -- 下次 spawn 时重建
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
