# 数值框架完整代码参考

本文件包含各基类和具体实现的 Lua 代码模板，供实现时直接参考。

## 目录

1. [DamageType 枚举与 DamageInfo](#1-damagetype-与-damageinfo)
2. [AbstractCard 基类](#2-abstractcard-基类)
3. [AbstractPower 基类](#3-abstractpower-基类)
4. [AbstractRelic 基类](#4-abstractrelic-基类)
5. [Creature 结算流程](#5-creature-结算流程)
6. [具体 Power 实现](#6-具体-power-实现)
7. [UI 数值变色](#7-ui-数值变色)

---

## 1. DamageType 与 DamageInfo

```lua
---@enum DamageType
local DamageType = {
    NORMAL = "NORMAL",   -- 普通攻击，受所有修正
    THORNS = "THORNS",   -- 荆棘反伤，跳过力量/虚弱/易伤
    HP_LOSS = "HP_LOSS", -- 生命流失，跳过几乎所有修正
}

---@class DamageInfo
---@field owner Creature   攻击来源
---@field type DamageType  伤害类型
---@field base number      基础值
---@field output number    最终结算值
local DamageInfo = {}
DamageInfo.__index = DamageInfo

function DamageInfo.new(owner, base, damageType)
    return setmetatable({
        owner = owner,
        type = damageType or DamageType.NORMAL,
        base = base,
        output = base,
    }, DamageInfo)
end
```

## 2. AbstractCard 基类

```lua
local AbstractCard = {}
AbstractCard.__index = AbstractCard

function AbstractCard.new(config)
    local self = setmetatable({}, AbstractCard)
    -- 基础值（升级时修改）
    self.baseDamage     = config.baseDamage or 0
    self.baseBlock      = config.baseBlock or 0
    self.baseMagicNumber = config.baseMagicNumber or 0
    self.cost           = config.cost or 1

    -- 修正值（每次展示/使用时重算）
    self.damage         = self.baseDamage
    self.block          = self.baseBlock
    self.magicNumber    = self.baseMagicNumber
    self.costForTurn    = self.cost

    -- UI 变色标记
    self.isDamageModified      = false
    self.isBlockModified       = false
    self.isMagicNumberModified = false

    self.damageType = DamageType.NORMAL
    return self
end

--- 每回合开始调用
function AbstractCard:resetAttributes()
    self.damage         = self.baseDamage
    self.block          = self.baseBlock
    self.magicNumber    = self.baseMagicNumber
    self.costForTurn    = self.cost
    self.isDamageModified      = false
    self.isBlockModified       = false
    self.isMagicNumberModified = false
end

--- 升级相关
function AbstractCard:upgradeDamage(amount)
    self.baseDamage = self.baseDamage + amount
end

function AbstractCard:upgradeBlock(amount)
    self.baseBlock = self.baseBlock + amount
end

function AbstractCard:upgradeMagicNumber(amount)
    self.baseMagicNumber = self.baseMagicNumber + amount
end

--- 面板伤害计算（无目标，仅攻击方修正）
function AbstractCard:applyPowers(player)
    local tmp = self.baseDamage

    -- 1. 遗物修正（管线最前端）
    for _, relic in ipairs(player.relics) do
        tmp = relic:atDamageModify(tmp, self)
    end

    -- 2. 攻击方 Power 修正（按 priority 排序）
    for _, power in ipairs(player:getSortedPowers()) do
        tmp = power:atDamageGive(tmp, self.damageType, self)
    end

    -- 3. 姿态修正
    if player.stance then
        tmp = player.stance:atDamageGive(tmp, self.damageType, self)
    end

    tmp = math.floor(tmp)
    tmp = math.max(0, tmp)

    self.damage = tmp
    self.isDamageModified = (self.damage ~= self.baseDamage)
end

--- 面板伤害计算（含目标方修正，用于实际展示）
function AbstractCard:calculateCardDamage(player, target)
    -- 先做攻击方修正
    self:applyPowers(player)
    local tmp = self.damage

    -- 4. 防御方 Power 修正
    for _, power in ipairs(target:getSortedPowers()) do
        tmp = power:atDamageReceive(tmp, self.damageType, self)
    end

    -- 5. 攻击方最终修正
    for _, power in ipairs(player:getSortedPowers()) do
        tmp = power:atDamageFinalGive(tmp, self.damageType)
    end

    -- 6. 防御方最终修正
    for _, power in ipairs(target:getSortedPowers()) do
        tmp = power:atDamageFinalReceive(tmp, self.damageType)
    end

    tmp = math.floor(tmp)
    tmp = math.max(0, tmp)

    self.damage = tmp
    self.isDamageModified = (self.damage ~= self.baseDamage)
end

--- 格挡计算
function AbstractCard:applyBlockPowers(player)
    local tmp = self.baseBlock

    for _, power in ipairs(player:getSortedPowers()) do
        tmp = power:modifyBlock(tmp, self)
    end
    for _, power in ipairs(player:getSortedPowers()) do
        tmp = power:modifyBlockLast(tmp)
    end

    tmp = math.floor(tmp)
    tmp = math.max(0, tmp)

    self.block = tmp
    self.isBlockModified = (self.block ~= self.baseBlock)
end
```

## 3. AbstractPower 基类

```lua
local AbstractPower = {}
AbstractPower.__index = AbstractPower

function AbstractPower.new(config)
    local self = setmetatable({}, AbstractPower)
    self.id       = config.id or "UnnamedPower"
    self.name     = config.name or self.id
    self.amount   = config.amount or 0
    self.owner    = config.owner       -- 持有者 Creature
    self.priority = config.priority or 0
    self.isTurnBased = config.isTurnBased or false  -- true=持续型(回合倒计时)
    return self
end

--- 伤害修正钩子（默认返回原值，子类按需 override）

-- 攻击方初始修正
function AbstractPower:atDamageGive(dmg, damageType, card)
    return dmg
end

-- 防御方中间修正
function AbstractPower:atDamageReceive(dmg, damageType, card)
    return dmg
end

-- 攻击方最终修正
function AbstractPower:atDamageFinalGive(dmg, damageType)
    return dmg
end

-- 防御方最终修正
function AbstractPower:atDamageFinalReceive(dmg, damageType)
    return dmg
end

--- 格挡修正钩子
function AbstractPower:modifyBlock(block, card)
    return block
end

function AbstractPower:modifyBlockLast(block)
    return block
end

--- 结算阶段钩子
function AbstractPower:onAttackedToChangeDamage(info, dmg)
    return dmg
end

--- 回合生命周期钩子
function AbstractPower:atStartOfTurn() end
function AbstractPower:atEndOfTurn() end
function AbstractPower:onCardDraw(card) end
function AbstractPower:onUseCard(card) end

--- 回合倒计时（持续型 Power 调用）
function AbstractPower:reducePower()
    if self.isTurnBased then
        self.amount = self.amount - 1
        if self.amount <= 0 then
            self:removeSelf()
        end
    end
end
```

## 4. AbstractRelic 基类

```lua
local AbstractRelic = {}
AbstractRelic.__index = AbstractRelic

function AbstractRelic.new(config)
    local self = setmetatable({}, AbstractRelic)
    self.id    = config.id or "UnnamedRelic"
    self.name  = config.name or self.id
    self.owner = config.owner
    self.counter = config.counter or -1  -- -1=不显示计数器
    return self
end

--- 面板计算阶段（管线最前端）
function AbstractRelic:atDamageModify(dmg, card)
    return dmg
end

--- 结算阶段钩子
function AbstractRelic:onAttackToChangeDamage(info, dmg)
    return dmg
end

function AbstractRelic:onAttacked(info, dmg)
    return dmg
end

--- 生命周期钩子
function AbstractRelic:atBattleStart() end
function AbstractRelic:atTurnStart() end
function AbstractRelic:onUseCard(card) end
function AbstractRelic:onGainGold(amount) return amount end
```

## 5. Creature 结算流程

```lua
--- 实际扣血（结算层核心）
function Creature:damage(info)
    local dmg = info.output

    -- 特殊状态：无形 → 伤害强制为 1
    if self:hasPower("Intangible") and dmg > 0 then
        dmg = 1
    end

    -- 扣除格挡
    if self.currentBlock > 0 then
        if dmg > self.currentBlock then
            dmg = dmg - self.currentBlock
            self.currentBlock = 0
        else
            self.currentBlock = self.currentBlock - dmg
            dmg = 0
        end
    end

    -- 遗物保底修正（攻击方）
    if info.owner then
        for _, relic in ipairs(info.owner.relics) do
            dmg = relic:onAttackToChangeDamage(info, dmg)
        end
    end

    -- Power 免伤修正（防御方）
    for _, power in ipairs(self:getSortedPowers()) do
        dmg = power:onAttackedToChangeDamage(info, dmg)
    end

    -- 遗物减免修正（防御方）
    for _, relic in ipairs(self.relics) do
        dmg = relic:onAttacked(info, dmg)
    end

    -- 最终扣血
    dmg = math.max(0, dmg)
    if dmg > 0 then
        self.currentHealth = self.currentHealth - dmg
        -- 触发受伤回调
        self:onDamaged(dmg)
    end

    return dmg
end

--- 获取按 priority 排序的 Power 列表
function Creature:getSortedPowers()
    local sorted = {}
    for _, p in ipairs(self.powers) do
        sorted[#sorted + 1] = p
    end
    table.sort(sorted, function(a, b) return a.priority < b.priority end)
    return sorted
end
```

## 6. 具体 Power 实现

### 力量（Strength）— 永久型，加法

```lua
local StrengthPower = setmetatable({}, { __index = AbstractPower })
StrengthPower.__index = StrengthPower

function StrengthPower.new(owner, amount)
    local self = AbstractPower.new({
        id = "Strength", name = "力量",
        owner = owner, amount = amount,
        priority = 0,       -- 默认优先级（加法先执行）
        isTurnBased = false, -- 永久型
    })
    return setmetatable(self, StrengthPower)
end

function StrengthPower:atDamageGive(dmg, damageType, card)
    if damageType ~= DamageType.NORMAL then return dmg end
    return dmg + self.amount  -- 加法修正
end
```

### 虚弱（Weak）— 持续型，乘法

```lua
local WeakPower = setmetatable({}, { __index = AbstractPower })
WeakPower.__index = WeakPower

function WeakPower.new(owner, amount)
    local self = AbstractPower.new({
        id = "Weak", name = "虚弱",
        owner = owner, amount = amount,
        priority = 99,      -- 高优先级（乘法后执行）
        isTurnBased = true,  -- 持续型（amount=回合数）
    })
    return setmetatable(self, WeakPower)
end

function WeakPower:atDamageGive(dmg, damageType, card)
    if damageType ~= DamageType.NORMAL then return dmg end
    return dmg * 0.75  -- 固定乘数，不依赖 amount
end

function WeakPower:atEndOfTurn()
    self:reducePower()
end
```

### 易伤（Vulnerable）— 持续型，防御方乘法

```lua
local VulnerablePower = setmetatable({}, { __index = AbstractPower })
VulnerablePower.__index = VulnerablePower

function VulnerablePower.new(owner, amount)
    local self = AbstractPower.new({
        id = "Vulnerable", name = "易伤",
        owner = owner, amount = amount,
        priority = 0,
        isTurnBased = true,
    })
    return setmetatable(self, VulnerablePower)
end

function VulnerablePower:atDamageReceive(dmg, damageType, card)
    if damageType ~= DamageType.NORMAL then return dmg end
    return dmg * 1.5
end

function VulnerablePower:atEndOfTurn()
    self:reducePower()
end
```

### 敏捷（Dexterity）— 永久型，格挡加法

```lua
local DexterityPower = setmetatable({}, { __index = AbstractPower })
DexterityPower.__index = DexterityPower

function DexterityPower.new(owner, amount)
    local self = AbstractPower.new({
        id = "Dexterity", name = "敏捷",
        owner = owner, amount = amount,
        priority = 0,
        isTurnBased = false,
    })
    return setmetatable(self, DexterityPower)
end

function DexterityPower:modifyBlock(block, card)
    return block + self.amount
end
```

### 缓冲（Buffer）— 免伤

```lua
local BufferPower = setmetatable({}, { __index = AbstractPower })
BufferPower.__index = BufferPower

function BufferPower.new(owner, amount)
    local self = AbstractPower.new({
        id = "Buffer", name = "缓冲",
        owner = owner, amount = amount,
    })
    return setmetatable(self, BufferPower)
end

function BufferPower:onAttackedToChangeDamage(info, dmg)
    if dmg > 0 then
        self.amount = self.amount - 1
        if self.amount <= 0 then
            self:removeSelf()
        end
        return 0  -- 完全免伤
    end
    return dmg
end
```

## 7. UI 数值变色

```lua
--- 根据 base 和 modified 的比较确定颜色
function getValueColor(base, modified)
    if modified > base then
        return {0.3, 0.9, 0.3, 1.0}  -- 绿色=增强
    elseif modified < base then
        return {0.9, 0.3, 0.3, 1.0}  -- 红色=削弱
    else
        return {1.0, 1.0, 1.0, 1.0}  -- 白色=无变化
    end
end

--- NanoVG 渲染示例
function renderCardDamage(vg, card, x, y)
    local color = getValueColor(card.baseDamage, card.damage)
    nvgFillColor(vg, nvgRGBAf(color[1], color[2], color[3], color[4]))
    nvgText(vg, x, y, tostring(card.damage))
end
```

## 数值验证示例

```
场景：玩家有力量3 + 虚弱，打有易伤的敌人，用6伤害卡

baseDamage = 6
  → 力量(priority=0): 6 + 3 = 9          (加法先)
  → 虚弱(priority=99): 9 × 0.75 = 6.75   (乘法后)
  → 易伤(防御方): 6.75 × 1.5 = 10.125
  → floor + max(0) = 10

如果顺序反了（先乘法再加法）:
  6 × 0.75 = 4.5 → 4.5 + 3 = 7.5 → 7.5 × 1.5 = 11.25 → 11
  结果偏差 10%，这就是为什么顺序必须确定。
```
