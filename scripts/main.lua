-- ============================================================================
-- main.lua - 暗面都市 · 入口
-- NanoVG Mode B (系统逻辑分辨率 + DPR)
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local Tween       = require "lib.Tween"
local VFX         = require "lib.VFX"
local Theme       = require "Theme"
local Card        = require "Card"
local Board       = require "Board"
local Token       = require "Token"
local ResourceBar = require "ResourceBar"
local EventPopup  = require "EventPopup"
local CameraButton = require "CameraButton"
local TitleScreen = require "TitleScreen"
local GameOver    = require "GameOver"
local ShopPopup    = require "ShopPopup"
local CardManager      = require "CardManager"
local HandPanel        = require "HandPanel"
local DateTransition   = require "DateTransition"

-- ---------------------------------------------------------------------------
-- 全局变量
-- ---------------------------------------------------------------------------
---@type userdata NanoVG context
local vg = nil
local fontSans = -1

-- 分辨率 (Mode B)
local physW, physH = 0, 0
local dpr = 1.0
local logicalW, logicalH = 0, 0

-- 游戏时间
local gameTime = 0

-- F4: 前置声明 (回调注入需要引用)
local handleInventoryExorcism

-- 模块实例
---@type BoardData
local board = nil
---@type table token
local token = nil
local emotionHandles = nil  -- Token 表情贴图句柄 (全局共享)

-- 交互状态
-- idle | dealing | ready | flipping | moving | popup | photographing | exorcising
local demoState = "idle"

-- Hover 追踪
local hoveredCard = nil

-- 日期
local dayCount = 1
local MAX_DAYS = 3  -- 存活目标天数

-- 游戏阶段: "title" | "playing" | "gameover"
local gamePhase = "title"

-- 统计
local gameStats = {
    cardsRevealed = 0,
    monstersSlain = 0,
    photosUsed    = 0,
}

-- ============================================================================
-- 分辨率计算
-- ============================================================================

local function recalcResolution()
    local graphics = GetGraphics()
    physW = graphics:GetWidth()
    physH = graphics:GetHeight()
    dpr = graphics:GetDPR()
    logicalW = physW / dpr
    logicalH = physH / dpr
    print(string.format("[Main] Resolution: %dx%d, DPR=%.1f, Logical=%.0fx%.0f",
        physW, physH, dpr, logicalW, logicalH))
end

-- ============================================================================
-- 布局
-- ============================================================================

local function recalcLayout()
    if board then
        local boardCX = logicalW * 0.45
        local boardCY = logicalH * 0.48
        Board.recalcLayout(board, boardCX, boardCY)
    end
    CameraButton.recalcLayout(logicalW, logicalH)
end

-- ============================================================================
-- 初始化
-- ============================================================================

function Start()
    SampleStart()
    SampleInitMouseMode(MM_FREE)

    -- NanoVG 上下文
    vg = nvgCreate(1)
    if not vg then
        print("[Main] ERROR: Failed to create NanoVG context")
        return
    end
    print("[Main] NanoVG context created")

    -- 字体
    fontSans = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    if fontSans == -1 then
        print("[Main] ERROR: Failed to load font")
    else
        print("[Main] Font loaded: sans = " .. fontSans)
    end

    -- 分辨率
    recalcResolution()

    -- 主题
    Theme.init("bright")

    -- 资源
    ResourceBar.init()

    -- 棋盘
    board = Board.new()
    local reqLocs = CardManager.preSelectLocations()
    Board.generateCards(board, reqLocs)
    recalcLayout()

    -- Token + 表情贴图
    emotionHandles = Token.loadImages(vg)
    token = Token.new()
    token.imageHandles = emotionHandles

    -- 注入传闻查询到 Card (避免循环依赖)
    Card.setRumorQuery(function(location)
        return CardManager.getRumorFor(location)
    end)

    -- 注入"结束今天"回调到 HandPanel
    HandPanel.setEndDayCallback(function()
        advanceDay()
    end)

    -- 注入"使用驱魔香"回调到 HandPanel (F4)
    HandPanel.setUseExorcismCallback(function()
        handleInventoryExorcism()
    end)

    -- 注入"地图碎片"回调到 ShopPopup (购买后随机揭示一张未翻开卡牌)
    ShopPopup.setMapRevealCallback(function()
        if not board or not board.cards then return end
        -- 收集所有未翻开的卡牌
        local hidden = {}
        for r = 1, Board.ROWS do
            for c = 1, Board.COLS do
                local cd = board.cards[r] and board.cards[r][c]
                if cd and not cd.faceUp and not cd.isFlipping and not cd.revealed then
                    hidden[#hidden + 1] = cd
                end
            end
        end
        if #hidden == 0 then
            VFX.spawnBanner("没有可揭示的卡牌", 180, 180, 180, 16, 0.6)
            return
        end
        -- 随机选一张，标记为"已揭示类型"
        local pick = hidden[math.random(1, #hidden)]
        pick.revealed = true  -- Card.draw 可用此标记显示类型提示
        local cx, cy = Board.cardPos(board, pick.row, pick.col)
        local tc = Theme.cardTypeColor(pick.type)
        VFX.spawnBurst(cx, cy, 8, tc.r, tc.g, tc.b)
        VFX.spawnBanner("🗺️ 揭示了一张卡牌!", tc.r, tc.g, tc.b, 18, 0.8)
        print(string.format("[Main] Map revealed card at (%d,%d) type=%s", pick.row, pick.col, pick.type))
    end)

    -- 注入"相机模式"进入/退出回调 (自动翻开/翻回已侦察卡牌)
    CameraButton.setOnEnterCallback(function()
        if not board or not board.cards then return end
        for r = 1, Board.ROWS do
            for c = 1, Board.COLS do
                local cd = board.cards[r] and board.cards[r][c]
                if cd and cd.scouted and not cd.faceUp and not cd.isFlipping then
                    -- 快速翻开动画 (scaleX 0 → 1)
                    cd.faceUp = true
                    cd.scaleX = 0
                    Tween.to(cd, { scaleX = 1.0 }, 0.2, {
                        easing = Tween.Easing.easeOutBack,
                        tag = "cameramode",
                    })
                end
            end
        end
    end)

    CameraButton.setOnExitCallback(function()
        if not board or not board.cards then return end
        for r = 1, Board.ROWS do
            for c = 1, Board.COLS do
                local cd = board.cards[r] and board.cards[r][c]
                if cd and cd.scouted and cd.faceUp and not cd.isFlipping then
                    -- 快速翻回动画 (scaleX → 0 → 1)
                    Tween.to(cd, { scaleX = 0 }, 0.1, {
                        easing = Tween.Easing.easeInQuad,
                        tag = "cameramode",
                        onComplete = function()
                            cd.faceUp = false
                            Tween.to(cd, { scaleX = 1.0 }, 0.15, {
                                easing = Tween.Easing.easeOutBack,
                                tag = "cameramode",
                            })
                        end
                    })
                end
            end
        end
    end)

    -- 日期转场初始化
    DateTransition.init(vg)

    -- 事件
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")

    -- 显示标题画面 (不直接发牌)
    gamePhase = "title"
    demoState = "idle"
    TitleScreen.show(function()
        -- 标题画面关闭后: 播放第一天日期转场，然后开始游戏
        gamePhase = "playing"
        DateTransition.play(dayCount, function()
            startDeal()
        end)
    end)

    print("[Main] Initialization complete")
end

function Stop()
    if vg then
        nvgDelete(vg)
        vg = nil
    end
end

-- ============================================================================
-- 发牌 / 收牌 / 日期流程
-- ============================================================================

function startDeal()
    demoState = "dealing"
    VFX.spawnBanner("第 " .. dayCount .. " 天", 255, 255, 255, 28, 1.2)

    Board.dealAll(board, function()
        demoState = "ready"
        print("[Main] Deal complete, Day " .. dayCount)

        -- Token 出现在"家"的位置
        local homeRow = board.homeRow
        local homeCol = board.homeCol
        local cx, cy = Board.cardPos(board, homeRow, homeCol)
        Token.show(token, cx, cy)
        token.targetRow = homeRow
        token.targetCol = homeCol

        -- 家的卡牌默认翻开 (安全起始点)
        local homeCard = board.cards[homeRow][homeCol]
        if homeCard and not homeCard.faceUp then
            homeCard.faceUp = true
        end

        -- 生成日程卡和传闻卡
        CardManager.generateDaily(board)

        -- 显示手牌面板和相机按钮
        HandPanel.show(logicalH)
        CameraButton.show()
    end)
end

function startRedeal()
    if gamePhase ~= "playing" then return end
    if demoState == "dealing" then return end
    if EventPopup.isActive() or CameraButton.isActive() or ShopPopup.isActive() then return end
    demoState = "dealing"
    hoveredCard = nil
    Tween.cancelTag("cardflip")
    Tween.cancelTag("carddeal")
    Tween.cancelTag("cardshake")
    Tween.cancelTag("cardtransform")
    Tween.cancelTag("tokenmove")
    Tween.cancelTag("token")
    Tween.cancelTag("popup")
    Tween.cancelTag("camerabtn")
    Tween.cancelTag("cameramode")
    Tween.cancelTag("camerabtn_shake")
    Tween.cancelTag("shoppopup")
    Tween.cancelTag("shoppopup_card")
    Tween.cancelTag("shoppopup_flash")
    Tween.cancelTag("handpanel")

    -- 隐藏 token、手牌面板和相机按钮
    token.visible = false
    token.alpha = 0
    HandPanel.hide()
    CameraButton.hide()

    Board.undealAll(board, function()
        -- 重新生成
        local locs = CardManager.preSelectLocations()
        Board.generateCards(board, locs)
        recalcLayout()
        startDeal()
    end)
end

-- 前向声明 (定义在"胜负判定"章节)
local checkVictory

function advanceDay()
    if gamePhase ~= "playing" then return end
    if demoState ~= "ready" then return end
    if EventPopup.isActive() or CameraButton.isActive() or ShopPopup.isActive() then return end

    -- 收起笔记本
    HandPanel.hide()

    -- 日程卡日结算 (奖励/惩罚)
    CardManager.settleDay()

    -- 每日结算: 回家恢复理智 +1, 秩序 +1
    ResourceBar.change("san", 1)
    ResourceBar.change("order", 1)

    -- 每日重置: 胶卷恢复为 3
    local currentFilm = ResourceBar.get("film")
    if currentFilm < 3 then
        ResourceBar.change("film", 3 - currentFilm)
    end

    -- 每日基础收入
    ResourceBar.change("money", 10)

    -- 日结过渡: P4 风格日期转场
    demoState = "dealing"
    hoveredCard = nil

    Tween.cancelTag("cardflip")
    Tween.cancelTag("cardshake")

    -- 隐藏 token、手牌面板和相机按钮
    token.visible = false
    token.alpha = 0
    HandPanel.hide()
    CameraButton.hide()

    -- 先收牌，然后播放日期转场
    Board.undealAll(board, function()
        dayCount = dayCount + 1

        -- 胜利检查
        if checkVictory() then return end

        -- 播放 P4 日期转场
        DateTransition.play(dayCount, function()
            -- 转场结束后重新发牌
            local locs = CardManager.preSelectLocations()
            Board.generateCards(board, locs)
            recalcLayout()
            startDeal()
        end)
    end)
end

-- ============================================================================
-- 胜负判定
-- ============================================================================

--- 检查资源是否触发失败
local function checkDefeat()
    if gamePhase ~= "playing" then return end
    local san   = ResourceBar.get("san")
    local order = ResourceBar.get("order")
    if san <= 0 or order <= 0 then
        -- 延迟一帧，等资源动画播完
        local delay = { t = 0 }
        Tween.to(delay, { t = 1 }, 0.8, {
            tag = "gameover",
            onComplete = function()
                gamePhase = "gameover"
                demoState = "idle"
                Token.setEmotion(token, "dead")
                CameraButton.hide()
                VFX.triggerShake(8, 0.4, 20)
                VFX.flashScreen(180, 30, 30, 0.5, 200)
                GameOver.show(false, {
                    daysSurvived  = dayCount,
                    cardsRevealed = gameStats.cardsRevealed,
                    monstersSlain = gameStats.monstersSlain,
                    photosUsed    = gameStats.photosUsed,
                }, onGameRestart)
            end
        })
    end
end

--- 检查胜利：存活到第 MAX_DAYS 天结束
checkVictory = function()
    if gamePhase ~= "playing" then return false end
    if dayCount > MAX_DAYS then
        gamePhase = "gameover"
        demoState = "idle"
        Token.setEmotion(token, "happy")
        VFX.flashScreen(255, 215, 100, 0.5, 180)
        GameOver.show(true, {
            daysSurvived  = MAX_DAYS,
            cardsRevealed = gameStats.cardsRevealed,
            monstersSlain = gameStats.monstersSlain,
            photosUsed    = gameStats.photosUsed,
        }, onGameRestart)
        return true
    end
    return false
end

--- 重新开始回调 (GameOver 按钮)
function onGameRestart()
    -- 清理一切
    Tween.cancelAll()
    VFX.resetAll()
    hoveredCard = nil

    -- 重置状态
    dayCount = 1
    gamePhase = "playing"
    gameStats.cardsRevealed = 0
    gameStats.monstersSlain = 0
    gameStats.photosUsed    = 0

    -- 重置资源
    ResourceBar.reset()

    -- 重置日程/传闻/手牌面板/道具库存
    CardManager.reset()
    HandPanel.reset()
    ShopPopup.resetInventory()

    -- 重置棋盘
    local locs = CardManager.preSelectLocations()
    Board.generateCards(board, locs)
    recalcLayout()

    -- 重置 token (复用已加载的贴图句柄)
    token = Token.new()
    token.imageHandles = emotionHandles

    -- 开始发牌
    startDeal()
end

-- ============================================================================
-- 弹窗关闭回调 — 在此时才执行资源结算
-- ============================================================================

local function onPopupDismissed(cardType, effects)
    -- === 护身符检查：monster/trap 伤害可被抵消 ===
    if effects and #effects > 0 and (cardType == "monster" or cardType == "trap") then
        if ShopPopup.useItem("shield") then
            -- 抵消全部伤害
            Token.setEmotion(token, "relieved")
            local tc = Theme.current
            VFX.spawnBanner("🧿 护身符抵消了伤害!", tc.safe.r, tc.safe.g, tc.safe.b, 18, 1.0)
            VFX.flashScreen(100, 180, 255, 0.3, 120)
            effects = {}  -- 清空伤害效果
            print("[Main] Shield absorbed damage from " .. cardType)
        end
    end

    -- 资源结算
    if effects then
        for _, eff in ipairs(effects) do
            ResourceBar.change(eff[1], eff[2])
        end
    end

    -- 统计
    gameStats.cardsRevealed = gameStats.cardsRevealed + 1

    -- F7: 线索事件触发额外传闻
    local gotRumor = false
    if cardType == "clue" then
        local added = CardManager.addRumor(board)
        if added then
            gotRumor = true
            local tc2 = Theme.current
            VFX.spawnBanner("📰 获得了新传闻!", tc2.rumor.r, tc2.rumor.g, tc2.rumor.b, 18, 0.8)
        end
    end

    -- 恢复交互 — 正面事件显示开心
    local positiveTypes = { clue = true, safe = true, home = true, landmark = true }
    if positiveTypes[cardType] or gotRumor then
        Token.setEmotion(token, "happy")
    else
        Token.setEmotion(token, "default")
    end
    demoState = "ready"
    CameraButton.show()
    print("[Main] Popup dismissed, effects applied for: " .. tostring(cardType))

    -- 败北检查 (资源结算后)
    checkDefeat()
end

-- ============================================================================
-- 翻牌完成 → 进入弹窗
-- ============================================================================

--- 普通翻牌回调 (移动到位后翻牌，或当前位置翻牌)
local function onCardFlipped(card, targetX, targetY)
    -- 地标光环：如果在光环范围内，怪物/陷阱自动变安全
    if Board.isInLandmarkAura(board, card.row, card.col) then
        if card.type == "monster" or card.type == "trap" then
            card.type = "safe"
            print("[Main] Landmark aura neutralized danger at (" .. card.row .. "," .. card.col .. ")")
        end
    end

    -- 日程完成检测: 到达此地点，标记对应日程
    if card.location then
        local anyCompleted = CardManager.checkArrival(card.location)
        if anyCompleted then
            local sc = Theme.current.completed
            VFX.spawnBanner("日程完成!", sc.r, sc.g, sc.b, 20, 0.8)
        end
    end

    local tc = Theme.cardTypeColor(card.type)

    -- 粒子
    VFX.spawnBurst(targetX, targetY, 10, tc.r, tc.g, tc.b)

    -- 表情切换
    local emotionMap = {
        monster = "scared", trap = "nervous", shop = "confused",
        clue = "surprised", home = "relieved", landmark = "relieved",
        safe = "relieved",
    }
    Token.setEmotion(token, emotionMap[card.type] or "default")

    -- === 安全区 (home/landmark): 不弹事件弹窗，直接安全通过 ===
    if card.type == "home" or card.type == "landmark" then
        local locInfo = Card.LOCATION_INFO[card.location]
        local safeName = locInfo and locInfo.label or "安全区"
        local sc = Theme.current.safe
        VFX.spawnBanner(safeName .. " · 安全", sc.r, sc.g, sc.b, 18, 0.8)
        gameStats.cardsRevealed = gameStats.cardsRevealed + 1
        demoState = "ready"
        CameraButton.show()
        print("[Main] Safe zone: " .. card.type .. " at (" .. card.row .. "," .. card.col .. ")")
        return
    end

    -- 屏幕震动 (仅非安全区)
    VFX.triggerShake(3, 0.15)

    -- 延迟后弹出事件弹窗
    demoState = "popup"
    hoveredCard = nil

    local popupDelay = { t = 0 }
    Tween.to(popupDelay, { t = 1 }, 0.4, {
        tag = "popup_delay",
        onComplete = function()
            local popCX = logicalW / 2
            local popCY = logicalH * 0.42
            if card.type == "shop" then
                -- 商店卡：专用弹窗，购买时实时结算，关闭时仅恢复状态
                ShopPopup.show(popCX, popCY, function()
                    gameStats.cardsRevealed = gameStats.cardsRevealed + 1
                    Token.setEmotion(token, "happy")
                    demoState = "ready"
                    print("[Main] ShopPopup dismissed")
                    checkDefeat()
                end)
            else
                EventPopup.show(card.type, popCX, popCY, onPopupDismissed, card.location)
            end
        end
    })
end

--- 拍摄翻牌回调 (仅预览，不结算资源; 关闭弹窗后翻回并标记侦察)
local function onPhotographFlipped(card, targetX, targetY)
    local tc = Theme.cardTypeColor(card.type)

    VFX.spawnBurst(targetX, targetY, 8, tc.r, tc.g, tc.b)
    VFX.triggerShake(2, 0.1)

    -- 延迟后弹出预览弹窗 (不结算资源)
    demoState = "popup"
    hoveredCard = nil

    local popupDelay = { t = 0 }
    Tween.to(popupDelay, { t = 1 }, 0.4, {
        tag = "popup_delay",
        onComplete = function()
            local popCX = logicalW / 2
            local popCY = logicalH * 0.42
            -- 相片风格预览弹窗：不结算资源
            EventPopup.showPhoto(card.type, popCX, popCY, function(_cardType, _effects)
                gameStats.cardsRevealed = gameStats.cardsRevealed + 1

                -- 侦察完成：翻回卡牌 (scaleX 动画模拟翻回)
                card.scouted = true
                Tween.to(card, { scaleX = 0 }, 0.12, {
                    easing = Tween.Easing.easeInQuad,
                    tag = "cardflip",
                    onComplete = function()
                        card.faceUp = false  -- 翻回地点面
                        Tween.to(card, { scaleX = 1.0 }, 0.2, {
                            easing = Tween.Easing.easeOutBack,
                            tag = "cardflip",
                        })
                    end
                })

                Token.setEmotion(token, "happy")
                demoState = "ready"
                CameraButton.show()
                print("[Main] Photograph scouted: " .. tostring(_cardType) .. " at (" .. card.row .. "," .. card.col .. ")")
            end, card.location)
        end
    })
end

-- ============================================================================
-- 相机模式操作: 拍摄 / 驱除
-- ============================================================================

--- 执行拍摄 (远程翻牌，仅预览不结算资源)
local function doPhotograph(card, row, col)
    local targetX, targetY = Board.cardPos(board, row, col)

    ResourceBar.change("film", -1)
    gameStats.photosUsed = gameStats.photosUsed + 1

    demoState = "photographing"
    CameraButton.hide()
    Token.setEmotion(token, "determined")

    -- 快门闪光 (白色)
    VFX.flashScreen(255, 255, 255, 0.3, 180)

    -- Token 拍照姿势 (原地轻微跳跃)
    local origY = token.y
    Tween.to(token, { y = origY - 5 }, 0.1, {
        easing = Tween.Easing.easeOutQuad,
        tag = "tokenmove",
        onComplete = function()
            Tween.to(token, { y = origY }, 0.15, {
                easing = Tween.Easing.easeInQuad,
                tag = "tokenmove",
            })
        end
    })

    -- 延迟后翻牌
    local delay = { t = 0 }
    Tween.to(delay, { t = 1 }, 0.25, {
        tag = "photograph",
        onComplete = function()
            if not card.faceUp and not card.isFlipping then
                demoState = "flipping"
                Card.flip(card, function(c)
                    onPhotographFlipped(c, targetX, targetY)
                end)
            else
                Token.setEmotion(token, "default")
                demoState = "ready"
                CameraButton.show()
            end
        end
    })
end

--- 执行驱除 (怪物 → 相片)
local function doExorcise(card, row, col, freeExorcise)
    local targetX, targetY = Board.cardPos(board, row, col)

    -- === 资源消耗 ===
    if freeExorcise then
        -- 从工具栏使用驱魔香，库存已在外部扣除
        VFX.spawnBanner("🪔 驱魔香驱除!", Theme.current.safe.r, Theme.current.safe.g, Theme.current.safe.b, 16, 0.8)
        print("[Main] Exorcise with incense (toolbar)")
    elseif ShopPopup.useItem("exorcism") then
        VFX.spawnBanner("🪔 驱魔香免费驱除!", Theme.current.safe.r, Theme.current.safe.g, Theme.current.safe.b, 16, 0.8)
        print("[Main] Exorcise with incense (free)")
    else
        ResourceBar.change("film", -1)
    end
    gameStats.photosUsed    = gameStats.photosUsed + 1
    gameStats.monstersSlain = gameStats.monstersSlain + 1

    demoState = "exorcising"
    CameraButton.hide()
    Token.setEmotion(token, "angry")

    -- 紫色闪光
    local pc = Theme.color("plot")
    VFX.flashScreen(pc.r, pc.g, pc.b, 0.35, 150)
    VFX.triggerShake(4, 0.2)

    -- Token 拍照姿势
    local origY = token.y
    Tween.to(token, { y = origY - 6 }, 0.12, {
        easing = Tween.Easing.easeOutQuad,
        tag = "tokenmove",
        onComplete = function()
            Tween.to(token, { y = origY }, 0.18, {
                easing = Tween.Easing.easeInQuad,
                tag = "tokenmove",
            })
        end
    })

    -- 延迟后变形
    local delay = { t = 0 }
    Tween.to(delay, { t = 1 }, 0.3, {
        tag = "exorcise",
        onComplete = function()
            Card.transformTo(card, "photo", function(c)
                VFX.spawnBurst(targetX, targetY, 16, pc.r, pc.g, pc.b)
                VFX.spawnBanner("驱除成功!", pc.r, pc.g, pc.b, 24, 1.0)
                Token.setEmotion(token, "happy")
                demoState = "ready"
                CameraButton.show()
                print("[Main] Exorcise complete at (" .. row .. "," .. col .. ")")
            end)
        end
    })
end

-- ---------------------------------------------------------------------------
-- F4: 从工具栏使用驱魔香 (免侦察驱除当前格子怪物)
-- ---------------------------------------------------------------------------

handleInventoryExorcism = function()
    if demoState ~= "ready" then return end

    -- 扣库存
    if not ShopPopup.useItem("exorcism") then
        VFX.spawnBanner("没有驱魔香!", 220, 80, 80, 18, 0.7)
        return
    end

    -- 当前所在格子
    local row, col = token.targetRow, token.targetCol
    local card = board.cards[row] and board.cards[row][col]

    if not card then
        -- 不该发生，退还
        ShopPopup.addItem("exorcism", 1)
        VFX.spawnBanner("无效位置", 180, 180, 180, 16, 0.6)
        return
    end

    -- 检查当前格子是否有已翻开的怪物
    if card.faceUp and card.type == "monster" then
        -- 直接驱除 (freeExorcise = true，库存已扣)
        doExorcise(card, row, col, true)
    else
        -- 当前格子不是已翻开的怪物 → 退还驱魔香
        ShopPopup.addItem("exorcism", 1)
        if not card.faceUp then
            VFX.spawnBanner("需要先翻开卡牌!", 220, 160, 80, 16, 0.7)
        else
            VFX.spawnBanner("当前格子没有怪物", 180, 180, 180, 16, 0.6)
        end
    end
end

-- ============================================================================
-- 交互处理
-- ============================================================================

--- 检查两个格子是否相邻 (上下左右)
local function isAdjacent(r1, c1, r2, c2)
    local dr = math.abs(r1 - r2)
    local dc = math.abs(c1 - c2)
    return (dr + dc) == 1  -- 曼哈顿距离为1 = 相邻
end

--- 普通模式点击处理 (只能移动到相邻格子)
local function handleNormalModeClick(lx, ly)
    local card, row, col = Board.hitTest(board, lx, ly)
    if not card then return end

    local targetX, targetY = Board.cardPos(board, row, col)
    local tokenTargetY = targetY
    local isCurrent = (token.targetRow == row and token.targetCol == col)

    -- === 当前位置：翻牌 / 抖动 ===
    if isCurrent then
        if not card.faceUp and not card.isFlipping then
            demoState = "flipping"
            CameraButton.hide()
            Card.flip(card, function(c)
                onCardFlipped(c, targetX, targetY)
            end)
        else
            Card.shake(card)
        end
        return
    end

    -- === 相邻检查：只能移动到上下左右相邻的格子 ===
    if not isAdjacent(token.targetRow, token.targetCol, row, col) then
        Card.shake(card)
        VFX.spawnBanner("只能移动到相邻格子", 180, 180, 180, 16, 0.6)
        return
    end

    -- === 相邻格子：移动 ===
    demoState = "moving"
    CameraButton.hide()
    token.targetRow = row
    token.targetCol = col
    Token.setEmotion(token, "running")

    Token.moveTo(token, targetX, tokenTargetY, function()
        -- 到达后：未翻开 → 翻牌+弹窗; 已翻开 → 检查日程后 ready
        if not card.faceUp and not card.isFlipping then
            demoState = "flipping"
            Card.flip(card, function(c)
                onCardFlipped(c, targetX, targetY)
            end)
        else
            -- 已翻开的卡：地点仍然有效，检查日程完成
            if card.location then
                local anyCompleted = CardManager.checkArrival(card.location)
                if anyCompleted then
                    local sc = Theme.current.completed
                    VFX.spawnBanner("日程完成!", sc.r, sc.g, sc.b, 20, 0.8)
                end
            end
            Token.setEmotion(token, "default")
            demoState = "ready"
            CameraButton.show()
        end
    end)
end

--- 相机模式点击处理 (拍摄 / 驱除)
local function handleCameraModeClick(lx, ly)
    -- 点击相机按钮本身 → 由外层已处理 (退出相机模式)

    local card, row, col = Board.hitTest(board, lx, ly)
    if not card then return end

    -- 检查胶卷 (驱除和拍摄都需要，查看相片不需要)
    local film = ResourceBar.get("film")

    -- 已翻开的怪物 → 驱除 (优先于查看相片，解决 scouted 怪物的冲突)
    if card.faceUp and card.type == "monster" and not card.isFlipping then
        if film <= 0 then
            CameraButton.shakeNoFilm()
            VFX.spawnBanner("胶卷不足!", 220, 80, 80, 22, 0.8)
            return
        end
        CameraButton.exitCameraMode(function()
            doExorcise(card, row, col)
        end)
        return
    end

    -- 已侦察过的非怪物卡牌 → 重新查看相片 (不消耗胶卷)
    if card.scouted and card.faceUp and not card.isFlipping then
        demoState = "popup"
        hoveredCard = nil
        local popCX = logicalW / 2
        local popCY = logicalH * 0.42
        EventPopup.showPhoto(card.type, popCX, popCY, function()
            Token.setEmotion(token, "default")
            demoState = "ready"
        end, card.location)
        return
    end

    if film <= 0 then
        CameraButton.shakeNoFilm()
        VFX.spawnBanner("胶卷不足!", 220, 80, 80, 22, 0.8)
        return
    end

    if not card.faceUp and not card.isFlipping then
        -- 未翻开 → 拍摄 (远程翻牌预览)
        CameraButton.exitCameraMode(function()
            doPhotograph(card, row, col)
        end)
    else
        -- 已翻开的非怪物 → 无法拍摄
        Card.shake(card)
        VFX.spawnBanner("无法拍摄", 180, 180, 180, 20, 0.6)
    end
end

local function handleClick(inputX, inputY)
    -- 转换到逻辑坐标 (Mode B)
    local lx = inputX / dpr
    local ly = inputY / dpr

    -- 日期转场期间阻止交互
    if DateTransition.isActive() then return end

    -- 标题画面最优先
    if TitleScreen.isActive() then
        TitleScreen.handleClick()
        return
    end

    -- 结算画面
    if GameOver.isActive() then
        GameOver.handleClick(lx, ly, logicalW, logicalH)
        return
    end

    -- 弹窗优先处理
    if ShopPopup.isActive() then
        ShopPopup.handleClick(lx, ly)
        return
    end

    if EventPopup.isActive() then
        EventPopup.handleClick(lx, ly)
        return
    end

    -- 手牌面板点击 (标签栏总可点击；展开时优先消费全面板)
    if HandPanel.isActive() then
        local handConsumed = HandPanel.handleClick(lx, ly, logicalW, logicalH)
        if handConsumed then return end
    end

    -- 相机按钮点击 (优先于棋盘)
    local consumed, reason = CameraButton.handleClick(lx, ly)
    if consumed then
        if reason == "no_film" then
            VFX.spawnBanner("胶卷不足!", 220, 80, 80, 22, 0.8)
        end
        return
    end

    if gamePhase ~= "playing" then return end
    if demoState ~= "ready" then return end

    -- 根据相机模式分流处理
    if CameraButton.isActive() then
        handleCameraModeClick(lx, ly)
    else
        handleNormalModeClick(lx, ly)
    end
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    local button = eventData:GetInt("Button")
    if button ~= MOUSEB_LEFT then return end
    local mousePos = input:GetMousePosition()
    handleClick(mousePos.x, mousePos.y)
end

---@param eventType string
---@param eventData TouchBeginEventData
function HandleTouchBegin(eventType, eventData)
    local tx = eventData:GetInt("X")
    local ty = eventData:GetInt("Y")
    handleClick(tx, ty)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData:GetInt("Key")

    -- 日期转场期间阻止按键
    if DateTransition.isActive() then return end

    -- 标题画面
    if TitleScreen.isActive() then
        TitleScreen.handleKey(key)
        return
    end

    -- 结算画面
    if GameOver.isActive() then
        GameOver.handleKey(key)
        return
    end

    -- 商店弹窗
    if ShopPopup.isActive() then
        ShopPopup.handleKey(key)
        return
    end

    -- 事件弹窗
    if EventPopup.isActive() then
        if key == KEY_RETURN or key == KEY_SPACE then
            EventPopup.dismiss()
        end
        return
    end

    -- 相机模式激活时，Escape 退出
    if CameraButton.isActive() then
        if key == KEY_ESCAPE then
            CameraButton.exitCameraMode()
        end
        -- 相机模式中屏蔽其他按键
        return
    end

    if gamePhase ~= "playing" then return end

    if key == KEY_ESCAPE then
        engine:Exit()
    end
end

-- ============================================================================
-- Hover 追踪
-- ============================================================================

local function updateHover(dt)
    local mousePos = input:GetMousePosition()
    local lx = mousePos.x / dpr
    local ly = mousePos.y / dpr

    -- 结算画面按钮 hover
    GameOver.updateHover(lx, ly, dt, logicalW, logicalH)

    -- 弹窗/按钮/面板 hover
    ShopPopup.updateHover(lx, ly, dt)
    EventPopup.updateHover(lx, ly, dt)
    CameraButton.updateHover(lx, ly, dt)
    HandPanel.updateHover(lx, ly, dt, logicalW, logicalH)

    -- 非游戏阶段 或 非 ready 状态不追踪卡牌 hover
    if gamePhase ~= "playing" or demoState ~= "ready" then
        hoveredCard = nil
    else
        local card = Board.hitTest(board, lx, ly)
        -- 相机模式下：仅高亮可操作目标 (未翻开 or 怪物)
        if CameraButton.isActive() and card then
            if card.faceUp and card.type ~= "monster" then
                card = nil  -- 非可操作目标不高亮
            end
        end
        hoveredCard = card
    end

    -- 平滑过渡所有卡牌的 hoverT
    if not board or not board.cards then return end
    for row = 1, Board.ROWS do
        if board.cards[row] then
            for col = 1, Board.COLS do
                local card = board.cards[row][col]
                if card then
                    local target = (card == hoveredCard) and 1.0 or 0.0
                    card.hoverT = card.hoverT + (target - card.hoverT) * math.min(1, dt * 12)
                    if math.abs(card.hoverT - target) < 0.005 then
                        card.hoverT = target
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 更新
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData:GetFloat("TimeStep")
    gameTime = gameTime + dt

    Tween.update(dt)
    VFX.updateAll(dt)
    DateTransition.update(dt)
    Board.update(board, dt)
    Token.update(token, dt)
    ResourceBar.update(dt)
    CameraButton.update(dt)
    updateHover(dt)
end

-- ============================================================================
-- 渲染
-- ============================================================================

function HandleNanoVGRender(eventType, eventData)
    if not vg then return end

    VFX.setContext(vg, logicalW, logicalH, gameTime)

    nvgBeginFrame(vg, logicalW, logicalH, dpr)

    -- 屏幕抖动
    local sx, sy = VFX.getShakeOffset()
    if sx ~= 0 or sy ~= 0 then
        nvgTranslate(vg, sx, sy)
    end

    -- === 背景渐变 ===
    drawBackground()

    -- === 棋盘 + 卡牌 ===
    Board.draw(vg, board, gameTime)

    -- === Token ===
    Token.draw(vg, token, gameTime)

    -- === 相机模式取景器叠加层 (在 Token 后, VFX 前) ===
    CameraButton.drawOverlay(vg, logicalW, logicalH, gameTime)

    -- === VFX 叠加层 ===
    VFX.drawBurst()
    VFX.drawPopups()
    VFX.drawBanners()
    VFX.drawTransition()

    -- === 资源栏 ===
    ResourceBar.draw(vg, logicalW, logicalH)

    -- === 手牌面板 ===
    HandPanel.draw(vg, logicalW, logicalH, gameTime)

    -- === HUD ===
    drawHUD()

    -- === 相机按钮 (HUD 后, Flash 前) ===
    CameraButton.draw(vg, logicalW, logicalH, gameTime)

    -- === 屏幕闪光 (覆盖所有内容) ===
    VFX.drawFlash()

    -- === 事件弹窗 / 商店弹窗 ===
    EventPopup.draw(vg, logicalW, logicalH, gameTime)
    ShopPopup.draw(vg, logicalW, logicalH, gameTime)

    -- === 结算画面 (覆盖游戏内容) ===
    GameOver.draw(vg, logicalW, logicalH, gameTime)

    -- === P4 日期转场 (覆盖游戏内容，在标题画面下) ===
    DateTransition.draw(vg, logicalW, logicalH, gameTime)

    -- === 标题画面 (最顶层) ===
    TitleScreen.draw(vg, logicalW, logicalH, gameTime)

    nvgEndFrame(vg)
end

-- ============================================================================
-- 背景
-- ============================================================================

function drawBackground()
    local t = Theme.current

    -- 天空渐变
    nvgBeginPath(vg)
    nvgRect(vg, -20, -20, logicalW + 40, logicalH + 40)
    local bgPaint = nvgLinearGradient(vg, 0, 0, 0, logicalH,
        Theme.rgba(t.bgTop), Theme.rgba(t.bgBottom))
    nvgFillPaint(vg, bgPaint)
    nvgFill(vg)

    -- 装饰云朵
    local cloudAlpha = 50
    for i = 1, 4 do
        local cx = (logicalW * 0.15 * i + gameTime * (5 + i * 2)) % (logicalW + 100) - 50
        local cy = logicalH * (0.08 + i * 0.05)
        local cw = 60 + i * 15
        local ch = 18 + i * 4

        nvgBeginPath(vg)
        nvgEllipse(vg, cx, cy, cw, ch)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, cloudAlpha))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgEllipse(vg, cx - cw * 0.3, cy - ch * 0.5, cw * 0.4, ch * 0.7)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, cloudAlpha - 10))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgEllipse(vg, cx + cw * 0.25, cy - ch * 0.35, cw * 0.35, ch * 0.6)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, cloudAlpha - 15))
        nvgFill(vg)
    end
end

-- ============================================================================
-- HUD
-- ============================================================================

function drawHUD()
    local t = Theme.current

    -- 天数/回合 (右上角)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, t.fontSize.subtitle)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, Theme.rgba(t.textPrimary))
    nvgText(vg, logicalW - 20, 16, "第 " .. dayCount .. " 天", nil)
end

-- ============================================================================
-- 屏幕变化
-- ============================================================================

function HandleScreenMode(eventType, eventData)
    recalcResolution()
    recalcLayout()
    print("[Main] Screen mode changed")
end
