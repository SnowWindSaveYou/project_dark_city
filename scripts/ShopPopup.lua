-- ============================================================================
-- ShopPopup.lua - 商店弹窗系统 (卡牌式横排)
-- shop 卡翻开后弹出 3 张横排商品卡牌，点击即购买，可花钱刷新
-- ============================================================================

local Tween        = require "lib.Tween"
local VFX          = require "lib.VFX"
local Theme        = require "Theme"
local ResourceBar  = require "ResourceBar"
local ItemIcons    = require "ItemIcons"
local AudioManager = require "AudioManager"

local M = {}

-- ---------------------------------------------------------------------------
-- 商品数据
-- ---------------------------------------------------------------------------

local ALL_GOODS = {
    -- 设计文档核心道具
    { icon = "☕", name = "咖啡",       price = 8,  effects = { { "san", 2 } },
      desc = "恢复2点理智",    inventoryKey = "coffee",    iconKey = "coffee" },
    { icon = "🎞️", name = "胶卷",       price = 10, effects = { { "film", 1 } },
      desc = "补充1个胶卷",                                iconKey = "film" },
    { icon = "🧿", name = "护身符",     price = 15, effects = { { "shield", 1 } },
      desc = "抵消1次伤害",    inventoryKey = "shield",    iconKey = "shield" },
    { icon = "🪔", name = "驱魔香",     price = 12, effects = { { "exorcism", 1 } },
      desc = "免侦察驱除怪物", inventoryKey = "exorcism",  iconKey = "exorcism" },
    { icon = "🗺️", name = "地图碎片",   price = 10, effects = { { "mapReveal", 1 } },
      desc = "揭示1张卡牌类型",                            iconKey = "mapReveal" },
    -- 补给型道具 (可存入背包)
    { icon = "💊", name = "镇定剂",     price = 12, effects = { { "san", 3 } },
      desc = "恢复3点理智",    inventoryKey = "sedative",    iconKey = "sedative" },
    { icon = "📜", name = "秩序手册",   price = 10, effects = { { "order", 2 } },
      desc = "恢复2点秩序",    inventoryKey = "orderManual", iconKey = "orderManual" },
}

local SHOP_VARIANTS = {
    { name = "黑市商人",   desc = "\"需要什么？\" 低声问道。" },
    { name = "旧货铺",     desc = "货架上摆满了来源不明的物品。" },
    { name = "自动售货机", desc = "孤零零的售货机嗡嗡作响。" },
}

local RES_ICONS = {
    san       = "🧠",
    order     = "⚖️",
    film      = "🎞️",
    money     = "💰",
    shield    = "🧿",
    exorcism  = "🪔",
    mapReveal = "🗺️",
}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------

local TAG       = "shoppopup"
local TAG_CARD  = "shoppopup_card"
local TAG_FLASH = "shoppopup_flash"

local POPUP_W    = 310
local POPUP_R    = 14
local CARD_W     = 78
local CARD_H     = 110
local CARD_GAP   = 14
local CARD_R     = 10
local CARD_COUNT = 3

local BTN_H      = 28
local BTN_R      = 7
local REFRESH_BTN_W = 100
local LEAVE_BTN_W   = 60
local BTN_GAP    = 14

local REFRESH_COST = 5

-- Layout Y (from top of popup)
local HEADER_Y   = 12
local TITLE_Y    = 40
local DESC_Y     = 58
local DIVIDER_Y  = 76
local CARDS_Y    = 84
local BTN_Y      = CARDS_Y + CARD_H + 10   -- 204
local POPUP_H    = BTN_Y + BTN_H + 14      -- 246

-- ---------------------------------------------------------------------------
-- 道具库存 (背包持久状态)
-- ---------------------------------------------------------------------------

local inventory = {
    shield      = 0,   -- 护身符: 抵消1次伤害
    exorcism    = 0,   -- 驱魔香: 免费驱除1次怪物
    coffee      = 0,   -- 咖啡: 恢复2点理智
    sedative    = 0,   -- 镇定剂: 恢复3点理智
    orderManual = 0,   -- 秩序手册: 恢复2点秩序
}

--- 可消耗道具元数据 (HandPanel 工具栏渲染用)
--- order 决定工具栏排列顺序
local CONSUMABLE_ITEMS = {
    coffee      = { icon = "☕", label = "咖啡",     effects = { { "san", 2 } },   order = 1, iconKey = "coffee" },
    sedative    = { icon = "💊", label = "镇定剂",   effects = { { "san", 3 } },   order = 2, iconKey = "sedative" },
    orderManual = { icon = "📜", label = "秩序手册", effects = { { "order", 2 } }, order = 3, iconKey = "orderManual" },
    exorcism    = { icon = "🪔", label = "驱魔香",   effects = { { "exorcism", 1 } }, order = 4, iconKey = "exorcism" },
}

--- 地图碎片回调 (由 main.lua 注入，购买时立即调用)
local mapRevealCallback = nil

-- ---------------------------------------------------------------------------
-- 道具查询/消耗 API
-- ---------------------------------------------------------------------------

--- 查询道具数量
function M.getItem(key)
    return inventory[key] or 0
end

--- 增加道具 (任意 inventoryKey)
function M.addItem(key, amount)
    amount = amount or 1
    inventory[key] = (inventory[key] or 0) + amount
    print(string.format("[ShopPopup] AddItem %s +%d → %d", key, amount, inventory[key]))
end

--- 消耗道具 (返回是否消耗成功)
function M.useItem(key)
    if (inventory[key] or 0) > 0 then
        inventory[key] = inventory[key] - 1
        print(string.format("[ShopPopup] Used item: %s, remaining: %d", key, inventory[key]))
        return true
    end
    return false
end

--- 使用消耗品并立即结算资源效果 (HandPanel 工具栏调用)
--- 返回 true/false 表示是否使用成功
function M.useConsumable(key)
    local meta = CONSUMABLE_ITEMS[key]
    if not meta then return false end
    if not M.useItem(key) then return false end

    -- 结算效果
    for _, eff in ipairs(meta.effects) do
        local resKey = eff[1]
        local delta  = eff[2]
        -- exorcism 效果由外部回调处理，这里只扣库存
        if resKey ~= "exorcism" then
            ResourceBar.change(resKey, delta)
        end
    end
    return true
end

--- 获取消耗品元数据 (icon/label/effects/order)
function M.getConsumableInfo(key)
    return CONSUMABLE_ITEMS[key]
end

--- 获取所有消耗品的排序列表 (仅返回库存 > 0 的)
--- 返回 { { key="coffee", info={...}, count=2 }, ... } 按 order 升序
function M.getConsumableOrder()
    local list = {}
    for key, info in pairs(CONSUMABLE_ITEMS) do
        local count = inventory[key] or 0
        if count > 0 then
            list[#list + 1] = { key = key, info = info, count = count }
        end
    end
    table.sort(list, function(a, b) return a.info.order < b.info.order end)
    return list
end

--- 注入地图碎片回调
function M.setMapRevealCallback(fn)
    mapRevealCallback = fn
end

--- 重置库存 (新游戏时调用)
function M.resetInventory()
    for key in pairs(inventory) do
        inventory[key] = 0
    end
end

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------

local state = {
    active    = false,
    phase     = "done",   -- "enter"|"idle"|"exit"|"done"

    shopName  = "",
    shopDesc  = "",
    cx = 0, cy = 0,
    onDismiss = nil,

    -- 面板动画
    overlayAlpha = 0,
    popupScale   = 0,
    popupAlpha   = 0,
    headerT      = 0,
    descT        = 0,

    -- 卡牌数据 (每张: item, sold, t, rot, hoverT, purchaseFlash, pulseScale, shakeX)
    cards = {},

    -- 按钮
    refreshT      = 0,
    leaveT        = 0,
    refreshHoverT = 0,
    leaveHoverT   = 0,
    refreshCount  = 0,

    -- 刷新动画阶段
    refreshPhase = "idle",  -- "idle"|"exit"|"enter"
}

-- ---------------------------------------------------------------------------
-- 卡牌位置 (相对弹窗中心)
-- ---------------------------------------------------------------------------

local function cardRelX(i)
    local totalW = CARD_COUNT * CARD_W + (CARD_COUNT - 1) * CARD_GAP
    return -totalW / 2 + (i - 1) * (CARD_W + CARD_GAP) + CARD_W / 2
end

local function cardRelY()
    return -POPUP_H / 2 + CARDS_Y + CARD_H / 2
end

-- ---------------------------------------------------------------------------
-- 碰撞检测
-- ---------------------------------------------------------------------------

local function hitRect(lx, ly, rx, ry, rw, rh)
    return lx >= rx and lx <= rx + rw and ly >= ry and ly <= ry + rh
end

local function cardWorldRect(i)
    local rx = cardRelX(i)
    local ry = cardRelY()
    return state.cx + rx - CARD_W / 2, state.cy + ry - CARD_H / 2, CARD_W, CARD_H
end

local function refreshBtnWorldRect()
    local totalBtnW = REFRESH_BTN_W + BTN_GAP + LEAVE_BTN_W
    local x = state.cx - totalBtnW / 2
    local y = state.cy - POPUP_H / 2 + BTN_Y
    return x, y, REFRESH_BTN_W, BTN_H
end

local function leaveBtnWorldRect()
    local totalBtnW = REFRESH_BTN_W + BTN_GAP + LEAVE_BTN_W
    local x = state.cx - totalBtnW / 2 + REFRESH_BTN_W + BTN_GAP
    local y = state.cy - POPUP_H / 2 + BTN_Y
    return x, y, LEAVE_BTN_W, BTN_H
end

local function panelWorldRect()
    return state.cx - POPUP_W / 2, state.cy - POPUP_H / 2, POPUP_W, POPUP_H
end

-- ---------------------------------------------------------------------------
-- 工具
-- ---------------------------------------------------------------------------

--- Fisher-Yates 抽取 count 件商品
local function pickItems(count)
    count = math.min(count or CARD_COUNT, #ALL_GOODS)
    local indices = {}
    for i = 1, #ALL_GOODS do indices[i] = i end
    for i = 1, count do
        local j = math.random(i, #ALL_GOODS)
        indices[i], indices[j] = indices[j], indices[i]
    end
    local result = {}
    for i = 1, count do
        result[i] = ALL_GOODS[indices[i]]
    end
    return result
end

--- 创建单张卡牌状态
local function newCard(item)
    return {
        item          = item,
        sold          = false,
        t             = 0,       -- 入场进度 (0=隐藏, 1=显示)
        rot           = 0,       -- 旋转角度 (度)
        hoverT        = 0,       -- hover 进度
        purchaseFlash = 0,       -- 购买闪光
        pulseScale    = 1.0,     -- 购买脉冲
        shakeX        = 0,       -- 拒绝抖动
    }
end

-- ---------------------------------------------------------------------------
-- 内部: 购买
-- ---------------------------------------------------------------------------

local function doPurchase(i)
    local card = state.cards[i]
    if not card or card.sold then return end

    local item  = card.item
    local money = ResourceBar.get("money")

    if money < item.price then
        -- 金币不足: 卡牌抖动 + 横幅
        local dummy = { p = 0 }
        Tween.to(dummy, { p = 1 }, 0.4, {
            tag = TAG_CARD,
            onUpdate = function(_, p)
                card.shakeX = math.sin(p * math.pi * 4) * 5 * (1 - p)
            end,
            onComplete = function()
                card.shakeX = 0
            end,
        })
        AudioManager.playSFX("shop_reject")
        VFX.spawnBanner("金币不足!", 220, 80, 80, 20, 0.7)
        return
    end

    -- === 购买成功 ===
    AudioManager.playSFX("shop_buy")
    card.sold = true
    ResourceBar.change("money", -item.price)

    if item.inventoryKey then
        -- 有 inventoryKey → 存入背包
        M.addItem(item.inventoryKey, 1)
    else
        -- 无 inventoryKey → 立即生效 (胶卷、地图碎片等)
        for _, eff in ipairs(item.effects) do
            local key = eff[1]
            if key == "mapReveal" then
                if mapRevealCallback then
                    mapRevealCallback()
                end
            else
                ResourceBar.change(key, eff[2])
            end
        end
    end

    -- 脉冲: 放大 → 弹回
    Tween.to(card, { pulseScale = 1.15 }, 0.12, {
        easing = Tween.Easing.easeOutQuad, tag = TAG_CARD,
        onComplete = function()
            Tween.to(card, { pulseScale = 1.0 }, 0.25, {
                easing = Tween.Easing.easeOutBounce, tag = TAG_CARD,
            })
        end,
    })

    -- 闪光: 绿色覆盖渐消
    card.purchaseFlash = 1.0
    Tween.to(card, { purchaseFlash = 0 }, 0.4, { tag = TAG_FLASH })

    -- 粒子爆发
    local wx = state.cx + cardRelX(i)
    local wy = state.cy + cardRelY()
    local t = Theme.current
    VFX.spawnBurst(wx, wy, 10, t.safe.r, t.safe.g, t.safe.b)

    -- 效果弹出文字
    local popText = ""
    if item.inventoryKey then
        -- 背包道具：显示"获得"
        local icon = item.icon or ""
        popText = icon .. " 获得 "
    else
        for _, eff in ipairs(item.effects) do
            local key = eff[1]
            local icon = RES_ICONS[key] or ""
            if key == "mapReveal" then
                popText = popText .. icon .. " 揭示 "
            else
                popText = popText .. icon .. "+" .. eff[2] .. " "
            end
        end
    end
    VFX.spawnPopup(popText, wx, wy - CARD_H / 2 - 10,
        t.safe.r, t.safe.g, t.safe.b, 0.8)

    print(string.format("[ShopPopup] Bought: %s for %d", item.name, item.price))
end

-- ---------------------------------------------------------------------------
-- 内部: 刷新
-- ---------------------------------------------------------------------------

local function doRefresh()
    if state.refreshPhase ~= "idle" then return end

    local money = ResourceBar.get("money")
    if money < REFRESH_COST then
        AudioManager.playSFX("shop_reject")
        VFX.spawnBanner("金币不足!", 220, 80, 80, 20, 0.7)
        return
    end

    AudioManager.playSFX("shop_refresh")
    ResourceBar.change("money", -REFRESH_COST)
    state.refreshCount = state.refreshCount + 1
    state.refreshPhase = "exit"

    -- === Phase 1: 旧卡牌旋转缩小飞出 ===
    for i = 1, CARD_COUNT do
        local card = state.cards[i]
        local spinDir = (math.random() > 0.5 and 1 or -1)
        local targetRot = spinDir * (10 + math.random() * 10)

        Tween.to(card, { t = 0, rot = targetRot }, 0.22, {
            delay = (i - 1) * 0.05,
            easing = Tween.Easing.easeInBack,
            tag = TAG_CARD,
            onComplete = (i == CARD_COUNT) and function()
                -- === Phase 2: 生成新卡牌 ===
                local items = pickItems(CARD_COUNT)
                for j = 1, CARD_COUNT do
                    state.cards[j] = newCard(items[j])
                end

                state.refreshPhase = "enter"

                -- === Phase 3: 新卡牌弹入 ===
                for j = 1, CARD_COUNT do
                    local c = state.cards[j]
                    local startRot = (math.random() > 0.5 and 1 or -1) * (4 + math.random() * 4)
                    c.rot = startRot

                    Tween.to(c, { t = 1, rot = 0 }, 0.32, {
                        delay = 0.06 + (j - 1) * 0.08,
                        easing = Tween.Easing.easeOutBack,
                        tag = TAG_CARD,
                        onComplete = (j == CARD_COUNT) and function()
                            state.refreshPhase = "idle"
                        end or nil,
                    })
                end
            end or nil,
        })
    end

    print(string.format("[ShopPopup] Refresh #%d", state.refreshCount))
end

-- ---------------------------------------------------------------------------
-- 渲染: 单张商品卡牌
-- ---------------------------------------------------------------------------

local function drawCard(vg, idx, card, theme, shopColor, gameTime)
    local cx = cardRelX(idx)
    local cy = cardRelY()
    local item = card.item

    -- 呼吸浮动 (idle 微动)
    local floatY = math.sin(gameTime * 2.0 + idx * 1.3) * 1.5

    -- Hover 上浮 + 缩放
    local hoverLift  = card.hoverT * 4
    local hoverScale = 1.0 + card.hoverT * 0.04

    nvgSave(vg)
    nvgTranslate(vg, cx + card.shakeX, cy + floatY - hoverLift)
    nvgRotate(vg, math.rad(card.rot))
    local s = card.t * card.pulseScale * hoverScale
    nvgScale(vg, s, s)
    nvgGlobalAlpha(vg, state.popupAlpha * math.min(card.t * 1.5, 1.0))

    local hw = CARD_W / 2
    local hh = CARD_H / 2

    local money     = ResourceBar.get("money")
    local canAfford = money >= item.price

    -- ── 卡牌阴影 ──
    local shadowP = nvgBoxGradient(vg, -hw + 1, -hh + 3, CARD_W, CARD_H, CARD_R, 10,
        nvgRGBA(0, 0, 0, 50), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, -hw - 10, -hh - 8, CARD_W + 20, CARD_H + 18)
    nvgFillPaint(vg, shadowP)
    nvgFill(vg)

    -- ── 卡牌背景 (微渐变) ──
    local bgA = (card.sold or not canAfford) and 210 or 245
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, CARD_W, CARD_H, CARD_R)
    local cf = theme.cardFace
    local bgPaint = nvgLinearGradient(vg, 0, -hh, 0, hh,
        nvgRGBA(math.min(cf.r + 12, 255), math.min(cf.g + 12, 255), math.min(cf.b + 12, 255), bgA),
        nvgRGBA(math.max(cf.r - 6, 0), math.max(cf.g - 6, 0), math.max(cf.b - 6, 0), bgA))
    nvgFillPaint(vg, bgPaint)
    nvgFill(vg)

    -- ── 卡牌边框 ──
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, CARD_W, CARD_H, CARD_R)
    if card.sold then
        nvgStrokeColor(vg, Theme.rgbaA(theme.safe, 200))
        nvgStrokeWidth(vg, 2.0)
    elseif canAfford then
        local ba = 100 + math.floor(card.hoverT * 100)
        nvgStrokeColor(vg, Theme.rgbaA(shopColor, ba))
        nvgStrokeWidth(vg, 1.2 + card.hoverT * 0.8)
    else
        nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 70))
        nvgStrokeWidth(vg, 1.0)
    end
    nvgStroke(vg)

    -- ── Hover 外发光 ──
    if card.hoverT > 0.01 and not card.sold then
        local glowP = nvgBoxGradient(vg, -hw - 2, -hh - 2, CARD_W + 4, CARD_H + 4,
            CARD_R + 1, 8,
            nvgRGBA(shopColor.r, shopColor.g, shopColor.b, math.floor(card.hoverT * 50)),
            nvgRGBA(shopColor.r, shopColor.g, shopColor.b, 0))
        nvgBeginPath(vg)
        nvgRect(vg, -hw - 12, -hh - 12, CARD_W + 24, CARD_H + 24)
        nvgFillPaint(vg, glowP)
        nvgFill(vg)
    end

    -- ── 购买闪光覆盖 ──
    if card.purchaseFlash > 0.01 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -hw, -hh, CARD_W, CARD_H, CARD_R)
        nvgFillColor(vg, nvgRGBA(theme.safe.r, theme.safe.g, theme.safe.b,
            math.floor(card.purchaseFlash * 100)))
        nvgFill(vg)
    end

    -- ── 卡牌内容 ──
    nvgFontFace(vg, "sans")

    if card.sold then
        -- 已购: 整体变暗 + ✓ 勾选
        nvgSave(vg)
        nvgGlobalAlpha(vg, state.popupAlpha * math.min(card.t * 1.5, 1.0) * 0.4)

        -- 图标 (暗淡) — 有纹理图标时使用纹理，否则 fallback emoji
        local iconY = -hh + 22
        if item.iconKey and ItemIcons.draw(vg, item.iconKey, 0, iconY, 22, 100) then
            -- 纹理绘制成功
        else
            nvgFontSize(vg, 22)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, Theme.rgbaA(theme.textPrimary, 100))
            nvgText(vg, 0, iconY, item.icon, nil)
        end

        -- 名称 (暗淡，无论图标走哪条分支都重置文本状态)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgbaA(theme.textPrimary, 100))
        nvgText(vg, 0, -hh + 42, item.name, nil)

        nvgRestore(vg)

        -- ✓ 大勾
        nvgFontSize(vg, 34)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgbaA(theme.safe, 210))
        nvgText(vg, 0, 8, "✓", nil)

        -- "已购" 小字
        nvgFontSize(vg, 11)
        nvgFillColor(vg, Theme.rgbaA(theme.safe, 180))
        nvgText(vg, 0, hh - 14, "已购", nil)
    else
        -- 可购 / 不可购
        local alpha = canAfford and 240 or 130

        -- 图标 — 有纹理图标时使用纹理，否则 fallback emoji
        local iconY = -hh + 22
        if item.iconKey and ItemIcons.draw(vg, item.iconKey, 0, iconY, 22, alpha) then
            -- 纹理绘制成功
        else
            nvgFontSize(vg, 22)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(theme.textPrimary.r, theme.textPrimary.g, theme.textPrimary.b, alpha))
            nvgText(vg, 0, iconY, item.icon, nil)
        end

        -- 名称 (无论图标走哪条分支，都重新设置文本状态)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(theme.textPrimary.r, theme.textPrimary.g, theme.textPrimary.b, alpha))
        nvgText(vg, 0, -hh + 42, item.name, nil)

        -- 效果徽章 / 描述
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local effY = -hh + 60
        if item.inventoryKey and item.desc then
            -- 背包道具：显示描述文字
            nvgFillColor(vg, Theme.rgbaA(theme.info, canAfford and 200 or 110))
            nvgText(vg, 0, effY, item.desc, nil)
        elseif item.desc and item.effects[1] and item.effects[1][1] == "mapReveal" then
            -- 地图碎片等特殊即时道具：也显示描述
            nvgFillColor(vg, Theme.rgbaA(theme.info, canAfford and 200 or 110))
            nvgText(vg, 0, effY, item.desc, nil)
        else
            -- 常规道具 (胶卷等)：显示数值效果
            for _, eff in ipairs(item.effects) do
                local icon = RES_ICONS[eff[1]] or ""
                local label = icon .. " +" .. eff[2]
                nvgFillColor(vg, Theme.rgbaA(theme.safe, canAfford and 200 or 110))
                nvgText(vg, 0, effY, label, nil)
                effY = effY + 14
            end
        end

        -- 价格 (底部)
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local priceColor = canAfford and theme.highlight or theme.danger
        nvgFillColor(vg, Theme.rgbaA(priceColor, canAfford and 240 or 170))
        nvgText(vg, 0, hh - 14, "💰 " .. item.price, nil)

        -- 点击提示: hover 时显示 "点击购买"
        if card.hoverT > 0.3 and canAfford then
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, Theme.rgbaA(shopColor, math.floor(card.hoverT * 160)))
            nvgText(vg, 0, hh - 28, "点击购买", nil)
        end
    end

    nvgRestore(vg)
end

-- ---------------------------------------------------------------------------
-- 渲染: 底部按钮
-- ---------------------------------------------------------------------------

local function drawButtons(vg, theme, shopColor, gameTime)
    local hh        = POPUP_H / 2
    local totalBtnW = REFRESH_BTN_W + BTN_GAP + LEAVE_BTN_W
    local startX    = -totalBtnW / 2
    local btnBaseY  = -hh + BTN_Y

    local money      = ResourceBar.get("money")
    local canRefresh = money >= REFRESH_COST and state.refreshPhase == "idle"

    -- ── 刷新按钮 ──
    if state.refreshT > 0.01 then
        nvgSave(vg)
        local rx = startX + REFRESH_BTN_W / 2
        local ry = btnBaseY + BTN_H / 2
        nvgTranslate(vg, rx, ry + (1 - state.refreshT) * 15)
        nvgScale(vg, state.refreshT, state.refreshT)
        nvgGlobalAlpha(vg, state.popupAlpha * state.refreshT)

        local hoverLerp = state.refreshHoverT
        local bScale = 1.0 + hoverLerp * 0.05
        nvgScale(vg, bScale, bScale)

        -- 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -REFRESH_BTN_W / 2, -BTN_H / 2, REFRESH_BTN_W, BTN_H, BTN_R)
        if canRefresh then
            local r = math.floor(shopColor.r + (255 - shopColor.r) * hoverLerp * 0.25)
            local g = math.floor(shopColor.g + (255 - shopColor.g) * hoverLerp * 0.25)
            local b = math.floor(shopColor.b + (255 - shopColor.b) * hoverLerp * 0.25)
            nvgFillColor(vg, nvgRGBA(r, g, b, 185))
        else
            nvgFillColor(vg, nvgRGBA(100, 100, 100, 80))
        end
        nvgFill(vg)

        -- Hover 外发光
        if hoverLerp > 0.01 and canRefresh then
            local glowP = nvgBoxGradient(vg,
                -REFRESH_BTN_W / 2 - 2, -BTN_H / 2 - 2,
                REFRESH_BTN_W + 4, BTN_H + 4, BTN_R + 1, 6,
                nvgRGBA(255, 255, 255, math.floor(hoverLerp * 35)),
                nvgRGBA(255, 255, 255, 0))
            nvgBeginPath(vg)
            nvgRect(vg, -REFRESH_BTN_W / 2 - 10, -BTN_H / 2 - 10,
                REFRESH_BTN_W + 20, BTN_H + 20)
            nvgFillPaint(vg, glowP)
            nvgFill(vg)
        end

        -- 文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local tAlpha = canRefresh and 235 or 100
        nvgFillColor(vg, nvgRGBA(255, 255, 255, tAlpha))
        nvgText(vg, 0, 0, "🔄 刷新 💰" .. REFRESH_COST, nil)

        nvgRestore(vg)
    end

    -- ── 离开按钮 ──
    if state.leaveT > 0.01 then
        nvgSave(vg)
        local lx = startX + REFRESH_BTN_W + BTN_GAP + LEAVE_BTN_W / 2
        local ly = btnBaseY + BTN_H / 2
        nvgTranslate(vg, lx, ly + (1 - state.leaveT) * 15)
        nvgScale(vg, state.leaveT, state.leaveT)
        nvgGlobalAlpha(vg, state.popupAlpha * state.leaveT)

        local hoverLerp = state.leaveHoverT
        local bScale = 1.0 + hoverLerp * 0.05
        nvgScale(vg, bScale, bScale)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, -LEAVE_BTN_W / 2, -BTN_H / 2, LEAVE_BTN_W, BTN_H, BTN_R)
        local br = math.floor(theme.textSecondary.r + (255 - theme.textSecondary.r) * hoverLerp * 0.3)
        local bg = math.floor(theme.textSecondary.g + (255 - theme.textSecondary.g) * hoverLerp * 0.3)
        local bb = math.floor(theme.textSecondary.b + (255 - theme.textSecondary.b) * hoverLerp * 0.3)
        nvgFillColor(vg, nvgRGBA(br, bg, bb, 140))
        nvgFill(vg)

        if hoverLerp > 0.01 then
            local glowP = nvgBoxGradient(vg,
                -LEAVE_BTN_W / 2 - 2, -BTN_H / 2 - 2,
                LEAVE_BTN_W + 4, BTN_H + 4, BTN_R + 1, 6,
                nvgRGBA(255, 255, 255, math.floor(hoverLerp * 30)),
                nvgRGBA(255, 255, 255, 0))
            nvgBeginPath(vg)
            nvgRect(vg, -LEAVE_BTN_W / 2 - 10, -BTN_H / 2 - 10,
                LEAVE_BTN_W + 20, BTN_H + 20)
            nvgFillPaint(vg, glowP)
            nvgFill(vg)
        end

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgText(vg, 0, 0, "离开", nil)

        nvgRestore(vg)
    end
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

function M.show(cx, cy, onDismiss)
    local variant = SHOP_VARIANTS[math.random(1, #SHOP_VARIANTS)]
    local items   = pickItems(CARD_COUNT)

    state.active       = true
    state.phase        = "enter"
    state.shopName     = variant.name
    state.shopDesc     = variant.desc
    state.cx           = cx
    state.cy           = cy
    state.onDismiss    = onDismiss
    state.refreshCount = 0
    state.refreshPhase = "idle"

    -- 面板动画重置
    state.overlayAlpha  = 0
    state.popupScale    = 0.3
    state.popupAlpha    = 0
    state.headerT       = 0
    state.descT         = 0
    state.refreshT      = 0
    state.leaveT        = 0
    state.refreshHoverT = 0
    state.leaveHoverT   = 0

    -- 创建卡牌
    state.cards = {}
    for i = 1, CARD_COUNT do
        state.cards[i] = newCard(items[i])
    end

    -- === 入场编排 ===

    -- 面板整体
    Tween.to(state, { overlayAlpha = 0.45, popupScale = 1.0, popupAlpha = 1.0 }, 0.35, {
        easing = Tween.Easing.easeOutBack, tag = TAG,
    })

    local base    = 0.12
    local stagger = 0.07

    -- 标题/描述
    Tween.to(state, { headerT = 1 }, 0.3, {
        delay = base, easing = Tween.Easing.easeOutBack, tag = TAG,
    })
    Tween.to(state, { descT = 1 }, 0.25, {
        delay = base + stagger, easing = Tween.Easing.easeOutCubic, tag = TAG,
    })

    -- 三张卡牌: 错时弹入 + 微旋转归零
    for i = 1, CARD_COUNT do
        local c = state.cards[i]
        c.rot = (math.random() > 0.5 and 1 or -1) * (3 + math.random() * 5)

        Tween.to(c, { t = 1, rot = 0 }, 0.35, {
            delay = base + stagger * (i + 1),
            easing = Tween.Easing.easeOutBack,
            tag = TAG_CARD,
        })
    end

    -- 按钮
    local btnDelay = base + stagger * (CARD_COUNT + 2)
    Tween.to(state, { refreshT = 1 }, 0.25, {
        delay = btnDelay, easing = Tween.Easing.easeOutBack, tag = TAG,
    })
    Tween.to(state, { leaveT = 1 }, 0.25, {
        delay = btnDelay + 0.06, easing = Tween.Easing.easeOutBack, tag = TAG,
        onComplete = function()
            state.phase = "idle"
        end,
    })

    print(string.format("[ShopPopup] Show: %s (%d cards)", variant.name, CARD_COUNT))
end

function M.dismiss()
    if not state.active or state.phase == "exit" then return end
    state.phase = "exit"

    Tween.cancelTag(TAG)
    Tween.cancelTag(TAG_CARD)
    Tween.cancelTag(TAG_FLASH)

    -- 卡牌旋转飞散
    for i = 1, CARD_COUNT do
        local c = state.cards[i]
        if c then
            local spinDir = (i == 2) and 0 or ((i == 1) and -1 or 1)
            Tween.to(c, { t = 0, rot = spinDir * 15 }, 0.2, {
                delay = (i - 1) * 0.03,
                easing = Tween.Easing.easeInBack, tag = TAG_CARD,
            })
        end
    end

    Tween.to(state, {
        overlayAlpha = 0, popupScale = 0.5, popupAlpha = 0,
        headerT = 0, descT = 0, refreshT = 0, leaveT = 0,
    }, 0.25, {
        delay = 0.08,
        easing = Tween.Easing.easeInBack, tag = TAG,
        onComplete = function()
            state.active = false
            state.phase  = "done"
            state.cards  = {}
            if state.onDismiss then state.onDismiss() end
        end,
    })
end

function M.isActive()
    return state.active
end

-- ---------------------------------------------------------------------------
-- 交互
-- ---------------------------------------------------------------------------

function M.handleClick(lx, ly)
    if not state.active then return false end
    if state.phase == "enter" or state.phase == "exit" then return true end
    if state.refreshPhase ~= "idle" then return true end

    -- 检测卡牌点击
    for i = 1, CARD_COUNT do
        local rx, ry, rw, rh = cardWorldRect(i)
        if hitRect(lx, ly, rx, ry, rw, rh) then
            local card = state.cards[i]
            if card.sold then
                -- 已购: 抖动
                local dummy = { p = 0 }
                Tween.to(dummy, { p = 1 }, 0.3, {
                    tag = TAG_CARD,
                    onUpdate = function(_, p)
                        card.shakeX = math.sin(p * math.pi * 3) * 3 * (1 - p)
                    end,
                    onComplete = function() card.shakeX = 0 end,
                })
            else
                doPurchase(i)
            end
            return true
        end
    end

    -- 检测刷新按钮
    if state.refreshT > 0.5 then
        local rx, ry, rw, rh = refreshBtnWorldRect()
        if hitRect(lx, ly, rx, ry, rw, rh) then
            doRefresh()
            return true
        end
    end

    -- 检测离开按钮
    if state.leaveT > 0.5 then
        local rx, ry, rw, rh = leaveBtnWorldRect()
        if hitRect(lx, ly, rx, ry, rw, rh) then
            M.dismiss()
            return true
        end
    end

    -- 面板外 → 关闭
    local px, py, pw, ph = panelWorldRect()
    if not hitRect(lx, ly, px, py, pw, ph) then
        M.dismiss()
        return true
    end

    return true
end

function M.handleKey(key)
    if not state.active then return false end
    if state.phase ~= "idle" then return true end

    if key == KEY_RETURN or key == KEY_SPACE or key == KEY_ESCAPE then
        M.dismiss()
        return true
    end
    return true
end

function M.updateHover(lx, ly, dt)
    if not state.active then return end

    local speed = math.min(1, dt * 12)

    -- 卡牌 hover
    for i = 1, CARD_COUNT do
        local card = state.cards[i]
        if card then
            local target = 0
            if state.phase == "idle" and state.refreshPhase == "idle" and not card.sold then
                local rx, ry, rw, rh = cardWorldRect(i)
                if hitRect(lx, ly, rx, ry, rw, rh) then
                    target = 1
                end
            end
            card.hoverT = card.hoverT + (target - card.hoverT) * speed
        end
    end

    -- 刷新按钮 hover
    local rTarget = 0
    if state.phase == "idle" and state.refreshPhase == "idle" and state.refreshT > 0.5 then
        local money = ResourceBar.get("money")
        if money >= REFRESH_COST then
            local rx, ry, rw, rh = refreshBtnWorldRect()
            if hitRect(lx, ly, rx, ry, rw, rh) then
                rTarget = 1
            end
        end
    end
    state.refreshHoverT = state.refreshHoverT + (rTarget - state.refreshHoverT) * speed

    -- 离开按钮 hover
    local lTarget = 0
    if state.phase == "idle" and state.leaveT > 0.5 then
        local rx, ry, rw, rh = leaveBtnWorldRect()
        if hitRect(lx, ly, rx, ry, rw, rh) then
            lTarget = 1
        end
    end
    state.leaveHoverT = state.leaveHoverT + (lTarget - state.leaveHoverT) * speed
end

-- ---------------------------------------------------------------------------
-- 渲染
-- ---------------------------------------------------------------------------

function M.draw(vg, logicalW, logicalH, gameTime)
    if not state.active then return end
    local t  = Theme.current
    local tc = Theme.cardTypeColor("shop")  -- info 蓝

    -- === 遮罩 ===
    if state.overlayAlpha > 0.01 then
        nvgBeginPath(vg)
        nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(state.overlayAlpha * 255)))
        nvgFill(vg)
    end

    -- === 面板 ===
    nvgSave(vg)
    nvgTranslate(vg, state.cx, state.cy)
    nvgScale(vg, state.popupScale, state.popupScale)
    nvgGlobalAlpha(vg, state.popupAlpha)

    local hw = POPUP_W / 2
    local hh = POPUP_H / 2

    -- 阴影
    local shadowP = nvgBoxGradient(vg, -hw + 2, -hh + 4, POPUP_W, POPUP_H, POPUP_R, 18,
        nvgRGBA(0, 0, 0, 65), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, -hw - 20, -hh - 16, POPUP_W + 40, POPUP_H + 40)
    nvgFillPaint(vg, shadowP)
    nvgFill(vg)

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, POPUP_W, POPUP_H, POPUP_R)
    nvgFillColor(vg, nvgRGBA(t.panelBg.r, t.panelBg.g, t.panelBg.b, 245))
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, POPUP_W, POPUP_H, POPUP_R)
    nvgStrokeColor(vg, Theme.rgbaA(t.panelBorder, 120))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    -- 顶部色条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw + 4, -hh + 4, POPUP_W - 8, 5, 3)
    nvgFillColor(vg, Theme.rgbaA(tc, 200))
    nvgFill(vg)

    -- ── Header ──
    if state.headerT > 0.01 then
        nvgSave(vg)
        nvgGlobalAlpha(vg, state.popupAlpha * state.headerT)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 26)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, Theme.rgba(t.textPrimary))
        nvgText(vg, 0, -hh + HEADER_Y, "🛒", nil)

        nvgFontSize(vg, 15)
        nvgFillColor(vg, Theme.rgba(tc))
        nvgText(vg, 0, -hh + TITLE_Y, state.shopName, nil)

        nvgRestore(vg)
    end

    -- ── 描述 ──
    if state.descT > 0.01 then
        nvgSave(vg)
        nvgGlobalAlpha(vg, state.popupAlpha * state.descT)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 180))
        nvgText(vg, 0, -hh + DESC_Y + (1 - state.descT) * 6, state.shopDesc, nil)

        nvgRestore(vg)
    end

    -- ── 分割线 ──
    nvgBeginPath(vg)
    nvgMoveTo(vg, -hw + 16, -hh + DIVIDER_Y)
    nvgLineTo(vg, hw - 16, -hh + DIVIDER_Y)
    nvgStrokeColor(vg, Theme.rgbaA(t.panelBorder, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ── 三张卡牌 ──
    for i = 1, CARD_COUNT do
        local card = state.cards[i]
        if card and card.t > 0.01 then
            drawCard(vg, i, card, t, tc, gameTime)
        end
    end

    -- ── 按钮 ──
    drawButtons(vg, t, tc, gameTime)

    nvgRestore(vg)
end

return M
