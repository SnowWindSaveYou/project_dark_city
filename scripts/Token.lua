-- ============================================================================
-- Token.lua - 玩家棋子 (3D Billboard 版)
-- 15 种表情贴图 + 呼吸/弹跳/挤压/翻面动效
-- 使用 BillboardSet 面向相机的 3D 精灵，站立在卡牌上
-- ============================================================================

local Tween = require "lib.Tween"
local Theme = require "Theme"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------

-- 3D 精灵尺寸 (米)
local SPRITE_3D_H = 0.50                         -- 站立高度
local SPRITE_3D_W = SPRITE_3D_H * (515 / 768)    -- 保持宽高比 ≈ 0.335m
local DEAD_3D_H   = 0.38                          -- 躺尸高度
local DEAD_3D_W   = DEAD_3D_H * (768 / 515)      -- 横版宽高比 ≈ 0.57m

-- 兼容旧引用
M.SIZE   = 20
M.BODY_H = 14

-- ---------------------------------------------------------------------------
-- 表情映射
-- ---------------------------------------------------------------------------
local EMOTIONS = {
    default    = "image/主角chibi恐怖风v5_20260425143954.png",
    happy      = "image/主角_开心_20260425144434.png",
    scared     = "image/主角_惊恐v3_20260425145053.png",
    surprised  = "image/主角_惊讶_20260425152052.png",
    nervous    = "image/主角_紧张_20260425152033.png",
    angry      = "image/主角_愤怒_20260425152036.png",
    determined = "image/主角_坚定_20260425152030.png",
    relieved   = "image/主角_释然_20260425152041.png",
    sleepy     = "image/主角_困倦_20260425152033.png",
    confused   = "image/主角_疑惑v5_20260425150409.png",
    sad        = "image/主角_伤心_20260425144628.png",
    dead       = "image/主角_躺尸_20260425154955.png",
    disgusted  = "image/主角_厌恶_20260425152036.png",
    dazed      = "image/主角_呆滞_20260425144455.png",
    running    = "image/主角_奔跑v3_20260425153021.png",
}

-- ---------------------------------------------------------------------------
-- 构造
-- ---------------------------------------------------------------------------

function M.new()
    return {
        -- 世界坐标 (主要定位)
        worldX = 0,
        worldZ = 0,
        bounceY = 0,      -- 高度偏移 (正值=向上)

        targetRow = 1,
        targetCol = 1,

        scaleX = 1.0,
        scaleY = 1.0,
        alpha = 0,
        squashX = 1.0,
        squashY = 1.0,
        isMoving = false,
        visible = false,
        idleTimer = 0,

        -- 表情系统
        emotion = "default",
        pendingEmotion = nil,

        -- 3D 节点
        node3d = nil,        ---@type userdata BillboardSet
        billboardSet = nil,  ---@type userdata Billboard
        billboard = nil,
        material3d = nil,
        textures = {},       -- emotion → Texture2D
    }
end

-- ---------------------------------------------------------------------------
-- 纹理加载 (Texture2D, 替代旧的 NanoVG loadImages)
-- ---------------------------------------------------------------------------

--- 一次性加载全部表情为 Texture2D (在 Start() 中调用)
---@return table textures  表情名 → Texture2D
function M.loadTextures()
    local textures = {}
    local loaded, failed = 0, 0
    local loaded_paths = {}

    for key, path in pairs(EMOTIONS) do
        -- 去重: 同路径共享 Texture2D
        if loaded_paths[path] then
            textures[key] = loaded_paths[path]
            loaded = loaded + 1
        else
            local tex = cache:GetResource("Texture2D", path)
            if tex then
                textures[key] = tex
                loaded_paths[path] = tex
                loaded = loaded + 1
            else
                print("[Token] ERROR: Failed to load texture " .. path)
                failed = failed + 1
            end
        end
    end
    print("[Token] Loaded " .. loaded .. " emotion textures, " .. failed .. " failed")
    return textures
end

-- ---------------------------------------------------------------------------
-- 3D 节点: 创建 (BillboardSet, 面向相机)
-- ---------------------------------------------------------------------------

--- 创建 Token 的 3D Billboard 节点
---@param token table
---@param parentNode userdata 父节点 (通常是 scene_)
function M.createNode(token, parentNode)
    if token.node3d then return end

    local node = parentNode:CreateChild("Token")

    local bbSet = node:CreateComponent("BillboardSet")
    bbSet:SetNumBillboards(1)
    bbSet:SetFaceCameraMode(FC_ROTATE_Y)  -- 绕 Y 轴旋转面向相机, 保持竖直
    bbSet:SetSorted(true)

    -- 材质: 透明 Diffuse
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    local defaultTex = token.textures and token.textures["default"]
    if defaultTex then
        mat:SetTexture(TU_DIFFUSE, defaultTex)
    end
    bbSet:SetMaterial(mat)

    -- 单个 Billboard (锚点在底部: 局部 Y 偏移半高, 使底边贴合节点原点)
    local bb = bbSet:GetBillboard(0)
    bb.position = Vector3(0, SPRITE_3D_H / 2, 0)
    bb.size = Vector2(SPRITE_3D_W, SPRITE_3D_H)
    bb.color = Color(1, 1, 1, 0)  -- 初始透明
    bb.enabled = false
    bbSet:Commit()

    -- Blob shadow (独立节点, 直接在 parentNode 下, 不跟随 bounceY)
    local shadowNode = parentNode:CreateChild("TokenShadow")
    shadowNode:SetPosition(Vector3(0, 0.015, 0))
    shadowNode:SetScale(Vector3(SPRITE_3D_W * 1.1, 0.001, SPRITE_3D_W * 0.5))
    local shadowModel = shadowNode:CreateComponent("StaticModel")
    shadowModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    local shadowMat = Material:new()
    shadowMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    shadowMat:SetShaderParameter("MatDiffColor", Variant(Color(0, 0, 0, 0.3)))
    shadowMat:SetShaderParameter("MatRoughness", Variant(1.0))
    shadowMat:SetShaderParameter("MatMetallic", Variant(0.0))
    shadowModel:SetMaterial(shadowMat)

    token.node3d = node
    token.billboardSet = bbSet
    token.billboard = bb
    token.material3d = mat
    token.shadowNode = shadowNode

    print("[Token] Created 3D billboard node")
end

-- ---------------------------------------------------------------------------
-- 3D 节点: 销毁
-- ---------------------------------------------------------------------------

function M.destroyNode(token)
    if token.shadowNode then
        token.shadowNode:Remove()
        token.shadowNode = nil
    end
    if token.node3d then
        token.node3d:Remove()
        token.node3d = nil
        token.billboardSet = nil
        token.billboard = nil
        token.material3d = nil
    end
end

-- ---------------------------------------------------------------------------
-- 3D 节点: 每帧同步 Lua 属性 → Node Transform
-- ---------------------------------------------------------------------------

--- 每帧调用: 将 token 的 Lua 属性映射到 3D Billboard
---@param token table
---@param gameTime number 游戏总时间 (用于呼吸动画)
function M.syncNode(token, gameTime)
    if not token.node3d then return end

    local bb = token.billboard
    if not bb then return end

    if not token.visible or token.alpha <= 0.01 then
        bb.enabled = false
        token.billboardSet:Commit()
        return
    end

    -- 呼吸动画 (非移动时微弱上下浮动 + 缩放)
    local breatheY = 0
    local breatheScale = 1.0
    if not token.isMoving and gameTime then
        breatheY = math.sin(gameTime * 2.5) * 0.008
        breatheScale = 1.0 + math.sin(gameTime * 2.5) * 0.02
    end

    -- 节点位置: 精灵底边浮于卡面上方 (billboard 自身已上移半高)
    -- 0.12m: 45°视角下需足够高度避免被前排卡牌遮挡
    token.node3d:SetPosition(Vector3(
        token.worldX,
        0.25 + token.bounceY + breatheY,
        token.worldZ
    ))

    -- Billboard 尺寸 (含 squash/stretch 动画)
    local isDead = (token.emotion == "dead")
    local baseW = isDead and DEAD_3D_W or SPRITE_3D_W
    local baseH = isDead and DEAD_3D_H or SPRITE_3D_H

    -- 更新 billboard 局部位置以匹配动态高度 (底边锚定)
    local actualH = baseH * token.scaleY * token.squashY * breatheScale
    bb.position = Vector3(0, actualH / 2, 0)

    bb.size = Vector2(
        baseW * token.scaleX * token.squashX * breatheScale,
        baseH * token.scaleY * token.squashY * breatheScale
    )
    bb.color = Color(1, 1, 1, token.alpha)
    bb.enabled = true

    token.billboardSet:Commit()

    -- Shadow: 独立节点直接定位在脚下地面
    if token.shadowNode then
        token.shadowNode:SetPosition(Vector3(token.worldX, 0.015, token.worldZ))
        -- 跳起时阴影变淡变小
        local shadowAlpha = math.max(0.1, 0.3 - token.bounceY * 0.8)
        local shadowScale = math.max(0.6, 1.0 - token.bounceY * 1.5)
        token.shadowNode:SetScale(Vector3(
            SPRITE_3D_W * 1.1 * shadowScale,
            0.001,
            SPRITE_3D_W * 0.5 * shadowScale
        ))
    end
end

-- ---------------------------------------------------------------------------
-- 表情切换 (换材质纹理 + 翻面动效)
-- ---------------------------------------------------------------------------

--- 切换表情
---@param token table
---@param emotion string 表情名
function M.setEmotion(token, emotion)
    if not token.textures[emotion] then
        emotion = "default"
    end
    if token.emotion == emotion then return end

    -- 移动中直接切换, 不做翻面
    if token.isMoving then
        token.emotion = emotion
        if token.material3d and token.textures[emotion] then
            token.material3d:SetTexture(TU_DIFFUSE, token.textures[emotion])
        end
        return
    end

    -- 翻面动效: squashX → 0 → 切纹理 → 1
    token.pendingEmotion = emotion
    Tween.to(token, { squashX = 0.0 }, 0.07, {
        easing = Tween.Easing.easeInQuad,
        tag = "tokenflip",
        onComplete = function()
            local newEmotion = token.pendingEmotion or emotion
            token.emotion = newEmotion
            token.pendingEmotion = nil
            -- 换纹理
            if token.material3d and token.textures[newEmotion] then
                token.material3d:SetTexture(TU_DIFFUSE, token.textures[newEmotion])
            end
            Tween.to(token, { squashX = 1.0 }, 0.09, {
                easing = Tween.Easing.easeOutBack,
                tag = "tokenflip",
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 出现 (世界坐标)
-- ---------------------------------------------------------------------------

--- Token 出现在指定世界坐标
---@param token table
---@param worldX number
---@param worldZ number
function M.show(token, worldX, worldZ)
    token.worldX = worldX
    token.worldZ = worldZ
    token.bounceY = 0.15     -- 从高处落下
    token.visible = true
    token.scaleX = 0.5
    token.scaleY = 0.5

    Tween.to(token, {
        alpha = 1.0,
        scaleX = 1.0,
        scaleY = 1.0,
        bounceY = 0,
    }, 0.4, {
        easing = Tween.Easing.easeOutBack,
        tag = "token",
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 移动到目标 (世界坐标)
-- ---------------------------------------------------------------------------

--- Token 移动到指定世界坐标
---@param token table
---@param targetX number 目标世界 X
---@param targetZ number 目标世界 Z
---@param onComplete function|nil 完成回调
function M.moveTo(token, targetX, targetZ, onComplete)
    if token.isMoving then return end
    token.isMoving = true

    local dx = targetX - token.worldX
    local dz = targetZ - token.worldZ
    local dist = math.sqrt(dx * dx + dz * dz)
    local duration = math.min(0.6, math.max(0.25, dist / 2.5))  -- ~2.5 m/s

    -- 起跳挤压
    Tween.to(token, { squashX = 1.2, squashY = 0.8 }, 0.08, {
        easing = Tween.Easing.easeOutQuad,
        tag = "tokenmove",
        onComplete = function()
            Tween.to(token, { squashX = 0.85, squashY = 1.15 }, 0.06, {
                easing = Tween.Easing.easeOutQuad,
                tag = "tokenmove",
            })
        end
    })

    -- 主移动 (世界坐标)
    Tween.to(token, { worldX = targetX, worldZ = targetZ }, duration, {
        delay = 0.06,
        easing = Tween.Easing.easeInOutCubic,
        tag = "tokenmove",
    })

    -- 弧形跳跃 (3D: 正值=向上)
    local jumpHeight = math.min(0.20, dist * 0.15 + 0.08)
    Tween.to(token, { bounceY = jumpHeight }, duration * 0.45, {
        delay = 0.06,
        easing = Tween.Easing.easeOutQuad,
        tag = "tokenmove",
        onComplete = function()
            Tween.to(token, { bounceY = 0 }, duration * 0.55, {
                easing = Tween.Easing.easeOutBounce,
                tag = "tokenmove",
            })
        end
    })

    -- 落地挤压恢复
    Tween.to(token, { squashX = 1.0, squashY = 1.0 }, 0.01, {
        delay = duration + 0.06,
        tag = "tokenmove",
        onComplete = function()
            Tween.to(token, { squashX = 1.25, squashY = 0.75 }, 0.06, {
                easing = Tween.Easing.easeOutQuad,
                tag = "tokenmove",
                onComplete = function()
                    Tween.to(token, { squashX = 1.0, squashY = 1.0 }, 0.2, {
                        easing = Tween.Easing.easeOutElastic,
                        tag = "tokenmove",
                        onComplete = function()
                            token.isMoving = false
                            if onComplete then onComplete() end
                        end
                    })
                end
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 小跳 (拍照/驱魔等动作)
-- ---------------------------------------------------------------------------

--- 原地小跳 (世界空间高度偏移)
---@param token table
---@param height number|nil 跳跃高度 (米), 默认 0.05
function M.hop(token, height)
    local h = height or 0.05
    Tween.to(token, { bounceY = h }, 0.10, {
        easing = Tween.Easing.easeOutQuad,
        tag = "tokenmove",
        onComplete = function()
            Tween.to(token, { bounceY = 0 }, 0.15, {
                easing = Tween.Easing.easeInQuad,
                tag = "tokenmove",
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 更新 (idle 计时)
-- ---------------------------------------------------------------------------

function M.update(token, dt)
    if not token.visible then return end
    token.idleTimer = token.idleTimer + dt
end

return M
