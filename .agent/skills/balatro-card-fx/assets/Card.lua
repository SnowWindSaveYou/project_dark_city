-- ============================================================================
-- Card.lua - 卡牌数据 + NanoVG 渲染
-- Balatro 风格：圆角卡牌、阴影、光泽、花色渲染、翻转动画
-- ============================================================================

local Card = {}
Card.__index = Card

-- ============================================================================
-- 常量
-- ============================================================================

Card.WIDTH  = 90   -- 逻辑像素
Card.HEIGHT = 130
Card.RADIUS = 8    -- 圆角

Card.SUITS = { "spade", "heart", "diamond", "club" }
Card.RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }

Card.SUIT_SYMBOLS = {
    spade   = "\xe2\x99\xa0",  -- ♠
    heart   = "\xe2\x99\xa5",  -- ♥
    diamond = "\xe2\x99\xa6",  -- ♦
    club    = "\xe2\x99\xa3",  -- ♣
}

Card.SUIT_COLORS = {
    spade   = { 44,  62,  80,  255 },  -- 深蓝黑
    heart   = { 231, 76,  60,  255 },  -- 红
    diamond = { 230, 126, 34,  255 },  -- 橙红
    club    = { 39,  174, 96,  255 },  -- 绿
}

-- 背面颜色
Card.BACK_COLOR   = { 44, 62, 100, 255 }
Card.BACK_PATTERN = { 52, 73, 120, 255 }

-- ============================================================================
-- 构造
-- ============================================================================

--- 创建一张卡牌
---@param suit string "spade"|"heart"|"diamond"|"club"
---@param rank string "A"|"2"..."K"
---@param id number|nil 唯一标识
function Card.new(suit, rank, id)
    local self = setmetatable({}, Card)

    -- 数据
    self.suit = suit
    self.rank = rank
    self.id = id or 0

    -- 显示状态（渲染直接使用）
    self.x = 0
    self.y = 0
    self.rotation = 0       -- 度
    self.scale = 1.0
    self.opacity = 255

    -- 目标状态（布局计算后设置，用 damp 平滑过渡）
    self.targetX = 0
    self.targetY = 0
    self.targetRotation = 0
    self.targetScale = 1.0

    -- 交互状态
    self.hovered = false
    self.selected = false
    self.dragging = false
    self.faceUp = true

    -- 翻转动画 (0=正面, 1=背面, 动画中间态)
    self.flipProgress = 0   -- 0~1, 0.5时切换正反
    self.flipping = false
    self.flipDirection = 1  -- 1=翻到正面, -1=翻到背面

    -- z 轴排序
    self.zIndex = 0
    self.baseZIndex = 0

    -- 微动 (idle wobble)
    self.wobblePhase = math.random() * math.pi * 2
    self.wobbleAmount = 0    -- 当前抖动量

    -- 悬停倾斜效果（Balatro 3D tilt）
    self.tiltX = 0           -- 垂直倾斜（鼠标上下偏移 → X 轴旋转）
    self.tiltY = 0           -- 水平倾斜（鼠标左右偏移 → Y 轴旋转）
    self.targetTiltX = 0
    self.targetTiltY = 0

    -- 拖拽惯性旋转
    self.dragVelX = 0        -- 拖拽速度 X
    self.dragVelY = 0        -- 拖拽速度 Y
    self.dragTilt = 0        -- 拖拽惯性倾斜角度（度）

    -- 全息闪卡效果
    self.holoEnabled = false  -- 是否为闪卡
    self.holoPhase = math.random() * math.pi * 2  -- 随机相位偏移

    return self
end

--- 创建一副标准 52 张牌
function Card.createDeck()
    local deck = {}
    local id = 1
    for _, suit in ipairs(Card.SUITS) do
        for _, rank in ipairs(Card.RANKS) do
            deck[#deck + 1] = Card.new(suit, rank, id)
            id = id + 1
        end
    end
    return deck
end

--- 洗牌（Fisher-Yates）
function Card.shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(1, i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

-- ============================================================================
-- 碰撞检测
-- ============================================================================

--- 点是否在卡牌内（考虑旋转和缩放）
function Card:hitTest(px, py)
    -- 将点转换到卡牌局部坐标
    local cx, cy = self.x, self.y   -- 卡牌中心
    local dx, dy = px - cx, py - cy

    -- 反向旋转
    local rad = -self.rotation * math.pi / 180
    local cosR = math.cos(rad)
    local sinR = math.sin(rad)
    local lx = dx * cosR - dy * sinR
    local ly = dx * sinR + dy * cosR

    -- 缩放
    lx = lx / self.scale
    ly = ly / self.scale

    local hw = Card.WIDTH / 2
    local hh = Card.HEIGHT / 2
    return lx >= -hw and lx <= hw and ly >= -hh and ly <= hh
end

-- ============================================================================
-- 渲染
-- ============================================================================

--- 绘制卡牌
---@param vg userdata NanoVG context
---@param time number 当前时间（用于动画）
function Card:draw(vg, time)
    local w = Card.WIDTH
    local h = Card.HEIGHT
    local r = Card.RADIUS

    nvgSave(vg)

    -- 移动到卡牌中心
    nvgTranslate(vg, self.x, self.y)

    -- 旋转（含拖拽惯性）
    local totalRotation = self.rotation + self.dragTilt
    if totalRotation ~= 0 then
        nvgRotate(vg, totalRotation * math.pi / 180)
    end

    -- 缩放
    local sx = self.scale
    local sy = self.scale

    -- 翻转效果：水平缩放
    if self.flipping then
        local flipScale = math.abs(math.cos(self.flipProgress * math.pi))
        sx = sx * math.max(0.02, flipScale)
    end

    -- 缩放
    nvgScale(vg, sx, sy)

    -- 倾斜变换模拟 3D 透视（tilt）
    -- NanoVG 坐标系: X 右, Y 下, 已 translate 到卡牌中心
    --
    -- nvgSkewX(angle): c = tan(angle), x' = x + c*y
    --   angle > 0 → 上半(y<0)左移, 下半(y>0)右移 → 顶部向左倾
    --   angle < 0 → 顶部向右倾
    --
    -- nvgSkewY(angle): b = tan(angle), y' = b*x + y
    --   angle > 0 → 左半上移, 右半下移 → 左高右低
    --   angle < 0 → 左低右高
    --
    -- 透视模拟:
    --   鼠标右侧(tiltY>0) → 卡牌顶部应向右倾 → skewX 角度 < 0
    --   鼠标上方(tiltX>0) → 卡牌应"仰起"    → skewY 角度 > 0（左高右低，模拟俯视透视）
    local tiltFactor = 0.012  -- 控制斜切强度（弧度/tilt单位）
    if math.abs(self.tiltX) > 0.1 or math.abs(self.tiltY) > 0.1 then
        nvgSkewX(vg, -self.tiltY * tiltFactor)
        nvgSkewY(vg,  self.tiltX * tiltFactor)
    end

    -- 全局透明度
    nvgGlobalAlpha(vg, self.opacity / 255)

    -- 判断当前显示面
    local showFace = self.faceUp
    if self.flipping then
        showFace = self.flipProgress < 0.5
        if self.flipDirection < 0 then showFace = not showFace end
    end

    -- 1) 阴影（倾斜时阴影偏移更大）
    self:drawShadow(vg, w, h, r)

    if showFace then
        -- 2) 正面
        self:drawFace(vg, w, h, r, time)

        -- 3) 倾斜光泽高光
        if math.abs(self.tiltX) > 0.5 or math.abs(self.tiltY) > 0.5 then
            self:drawTiltShine(vg, w, h, r)
        end

        -- 4) 全息闪卡效果
        if self.holoEnabled and showFace then
            self:drawHoloEffect(vg, w, h, r, time)
        end
    else
        -- 2) 背面
        self:drawBack(vg, w, h, r, time)
    end

    nvgRestore(vg)
end

--- 绘制阴影
function Card:drawShadow(vg, w, h, r)
    local shadowOff = 4
    local shadowBlur = 8
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -w/2 + shadowOff, -h/2 + shadowOff + 2, w, h, r)
    local shadowPaint = nvgBoxGradient(vg,
        -w/2 + shadowOff, -h/2 + shadowOff + 4, w, h,
        r, shadowBlur,
        nvgRGBA(0, 0, 0, 80), nvgRGBA(0, 0, 0, 0))
    nvgFillPaint(vg, shadowPaint)
    nvgFill(vg)
end

--- 绘制正面
function Card:drawFace(vg, w, h, r, time)
    local hw, hh = w / 2, h / 2
    local color = Card.SUIT_COLORS[self.suit] or { 0, 0, 0, 255 }
    local symbol = Card.SUIT_SYMBOLS[self.suit] or "?"

    -- 卡底（白色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, w, h, r)
    nvgFillColor(vg, nvgRGBA(252, 252, 250, 255))
    nvgFill(vg)

    -- 选中高亮
    if self.selected then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -hw, -hh, w, h, r)
        nvgFillColor(vg, nvgRGBA(255, 240, 180, 60))
        nvgFill(vg)
    end

    -- 悬停光泽
    if self.hovered then
        local shine = nvgLinearGradient(vg, -hw, -hh, hw, hh,
            nvgRGBA(255, 255, 255, 30), nvgRGBA(255, 255, 255, 0))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -hw, -hh, w, h, r)
        nvgFillPaint(vg, shine)
        nvgFill(vg)
    end

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, w, h, r)
    if self.hovered then
        nvgStrokeColor(vg, nvgRGBA(255, 215, 0, 200))
        nvgStrokeWidth(vg, 2.5)
    elseif self.selected then
        nvgStrokeColor(vg, nvgRGBA(255, 200, 60, 180))
        nvgStrokeWidth(vg, 2)
    else
        nvgStrokeColor(vg, nvgRGBA(200, 200, 200, 120))
        nvgStrokeWidth(vg, 1)
    end
    nvgStroke(vg)

    -- 花色颜色
    local cr, cg, cb = color[1], color[2], color[3]

    -- 左上角：rank + suit
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(cr, cg, cb, 255))
    nvgText(vg, -hw + 14, -hh + 16, self.rank, nil)
    nvgFontSize(vg, 14)
    nvgText(vg, -hw + 14, -hh + 32, symbol, nil)

    -- 右下角：倒置 rank + suit
    nvgSave(vg)
    nvgTranslate(vg, hw - 14, hh - 16)
    nvgRotate(vg, math.pi)
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, 0, -8, self.rank, nil)
    nvgFontSize(vg, 14)
    nvgText(vg, 0, 8, symbol, nil)
    nvgRestore(vg)

    -- 中心大花色符号
    nvgFontSize(vg, 40)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(cr, cg, cb, 220))
    nvgText(vg, 0, 2, symbol, nil)
end

--- 绘制背面
function Card:drawBack(vg, w, h, r, time)
    local hw, hh = w / 2, h / 2
    local bc = Card.BACK_COLOR
    local bp = Card.BACK_PATTERN

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, w, h, r)
    nvgFillColor(vg, nvgRGBA(bc[1], bc[2], bc[3], bc[4]))
    nvgFill(vg)

    -- 内框装饰
    local inset = 6
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw + inset, -hh + inset, w - inset * 2, h - inset * 2, r - 2)
    nvgStrokeColor(vg, nvgRGBA(bp[1], bp[2], bp[3], 150))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 中心菱形图案
    local dSize = 18
    nvgSave(vg)
    nvgTranslate(vg, 0, 0)
    nvgRotate(vg, math.pi / 4)
    nvgBeginPath(vg)
    nvgRect(vg, -dSize / 2, -dSize / 2, dSize, dSize)
    nvgFillColor(vg, nvgRGBA(bp[1], bp[2], bp[3], 120))
    nvgFill(vg)
    nvgRestore(vg)

    -- 网格纹理
    nvgSave(vg)
    nvgScissor(vg, -hw + inset + 2, -hh + inset + 2,
               w - inset * 2 - 4, h - inset * 2 - 4)
    nvgStrokeColor(vg, nvgRGBA(bp[1], bp[2], bp[3], 30))
    nvgStrokeWidth(vg, 0.8)
    local step = 10
    for gx = -hw + inset, hw - inset, step do
        nvgBeginPath(vg)
        nvgMoveTo(vg, gx, -hh + inset)
        nvgLineTo(vg, gx, hh - inset)
        nvgStroke(vg)
    end
    for gy = -hh + inset, hh - inset, step do
        nvgBeginPath(vg)
        nvgMoveTo(vg, -hw + inset, gy)
        nvgLineTo(vg, hw - inset, gy)
        nvgStroke(vg)
    end
    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, w, h, r)
    nvgStrokeColor(vg, nvgRGBA(80, 100, 140, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

-- ============================================================================
-- 倾斜光泽高光
-- ============================================================================

--- 绘制倾斜时的动态光泽（模拟反射光）
function Card:drawTiltShine(vg, w, h, r)
    local hw, hh = w / 2, h / 2
    -- 光泽位置跟随鼠标倾斜方向偏移（Balatro 风格：光随鼠标走）
    -- tiltY > 0 → 鼠标在右 → 光泽向右(+X)
    -- tiltX > 0 → 鼠标在上 → 光泽向上(-Y，NanoVG Y 轴向下)
    local shineX = self.tiltY * 0.6
    local shineY = -self.tiltX * 0.6
    local intensity = math.sqrt(self.tiltX * self.tiltX + self.tiltY * self.tiltY) / 15
    intensity = math.min(intensity, 1.0) * 60

    nvgSave(vg)
    nvgScissor(vg, -hw, -hh, w, h)

    -- 径向高光
    nvgBeginPath(vg)
    nvgEllipse(vg, shineX, shineY, w * 0.7, h * 0.5)
    local shine = nvgRadialGradient(vg,
        shineX, shineY, 0, w * 0.6,
        nvgRGBA(255, 255, 255, math.floor(intensity)),
        nvgRGBA(255, 255, 255, 0))
    nvgFillPaint(vg, shine)
    nvgFill(vg)

    nvgResetScissor(vg)
    nvgRestore(vg)
end

-- ============================================================================
-- 全息闪卡效果 (Holographic / Foil)
-- ============================================================================

--- 绘制全息彩虹光泽效果
function Card:drawHoloEffect(vg, w, h, r, time)
    local hw, hh = w / 2, h / 2
    -- 彩虹条纹角度随时间和鼠标位置动态变化
    local angle = time * 0.8 + self.holoPhase + self.tiltY * 0.05
    local cosA = math.cos(angle)
    local sinA = math.sin(angle)

    -- 彩虹渐变的偏移受鼠标位置影响
    local shiftX = self.tiltY * 1.5
    local shiftY = self.tiltX * 1.5

    nvgSave(vg)
    -- 裁切到卡牌区域
    nvgScissor(vg, -hw + 1, -hh + 1, w - 2, h - 2)

    -- 多层彩虹条纹叠加
    local colors = {
        { 255, 50,  50  },  -- 红
        { 255, 165, 0   },  -- 橙
        { 255, 255, 50  },  -- 黄
        { 50,  255, 50  },  -- 绿
        { 50,  150, 255 },  -- 蓝
        { 130, 50,  255 },  -- 靛
        { 255, 50,  200 },  -- 紫
    }

    -- 动态透明度（呼吸效果 + 倾斜增强）
    local tiltMag = math.sqrt(self.tiltX * self.tiltX + self.tiltY * self.tiltY)
    local baseAlpha = 25 + tiltMag * 2.5
    local breathe = 1.0 + math.sin(time * 2.0 + self.holoPhase) * 0.3

    -- 绘制多条彩虹条纹
    local stripeW = 35  -- 条纹宽度
    local totalW = #colors * stripeW
    local startOffset = -totalW / 2 + shiftX + math.sin(time * 0.5 + self.holoPhase) * 40

    for i, col in ipairs(colors) do
        local offset = startOffset + (i - 1) * stripeW
        -- 旋转后的条纹起止点
        local x1 = offset * cosA - (-hh) * sinA
        local y1 = offset * sinA + (-hh) * cosA
        local x2 = (offset + stripeW) * cosA - hh * sinA
        local y2 = (offset + stripeW) * sinA + hh * cosA

        local alpha = math.floor(baseAlpha * breathe)
        alpha = math.max(0, math.min(255, alpha))

        nvgBeginPath(vg)
        nvgRoundedRect(vg, -hw, -hh, w, h, r)
        local grad = nvgLinearGradient(vg, x1, y1, x2, y2,
            nvgRGBA(col[1], col[2], col[3], 0),
            nvgRGBA(col[1], col[2], col[3], alpha))
        nvgFillPaint(vg, grad)
        nvgFill(vg)
    end

    -- 闪烁小光点（星尘效果）
    math.randomseed(self.id * 1000)
    local sparkleCount = 6
    for i = 1, sparkleCount do
        local sx = (math.random() - 0.5) * (w - 8)
        local sy = (math.random() - 0.5) * (h - 8)
        local sparkPhase = math.random() * math.pi * 2
        local sparkle = math.sin(time * 3.0 + sparkPhase) * 0.5 + 0.5
        local sparkAlpha = math.floor(sparkle * 80 * breathe)

        if sparkAlpha > 10 then
            nvgBeginPath(vg)
            nvgCircle(vg, sx + shiftX * 0.3, sy + shiftY * 0.3, 1.5 + sparkle * 1.5)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, sparkAlpha))
            nvgFill(vg)
        end
    end
    math.randomseed(os.time())

    -- 整体柔光遮罩
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, w, h, r)
    local holoGlow = nvgRadialGradient(vg,
        shiftX * 0.5, shiftY * 0.5, 0, w * 0.8,
        nvgRGBA(255, 255, 255, math.floor(15 * breathe)),
        nvgRGBA(255, 255, 255, 0))
    nvgFillPaint(vg, holoGlow)
    nvgFill(vg)

    nvgResetScissor(vg)
    nvgRestore(vg)
end

-- ============================================================================
-- 绘制辅助：牌堆（叠放的背面牌）
-- ============================================================================

--- 绘制牌堆
---@param vg userdata NanoVG context
---@param x number 中心 X
---@param y number 中心 Y
---@param count number 剩余张数
---@param label string|nil 标签文字
function Card.drawPile(vg, x, y, count, label)
    local w = Card.WIDTH
    local h = Card.HEIGHT
    local r = Card.RADIUS

    -- 叠放效果（最多显示 4 层）
    local layers = math.min(count, 4)
    for i = layers, 1, -1 do
        local off = (i - 1) * 2
        nvgSave(vg)
        nvgTranslate(vg, x - off * 0.5, y - off)

        -- 阴影
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -w/2 + 2, -h/2 + 3, w, h, r)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 30))
        nvgFill(vg)

        -- 卡背
        local bc = Card.BACK_COLOR
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -w/2, -h/2, w, h, r)
        nvgFillColor(vg, nvgRGBA(bc[1], bc[2], bc[3], bc[4]))
        nvgFill(vg)

        -- 简单边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -w/2, -h/2, w, h, r)
        nvgStrokeColor(vg, nvgRGBA(80, 100, 140, 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgRestore(vg)
    end

    -- 数量标签
    if count > 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, x, y + h / 2 + 14, tostring(count), nil)
    end

    -- 标签
    if label then
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(180, 190, 210, 180))
        nvgText(vg, x, y + h / 2 + 28, label, nil)
    end
end

return Card
