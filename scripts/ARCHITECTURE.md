# 暗面都市 - 架构与模块使用文档

> 供后续 AI Agent 阅读，避免重复造轮子或引入不一致的实现。

---

## 目录结构

```
scripts/
├── main.lua            # 入口，事件注册，状态机，渲染主循环
├── Theme.lua           # 统一色彩/字号/间距，卡牌类型视觉映射
├── Card.lua            # 卡牌数据 + NanoVG 渲染 + 翻牌/发牌/抖动/变形动画
├── Board.lua           # 5x5 棋盘，螺旋发牌，碰撞检测
├── Token.lua           # 玩家棋子 (chibi)，弧形跳跃移动
├── ResourceBar.lua     # 底部资源 HUD (San/Order/Film/Money)
├── EventPopup.lua      # 翻牌事件弹窗 (遮罩 + 逐行入场 + 确认按钮)
├── CameraButton.lua    # 悬浮相机按钮 + 取景器叠加层 (拍摄/驱除)
├── ShopPopup.lua       # 商店弹窗 (商品列表 + 实时购买 + 离开)
├── TitleScreen.lua     # 标题画面 (氛围入场 + 浮动卡牌 + 点击开始)
├── GameOver.lua        # 结算画面 (胜/负 + 统计 + 重新开始)
└── lib/
    ├── Tween.lua       # 通用动画引擎 (缓动/延迟/回调/标签)
    └── VFX.lua         # 全局视觉特效 (屏幕震动/飘字/粒子/过渡/闪光)
```

---

## 1. Tween.lua — 动画引擎

**唯一的动画驱动**。所有模块的动画都通过 Tween 实现，禁止自造动画循环。

### 核心 API

```lua
local Tween = require "lib.Tween"

-- 创建动画 (直接修改 target 的属性)
Tween.to(target, { x = 100, alpha = 1.0 }, 0.5, {
    delay    = 0.1,                        -- 延迟启动(秒)
    easing   = Tween.Easing.easeOutBack,   -- 缓动函数
    tag      = "mytag",                    -- 标签，用于批量取消
    onUpdate = function(target, t) end,    -- 每帧回调 (t: 0→1 原始进度)
    onComplete = function(target) end,     -- 完成回调
})

-- 取消
Tween.cancelTarget(target)   -- 取消 target 上的所有动画
Tween.cancelTag("mytag")     -- 取消指定标签
Tween.cancelAll()             -- 取消全部

-- 查询
Tween.count()                 -- 活跃动画数
Tween.isAnimating(target)     -- target 是否有活跃动画

-- 每帧调用 (已在 main.lua HandleUpdate 中调用)
Tween.update(dt)

-- 工具
Tween.damp(current, target, speed, dt)       -- 平滑逼近(指数衰减)
Tween.dampAngle(current, target, speed, dt)  -- 角度平滑逼近
```

### 可用缓动函数 (Tween.Easing.*)

| 函数 | 用途 |
|------|------|
| `linear` | 线性 |
| `easeInQuad` / `easeOutQuad` / `easeInOutQuad` | 二次 |
| `easeInCubic` / `easeOutCubic` / `easeInOutCubic` | 三次 |
| `easeOutQuart` | 四次减速 |
| `easeOutBack` / `easeInBack` | 回弹过冲 (卡牌弹入最爱) |
| `easeOutElastic` | 弹性 (落地恢复) |
| `easeOutBounce` | 弹跳 (落地效果) |
| `easeInOutSine` | 平滑呼吸 |

### 使用约定

- **tag 命名**：`"cardflip"` `"carddeal"` `"cardshake"` `"cardtransform"` `"tokenmove"` `"token"` `"popup"` `"popup_delay"` `"camerabtn"` `"cameramode"` `"camerabtn_shake"` `"photograph"` `"exorcise"` `"daytransition"` `"resource_xxx"` `"resource_delta_xxx"` `"shoppopup"` `"shoppopup_card"` `"shoppopup_flash"` `"titlescreen"` `"gameover"`
- **hover 动画不用 Tween**：hover 追踪用每帧手动 lerp（`dt * 12`），避免创建大量 Tween 实例。见 main.lua `updateHover()`。

---

## 2. VFX.lua — 全局视觉特效

**共享特效层**，不属于任何特定模块。在 main.lua 中统一渲染。

### 初始化 (每帧)

```lua
VFX.setContext(vg, logicalW, logicalH, gameTime)  -- 必须在 nvgBeginFrame 之后调用
VFX.updateAll(dt)                                  -- 在 HandleUpdate 中调用
```

### 特效 API

```lua
-- 屏幕震动
VFX.triggerShake(intensity, duration, frequency?)
-- 使用: nvgTranslate(vg, VFX.getShakeOffset()) 偏移画面

-- 飘字横幅 (逐字错时弹入，中屏显示)
VFX.spawnBanner(text, r, g, b, fontSize, duration)

-- 粒子爆发 (从指定点向四周散射)
VFX.spawnBurst(x, y, count, r, g, b, opts?)
-- opts: { speed, speedVar, life, lifeVar, size, sizeVar, gravity, upward }

-- 分数/标签弹出 (4段动画: 弹性放大→收缩→浮动→飞散)
VFX.spawnPopup(text, x, y, r, g, b, scale?)

-- 全屏过渡 (居中大字，淡入→停留→淡出)
VFX.showTransition(text, r, g, b)

-- 4层文字渲染 (阴影+暗色+主色+高光，用于重要文字)
VFX.drawLayeredText(x, y, text, r, g, b, alpha)

-- 全屏闪光 (快门/驱除)
VFX.flashScreen(r?, g?, b?, duration?, peakAlpha?)
-- 默认: 白色, 0.3s, 峰值透明度 200
-- 快速出现(20%)，缓慢消退(80%)
```

### 渲染顺序 (在 main.lua 的 HandleNanoVGRender 中)

```lua
VFX.drawBurst()       -- 粒子层
VFX.drawPopups()      -- 弹出标签层
VFX.drawBanners()     -- 飘字横幅层
VFX.drawTransition()  -- 全屏过渡层
VFX.drawFlash()       -- 全屏闪光层 (覆盖所有内容，在弹窗之前)
```

---

## 3. Theme.lua — 主题系统

**所有颜色/字号/间距的唯一来源**。禁止硬编码颜色值。

### 使用

```lua
local Theme = require "Theme"
Theme.init("bright")           -- 初始化 (目前只有 bright)
local t = Theme.current        -- 获取当前主题

-- 常用颜色
t.bgTop, t.bgBottom           -- 背景渐变
t.cardFace, t.cardBack         -- 卡牌正反面
t.accent, t.safe, t.danger     -- 功能色
t.textPrimary, t.textSecondary -- 文本色
t.panelBg, t.panelBorder       -- 面板

-- NanoVG 颜色转换
Theme.rgba(color)              -- ThemeColor → nvgRGBA
Theme.rgbaA(color, alpha)      -- 覆盖 alpha
Theme.lerpColor(a, b, t)       -- 颜色插值
Theme.darken(c, factor)        -- 变暗
Theme.lighten(c, factor)       -- 变亮

-- 卡牌类型
Theme.cardTypeInfo("monster")   -- → { icon="👻", label="怪物", colorKey="danger" }
Theme.cardTypeColor("monster")  -- → Theme.current.danger
```

### 字号 (t.fontSize.*)

| key | 值 | 用途 |
|-----|-----|------|
| `title` | 28 | 游戏标题 |
| `subtitle` | 18 | 副标题/日期 |
| `body` | 14 | 正文/状态 |
| `caption` | 11 | 说明/提示 |
| `cardIcon` | 28 | 卡面图标 |
| `cardLabel` | 11 | 卡面标签 |

### 间距 (t.spacing.*)

`xs=4` `sm=8` `md=16` `lg=24` `xl=32`

---

## 4. Card.lua — 卡牌

### 数据

```lua
local card = Card.new("monster", row, col)  -- 创建
-- 属性: type, row, col, faceUp, x, y, scaleX, scaleY, rotation,
--       alpha, bounceY, glowIntensity, isFlipping, isDealing, hoverT, shakeX
```

### 常量

`Card.WIDTH=64` `Card.HEIGHT=90` `Card.RADIUS=8`
`Card.ALL_TYPES = {"safe","landmark","shop","monster","trap","reward","plot","clue"}`

### 动画 API

```lua
Card.flip(card, onComplete)          -- 翻牌 (scaleX 挤压 + bounceY 弹跳 + 光晕)
Card.shake(card)                      -- 拒绝抖动 (阻尼正弦)
Card.dealTo(card, x, y, delay)       -- 发牌飞入
Card.undeal(card, deckX, deckY, delay, onComplete)  -- 收回牌堆
Card.transformTo(card, newType, onComplete)  -- 变形 (收缩+抖动→类型切换→弹出+光晕)
```

### 渲染

```lua
Card.draw(vg, card, gameTime)         -- 自动根据 faceUp 绘制正/反面
Card.hitTest(card, px, py) → bool     -- 点击检测
```

### hover 机制

- `card.hoverT` 由 main.lua 的 `updateHover()` 每帧手动 lerp 驱动
- Card.draw 内部读取 hoverT 产生: 上浮(-4px) + 放大(8%) + 金色边框 + 外发光

---

## 5. Board.lua — 棋盘

```lua
local board = Board.new()
Board.generateCards(board)               -- 随机填充 5x5 卡牌 (中心固定 landmark)
Board.recalcLayout(board, centerX, centerY) -- 布局计算
Board.dealAll(board, onComplete)         -- 螺旋发牌 (自动延迟)
Board.undealAll(board, onComplete)       -- 螺旋收牌
Board.update(board, dt)                  -- 更新发牌计时器
Board.draw(vg, board, gameTime)          -- 渲染全部卡牌 + 牌堆
Board.hitTest(board, px, py) → card, row, col  -- 点击检测
Board.cardPos(board, row, col) → x, y   -- 格子中心坐标
Board.spiralOrder() → {{row,col},...}    -- 螺旋遍历序列
```

常量: `Board.ROWS=5` `Board.COLS=5` `Board.GAP=10`

---

## 6. Token.lua — 玩家棋子

```lua
local token = Token.new()
Token.show(token, x, y)                  -- 出现动画 (从下方弹入)
Token.moveTo(token, targetX, targetY, onComplete)  -- 弧形跳跃移动
Token.update(token, dt)                  -- idle 计时
Token.draw(vg, token, gameTime)          -- 渲染 chibi 棋子
```

常量: `Token.SIZE=20` `Token.BODY_H=14`

移动动画分段: 起跳挤压 → 拉伸 → 弧形移动(easeInOutCubic) → bounceY 抛物线 → 落地挤压 → 弹性恢复

---

## 7. ResourceBar.lua — 资源 HUD

```lua
ResourceBar.init()                -- 初始化 4 种资源
ResourceBar.change("san", -15)    -- 改变值 (触发: 数值滚动 + 闪烁 + 飘字)
ResourceBar.get("film") → number  -- 查询当前值
ResourceBar.reset()               -- 重置到初始值
ResourceBar.update(dt)            -- 更新闪烁计时
ResourceBar.draw(vg, logicalW, logicalH)  -- 渲染底部面板
```

4 种资源: `san`(理智100) `order`(秩序80) `film`(胶卷3) `money`(钱币50)

---

## 8. EventPopup.lua — 事件弹窗

```lua
EventPopup.show(cardType, cx, cy, onDismiss)  -- 弹出 (cx/cy 为逻辑坐标)
EventPopup.dismiss()                           -- 关闭 (触发退场动画，完成后调 onDismiss)
EventPopup.isActive() → bool                   -- 是否激活
EventPopup.handleClick(lx, ly) → bool          -- 处理点击 (按钮/面板外→关闭)
EventPopup.updateHover(lx, ly, dt)             -- 按钮 hover (每帧)
EventPopup.draw(vg, logicalW, logicalH, gameTime) -- 渲染 (遮罩 + 面板 + 内容)
```

弹窗内自带文案模板 (`EventPopup.templates`) 和资源效果映射 (`EventPopup.cardEffects`)。

---

## 9. ShopPopup.lua — 商店弹窗（卡牌式）

shop 卡牌翻开后弹出专用商店界面。三张横排卡牌，点击即买，可花钱刷新。

```lua
ShopPopup.show(cx, cy, onDismiss)      -- 弹出 (随机商铺变体 + 3 张随机商品卡)
ShopPopup.dismiss()                     -- 退场动画 (卡牌向外散射 → 面板缩小)
ShopPopup.isActive() → bool
ShopPopup.handleClick(lx, ly) → bool   -- 点击卡牌购买 / 刷新按钮 / 离开按钮 / 面板外→关闭
ShopPopup.handleKey(key) → bool        -- Enter/Space/Escape → dismiss
ShopPopup.updateHover(lx, ly, dt)      -- 卡牌 hover + 按钮 hover (每帧)
ShopPopup.draw(vg, logicalW, logicalH, gameTime)
```

### 卡牌布局

```
┌─────────────────── 310px ───────────────────┐
│  商铺名称 + 描述                              │
│  ┌──78──┐  14  ┌──78──┐  14  ┌──78──┐       │
│  │ icon │      │ icon │      │ icon │  110h  │
│  │ name │      │ name │      │ name │       │
│  │💰price│      │💰price│      │💰price│       │
│  └──────┘      └──────┘      └──────┘       │
│  [🔄 刷新 💰5]          [离开]               │
└─────────────────────────────────────────────┘
```

常量: `POPUP_W=310` `POPUP_H=246` `CARD_W=78` `CARD_H=110` `CARD_GAP=14` `CARD_COUNT=3` `REFRESH_COST=5`

### 商品目录 (ALL_GOODS, 8 种)

| 图标 | 名称 | 价格 | 效果 |
|------|------|------|------|
| 💊 | 镇定剂 | 15 | 🧠+20 |
| 📜 | 秩序手册 | 12 | ⚖️+15 |
| 🎞️ | 胶卷补充 | 20 | 🎞️+2 |
| 🔋 | 能量饮料 | 8 | 🧠+10 |
| 🗺️ | 城市地图 | 10 | ⚖️+10 |
| 📷 | 一次性相机 | 25 | 🎞️+3 |
| 🧿 | 护身符 | 18 | 🧠+10 ⚖️+10 |
| 🎒 | 补给背包 | 30 | 🧠+15 🎞️+1 |

每次 Fisher-Yates 随机抽取 3 件，刷新时重新抽取。

### 商铺变体 (3 种)

| 名称 | 描述 |
|------|------|
| 黑市商人 | "需要什么？" 戴兜帽的人低声问道。 |
| 旧货铺 | 货架上摆满了来源不明的物品。 |
| 自动售货机 | 孤零零的售货机发出嗡嗡声。 |

### 卡牌状态

| 状态 | 视觉表现 |
|------|----------|
| 可购买 | 正常渲染，hover 时上浮 4px + 放大 4% + 边框发光 + "点击购买" 提示 |
| 已购买 (sold) | 40% 透明度 + 绿色 checkmark + "已购" 标签 |
| 余额不足 | 价格文字变红，点击时卡牌左右摇晃 + 红色 "金币不足!" 提示 |

### 刷新机制

- 花费 5 金币刷新商品，重新随机抽取 3 件
- 所有 sold 状态清除
- 三阶段动画: exit (旧卡旋转飞出) → 生成新商品 → enter (新卡旋转飞入)
- `refreshPhase`: `"idle"` → `"exit"` → `"enter"` → `"idle"`

### 动效设计

| 动效 | 描述 |
|------|------|
| 入场 | 面板 easeOutBack 弹入 + 卡牌交错入场 (微旋转归零) |
| 空闲浮动 | `sin(gameTime*2+idx*1.3)*1.5` 每张卡独立浮动 |
| Hover | 上浮 4px + 缩放 1.04 + 边框 glow + 外发光 |
| 购买脉冲 | 缩放 1→1.15→1 (easeOutBounce) + 绿色闪光 + VFX 粒子爆发 + 弹出文字 |
| 刷新旋出 | 旧卡随机旋转 ±10-20° + easeInBack 飞出 (交错 0.05s) |
| 刷新旋入 | 新卡从 ±4-8° 旋入 + easeOutBack (交错 0.08s) |
| 退场散射 | 左卡 -15°/中卡 0°/右卡 +15° 方向旋出 → 面板缩小 |
| 余额不足摇晃 | 阻尼正弦波左右振荡 |

### 与 EventPopup 的差异

| | EventPopup | ShopPopup |
|---|-----------|-----------|
| 资源结算时机 | dismiss 回调中 | 购买时实时结算 (ResourceBar.change) |
| 面板尺寸 | 固定 280×220px | 固定 310×246px |
| 交互方式 | 1 个确认按钮 | 点击卡牌购买 + 刷新按钮 + 离开按钮 |
| onDismiss 参数 | (cardType, effects) | 无参数 |

### 内部状态

面板: `"enter"` → `"idle"` → `"exit"` → `"done"`
刷新: `refreshPhase = "idle" | "exit" | "enter"`

每张卡牌状态: `{ item, sold, t, rot, hoverT, purchaseFlash, pulseScale, shakeX }`

Tags: `"shoppopup"` `"shoppopup_card"` `"shoppopup_flash"`

---

## 10. CameraButton.lua — 悬浮相机按钮 + 取景器

右下角悬浮按钮，点击进入相机模式，提供取景器叠加层 UI。

```lua
CameraButton.show()                            -- 显示按钮 (淡入 + 弹性缩放)
CameraButton.hide()                            -- 隐藏按钮 (淡出 + 缩小)
CameraButton.enterCameraMode()                 -- 进入相机模式 (取景器入场动画)
CameraButton.exitCameraMode(onComplete)        -- 退出相机模式 (取景器退场，完成后回调)
CameraButton.isActive() → bool                 -- 是否处于相机模式
CameraButton.isVisible() → bool                -- 按钮是否可见
CameraButton.hitTestButton(lx, ly) → bool      -- 按钮点击检测
CameraButton.handleClick(lx, ly) → consumed, reason  -- 处理点击
CameraButton.updateHover(lx, ly, dt)           -- 按钮 hover (每帧)
CameraButton.update(dt)                        -- 更新内部计时器
CameraButton.draw(vg, logicalW, logicalH, gameTime)        -- 渲染按钮
CameraButton.drawOverlay(vg, logicalW, logicalH, gameTime) -- 渲染取景器叠加层
CameraButton.shakeNoFilm()                     -- 胶卷不足抖动
CameraButton.recalcLayout(logicalW, logicalH)  -- 重算按钮位置
```

### 按钮

- 44px 圆形，位于右下角 (`logicalW - 42`, `logicalH - 112`)
- 普通状态: 暖金色 (`Theme.current.cameraBtn`)
- 激活状态: 珊瑚色 (`Theme.current.cameraBtnActive`)
- 图标: 📷

### 取景器叠加层 (相机模式)

| 元素 | 说明 |
|------|------|
| 暗角蒙版 | 四角深色渐变 |
| 角标 | 4 个 L 型白色角括号 |
| 扫描线 | 水平滚动半透明线 |
| REC 指示器 | 红点闪烁 + "REC" 文字 |
| 胶卷计数 | 右下角 "🎞️ x N" |

### 交互逻辑

| 点击位置 | 行为 |
|---------|------|
| 按钮(非相机模式) | 进入相机模式 |
| 按钮(相机模式中) | 退出相机模式 |
| 按钮外(非相机模式) | 不消费，传递给 Board |

### tag 约定

- `"camerabtn"` — 按钮显示/隐藏动画
- `"cameramode"` — 取景器入场/退场动画
- `"camerabtn_shake"` — 胶卷不足抖动

---

## 11. 卡牌类型

| type | 图标 | 色系 | 说明 |
|------|------|------|------|
| `safe` | 🏠 | safe(绿) | 安全屋 |
| `landmark` | ⛪ | highlight(金) | 地标，初始正面朝上 |
| `shop` | 🛒 | info(蓝) | 商店 |
| `monster` | 👻 | danger(红) | 怪物，可驱除 |
| `trap` | ⚡ | warning(黄) | 陷阱 |
| `reward` | 💎 | highlight(金) | 奖励 |
| `plot` | 📖 | plot(紫) | 剧情 |
| `clue` | 🔍 | info(蓝) | 线索 |
| `photo` | 📸 | safe(绿) | 相片(驱除后)，安全格 |

---

## 12. TitleScreen.lua — 标题画面

开场标题/开始画面，氛围感入场动画 + 点击/按键开始。

```lua
TitleScreen.show(onStart)           -- 显示标题画面，onStart 在退场完成后回调
TitleScreen.dismiss()               -- 退场动画 (标题上浮消失 + 遮罩淡出)
TitleScreen.isActive() → bool       -- 是否激活
TitleScreen.handleClick() → bool    -- 处理点击 (idle 阶段→dismiss)
TitleScreen.handleKey(key) → bool   -- Enter/Space → dismiss
TitleScreen.draw(vg, logicalW, logicalH, gameTime)
```

### 入场动画序列

1. 全屏深色遮罩 (1.0 → 0.55, 1.0s)
2. 12 张浮动卡牌装饰 (背景漂移)
3. 标题 "暗面都市" (easeOutBack 弹入 + 光晕)
4. 副标题 "用镜头记录真相 · 用光明驱散恐惧"
5. 呼吸闪烁提示 "点击或按 Enter 开始"

### 内部状态

| phase | 说明 |
|-------|------|
| `"enter"` | 入场动画播放中 |
| `"idle"` | 等待用户操作 |
| `"exit"` | 退场动画，完成后调 onStart |

Tag: `"titlescreen"`

---

## 13. GameOver.lua — 结算画面

游戏结算（胜利/失败），展示统计数据 + 重新开始按钮。

```lua
GameOver.show(isVictory, stats, onRestart)
-- stats: { daysSurvived, cardsRevealed, monstersSlain, photosUsed }
GameOver.dismiss()                          -- 退场，完成后调 onRestart
GameOver.isActive() → bool
GameOver.handleClick(lx, ly, logicalW, logicalH) → bool
GameOver.handleKey(key) → bool              -- Enter/Space → dismiss
GameOver.updateHover(lx, ly, dt, logicalW, logicalH) -- 按钮 hover
GameOver.draw(vg, logicalW, logicalH, gameTime)
```

### 视觉差异

| | 胜利 | 失败 |
|---|------|------|
| 遮罩色 | 深蓝 (15,25,45) | 暗红 (40,10,10) |
| 标题 | "任务完成" (safe绿) | "意识崩溃" (danger红) |
| 副标题 | "你在暗面都市中幸存了下来。" | "黑暗吞噬了你最后的理智..." |
| 按钮色 | safe 绿 | accent 金 |
| 粒子 | ✅ 金色星屑持续飘落 | ✗ 无 |

### 入场动画序列

1. 遮罩淡入 (0→0.7, 0.6s)
2. 标题 easeOutBack 弹入 (0.3s delay)
3. 副标题淡入 (0.6s delay)
4. 4 行统计数据淡入 (0.8s delay): 存活天数 / 翻开卡牌 / 驱除怪物 / 消耗胶卷
5. 按钮 easeOutBack 弹入 (1.1s delay)

### 内部状态

同 TitleScreen: `"enter"` → `"idle"` → `"exit"`

Tag: `"gameover"`

---

## 14. main.lua — 状态机

### 双层状态

```
gamePhase (全局) : "title" ─────→ "playing" ─────→ "gameover" ─→ "title"
                  TitleScreen.show   startDeal    GameOver.show   onGameRestart
```

| gamePhase | 管辖模块 | 说明 |
|-----------|---------|------|
| `"title"` | TitleScreen | 标题画面，等待点击/按键 |
| `"playing"` | Board + 全部游戏逻辑 | 正常游戏阶段 |
| `"gameover"` | GameOver | 结算画面，展示统计 |

`demoState` 仅在 `gamePhase == "playing"` 时有效：

### demoState 流转

```
idle → dealing → ready ↔ flipping → popup → ready
                   ↕
                 moving → flipping → popup → ready
                   ↕
          photographing → flipping → popup(预览) → ready
                   ↕
           exorcising → (变形动画) → ready
                   ↕
                dealing (重发/切天)
```

**相机模式不是独立 demoState**，而是 `ready` 状态上的 UI 修饰层。
通过 `CameraButton.isActive()` 判断当前是否处于相机模式。

| demoState | 允许的操作 |
|------|-----------|
| `idle` | 无 |
| `dealing` | 等待发牌完成 |
| `ready` | 点击卡牌(翻牌/直接移动)、📷相机按钮、Enter切天、Space重发 |
| `ready` + 相机模式 | 点击未翻开卡牌→拍摄、点击怪物→驱除、点击相机按钮/Escape→退出 |
| `flipping` | 等待翻牌动画 |
| `moving` | 等待 Token 移动 |
| `popup` | 弹窗交互，Enter/Space/点击关闭 |
| `photographing` | 快门闪光 → 远程翻牌 → 预览弹窗 |
| `exorcising` | 紫色闪光 → 怪物变形 → 飘字 |

### 胜负条件

| 条件 | 触发时机 | 表现 |
|------|---------|------|
| **败**: `san ≤ 0` 或 `order ≤ 0` | `onPopupDismissed()` 资源结算后 | 0.8s 延迟 → 红色闪光+震动 → GameOver(defeat) |
| **胜**: `dayCount > MAX_DAYS(3)` | `advanceDay()` 天数递增后 | 金色闪光 → GameOver(victory) |

### 游戏重启 (`onGameRestart()`)

1. `Tween.cancelAll()` — 清除所有活跃动画
2. `VFX.resetAll()` — 清除所有特效
3. 重置 `dayCount`, `gamePhase`, `gameStats`
4. `ResourceBar.reset()` — 资源回初始值
5. 重新生成 `Board` + `Token`
6. `startDeal()` — 开始新的发牌

### 渲染层级 (从底到顶)

1. 背景渐变 + 云朵
2. 棋盘 + 卡牌 (Board.draw)
3. Token (Token.draw)
4. CameraButton.drawOverlay (取景器叠加层，仅相机模式)
5. VFX 粒子/弹出/飘字/过渡
6. ResourceBar
7. HUD 文字
8. CameraButton.draw (悬浮按钮)
9. VFX.drawFlash (全屏闪光)
10. EventPopup (遮罩 + 面板)
11. ShopPopup (商店遮罩 + 面板)
12. GameOver (结算遮罩 + 面板)
13. TitleScreen (标题遮罩 + 装饰)

### 输入处理

- **鼠标/触摸**: 物理坐标 → `/ dpr` → 逻辑坐标
  - 优先级链: **TitleScreen** → **GameOver** → **ShopPopup** → **EventPopup** → **CameraButton** → **Board.hitTest**
  - TitleScreen/GameOver 激活时吞掉一切点击
  - ShopPopup/EventPopup 激活时吞掉一切点击 (返回 true)
  - CameraButton 检测按钮点击 (进入/退出相机模式)
  - 相机模式中: `handleCameraModeClick()` — 面朝下→拍摄，怪物→驱除，其他→shake
  - 普通模式: `handleNormalModeClick()` — 当前位置翻牌，其他位置直接移动
- **键盘**:
  - `Enter/Space` = TitleScreen 开始 / GameOver 重新开始 / 关弹窗(popup) / 切天(ready)
  - `Space` = 重发 (ready 状态)
  - `Escape` = 退出相机模式 (相机模式 → ready)

---

## 开发规约

### 动画

1. **所有动画走 Tween.to()**，不要自造 timer+插值
2. **hover 例外**: 用每帧 `lerp(current, target, dt * speed)` 手动驱动，避免 Tween 碎片
3. **tag 必填**: 方便 cancelTag 批量清理
4. **delay 代替 setTimeout**: 用 `Tween.to(dummy, {t=1}, delay, { onComplete=... })` 实现延迟

### 颜色

1. **所有颜色从 Theme.current 取**，不硬编码 RGB
2. **NanoVG 颜色**: 用 `Theme.rgba(c)` 或 `Theme.rgbaA(c, alpha)`
3. **新增功能色**: 加到 Theme.themes.bright 里，不要散落在各模块

### NanoVG 渲染

1. **所有 NanoVG 绘制**必须在 `HandleNanoVGRender` (NanoVGRender 事件) 中
2. **坐标系**: NanoVG Mode B，逻辑坐标 = 物理坐标 / DPR
3. **nvgSave/nvgRestore 必须配对**
4. **字体**: 唯一字体 `"sans"` (MiSans-Regular)，nvgCreateFont 只在 Start() 中调一次

### 新增模块

1. 遵循同样的模块模式: `local M = {} ... return M`
2. 依赖 Tween 做动画，依赖 Theme 取颜色
3. 公开 API 写清楚注释
4. 在 main.lua 中注册 update 和 draw
5. 更新本文档
