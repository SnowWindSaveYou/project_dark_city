# Balatro Card FX — API 参考

## Tween 模块

通用动画引擎，可独立用于任何项目。

### Tween.to(target, toProps, duration, opts) → TweenInstance

创建一个属性动画。

| 参数 | 类型 | 说明 |
|------|------|------|
| `target` | table | 目标对象，其属性会被直接修改 |
| `toProps` | `{[string]: number}` | 目标属性值表 |
| `duration` | number | 持续时间（秒） |
| `opts.easing` | function | 缓动函数，默认 `easeOutCubic` |
| `opts.delay` | number | 延迟启动（秒），默认 0 |
| `opts.onComplete` | function(target) | 完成回调 |
| `opts.onUpdate` | function(target, t) | 每帧回调（t=0~1） |
| `opts.tag` | string | 标签，用于 `cancelTag()` |

### Tween.cancelTarget(target)
取消目标上的所有动画。

### Tween.cancelTag(tag)
取消指定标签的所有动画。

### Tween.cancelAll()
取消所有活跃动画。

### Tween.update(dt)
每帧更新。`CardHand:update()` 内部已调用，通常无需手动调用。

### Tween.damp(current, target, speed, dt) → number
指数衰减平滑逼近，用于持续跟随动画（悬停、相机等）。

### Tween.dampAngle(current, target, speed, dt) → number
角度版 damp，处理 -180/180 跳变。

### Tween.count() → number
当前活跃动画数。

### Tween.isAnimating(target) → boolean
目标是否有活跃动画。

### 缓动函数

| 函数 | 特点 | 典型用途 |
|------|------|---------|
| `Easing.linear` | 匀速 | 进度条 |
| `Easing.easeOutCubic` | 快入慢出（默认） | 通用移动 |
| `Easing.easeOutBack` | 过冲回弹 | 抽牌飞入 |
| `Easing.easeInCubic` | 慢入快出 | 弃牌飞走 |
| `Easing.easeOutElastic` | 弹性振荡 | 得分弹跳 |
| `Easing.easeOutBounce` | 多次弹跳 | 落地效果 |
| `Easing.easeInOutSine` | 正弦平滑 | idle 呼吸 |
| `Easing.easeOutQuad` | 二次减速 | 轻柔移动 |
| `Easing.easeOutQuart` | 四次减速 | 快速减速 |

---

## Card 模块

单张卡牌的数据模型和 NanoVG 渲染。

### 常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `Card.WIDTH` | 90 | 卡牌宽度（逻辑像素） |
| `Card.HEIGHT` | 130 | 卡牌高度 |
| `Card.RADIUS` | 8 | 圆角半径 |

### Card.new(suit, rank, id) → Card

| 参数 | 类型 | 说明 |
|------|------|------|
| `suit` | string | `"spade"` / `"heart"` / `"diamond"` / `"club"` |
| `rank` | string | `"A"` / `"2"` ~ `"10"` / `"J"` / `"Q"` / `"K"` |
| `id` | number? | 唯一标识，默认 0 |

### Card 实例属性

**显示状态**（渲染直读）：

| 属性 | 类型 | 说明 |
|------|------|------|
| `x, y` | number | 当前位置（卡牌中心） |
| `rotation` | number | 旋转角度（度） |
| `scale` | number | 缩放 |
| `opacity` | number | 不透明度 0~255 |

**目标状态**（布局设置，damp 平滑过渡）：

| 属性 | 类型 | 说明 |
|------|------|------|
| `targetX, targetY` | number | 目标位置 |
| `targetRotation` | number | 目标旋转 |
| `targetScale` | number | 目标缩放 |

**交互状态**：

| 属性 | 类型 | 说明 |
|------|------|------|
| `hovered` | boolean | 鼠标悬停中 |
| `selected` | boolean | 已选中 |
| `dragging` | boolean | 拖拽中 |
| `faceUp` | boolean | 正面朝上 |

**视觉效果**：

| 属性 | 类型 | 说明 |
|------|------|------|
| `tiltX` | number | 垂直倾斜（鼠标上下偏移映射，±15） |
| `tiltY` | number | 水平倾斜（鼠标左右偏移映射，±15） |
| `dragTilt` | number | 拖拽惯性倾斜角度（度） |
| `holoEnabled` | boolean | 全息闪卡效果开关 |
| `holoPhase` | number | 全息随机相位（构造时随机） |

### Card.createDeck() → Card[]
创建标准 52 张牌。

### Card.shuffle(deck) → deck
Fisher-Yates 洗牌（原地修改）。

### card:hitTest(px, py) → boolean
点击检测（考虑旋转和缩放）。

### card:draw(vg, time)
NanoVG 渲染单张卡牌（含阴影、正/背面、倾斜光泽、全息效果）。

### Card.drawPile(vg, x, y, count, label)
绘制牌堆（叠放的背面牌 + 计数 + 标签）。

---

## CardHand 模块

手牌管理系统，处理布局、交互、动画。

### CardHand.new(config) → CardHand

`config` 表覆盖默认值：

| 参数 | 默认值 | 说明 |
|------|-------|------|
| `handBottomMargin` | 50 | 手牌区底部边距 |
| `maxSpread` | 500 | 最大横向展开宽度 |
| `cardSpacing` | 70 | 单卡间距（卡多了自动缩小） |
| `curveAmount` | 15 | 边缘卡牌下沉量（抛物线） |
| `maxRotation` | 6 | 边缘最大旋转角度 |
| `hoverLift` | 40 | 悬停抬起高度 |
| `hoverScale` | 1.18 | 悬停缩放倍率 |
| `hoverPushApart` | 25 | 悬停时推开邻牌距离 |
| `hoverSpeed` | 14 | 悬停响应速度（damp speed） |
| `selectLift` | 30 | 选中抬起高度 |
| `drawDuration` | 0.35 | 抽牌动画时长（秒） |
| `drawStagger` | 0.08 | 连抽间隔（秒） |
| `playDuration` | 0.3 | 出牌动画时长 |
| `discardDuration` | 0.25 | 弃牌动画时长 |
| `dragScale` | 1.1 | 拖拽缩放 |
| `inspectScale` | 2.2 | 查阅放大倍率 |
| `inspectDuration` | 0.25 | 查阅动画时长 |
| `maxHandSize` | 8 | 最大手牌数 |

### 数据属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `cards` | Card[] | 当前手牌 |
| `deck` | Card[] | 牌堆（未抽） |
| `discardPile` | Card[] | 弃牌堆 |
| `showCards` | Card[] | 出牌展示区 |
| `animatingCards` | Card[] | 飞行动画中的牌 |
| `animLocked` | boolean | 动画锁定（抽牌/出牌期间禁止交互） |
| `inspecting` | boolean | 查阅模式中 |

### 方法

#### hand:recalcLayout(screenW, screenH)
更新屏幕尺寸，重新计算牌堆/弃牌堆/出牌区位置。**屏幕尺寸变化时必须调用**。

#### hand:update(dt, mouseX, mouseY)
每帧更新。内部调用 `Tween.update(dt)` + 悬停检测 + 倾斜计算 + 平滑过渡。

#### hand:drawCards(count, onAllDone)
从牌堆抽 N 张到手牌，带翻转飞入动画。

#### hand:playSelected(onDone)
将选中的牌飞到出牌区展示（1.5 秒后自动淡出）。`onDone(playedCards)` 回调。

#### hand:discardSelected(onDone)
将选中的牌飞到弃牌堆。`onDone(discardedCards)` 回调。

#### hand:resetDeck()
收回所有牌，洗牌重置。

#### hand:beginInspect(card) / hand:endInspect()
查阅模式：居中放大展示，半透明遮罩，点击任意位置关闭。

#### hand:onMouseDown(x, y, button) → boolean
#### hand:onMouseMove(x, y) → boolean
#### hand:onMouseUp(x, y, button) → boolean
鼠标事件处理。左键选牌/拖拽，右键查阅。返回 true 表示事件已消费。

#### hand:getSelectedCards() → Card[]
#### hand:getSelectedCount() → number

#### hand:draw(vg, time)
绘制完整手牌场景（背景 → 牌堆 → 出牌区 → 动画牌 → 展示牌 → 手牌 → 拖拽指示 → 查阅遮罩）。
