-- ============================================================================
-- BoardDecor.lua - 卡桌都市装饰系统
-- 使用 BillboardSet 将插画贴图放置在棋盘周围，营造都市街角氛围
-- 包含桌面木纹贴图和远景背景板
-- ============================================================================

local M = {}

-- ---------------------------------------------------------------------------
-- 装饰定义表
-- 每个条目: { name, texture, x, z, w, h }
--   name:    节点名称
--   texture: 贴图路径 (相对 assets/)
--   x, z:    世界坐标 (Y=0 平面)
--   w, h:    Billboard 世界尺寸 (米)
-- ---------------------------------------------------------------------------

local DECOR_DEFS = {
    -- 屋顶装饰: 放在桌面边缘外围, 营造天台打牌的氛围
    -- 右后方 - 自动贩卖机 (384x512 → 比例 0.75:1)
    { name = "VendingMachine", texture = "image/自动贩卖机_20260426032218.png",
      x = 3.2, z = 2.8,  w = 0.9, h = 1.2 },
    -- 左后方 - 晾衣架 (384x514 → 比例 0.75:1)
    { name = "ClothesRack",   texture = "image/晾衣架正面_20260426042125.png",
      x = -3.0, z = 3.0, w = 1.0, h = 1.3 },
    -- 右侧偏前 - 长椅 (512x384 → 比例 1.33:1, 矮宽)
    { name = "Bench",         texture = "image/长椅_20260426032215.png",
      x = 3.5, z = -0.5,  w = 1.1, h = 0.8 },
    -- 左后方偏远 - 行道树 (384x512 → 比例 0.75:1, 稍大一些)
    { name = "RooftopTree",   texture = "image/行道树_20260426031426.png",
      x = -3.5, z = 3.5, w = 1.0, h = 1.4 },
}

-- 远景背景定义
local BACKDROP_TEX       = "image/都市天际线_20260426035953.png"
local BACKDROP_NIGHT_TEX = "image/edited_都市天际线_暗夜版_20260426105650.png"
local BACKDROP_W   = 20.0   -- 背景宽度 (米, 覆盖全视野)
local BACKDROP_H   = 8.0    -- 背景高度 (米)
local BACKDROP_Z   = 12.0   -- 背景 Z 位置 (最远层)
local BACKDROP_Y   = -2.0   -- 背景底边高度 (确保建筑剪影和天空都可见)

-- 桌面纹理 (屋顶地面)
local TABLE_TEX = "image/屋顶地面_20260426041833.png"

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------

local decorNodes_ = {}     -- 装饰 Billboard 节点
local backdropNode_ = nil  -- 远景背景节点 (白天)
local nightNode_ = nil     -- 远景背景节点 (暗夜, 叠加在白天之上)
local nightMat_ = nil      -- 暗夜背景材质 (控制 alpha 渐变)
local parentNode_ = nil    -- 根节点

-- ---------------------------------------------------------------------------
-- 创建单个装饰 Billboard
-- ---------------------------------------------------------------------------

local function createDecorBillboard(def, parent)
    local node = parent:CreateChild(def.name)
    node:SetPosition(Vector3(def.x, 0, def.z))

    local bbSet = node:CreateComponent("BillboardSet")
    bbSet:SetNumBillboards(1)
    bbSet:SetFaceCameraMode(FC_ROTATE_Y)  -- 绕 Y 轴旋转面向相机
    bbSet:SetSorted(true)

    -- 材质: 透明 Diffuse
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))

    local tex = cache:GetResource("Texture2D", def.texture)
    if tex then
        mat:SetTexture(TU_DIFFUSE, tex)
    else
        print("[BoardDecor] WARNING: texture not found: " .. def.texture)
    end
    bbSet:SetMaterial(mat)

    -- Billboard (底部锚点: Y 偏移半高)
    local bb = bbSet:GetBillboard(0)
    bb.position = Vector3(0, def.h / 2, 0)
    bb.size = Vector2(def.w, def.h)
    bb.color = Color(1, 1, 1, 1)
    bb.enabled = true
    bbSet:Commit()

    return node
end

-- ---------------------------------------------------------------------------
-- 创建远景背景板 (使用 BillboardSet, 绕 Y 轴面向相机)
-- ---------------------------------------------------------------------------

local function createBackdrop(parent)
    local node = parent:CreateChild("Backdrop")
    node:SetPosition(Vector3(0, 0, BACKDROP_Z))

    local bbSet = node:CreateComponent("BillboardSet")
    bbSet:SetNumBillboards(1)
    bbSet:SetFaceCameraMode(FC_ROTATE_Y)
    bbSet:SetSorted(true)

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    local tex = cache:GetResource("Texture2D", BACKDROP_TEX)
    if tex then
        mat:SetTexture(TU_DIFFUSE, tex)
    else
        print("[BoardDecor] WARNING: backdrop texture not found")
    end
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.2, 1.2, 1.2, 1.0)))
    bbSet:SetMaterial(mat)

    -- Billboard 底部锚点: 中心向上偏移半高
    local bb = bbSet:GetBillboard(0)
    bb.position = Vector3(0, BACKDROP_Y + BACKDROP_H / 2, 0)
    bb.size = Vector2(BACKDROP_W, BACKDROP_H)
    bb.color = Color(1, 1, 1, 1)
    bb.enabled = true
    bbSet:Commit()

    return node
end

-- ---------------------------------------------------------------------------
-- 创建暗夜背景板 (叠加在白天之上, alpha 由外部控制)
-- ---------------------------------------------------------------------------

local function createNightBackdrop(parent)
    local node = parent:CreateChild("BackdropNight")
    node:SetPosition(Vector3(0, 0, BACKDROP_Z - 0.05))  -- 略靠前, 避免 Z-fighting

    local bbSet = node:CreateComponent("BillboardSet")
    bbSet:SetNumBillboards(1)
    bbSet:SetFaceCameraMode(FC_ROTATE_Y)
    bbSet:SetSorted(true)

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    local tex = cache:GetResource("Texture2D", BACKDROP_NIGHT_TEX)
    if tex then
        mat:SetTexture(TU_DIFFUSE, tex)
    else
        print("[BoardDecor] WARNING: night backdrop texture not found")
    end
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 0)))  -- 初始全透明
    bbSet:SetMaterial(mat)

    local bb = bbSet:GetBillboard(0)
    bb.position = Vector3(0, BACKDROP_Y + BACKDROP_H / 2, 0)
    bb.size = Vector2(BACKDROP_W, BACKDROP_H)
    bb.color = Color(1, 1, 1, 1)
    bb.enabled = true
    bbSet:Commit()

    nightMat_ = mat
    return node
end

-- ---------------------------------------------------------------------------
-- 公开 API
-- ---------------------------------------------------------------------------

--- 初始化所有装饰节点
---@param scene userdata Scene 节点
---@param tableModel userdata 桌面 StaticModel (可选, 用于替换桌面纹理)
function M.init(scene, tableModel)
    parentNode_ = scene:CreateChild("BoardDecor")
    decorNodes_ = {}

    -- 装饰 Billboard
    for i, def in ipairs(DECOR_DEFS) do
        local node = createDecorBillboard(def, parentNode_)
        decorNodes_[i] = node
    end

    -- 远景背景板 (白天 + 暗夜叠加)
    backdropNode_ = createBackdrop(parentNode_)
    nightNode_ = createNightBackdrop(parentNode_)

    -- 替换桌面纹理 (深色游戏桌垫)
    if tableModel then
        local tableTex = cache:GetResource("Texture2D", TABLE_TEX)
        if tableTex then
            local mat = Material:new()
            mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/Diff.xml"))
            mat:SetTexture(TU_DIFFUSE, tableTex)
            tableModel:SetMaterial(mat)
            print("[BoardDecor] Applied table mat texture")
        end
    end

    print(string.format("[BoardDecor] Created %d decorations + backdrop", #decorNodes_))
end

--- 更新暗夜渐变 (每帧调用, t: 0=白天, 1=暗夜)
---@param t number 过渡进度 0~1
function M.updateNight(t)
    if nightMat_ then
        nightMat_:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, t)))
    end
end

--- 销毁所有装饰节点
function M.destroy()
    if parentNode_ then
        parentNode_:Remove()
        parentNode_ = nil
    end
    decorNodes_ = {}
    backdropNode_ = nil
    nightNode_ = nil
    nightMat_ = nil
end

return M
