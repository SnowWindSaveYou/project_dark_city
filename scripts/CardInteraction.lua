-- ============================================================================
-- CardInteraction.lua - 卡牌交互 (翻牌/拍照/驱除/移动)
-- 从 main.lua 提取, 处理所有卡牌点击后的业务逻辑
-- ============================================================================

local Card          = require "Card"
local Board         = require "Board"
local Token         = require "Token"
local CardTextures  = require "CardTextures"
local ResourceBar   = require "ResourceBar"
local EventPopup    = require "EventPopup"
local CameraButton  = require "CameraButton"
local ShopPopup     = require "ShopPopup"
local CardManager   = require "CardManager"
local MonsterGhost  = require "MonsterGhost"
local NPCManager    = require "NPCManager"
local DialogueSystem = require "DialogueSystem"
local BoardItems    = require "BoardItems"
local AudioManager  = require "AudioManager"
local BubbleDialogue = require "BubbleDialogue"
local DarkWorld     = require "DarkWorld"
local Theme         = require "Theme"
local Tween         = require "lib.Tween"
local VFX           = require "lib.VFX"

local M = {}

---@type table  shared mutable state, set by init()
local G

--- 初始化, 接收共享游戏状态表
---@param gameState table
function M.init(gameState)
    G = gameState
end

-- ============================================================================
-- Helpers
-- ============================================================================

local function isAdjacent(r1, c1, r2, c2)
    local dr = math.abs(r1 - r2)
    local dc = math.abs(c1 - c2)
    return (dr + dc) == 1
end

--- BFS 寻路: 找到从 (sr,sc) 到 (er,ec) 的最短路径
--- 中间格子必须已翻开 (faceUp), 目标格子不要求已翻开
---@return table|nil path  路径列表 {row,col} (不含起点, 含终点), nil=无路径
local function findPath(sr, sc, er, ec)
    local function key(r, c) return r * 10 + c end

    local visited = {}
    local parent = {}
    local queue = {}
    local dirs = { {-1, 0}, {1, 0}, {0, -1}, {0, 1} }

    visited[key(sr, sc)] = true
    queue[#queue + 1] = { sr, sc }
    local head = 1

    while head <= #queue do
        local cr, cc = queue[head][1], queue[head][2]
        head = head + 1

        for _, d in ipairs(dirs) do
            local nr, nc = cr + d[1], cc + d[2]
            if nr >= 1 and nr <= Board.ROWS and nc >= 1 and nc <= Board.COLS then
                local nk = key(nr, nc)
                if not visited[nk] then
                    local card = G.board.cards[nr] and G.board.cards[nr][nc]
                    if card then
                        local isTarget = (nr == er and nc == ec)
                        -- 中间格子必须 faceUp; 目标格子无此限制
                        if isTarget or card.faceUp then
                            visited[nk] = true
                            parent[nk] = { cr, cc }
                            if isTarget then
                                -- 回溯重建路径
                                local path = {}
                                local pr, pc = nr, nc
                                while pr ~= sr or pc ~= sc do
                                    table.insert(path, 1, { row = pr, col = pc })
                                    local prev = parent[key(pr, pc)]
                                    pr, pc = prev[1], prev[2]
                                end
                                return path
                            end
                            queue[#queue + 1] = { nr, nc }
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- ============================================================================
-- 弹窗关闭回调 (阻塞型事件弹窗消失后)
-- ============================================================================

local function onPopupDismissed(cardType, effects)
    if effects and #effects > 0 and (cardType == "monster" or cardType == "trap") then
        if ShopPopup.useItem("shield") then
            AudioManager.playItemUse("shield")
            Token.setEmotion(G.token, "relieved")
            local tc = Theme.current
            VFX.spawnBanner("🧿 护身符抵消了伤害!", tc.safe.r, tc.safe.g, tc.safe.b, 18, 1.0)
            VFX.flashScreen(100, 180, 255, 0.3, 120)
            effects = {}
        end
    end

    if effects then
        for _, eff in ipairs(effects) do
            ResourceBar.change(eff[1], eff[2])
            AudioManager.playResourceChange(eff[2])
        end
    end

    AudioManager.playSFX("popup_close")
    G.gameStats.cardsRevealed = G.gameStats.cardsRevealed + 1

    local gotRumor = false
    if cardType == "clue" then
        local added = CardManager.addRumor(G.board)
        if added then
            gotRumor = true
            local tc2 = Theme.current
            VFX.spawnBanner("📰 获得了新传闻!", tc2.rumor.r, tc2.rumor.g, tc2.rumor.b, 18, 0.8)
        end
    end

    local positiveTypes = { clue = true, safe = true, home = true, landmark = true }
    if positiveTypes[cardType] or gotRumor then
        Token.setEmotion(G.token, "happy")
    else
        Token.setEmotion(G.token, "default")
    end
    G.demoState = "ready"
    CameraButton.show()
    G.checkDefeat()
end

-- ============================================================================
-- 翻牌完成 → 效果处理 (核心业务逻辑)
-- ============================================================================

local function onCardFlipped(card, screenX, screenY)
    if Board.isInLandmarkAura(G.board, card.row, card.col) then
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

    -- 事件类型音效
    local sfxMap = {
        monster = "evt_monster", trap = "evt_trap", shop = "evt_safe",
        clue = "evt_clue", safe = "evt_safe", home = "evt_safe",
        landmark = "evt_safe", plot = "evt_plot", photo = "evt_photo",
    }
    AudioManager.playSFX(sfxMap[card.type] or "evt_safe")

    local tc = Theme.cardTypeColor(card.type)
    VFX.spawnBurst(screenX, screenY, 10, tc.r, tc.g, tc.b)

    local emotionMap = {
        monster = "scared", trap = "nervous", shop = "confused",
        clue = "surprised", home = "relieved", landmark = "relieved",
        safe = "relieved",
    }
    Token.setEmotion(G.token, emotionMap[card.type] or "default")

    -- 更新气泡对话上下文
    if G.playerBubble then
        BubbleDialogue.setContext(G.playerBubble, card.location, card.type)
    end

    if card.type == "home" or card.type == "landmark" then
        local locInfo = Card.LOCATION_INFO[card.location]
        local safeName = locInfo and locInfo.label or "安全区"
        local sc = Theme.current.safe
        VFX.spawnBanner(safeName .. " · 安全", sc.r, sc.g, sc.b, 18, 0.8)
        G.gameStats.cardsRevealed = G.gameStats.cardsRevealed + 1
        G.demoState = "ready"
        CameraButton.show()
        return
    end

    -- 标记裂隙 (事件完成后弹确认, 由 Update 中 checkPendingRift 驱动)
    if card.hasRift then
        G.pendingRiftRow = card.row
        G.pendingRiftCol = card.col
    end

    VFX.triggerShake(3, 0.15)

    -- -----------------------------------------------------------------------
    -- 阻塞 vs 非阻塞 分流
    -- -----------------------------------------------------------------------
    local isBlocking = EventPopup.isBlockingEvent(card.type)

    if isBlocking then
        -- === 阻塞路径: 商店 / 未来剧情选择 → 模态弹窗 ===
        G.demoState = "popup"
        G.hoveredCard = nil

        local popupDelay = { t = 0 }
        Tween.to(popupDelay, { t = 1 }, 0.4, {
            tag = "popup_delay",
            onComplete = function()
                local popCX = G.logicalW / 2
                local popCY = G.logicalH * 0.42
                if card.type == "shop" then
                    ShopPopup.show(popCX, popCY, function()
                        G.gameStats.cardsRevealed = G.gameStats.cardsRevealed + 1
                        Token.setEmotion(G.token, "happy")
                        G.demoState = "ready"
                        G.checkDefeat()
                    end)
                else
                    EventPopup.show(card.type, popCX, popCY, onPopupDismissed, card.location)
                end
            end
        })
    else
        -- === 非阻塞路径: 怪物/陷阱/安全/线索/剧情/照片/悬赏 → Toast ===

        -- 陷阱子类型: 使用专属效果表
        local effects
        if card.type == "trap" and card.trapSubtype then
            effects = EventPopup.trapSubtypeEffects[card.trapSubtype] or {}
        else
            effects = EventPopup.cardEffects[card.type] or {}
        end

        local shieldUsed = false

        -- 护盾检查 (仅怪物/陷阱有伤害效果; teleport 无伤害但仍可被护盾取消传送)
        if (card.type == "monster" or card.type == "trap") then
            local hasDamage = #effects > 0
            local isTeleport = (card.type == "trap" and card.trapSubtype == "teleport")
            if (hasDamage or isTeleport) and ShopPopup.useItem("shield") then
                shieldUsed = true
                AudioManager.playItemUse("shield")
                Token.setEmotion(G.token, "relieved")
                local safC = Theme.current.safe
                VFX.spawnBanner("🧿 护身符抵消了伤害!", safC.r, safC.g, safC.b, 18, 1.0)
                VFX.flashScreen(100, 180, 255, 0.3, 120)
                effects = {}
            end
        end

        -- 立即应用资源变化
        for _, eff in ipairs(effects) do
            ResourceBar.change(eff[1], eff[2])
            AudioManager.playResourceChange(eff[2])
        end

        -- 统计
        G.gameStats.cardsRevealed = G.gameStats.cardsRevealed + 1
        if card.type == "monster" then
            G.gameStats.monstersSlain = G.gameStats.monstersSlain + 1
            -- 怪物 Chibi 弹出环绕玩家
            MonsterGhost.spawnAroundPlayer(G.token.worldX, G.token.worldZ, card.location)
        end

        -- 传闻
        local gotRumor = false
        if card.type == "clue" then
            local added = CardManager.addRumor(G.board)
            if added then
                gotRumor = true
                local tc2 = Theme.current
                VFX.spawnBanner("📰 获得了新传闻!", tc2.rumor.r, tc2.rumor.g, tc2.rumor.b, 18, 0.8)
            end
        end

        -- 表情
        if gotRumor then
            Token.setEmotion(G.token, "happy")
        end

        -- 发送 toast (传递 trapSubtype)
        EventPopup.toast(card.type, effects, shieldUsed, card.location, card.trapSubtype)

        -- 怪物: 短暂停顿让 chibi 弹出, 再恢复 ready
        if card.type == "monster" then
            local pauseDummy = { t = 0 }
            Tween.to(pauseDummy, { t = 1 }, 0.6, {
                tag = "monster_pause",
                onComplete = function()
                    G.demoState = "ready"
                    CameraButton.show()
                    G.checkDefeat()
                end,
            })
        elseif card.type == "trap" and card.trapSubtype == "teleport" and not shieldUsed then
            -- === 空间错位: 传送到随机未翻开格子 ===
            G.demoState = "teleporting"

            local candidates = {}
            for r = 1, Board.ROWS do
                for c = 1, Board.COLS do
                    if not (r == card.row and c == card.col) then
                        local cd = G.board.cards[r] and G.board.cards[r][c]
                        if cd and not cd.faceUp and not cd.isFlipping then
                            candidates[#candidates + 1] = { r = r, c = c, card = cd }
                        end
                    end
                end
            end

            if #candidates == 0 then
                G.demoState = "ready"
                CameraButton.show()
                G.checkDefeat()
            else
                local pick = candidates[math.random(1, #candidates)]

                local teleDelay = { t = 0 }
                Tween.to(teleDelay, { t = 1 }, 0.5, {
                    tag = "teleport_delay",
                    onComplete = function()
                        AudioManager.playSFX("rift_enter", 0.6)
                        VFX.flashScreen(140, 80, 200, 0.35, 160)
                        VFX.triggerShake(5, 0.3)

                        local destWx, destWz = Board.cardPos(G.board, pick.r, pick.c)
                        local shareOff = NPCManager.getShareOffset(pick.r, pick.c)
                        G.token.targetRow = pick.r
                        G.token.targetCol = pick.c
                        Token.setEmotion(G.token, "scared")

                        Token.moveTo(G.token, destWx + shareOff, destWz, function()
                            local destCard = pick.card
                            if not destCard.faceUp and not destCard.isFlipping then
                                local dsx, dsy = G.worldToScreen(Vector3(destWx, 0, destWz))
                                G.demoState = "flipping"
                                Card.flip(destCard, function(c)
                                    onCardFlipped(c, dsx, dsy)
                                end, CardTextures)
                            else
                                G.demoState = "ready"
                                CameraButton.show()
                                G.checkDefeat()
                            end
                        end)
                    end,
                })
            end
        else
            G.demoState = "ready"
            CameraButton.show()
            G.checkDefeat()
        end
    end
end

-- ============================================================================
-- 拍照翻牌完成 (相机模式: 侦察=清除)
-- ============================================================================

local function onPhotographFlipped(card, screenX, screenY)
    AudioManager.playSFX("evt_photo")
    local tc = Theme.cardTypeColor(card.type)
    VFX.spawnBurst(screenX, screenY, 8, tc.r, tc.g, tc.b)
    VFX.triggerShake(2, 0.1)

    G.gameStats.cardsRevealed = G.gameStats.cardsRevealed + 1

    -- -----------------------------------------------------------------------
    -- 侦察=清除: 怪物/陷阱 → 显示动效后自动驱除, 变为安全格
    -- -----------------------------------------------------------------------
    if card.type == "monster" or card.type == "trap" then
        local isDanger = card.type

        if isDanger == "monster" then
            MonsterGhost.showOnCard(card, card.location)
            G.gameStats.monstersSlain = G.gameStats.monstersSlain + 1
        end

        Token.setEmotion(G.token, isDanger == "monster" and "scared" or "nervous")
        G.demoState = "exorcising"
        G.hoveredCard = nil

        local revealPause = { t = 0 }
        Tween.to(revealPause, { t = 1 }, 0.8, {
            tag = "photograph_exorcise",
            onComplete = function()
                AudioManager.playSFX("exorcise")
                local pc = Theme.color("plot")
                VFX.flashScreen(pc.r, pc.g, pc.b, 0.35, 150)
                VFX.triggerShake(4, 0.2)
                Token.setEmotion(G.token, "angry")
                Token.hop(G.token, 0.06)

                MonsterGhost.clearCardGhosts()

                AudioManager.playSFX("ghost_dispel")
                Card.transformTo(card, "photo", function(c)
                    VFX.spawnBurst(screenX, screenY, 16, pc.r, pc.g, pc.b)
                    if isDanger == "monster" then
                        VFX.spawnBanner("👻 发现怪物! 已驱除!", pc.r, pc.g, pc.b, 20, 1.0)
                    else
                        local trapLabel = "陷阱"
                        if card.trapSubtype and EventPopup.trapSubtypeInfo[card.trapSubtype] then
                            trapLabel = EventPopup.trapSubtypeInfo[card.trapSubtype].label
                        end
                        VFX.spawnBanner("⚡ 发现" .. trapLabel .. "! 已清除!", pc.r, pc.g, pc.b, 20, 1.0)
                    end
                    Token.setEmotion(G.token, "happy")
                    G.demoState = "ready"
                    CameraButton.show()
                end, CardTextures)
            end
        })
        return
    end

    -- -----------------------------------------------------------------------
    -- 非危险格: 显示踪迹箭头 + 侦察预览
    -- -----------------------------------------------------------------------
    local hasTrail = MonsterGhost.calculateTrail(card, G.board, Board.ROWS, Board.COLS)

    G.demoState = "popup"
    G.hoveredCard = nil

    local popupDelay = { t = 0 }
    Tween.to(popupDelay, { t = 1 }, 0.4, {
        tag = "popup_delay",
        onComplete = function()
            if hasTrail then
                MonsterGhost.showTrailOnCard(card, card.trailDirX, card.trailDirZ)
            end

            local popCX = G.logicalW / 2
            local popCY = G.logicalH * 0.42
            EventPopup.showPhoto(card.type, popCX, popCY, function(_cardType, _effects)
                card.scouted = true
                Card.flipBack(card, nil, CardTextures)

                MonsterGhost.clearTrailGhosts()

                Token.setEmotion(G.token, "happy")
                G.demoState = "ready"
                CameraButton.show()
            end, card.location)
        end
    })
end

-- ============================================================================
-- 相机模式操作
-- ============================================================================

local function doPhotograph(card, row, col)
    local wx, wz = Board.cardPos(G.board, row, col)
    local sx, sy = G.worldToScreen(Vector3(wx, 0, wz))

    ResourceBar.change("film", -1)
    G.gameStats.photosUsed = G.gameStats.photosUsed + 1

    G.demoState = "photographing"
    CameraButton.hide()
    Token.setEmotion(G.token, "determined")
    AudioManager.playSFX("camera_shutter")
    AudioManager.playSFX("screen_flash", 0.4)
    VFX.flashScreen(255, 255, 255, 0.3, 180)

    Token.hop(G.token, 0.05)

    local delay = { t = 0 }
    Tween.to(delay, { t = 1 }, 0.25, {
        tag = "photograph",
        onComplete = function()
            if not card.faceUp and not card.isFlipping then
                G.demoState = "flipping"
                Card.flip(card, function(c)
                    onPhotographFlipped(c, sx, sy)
                end, CardTextures)
            else
                Token.setEmotion(G.token, "default")
                G.demoState = "ready"
                CameraButton.show()
            end
        end
    })
end

local function doExorcise(card, row, col, freeExorcise)
    local wx, wz = Board.cardPos(G.board, row, col)
    local sx, sy = G.worldToScreen(Vector3(wx, 0, wz))

    if freeExorcise then
        VFX.spawnBanner("🪔 驱魔香驱除!", Theme.current.safe.r, Theme.current.safe.g, Theme.current.safe.b, 16, 0.8)
    elseif ShopPopup.useItem("exorcism") then
        VFX.spawnBanner("🪔 驱魔香免费驱除!", Theme.current.safe.r, Theme.current.safe.g, Theme.current.safe.b, 16, 0.8)
    else
        ResourceBar.change("film", -1)
    end
    G.gameStats.photosUsed    = G.gameStats.photosUsed + 1
    G.gameStats.monstersSlain = G.gameStats.monstersSlain + 1

    G.demoState = "exorcising"
    CameraButton.hide()
    Token.setEmotion(G.token, "angry")
    AudioManager.playSFX("exorcise")

    local pc = Theme.color("plot")
    VFX.flashScreen(pc.r, pc.g, pc.b, 0.35, 150)
    VFX.triggerShake(4, 0.2)

    Token.hop(G.token, 0.06)

    local delay = { t = 0 }
    Tween.to(delay, { t = 1 }, 0.3, {
        tag = "exorcise",
        onComplete = function()
            AudioManager.playSFX("ghost_dispel")
            Card.transformTo(card, "photo", function(c)
                VFX.spawnBurst(sx, sy, 16, pc.r, pc.g, pc.b)
                VFX.spawnBanner("驱除成功!", pc.r, pc.g, pc.b, 24, 1.0)
                Token.setEmotion(G.token, "happy")
                G.demoState = "ready"
                CameraButton.show()
            end, CardTextures)
        end
    })
end

-- ============================================================================
-- F4: 从工具栏使用驱魔香
-- ============================================================================

function M.handleInventoryExorcism()
    if G.demoState ~= "ready" then return end

    if not ShopPopup.useItem("exorcism") then
        AudioManager.playItemUseFail()
        VFX.spawnBanner("没有驱魔香!", 220, 80, 80, 18, 0.7)
        return
    end

    local row, col = G.token.targetRow, G.token.targetCol
    local card = G.board.cards[row] and G.board.cards[row][col]

    if not card then
        ShopPopup.addItem("exorcism", 1)
        VFX.spawnBanner("无效位置", 180, 180, 180, 16, 0.6)
        return
    end

    if card.faceUp and card.type == "monster" then
        doExorcise(card, row, col, true)
    else
        ShopPopup.addItem("exorcism", 1)
        AudioManager.playItemUseFail()
        if not card.faceUp then
            VFX.spawnBanner("需要先翻开卡牌!", 220, 160, 80, 16, 0.7)
        else
            VFX.spawnBanner("当前格子没有怪物", 180, 180, 180, 16, 0.6)
        end
    end
end

-- ============================================================================
-- 自动寻路行走: 沿已翻开卡牌逐格跳跃到远处目标
-- ============================================================================

--- 沿 path 逐格跳跃, 中间收集道具/检查日程, 终点执行正常翻牌/事件
---@param path table  {row,col} 列表 (不含起点, 含终点)
---@param screenX number 目标卡牌屏幕坐标 X
---@param screenY number 目标卡牌屏幕坐标 Y
local function executeAutoWalk(path, screenX, screenY)
    MonsterGhost.clearSurround()
    if G.playerBubble then BubbleDialogue.forceHide(G.playerBubble) end
    G.demoState = "moving"
    CameraButton.hide()
    Token.setEmotion(G.token, "running")
    AudioManager.playSFX("token_jump")

    local function walkStep(stepIndex)
        local step = path[stepIndex]
        local row, col = step.row, step.col
        local card = G.board.cards[row][col]
        local wx, wz = Board.cardPos(G.board, row, col)
        local isLast = (stepIndex == #path)

        G.token.targetRow = row
        G.token.targetCol = col

        local moveShareOff = NPCManager.getShareOffset(row, col)

        Token.moveTo(G.token, wx + moveShareOff, wz, function()
            -- 拾取该格子上的道具
            local collected = BoardItems.tryCollect(row, col)
            if collected then
                AudioManager.playSFX("item_pickup")
                if collected.key == "film" then
                    ResourceBar.change("film", 1)
                elseif collected.key == "mapReveal" then
                    local candidates = {}
                    for r2 = 1, Board.ROWS do
                        for c2 = 1, Board.COLS do
                            local cd2 = G.board.cards[r2] and G.board.cards[r2][c2]
                            if cd2 and not cd2.faceUp and not cd2.isFlipping then
                                candidates[#candidates + 1] = { r = r2, c = c2, card = cd2 }
                            end
                        end
                    end
                    if #candidates > 0 then
                        AudioManager.playItemUse("mapReveal")
                        local pick = candidates[math.random(#candidates)]
                        Card.flip(pick.card, nil, CardTextures)
                    end
                else
                    ShopPopup.addItem(collected.key, 1)
                end
                VFX.spawnBanner("获得 " .. collected.icon .. " " .. collected.label, 255, 220, 100, 18, 0.9)
            end

            if isLast then
                -- 终点: 与普通单步移动相同的处理
                if not card.faceUp and not card.isFlipping then
                    G.demoState = "flipping"
                    Card.flip(card, function(c)
                        onCardFlipped(c, screenX, screenY)
                    end, CardTextures)
                else
                    if card.location then
                        local anyCompleted = CardManager.checkArrival(card.location)
                        if anyCompleted then
                            local sc = Theme.current.completed
                            VFX.spawnBanner("日程完成!", sc.r, sc.g, sc.b, 20, 0.8)
                        end
                    end
                    Token.setEmotion(G.token, "default")
                    G.demoState = "ready"
                    CameraButton.show()
                end
            else
                -- 中间格子: 检查日程完成, 继续下一步
                if card.faceUp and card.location then
                    local anyCompleted = CardManager.checkArrival(card.location)
                    if anyCompleted then
                        local sc = Theme.current.completed
                        VFX.spawnBanner("日程完成!", sc.r, sc.g, sc.b, 20, 0.8)
                    end
                end
                AudioManager.playSFX("token_jump")
                walkStep(stepIndex + 1)
            end
        end, function()
            -- onLand: 落地音效
            AudioManager.playSFX("card_flip", 0.5)
        end)
    end

    walkStep(1)
end

-- ============================================================================
-- 普通模式点击 (移动 Token / 翻牌 / 对话)
-- ============================================================================

function M.handleNormalModeClick(card, row, col)
    local wx, wz = Board.cardPos(G.board, row, col)
    local sx, sy = G.worldToScreen(Vector3(wx, 0, wz))
    local isCurrent = (G.token.targetRow == row and G.token.targetCol == col)

    if isCurrent then
        if not card.faceUp and not card.isFlipping then
            G.demoState = "flipping"
            CameraButton.hide()
            Card.flip(card, function(c)
                onCardFlipped(c, sx, sy)
            end, CardTextures)
        elseif card.faceUp and card.hasRift then
            -- 已翻开的裂隙卡: 弹确认窗
            G.demoState = "popup"
            CameraButton.hide()
            local popCX = G.logicalW / 2
            local popCY = G.logicalH * 0.42
            EventPopup.showRiftConfirm(popCX, popCY,
                function() G.enterDarkWorld(row, col) end,
                function() G.demoState = "ready"; CameraButton.show() end
            )
        else
            -- 点击已翻开的当前格 → 检查是否有 NPC 可交互
            local npc = NPCManager.getNPCAt(row, col)
            if npc and npc.dialogueScript and not DialogueSystem.isActive() then
                G.demoState = "dialogue"
                CameraButton.hide()
                if G.playerBubble then BubbleDialogue.forceHide(G.playerBubble) end
                DialogueSystem.start(npc.dialogueScript, npc.texPath, function()
                    G.demoState = "ready"
                    CameraButton.show()
                end)
            elseif G.playerBubble then
                BubbleDialogue.clickTrigger(G.playerBubble)
            end
        end
        return
    end

    if not isAdjacent(G.token.targetRow, G.token.targetCol, row, col) then
        -- 尝试自动寻路: 沿已翻开的卡牌跳过去
        local path = findPath(G.token.targetRow, G.token.targetCol, row, col)
        if path then
            executeAutoWalk(path, sx, sy)
        else
            Card.shake(card)
            AudioManager.playSFX("card_shake", 0.5)
            VFX.spawnBanner("沿途有未翻开的卡牌，无法到达", 180, 180, 180, 16, 0.6)
        end
        return
    end

    -- 移动 Token
    MonsterGhost.clearSurround()
    if G.playerBubble then BubbleDialogue.forceHide(G.playerBubble) end
    G.demoState = "moving"
    CameraButton.hide()
    G.token.targetRow = row
    G.token.targetCol = col
    Token.setEmotion(G.token, "running")
    AudioManager.playSFX("token_jump")

    local moveShareOff = NPCManager.getShareOffset(row, col)
    Token.moveTo(G.token, wx + moveShareOff, wz, function()
        -- 检查并拾取该格子上的道具
        local collected = BoardItems.tryCollect(row, col)
        if collected then
            AudioManager.playSFX("item_pickup")
            if collected.key == "film" then
                ResourceBar.change("film", 1)
            elseif collected.key == "mapReveal" then
                local revealed = false
                local candidates = {}
                for r2 = 1, Board.ROWS do
                    for c2 = 1, Board.COLS do
                        local cd2 = G.board.cards[r2] and G.board.cards[r2][c2]
                        if cd2 and not cd2.faceUp and not cd2.isFlipping then
                            candidates[#candidates + 1] = { r = r2, c = c2, card = cd2 }
                        end
                    end
                end
                if #candidates > 0 then
                    AudioManager.playItemUse("mapReveal")
                    local pick = candidates[math.random(#candidates)]
                    Card.flip(pick.card, nil, CardTextures)
                    revealed = true
                end
                if not revealed then
                    VFX.spawnBanner("没有可翻开的卡牌", 180, 180, 180, 16, 0.6)
                end
            else
                ShopPopup.addItem(collected.key, 1)
            end
            VFX.spawnBanner("获得 " .. collected.icon .. " " .. collected.label, 255, 220, 100, 18, 0.9)
        end

        if not card.faceUp and not card.isFlipping then
            G.demoState = "flipping"
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
            Token.setEmotion(G.token, "default")
            G.demoState = "ready"
            CameraButton.show()
        end
    end, function()
        -- onLand: 角色落地瞬间（落地挤压开始时）
        AudioManager.playSFX("card_flip", 0.5)
    end)
end

-- ============================================================================
-- 相机模式点击 (拍照侦察 / 驱除怪物)
-- ============================================================================

function M.handleCameraModeClick(card, row, col)
    local film = ResourceBar.get("film")

    -- 已翻开的怪物: 消耗 1 胶卷驱除
    if card.faceUp and card.type == "monster" and not card.isFlipping then
        if film <= 0 then
            CameraButton.shakeNoFilm()
            AudioManager.playSFX("film_empty")
            VFX.spawnBanner("胶卷不足!", 220, 80, 80, 22, 0.8)
            return
        end
        CameraButton.exitCameraMode(function()
            doExorcise(card, row, col)
        end)
        return
    end

    -- 已侦察的安全牌 (相片预览)
    if card.scouted and card.faceUp and not card.isFlipping then
        G.demoState = "popup"
        G.hoveredCard = nil
        local popCX = G.logicalW / 2
        local popCY = G.logicalH * 0.42
        EventPopup.showPhoto(card.type, popCX, popCY, function()
            Token.setEmotion(G.token, "default")
            G.demoState = "ready"
        end, card.location)
        return
    end

    if film <= 0 then
        CameraButton.shakeNoFilm()
        AudioManager.playSFX("film_empty")
        VFX.spawnBanner("胶卷不足!", 220, 80, 80, 22, 0.8)
        return
    end

    -- 未翻开的牌: 消耗 1 胶卷侦察
    if not card.faceUp and not card.isFlipping then
        CameraButton.exitCameraMode(function()
            doPhotograph(card, row, col)
        end)
    else
        Card.shake(card)
        VFX.spawnBanner("无法拍摄", 180, 180, 180, 20, 0.6)
    end
end

return M
