-- ============================================================================
-- GameFlow.lua - 发牌 / 收牌 / 日期流程 / 胜负判定 / 重启
-- 从 main.lua 提取, 通过 G 共享状态表与主模块通信
-- ============================================================================

local Tween          = require "lib.Tween"
local VFX            = require "lib.VFX"
local Theme          = require "Theme"
local Card           = require "Card"
local Board          = require "Board"
local Token          = require "Token"
local CardTextures   = require "CardTextures"
local ResourceBar    = require "ResourceBar"
local EventPopup     = require "EventPopup"
local CameraButton   = require "CameraButton"
local GameOver       = require "GameOver"
local ShopPopup      = require "ShopPopup"
local CardManager    = require "CardManager"
local HandPanel      = require "HandPanel"
local DateTransition = require "DateTransition"
local BubbleDialogue = require "BubbleDialogue"
local BoardItems     = require "BoardItems"
local NPCManager     = require "NPCManager"
local DialogueSystem = require "DialogueSystem"
local DarkWorld      = require "DarkWorld"
local AudioManager   = require "AudioManager"

local M = {}

---@type table  shared mutable state
local G

-- main.lua 注入的回调 / 引用
local scene_           -- Scene (3D 场景根)
local recalcLayout_    -- function: 重新计算布局
local resetMainState_  -- function: 重置 main.lua 特有的局部状态 (savedReality 等)

-- 常量 (从 main.lua 搬过来)
local MAX_DAYS = 3

-- NPC 对话脚本
local QINXIN_DIALOGUE = {
    { speaker = "琴馨", text = "唔……你也能看到那些奇怪的东西啊……" },
    { speaker = "琴馨", text = "……我还以为只有我一个人呢。" },
    { speaker = "琴馨", text = "这台相机……可以拍下一些肉眼看不到的东西。" },
    { speaker = "琴馨", text = "比如那些影子。它们害怕闪光灯。" },
    { speaker = "琴馨", text = "你也小心点吧。" },
}

--- 初始化, 接收共享状态 + 依赖注入
---@param gameState table
---@param opts table { scene, recalcLayout, resetMainState }
function M.init(gameState, opts)
    G = gameState
    scene_          = opts.scene
    recalcLayout_   = opts.recalcLayout
    resetMainState_ = opts.resetMainState
end

-- ============================================================================
-- 发牌
-- ============================================================================

function M.startDeal()
    G.demoState = "dealing"
    G.gameStats.dayStartRevealed = G.gameStats.cardsRevealed
    AudioManager.playSFX("card_deal")
    VFX.spawnBanner("第 " .. G.dayCount .. " 天", 255, 255, 255, 28, 1.2)

    Board.dealAll(G.board, function()
        G.demoState = "ready"
        print("[GameFlow] Deal complete, Day " .. G.dayCount)

        local homeRow = G.board.homeRow
        local homeCol = G.board.homeCol

        -- Day 1: 放置琴馨 NPC
        if G.dayCount == 1 then
            local candidates = {}
            for r = 1, Board.ROWS do
                for c = 1, Board.COLS do
                    if not (r == homeRow and c == homeCol) then
                        candidates[#candidates + 1] = { r = r, c = c }
                    end
                end
            end
            if #candidates > 0 then
                local pick = candidates[math.random(#candidates)]
                NPCManager.spawnNPC("qinxin", "琴馨", pick.r, pick.c,
                    "image/怪物_面具使v2_20260426072832.png", QINXIN_DIALOGUE)
            end
        end

        -- Token 位置
        local wx, wz = Board.cardPos(G.board, homeRow, homeCol)
        local shareOff = NPCManager.getShareOffset(homeRow, homeCol)
        Token.show(G.token, wx + shareOff, wz)
        G.token.targetRow = homeRow
        G.token.targetCol = homeCol

        -- 家的卡牌默认翻开
        local homeCard = G.board.cards[homeRow][homeCol]
        if homeCard and not homeCard.faceUp then
            homeCard.faceUp = true
            Card.updateTexture(homeCard, CardTextures)
        end

        -- 安全区光晕
        local safeGlowTex = CardTextures.getSafeGlowTexture and CardTextures.getSafeGlowTexture()
        for r = 1, Board.ROWS do
            for c = 1, Board.COLS do
                local cd = G.board.cards[r] and G.board.cards[r][c]
                if cd then
                    if cd.type == "home" or cd.type == "landmark" then
                        Card.showSafeGlow(cd)
                    elseif safeGlowTex and Board.isInLandmarkAura(G.board, r, c) then
                        Card.attachGlowRings(cd, safeGlowTex)
                        Card.showSafeGlow(cd)
                    end
                end
            end
        end

        CardManager.generateDaily(G.board)
        HandPanel.show(G.logicalH, { showcase = true })
        CameraButton.show()

        BoardItems.spawnDaily(G.board, Board, homeRow, homeCol)
    end)
end

-- ============================================================================
-- 收牌 → 重新发牌
-- ============================================================================

function M.startRedeal()
    if G.gamePhase ~= "playing" then return end
    if G.demoState == "dealing" then return end
    if EventPopup.isActive() or CameraButton.isActive() or ShopPopup.isActive() or DialogueSystem.isActive() then return end
    G.demoState = "dealing"
    G.hoveredCard = nil
    EventPopup.clearToasts()
    if G.playerBubble then BubbleDialogue.forceHide(G.playerBubble) end
    Tween.cancelTag("cardflip")
    Tween.cancelTag("carddeal")
    Tween.cancelTag("cardshake")
    Tween.cancelTag("cardtransform")
    Tween.cancelTag("tokenmove")
    Tween.cancelTag("token")
    Tween.cancelTag("popup")
    Tween.cancelTag("toast")
    Tween.cancelTag("bubble")
    Tween.cancelTag("camerabtn")
    Tween.cancelTag("cameramode")
    Tween.cancelTag("camerabtn_shake")
    Tween.cancelTag("shoppopup")
    Tween.cancelTag("shoppopup_card")
    Tween.cancelTag("shoppopup_flash")
    Tween.cancelTag("handpanel")

    G.token.visible = false
    G.token.alpha = 0
    HandPanel.hide()
    CameraButton.hide()
    BoardItems.clear()
    NPCManager.clear()
    DialogueSystem.reset()

    Board.undealAll(G.board, function()
        Board.destroyAllNodes(G.board)
        CardTextures.clearCache()
        local locs = CardManager.preSelectLocations()
        Board.generateCards(G.board, locs)
        CardTextures.preloadBoard(G.board, Board.ROWS, Board.COLS)
        Board.createAllNodes(G.board, scene_, CardTextures)
        recalcLayout_()
        M.startDeal()
    end)
end

-- ============================================================================
-- 推进日期
-- ============================================================================

function M.advanceDay()
    if G.gamePhase ~= "playing" then return end
    if G.demoState ~= "ready" then return end
    if EventPopup.isActive() or CameraButton.isActive() or ShopPopup.isActive() or DialogueSystem.isActive() then return end

    HandPanel.hide()
    AudioManager.playStinger("day_transition", 0.7)
    local effects = CardManager.settleDay()

    local penaltyCount = 0
    local totalPenalty = 0
    for _, eff in ipairs(effects) do
        if eff[2] < 0 then
            penaltyCount = penaltyCount + 1
            totalPenalty = totalPenalty + math.abs(eff[2])
        end
    end
    if penaltyCount > 0 then
        VFX.spawnBanner("⚠ " .. penaltyCount .. "项日程未完成! 秩序-" .. totalPenalty, 220, 80, 80, 18, 1.2)
        VFX.flashScreen(180, 30, 30, 0.25, 100)
    end

    ResourceBar.change("san", 1)
    ResourceBar.change("order", 1)

    local currentFilm = ResourceBar.get("film")
    if currentFilm < 3 then
        ResourceBar.change("film", 3 - currentFilm)
    end
    ResourceBar.change("money", 10)

    if ResourceBar.get("order") <= 0 or ResourceBar.get("san") <= 0 then
        M.checkDefeat()
        return
    end

    G.demoState = "dealing"
    G.hoveredCard = nil
    if G.playerBubble then BubbleDialogue.forceHide(G.playerBubble) end
    Tween.cancelTag("cardflip")
    Tween.cancelTag("cardshake")
    Tween.cancelTag("bubble")

    G.token.visible = false
    G.token.alpha = 0
    HandPanel.hide()
    CameraButton.hide()
    BoardItems.clear()
    NPCManager.clear()
    DialogueSystem.reset()

    Board.undealAll(G.board, function()
        G.dayCount = G.dayCount + 1
        if M.checkVictory() then return end

        Board.destroyAllNodes(G.board)
        CardTextures.clearCache()

        DateTransition.play(G.dayCount, function()
            local locs = CardManager.preSelectLocations()
            Board.generateCards(G.board, locs)
            CardTextures.preloadBoard(G.board, Board.ROWS, Board.COLS)
            Board.createAllNodes(G.board, scene_, CardTextures)
            recalcLayout_()
            M.startDeal()
        end)
    end)
end

-- ============================================================================
-- 胜负判定
-- ============================================================================

function M.checkDefeat()
    if G.gamePhase ~= "playing" then return end
    local san   = ResourceBar.get("san")
    local order = ResourceBar.get("order")
    if san <= 0 or order <= 0 then
        AudioManager.playStinger("defeat_sting", 0.9)
        local delay = { t = 0 }
        Tween.to(delay, { t = 1 }, 0.8, {
            tag = "gameover",
            onComplete = function()
                G.gamePhase = "gameover"
                G.demoState = "idle"
                Token.setEmotion(G.token, "dead")
                CameraButton.hide()
                AudioManager.playBGM("defeat", 2.0)
                AudioManager.stopAmbient()
                VFX.triggerShake(8, 0.4, 20)
                VFX.flashScreen(180, 30, 30, 0.5, 200)
                GameOver.show(false, {
                    daysSurvived  = G.dayCount,
                    cardsRevealed = G.gameStats.cardsRevealed,
                    monstersSlain = G.gameStats.monstersSlain,
                    photosUsed    = G.gameStats.photosUsed,
                }, M.onGameRestart)
            end
        })
    end
end

function M.checkVictory()
    if G.gamePhase ~= "playing" then return false end
    if G.dayCount > MAX_DAYS then
        G.gamePhase = "gameover"
        G.demoState = "idle"
        Token.setEmotion(G.token, "happy")
        AudioManager.playStinger("victory_sting", 0.9)
        AudioManager.playBGM("victory", 2.0)
        AudioManager.stopAmbient()
        VFX.flashScreen(255, 215, 100, 0.5, 180)
        GameOver.show(true, {
            daysSurvived  = MAX_DAYS,
            cardsRevealed = G.gameStats.cardsRevealed,
            monstersSlain = G.gameStats.monstersSlain,
            photosUsed    = G.gameStats.photosUsed,
        }, M.onGameRestart)
        return true
    end
    return false
end

-- ============================================================================
-- 游戏重启
-- ============================================================================

function M.onGameRestart()
    AudioManager.reset()
    Tween.cancelAll()
    VFX.resetAll()
    EventPopup.clearToasts()
    G.hoveredCard = nil

    G.dayCount = 1
    G.gamePhase = "playing"
    G.gameStats.cardsRevealed = 0
    G.gameStats.dayStartRevealed = 0
    G.gameStats.monstersSlain = 0
    G.gameStats.photosUsed    = 0

    -- 重置 main.lua 特有的状态 (savedReality, bgTransition, cameraPan 等)
    resetMainState_()

    ResourceBar.reset()
    CardManager.reset()
    HandPanel.reset()
    ShopPopup.resetInventory()
    BoardItems.clear()
    NPCManager.clear()
    DialogueSystem.reset()
    DarkWorld.reset()
    G.pendingRiftRow = nil
    G.pendingRiftCol = nil

    Board.destroyAllNodes(G.board)
    CardTextures.clearCache()

    local locs = CardManager.preSelectLocations()
    Board.generateCards(G.board, locs)
    CardTextures.preloadBoard(G.board, Board.ROWS, Board.COLS)
    Board.createAllNodes(G.board, scene_, CardTextures)
    recalcLayout_()

    Token.destroyNode(G.token)
    local token = Token.new()
    token.textures = Token.loadTextures()
    Token.createNode(token, scene_)
    G.token = token

    -- 重置气泡对话
    local playerBubble = BubbleDialogue.newBubble()
    G.playerBubble = playerBubble

    AudioManager.playBGM("day_light", 2.0)
    M.startDeal()
end

-- ============================================================================
-- 裂隙确认 (翻牌后事件完成再触发)
-- ============================================================================

--- 在 Update 中轮询: 事件全部结束 + 有裂隙待确认 → 弹窗
---@return boolean consumed
function M.checkPendingRift()
    if not G.pendingRiftRow then return false end
    if EventPopup.isActive() or ShopPopup.isActive() or EventPopup.isRiftConfirmActive() then
        return false
    end
    local row, col = G.pendingRiftRow, G.pendingRiftCol
    G.pendingRiftRow, G.pendingRiftCol = nil, nil

    if not DarkWorld.canEnter(G.dayCount) then
        local tc2 = Theme.current
        VFX.spawnBanner("🌀 裂隙出现... 暗面世界第2天解锁",
            tc2.darkAccent.r, tc2.darkAccent.g, tc2.darkAccent.b, 16, 0.8)
        return false
    end

    G.demoState = "popup"
    CameraButton.hide()
    AudioManager.playSFX("popup_open")
    local tc2 = Theme.current
    VFX.spawnBanner("🌀 发现裂隙！", tc2.darkAccent.r, tc2.darkAccent.g, tc2.darkAccent.b, 18, 0.8)

    local riftDelay = { t = 0 }
    Tween.to(riftDelay, { t = 1 }, 0.5, {
        tag = "riftconfirm",
        onComplete = function()
            local popCX = G.logicalW / 2
            local popCY = G.logicalH * 0.42
            EventPopup.showRiftConfirm(popCX, popCY,
                function()
                    G.enterDarkWorld(row, col)
                end,
                function()
                    G.demoState = "ready"
                    CameraButton.show()
                end
            )
        end,
    })
    return true
end

return M
