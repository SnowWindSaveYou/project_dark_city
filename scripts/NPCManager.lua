-- ============================================================================
-- NPCManager.lua - NPC 管理模块
-- 3D BillboardSet chibi 精灵，同格偏移，点击交互
-- ============================================================================

local Tween = require "lib.Tween"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
local SPRITE_3D_H = 0.50                         -- 与 Token 一致
local SPRITE_3D_W = SPRITE_3D_H * (515 / 768)    -- ≈ 0.335m

-- 同格偏移 (Token 左移, NPC 右移)
local SHARE_OFFSET = 0.18

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------
---@type userdata
local scene_ = nil
---@type userdata
local parentNode_ = nil

---@class NPCData
---@field id string
---@field name string
---@field row number
---@field col number
---@field texPath string
---@field dialogueScript table
---@field node3d userdata
---@field bbSet userdata
---@field billboard userdata
---@field material3d userdata
---@field shadowNode userdata
---@field alpha number
---@field scale number
---@field breathePhase number
---@field worldX number
---@field worldZ number

local npcs_ = {}  -- id → NPCData

-- Board 引用 (由 main 注入)
local boardRef_ = nil
local BoardModule_ = nil

-- ---------------------------------------------------------------------------
-- 公开 API
-- ---------------------------------------------------------------------------

--- 初始化
---@param scene userdata
function M.init(scene)
    scene_ = scene
    parentNode_ = scene:CreateChild("NPCs")
    npcs_ = {}
end

--- 注入 Board 引用 (用于坐标计算)
function M.setBoard(board, BoardModule)
    boardRef_ = board
    BoardModule_ = BoardModule
end

--- 放置 NPC
---@param id string 唯一标识
---@param name string 显示名
---@param row number 棋盘行
---@param col number 棋盘列
---@param texPath string 贴图资源路径
---@param dialogueScript table 对话脚本
function M.spawnNPC(id, name, row, col, texPath, dialogueScript)
    if npcs_[id] then
        M.removeNPC(id)
    end
    if not parentNode_ or not BoardModule_ or not boardRef_ then
        print("[NPCManager] ERROR: not initialized or board not set")
        return
    end

    local wx, wz = BoardModule_.cardPos(boardRef_, row, col)

    local node = parentNode_:CreateChild("NPC_" .. id)

    local bbSet = node:CreateComponent("BillboardSet")
    bbSet:SetNumBillboards(1)
    bbSet:SetFaceCameraMode(FC_ROTATE_Y)
    bbSet:SetSorted(true)

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    local tex = cache:GetResource("Texture2D", texPath)
    if tex then
        mat:SetTexture(TU_DIFFUSE, tex)
    else
        print("[NPCManager] WARNING: texture not found: " .. texPath)
    end
    bbSet:SetMaterial(mat)

    local bb = bbSet:GetBillboard(0)
    bb.position = Vector3(0, SPRITE_3D_H / 2, 0)
    bb.size = Vector2(0.001, 0.001)  -- 初始极小 → 弹出动画
    bb.color = Color(1, 1, 1, 0)
    bb.enabled = true
    bbSet:Commit()

    -- Blob shadow
    local shadowNode = parentNode_:CreateChild("NPCShadow_" .. id)
    shadowNode:SetPosition(Vector3(wx + SHARE_OFFSET, 0.015, wz))
    shadowNode:SetScale(Vector3(SPRITE_3D_W * 1.0, 0.001, SPRITE_3D_W * 0.45))
    local shadowModel = shadowNode:CreateComponent("StaticModel")
    shadowModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    local shadowMat = Material:new()
    shadowMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    shadowMat:SetShaderParameter("MatDiffColor", Variant(Color(0, 0, 0, 0.25)))
    shadowMat:SetShaderParameter("MatRoughness", Variant(1.0))
    shadowMat:SetShaderParameter("MatMetallic", Variant(0.0))
    shadowModel:SetMaterial(shadowMat)

    ---@type NPCData
    local npc = {
        id = id,
        name = name,
        row = row,
        col = col,
        texPath = texPath,
        dialogueScript = dialogueScript,
        node3d = node,
        bbSet = bbSet,
        billboard = bb,
        material3d = mat,
        shadowNode = shadowNode,
        alpha = 0,
        scale = 0,
        breathePhase = math.random() * 6.28,
        worldX = wx + SHARE_OFFSET,
        worldZ = wz,
    }

    npcs_[id] = npc

    -- 弹出动画
    Tween.to(npc, { scale = 1.0, alpha = 1.0 }, 0.4, {
        easing = Tween.Easing.easeOutBack,
        delay = 0.3,
        tag = "npc_spawn",
    })

    print(string.format("[NPCManager] Spawned NPC '%s' at (%d,%d) pos=(%.2f,%.2f)",
        name, row, col, npc.worldX, npc.worldZ))
end

--- 移除指定 NPC
function M.removeNPC(id)
    local npc = npcs_[id]
    if not npc then return end

    Tween.cancelTarget(npc)
    if npc.shadowNode then npc.shadowNode:Remove() end
    if npc.node3d then npc.node3d:Remove() end
    npcs_[id] = nil
end

--- 清除全部 NPC
function M.clear()
    for id, npc in pairs(npcs_) do
        Tween.cancelTarget(npc)
        if npc.shadowNode then npc.shadowNode:Remove() end
        if npc.node3d then npc.node3d:Remove() end
    end
    npcs_ = {}
end

--- 查询指定格子的 NPC
---@param row number
---@param col number
---@return NPCData|nil
function M.getNPCAt(row, col)
    for _, npc in pairs(npcs_) do
        if npc.row == row and npc.col == col then
            return npc
        end
    end
    return nil
end

--- 获取 Token 的同格偏移量 (负值=左移)
--- 如果该格有 NPC 则返回 -SHARE_OFFSET，否则返回 0
---@param row number
---@param col number
---@return number dx Token 应叠加的 X 偏移
function M.getShareOffset(row, col)
    if M.getNPCAt(row, col) then
        return -SHARE_OFFSET
    end
    return 0
end

--- 每帧更新: 呼吸浮动 + 节点同步
---@param dt number
---@param gameTime number
function M.update(dt, gameTime)
    for _, npc in pairs(npcs_) do
        if not npc.node3d then goto continue end

        local bb = npc.billboard
        if not bb then goto continue end

        if npc.alpha <= 0.01 then
            bb.enabled = false
            npc.bbSet:Commit()
            goto continue
        end

        -- 呼吸动画
        local breatheY = math.sin(gameTime * 2.2 + npc.breathePhase) * 0.008
        local breatheScale = 1.0 + math.sin(gameTime * 2.2 + npc.breathePhase) * 0.015

        -- 节点位置 (含偏移)
        npc.node3d:SetPosition(Vector3(npc.worldX, 0.25 + breatheY, npc.worldZ))

        -- Billboard 尺寸
        local s = npc.scale * breatheScale
        local actualH = SPRITE_3D_H * s
        bb.position = Vector3(0, actualH / 2, 0)
        bb.size = Vector2(SPRITE_3D_W * s, actualH)
        bb.color = Color(1, 1, 1, npc.alpha)
        bb.enabled = true
        npc.bbSet:Commit()

        -- 阴影
        if npc.shadowNode then
            npc.shadowNode:SetPosition(Vector3(npc.worldX, 0.015, npc.worldZ))
        end

        ::continue::
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

return M
