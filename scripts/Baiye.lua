-- ============================================================================
-- Baiye.lua - 白夜跟随精灵 (3D Billboard)
-- 半透明灵体同伴，以飘浮姿态跟随玩家棋子
-- ============================================================================

local Tween = require "lib.Tween"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------

-- 3D 精灵尺寸 (比 Token 略小)
local SPRITE_3D_H = 0.20
local SPRITE_3D_W = SPRITE_3D_H * (515 / 768)  -- 保持宽高比

-- 跟随偏移 (相对 Token 的世界坐标)
local OFFSET_X = -0.20   -- 左侧
local OFFSET_Z =  0.14   -- 稍后方 (远离相机)

-- 跟随平滑速度 (越大越紧, 越小越飘)
local FOLLOW_SPEED = 4.0

-- 悬浮基础高度 (比 Token 稍高, 灵体漂浮感)
local BASE_Y = 0.30

-- 灵体透明度
local SPIRIT_ALPHA = 0.50

-- 纹理路径
local TEXTURE_PATH = "image/白夜_chibi_20260506003802.png"

-- ---------------------------------------------------------------------------
-- 构造
-- ---------------------------------------------------------------------------

function M.new()
    return {
        worldX   = 0,
        worldZ   = 0,
        targetX  = 0,
        targetZ  = 0,
        bounceY  = 0,
        alpha    = 0,
        scaleX   = 1.0,
        scaleY   = 1.0,
        visible  = false,

        -- 3D 节点
        node3d       = nil, ---@type Node
        billboardSet = nil, ---@type BillboardSet
        billboard    = nil,
        material3d   = nil, ---@type Material
        texture      = nil, ---@type Texture2D
        shadowNode   = nil, ---@type Node
    }
end

-- ---------------------------------------------------------------------------
-- 纹理加载
-- ---------------------------------------------------------------------------

---@return Texture2D|nil
function M.loadTexture()
    local tex = cache:GetResource("Texture2D", TEXTURE_PATH)
    if tex then
        print("[Baiye] Loaded texture: " .. TEXTURE_PATH)
    else
        print("[Baiye] ERROR: Failed to load texture " .. TEXTURE_PATH)
    end
    return tex
end

-- ---------------------------------------------------------------------------
-- 3D 节点: 创建
-- ---------------------------------------------------------------------------

---@param baiye table
---@param parentNode Node
function M.createNode(baiye, parentNode)
    if baiye.node3d then return end

    local node = parentNode:CreateChild("Baiye")

    -- BillboardSet (面向相机)
    local bbSet = node:CreateComponent("BillboardSet")
    bbSet:SetNumBillboards(1)
    bbSet:SetFaceCameraMode(FC_ROTATE_Y)
    bbSet:SetSorted(true)

    -- 材质: 透明 Diffuse
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    if baiye.texture then
        mat:SetTexture(TU_DIFFUSE, baiye.texture)
    end
    bbSet:SetMaterial(mat)

    -- 单个 Billboard (锚点底部)
    local bb = bbSet:GetBillboard(0)
    bb.position = Vector3(0, SPRITE_3D_H / 2, 0)
    bb.size = Vector2(SPRITE_3D_W, SPRITE_3D_H)
    bb.color = Color(1, 1, 1, 0)
    bb.enabled = false
    bbSet:Commit()

    -- Blob shadow (比 Token 更淡更小)
    local shadowNode = parentNode:CreateChild("BaiyeShadow")
    shadowNode:SetPosition(Vector3(0, 0.014, 0))
    shadowNode:SetScale(Vector3(SPRITE_3D_W * 0.7, 0.001, SPRITE_3D_W * 0.35))
    local shadowModel = shadowNode:CreateComponent("StaticModel")
    shadowModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    local shadowMat = Material:new()
    shadowMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    shadowMat:SetShaderParameter("MatDiffColor", Variant(Color(0, 0, 0, 0.12)))
    shadowMat:SetShaderParameter("MatRoughness", Variant(1.0))
    shadowMat:SetShaderParameter("MatMetallic", Variant(0.0))
    shadowModel:SetMaterial(shadowMat)

    baiye.node3d       = node
    baiye.billboardSet = bbSet
    baiye.billboard    = bb
    baiye.material3d   = mat
    baiye.shadowNode   = shadowNode

    print("[Baiye] Created 3D billboard node")
end

-- ---------------------------------------------------------------------------
-- 3D 节点: 销毁
-- ---------------------------------------------------------------------------

function M.destroyNode(baiye)
    if baiye.shadowNode then
        baiye.shadowNode:Remove()
        baiye.shadowNode = nil
    end
    if baiye.node3d then
        baiye.node3d:Remove()
        baiye.node3d = nil
        baiye.billboardSet = nil
        baiye.billboard    = nil
        baiye.material3d   = nil
    end
end

-- ---------------------------------------------------------------------------
-- 显示 (Token 出现时调用)
-- ---------------------------------------------------------------------------

---@param baiye table
---@param tokenWorldX number Token 的世界 X
---@param tokenWorldZ number Token 的世界 Z
function M.show(baiye, tokenWorldX, tokenWorldZ)
    -- 直接定位到 Token 旁边 (无延迟跟随)
    baiye.worldX  = tokenWorldX + OFFSET_X
    baiye.worldZ  = tokenWorldZ + OFFSET_Z
    baiye.targetX = baiye.worldX
    baiye.targetZ = baiye.worldZ
    baiye.visible = true

    -- 入场: 从小+透明 → 正常大小+半透明, 带回弹
    baiye.scaleX  = 0.3
    baiye.scaleY  = 0.3
    baiye.alpha   = 0
    baiye.bounceY = 0.15

    Tween.cancelTag("baiye")
    Tween.to(baiye, {
        alpha  = SPIRIT_ALPHA,
        scaleX = 1.0,
        scaleY = 1.0,
        bounceY = 0,
    }, 0.5, {
        delay  = 0.25,  -- Token 落地后再出现
        easing = Tween.Easing.easeOutBack,
        tag    = "baiye",
    })
end

-- ---------------------------------------------------------------------------
-- 隐藏 (暗面进入 / 沉睡 等场景)
-- ---------------------------------------------------------------------------

function M.hide(baiye)
    Tween.cancelTag("baiye")
    Tween.to(baiye, {
        alpha  = 0,
        scaleX = 0.3,
        scaleY = 0.3,
    }, 0.3, {
        easing = Tween.Easing.easeInBack,
        tag    = "baiye",
        onComplete = function()
            baiye.visible = false
        end,
    })
end

-- ---------------------------------------------------------------------------
-- 每帧更新: 平滑跟随 Token
-- ---------------------------------------------------------------------------

---@param baiye table
---@param dt number
---@param tokenWorldX number Token 当前世界 X
---@param tokenWorldZ number Token 当前世界 Z
function M.update(baiye, dt, tokenWorldX, tokenWorldZ)
    if not baiye.visible then return end

    baiye.targetX = tokenWorldX + OFFSET_X
    baiye.targetZ = tokenWorldZ + OFFSET_Z

    -- 平滑跟随 (指数衰减, 产生飘浮拖尾感)
    baiye.worldX = Tween.damp(baiye.worldX, baiye.targetX, FOLLOW_SPEED, dt)
    baiye.worldZ = Tween.damp(baiye.worldZ, baiye.targetZ, FOLLOW_SPEED, dt)
end

-- ---------------------------------------------------------------------------
-- 每帧同步: Lua 属性 → 3D Node Transform
-- ---------------------------------------------------------------------------

---@param baiye table
---@param gameTime number
function M.syncNode(baiye, gameTime)
    if not baiye.node3d then return end

    local bb = baiye.billboard
    if not bb then return end

    if not baiye.visible or baiye.alpha <= 0.01 then
        bb.enabled = false
        baiye.billboardSet:Commit()
        if baiye.shadowNode then
            baiye.shadowNode:SetEnabled(false)
        end
        return
    end

    -- 灵体飘浮动画 (比 Token 幅度大、频率慢, 营造悬空感)
    local floatY = math.sin(gameTime * 1.8) * 0.018
    local floatX = math.sin(gameTime * 1.1 + 0.7) * 0.010
    local breatheScale = 1.0 + math.sin(gameTime * 1.8) * 0.035

    -- 节点位置
    baiye.node3d:SetPosition(Vector3(
        baiye.worldX + floatX,
        BASE_Y + baiye.bounceY + floatY,
        baiye.worldZ
    ))

    -- Billboard 尺寸
    local actualH = SPRITE_3D_H * baiye.scaleY * breatheScale
    bb.position = Vector3(0, actualH / 2, 0)
    bb.size = Vector2(
        SPRITE_3D_W * baiye.scaleX * breatheScale,
        SPRITE_3D_H * baiye.scaleY * breatheScale
    )
    bb.color = Color(1, 1, 1, baiye.alpha)
    bb.enabled = true
    baiye.billboardSet:Commit()

    -- 阴影
    if baiye.shadowNode then
        baiye.shadowNode:SetEnabled(true)
        baiye.shadowNode:SetPosition(Vector3(baiye.worldX, 0.014, baiye.worldZ))
        -- 飘浮越高阴影越淡
        local shadowAlpha = math.max(0.05, 0.12 - (floatY + baiye.bounceY) * 0.3)
        local sm = baiye.shadowNode:GetComponent("StaticModel")
        if sm then
            local smat = sm:GetMaterial(0)
            if smat then
                smat:SetShaderParameter("MatDiffColor", Variant(Color(0, 0, 0, shadowAlpha)))
            end
        end
    end
end

return M
