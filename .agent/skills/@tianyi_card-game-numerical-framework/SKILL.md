---
name: card-game-numerical-framework
description: |
  构建类杀戮尖塔的卡牌游戏数值管理框架。涵盖双层数值体系、修正链管线、
  Buff/Debuff 钩子系统、伤害类型分流、遗物被动触发。
  Use when: (1) 开发卡牌 Roguelike 或回合制战斗游戏,
  (2) 需要设计伤害计算管线（加法/乘法修正链）,
  (3) 需要实现 Buff/Debuff（Power）系统,
  (4) 需要实现遗物/被动装备的钩子体系,
  (5) 需要处理多种伤害类型（普通/荆棘/生命流失）的分流逻辑,
  (6) 需要数值驱动型游戏的架构设计参考。
---

# 卡牌游戏数值管理框架

基于杀戮尖塔（Slay the Spire）反编译代码总结的数值管理架构。

## 核心架构：三层设计

```
┌─────────────────────────────────────────────────┐
│                  数据层（Data）                    │
│  Card.baseDamage / baseBlock / baseMagicNumber  │
│  → 只在升级或永久事件时改变                         │
├─────────────────────────────────────────────────┤
│              修正层（Modifier Pipeline）           │
│  Relic → Power(加法) → Power(乘法) → Stance      │
│  → 每次展示/使用时实时计算                          │
├─────────────────────────────────────────────────┤
│               结算层（Resolution）                 │
│  格挡扣除 → 保底/减免 → 扣血                       │
│  → 实际造成伤害时执行                              │
└─────────────────────────────────────────────────┘
```

## 设计原则

1. **基础值不可变（每回合重置）** — 保证可预测性
2. **修正链有确定顺序** — 加法先于乘法，攻击方先于防御方
3. **钩子默认返回原值** — 子类只 override 关心的钩子
4. **DamageType 控制修正范围** — 不同伤害类型走不同修正路径
5. **遗物管触发、Power 管数值** — 职责分离

## 一、卡牌双层数值体系

每个数值字段有 base 和 modified 两层：

```lua
-- 基础值 — 卡牌固有属性（升级时改 base）
baseDamage = 6
baseBlock = 5
baseMagicNumber = 1
cost = 1

-- 修正值 — 经 Power/Relic 计算后的实际值（每帧/每次展示重算）
damage = 0
block = 0
magicNumber = 0
costForTurn = 0

-- 修正标记 — UI 变色：绿=增强 红=削弱 白=无变化
isDamageModified = false
```

- **每回合重置**: `resetAttributes()` 将 modified 值重置为 base 值
- **升级改 base**: `upgradeDamage(amount)` → `baseDamage += amount`

## 二、伤害计算管线（核心）

### 面板伤害（展示用）

```
baseDamage
  → [Relic]  atDamageModify(dmg, card)        -- 遗物最先介入
  → [Power]  atDamageGive(dmg, type, card)     -- 攻击方(力量+N，加法)
  → [Power]  atDamageGive(dmg, type, card)     -- 攻击方(虚弱×0.75，乘法，高priority)
  → [Stance] atDamageGive(dmg, type, card)     -- 姿态修正(愤怒×2)
  → [Power]  atDamageReceive(dmg, type, card)  -- 防御方(易伤×1.5)
  → [Power]  atDamageFinalGive(dmg, type)      -- 攻击方最终修正
  → [Power]  atDamageFinalReceive(dmg, type)   -- 防御方最终修正
  → floor() + max(0)                           -- 取整 + 非负
```

### 实际结算（扣血用）

```
面板伤害
  → [特殊状态] 无形 → 强制=1
  → 扣除格挡
  → [Relic]  onAttackToChangeDamage(info, dmg)   -- 保底(战靴:<5→5)
  → [Power]  onAttackedToChangeDamage(info, dmg)  -- 免伤(缓冲:→0)
  → [Relic]  onAttacked(info, dmg)                -- 减免(鸟居:2~5→1)
  → currentHealth -= damageAmount
```

### DamageType 分流

| 类型 | 说明 | 修正范围 |
|------|------|---------|
| `NORMAL` | 普通攻击 | 受所有修正影响 |
| `THORNS` | 荆棘反伤 | 跳过力量/虚弱/易伤 |
| `HP_LOSS` | 生命流失 | 跳过几乎所有修正 |

Power 钩子内必须检查 `type == NORMAL` 再修正，非 NORMAL 直接返回原值。

## 三、Power（Buff/Debuff）钩子体系

### 伤害修正钩子（按执行顺序）

| 钩子 | 归属 | 典型实现 |
|------|------|---------|
| `atDamageGive(dmg, type, card)` | 攻击方 | 力量: `dmg + amount` |
| `atDamageGive(dmg, type, card)` | 攻击方 | 虚弱: `dmg × 0.75`（高 priority） |
| `atDamageReceive(dmg, type, card)` | 防御方 | 易伤: `dmg × 1.5` |
| `atDamageFinalGive(dmg, type)` | 攻击方 | 特殊二次修正 |
| `atDamageFinalReceive(dmg, type)` | 防御方 | 特殊二次修正 |

### 格挡修正

```
baseBlock → modifyBlock(block, card) → modifyBlockLast(block) → floor()
```

### amount 两种语义

- **永久型**（力量/敏捷）: `amount` 直接参与计算
- **持续型**（虚弱/易伤）: `amount` 仅为回合倒计时，乘数固定

### 执行顺序控制

`priority` 字段，默认 0。虚弱设 `priority = 99` 确保力量(加法)先于虚弱(乘法)。

## 四、Relic（遗物）钩子体系

两种数值介入模式：

**模式 A — 直接修正**:
`atDamageModify(dmg, card)` 在管线最前端，会被后续乘法放大。

**模式 B — 通过施加 Power 间接修正**（推荐）:
遗物负责计数和触发，通过 `ApplyPowerAction` 施加临时 Power，Power 负责数值修正。

```
示例: 笔尖遗物
onUseCard → 攻击牌计数 → 第9张施加 PenNibPower → Power.atDamageGive 翻倍
```

## 五、常见陷阱

1. **加法乘法顺序**: 必须先加法再乘法，否则数值偏差大
2. **取整时机**: 中间计算用 float，只在最终结果 `floor` 一次
3. **非负保证**: 修正后伤害可能为负，必须 `max(0, result)`
4. **回合重置遗漏**: 忘记重置 `costForTurn` 导致跨回合 bug
5. **DamageType 检查遗漏**: 钩子内忘记检查 type 导致荆棘/中毒也被力量加成

## 六、实现清单

按此顺序实现：

1. DamageType 枚举
2. DamageInfo 封装（owner, type, base, output）
3. AbstractCard 双层数值 + `resetAttributes()`
4. AbstractPower 基类（钩子默认返回原值）
5. `applyPowers()` 修正链管线
6. `calculateCardDamage(target)` 含目标方修正
7. AbstractRelic 基类 + `atDamageModify` 钩子
8. `Creature.damage()` 实际结算流程
9. 具体 Power（力量/虚弱/易伤/敏捷）
10. 具体 Relic
11. UI 数值变色（base vs modified 比较）

## 详细参考

完整代码示例、基类模板、具体 Power/Relic 实现 → 见 [references/reference.md](references/reference.md)
