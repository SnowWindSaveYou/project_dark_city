-- ============================================================================
-- main.lua - 暗面都市 · 入口 (3D 版本)
-- 混合渲染: 3D Viewport (棋盘/卡牌/桌面) + NanoVG 叠加层 (HUD/弹窗)
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local Tween       = require "lib.Tween"
local VFX         = require "lib.VFX"
local Theme       = require "Theme"
local Card        = require "Card"
local Board       = require "Board"
local Token       = require "Token"
local CardTextures = require "CardTextures"
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
---@type userdata NanoVG context (HUD 叠加层)
local vg = nil
local fontSans = -1

-- 3D 场景
---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil
---@type Camera
local camera_ = nil
local tableNode_ = nil  -- 桌面节点

-- 分辨率 (Mode B)
local physW, physH = 0, 0
local dpr = 1.0
local logicalW, logicalH = 0, 0

-- 游戏时间
local gameTime = 0
local frameDt  = 0

-- (3D 版: 背景由 Zone fogColor 提供, 不再使用 NanoVG 背景图)

-- F4: 前置声明
local handleInventoryExorcism

-- 模块实例
---@type BoardData
local board = nil
---@type table token
local token = nil
local emotionHandles = nil

-- 交互状态
local demoState = "idle"
local hoveredCard = nil

-- 日期
local dayCount = 1
local MAX_DAYS = 3

-- 游戏阶段
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
-- 布局 (3D 版: 不再需要棋盘居中计算)
-- ============================================================================

local function recalcLayout()
    CameraButton.recalcLayout(logicalW, logicalH)
end

-- ============================================================================
-- 3D→2D 坐标转换 (供 VFX/Token 使用)
-- ============================================================================

--- 将世界坐标转换为逻辑屏幕坐标
local function worldToScreen(worldPos)
    if not camera_ then return logicalW / 2, logicalH / 2 end
    local screenPos = camera_:WorldToScreenPoint(worldPos)
    return screenPos.x * logicalW, screenPos.y * logicalH
end

-- ============================================================================
-- 3D 场景初始化
-- ============================================================================

local function setup3DScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 光照
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    if lightGroupFile then
        local lightGroup = scene_:CreateChild("LightGroup")
        lightGroup:LoadXML(lightGroupFile:GetRoot())
    else
        -- Fallback: 手动创建方向光
        local lightNode = scene_:CreateChild("DirectionalLight")
        lightNode:SetDirection(Vector3(0.5, -1.0, 0.6))
        local light = lightNode:CreateComponent("Light")
        light.lightType = LIGHT_DIRECTIONAL
        light.color = Color(0.95, 0.95, 0.9, 1.0)
        light.brightness = 1.2
        light.castShadows = true
    end

    -- 相机: 45度角俯瞰
    cameraNode_ = scene_:CreateChild("Camera")
    cameraNode_:SetPosition(Vector3(0, 4.5, -4.5))
    cameraNode_:LookAt(Vector3(0, 0, 0.3))

    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.nearClip = 0.1
    camera_.farClip = 100.0
    camera_.fov = 45.0

    -- 视口
    local viewport = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport)
    renderer.hdrRendering = true

    -- 环境
    local zone = scene_:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(Vector3(-100, -100, -100), Vector3(100, 100, 100))
    zone.fogColor = Color(0.15, 0.12, 0.18, 1.0)  -- 深紫暗色背景
    zone.fogStart = 50.0
    zone.fogEnd = 80.0
    zone.ambientColor = Color(0.3, 0.3, 0.35, 1.0)

    -- 桌面: 大平板 (Box.mdl 缩放)
    tableNode_ = scene_:CreateChild("Table")
    tableNode_:SetPosition(Vector3(0, -0.05, 0))  -- 略低于卡牌
    tableNode_:SetScale(Vector3(8, 0.1, 8))
    local tableModel = tableNode_:CreateComponent("StaticModel")
    tableModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local tableMat = Material:new()
    tableMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    tableMat:SetShaderParameter("MatDiffColor", Variant(Color(0.12, 0.10, 0.15, 1.0)))
    tableMat:SetShaderParameter("MatRoughness", Variant(0.85))
    tableMat:SetShaderParameter("MatMetallic", Variant(0.05))
    tableModel:SetMaterial(tableMat)

    print("[Main] 3D scene initialized")
end

-- ============================================================================
-- 初始化
-- ============================================================================

function Start()
    SampleStart()
    SampleInitMouseMode(MM_FREE)

    -- 分辨率
    recalcResolution()

    -- 3D 场景
    setup3DScene()

    -- NanoVG 上下文 (HUD 叠加层)
    vg = nvgCreate(1)
    if not vg then
        print("[Main] ERROR: Failed to create NanoVG context")
        return
    end

    -- 字体
    fontSans = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")

    -- (3D 版: 背景由 Zone fogColor 提供, 不再加载 NanoVG 背景图)

    -- 主题
    Theme.init("bright")

    -- 卡牌纹理系统
    CardTextures.init()

    -- 资源
    ResourceBar.init()

    -- 棋盘
    board = Board.new()
    local reqLocs = CardManager.preSelectLocations()
    Board.generateCards(board, reqLocs)
    recalcLayout()

    -- 预加载纹理 + 创建 3D 节点
    CardTextures.preloadBoard(board, Board.ROWS, Board.COLS)
    Board.createAllNodes(board, scene_, CardTextures)

    -- Token + 表情贴图 (Phase 1: 仍使用 NanoVG 叠加)
    emotionHandles = Token.loadImages(vg)
    token = Token.new()
    token.imageHandles = emotionHandles

    -- 注入回调
    Card.setRumorQuery(function(location)
        return CardManager.getRumorFor(location)
    end)
    CardTextures.setRumorQuery(function(location)
        return CardManager.getRumorFor(location)
    end)

    HandPanel.setEndDayCallback(function()
        advanceDay()
    end)

    HandPanel.setUseExorcismCallback(function()
        handleInventoryExorcism()
    end)

    ShopPopup.setMapRevealCallback(function()
        if not board or not board.cards then return end
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
        local pick = hidden[math.random(1, #hidden)]
        pick.revealed = true
        -- 3D: 用 worldToScreen 获取屏幕坐标给 VFX
        local sx, sy = worldToScreen(Vector3(pick.x, 0, pick.y))
        local tc = Theme.cardTypeColor(pick.type)
        VFX.spawnBurst(sx, sy, 8, tc.r, tc.g, tc.b)
        VFX.spawnBanner("🗺️ 揭示了一张卡牌!", tc.r, tc.g, tc.b, 18, 0.8)
    end)

    -- 相机模式回调
    CameraButton.setOnEnterCallback(function()
        if not board or not board.cards then return end
        for r = 1, Board.ROWS do
            for c = 1, Board.COLS do
                local cd = board.cards[r] and board.cards[r][c]
                if cd and cd.scouted and not cd.faceUp and not cd.isFlipping then
                    cd.faceUp = true
                    cd.scaleX = 0
                    Card.updateTexture(cd, CardTextures)
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
                    Tween.to(cd, { scaleX = 0 }, 0.1, {
                        easing = Tween.Easing.easeInQuad,
                        tag = "cameramode",
                        onComplete = function()
                            cd.faceUp = false
                            Card.updateTexture(cd, CardTextures)
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

    -- 日期转场
    DateTransition.init(vg)

    -- 事件
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")

    -- 标题画面
    gamePhase = "title"
    demoState = "idle"
    TitleScreen.show(function()
        gamePhase = "playing"
        startDeal()
    end)

    print("[Main] Initialization complete (3D mode)")
end

function Stop()
    CardTextures.destroy()
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

        -- Token 出现在"家" (3D→屏幕坐标)
        local homeRow = board.homeRow
        local homeCol = board.homeCol
        local wx, wz = Board.cardPos(board, homeRow, homeCol)
        local sx, sy = worldToScreen(Vector3(wx, 0, wz))
        Token.show(token, sx, sy)
        token.targetRow = homeRow
        token.targetCol = homeCol

        -- 保存世界坐标供 Token 使用
        token.worldX = wx
        token.worldZ = wz

        -- 家的卡牌默认翻开
        local homeCard = board.cards[homeRow][homeCol]
        if homeCard and not homeCard.faceUp then
            homeCard.faceUp = true
            Card.updateTexture(homeCard, CardTextures)
        end

        CardManager.generateDaily(board)
        HandPanel.show(logicalH, { showcase = true })
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

    token.visible = false
    token.alpha = 0
    HandPanel.hide()
    CameraButton.hide()

    Board.undealAll(board, function()
        Board.destroyAllNodes(board)
        CardTextures.clearCache()
        local locs = CardManager.preSelectLocations()
        Board.generateCards(board, locs)
        CardTextures.preloadBoard(board, Board.ROWS, Board.COLS)
        Board.createAllNodes(board, scene_, CardTextures)
        recalcLayout()
        startDeal()
    end)
end

local checkVictory

function advanceDay()
    if gamePhase ~= "playing" then return end
    if demoState ~= "ready" then return end
    if EventPopup.isActive() or CameraButton.isActive() or ShopPopup.isActive() then return end

    HandPanel.hide()
    CardManager.settleDay()

    ResourceBar.change("san", 1)
    ResourceBar.change("order", 1)

    local currentFilm = ResourceBar.get("film")
    if currentFilm < 3 then
        ResourceBar.change("film", 3 - currentFilm)
    end
    ResourceBar.change("money", 10)

    demoState = "dealing"
    hoveredCard = nil
    Tween.cancelTag("cardflip")
    Tween.cancelTag("cardshake")

    token.visible = false
    token.alpha = 0
    HandPanel.hide()
    CameraButton.hide()

    Board.undealAll(board, function()
        dayCount = dayCount + 1
        if checkVictory() then return end

        Board.destroyAllNodes(board)
        CardTextures.clearCache()

        DateTransition.play(dayCount, function()
            local locs = CardManager.preSelectLocations()
            Board.generateCards(board, locs)
            CardTextures.preloadBoard(board, Board.ROWS, Board.COLS)
            Board.createAllNodes(board, scene_, CardTextures)
            recalcLayout()
            startDeal()
        end)
    end)
end

-- ============================================================================
-- 胜负判定
-- ============================================================================

local function checkDefeat()
    if gamePhase ~= "playing" then return end
    local san   = ResourceBar.get("san")
    local order = ResourceBar.get("order")
    if san <= 0 or order <= 0 then
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

function onGameRestart()
    Tween.cancelAll()
    VFX.resetAll()
    hoveredCard = nil

    dayCount = 1
    gamePhase = "playing"
    gameStats.cardsRevealed = 0
    gameStats.monstersSlain = 0
    gameStats.photosUsed    = 0

    ResourceBar.reset()
    CardManager.reset()
    HandPanel.reset()
    ShopPopup.resetInventory()

    Board.destroyAllNodes(board)
    CardTextures.clearCache()

    local locs = CardManager.preSelectLocations()
    Board.generateCards(board, locs)
    CardTextures.preloadBoard(board, Board.ROWS, Board.COLS)
    Board.createAllNodes(board, scene_, CardTextures)
    recalcLayout()

    token = Token.new()
    token.imageHandles = emotionHandles

    startDeal()
end

-- ============================================================================
-- 弹窗关闭回调
-- ============================================================================

local function onPopupDismissed(cardType, effects)
    if effects and #effects > 0 and (cardType == "monster" or cardType == "trap") then
        if ShopPopup.useItem("shield") then
            Token.setEmotion(token, "relieved")
            local tc = Theme.current
            VFX.spawnBanner("🧿 护身符抵消了伤害!", tc.safe.r, tc.safe.g, tc.safe.b, 18, 1.0)
            VFX.flashScreen(100, 180, 255, 0.3, 120)
            effects = {}
        end
    end

    if effects then
        for _, eff in ipairs(effects) do
            ResourceBar.change(eff[1], eff[2])
        end
    end

    gameStats.cardsRevealed = gameStats.cardsRevealed + 1

    local gotRumor = false
    if cardType == "clue" then
        local added = CardManager.addRumor(board)
        if added then
            gotRumor = true
            local tc2 = Theme.current
            VFX.spawnBanner("📰 获得了新传闻!", tc2.rumor.r, tc2.rumor.g, tc2.rumor.b, 18, 0.8)
        end
    end

    local positiveTypes = { clue = true, safe = true, home = true, landmark = true }
    if positiveTypes[cardType] or gotRumor then
        Token.setEmotion(token, "happy")
    else
        Token.setEmotion(token, "default")
    end
    demoState = "ready"
    CameraButton.show()
    checkDefeat()
end

-- ============================================================================
-- 翻牌完成 → 弹窗
-- ============================================================================

local function onCardFlipped(card, screenX, screenY)
    if Board.isInLandmarkAura(board, card.row, card.col) then
        if card.type == "monster" or card.type == "trap" then
            card.type = "safe"
            Card.updateTexture(card, CardTextures)
        end
    end

    if card.location then
        local anyCompleted = CardManager.checkArrival(card.location)
        if anyCompleted then
            local sc = Theme.current.completed
            VFX.spawnBanner("日程完成!", sc.r, sc.g, sc.b, 20, 0.8)
        end
    end

    local tc = Theme.cardTypeColor(card.type)
    VFX.spawnBurst(screenX, screenY, 10, tc.r, tc.g, tc.b)

    local emotionMap = {
        monster = "scared", trap = "nervous", shop = "confused",
        clue = "surprised", home = "relieved", landmark = "relieved",
        safe = "relieved",
    }
    Token.setEmotion(token, emotionMap[card.type] or "default")

    if card.type == "home" or card.type == "landmark" then
        local locInfo = Card.LOCATION_INFO[card.location]
        local safeName = locInfo and locInfo.label or "安全区"
        local sc = Theme.current.safe
        VFX.spawnBanner(safeName .. " · 安全", sc.r, sc.g, sc.b, 18, 0.8)
        gameStats.cardsRevealed = gameStats.cardsRevealed + 1
        demoState = "ready"
        CameraButton.show()
        return
    end

    VFX.triggerShake(3, 0.15)

    demoState = "popup"
    hoveredCard = nil

    local popupDelay = { t = 0 }
    Tween.to(popupDelay, { t = 1 }, 0.4, {
        tag = "popup_delay",
        onComplete = function()
            local popCX = logicalW / 2
            local popCY = logicalH * 0.42
            if card.type == "shop" then
                ShopPopup.show(popCX, popCY, function()
                    gameStats.cardsRevealed = gameStats.cardsRevealed + 1
                    Token.setEmotion(token, "happy")
                    demoState = "ready"
                    checkDefeat()
                end)
            else
                EventPopup.show(card.type, popCX, popCY, onPopupDismissed, card.location)
            end
        end
    })
end

local function onPhotographFlipped(card, screenX, screenY)
    local tc = Theme.cardTypeColor(card.type)
    VFX.spawnBurst(screenX, screenY, 8, tc.r, tc.g, tc.b)
    VFX.triggerShake(2, 0.1)

    demoState = "popup"
    hoveredCard = nil

    local popupDelay = { t = 0 }
    Tween.to(popupDelay, { t = 1 }, 0.4, {
        tag = "popup_delay",
        onComplete = function()
            local popCX = logicalW / 2
            local popCY = logicalH * 0.42
            EventPopup.showPhoto(card.type, popCX, popCY, function(_cardType, _effects)
                gameStats.cardsRevealed = gameStats.cardsRevealed + 1

                card.scouted = true
                Tween.to(card, { scaleX = 0 }, 0.12, {
                    easing = Tween.Easing.easeInQuad,
                    tag = "cardflip",
                    onComplete = function()
                        card.faceUp = false
                        Card.updateTexture(card, CardTextures)
                        Tween.to(card, { scaleX = 1.0 }, 0.2, {
                            easing = Tween.Easing.easeOutBack,
                            tag = "cardflip",
                        })
                    end
                })

                Token.setEmotion(token, "happy")
                demoState = "ready"
                CameraButton.show()
            end, card.location)
        end
    })
end

-- ============================================================================
-- 相机模式操作
-- ============================================================================

local function doPhotograph(card, row, col)
    local wx, wz = Board.cardPos(board, row, col)
    local sx, sy = worldToScreen(Vector3(wx, 0, wz))

    ResourceBar.change("film", -1)
    gameStats.photosUsed = gameStats.photosUsed + 1

    demoState = "photographing"
    CameraButton.hide()
    Token.setEmotion(token, "determined")
    VFX.flashScreen(255, 255, 255, 0.3, 180)

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

    local delay = { t = 0 }
    Tween.to(delay, { t = 1 }, 0.25, {
        tag = "photograph",
        onComplete = function()
            if not card.faceUp and not card.isFlipping then
                demoState = "flipping"
                Card.flip(card, function(c)
                    onPhotographFlipped(c, sx, sy)
                end, CardTextures)
            else
                Token.setEmotion(token, "default")
                demoState = "ready"
                CameraButton.show()
            end
        end
    })
end

local function doExorcise(card, row, col, freeExorcise)
    local wx, wz = Board.cardPos(board, row, col)
    local sx, sy = worldToScreen(Vector3(wx, 0, wz))

    if freeExorcise then
        VFX.spawnBanner("🪔 驱魔香驱除!", Theme.current.safe.r, Theme.current.safe.g, Theme.current.safe.b, 16, 0.8)
    elseif ShopPopup.useItem("exorcism") then
        VFX.spawnBanner("🪔 驱魔香免费驱除!", Theme.current.safe.r, Theme.current.safe.g, Theme.current.safe.b, 16, 0.8)
    else
        ResourceBar.change("film", -1)
    end
    gameStats.photosUsed    = gameStats.photosUsed + 1
    gameStats.monstersSlain = gameStats.monstersSlain + 1

    demoState = "exorcising"
    CameraButton.hide()
    Token.setEmotion(token, "angry")

    local pc = Theme.color("plot")
    VFX.flashScreen(pc.r, pc.g, pc.b, 0.35, 150)
    VFX.triggerShake(4, 0.2)

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

    local delay = { t = 0 }
    Tween.to(delay, { t = 1 }, 0.3, {
        tag = "exorcise",
        onComplete = function()
            Card.transformTo(card, "photo", function(c)
                VFX.spawnBurst(sx, sy, 16, pc.r, pc.g, pc.b)
                VFX.spawnBanner("驱除成功!", pc.r, pc.g, pc.b, 24, 1.0)
                Token.setEmotion(token, "happy")
                demoState = "ready"
                CameraButton.show()
            end, CardTextures)
        end
    })
end

-- ---------------------------------------------------------------------------
-- F4: 从工具栏使用驱魔香
-- ---------------------------------------------------------------------------

handleInventoryExorcism = function()
    if demoState ~= "ready" then return end

    if not ShopPopup.useItem("exorcism") then
        VFX.spawnBanner("没有驱魔香!", 220, 80, 80, 18, 0.7)
        return
    end

    local row, col = token.targetRow, token.targetCol
    local card = board.cards[row] and board.cards[row][col]

    if not card then
        ShopPopup.addItem("exorcism", 1)
        VFX.spawnBanner("无效位置", 180, 180, 180, 16, 0.6)
        return
    end

    if card.faceUp and card.type == "monster" then
        doExorcise(card, row, col, true)
    else
        ShopPopup.addItem("exorcism", 1)
        if not card.faceUp then
            VFX.spawnBanner("需要先翻开卡牌!", 220, 160, 80, 16, 0.7)
        else
            VFX.spawnBanner("当前格子没有怪物", 180, 180, 180, 16, 0.6)
        end
    end
end

-- ============================================================================
-- 交互处理 (3D 射线检测)
-- ============================================================================

local function isAdjacent(r1, c1, r2, c2)
    local dr = math.abs(r1 - r2)
    local dc = math.abs(c1 - c2)
    return (dr + dc) == 1
end

local function handleNormalModeClick(card, row, col)
    local wx, wz = Board.cardPos(board, row, col)
    local sx, sy = worldToScreen(Vector3(wx, 0, wz))
    local isCurrent = (token.targetRow == row and token.targetCol == col)

    if isCurrent then
        if not card.faceUp and not card.isFlipping then
            demoState = "flipping"
            CameraButton.hide()
            Card.flip(card, function(c)
                onCardFlipped(c, sx, sy)
            end, CardTextures)
        else
            Card.shake(card)
        end
        return
    end

    if not isAdjacent(token.targetRow, token.targetCol, row, col) then
        Card.shake(card)
        VFX.spawnBanner("只能移动到相邻格子", 180, 180, 180, 16, 0.6)
        return
    end

    -- 移动 Token (屏幕坐标)
    demoState = "moving"
    CameraButton.hide()
    token.targetRow = row
    token.targetCol = col
    token.worldX = wx
    token.worldZ = wz
    Token.setEmotion(token, "running")

    Token.moveTo(token, sx, sy, function()
        if not card.faceUp and not card.isFlipping then
            demoState = "flipping"
            Card.flip(card, function(c)
                onCardFlipped(c, sx, sy)
            end, CardTextures)
        else
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

local function handleCameraModeClick(card, row, col)
    local film = ResourceBar.get("film")

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
        CameraButton.exitCameraMode(function()
            doPhotograph(card, row, col)
        end)
    else
        Card.shake(card)
        VFX.spawnBanner("无法拍摄", 180, 180, 180, 20, 0.6)
    end
end

local function handleClick(inputX, inputY)
    local lx = inputX / dpr
    local ly = inputY / dpr

    if DateTransition.isActive() then return end

    if TitleScreen.isActive() then
        TitleScreen.handleClick()
        return
    end

    if GameOver.isActive() then
        GameOver.handleClick(lx, ly, logicalW, logicalH)
        return
    end

    if ShopPopup.isActive() then
        ShopPopup.handleClick(lx, ly)
        return
    end

    if EventPopup.isActive() then
        EventPopup.handleClick(lx, ly)
        return
    end

    if HandPanel.isActive() then
        local handConsumed = HandPanel.handleClick(lx, ly, logicalW, logicalH)
        if handConsumed then return end
    end

    local consumed, reason = CameraButton.handleClick(lx, ly)
    if consumed then
        if reason == "no_film" then
            VFX.spawnBanner("胶卷不足!", 220, 80, 80, 22, 0.8)
        end
        return
    end

    if gamePhase ~= "playing" then return end
    if demoState ~= "ready" then return end

    -- 3D 射线检测
    local card, row, col = Board.hitTest(board, camera_, inputX, inputY, physW, physH)
    if not card then return end

    if CameraButton.isActive() then
        handleCameraModeClick(card, row, col)
    else
        handleNormalModeClick(card, row, col)
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

    if DateTransition.isActive() then return end

    if TitleScreen.isActive() then
        TitleScreen.handleKey(key)
        return
    end

    if GameOver.isActive() then
        GameOver.handleKey(key)
        return
    end

    if ShopPopup.isActive() then
        ShopPopup.handleKey(key)
        return
    end

    if EventPopup.isActive() then
        if key == KEY_RETURN or key == KEY_SPACE then
            EventPopup.dismiss()
        end
        return
    end

    if CameraButton.isActive() then
        if key == KEY_ESCAPE then
            CameraButton.exitCameraMode()
        end
        return
    end

    if gamePhase ~= "playing" then return end

    if key == KEY_ESCAPE then
        engine:Exit()
    end
end

-- ============================================================================
-- Hover 追踪 (3D 射线)
-- ============================================================================

local function updateHover(dt)
    local mousePos = input:GetMousePosition()
    local lx = mousePos.x / dpr
    local ly = mousePos.y / dpr

    GameOver.updateHover(lx, ly, dt, logicalW, logicalH)
    ShopPopup.updateHover(lx, ly, dt)
    EventPopup.updateHover(lx, ly, dt)
    CameraButton.updateHover(lx, ly, dt)
    HandPanel.updateHover(lx, ly, dt, logicalW, logicalH)

    if gamePhase ~= "playing" or demoState ~= "ready" then
        hoveredCard = nil
    else
        -- 3D 射线检测
        local card = Board.hitTest(board, camera_, mousePos.x, mousePos.y, physW, physH)
        if CameraButton.isActive() and card then
            if card.faceUp and card.type ~= "monster" then
                card = nil
            end
        end
        hoveredCard = card
    end

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
-- 更新 (3D 节点同步 + NanoVG 叠加更新)
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData:GetFloat("TimeStep")
    gameTime = gameTime + dt
    frameDt = dt

    Tween.update(dt)
    VFX.updateAll(dt)
    DateTransition.update(dt)
    Board.update(board, dt)
    Token.update(token, dt)
    ResourceBar.update(dt)
    CameraButton.update(dt)
    updateHover(dt)

    -- 3D 节点同步 (每帧将 Lua 属性映射到 Node Transform)
    Board.syncAllNodes(board)

    -- Token 屏幕位置更新 (跟随世界坐标)
    if token.visible and token.worldX and not token.isMoving then
        local sx, sy = worldToScreen(Vector3(token.worldX, 0, token.worldZ))
        -- 不直接覆盖 (Tween 可能正在操作)，仅在非移动时微调
        if not token.isMoving and demoState == "ready" then
            token.x = sx
            token.y = sy
        end
    end

    -- 屏幕抖动 → 相机偏移
    local shakeX, shakeY = VFX.getShakeOffset()
    if cameraNode_ and (shakeX ~= 0 or shakeY ~= 0) then
        -- 将屏幕像素抖动转为世界空间偏移 (大约 1px = 0.005m)
        local basePos = Vector3(0, 4.5, -4.5)
        cameraNode_:SetPosition(Vector3(
            basePos.x + shakeX * 0.005,
            basePos.y + shakeY * 0.005,
            basePos.z
        ))
    elseif cameraNode_ then
        -- 无抖动时确保相机在正确位置
        cameraNode_:SetPosition(Vector3(0, 4.5, -4.5))
    end
end

-- ============================================================================
-- NanoVG 渲染 (仅 HUD / 弹窗叠加层)
-- ============================================================================

function HandleNanoVGRender(eventType, eventData)
    if not vg then return end

    VFX.setContext(vg, logicalW, logicalH, gameTime)

    nvgBeginFrame(vg, logicalW, logicalH, dpr)

    -- 屏幕抖动 (NanoVG 层同步)
    local sx, sy = VFX.getShakeOffset()
    if sx ~= 0 or sy ~= 0 then
        nvgTranslate(vg, sx, sy)
    end

    -- === 3D 场景已由 Viewport 渲染，无需绘制背景 ===
    -- === 棋盘/卡牌已由 3D Viewport 渲染 ===

    -- === Token (Phase 1: 仍使用 NanoVG 叠加) ===
    Token.draw(vg, token, gameTime)

    -- === 相机模式取景器叠加层 ===
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

    -- === 相机按钮 ===
    CameraButton.draw(vg, logicalW, logicalH, gameTime)

    -- === 屏幕闪光 ===
    VFX.drawFlash()

    -- === 弹窗 ===
    EventPopup.draw(vg, logicalW, logicalH, gameTime)
    ShopPopup.draw(vg, logicalW, logicalH, gameTime)

    -- === 结算画面 ===
    GameOver.draw(vg, logicalW, logicalH, gameTime)

    -- === 日期转场 ===
    DateTransition.draw(vg, logicalW, logicalH, gameTime)

    -- === 标题画面 ===
    TitleScreen.draw(vg, logicalW, logicalH, gameTime)

    nvgEndFrame(vg)
end

-- ============================================================================
-- HUD
-- ============================================================================

function drawHUD()
    local t = Theme.current
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
end
