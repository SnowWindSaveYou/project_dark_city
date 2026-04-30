---
name: balatro-card-fx
description: |
  Balatro 风格卡牌动效系统。提供完整的卡牌视觉效果库：扇形手牌布局、悬停 3D 倾斜、拖拽惯性旋转、
  抽牌/出牌/弃牌飞行动画、翻转动画、查阅放大、全息闪卡(Holographic)效果、Tween 动画引擎。
  纯 NanoVG 渲染，不依赖 UI 库，可直接复用到任何 UrhoX 2D 卡牌项目。
  MUST trigger when: (1) 用户要做卡牌游戏且需要 Balatro 风格动效, (2) 用户要求"卡牌动效"或"手牌系统",
  (3) 用户提到 Balatro/小丑牌 的视觉效果, (4) 需要卡牌悬停倾斜/全息/闪卡效果。
---

# Balatro 风格卡牌动效系统

## 概述

三个独立模块，复制到项目 `scripts/` 下即可使用：

| 模块 | 文件 | 职责 |
|------|------|------|
| **Tween** | `Tween.lua` | 通用动画引擎（缓动、damp、链式回调） |
| **Card** | `Card.lua` | 单卡数据 + NanoVG 渲染（正/背面、阴影、倾斜光泽、全息效果） |
| **CardHand** | `CardHand.lua` | 手牌管理（扇形布局、悬停/选中/拖拽/抽牌/出牌/弃牌/查阅） |

## 集成步骤

### Step 1: 复制模块

将 `assets/` 下的三个 Lua 文件复制到项目的 `scripts/<模块目录>/`：

```
scripts/
├── main.lua
└── balatro/          ← 模块目录名可自定义
    ├── Tween.lua
    ├── Card.lua
    └── CardHand.lua
```

### Step 2: 在入口文件中初始化

参考 `assets/example-main.lua` 编写入口，核心流程：

```lua
local Card     = require "balatro.Card"
local CardHand = require "balatro.CardHand"
local Tween    = require "balatro.Tween"

local hand = CardHand.new()
hand:recalcLayout(logicalW, logicalH)
hand.deck = Card.shuffle(Card.createDeck())

-- Update 事件中
hand:update(dt, mouseX, mouseY)

-- NanoVGRender 事件中
hand:draw(vg, gameTime)

-- 鼠标事件转发
hand:onMouseDown(mx, my, button)
hand:onMouseMove(mx, my)
hand:onMouseUp(mx, my, button)
```

### Step 3: 调用动作 API

```lua
hand:drawCards(5, onDone)           -- 抽 5 张
hand:playSelected(onDone)          -- 出选中的牌
hand:discardSelected(onDone)       -- 弃选中的牌
hand:resetDeck()                   -- 洗牌重置
hand:beginInspect(card)            -- 查阅放大
hand:endInspect()                  -- 关闭查阅
card.holoEnabled = true            -- 开启全息闪卡
```

## 效果清单

| 效果 | 实现方式 | 关键参数 |
|------|---------|---------|
| 扇形布局 | 抛物线 Y 偏移 + 线性旋转 | `curveAmount`, `maxRotation`, `cardSpacing` |
| 悬停弹起 | damp 平滑逼近 targetY | `hoverLift`, `hoverScale`, `hoverPushApart` |
| 3D 倾斜 | `nvgSkewX`/`nvgSkewY` 仿射变换 | `tiltFactor = 0.012` |
| 拖拽惯性旋转 | 速度 → 反向倾斜 + 衰减 | `dragTilt = -velX * 0.8` |
| 倾斜光泽 | 径向渐变跟随鼠标偏移 | `drawTiltShine()` |
| 全息闪卡 | 7 色彩虹条纹 + 星尘粒子 + 呼吸透明度 | `drawHoloEffect()` |
| 抽牌飞入 | Tween easeOutBack + 翻转 | `drawDuration`, `drawStagger` |
| 出牌飞出 | Tween easeOutCubic → 展示区 | `playDuration` |
| 弃牌飞出 | Tween easeInCubic → 弃牌堆 | `discardDuration` |
| 翻转动画 | cos 缩放 + 0.5 切换正反面 | `flipProgress` |
| 查阅放大 | Tween 居中 + 半透明遮罩 | `inspectScale`, `inspectDuration` |
| idle 微抖动 | sin 波 Y 偏移 | `wobblePhase` |

## 3D 倾斜数学推导

**NanoVG 坐标系**：X 右, Y 下, 卡牌已 translate 到中心。

**斜切变换**（仿射近似透视）：

| 变换 | 矩阵效果 | 正角度视觉 |
|------|---------|-----------|
| `nvgSkewX(angle)` | `x' = x + tan(angle)*y` | 顶部左移、底部右移 → 卡顶向左倾 |
| `nvgSkewY(angle)` | `y' = tan(angle)*x + y` | 左侧上移、右侧下移 → 左高右低 |

**符号映射**（关键！取反！）：

```
鼠标右侧(tiltY>0) → 卡牌应向右倾 → nvgSkewX(-tiltY * factor)  ← 负号
鼠标上方(tiltX>0) → 卡牌应"仰起"  → nvgSkewY(+tiltX * factor)  ← 正号
```

**代码**：
```lua
nvgScale(vg, sx, sy)
nvgSkewX(vg, -self.tiltY * 0.012)
nvgSkewY(vg,  self.tiltX * 0.012)
```

## 自定义配置

`CardHand.new(config)` 接受配置表覆盖默认值，完整参数见 `references/api.md`。

## 注意事项

1. **NanoVGRender 事件**：所有绘制必须在 `NanoVGRender` 事件回调中
2. **nvgCreateFont 只调用一次**：在 `Start()` 中创建，不要每帧调用
3. **分辨率模式 B**：使用 `logicalW = physW / dpr`, `nvgBeginFrame(vg, logicalW, logicalH, dpr)`
4. **鼠标坐标转换**：`mx = inputX / dpr`, `my = inputY / dpr`
5. **Tween.update(dt)**：由 `CardHand:update()` 内部调用，无需外部重复调用
