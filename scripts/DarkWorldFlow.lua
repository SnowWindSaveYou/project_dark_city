-- ============================================================================
-- DarkWorldFlow.lua - 暗面世界进出 / 层间切换
-- 从 main.lua 拆分, 通过 G 共享状态表与主模块通信
-- ============================================================================

local DarkWorld     = require "DarkWorld"
local Tween         = require "lib.Tween"
local VFX           = require "lib.VFX"
local Board         = require "Board"
local Card          = require "Card"
local Token         = require "Token"
local CardTextures  = require "CardTextures"
local ResourceBar   = require "ResourceBar"
local CameraButton  = require "CameraButton"
local HandPanel     = require "HandPanel"
local BubbleDialogue = require "BubbleDialogue"
local MonsterGhost  = require "MonsterGhost"
local BoardItems    = require "BoardItems"
local NPCManager    = require "NPCManager"
local AudioManager  = require "AudioManager"

local M = {}

---@type table  共享状态表
local G

-- 从 init opts 注入的引用
local scene_
local camera_
local recalcLayout_
local setBgTarget_     -- function(v): 设置 bgTransitionTarget
local getBgTarget_     -- function(): number 获取 bgTransitionTarget

-- ── 模块内部状态 (现实世界快照, 仅进出暗面时使用) ──
local savedRealityCards = nil
local savedRealityFaceUp = nil  -- {[row]={[col]=bool}}
local savedHomeRow, savedHomeCol = nil, nil
local savedBgTransition = 0

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化 DarkWorldFlow
---@param gameState table  共享 G 表
---@param opts table  { scene, camera, recalcLayout, setBgTransitionTarget, getBgTransitionTarget }
function M.init(gameState, opts)
    G = gameState
    scene_         = opts.scene
    camera_        = opts.camera
    recalcLayout_  = opts.recalcLayout
    setBgTarget_   = opts.setBgTransitionTarget
    getBgTarget_   = opts.getBgTransitionTarget
end

--- 重置保存的现实世界快照 (游戏重新开始时由 GameFlow 调用)
function M.resetSavedState()
    savedRealityCards = nil
    savedRealityFaceUp = nil
    savedHomeRow = nil
    savedHomeCol = nil
    savedBgTransition = 0
end

-- ============================================================================
-- 进入暗面世界
-- ============================================================================

--- 进入暗面世界 (从裂隙卡触发, 复用 Board 收发牌流程)
function M.enterDarkWorld(riftRow, riftCol)
    local board = G.board
    local token = G.token

    if DarkWorld.isActive() then return end
    if not DarkWorld.canEnter(G.dayCount) then
        VFX.spawnBanner("暗面世界尚未开启 (第2天解锁)", 180, 80, 80, 16, 0.8)
        G.demoState = "ready"
        CameraButton.show()
        return
    end

    G.demoState = "transition"
    CameraButton.hide()
    HandPanel.hide()
    if G.playerBubble then BubbleDialogue.forceHide(G.playerBubble) end
    AudioManager.playSFX("rift_enter")
    AudioManager.playBGM("dark_world", 2.0)
    AudioManager.playAmbient("dark")

    -- 1. 保存现实世界状态 (undeal 会重置 faceUp, 需单独快照)
    savedRealityCards = board.cards
    savedRealityFaceUp = {}
    for r = 1, Board.ROWS do
        savedRealityFaceUp[r] = {}
        for c = 1, Board.COLS do
            local cd = board.cards[r] and board.cards[r][c]
            if cd then savedRealityFaceUp[r][c] = cd.faceUp end
        end
    end
    savedHomeRow = board.homeRow
    savedHomeCol = board.homeCol
    savedBgTransition = getBgTarget_()

    -- 2. 清理现实世界的覆盖物
    MonsterGhost.clearSurround()
    MonsterGhost.clearCardGhosts()
    MonsterGhost.clearTrailGhosts()
    BoardItems.clear()
    NPCManager.clear()

    -- 3. 隐藏 Token
    token.visible = false
    token.alpha = 0

    -- 4. 收牌 → 销毁 → 重建暗面卡牌
    local physW, physH = graphics:GetWidth(), graphics:GetHeight()
    Tween.cancelTag("cardflip")
    Tween.cancelTag("cardshake")
    Board.undealAll(board, function()
        Board.destroyAllNodes(board)
        CardTextures.clearCache()

        -- 5. 设置暗面状态 & 大气
        DarkWorld.enter(G.dayCount, riftRow, riftCol, scene_, camera_, CardTextures, physW, physH,
            function() M.exitDarkWorld() end
        )
        setBgTarget_(1.0)  -- 暗面世界全暗大气

        -- 5.5 立即切换 ResourceBar 到暗面模式 (收牌后、发牌前, 让 HUD 先变)
        local layerIdx = DarkWorld.getCurrentLayer()
        ResourceBar.setDarkMode(true, {
            layerName = DarkWorld.getLayerName(),
            energy = DarkWorld.getEnergy(),
            maxEnergy = 10,
            layerIdx = layerIdx,
            layerCount = 3,
        })

        -- 6. 生成或恢复暗面卡牌
        local layerData = DarkWorld.getLayerData()

        if layerData.generated and layerData.savedCards then
            -- 已生成过: 恢复保存的卡牌
            board.cards = layerData.savedCards
            board.homeRow = layerData.entryRow
            board.homeCol = layerData.entryCol
        else
            -- 首次进入: 生成新卡牌
            local darkConfig = DarkWorld.getDarkConfig(layerIdx)
            local darkLocations = DarkWorld.getDarkLocations(layerIdx)
            Board.generateDarkCards(board, layerData, darkLocations, darkConfig)
            DarkWorld.generateOverlayData(layerIdx)
        end

        -- 7. 预加载纹理 → 创建节点 → 发牌
        CardTextures.preloadBoard(board, Board.ROWS, Board.COLS)
        Board.createAllNodes(board, scene_, CardTextures)
        DarkWorld.createOverlayNodes(board.boardNode)
        recalcLayout_()

        -- 8. 发牌动画完成后显示 Token
        Board.dealAll(board, function()
            local pRow = layerData.playerRow or layerData.entryRow
            local pCol = layerData.playerCol or layerData.entryCol
            local wx, wz = Board.cardPos(board, pRow, pCol)
            Token.show(token, wx, wz)
            token.targetRow = pRow
            token.targetCol = pCol
            Token.setEmotion(token, "normal")

            -- 暗面卡牌全明牌: 翻开所有可通行卡
            for r = 1, Board.ROWS do
                for c = 1, Board.COLS do
                    local cd = board.cards[r] and board.cards[r][c]
                    if cd and not cd.faceUp and cd.isDark then
                        cd.faceUp = true
                        Card.updateTexture(cd, CardTextures)
                    end
                end
            end

            G.demoState = "ready"
            CameraButton.show()
            DarkWorld.onEnterComplete()
            print("[Main] Dark world entered, layer=" .. layerIdx)
        end)
    end)
end

-- ============================================================================
-- 退出暗面世界
-- ============================================================================

--- 退出暗面世界 (恢复现实世界棋盘)
function M.exitDarkWorld()
    local board = G.board
    local token = G.token

    if not DarkWorld.isActive() then return end

    G.demoState = "transition"
    CameraButton.hide()
    if G.playerBubble then BubbleDialogue.forceHide(G.playerBubble) end
    AudioManager.playSFX("rift_exit")
    AudioManager.stopAmbient()
    -- BGM 根据当前氛围恢复 (savedBgTransition 决定)
    if savedBgTransition > 0.5 then
        AudioManager.playBGM("day_dark", 2.0)
    else
        AudioManager.playBGM("day_light", 2.0)
    end

    -- 1. 保存暗面卡牌状态
    local layerData = DarkWorld.getLayerData()
    layerData.savedCards = board.cards
    -- playerRow/playerCol 由 DarkWorld.handleClick 在移动时维护

    -- 2. 获取裂隙位置 (返回现实世界后 Token 站的位置)
    local riftRow, riftCol, _ = DarkWorld.beginExit()

    -- 3. 隐藏 Token
    token.visible = false
    token.alpha = 0

    -- 4. 收牌 → 销毁 → 恢复现实
    Tween.cancelTag("cardflip")
    Tween.cancelTag("cardshake")
    Board.undealAll(board, function()
        DarkWorld.destroyOverlayNodes()
        Board.destroyAllNodes(board)
        CardTextures.clearCache()
        DarkWorld.onExitComplete()

        -- 立即恢复 ResourceBar 到现实模式 (收牌后、发牌前)
        ResourceBar.setDarkMode(false)

        -- 5. 恢复大气
        setBgTarget_(savedBgTransition)

        -- 6. 恢复现实世界卡牌 & faceUp 状态
        board.cards = savedRealityCards
        board.homeRow = savedHomeRow
        board.homeCol = savedHomeCol
        if savedRealityFaceUp then
            for r = 1, Board.ROWS do
                for c = 1, Board.COLS do
                    local cd = board.cards[r] and board.cards[r][c]
                    if cd and savedRealityFaceUp[r] then
                        cd.faceUp = savedRealityFaceUp[r][c] or false
                    end
                end
            end
        end
        savedRealityCards = nil
        savedRealityFaceUp = nil

        -- 7. 预加载 → 创建节点 → 发牌
        CardTextures.preloadBoard(board, Board.ROWS, Board.COLS)
        Board.createAllNodes(board, scene_, CardTextures)
        recalcLayout_()

        Board.dealAll(board, function()
            -- 安全区光晕: 恢复 (home/landmark 自带, 辐射区需额外 attach)
            local safeGlowTex = CardTextures.getSafeGlowTexture and CardTextures.getSafeGlowTexture()
            for r = 1, Board.ROWS do
                for c = 1, Board.COLS do
                    local cd = board.cards[r] and board.cards[r][c]
                    if cd then
                        if cd.type == "home" or cd.type == "landmark" then
                            Card.showSafeGlow(cd)
                        elseif safeGlowTex and Board.isInLandmarkAura(board, r, c) then
                            Card.attachGlowRings(cd, safeGlowTex)
                            Card.showSafeGlow(cd)
                        end
                    end
                end
            end

            -- Token 回到裂隙卡位置
            local wx, wz = Board.cardPos(board, riftRow, riftCol)
            Token.show(token, wx, wz)
            token.targetRow = riftRow
            token.targetCol = riftCol
            Token.setEmotion(token, "normal")

            G.demoState = "ready"
            CameraButton.show()
            HandPanel.show(G.logicalH, { showcase = false })
            print("[Main] Returned to reality from dark world")
        end)
    end)
end

-- ============================================================================
-- 暗面世界层间切换
-- ============================================================================

--- 暗面世界层间切换 (由 DarkWorld 通道卡触发)
function M.changeDarkLayer(targetLayer, dc)
    local board = G.board
    local token = G.token

    if not DarkWorld.isActive() then return end

    G.demoState = "transition"
    AudioManager.playSFX("layer_transition")

    -- 1. 保存当前层卡牌
    local oldLayerData = DarkWorld.getLayerData()
    oldLayerData.savedCards = board.cards

    -- 2. 切换层级 (DarkWorld 内部更新 currentLayer_)
    local success, layerName = DarkWorld.beginChangeLayer(targetLayer, dc)
    if not success then
        G.demoState = "ready"
        return
    end

    -- 3. 隐藏 Token
    token.visible = false
    token.alpha = 0

    VFX.spawnBanner("前往 " .. (layerName or "未知区域"), 200, 180, 255, 20, 1.0)

    -- 4. 收牌 → 销毁 → 生成新层
    Tween.cancelTag("cardflip")
    Tween.cancelTag("cardshake")
    Board.undealAll(board, function()
        DarkWorld.destroyOverlayNodes()
        Board.destroyAllNodes(board)
        CardTextures.clearCache()

        -- 立即更新 ResourceBar 暗面信息 (新层, 收牌后发牌前)
        local newLayerIdx = DarkWorld.getCurrentLayer()
        ResourceBar.setDarkMode(true, {
            layerName = DarkWorld.getLayerName(),
            energy = DarkWorld.getEnergy(),
            maxEnergy = 10,
            layerIdx = newLayerIdx,
            layerCount = 3,
        })

        -- 5. 生成或恢复目标层卡牌
        local newLayerData = DarkWorld.getLayerData()

        if newLayerData.generated and newLayerData.savedCards then
            board.cards = newLayerData.savedCards
            board.homeRow = newLayerData.entryRow
            board.homeCol = newLayerData.entryCol
        else
            local darkConfig = DarkWorld.getDarkConfig(newLayerIdx)
            local darkLocations = DarkWorld.getDarkLocations(newLayerIdx)
            Board.generateDarkCards(board, newLayerData, darkLocations, darkConfig)
            DarkWorld.generateOverlayData(newLayerIdx)
        end

        -- 6. 预加载 → 创建 → 发牌
        CardTextures.preloadBoard(board, Board.ROWS, Board.COLS)
        Board.createAllNodes(board, scene_, CardTextures)
        DarkWorld.createOverlayNodes(board.boardNode)
        recalcLayout_()

        Board.dealAll(board, function()
            local pRow = newLayerData.playerRow or newLayerData.entryRow
            local pCol = newLayerData.playerCol or newLayerData.entryCol
            local wx, wz = Board.cardPos(board, pRow, pCol)
            Token.show(token, wx, wz)
            token.targetRow = pRow
            token.targetCol = pCol

            -- 全明牌
            for r = 1, Board.ROWS do
                for c = 1, Board.COLS do
                    local cd = board.cards[r] and board.cards[r][c]
                    if cd and not cd.faceUp and cd.isDark then
                        cd.faceUp = true
                        Card.updateTexture(cd, CardTextures)
                    end
                end
            end

            G.demoState = "ready"
            DarkWorld.onChangeLayerComplete()
            print("[Main] Dark layer changed to " .. newLayerIdx)
        end)
    end)
end

return M
