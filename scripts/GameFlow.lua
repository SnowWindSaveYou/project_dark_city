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
local Baiye          = require "Baiye"
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
local DarkWorldFlow  = require "DarkWorldFlow"
local AudioManager   = require "AudioManager"
local StoryManager        = require "StoryManager"
local EndingSystem        = require "EndingSystem"
local MilestoneManager    = require "MilestoneManager"
local MonsterGhost        = require "MonsterGhost"
local StoryEventManager   = require "StoryEventManager"
local Weather             = require "Weather"

local M = {}

---@type table  shared mutable state
local G

-- main.lua 注入的回调 / 引用
local scene_           -- Scene (3D 场景根)
local recalcLayout_    -- function: 重新计算布局
local resetMainState_  -- function: 重置 main.lua 特有的局部状态 (savedReality 等)

-- 动态最大天数 (由 StoryManager 碎片数决定)
local function getMaxDays()
    if G and G.storyMgr then
        return StoryManager.getMaxDays(G.storyMgr)
    end
    return 7
end

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
    G.stepsUsed = 0   -- 每日步数重置
    G.gameStats.dayStartRevealed = G.gameStats.cardsRevealed
    AudioManager.playSFX("card_deal")
    VFX.spawnBanner("第 " .. G.dayCount .. " 天", 255, 255, 255, 28, 1.2)

    Board.dealAll(G.board, function()
        G.demoState = "ready"
        print("[GameFlow] Deal complete, Day " .. G.dayCount)

        -- 天气环境音 (每日发牌完成后根据天气播放)
        local dayWeather = Weather.getWeather(G.dayCount)
        AudioManager.playAmbient(Weather.getAmbientKey(dayWeather))
        print("[GameFlow] Weather: " .. Weather.getName(dayWeather))

        local homeRow = G.board.homeRow
        local homeCol = G.board.homeCol

        -- NPC 生成
        local usedTiles = {}  -- 已占用的格子 (含 home)
        usedTiles[homeRow * 10 + homeCol] = true

        local function pickFreeTile()
            local cands = {}
            for r = 1, Board.ROWS do
                for c = 1, Board.COLS do
                    if not usedTiles[r * 10 + c] then
                        cands[#cands + 1] = { r = r, c = c }
                    end
                end
            end
            if #cands == 0 then return nil end
            local p = cands[math.random(#cands)]
            usedTiles[p.r * 10 + p.c] = true
            return p
        end

        -- Day 1: 琴馨 (相机教学)
        if G.dayCount == 1 then
            local pick = pickFreeTile()
            if pick then
                NPCManager.spawnNPC("qinxin", "琴馨", pick.r, pick.c,
                    "image/怪物_面具使v2_20260426072832.png", QINXIN_DIALOGUE)
            end
        end

        -- Day 3+: 房东 (资源交换)
        if G.dayCount >= 3 then
            local pick = pickFreeTile()
            if pick then
                NPCManager.spawnNPC("fangdong", "房东", pick.r, pick.c,
                    "image/npc_房东_chibi_20260507035549.png", nil)
            end
        end

        -- 随机: 猫 (50% 概率出现)
        if math.random() < 0.5 then
            local pick = pickFreeTile()
            if pick then
                NPCManager.spawnNPC("cat", "猫", pick.r, pick.c,
                    "image/npc_猫咪_自然_20260507040343.png", nil)
            end
        end

        -- Token 位置
        local wx, wz = Board.cardPos(G.board, homeRow, homeCol)
        local shareOff = NPCManager.getShareOffset(homeRow, homeCol)
        Token.show(G.token, wx + shareOff, wz)
        if G.baiye then Baiye.show(G.baiye, wx + shareOff, wz) end
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

        -- Day 1 教程: 发牌完成、所有初始化结束后触发
        -- 流程: 相机 Pan 聚焦主角 → 短暂定格 → 相机回中心 → 白夜对话 → 笔记本高亮
        if G.dayCount == 1 then
            M.triggerDay1Tutorial(wx, wz)
        end
    end)
end

-- ============================================================================
-- Day 1 引导教程
-- ============================================================================

-- 白夜引导对话内容
local DAY1_TUTORIAL_DIALOGUE = {
    { speaker = "白夜", text = "……这里是外面的世界。" },
    { speaker = "苏柚", text = "对。我们今天要出门。" },
    { speaker = "白夜", text = "那些背面朝上的牌……翻开后会有麻烦吗？" },
    { speaker = "苏柚", text = "有些是正常的地方，有些……自从你来了以后，就不太一样了。" },
    { speaker = "白夜", text = "……对不起。" },
    { speaker = "苏柚", text = "不是怪你。（翻开笔记本）不管怎样，我今天有些事要做。" },
    { speaker = "苏柚", text = "左边这本是日程，完成了有好处。尽量别一直拖着。" },
    { speaker = "白夜", text = "……我知道了。我不会拖累你的。" },
}

--- Day 1 教程触发
---@param tokenWX number Token 的世界 X
---@param tokenWZ number Token 的世界 Z
function M.triggerDay1Tutorial(tokenWX, tokenWZ)
    if not G.setCameraPan then return end

    -- 阶段1: 相机 Pan 聚焦主角格子 (稍微偏移，不完全居中以保留棋盘感)
    local panTargetX = tokenWX * 0.55
    local panTargetZ = tokenWZ * 0.55

    -- 短暂延迟让 Token/白夜 入场动画先播完
    local delay = { t = 0 }
    Tween.to(delay, { t = 1 }, 0.6, {
        tag = "tutorial",
        onComplete = function()
            -- 聚焦主角
            G.setCameraPan(panTargetX, panTargetZ, 0.9, Tween.Easing.easeOutQuad, function()
                -- 阶段2: 定格 0.8s 让玩家看清自己的角色
                local hold = { t = 0 }
                Tween.to(hold, { t = 1 }, 0.8, {
                    tag = "tutorial",
                    onComplete = function()
                        -- 阶段3: 相机缓回中心，同时触发对话
                        G.setCameraPan(0, 0, 1.2, Tween.Easing.easeInOutQuad)

                        -- 短暂等待后弹出对话（和相机回程同步，更自然）
                        local dialogDelay = { t = 0 }
                        Tween.to(dialogDelay, { t = 1 }, 0.3, {
                            tag = "tutorial",
                            onComplete = function()
                                DialogueSystem.start(DAY1_TUTORIAL_DIALOGUE, nil, function()
                                    -- 对话结束 → 笔记本高亮提示
                                    HandPanel.highlightOnce()
                                end)
                            end,
                        })
                    end,
                })
            end)
        end,
    })
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
    if G.baiye then G.baiye.visible = false; G.baiye.alpha = 0 end
    HandPanel.hide()
    CameraButton.hide()
    BoardItems.clear()
    NPCManager.clear()
    DialogueSystem.reset()

    Board.undealAll(G.board, function()
        Board.destroyAllNodes(G.board)
        CardTextures.clearCache()
        local locs = CardManager.preSelectLocations()
        Board.generateCards(G.board, locs, { dayCount = G.dayCount, canHaveRift = G.dayCount > 1 and DarkWorld.canEnter() })
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
        VFX.spawnBanner("⚠ " .. penaltyCount .. "项日程未完成!", 220, 80, 80, 18, 1.2)
        VFX.flashScreen(180, 30, 30, 0.25, 100)
    end

    ResourceBar.change("san", 1)

    -- 每日胶卷重置为 3（仅补足 dailyFilm）
    local curDaily = ResourceBar.get("dailyFilm")
    if curDaily < 3 then
        ResourceBar.change("dailyFilm", 3 - curDaily)
    end
    ResourceBar.change("money", 10)

    if ResourceBar.get("health") <= 0 or ResourceBar.get("san") <= 0 then
        M.checkDefeat()
        return
    end

    -- 夜谈触发: 在 undeal 动画前播放当日结束对话
    local eveningCtx = { dayCount = G.dayCount }
    local function doUndealAndAdvance()
        G.demoState = "dealing"
        G.hoveredCard = nil
        if G.playerBubble then BubbleDialogue.forceHide(G.playerBubble) end
        Tween.cancelTag("cardflip")
        Tween.cancelTag("cardshake")
        Tween.cancelTag("bubble")

        G.token.visible = false
        G.token.alpha = 0
        if G.baiye then G.baiye.visible = false; G.baiye.alpha = 0 end
        HandPanel.hide()
        CameraButton.hide()
        BoardItems.clear()
        NPCManager.clear()
        DialogueSystem.reset()

        Board.undealAll(G.board, function()
        G.dayCount = G.dayCount + 1

        -- 故事系统: 每日结算
        local baiyeWokeUp = false
        local chapterChanged = false
        if G.storyMgr then
            local wasSleeping = G.storyMgr.sleep_days_left > 0
            StoryManager.tickSleep(G.storyMgr)
            baiyeWokeUp = wasSleeping and G.storyMgr.sleep_days_left <= 0

            local oldChapter = G.storyMgr.currentChapter
            StoryManager.updateChapter(G.storyMgr, G.dayCount)
            chapterChanged = (oldChapter ~= G.storyMgr.currentChapter)
        end

        if M.checkVictory() then return end

        Board.destroyAllNodes(G.board)
        CardTextures.clearCache()

        DateTransition.play(G.dayCount, function()
            local locs = CardManager.preSelectLocations()
            Board.generateCards(G.board, locs, { dayCount = G.dayCount, canHaveRift = G.dayCount > 1 and DarkWorld.canEnter() })
            CardTextures.preloadBoard(G.board, Board.ROWS, Board.COLS)
            Board.createAllNodes(G.board, scene_, CardTextures)
            recalcLayout_()

            -- 每日开场 → 里程碑 hook 链: morning → baiye_return → chapter_enter → resource_low → startDeal
            local msCtx = { dayCount = G.dayCount }
            local function afterMilestones()
                M.startDeal()
            end
            local function tryResourceLow()
                local hp = ResourceBar.get("health")
                local san = ResourceBar.get("san")
                if hp <= 2 or san <= 2 then
                    MilestoneManager.tryTrigger("resource_low", G.storyMgr, msCtx, afterMilestones)
                else
                    afterMilestones()
                end
            end
            local function tryChapterEnter()
                if chapterChanged then
                    MilestoneManager.tryTrigger("chapter_enter", G.storyMgr, msCtx, tryResourceLow)
                else
                    tryResourceLow()
                end
            end
            local function tryMilestoneChain()
                if baiyeWokeUp then
                    MilestoneManager.tryTrigger("baiye_return", G.storyMgr, msCtx, tryChapterEnter)
                else
                    tryChapterEnter()
                end
            end
            -- 第6天特殊: 开场后强制进入暗面（碎片守卫剧情）
            -- 先播放晨间事件对话，结束后直接触发 enterDarkWorld
            local function afterMorningForDay6()
                -- 显示提示横幅后进入暗面
                VFX.spawnBanner("暗面异动……", 180, 80, 220, 18, 1.2)
                local delay = { t = 0 }
                Tween.to(delay, { t = 1 }, 0.8, {
                    tag = "day6_dark_enter",
                    onComplete = function()
                        -- 找棋盘中心位置作为裂隙入口（固定行列）
                        local riftRow = math.ceil(Board.ROWS / 2)
                        local riftCol = math.ceil(Board.COLS / 2)
                        DarkWorldFlow.enterDarkWorld(riftRow, riftCol)
                    end,
                })
            end

            if G.dayCount == 6 then
                -- 第6天: 晨间事件完成后强制进入暗面，不走里程碑链
                StoryEventManager.tryMorningEvent(G.storyMgr, msCtx, afterMorningForDay6)
            else
                -- 其他天: 正常晨间事件 → 里程碑链
                StoryEventManager.tryMorningEvent(G.storyMgr, msCtx, tryMilestoneChain)
            end
        end)
        end)  -- Board.undealAll 结束
    end  -- doUndealAndAdvance 结束

    -- 触发夜谈: 对话结束后再进行 undeal 流程
    StoryEventManager.tryEveningEvent(G.storyMgr, eveningCtx, doUndealAndAdvance)
end

-- ============================================================================
-- 胜负判定
-- ============================================================================

function M.checkDefeat()
    if G.gamePhase ~= "playing" then return end
    local san    = ResourceBar.get("san")
    local health = ResourceBar.get("health")
    if san <= 0 or health <= 0 then
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
    local maxDays = getMaxDays()
    if G.dayCount > maxDays then
        -- 结局判定
        local ending = nil
        if G.storyMgr then
            local ctx = { dayCount = G.dayCount }
            ending = EndingSystem.judge(G.storyMgr, ctx)
        end

        local isVictory = ending and ending.isVictory ~= false or true
        G.gamePhase = "gameover"
        G.demoState = "idle"
        Token.setEmotion(G.token, isVictory and "happy" or "dead")
        AudioManager.playStinger(isVictory and "victory_sting" or "defeat_sting", 0.9)
        AudioManager.playBGM(isVictory and "victory" or "defeat", 2.0)
        AudioManager.stopAmbient()

        if isVictory then
            VFX.flashScreen(255, 215, 100, 0.5, 180)
        else
            VFX.flashScreen(180, 30, 30, 0.5, 200)
        end

        GameOver.show(isVictory, {
            daysSurvived  = maxDays,
            cardsRevealed = G.gameStats.cardsRevealed,
            monstersSlain = G.gameStats.monstersSlain,
            photosUsed    = G.gameStats.photosUsed,
        }, M.onGameRestart, ending)
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
    G.stepsUsed = 0
    G.gamePhase = "playing"
    G.gameStats.cardsRevealed = 0
    G.gameStats.dayStartRevealed = 0
    G.gameStats.monstersSlain = 0
    G.gameStats.photosUsed    = 0

    -- 重置 main.lua 特有的状态 (savedReality, bgTransition, cameraPan 等)
    resetMainState_()

    -- 故事系统重置
    if G.storyMgr then
        StoryManager.reset(G.storyMgr)
    end
    MilestoneManager.reset()
    StoryEventManager.reset()

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
    Board.generateCards(G.board, locs, { dayCount = G.dayCount, canHaveRift = G.dayCount > 1 and DarkWorld.canEnter() })
    CardTextures.preloadBoard(G.board, Board.ROWS, Board.COLS)
    Board.createAllNodes(G.board, scene_, CardTextures)
    recalcLayout_()

    Token.destroyNode(G.token)
    local token = Token.new()
    token.textures = Token.loadTextures()
    Token.createNode(token, scene_)
    G.token = token

    -- 重建白夜跟随精灵
    if G.baiye then Baiye.destroyNode(G.baiye) end
    local baiye = Baiye.new()
    baiye.texture = Baiye.loadTexture()
    Baiye.createNode(baiye, scene_)
    G.baiye = baiye

    -- 重置气泡对话
    local playerBubble = BubbleDialogue.newBubble()
    G.playerBubble = playerBubble

    AudioManager.playBGM("day_light", 2.0)
    -- Day 1 开场剧情 (重启后也播放)
    local morningCtx = { dayCount = G.dayCount }
    StoryEventManager.tryMorningEvent(G.storyMgr, morningCtx, function()
        M.startDeal()
    end)
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

    if not DarkWorld.canEnter() then
        local tc2 = Theme.current
        VFX.spawnBanner("🌀 裂隙出现... 灵感不足，暗面世界尚未开启",
            tc2.darkAccent.r, tc2.darkAccent.g, tc2.darkAccent.b, 16, 0.8)
        return false
    end

    G.demoState = "popup"
    CameraButton.hide()
    AudioManager.playSFX("popup_open")
    local tc2 = Theme.current
    VFX.spawnBanner("🌀 发现裂隙！", tc2.darkAccent.r, tc2.darkAccent.g, tc2.darkAccent.b, 18, 0.8)

    -- 在卡牌上显示裂隙 chibi
    local riftCard = G.board.cards[row] and G.board.cards[row][col]
    if riftCard then
        MonsterGhost.showRiftOnCard(riftCard)
    end

    local riftDelay = { t = 0 }
    Tween.to(riftDelay, { t = 1 }, 0.5, {
        tag = "riftconfirm",
        onComplete = function()
            local popCX = G.logicalW / 2
            local popCY = G.logicalH * 0.42
            EventPopup.showRiftConfirm(popCX, popCY,
                function()
                    MonsterGhost.clearCardGhosts()
                    G.enterDarkWorld(row, col)
                end,
                function()
                    MonsterGhost.clearCardGhosts()
                    G.demoState = "ready"
                    CameraButton.show()
                end
            )
        end,
    })
    return true
end

return M
