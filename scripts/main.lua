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
local MonsterGhost     = require "MonsterGhost"
local BubbleDialogue   = require "BubbleDialogue"
local ItemIcons        = require "ItemIcons"
local BoardItems       = require "BoardItems"
local NPCManager       = require "NPCManager"
local DialogueSystem   = require "DialogueSystem"
local DarkWorld        = require "DarkWorld"
local AudioManager     = require "AudioManager"
local CardInteraction  = require "CardInteraction"
local GameFlow         = require "GameFlow"
local DarkWorldFlow    = require "DarkWorldFlow"

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

-- F4: 前置声明 (拆分后大部分移至子模块, 仅保留必要声明)

-- 共享状态表 (CardInteraction / GameFlow / DarkWorldFlow 通过 G 读写)
local G = {
    demoState      = "idle",
    hoveredCard    = nil,
    gamePhase      = "title",
    dayCount       = 1,
    pendingRiftRow = nil,
    pendingRiftCol = nil,
    gameStats      = nil,   -- → Start() 中赋值
    board          = nil,   -- → Start() 中赋值
    token          = nil,   -- → Start() 中赋值
    playerBubble   = nil,   -- → Start() 中赋值
    logicalW       = 0,
    logicalH       = 0,
    worldToScreen  = nil,   -- → Start() 中赋值
    checkDefeat    = nil,   -- → Start() 中赋值 (跨模块回调)
    enterDarkWorld = nil,   -- → Start() 中赋值 (跨模块回调)
}

-- 模块实例 (同时存储在 G 中供子模块访问)
---@type BoardData
local board = nil
---@type table token
local token = nil

-- 气泡对话
local playerBubble = nil

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

-- 游戏阶段 (gamePhase 存储在 G.gamePhase)

-- 统计
local gameStats = {
    cardsRevealed = 0,
    dayStartRevealed = 0,  -- 每天开始时的翻牌数 (用于每日氛围重置)
    monstersSlain = 0,
    photosUsed    = 0,
}

-- ---------------------------------------------------------------------------
-- 琴馨 NPC 对话脚本 (Day 1 相机教程)
-- ---------------------------------------------------------------------------
local QINXIN_DIALOGUE = {
    { speaker = "琴馨", text = "唔……你也能看到那些奇怪的东西啊……" },
    { speaker = "琴馨", text = "……我还以为只有我一个人呢。" },
    { speaker = "琴馨", text = "嗯，那个……你看到右下角的 📷 了吗？" },
    { speaker = "琴馨", text = "点一下就能进入相机模式哦。" },
    { speaker = "琴馨", text = "在相机模式里，你可以拍照侦测还没翻开的牌……" },
    { speaker = "琴馨", text = "这样就能提前知道哪张牌下面藏着什么了。" },
    { speaker = "琴馨", text = "而且啊……如果已经知道是怪物，还能直接驱除掉它。" },
    { speaker = "琴馨", text = "不过每次拍照都要消耗胶卷哦，每天只有3卷……" },
    { speaker = "琴馨", text = "省着点用吧。……我先眯一会儿了。" },
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
    G.logicalW = logicalW
    G.logicalH = logicalH
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
    dirLight_.brightness = 2.8
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
    zone_.ambientColor = Color(0.70, 0.70, 0.75, 1.0)

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
    MonsterGhost.init(scene_)
    BoardItems.init(scene_)
    NPCManager.init(scene_)

    print("[Main] 3D scene initialized")
end

-- ============================================================================
-- 背景氛围过渡 (翻牌越多越暗)
-- ============================================================================

-- 明亮 → 暗色 的颜色定义
local BG_BRIGHT = {
    fog     = { 0.53, 0.76, 0.92 },  -- 天蓝 #87C3EB
    ambient = { 0.70, 0.70, 0.75 },
    table   = { 0.38, 0.44, 0.54 },  -- 偏蓝灰桌面
    brightness = 2.8,
}
local BG_DARK = {
    fog     = { 0.15, 0.12, 0.18 },  -- 深紫暗色
    ambient = { 0.35, 0.32, 0.38 },
    table   = { 0.16, 0.14, 0.20 },  -- 暗紫桌面
    brightness = 2.0,
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

    -- 天际线日夜渐变
    BoardDecor.updateNight(t)
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

    -- 音频管理器
    AudioManager.init(scene_)

    -- NanoVG 上下文 (HUD 叠加层)
    vg = nvgCreate(1)
    if not vg then
        print("[Main] ERROR: Failed to create NanoVG context")
        return
    end

    -- 字体
    fontSans = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")

    -- 道具图标纹理
    ItemIcons.init(vg)

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
    NPCManager.setBoard(board, Board)
    recalcLayout()

    -- 预加载纹理 + 创建 3D 节点
    CardTextures.preloadBoard(board, Board.ROWS, Board.COLS)
    Board.createAllNodes(board, scene_, CardTextures)

    -- Token (3D Billboard)
    token = Token.new()
    token.textures = Token.loadTextures()
    Token.createNode(token, scene_)

    -- 气泡对话
    playerBubble = BubbleDialogue.newBubble()

    -- 同步引用类型到共享状态表
    G.board         = board
    G.token         = token
    G.playerBubble  = playerBubble
    G.gameStats     = gameStats
    G.logicalW      = logicalW
    G.logicalH      = logicalH
    G.worldToScreen = worldToScreen
    G.checkDefeat    = nil  -- → GameFlow.init 后设置
    G.enterDarkWorld = nil  -- → DarkWorldFlow.init 后设置
    DarkWorldFlow.init(G, {
        scene = scene_,
        camera = camera_,
        recalcLayout = recalcLayout,
        setBgTransitionTarget = function(v) bgTransitionTarget = v end,
        getBgTransitionTarget = function() return bgTransitionTarget end,
    })
    G.enterDarkWorld = DarkWorldFlow.enterDarkWorld
    GameFlow.init(G, {
        scene = scene_,
        recalcLayout = recalcLayout,
        resetMainState = function()
            -- 重置 main.lua 特有的局部状态
            bgTransition = 0
            bgTransitionTarget = 0
            updateSceneAtmosphere(0)
            cameraPanX_ = 0
            cameraPanZ_ = 0
            DarkWorldFlow.resetSavedState()
            -- 同步 main local 引用
            board = G.board
            token = G.token
            playerBubble = G.playerBubble
        end,
    })
    G.checkDefeat = GameFlow.checkDefeat
    CardInteraction.init(G)

    -- 注入回调
    Card.setRumorQuery(function(location)
        return CardManager.getRumorFor(location)
    end)
    CardTextures.setRumorQuery(function(location)
        return CardManager.getRumorFor(location)
    end)

    HandPanel.setEndDayCallback(function()
        GameFlow.advanceDay()
    end)

    HandPanel.setUseExorcismCallback(function()
        CardInteraction.handleInventoryExorcism()
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
        AudioManager.playSFX("camera_enter")
        if not board or not board.cards then return end
        for r = 1, Board.ROWS do
            for c = 1, Board.COLS do
                local cd = board.cards[r] and board.cards[r][c]
                if cd and cd.scouted and not cd.faceUp and not cd.isFlipping then
                    Card.flipToFace(cd, CardTextures)
                end
            end
        end
        -- 已侦测的怪物卡显示 chibi
        MonsterGhost.showOnScoutedCards(board, Board.ROWS, Board.COLS)
        -- 已记录的踪迹箭头 (小幽灵指向最近怪物)
        MonsterGhost.showTrailsOnBoard(board, Board.ROWS, Board.COLS)
    end)

    CameraButton.setOnExitCallback(function()
        AudioManager.playSFX("camera_exit")
        if not board or not board.cards then return end
        -- 清除相机模式下的怪物 chibi 和踪迹箭头
        MonsterGhost.clearCardGhosts()
        MonsterGhost.clearTrailGhosts()
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

    -- 对话系统
    DialogueSystem.init(vg)

    -- 暗面世界
    DarkWorld.init(vg)
    DarkWorld.setExitCallback(function()
        DarkWorldFlow.exitDarkWorld()
    end)
    DarkWorld.changeLayerCallback = function(targetLayer, dc)
        DarkWorldFlow.changeDarkLayer(targetLayer, dc)
    end

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
    G.gamePhase = "title"
    G.demoState = "idle"
    TitleScreen.show(function()
        G.gamePhase = "playing"
        AudioManager.playBGM("day_light", 2.0)
        GameFlow.startDeal()
    end)

    print("[Main] Initialization complete (3D mode)")
end

function Stop()
    DarkWorld.reset()
    Token.destroyNode(token)
    NPCManager.destroy()
    DialogueSystem.reset()
    CardTextures.destroy()
    if vg then
        nvgDelete(vg)
        vg = nil
    end
end
-- ============================================================================
-- 卡牌交互逻辑 → 已提取到 CardInteraction.lua
-- ============================================================================

-- ============================================================================
-- 暗面世界进出 → 已提取到 DarkWorldFlow.lua
-- ============================================================================


-- ============================================================================
-- 交互处理 (3D 射线检测)
-- ============================================================================

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

    if DialogueSystem.isActive() then
        DialogueSystem.handleClick(lx, ly)
        return
    end

    if EventPopup.isRiftConfirmActive() then
        EventPopup.handleRiftClick(lx, ly)
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

    if G.gamePhase ~= "playing" then return end

    -- === 暗面世界路由 ===
    if DarkWorld.isActive() then
        -- 退出按钮 (已整合到 ResourceBar 暗面面板)
        if ResourceBar.hitTestDarkExit(lx, ly) then
            DarkWorldFlow.exitDarkWorld()
            return
        end
        -- 暗面世界中的相机驱除
        if CameraButton.isActive() then
            local shotHit = DarkWorld.handleCameraShot(board, token, inputX, inputY, ResourceBar)
            if shotHit then
                ResourceBar.change("film", -1)
                gameStats.photosUsed = gameStats.photosUsed + 1
                return
            end
        end
        -- 暗面世界卡牌点击
        DarkWorld.handleClick(board, token, inputX, inputY, ResourceBar, DialogueSystem, ShopPopup, G.dayCount)
        return
    end

    if G.demoState ~= "ready" then return end

    -- 3D 射线检测
    local card, row, col = Board.hitTest(board, camera_, inputX, inputY, physW, physH)
    if not card then return end

    if CameraButton.isActive() then
        CardInteraction.handleCameraModeClick(card, row, col)
    else
        CardInteraction.handleNormalModeClick(card, row, col)
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

    if DialogueSystem.isActive() then
        DialogueSystem.handleKey(key)
        return
    end

    if ShopPopup.isActive() then
        ShopPopup.handleKey(key)
        return
    end

    if EventPopup.isRiftConfirmActive() then
        return  -- 裂隙确认弹窗不响应键盘, 需点击
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

    if G.gamePhase ~= "playing" then return end

    -- 暗面世界: ESC 退出
    if DarkWorld.isActive() then
        if key == KEY_ESCAPE then
            DarkWorldFlow.exitDarkWorld()
        end
        return
    end

    -- [DEBUG] 按 1 强制进入暗面世界
    if key == KEY_1 and G.demoState == "ready" then
        DarkWorldFlow.enterDarkWorld(token.targetRow or 3, token.targetCol or 3)
        return
    end

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
    EventPopup.updateRiftHover(lx, ly, dt)
    CameraButton.updateHover(lx, ly, dt)
    HandPanel.updateHover(lx, ly, dt, logicalW, logicalH)

    if G.gamePhase ~= "playing" or G.demoState ~= "ready" or dragState_.isDragging then
        G.hoveredCard = nil
    else
        -- 3D 射线检测
        local card = Board.hitTest(board, camera_, mousePos.x, mousePos.y, physW, physH)
        if CameraButton.isActive() and card then
            if card.faceUp and card.type ~= "monster" then
                card = nil
            end
        end
        G.hoveredCard = card
    end

    if not board or not board.cards then return end
    for row = 1, Board.ROWS do
        if board.cards[row] then
            for col = 1, Board.COLS do
                local card = board.cards[row][col]
                if card then
                    local target = (card == G.hoveredCard) and 1.0 or 0.0
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

    AudioManager.update(dt)
    Tween.update(dt)
    VFX.updateAll(dt)
    DateTransition.update(dt)
    Board.update(board, dt)
    Token.update(token, dt)
    ResourceBar.update(dt)
    CameraButton.update(dt)
    EventPopup.updateToasts(dt)
    MonsterGhost.update(dt, gameTime)
    BoardItems.update(dt, gameTime)
    NPCManager.update(dt, gameTime)
    DialogueSystem.update(dt)
    DarkWorld.update(dt, gameTime)

    -- 气泡对话更新
    if playerBubble then
        local isIdle = not token.isMoving and G.demoState == "ready"
        local canTrigger = (G.gamePhase == "playing" and G.demoState == "ready"
            and not EventPopup.isActive() and not ShopPopup.isActive()
            and not CameraButton.isActive() and not DateTransition.isActive())
        BubbleDialogue.update(playerBubble, dt, isIdle, canTrigger)
    end

    updateHover(dt)

    -- 裂隙确认轮询 (事件结束后自动弹窗)
    if G.demoState == "ready" and G.gamePhase == "playing" then
        GameFlow.checkPendingRift()
    end

    -- 背景氛围过渡 (根据当天翻牌数平滑变暗, 每天重置; 暗面世界时由进出流程控制)
    if not DarkWorld.isActive() then
        local totalForFull = 8
        local dailyRevealed = gameStats.cardsRevealed - gameStats.dayStartRevealed
        bgTransitionTarget = math.min(dailyRevealed / totalForFull, 1.0)
        -- BGM 随氛围切换: 亮 → day_light, 暗 → day_dark
        if G.gamePhase == "playing" then
            local wantDark = bgTransitionTarget > 0.5
            local curKey = wantDark and "day_dark" or "day_light"
            AudioManager.playBGM(curKey)  -- 内部会跳过相同 key
        end
    end
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

    -- === 暗面世界 HUD 叠加层 ===
    DarkWorld.draw(vg, logicalW, logicalH, gameTime)

    -- === 相机模式取景器叠加层 ===
    CameraButton.drawOverlay(vg, logicalW, logicalH, gameTime)

    -- === 气泡对话 (角色头顶, 3D→2D 投影) ===
    if playerBubble and token and token.visible then
        -- Token 头顶世界坐标 (bounceY + 精灵高度)
        local headWorldY = 0.25 + token.bounceY + 0.50 -- 0.25=基础Y, 0.50=精灵高度
        local headPos = Vector3(token.worldX, headWorldY, token.worldZ)
        local headSX, headSY = worldToScreen(headPos)
        BubbleDialogue.draw(playerBubble, vg, headSX, headSY)
    end

    -- === NPC 交互提示 (同格时浮动气泡, 笔记本风格) ===
    if G.gamePhase == "playing" and G.demoState == "ready"
       and not DialogueSystem.isActive() and not CameraButton.isActive()
       and token and token.visible then
        local npcHere = NPCManager.getNPCAt(token.targetRow, token.targetCol)
        if npcHere and npcHere.alpha > 0.5 then
            local hintWorldPos = Vector3(npcHere.worldX, 1.10, npcHere.worldZ)
            local hsx, hsy = worldToScreen(hintWorldPos)
            local bounce = math.sin(gameTime * 3.0) * 4
            local pulse = 0.75 + 0.25 * math.sin(gameTime * 2.5)
            local hAlpha = math.floor(240 * pulse)

            local hintLabel = "💬 点击对话"
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local tw = nvgTextBounds(vg, 0, 0, hintLabel, nil) or 80
            local pw, ph = tw + 18, 22
            local bx = hsx - pw / 2
            local by = hsy - ph / 2 + bounce
            local arrowH = 5

            -- 阴影
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx + 1, by + 2, pw, ph, 8)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(25 * pulse)))
            nvgFill(vg)

            -- 白色气泡背景 (与 BubbleDialogue 统一)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, pw, ph, 8)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, hAlpha))
            nvgFill(vg)

            -- 细边框
            nvgStrokeColor(vg, nvgRGBA(180, 180, 180, math.floor(100 * pulse)))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 小三角指向下方 (白底 + 边框)
            local triCX = hsx
            local triY = by + ph
            nvgBeginPath(vg)
            nvgMoveTo(vg, triCX - 5, triY)
            nvgLineTo(vg, triCX, triY + arrowH)
            nvgLineTo(vg, triCX + 5, triY)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, hAlpha))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, triCX - 5, triY)
            nvgLineTo(vg, triCX, triY + arrowH)
            nvgLineTo(vg, triCX + 5, triY)
            nvgStrokeColor(vg, nvgRGBA(180, 180, 180, math.floor(100 * pulse)))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            -- 遮盖接合处边框
            nvgBeginPath(vg)
            nvgRect(vg, triCX - 5, triY - 1, 10, 2)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, hAlpha))
            nvgFill(vg)

            -- 文字 (深色墨水)
            nvgFillColor(vg, nvgRGBA(50, 50, 50, math.floor(220 * pulse)))
            nvgText(vg, hsx, by + ph / 2, hintLabel)
        end
    end

    -- === VFX 叠加层 ===
    VFX.drawBurst()
    VFX.drawPopups()
    VFX.drawBanners()
    VFX.drawTransition()

    -- === 资源栏 ===
    ResourceBar.draw(vg, logicalW, logicalH, G.dayCount)

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
    EventPopup.drawRiftConfirm(vg, logicalW, logicalH)
    ShopPopup.draw(vg, logicalW, logicalH, gameTime)

    -- === 对话系统 (Gal 风格, 在弹窗之上、结算之下) ===
    DialogueSystem.draw(vg, logicalW, logicalH, gameTime)

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
    DarkWorld.updateScreenParams(camera_, physW, physH)
end
