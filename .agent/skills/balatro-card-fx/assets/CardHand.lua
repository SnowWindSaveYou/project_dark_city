-- ============================================================================
-- CardHand.lua - Balatro 风格手牌管理系统
-- 扇形布局、悬停弹起推开、选牌、抽牌、出牌、弃牌、拖拽换位、查阅放大
-- ============================================================================

local Tween = require "balatro.Tween"
local Card  = require "balatro.Card"

local CardHand = {}
CardHand.__index = CardHand

-- ============================================================================
-- 配置
-- ============================================================================

local DEFAULT_CONFIG = {
    -- 手牌区域（相对屏幕底部居中）
    handY           = 0,      -- 会在 recalc 中设为 screenH - 偏移
    handBottomMargin = 50,    -- 底部边距

    -- 扇形布局
    maxSpread       = 500,    -- 最大横向展开宽度
    cardSpacing     = 70,     -- 单卡间距（卡多了会自动缩小）
    curveAmount     = 15,     -- 边缘卡牌下沉量
    maxRotation     = 6,      -- 边缘最大旋转角度

    -- 悬停效果
    hoverLift       = 40,     -- 悬停抬起高度
    hoverScale      = 1.18,   -- 悬停缩放
    hoverPushApart  = 25,     -- 悬停时推开邻牌距离
    hoverSpeed      = 14,     -- 悬停响应速度（damp speed）

    -- 选中效果
    selectLift      = 30,     -- 选中抬起高度

    -- 抽牌动画
    drawDuration    = 0.35,   -- 单卡动画时长
    drawStagger     = 0.08,   -- 连抽间隔

    -- 出牌/弃牌动画
    playDuration    = 0.3,
    discardDuration = 0.25,

    -- 拖拽
    dragScale       = 1.1,

    -- 查阅放大
    inspectScale    = 2.2,
    inspectDuration = 0.25,

    -- 最大手牌数
    maxHandSize     = 8,
}

-- ============================================================================
-- 构造
-- ============================================================================

---@param config table|nil 可选配置覆盖
function CardHand.new(config)
    local self = setmetatable({}, CardHand)

    self.config = {}
    for k, v in pairs(DEFAULT_CONFIG) do self.config[k] = v end
    if config then
        for k, v in pairs(config) do self.config[k] = v end
    end

    -- 屏幕尺寸（需要外部调用 recalcLayout 更新）
    self.screenW = 800
    self.screenH = 600

    -- 手牌列表
    ---@type table[]
    self.cards = {}

    -- 牌堆（未抽的牌）
    self.deck = {}
    -- 弃牌堆
    self.discardPile = {}
    -- 出牌区（打出的牌）
    self.playedCards = {}

    -- 牌堆/弃牌堆/出牌区位置
    self.deckPos     = { x = 0, y = 0 }
    self.discardPos  = { x = 0, y = 0 }
    self.playAreaPos  = { x = 0, y = 0 }

    -- 交互状态
    self.hoveredCard  = nil
    self.hoveredIndex = 0
    self.selectedCards = {}

    -- 拖拽
    self.dragCard     = nil
    self.dragIndex    = 0
    self.dragOffsetX  = 0
    self.dragOffsetY  = 0
    self.dragStartX   = 0
    self.dragStartY   = 0
    self.dragStarted  = false  -- 区分点击与拖拽
    self.insertIndex  = 0

    -- 查阅模式
    self.inspecting   = false
    self.inspectCard  = nil
    self.inspectOverlayAlpha = 0

    -- 动画锁定（抽牌/出牌期间禁止交互）
    self.animLocked   = false
    self.animLockCount = 0

    -- 出牌展示区的卡牌（带动画数据）
    self.showCards = {}
    self.showTimer = 0

    -- 动画中的卡牌（出牌/弃牌期间独立渲染）
    self.animatingCards = {}

    return self
end

-- ============================================================================
-- 布局计算
-- ============================================================================

--- 更新屏幕尺寸并重新计算固定位置
function CardHand:recalcLayout(screenW, screenH)
    self.screenW = screenW
    self.screenH = screenH
    self.config.handY = screenH - self.config.handBottomMargin - Card.HEIGHT / 2

    -- 牌堆：右上
    self.deckPos.x = screenW - 80
    self.deckPos.y = 120

    -- 弃牌堆：右下（牌堆下方）
    self.discardPos.x = screenW - 80
    self.discardPos.y = 280

    -- 出牌区：中央偏上
    self.playAreaPos.x = screenW / 2
    self.playAreaPos.y = screenH / 2 - 80

    self:updateTargets()
end

--- 计算每张手牌的目标位置（扇形布局）
function CardHand:updateTargets()
    local n = #self.cards
    if n == 0 then return end

    local cfg = self.config
    local centerX = self.screenW / 2
    local baseY = cfg.handY

    -- 动态间距：卡多了自动缩小
    local spacing = math.min(cfg.cardSpacing, cfg.maxSpread / math.max(1, n))

    for i = 1, n do
        local card = self.cards[i]
        -- 归一化位置 [-1, 1]
        local t = 0
        if n > 1 then
            t = (i - 1) / (n - 1) * 2 - 1   -- -1 到 1
        end

        -- 被拖拽的牌不参与布局
        if card == self.dragCard then
            goto continue
        end

        -- 拖拽中的插入位偏移
        local insertOffset = 0
        if self.dragCard and self.insertIndex > 0 then
            local layoutI = i
            -- 拖拽的牌被移除后的有效索引
            if self.dragIndex > 0 and i > self.dragIndex then
                -- 后面的牌缩进
            end
            if layoutI >= self.insertIndex then
                insertOffset = spacing * 0.5
            end
            if layoutI < self.insertIndex then
                insertOffset = -spacing * 0.5
            end
        end

        -- 基础位置
        card.targetX = centerX + t * (spacing * (n - 1)) / 2 + insertOffset

        -- 抛物线下沉（边缘牌略低）
        card.targetY = baseY + t * t * cfg.curveAmount

        -- 扇形旋转
        card.targetRotation = t * cfg.maxRotation

        -- 基础缩放
        card.targetScale = 1.0

        -- 基础 z 轴
        card.baseZIndex = i

        -- 悬停效果
        if card.hovered and not card.dragging then
            card.targetY = card.targetY - cfg.hoverLift
            card.targetScale = cfg.hoverScale
            card.targetRotation = 0   -- 悬停时旋转归零
            card.zIndex = 100         -- 悬停牌在最上层
        else
            card.zIndex = card.baseZIndex
        end

        -- 选中效果（叠加在悬停上）
        if card.selected then
            card.targetY = card.targetY - cfg.selectLift
        end

        -- 悬停推开邻牌
        if self.hoveredCard and not card.dragging and card ~= self.hoveredCard then
            local hi = self.hoveredIndex
            local dist = i - hi
            if math.abs(dist) <= 2 then
                local push = cfg.hoverPushApart * (1 - math.abs(dist) / 3)
                if dist < 0 then push = -push end
                card.targetX = card.targetX + push
            end
        end

        ::continue::
    end
end

-- ============================================================================
-- 帧更新
-- ============================================================================

--- 每帧更新（在 HandleUpdate 中调用）
function CardHand:update(dt, mouseX, mouseY)
    local cfg = self.config

    -- 更新 Tween 引擎
    Tween.update(dt)

    -- 查阅模式下不做手牌交互
    if self.inspecting then
        -- 渐入遮罩
        self.inspectOverlayAlpha = Tween.damp(self.inspectOverlayAlpha, 180, 8, dt)
        return
    else
        self.inspectOverlayAlpha = Tween.damp(self.inspectOverlayAlpha, 0, 10, dt)
    end

    -- 动画锁定时不做悬停检测
    if not self.animLocked then
        self:updateHover(mouseX, mouseY)
    end

    -- 更新目标
    self:updateTargets()

    -- 平滑过渡显示值
    local speed = cfg.hoverSpeed
    for _, card in ipairs(self.cards) do
        if not card.dragging and not Tween.isAnimating(card) then
            card.x = Tween.damp(card.x, card.targetX, speed, dt)
            card.y = Tween.damp(card.y, card.targetY, speed, dt)
            card.rotation = Tween.dampAngle(card.rotation, card.targetRotation, speed, dt)
            card.scale = Tween.damp(card.scale, card.targetScale, speed, dt)
        end

        -- 倾斜效果：悬停时根据鼠标位置计算，否则归零
        if card.hovered and not card.dragging then
            -- 鼠标相对卡牌中心的偏移
            local dx = mouseX - card.x
            local dy = mouseY - card.y
            -- 归一化到 [-1, 1]（基于卡牌尺寸）
            local normX = math.max(-1, math.min(1, dx / (Card.WIDTH / 2 * card.scale)))
            local normY = math.max(-1, math.min(1, dy / (Card.HEIGHT / 2 * card.scale)))
            -- tiltX: 鼠标在上方 → 向上倾斜（负值）
            card.targetTiltX = -normY * 15
            card.targetTiltY = normX * 15
        else
            card.targetTiltX = 0
            card.targetTiltY = 0
        end
        card.tiltX = Tween.damp(card.tiltX, card.targetTiltX, 10, dt)
        card.tiltY = Tween.damp(card.tiltY, card.targetTiltY, 10, dt)

        -- 拖拽惯性旋转衰减
        if not card.dragging then
            card.dragTilt = Tween.damp(card.dragTilt, 0, 6, dt)
            card.dragVelX = Tween.damp(card.dragVelX, 0, 8, dt)
            card.dragVelY = Tween.damp(card.dragVelY, 0, 8, dt)
        end
    end

    -- 微抖动（idle wobble）
    local time = 0
    if GetTime then time = GetTime():GetElapsedTime() end
    for _, card in ipairs(self.cards) do
        card.wobbleAmount = math.sin(time * 1.5 + card.wobblePhase) * 0.5
    end

    -- 出牌展示区倒计时
    if #self.showCards > 0 then
        self.showTimer = self.showTimer - dt
        if self.showTimer <= 0 then
            self:clearShowCards()
        end
    end
end

--- 更新悬停检测
function CardHand:updateHover(mouseX, mouseY)
    self.hoveredCard = nil
    self.hoveredIndex = 0

    -- 从上层到下层检测（后绘制的在上层）
    for i = #self.cards, 1, -1 do
        local card = self.cards[i]
        if not card.dragging and card:hitTest(mouseX, mouseY) then
            self.hoveredCard = card
            self.hoveredIndex = i
            break
        end
    end

    -- 设置 hovered 状态
    for _, card in ipairs(self.cards) do
        card.hovered = (card == self.hoveredCard)
    end
end

-- ============================================================================
-- 输入处理
-- ============================================================================

--- 鼠标按下
function CardHand:onMouseDown(x, y, button)
    if self.animLocked then return false end

    -- 查阅模式：任何点击退出
    if self.inspecting then
        self:endInspect()
        return true
    end

    -- 右键查阅
    if button == MOUSEB_RIGHT then
        if self.hoveredCard then
            self:beginInspect(self.hoveredCard)
            return true
        end
        return false
    end

    -- 左键：开始拖拽或选择
    if button == MOUSEB_LEFT and self.hoveredCard then
        self.dragCard = self.hoveredCard
        self.dragIndex = self.hoveredIndex
        self.dragOffsetX = x - self.hoveredCard.x
        self.dragOffsetY = y - self.hoveredCard.y
        self.dragStartX = x
        self.dragStartY = y
        self.dragStarted = false
        return true
    end

    return false
end

--- 鼠标移动
function CardHand:onMouseMove(x, y)
    if not self.dragCard then return false end

    -- 判断是否开始拖拽（移动超过 5px）
    local dx = x - self.dragStartX
    local dy = y - self.dragStartY
    if not self.dragStarted and (dx * dx + dy * dy) > 25 then
        self.dragStarted = true
        self.dragCard.dragging = true
        self.dragCard.zIndex = 200
    end

    if self.dragStarted then
        local card = self.dragCard
        local prevX = card.x
        card.x = x - self.dragOffsetX
        card.y = y - self.dragOffsetY
        card.targetScale = self.config.dragScale
        card.scale = Tween.damp(card.scale, self.config.dragScale, 12, 0.016)
        card.rotation = Tween.dampAngle(card.rotation, 0, 12, 0.016)

        -- 拖拽速度 → 惯性倾斜（卡牌向移动方向反向倾斜）
        local velX = card.x - prevX
        card.dragVelX = velX
        card.dragTilt = Tween.damp(card.dragTilt, -velX * 0.8, 8, 0.016)
        -- 拖拽时倾斜归零
        card.tiltX = 0
        card.tiltY = 0

        -- 计算插入位置
        self:calcInsertIndex(x)
    end

    return self.dragStarted
end

--- 鼠标抬起
function CardHand:onMouseUp(x, y, button)
    if button ~= MOUSEB_LEFT then return false end
    if not self.dragCard then return false end

    local card = self.dragCard

    if self.dragStarted then
        -- 完成拖拽：移动到新位置
        card.dragging = false
        if self.insertIndex > 0 and self.insertIndex ~= self.dragIndex then
            self:reorderCard(self.dragIndex, self.insertIndex)
        end
    else
        -- 点击：切换选中
        card.dragging = false
        self:toggleSelect(card)
    end

    self.dragCard = nil
    self.dragIndex = 0
    self.dragStarted = false
    self.insertIndex = 0
    self:updateTargets()

    return true
end

--- 计算拖拽时的插入位置
function CardHand:calcInsertIndex(mouseX)
    local n = #self.cards
    if n <= 1 then
        self.insertIndex = 1
        return
    end

    -- 找到最近的间隙
    local bestIdx = 1
    local bestDist = math.huge

    for i = 1, n do
        local card = self.cards[i]
        if card ~= self.dragCard then
            local dist = math.abs(mouseX - card.targetX)
            if dist < bestDist then
                bestDist = dist
                bestIdx = i
                -- 如果鼠标在卡牌右侧，插入到右边
                if mouseX > card.targetX then
                    bestIdx = i + 1
                end
            end
        end
    end

    self.insertIndex = math.max(1, math.min(bestIdx, n))
end

--- 重新排列卡牌
function CardHand:reorderCard(fromIdx, toIdx)
    local card = table.remove(self.cards, fromIdx)
    if toIdx > fromIdx then toIdx = toIdx - 1 end
    toIdx = math.max(1, math.min(toIdx, #self.cards + 1))
    table.insert(self.cards, toIdx, card)
end

--- 切换选中状态
function CardHand:toggleSelect(card)
    card.selected = not card.selected

    if card.selected then
        self.selectedCards[card] = true
    else
        self.selectedCards[card] = nil
    end
end

--- 获取选中的卡牌列表
function CardHand:getSelectedCards()
    local result = {}
    for _, card in ipairs(self.cards) do
        if card.selected then
            result[#result + 1] = card
        end
    end
    return result
end

--- 获取选中数量
function CardHand:getSelectedCount()
    local count = 0
    for _ in pairs(self.selectedCards) do count = count + 1 end
    return count
end

-- ============================================================================
-- 动画动作
-- ============================================================================

--- 抽牌（从牌堆抽 N 张到手牌）
function CardHand:drawCards(count, onAllDone)
    count = math.min(count, #self.deck, self.config.maxHandSize - #self.cards)
    if count <= 0 then
        if onAllDone then onAllDone() end
        return
    end

    self:lockAnim(count)

    for i = 1, count do
        local card = table.remove(self.deck, 1)
        if not card then break end

        -- 初始位置：牌堆位置
        card.x = self.deckPos.x
        card.y = self.deckPos.y
        card.rotation = 0
        card.scale = 0.6
        card.opacity = 255
        card.faceUp = false
        card.flipping = true
        card.flipProgress = 0
        card.flipDirection = 1

        -- 加入手牌
        self.cards[#self.cards + 1] = card
        self:updateTargets()

        local targetX = card.targetX
        local targetY = card.targetY
        local targetRot = card.targetRotation

        -- 抽卡动画
        local delay = (i - 1) * self.config.drawStagger
        Tween.to(card, {
            x = targetX,
            y = targetY,
            rotation = targetRot,
            scale = 1.0,
            flipProgress = 1.0,
        }, self.config.drawDuration, {
            easing = Tween.Easing.easeOutBack,
            delay = delay,
            tag = "draw",
            onComplete = function()
                card.flipping = false
                card.faceUp = true
                card.flipProgress = 0
                self:unlockAnim()
                if self.animLockCount <= 0 and onAllDone then
                    onAllDone()
                end
            end
        })
    end
end

--- 出牌（选中的牌飞到出牌区）
function CardHand:playSelected(onDone)
    local selected = self:getSelectedCards()
    if #selected == 0 then
        if onDone then onDone({}) end
        return
    end

    self:lockAnim(#selected)

    -- 清除旧的展示牌
    self:clearShowCards()

    local played = {}
    local centerX = self.playAreaPos.x
    local centerY = self.playAreaPos.y
    local spacing = 60

    -- 先从手牌移除并加入动画数组
    for _, card in ipairs(selected) do
        card.selected = false
        card.hovered = false
        self.selectedCards[card] = nil
        for j = #self.cards, 1, -1 do
            if self.cards[j] == card then
                table.remove(self.cards, j)
                break
            end
        end
        self.animatingCards[#self.animatingCards + 1] = card
    end

    self:updateTargets()

    for i, card in ipairs(selected) do
        -- 目标位置：出牌区横排
        local offsetX = (i - (#selected + 1) / 2) * spacing
        local targetX = centerX + offsetX
        local targetY = centerY

        played[#played + 1] = card

        Tween.to(card, {
            x = targetX,
            y = targetY,
            rotation = 0,
            scale = 1.05,
        }, self.config.playDuration, {
            easing = Tween.Easing.easeOutCubic,
            tag = "play",
            onComplete = function()
                -- 动画完成：从 animatingCards 移到 showCards
                for k = #self.animatingCards, 1, -1 do
                    if self.animatingCards[k] == card then
                        table.remove(self.animatingCards, k)
                        break
                    end
                end
                self.showCards[#self.showCards + 1] = card
                self:unlockAnim()
                if self.animLockCount <= 0 then
                    self.showTimer = 1.5
                    if onDone then onDone(played) end
                end
            end
        })
    end
end

--- 弃牌（选中的牌飞到弃牌堆）
function CardHand:discardSelected(onDone)
    local selected = self:getSelectedCards()
    if #selected == 0 then
        if onDone then onDone({}) end
        return
    end

    self:lockAnim(#selected)

    local discarded = {}

    -- 先从手牌移除并加入动画数组
    for _, card in ipairs(selected) do
        card.selected = false
        card.hovered = false
        self.selectedCards[card] = nil
        discarded[#discarded + 1] = card
        for j = #self.cards, 1, -1 do
            if self.cards[j] == card then
                table.remove(self.cards, j)
                break
            end
        end
        self.animatingCards[#self.animatingCards + 1] = card
    end

    self:updateTargets()

    for i, card in ipairs(discarded) do
        Tween.to(card, {
            x = self.discardPos.x,
            y = self.discardPos.y,
            rotation = 15 + math.random() * 20,
            scale = 0.5,
            opacity = 80,
        }, self.config.discardDuration, {
            easing = Tween.Easing.easeInCubic,
            delay = (i - 1) * 0.05,
            tag = "discard",
            onComplete = function()
                -- 动画完成：从 animatingCards 移到弃牌堆
                for k = #self.animatingCards, 1, -1 do
                    if self.animatingCards[k] == card then
                        table.remove(self.animatingCards, k)
                        break
                    end
                end
                card.opacity = 255
                self.discardPile[#self.discardPile + 1] = card
                self:unlockAnim()
                if self.animLockCount <= 0 and onDone then
                    onDone(discarded)
                end
            end
        })
    end
end

--- 清除展示区
function CardHand:clearShowCards()
    -- 展示区的牌飞走
    for _, card in ipairs(self.showCards) do
        Tween.cancelTarget(card)
        Tween.to(card, {
            y = card.y - 60,
            opacity = 0,
            scale = 0.7,
        }, 0.3, {
            easing = Tween.Easing.easeInCubic,
            tag = "showClear",
        })
    end
    self.showCards = {}
    self.showTimer = 0
end

--- 洗牌重置
function CardHand:resetDeck()
    -- 收回所有牌
    Tween.cancelAll()

    local allCards = {}
    for _, c in ipairs(self.cards) do allCards[#allCards + 1] = c end
    for _, c in ipairs(self.discardPile) do allCards[#allCards + 1] = c end
    for _, c in ipairs(self.playedCards) do allCards[#allCards + 1] = c end
    for _, c in ipairs(self.showCards) do allCards[#allCards + 1] = c end
    for _, c in ipairs(self.animatingCards) do allCards[#allCards + 1] = c end

    self.cards = {}
    self.discardPile = {}
    self.playedCards = {}
    self.showCards = {}
    self.animatingCards = {}
    self.showTimer = 0
    self.selectedCards = {}
    self.animLocked = false
    self.animLockCount = 0
    self.hoveredCard = nil
    self.inspecting = false
    self.dragCard = nil

    -- 重置所有卡牌状态
    for _, card in ipairs(allCards) do
        card.selected = false
        card.hovered = false
        card.dragging = false
        card.faceUp = true
        card.flipping = false
        card.opacity = 255
        card.scale = 1.0
    end

    -- 洗牌放回
    Card.shuffle(allCards)
    self.deck = allCards
end

-- ============================================================================
-- 查阅模式
-- ============================================================================

--- 开始查阅（放大居中展示）
function CardHand:beginInspect(card)
    if self.inspecting then return end
    self.inspecting = true
    self.inspectCard = card

    -- 保存原始位置
    card._savedX = card.targetX
    card._savedY = card.targetY
    card._savedRot = card.targetRotation
    card._savedScale = card.targetScale

    Tween.cancelTarget(card)
    Tween.to(card, {
        x = self.screenW / 2,
        y = self.screenH / 2,
        rotation = 0,
        scale = self.config.inspectScale,
    }, self.config.inspectDuration, {
        easing = Tween.Easing.easeOutCubic,
        tag = "inspect",
    })
end

--- 结束查阅
function CardHand:endInspect()
    if not self.inspecting then return end
    local card = self.inspectCard
    self.inspecting = false

    if card then
        Tween.cancelTarget(card)
        Tween.to(card, {
            x = card._savedX or card.targetX,
            y = card._savedY or card.targetY,
            rotation = card._savedRot or card.targetRotation,
            scale = card._savedScale or 1.0,
        }, self.config.inspectDuration, {
            easing = Tween.Easing.easeOutCubic,
            tag = "inspect",
        })
    end

    self.inspectCard = nil
end

-- ============================================================================
-- 动画锁
-- ============================================================================

function CardHand:lockAnim(count)
    self.animLocked = true
    self.animLockCount = self.animLockCount + (count or 1)
end

function CardHand:unlockAnim()
    self.animLockCount = self.animLockCount - 1
    if self.animLockCount <= 0 then
        self.animLockCount = 0
        self.animLocked = false
    end
end

-- ============================================================================
-- 渲染
-- ============================================================================

--- 绘制完整手牌场景
function CardHand:draw(vg, time)
    -- 1) 背景装饰
    self:drawBackground(vg)

    -- 2) 牌堆 & 弃牌堆
    Card.drawPile(vg, self.deckPos.x, self.deckPos.y, #self.deck, "\xe7\x89\x8c\xe5\xa0\x86")
    Card.drawPile(vg, self.discardPos.x, self.discardPos.y, #self.discardPile, "\xe5\xbc\x83\xe7\x89\x8c\xe5\xa0\x86")

    -- 3) 出牌区
    self:drawPlayArea(vg, time)

    -- 4) 动画中的牌（出牌/弃牌飞行中）
    for _, card in ipairs(self.animatingCards) do
        card:draw(vg, time)
    end

    -- 5) 展示区的牌
    for _, card in ipairs(self.showCards) do
        card:draw(vg, time)
    end

    -- 6) 手牌（按 z 轴排序）
    local sorted = {}
    for i, card in ipairs(self.cards) do
        sorted[#sorted + 1] = { card = card, z = card.zIndex }
    end
    table.sort(sorted, function(a, b) return a.z < b.z end)

    for _, item in ipairs(sorted) do
        local card = item.card
        -- 微动偏移
        local savedY = card.y
        card.y = card.y + card.wobbleAmount
        card:draw(vg, time)
        card.y = savedY
    end

    -- 7) 拖拽中的牌（最上层再画一次）
    if self.dragCard and self.dragStarted then
        -- 插入指示线
        self:drawInsertIndicator(vg)
    end

    -- 8) 查阅遮罩
    if self.inspectOverlayAlpha > 1 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, self.screenW, self.screenH)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(self.inspectOverlayAlpha)))
        nvgFill(vg)

        -- 查阅的牌在遮罩上面
        if self.inspectCard then
            self.inspectCard:draw(vg, time)

            -- 提示文字
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 160))
            nvgText(vg, self.screenW / 2, self.screenH - 40,
                "\xe7\x82\xb9\xe5\x87\xbb\xe4\xbb\xbb\xe6\x84\x8f\xe4\xbd\x8d\xe7\xbd\xae\xe5\x85\xb3\xe9\x97\xad",  -- 点击任意位置关闭
                nil)
        end
    end
end

--- 绘制背景
function CardHand:drawBackground(vg)
    -- 手牌区域底部装饰条
    local areaY = self.config.handY - Card.HEIGHT / 2 - 60
    local areaH = Card.HEIGHT + 120 + self.config.handBottomMargin

    nvgBeginPath(vg)
    nvgRect(vg, 0, areaY, self.screenW, areaH)
    local bg = nvgLinearGradient(vg, 0, areaY, 0, areaY + areaH,
        nvgRGBA(15, 20, 35, 0), nvgRGBA(10, 15, 25, 120))
    nvgFillPaint(vg, bg)
    nvgFill(vg)

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 40, areaY + 10)
    nvgLineTo(vg, self.screenW - 40, areaY + 10)
    nvgStrokeColor(vg, nvgRGBA(80, 100, 140, 40))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

--- 绘制出牌区
function CardHand:drawPlayArea(vg, time)
    local px, py = self.playAreaPos.x, self.playAreaPos.y
    local pw, ph = 300, 150

    -- 虚线框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px - pw / 2, py - ph / 2, pw, ph, 12)
    nvgStrokeColor(vg, nvgRGBA(80, 100, 140, 50))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 标签
    if #self.showCards == 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 120, 150, 80))
        nvgText(vg, px, py,
            "\xe5\x87\xba\xe7\x89\x8c\xe5\x8c\xba",  -- 出牌区
            nil)
    end
end

--- 绘制拖拽插入指示线
function CardHand:drawInsertIndicator(vg)
    if self.insertIndex <= 0 then return end

    local n = #self.cards
    if n <= 0 then return end

    -- 找到插入位置的 X 坐标
    local insertX = self.screenW / 2
    local cfg = self.config
    local spacing = math.min(cfg.cardSpacing, cfg.maxSpread / math.max(1, n))

    -- 简单地在两张牌之间画线
    local idx = math.max(1, math.min(self.insertIndex, n))
    if idx <= n then
        insertX = self.cards[idx].targetX - spacing / 2
    else
        insertX = self.cards[n].targetX + spacing / 2
    end

    local lineY = cfg.handY - Card.HEIGHT / 2 - 15
    local lineH = Card.HEIGHT + 30

    nvgBeginPath(vg)
    nvgMoveTo(vg, insertX, lineY)
    nvgLineTo(vg, insertX, lineY + lineH)
    nvgStrokeColor(vg, nvgRGBA(255, 215, 0, 150))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    -- 小三角
    nvgBeginPath(vg)
    nvgMoveTo(vg, insertX - 6, lineY)
    nvgLineTo(vg, insertX + 6, lineY)
    nvgLineTo(vg, insertX, lineY + 8)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 215, 0, 150))
    nvgFill(vg)
end

return CardHand
