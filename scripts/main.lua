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
local BoardDecor       = require "BoardDecor"

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

-- 相机自适应参数 (根据屏幕宽高比动态计算)
local cameraBaseY_ = 4.5
local cameraBaseZ_ = -4.5
local cameraLookAtZ_ = -0.3

-- 相机平移 (拖拽偏移, 世界空间)
local cameraPanX_ = 0
local cameraPanZ_ = 0
local PAN_LIMIT_X = 1.5
local PAN_LIMIT_Z = 1.5

-- 分辨率 (Mode B)
local physW, physH = 0, 0
local dpr = 1.0
local logicalW, logicalH = 0, 0

-- 游戏时间
local gameTime = 0
local frameDt  = 0

-- 背景过渡 (3D 版: 通过 Zone fogColor + 桌面颜色 + 光照亮度平滑变化)
local bgTransition = 0       -- 当前过渡进度 0=全亮 1=全暗
local bgTransitionTarget = 0 -- 目标过渡值
---@type Zone
local zone_ = nil            -- Zone 组件引用
---@type Light
local dirLight_ = nil        -- 方向光引用
local tableMat_ = nil        -- 桌面材质引用

-- F4: 前置声明
local handleInventoryExorcism

-- 模块实例
---@type BoardData
local board = nil
---@type table token
local token = nil

-- 交互状态
local demoState = "idle"
local hoveredCard = nil

-- 帧计数器 (用于防止触摸模拟导致的同帧双重点击)
local frameCount_ = 0
local lastClickFrame_ = -1

-- 拖拽状态 (用于区分点击和拖拽平移)
local DRAG_THRESHOLD = 8  -- 逻辑像素, 超过此距离判定为拖拽
local dragState_ = {
    active = false,       -- 按下中 (尚未抬起)
    isDragging = false,   -- 已超过阈值, 正在拖拽
    startLX = 0,          -- 按下时的逻辑坐标
    startLY = 0,
    lastLX = 0,           -- 上一次的逻辑坐标 (用于计算增量)
    lastLY = 0,
    physStartX = 0,       -- 按下时的物理坐标 (用于 handleClick)
    physStartY = 0,
    inputSource = "none", -- "mouse" 或 "touch"
}

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
-- 布局 (3D 版: 相机根据屏幕宽高比自适应)
-- ============================================================================

--- 将相机移动到 base + pan 偏移位置 (保持45°角)
local function applyCameraPosition()
    if not cameraNode_ then return end
    cameraNode_:SetPosition(Vector3(
        cameraPanX_, cameraBaseY_, cameraBaseZ_ + cameraPanZ_
    ))
    cameraNode_:LookAt(Vector3(
        cameraPanX_, 0, cameraLookAtZ_ + cameraPanZ_
    ))
end

--- 更新拖拽增量, 平移相机
local function updateDrag(lx, ly)
    local dx = lx - dragState_.startLX
    local dy = ly - dragState_.startLY

    -- 判定是否开始拖拽
    if not dragState_.isDragging then
        if math.abs(dx) > DRAG_THRESHOLD or math.abs(dy) > DRAG_THRESHOLD then
            dragState_.isDragging = true
        else
            return
        end
    end

    -- 计算增量
    local deltaLX = lx - dragState_.lastLX
    local deltaLY = ly - dragState_.lastLY
    dragState_.lastLX = lx
    dragState_.lastLY = ly

    -- 灵敏度: 屏幕像素 → 世界米
    if not camera_ then return end
    local D = cameraBaseY_ * math.sqrt(2)
    local visibleH = 2 * D * math.tan(math.rad(camera_.fov / 2))
    local worldPerPx = visibleH / logicalH

    -- 拖拽方向 → 相机平移 (grab 手势: 内容跟手)
    -- 水平: 手指右移 → 相机左移 (-X)
    -- 竖直: 手指下移 → 相机前移 (+Z) (因为屏幕上方=世界+Z)
    cameraPanX_ = cameraPanX_ - deltaLX * worldPerPx
    cameraPanZ_ = cameraPanZ_ + deltaLY * worldPerPx

    -- 限制范围
    cameraPanX_ = math.max(-PAN_LIMIT_X, math.min(PAN_LIMIT_X, cameraPanX_))
    cameraPanZ_ = math.max(-PAN_LIMIT_Z, math.min(PAN_LIMIT_Z, cameraPanZ_))

    applyCameraPosition()
end

--- 根据屏幕宽高比计算相机位置，确保棋盘完整可见
local function recalcCamera()
    if not camera_ then return end

    local aspect = logicalW / logicalH  -- >1 横屏, <1 竖屏
    local fovRad = math.rad(camera_.fov)  -- 45° → 0.785 rad
    local halfTanFov = math.tan(fovRad / 2)  -- tan(22.5°) ≈ 0.4142

    -- 棋盘宽度 (含少量边距)
    local boardW = Board.COLS * (Card.CARD_W + Board.GAP) - Board.GAP  -- 3.68m
    local margin = 1.12  -- 12% 边距
    local requiredW = boardW * margin  -- ~4.12m

    -- 45° 俯视相机: 相机到棋面中心的距离 = camY * sqrt(2)
    -- 水平可视宽度 = 2 * camY * sqrt(2) * tan(vFOV/2) * aspect
    -- 解 camY: camY = requiredW / (2 * sqrt(2) * tan(vFOV/2) * aspect)
    local camYFromW = requiredW / (2 * math.sqrt(2) * halfTanFov * aspect)

    -- 横屏 (aspect ≥ 1.0) 时宽度富余, 保持原始值 4.5
    -- 竖屏时按需拉远
    local camY = math.max(4.5, camYFromW)

    -- 上限: 避免棋盘过小 (极窄屏保护)
    camY = math.min(camY, 8.5)

    -- 45° 角: Z = -Y
    cameraBaseY_ = camY
    cameraBaseZ_ = -camY

    -- LookAt 偏移: 按比例调整 (原始 camY=4.5 时 lookAtZ=-0.3)
    cameraLookAtZ_ = -0.3 * (camY / 4.5)

    -- 应用 (含 pan 偏移)
    applyCameraPosition()

    print(string.format("[Main] Camera adapted: aspect=%.2f, camY=%.1f, camZ=%.1f, lookAtZ=%.2f",
        aspect, cameraBaseY_, cameraBaseZ_, cameraLookAtZ_))
end

local function recalcLayout()
    recalcCamera()
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

    -- 光照: 方向光 (明亮场景)
    local lightNode = scene_:CreateChild("DirectionalLight")
    lightNode:SetDirection(Vector3(0.5, -1.0, 0.6))
    dirLight_ = lightNode:CreateComponent("Light")
    dirLight_.lightType = LIGHT_DIRECTIONAL
    dirLight_.color = Color(1.0, 1.0, 0.95, 1.0)
    dirLight_.brightness = 2.2
    dirLight_.castShadows = true

    -- 相机: 45度角俯瞰
    cameraNode_ = scene_:CreateChild("Camera")
    cameraNode_:SetPosition(Vector3(0, 4.5, -4.5))
    cameraNode_:LookAt(Vector3(0, 0, -0.3))

    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.nearClip = 0.1
    camera_.farClip = 100.0
    camera_.fov = 45.0

    -- 视口
    local viewport = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport)
    renderer.hdrRendering = true

    -- 环境
    zone_ = scene_:CreateComponent("Zone")
    zone_.boundingBox = BoundingBox(Vector3(-100, -100, -100), Vector3(100, 100, 100))
    zone_.fogColor = Color(0.53, 0.76, 0.92, 1.0)  -- 初始: 明亮天蓝 (#87C3EB)
    zone_.fogStart = 50.0
    zone_.fogEnd = 80.0
    zone_.ambientColor = Color(0.5, 0.5, 0.55, 1.0)

    -- 桌面: 大平板 (Box.mdl 缩放)
    tableNode_ = scene_:CreateChild("Table")
    tableNode_:SetPosition(Vector3(0, -0.15, 0))  -- 桌面顶部在 Y=-0.1, 远离棋盘平面
    tableNode_:SetScale(Vector3(8, 0.1, 8))
    local tableModel = tableNode_:CreateComponent("StaticModel")
    tableModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    tableMat_ = Material:new()
    tableMat_:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    tableMat_:SetShaderParameter("MatDiffColor", Variant(Color(0.32, 0.38, 0.48, 1.0)))  -- 初始: 偏蓝灰桌面
    tableMat_:SetShaderParameter("MatRoughness", Variant(0.85))
    tableMat_:SetShaderParameter("MatMetallic", Variant(0.05))
    tableModel:SetMaterial(tableMat_)

    -- 装饰 (传入桌面 model 以替换纹理)
    BoardDecor.init(scene_, tableModel)

    print("[Main] 3D scene initialized")
end

-- ============================================================================
-- 背景氛围过渡 (翻牌越多越暗)
-- ============================================================================

-- 明亮 → 暗色 的颜色定义
local BG_BRIGHT = {
    fog     = { 0.53, 0.76, 0.92 },  -- 天蓝 #87C3EB
    ambient = { 0.55, 0.55, 0.60 },
    table   = { 0.32, 0.38, 0.48 },  -- 偏蓝灰桌面
    brightness = 2.2,
}
local BG_DARK = {
    fog     = { 0.15, 0.12, 0.18 },  -- 深紫暗色
    ambient = { 0.25, 0.22, 0.28 },
    table   = { 0.12, 0.10, 0.15 },  -- 暗紫桌面
    brightness = 1.6,
}

--- 根据过渡进度 t (0=全亮, 1=全暗) 更新场景氛围
local function updateSceneAtmosphere(t)
    if not zone_ then return end

    local function lerp(a, b, f) return a + (b - a) * f end
    local function lerpColor(ca, cb, f)
        return Color(lerp(ca[1], cb[1], f), lerp(ca[2], cb[2], f), lerp(ca[3], cb[3], f), 1.0)
    end

    zone_.fogColor = lerpColor(BG_BRIGHT.fog, BG_DARK.fog, t)
    zone_.ambientColor = lerpColor(BG_BRIGHT.ambient, BG_DARK.ambient, t)

    if dirLight_ then
        dirLight_.brightness = lerp(BG_BRIGHT.brightness, BG_DARK.brightness, t)
    end

    if tableMat_ then
        tableMat_:SetShaderParameter("MatDiffColor",
            Variant(lerpColor(BG_BRIGHT.table, BG_DARK.table, t)))
    end
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

    -- 重置背景过渡
    bgTransition = 0
    bgTransitionTarget = 0
    updateSceneAtmosphere(0)  -- 初始化为全亮

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

    -- Token (3D Billboard)
    token = Token.new()
    token.textures = Token.loadTextures()
    Token.createNode(token, scene_)

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
                    Card.flipToFace(cd, CardTextures)
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
                    Card.flipToBack(cd, CardTextures)
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
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")

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
    Token.destroyNode(token)
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

        -- Token 出现在"家" (世界坐标)
        local homeRow = board.homeRow
        local homeCol = board.homeCol
        local wx, wz = Board.cardPos(board, homeRow, homeCol)
        Token.show(token, wx, wz)
        token.targetRow = homeRow
        token.targetCol = homeCol

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
    EventPopup.clearToasts()
    Tween.cancelTag("cardflip")
    Tween.cancelTag("carddeal")
    Tween.cancelTag("cardshake")
    Tween.cancelTag("cardtransform")
    Tween.cancelTag("tokenmove")
    Tween.cancelTag("token")
    Tween.cancelTag("popup")
    Tween.cancelTag("toast")
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
    EventPopup.clearToasts()
    hoveredCard = nil

    dayCount = 1
    gamePhase = "playing"
    gameStats.cardsRevealed = 0
    gameStats.monstersSlain = 0
    gameStats.photosUsed    = 0

    -- 重置背景过渡和相机平移
    bgTransition = 0
    bgTransitionTarget = 0
    updateSceneAtmosphere(0)
    cameraPanX_ = 0
    cameraPanZ_ = 0

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

    Token.destroyNode(token)
    token = Token.new()
    token.textures = Token.loadTextures()
    Token.createNode(token, scene_)

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

    -- -----------------------------------------------------------------------
    -- 阻塞 vs 非阻塞 分流
    -- -----------------------------------------------------------------------
    local isBlocking = EventPopup.isBlockingEvent(card.type)

    if isBlocking then
        -- === 阻塞路径: 商店 / 未来剧情选择 → 模态弹窗 ===
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
    else
        -- === 非阻塞路径: 怪物/陷阱/安全/线索/剧情/照片/悬赏 → Toast ===
        local effects = EventPopup.cardEffects[card.type] or {}
        local shieldUsed = false

        -- 护盾检查 (仅怪物/陷阱有伤害效果)
        if #effects > 0 and (card.type == "monster" or card.type == "trap") then
            if ShopPopup.useItem("shield") then
                shieldUsed = true
                Token.setEmotion(token, "relieved")
                local safC = Theme.current.safe
                VFX.spawnBanner("🧿 护身符抵消了伤害!", safC.r, safC.g, safC.b, 18, 1.0)
                VFX.flashScreen(100, 180, 255, 0.3, 120)
                effects = {}
            end
        end

        -- 立即应用资源变化
        for _, eff in ipairs(effects) do
            ResourceBar.change(eff[1], eff[2])
        end

        -- 统计
        gameStats.cardsRevealed = gameStats.cardsRevealed + 1
        if card.type == "monster" then
            gameStats.monstersSlain = gameStats.monstersSlain + 1
        end

        -- 传闻
        local gotRumor = false
        if card.type == "clue" then
            local added = CardManager.addRumor(board)
            if added then
                gotRumor = true
                local tc2 = Theme.current
                VFX.spawnBanner("📰 获得了新传闻!", tc2.rumor.r, tc2.rumor.g, tc2.rumor.b, 18, 0.8)
            end
        end

        -- 表情: 保持 emotionMap 初始表情 (scared/nervous/surprised 等)
        -- 仅在特殊情况下覆盖
        if gotRumor then
            Token.setEmotion(token, "happy")
        end
        -- 护盾路径已在上方设置 "relieved", 无需再覆盖

        -- 发送 toast
        EventPopup.toast(card.type, effects, shieldUsed, card.location)

        -- 立即恢复 ready（不阻塞）
        demoState = "ready"
        CameraButton.show()

        -- 败北检查
        checkDefeat()
    end
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
                Card.flipBack(card, nil, CardTextures)

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

    Token.hop(token, 0.05)

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

    Token.hop(token, 0.06)

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

    -- 移动 Token (世界坐标)
    demoState = "moving"
    CameraButton.hide()
    token.targetRow = row
    token.targetCol = col
    Token.setEmotion(token, "running")

    Token.moveTo(token, wx, wz, function()
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
    -- 防止触摸模拟导致同帧双重点击 (SampleStart 在移动端启用触摸模拟,
    -- 一次触摸同时触发 HandleTouchBegin 和 HandleMouseDown)
    if frameCount_ == lastClickFrame_ then return end
    lastClickFrame_ = frameCount_

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

    -- Toast 点击 (非阻塞, 提前关闭)
    if EventPopup.handleToastClick(lx, ly) then
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

--- 开始拖拽跟踪 (点击延迟到抬起时触发, 以支持拖拽平移)
local function beginDragTracking(physX, physY, source)
    if dragState_.active then return end  -- 已有活跃按下 (避免触摸模拟重复)
    local lx = physX / dpr
    local ly = physY / dpr
    dragState_.active = true
    dragState_.isDragging = false
    dragState_.startLX = lx
    dragState_.startLY = ly
    dragState_.lastLX = lx
    dragState_.lastLY = ly
    dragState_.physStartX = physX
    dragState_.physStartY = physY
    dragState_.inputSource = source
end

--- 结束拖拽, 如果未拖拽则触发点击
local function endDragTracking(source)
    if not dragState_.active then return end
    if dragState_.inputSource ~= source then return end
    if not dragState_.isDragging then
        handleClick(dragState_.physStartX, dragState_.physStartY)
    end
    dragState_.active = false
    dragState_.isDragging = false
    dragState_.inputSource = "none"
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    local button = eventData:GetInt("Button")
    if button ~= MOUSEB_LEFT then return end
    local mousePos = input:GetMousePosition()
    beginDragTracking(mousePos.x, mousePos.y, "mouse")
end

---@param eventType string
---@param eventData MouseButtonUpEventData
function HandleMouseUp(eventType, eventData)
    local button = eventData:GetInt("Button")
    if button ~= MOUSEB_LEFT then return end
    endDragTracking("mouse")
end

---@param eventType string
---@param eventData TouchBeginEventData
function HandleTouchBegin(eventType, eventData)
    local tx = eventData:GetInt("X")
    local ty = eventData:GetInt("Y")
    beginDragTracking(tx, ty, "touch")
end

---@param eventType string
---@param eventData TouchMoveEventData
function HandleTouchMove(eventType, eventData)
    if not dragState_.active or dragState_.inputSource ~= "touch" then return end
    local tx = eventData:GetInt("X")
    local ty = eventData:GetInt("Y")
    updateDrag(tx / dpr, ty / dpr)
end

---@param eventType string
---@param eventData TouchEndEventData
function HandleTouchEnd(eventType, eventData)
    endDragTracking("touch")
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

    if gamePhase ~= "playing" or demoState ~= "ready" or dragState_.isDragging then
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
    frameCount_ = frameCount_ + 1

    -- 鼠标拖拽跟踪 (触摸拖拽由 HandleTouchMove 事件处理)
    if dragState_.active and dragState_.inputSource == "mouse" then
        local mousePos = input:GetMousePosition()
        updateDrag(mousePos.x / dpr, mousePos.y / dpr)
    end

    Tween.update(dt)
    VFX.updateAll(dt)
    DateTransition.update(dt)
    Board.update(board, dt)
    Token.update(token, dt)
    ResourceBar.update(dt)
    CameraButton.update(dt)
    EventPopup.updateToasts(dt)
    updateHover(dt)

    -- 背景氛围过渡 (根据翻牌数平滑变暗)
    local totalForFull = 8
    bgTransitionTarget = math.min(gameStats.cardsRevealed / totalForFull, 1.0)
    local bgSpeed = 2.0
    if bgTransition < bgTransitionTarget then
        bgTransition = math.min(bgTransition + bgSpeed * dt, bgTransitionTarget)
    elseif bgTransition > bgTransitionTarget then
        bgTransition = math.max(bgTransition - bgSpeed * dt, bgTransitionTarget)
    end
    updateSceneAtmosphere(bgTransition)

    -- 3D 节点同步 (每帧将 Lua 属性映射到 Node Transform)
    Board.syncAllNodes(board)
    Token.syncNode(token, gameTime)

    -- 屏幕抖动 → 相机偏移 (叠加 pan 平移)
    local shakeX, shakeY = VFX.getShakeOffset()
    if cameraNode_ and (shakeX ~= 0 or shakeY ~= 0) then
        cameraNode_:SetPosition(Vector3(
            cameraPanX_ + shakeX * 0.005,
            cameraBaseY_ + shakeY * 0.005,
            cameraBaseZ_ + cameraPanZ_
        ))
    elseif cameraNode_ then
        cameraNode_:SetPosition(Vector3(
            cameraPanX_, cameraBaseY_, cameraBaseZ_ + cameraPanZ_
        ))
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

    -- === 3D 场景已由 Viewport 渲染 (棋盘/卡牌/Token 均为 3D) ===

    -- === 相机模式取景器叠加层 ===
    CameraButton.drawOverlay(vg, logicalW, logicalH, gameTime)

    -- === VFX 叠加层 ===
    VFX.drawBurst()
    VFX.drawPopups()
    VFX.drawBanners()
    VFX.drawTransition()

    -- === 资源栏 ===
    ResourceBar.draw(vg, logicalW, logicalH, dayCount)

    -- === 手牌面板 ===
    HandPanel.draw(vg, logicalW, logicalH, gameTime)

    -- === HUD (天数已整合到 ResourceBar) ===

    -- === 相机按钮 ===
    CameraButton.draw(vg, logicalW, logicalH, gameTime)

    -- === 屏幕闪光 ===
    VFX.drawFlash()

    -- === 非阻塞 Toast ===
    EventPopup.drawToasts(vg, logicalW, logicalH, gameTime)

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
-- HUD (天数已整合到 ResourceBar 纸条中)
-- ============================================================================

-- ============================================================================
-- 屏幕变化
-- ============================================================================

function HandleScreenMode(eventType, eventData)
    recalcResolution()
    recalcLayout()
end
